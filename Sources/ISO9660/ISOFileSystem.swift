import Foundation

/// A filesystem API to ``ISOImageMedia``. This helps you read/write files and directories from/to an
/// ISO image.
public class ISOFileSystem {
    /// Number of leading logical sectors classified as System Area, as per ECMA-119 6.2.1
    public static let NUM_SYSTEM_SECTORS = 16

    let media: ISOImageMedia
    public private(set) var descriptors: [VolumeDescriptor] = []
    fileprivate var blockSize: UInt16

    /// Return true if primary volume descriptor has SUSP information available
    lazy var primaryHasSUSP: Bool = {
        for descriptor in descriptors {
            if case .primary(let vdd) = descriptor {
                let rootBlock = (try? readBlock(vdd.rootDirectory.extentLocation)) ?? Data()
                var idx = 0
                while idx < rootBlock.count {
                    let len = Int(rootBlock[rootBlock.startIndex + idx])
                    if idx + len > rootBlock.count {
                        break
                    }
                    let dir = DirectoryRecord(from: rootBlock[(0..<len).inc(by: rootBlock.startIndex + idx)])
                    if let systemUse = dir.systemUse {
                        if !SUSPEntry.deserialize(from: systemUse).isEmpty {
                            return true
                        }
                    }
                }
            }
        }
        return false
    }()

    /// Initialize the filesystem with `media`
    /// - Parameter media: The media to use
    public init(_ media: ISOImageMedia) throws {
        self.media = media

        // default block size
        self.blockSize = DEFAULT_BLOCK_SIZE

        // if the media is not blank, we read it
        if !media.isBlank {
            try loadExisting()
        }
    }

    // TODO: implement multiple media support

    /// Load the existing volume descriptors from the media
    private func loadExisting() throws {
        var descriptors: [VolumeDescriptor] = []

        for sectorIdx in Self.NUM_SYSTEM_SECTORS..<media.maximumSectors {
            let data = try media.getSectorData(sectorIdx)
            guard let vd = VolumeDescriptor.from(data) else {
                throw APIError.invalidImage
            }

            if case .terminator = vd {
                break
            } else {
                descriptors.append(vd)
            }
        }

        var blockSize: UInt16 = 0
        for descriptor in descriptors {
            if case .primary(let vdd) = descriptor {
                blockSize = vdd.logicalBlockSize
                break
            }
        }
        if blockSize == 0 || blockSize > media.sectorSize {
            throw SpecError.invalidLogicalBlockSize(size: blockSize)
        }

        self.descriptors = descriptors
        self.blockSize = blockSize
    }

    /// Get the ``VolumeDirectoryDescriptor`` and ``PathTraversal`` options corresponding to `using`.
    ///
    /// If the value of `using` is ``PathResolution/any``, then the preferred descriptor order is:
    /// 1. Primary Volume Descriptor (if SUSP information is available)
    /// 2. Supplementary Volume Descriptor
    /// 3. Enhanced Volume Descriptor
    /// 4. Primary Volume Descriptor (if SUSP information is not available)
    ///
    /// - Parameter using: The path resolution method to use.
    /// - Returns: A tuple containing the ``VolumeDirectoryDescriptor`` and ``PathTraversal`` options
    private func getDirectoryDescriptor(using: PathResolution) throws -> (VolumeDirectoryDescriptor, PathTraversal) {
        switch using {
        case .primary(let pt):
            for vd in descriptors {
                if case let .primary(vdd) = vd {
                    return (vdd, pt)
                }
            }
        case .supplementary(let pt):
            for vd in descriptors {
                if case let .supplementary(vdd) = vd {
                    return (vdd, pt)
                }
            }
        case .enhanced(let pt):
            for vd in descriptors {
                if case let .enhanced(vdd) = vd {
                    return (vdd, pt)
                }
            }
        case .any(let pt):
            var descriptor: VolumeDirectoryDescriptor? = nil
            var pathTraversal: PathTraversal = .useDirectoryRecords
            for vd in descriptors {
                switch vd {
                case let .primary(vdd):
                    if descriptor == nil || primaryHasSUSP {
                        descriptor = vdd
                        pathTraversal = pt
                        if primaryHasSUSP {
                            return (vdd, pathTraversal) // we're done here - highest pref
                        }
                    }
                case let .supplementary(vdd):
                    if (descriptor?.type ?? 0) < 2 {
                        descriptor = vdd
                        pathTraversal = pt
                    }
                case let .enhanced(vdd):
                    if (descriptor?.type ?? 0) < 2 || (descriptor?.version ?? 0) < 2 {
                        descriptor = vdd
                        pathTraversal = pt
                    }
                default:
                    continue
                }
            }
            if let descriptor = descriptor {
                return (descriptor, pathTraversal)
            }
        }

        throw APIError.invalidArgument(name: "using", message: "invalid directory descriptor requested")
    }

    /// Get a handle to ``FSEntry`` corresponding to `path`, `using` the specified path resolution method.
    ///
    /// If the ``PathTraversal`` option in `using` is specified to be ``PathTraversal/useDirectoryRecords``,
    /// then we start from ``VolumeDirectoryDescriptor/rootDirectory`` and traverse the directory records
    /// one by one. Remember that each ``DirectoryRecord`` for a fresh directory is stored in a new block,
    /// so this approach requires reading more number of blocks. However, this approach is more robust, at
    /// least for ISOs meant for unix systems, due to the attachment of SUSP records.
    ///
    /// If the ``PathTraversal`` option in `using` is specified to be ``PathTraversal/usePathTable``, then
    /// we iterate through the entries in the path table to find the relevant ``PathTableRecord``. Note
    /// that in this approach, while it's faster to navigate, we may not be able to find the ``PathTableRecord``
    /// for the final component in the path (if it's not a directory), in which case we use the corresponding
    /// ``DirectoryRecord`` and then go through its entries to lookup the final file. Even when the final
    /// component is a directory, we still need to look up the detailed ``DirectoryRecord`` to find the
    /// SUSP information. That's why this approach is not preferred.
    ///
    /// - Parameter path: The path to file/directory. This must be an absolute path.
    /// - Parameter using: The path resolution method to use. By default, ``PathResolution/any`
    ///             is used, along with ``PathTraversal/useDirectoryRecords``.
    /// - Returns: The ``FSEntry`` corresponding to `path`.
    public func getFSEntry(_ path: String, using: PathResolution = .any(.useDirectoryRecords)) throws -> FSEntry {
        let (vdd, pt) = try getDirectoryDescriptor(using: using)
        let pathComponents = path.pathComponents
        let pathTraversal = pathComponents.isEmpty ? .useDirectoryRecords : pt

        switch pathTraversal {
        case .useDirectoryRecords:
            // we start with root directory
            let rootBlock = try readBlock(vdd.rootDirectory.extentLocation)
            var currentDR = try entryFromDirectoryRecord(rootBlock, using, vdd.encoding, vdd.maxNameLength)
            for component in path.pathComponents {
                // then at each step we look for the record corresponding to the next component
                var found = false
                // TODO: replace with a search function
                for child in try list(directory: currentDR) {
                    if child.name == component {
                        currentDR = child
                        found = true
                        break
                    }
                }
                if !found {
                    throw APIError.invalidArgument(name: "path", message: "invalid path")
                }
            }
            return currentDR
        case .usePathTable:
            let ptLoc = Int.isLittleEndian ? vdd.lPathTableLocation : vdd.mPathTableLocation
            let ptSize = vdd.pathTableSize
            let table = try readExtent(ptLoc, ptSize).consume()

            let encoding = vdd.encoding
            let maxNameLength = vdd.maxNameLength

            var parentDirectoryNumberToLookFor = 1
            var idx = table.startIndex
            var penultimateRecord: PathTableRecord? = nil
            var ptrIdx = 0
            for (componentIdx, componentName) in pathComponents.enumerated() {
                var componentFound = false
                while idx < table.endIndex {
                    guard let ptr = PathTableRecord(from: table[idx...]) else {
                        break
                    }
                    ptrIdx += 1
                    idx += ptr.length
                    let pdn = ptr.parentDirectoryNumber
                    if pdn < parentDirectoryNumberToLookFor {
                        // we keep moving forward if we're still behind the required parent
                        continue
                    } else if pdn == parentDirectoryNumberToLookFor {
                        // we're at the right parent, so we check if the component matches
                        if ptr.getDirectoryIdentifier(encoding: encoding) == componentName {
                            componentFound = true
                            if componentIdx == pathComponents.count - 2 {
                                // we're at the penultimate component, so we save the record
                                penultimateRecord = ptr
                            } else if componentIdx == pathComponents.count - 1 {
                                // we're at the last component, so we return the entry
                                let data = try readBlock(ptr.extentLocation)
                                return try entryFromDirectoryRecord(data, using, encoding, maxNameLength)
                            } else {
                                // we're at an intermediate component, so we update the parent directory number
                                parentDirectoryNumberToLookFor = ptrIdx
                            }
                            break
                        }
                    } else if pdn > parentDirectoryNumberToLookFor {
                        break
                    }
                }
                if !componentFound {
                    // we didn't find the component, but maybe it's a file, and we have its
                    // parent directory record as the penultimate record
                    if let penultimateRecord = penultimateRecord {
                        let data = try readBlock(penultimateRecord.extentLocation)
                        let dir = try entryFromDirectoryRecord(data, using, vdd.encoding, vdd.maxNameLength)
                        // TODO: replace with a search function
                        for child in try list(directory: dir) {
                            if child.name == componentName {
                                return child
                            }
                        }
                    }
                    throw APIError.invalidArgument(name: "path", message: "invalid path")
                }
            }

            throw APIError.invalidArgument(name: "path", message: "invalid path")
        }
    }

    /// Get the children of the specified directory
    /// - Parameter directory: The directory to get children of
    /// - Returns: The children of the directory
    public func list(directory: FSEntry) throws -> [FSEntry] {
        guard directory.isDirectory else {
            throw APIError.invalidArgument(name: "directory", message: "not a directory")
        }
        let using = directory.metadata?.pathResolution ?? .any(.useDirectoryRecords)
        let (vdd, _) = try getDirectoryDescriptor(using: using)
        let encoding = vdd.encoding
        let maxNameLength = vdd.maxNameLength

        // we always read children via directory records, as it might contain files
        if let directoryRecord = directory.metadata?.directoryRecord {
            if !directoryRecord.isLastExtent {
                // TODO: implement multi-extent directories
                fatalError("multi-extent directories not yet implemented")
            }
            let extentIS = try readExtent(directoryRecord.extentLocation, directoryRecord.dataLength)
            let extent = try extentIS.consume(Int(directoryRecord.dataLength))
            var idx = extent.startIndex
            var children: [FSEntry] = []
            while idx < extent.endIndex {
                let len = Int(extent[idx])
                if len == 0 || len > extent.endIndex - idx {
                    break
                }
                let fsEntry = try entryFromDirectoryRecord(extent[(0..<len).inc(by: idx)], using, encoding, maxNameLength)
                children.append(fsEntry)
                idx += len
            }
            return children
        } else {
            throw APIError.invalidArgument(name: "directory", message: "not a valid directory")
        }
    }

    /// Reads a ``DirectoryRecord`` `at` the specified location, and returns the ``FSEntry`` corresponding to it.
    /// - Parameter at: The location to read the directory record from
    /// - Parameter using: The path resolution to use for the directory record.
    /// - Parameter encoding: The encoding to use for the directory record.
    /// - Parameter maxNameLength: The maximum length of a name in the directory record.
    /// - Returns: The ``FSEntry`` corresponding to the directory record.
    private func entryFromDirectoryRecord(_ at: Data, _ using: PathResolution, _ encoding: String.Encoding, _ maxNameLength: UInt8) throws -> FSEntry {
        let dr = DirectoryRecord(from: at)
        let fsEntry: FSEntry
        if var susp = SUSPArea(continuation: dr.systemUse) {
            while let (block, offset, length) = susp.continuesAt {
                let data = (try readBlock(block))[(0..<Int(length)).inc(by: Int(offset))]
                if !susp.add(continuation: data) {
                    break
                }
            }
            fsEntry = FSEntry(from: dr, encoding: encoding, susp: susp, pathResolution: using)
        } else {
            fsEntry = FSEntry(from: dr, encoding: encoding, pathResolution: using)
        }
        return fsEntry
    }

    /// Open a file for reading. The contents have to be read via the returned `InputStream`.
    /// - Parameter file: The file to read
    /// - Returns: An input stream to read the file contents from
    public func readFile(_ file: FSEntry) throws -> InputStream {
        guard case .file = file else {
            throw APIError.invalidArgument(name: "file", message: "not a file")
        }

        if let directoryRecord = file.metadata?.directoryRecord {
            if !directoryRecord.isLastExtent {
                // TODO: implement multi-extent files
                fatalError("multi-extent files not yet implemented")
            }
            // TODO: account for additional extents
            let extent = try readExtent(directoryRecord.extentLocation, directoryRecord.dataLength)
            // TODO: account for extended attributes
            // directoryRecord.extendedAttributeRecordLength
            // TODO: handle interleaving
            return extent
        } else {
            throw APIError.invalidArgument(name: "directory", message: "not a valid directory")
        }
    }

    /// Reads the `file`'s contents in one shot and returns the data. Note that this will
    /// load the entire file into memory, and thus should be done only for small files.
    /// - Parameter file: The file to read
    /// - Returns: The file's contents
    public func readFileContents(_ file: FSEntry) throws -> Data {
        guard case .file = file else {
            throw APIError.invalidArgument(name: "file", message: "not a valid file")
        }
        let stream = try readFile(file)
        defer {
            stream.close()
        }
        let bufferSize = 2048
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer {
            buffer.deallocate()
        }

        var data = Data(capacity: Int(file.metadata?.length ?? 0))
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if let err = stream.streamError {
                throw err
            } else if read > 0 {
                data.append(buffer, count: read)
            } else {
                break
            }
        }
        return data
    }

    /// Reads the content of the specified extent
    /// - Parameter startBlock: The logical block number of the beginning of this extent
    /// - Parameter length: The length of the extent in bytes
    /// - Returns: The extent data
    public func readExtent(_ startBlock: UInt32, _ length: UInt32) throws -> InputStream {
        return ExtentInputStream(fs: self, startBlock: startBlock, extentLength: length)
    }

    /// Reads the content of the specified logical block
    /// - Parameter block: The logical block number
    /// - Returns: The block data
    public func readBlock(_ block: UInt32) throws -> Data {
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(blockSize))
        defer {
            buffer.deallocate()
        }
        try readBlock(block, into: buffer)
        return Data(bytes: buffer, count: Int(blockSize))
    }

    /// Reads the content of the specified logical block into the provided buffer
    /// - Parameter block: The logical block number
    /// - Parameter buffer: The buffer to read the block data into
    public func readBlock(_ block: UInt32, into buffer: UnsafeMutablePointer<UInt8>) throws {
        let bs = Int(blockSize)
        let blocksPerSector = Int(media.sectorSize) / bs
        let sectorIdx = Int(block) / blocksPerSector
        let sectorData = try media.getSectorData(sectorIdx)
        let offset = (Int(block) % blocksPerSector) * bs
        sectorData.copyBytes(to: buffer, from: offset..<offset+bs)
    }

    /// Which method to use to navigate the path to a ``DirectoryRecord`` corresponding to a ``FSEntry``. By
    /// default, we use the ``useDirectoryRecords`` method, but appropriate filesystem calls can be made to
    /// use ``usePathTable`` instead.
    ///
    /// While ``DirectoryRecord``s are the ultimate source of truth for every file/directory entry in the
    /// filesystem, the way a full path tree is navigated to reach this record can be of two kinds:
    /// 1. By jumping from one ``DirectoryRecord`` to the next, for each component of the path tree, until
    ///    the final record is reached. This is what ``useDirectoryRecords`` does, and is the default.
    /// 2. By using the path table, which is a linear array of ``PathTableRecord``s, each of which contains
    ///    the location of the ``DirectoryRecord`` corresponding to that name. While theoretically faster,
    ///    this has caveats, and so is not the default. See ``usePathTable`` for more details.
    public enum PathTraversal {
        /// Starting from ``VolumeDirectoryDescriptor/rootDirectory``, we jump from one ``DirectoryRecord``
        /// to the next, for each component of the path tree, until the final record is reached. This is the
        /// default traversal method for this library.
        case useDirectoryRecords

        /// Uses the path table as specified in ``VolumeDirectoryDescriptor/lPathTableLocation`` to locate
        /// the ``DirectoryRecord`` for a path tree.
        ///
        /// While theoretically faster, this is meaningful only where the proper name is encoded in the
        /// path table (e.g. in Supplementary/Enhanced Volume Descriptors). In the Primary vol descriptor,
        /// this would usually fail, unless the names in the path use the 8.3 name format.
        case usePathTable
    }

    /// Which tuple of (``VolumeDescriptor``, ``PathTraversal``) to use to reach the ``DirectoryRecord``
    /// corresponding to a path.
    public enum PathResolution {
        /// Use the Primary Volume Descriptor and the specified ``PathTraversal`` method.
        case primary(PathTraversal)
        /// Use the Supplementary Volume Descriptor and the specified ``PathTraversal`` method.
        case supplementary(PathTraversal)
        /// Use the Enhanced Volume Descriptor and the specified ``PathTraversal`` method.
        case enhanced(PathTraversal)
        /// Use whichever comes first in this order: `primary (if has SUSP)` > `supplementary` >
        /// `enhanced` > `primary (without SUSP)`
        case any(PathTraversal)
    }
}

/// A file system entry
public enum FSEntry {
    /// A file
    case file(name: String, size: UInt64, metadata: Metadata? = nil)
    /// Current directory
    case currentDirectory(metadata: Metadata? = nil)
    /// Parent directory
    case parentDirectory(metadata: Metadata? = nil)
    /// A named directory
    case directory(name: String, metadata: Metadata? = nil)
    /// A symbolic link
    case symlink(name: String, target: String, metadata: Metadata? = nil)

    /// The name of this entry, as inferred by first checking the alternate
    /// name (NM), and then the name as mentioned in the volume descriptor.
    /// Also see `nameInVolDescriptor`.
    public var name: String {
        return metadata?.alternateName ?? nameInVolDescriptor
    }

    /// The name of this entry as mentioned in the volume descriptor.
    public var nameInVolDescriptor: String {
        switch self {
        case .file(let name, _, _):
            return name
        case .currentDirectory:
            return "."
        case .parentDirectory:
            return ".."
        case .directory(let name, _):
            return name
        case .symlink(let name, _, _):
            return name
        }
    }

    /// True if this entry is a directory
    public var isDirectory: Bool {
        switch self {
        case .directory, .currentDirectory, .parentDirectory:
            return true
        default:
            return false
        }
    }

    /// Metadata for this entry
    public var metadata: Metadata? {
        switch self {
        case .file(_, _, let metadata):
            return metadata
        case .currentDirectory(let metadata):
            return metadata
        case .parentDirectory(let metadata):
            return metadata
        case .directory(_, let metadata):
            return metadata
        case .symlink(_, _, let metadata):
            return metadata
        }
    }

    /// Is this entry marked as hidden
    public var isHidden: Bool {
        if let dr = metadata?.directoryRecord {
            return dr.flags & DirectoryRecord.FLAG_IS_HIDDEN != 0
        } else {
            return false
        }
    }

    /// Initialize a file system entry from a directory record
    /// - Parameter from: The directory record to initialize from
    /// - Parameter encoding: The encoding to use for the name
    /// - Parameter susp: The SUSP area for this entry, if available
    /// - Parameter pathResolution: The method used to reach this entry's directory record
    fileprivate init(from: DirectoryRecord, encoding: String.Encoding, susp: SUSPArea? = nil, pathResolution: ISOFileSystem.PathResolution = .any(.useDirectoryRecords)) {
        var metadata = Metadata(directoryRecord: from, pathResolution: pathResolution)
        metadata.length = UInt64(from.dataLength)

        var symlinkTarget: String? = nil
        if let susp = susp {
            for suspEntry in susp.entries {
                switch suspEntry {
                case .rrip(.PX(let fileMode, let links, let uid, let gid, _)):
                    metadata.mode = Int(fileMode)
                    metadata.links = Int(links)
                    metadata.uid = Int(uid)
                    metadata.gid = Int(gid)
                case .rrip(.SL(_, _)):
                    if let sl = SUSPEntry.RockRidge.Symlink(suspEntry) {
                        symlinkTarget = sl.components.path
                    }
                case .rrip(.NM(_, _)):
                    if let nm = SUSPEntry.RockRidge.AlternateName(suspEntry) {
                        metadata.alternateName = String(bytes: nm.data, encoding: .utf8)
                    }
                case .rrip(.TF(let createdAt, let modifiedAt, _, _, _, _, _, _)):
                    metadata.creationDate = createdAt
                    metadata.modificationDate = modifiedAt
                default:
                    continue
                }
            }
        }

        // assign identities appropriately
        switch from.getIdentifier(encoding: encoding) {
        case .dot:
            self = .currentDirectory(metadata: metadata)
        case .dotdot:
            self = .parentDirectory(metadata: metadata)
        case .file(let name):
            if let target = symlinkTarget {
                self = .symlink(name: name, target: target, metadata: metadata)
            } else {
                self = .file(name: name, size: UInt64(from.dataLength), metadata: metadata)
            }
        case .directory(let name):
            self = .directory(name: name, metadata: metadata)
        default:
            fatalError("unsupported directory record type")
        }
    }

    /// Metadata for a file system entry. This includes POSIX information, along with some hidden information
    /// about the location of the entry.
    public struct Metadata {
        /// Length of the data in bytes
        public fileprivate(set) var length: UInt64? = nil

        /// POSIX alternate name
        public var alternateName: String? = nil
        /// POSIX file mode
        public var mode: Int? = nil
        /// POSIX number of links to this
        public var links: Int = 1
        /// POSIX user ID
        public var uid: Int? = nil
        /// POSIX group ID
        public var gid: Int? = nil
        /// POSIX file creation time
        public var creationDate: Date? = nil
        /// POSIX file modification time
        public var modificationDate: Date? = nil

        // Hidden information
        internal var directoryRecord: DirectoryRecord
        fileprivate let pathResolution: ISOFileSystem.PathResolution

        fileprivate init(directoryRecord: DirectoryRecord, pathResolution: ISOFileSystem.PathResolution) {
            self.directoryRecord = directoryRecord
            self.pathResolution = pathResolution
        }

        public init() {
            let data = Data(count: 34)
            directoryRecord = DirectoryRecord(from: data)
            pathResolution = .any(.useDirectoryRecords)
        }
    }
}

private extension VolumeDirectoryDescriptor {
    var maxNameLength: UInt8 {
        return type <= 1 ? 8 : 207
    }
}

private extension VolumeDescriptor {
    var encoding: String.Encoding {
        switch self {
        case .primary(let desc), .supplementary(let desc), .enhanced(let desc):
            return desc.encoding
        default:
            return .ascii
        }
    }

    var maxNameLength: UInt8 {
        switch self {
        case .primary(let desc), .supplementary(let desc), .enhanced(let desc):
            return desc.maxNameLength
        default:
            return 8
        }
    }
}

private extension SUSPEntry.RockRidge.NamedComponent {
    var name: String {
        #if os(Windows)
        let pathSep = "\\"
        #else
        let pathSep = "/"
        #endif
        switch self {
            case .currentDirectory:
                return "."
            case .parentDirectory:
                return ".."
            case .rootDirectory:
                return pathSep
            case .volumeRoot:
                return pathSep
            case .host:
                let currentHost = Host.current().name ?? "<host>"
                return "\\\\\(currentHost)"
            case .named(let data):
                return String(bytes: data, encoding: .utf8) ?? "<invalid>"
        }
    }
}

private extension Array where Element == SUSPEntry.RockRidge.NamedComponent {
    var path: String {
        return NSString.path(withComponents: self.map { $0.name })
    }
}

/// Stream wrapper to consume extent bytes in a memory bound way.
class ExtentInputStream: InputStream {
    private let fs: ISOFileSystem
    private let startingBlock: Int
    private let extentLength: Int
    private let blockSize: Int
    private var currentBlock: Int = 0
    private var currentOffset: Int = 0
    private var buffer: UnsafeMutablePointer<UInt8>
    private var lastError: Error? = nil

    init(fs: ISOFileSystem, startBlock: UInt32, extentLength: UInt32) {
        self.fs = fs
        self.startingBlock = Int(startBlock)
        self.extentLength = Int(extentLength)
        self.blockSize = Int(fs.blockSize)
        self.currentBlock = Int(startBlock)
        self.currentOffset = 0
        self.buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: blockSize)
        super.init()
    }

    deinit {
        buffer.deallocate()
    }

    override func open() {
    }

    override func close() {
        self.currentBlock = startingBlock + (extentLength / blockSize) + 1
    }

    override func read(_ userBuffer: UnsafeMutablePointer<UInt8>, maxLength len: Int) -> Int {
        do {
            if !hasBytesAvailable {
                return 0
            }

            var copyFromBuffer = true
            let bytesToCopy = min(len, blockSize - currentOffset, remainingBytes)
            if currentOffset == 0 {
                // read the next block, if we don't have data pending in the current buffer
                if bytesToCopy == blockSize {
                    // we can read directly into the user buffer
                    try fs.readBlock(UInt32(currentBlock), into: userBuffer)
                    copyFromBuffer = false
                } else {
                    // we need to preserve the block data for the next read
                    try fs.readBlock(UInt32(currentBlock), into: buffer)
                }
            }

            if copyFromBuffer {
                // we have data pending in the current buffer, so we copy that
                let _ = self.buffer.withMemoryRebound(to: UInt8.self, capacity: blockSize) { (ptr: UnsafeMutablePointer<UInt8>) in
                    // copy the data to the user buffer
                    memcpy(userBuffer, ptr.advanced(by: currentOffset), bytesToCopy)
                }
            }

            currentOffset = currentOffset + bytesToCopy
            assert(currentOffset <= blockSize, "incorrect offset state for extent input stream")

            if currentOffset == blockSize {
                // roll over to the next block
                currentBlock += 1
                currentOffset = 0
            }
            return bytesToCopy
        } catch {
            self.lastError = error
            return -1
        }
    }

    override func getBuffer(_ buffer: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>, length len: UnsafeMutablePointer<Int>) -> Bool {
        return false
    }

    var remainingBytes: Int {
        let byteOffset = (currentBlock - startingBlock) * blockSize + currentOffset
        return extentLength - byteOffset
    }

    override var hasBytesAvailable: Bool {
        return remainingBytes > 0
    }

    override var streamError: Error? {
        return lastError
    }
}

private extension InputStream {
    /// Consume this stream and return the full content as a Data object.
    func consume(_ length: Int? = nil) throws -> Data {
        let chunkSize = 1024
        var data = length != nil ? Data(capacity: length!) : Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
        defer {
            buffer.deallocate()
        }
        while hasBytesAvailable {
            let bytesRead = read(buffer, maxLength: chunkSize)
            if let err = streamError {
                throw err
            } else if bytesRead > 0 {
                data.append(buffer, count: bytesRead)
            } else {
                break
            }
        }
        return data
    }
}
