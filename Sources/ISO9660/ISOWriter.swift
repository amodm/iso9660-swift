import Foundation

/// Writer interface for ISO images. This is kept separate from ``ISOFileSystem`` because
/// ISO9660 structure is optimised for write-once read-many scenarios. This class is not
/// thread-safe.
public class ISOWriter {
    private let recordDate = Date()
    var media: ISOImageMedia
    @usableFromInline internal let options: WriteOptions

    /// Descriptors to include in the ISO image.
    public var descriptors: [VolumeDescriptor]

    /// The in-memory scratch pad we use, where each entry is a logical block.
    private var blocks: [Data?]
    /// Locations of files
    private var fileLocations: [String: (Int, UInt64)] = [:]
    private var nextFileLBA = 0
    private var numFileBlocks = 0

    /// The root node of the ISO filesystem.
    private var root = TreeNode(entry: FSEntry.directory(name: ""))

    /// Is this writer open for writing?
    private var isOpen: Bool = true

    /// Callback to get the contents of a file.
    private let contentCallback: (String) -> InputStream

    /// Add a directory to the ISO image.
    ///
    /// - Parameters:
    ///   - path: The absolute path of the directory in the ISO filesystem.
    ///   - metadata: Metadata information like mode/uid/gid etc.
    public func addDirectory(path: String, metadata: FSEntry.Metadata? = nil) throws {
        try addHelper(path) { parent, name, existing in
            if let existing = existing {
                if !existing.entry.isDirectory {
                    throw APIError.invalidArgument(name: "path", message: "a component of the path is not a directory")
                }
                existing.metadata = metadata
            } else {
                parent.children.append(TreeNode(entry: FSEntry.directory(name: name, metadata: metadata)))
            }
        }
    }

    /// Add a file to the ISO image.
    ///
    /// - Parameters:
    ///   - path: The absolute path of the file in the ISO filesystem.
    ///   - size: The size of the file in bytes.
    ///   - metadata: Metadata information like mode/uid/gid etc.
    public func addFile(path: String, size: UInt64, metadata: FSEntry.Metadata? = nil) throws {
        try addHelper(path) { parent, name, existing in
            if let existing = existing {
                if existing.entry.isDirectory {
                    throw APIError.invalidArgument(name: "path", message: "trying to replace a directory with a file")
                }
                existing.metadata = metadata
            } else {
                parent.children.append(TreeNode(entry: FSEntry.file(name: name, size: size, metadata: metadata)))
            }
        }
    }

    /// Add a symlink to the ISO image.
    ///
    /// - Parameters:
    ///   - path: The absolute path of the file in the ISO filesystem.
    ///   - target: The target of the symlink.
    ///   - metadata: Metadata information like mode/uid/gid etc.
    public func addSymlink(path: String, target: String, metadata: FSEntry.Metadata? = nil) throws {
        try addHelper(path) { parent, name, existing in
            if let existing = existing {
                if existing.entry.isDirectory {
                    throw APIError.invalidArgument(name: "path", message: "trying to replace a directory with a file")
                }
                existing.metadata = metadata
            } else {
                parent.children.append(TreeNode(entry: FSEntry.symlink(name: name, target: target, metadata: metadata)))
            }
        }
    }

    /// Helper function to add nodes to directory tree.
    ///
    /// - Parameter path: The absolute path of the file/directory in the ISO filesystem.
    /// - Parameter createOrUpdateNode: A callback that should modify an existing node, or add a new one to the parent.
    private func addHelper(_ path: String, _ createOrUpdateNode: (_ parent: TreeNode, _ name: String, _ existing: TreeNode?) throws -> Void) throws {
        if !isOpen {
            throw APIError.writerClosed
        }
        var parentComponents = path.pathComponents
        let name = parentComponents.removeLast()
        var dir = self.root
        for component in parentComponents {
            if component == "." || component == ".." {
                throw APIError.invalidArgument(name: "path", message: "directories with a path component of '.' or '..' are not allowed")
            }
            if !dir.entry.isDirectory {
                throw APIError.invalidArgument(name: "path", message: "a component of the path is not a directory")
            }
            if let existing = dir.children.first(where: { $0.entry.name == component }) {
                dir = existing
            } else {
                let newNode = TreeNode(entry: FSEntry.directory(name: component, metadata: nil))
                dir.children.append(newNode)
                dir = newNode
            }
        }
        let existing = dir.children.first(where: { $0.entry.name == name })
        try createOrUpdateNode(dir, name, existing)
    }

    /// Writes to the ISO image, and closes this writer for further writing.
    public func writeAndClose() throws {
        if !isOpen {
            throw APIError.writerClosed
        }
        let logicalSectorSize = 2048
        media.sectorSize = logicalSectorSize

        // write descriptors
        for desc in descriptors {
            try writeDescriptor(desc)
        }

        // flush blocks
        let blockWriter = BlockSectorWriter(blockSize: options.blockSize, media: media)
        for (blockId, block) in blocks.enumerated() {
            if let block = block {
                try blockWriter.withBlockBuffer(blockId) { buffer in
                    buffer.replaceSubrange((0..<block.count).inc(by: buffer.startIndex), with: block)
                }
            }
        }

        // write files
        for (path, (blockId, fileSize)) in fileLocations.sorted(by: { $0.1.0 < $1.1.0 }) {
            let stream = contentCallback(path)
            stream.open()
            var blockId = blockId
            var numBytesRemaining = fileSize
            // we use numBytesRemaining instead of stream.hasBytesAvailable because the latter will return true
            // unless the another read call is done (post-eof), and that ends up incorrectly marking the buffer
            // in `withBlockBuffer` as dirty
            while numBytesRemaining > 0 {
                // in each loop, we try to read one block worth of data
                let toBeRead = min(options.blockSize, Int(numBytesRemaining))
                let numRead = try blockWriter.withBlockBuffer(blockId) { buffer in
                    return try stream.readInto(&buffer, toBeRead)
                }
                if numRead == 0 {
                    break
                } else {
                    blockId += (numRead + options.blockSize - 1) / options.blockSize
                    numBytesRemaining -= UInt64(numRead)
                }
            }
            if numBytesRemaining > 0 {
                throw SpecError.preconditionFailed(
                    reason: "contents of file \(path) (\(fileSize-numBytesRemaining) bytes) are shorter than expected (\(fileSize) bytes)"
                )
            }
        }

        // flush any pending blocks
        try blockWriter.flush()

        try media.sync()
        isOpen = false
    }

    /// Creates the directory record corresponding to `node` and returns its LBA (or nil if not added)
    private func createDirectoryRecord(
        _ node: TreeNode,
        _ parentLBA: Int,
        _ parentLen: UInt32,
        minLBA: Int,
        susp: Bool,
        volPath: String,
        pathTable: inout [PathTableRecord],
        parentDirectoryNumber: Int,
        nameContext: (FSEntry, [String]) -> (idBytes: Data, altName: String?, encoding: String.Encoding)
    ) -> (lba: Int, extentLen: Int) {
        if case .directory = node.entry {
            // sort children
            let children = node.children.sorted { $0.entry.name < $1.entry.name }
                // skip the symlinks if we're not including SUSP
                .filter { if case .symlink = $0.entry { return susp } else { return true } }

            // . and .. directories
            var currentDir = DirectoryRecord(Data([0]), isDir: true, altName: nil)
            updateDirRecordMeta(&currentDir, node.entry, susp: susp)
            var parentDir = DirectoryRecord(Data([1]), isDir: true, altName: nil)
            updateDirRecordMeta(&parentDir, node.entry, susp: susp)

            // initialize the list of dir entries with the standard directory records
            var dirEntries = [currentDir, parentDir]

            // we add all the children to the list of directory records, though remember that
            // none of these records is fully defined yet (we don't know their LBA or extent length)
            var existingNames = [String]()
            for child in children {
                let (idBytes, altName, encoding) = nameContext(child.entry, existingNames)
                existingNames.append(String(data: idBytes, encoding: encoding)!)
                var rec = DirectoryRecord(idBytes, isDir: child.entry.isDirectory, altName: altName)
                updateDirRecordMeta(&rec, child.entry, susp: susp)
                dirEntries.append(rec)
            }
            // at this point we can calculate the extent length of this directory

            // calculate the extent length
            var thisLen: UInt32 = 0
            for de in dirEntries {
                thisLen += UInt32(de.length)
            }
            dirEntries[0].dataLength = thisLen

            // LBA calculations
            let thisNumBlocks = numBlocksNeededFor(Int(thisLen))
            let thisLBA = nextAvailBlock(minLBA, thisNumBlocks)

            // write the directory records for children
            var nextChildLBA = thisLBA + thisNumBlocks
            for (idx, child) in children.enumerated() {
                let childLBA: Int, childLen: Int
                let fullPath = "\(volPath)/\(child.entry.name)"
                if child.entry.isDirectory {
                    let (idBytes, _, _) = nameContext(child.entry, [])
                    let ptr = PathTableRecord(idBytes)
                    pathTable.append(ptr)
                    let ptrIdx = pathTable.count - 1
                    // we recurse when we're dealing with a directory
                    (childLBA, childLen) = createDirectoryRecord(
                        child,
                        thisLBA,
                        thisLen,
                        minLBA: nextChildLBA,
                        susp: susp,
                        volPath: fullPath,
                        pathTable: &pathTable,
                        parentDirectoryNumber: ptrIdx + 1,
                        nameContext: nameContext
                    )
                    pathTable[ptrIdx].extentLocation = UInt32(childLBA)
                    pathTable[ptrIdx].parentDirectoryNumber = UInt16(parentDirectoryNumber)
                } else if case .file(_, let size, _) = child.entry {
                    // we use the file loc register when dealing with files
                    childLen = Int(size)
                    if let (existingLoc, existingSize) = fileLocations[fullPath] {
                        childLBA = existingLoc
                        assert(size == existingSize, "file size mismatch for \(fullPath)")
                    } else {
                        let childBlocks = numBlocksNeededFor(childLen)
                        childLBA = max(nextFileLBA, blocks.count)
                        fileLocations[fullPath] = (childLBA, size)
                        nextFileLBA = childLBA + childBlocks
                        numFileBlocks += childBlocks
                    }
                } else {
                    fatalError("should not have reached here")
                }
                nextChildLBA += numBlocksNeededFor(childLen)
                dirEntries[idx + 2].extentLocation = UInt32(childLBA)
                dirEntries[idx + 2].dataLength = UInt32(childLen)
            }

            // update current and parent directory records
            dirEntries[0].extentLocation = UInt32(thisLBA)
            dirEntries[0].dataLength = thisLen
            dirEntries[1].extentLocation = UInt32(parentLBA == 0 ? thisLBA : parentLBA)
            dirEntries[1].dataLength = UInt32(parentLBA == 0 ? thisLen : parentLen)

            // create and write this directory's extent
            var dirExtent = Data(capacity: Int(thisLen))
            for de in dirEntries {
                dirExtent.append(de.serialize())
            }

            // write this record
            _ = writeToBlockCache(dirExtent, at: thisLBA)
            return (lba: thisLBA, extentLen: Int(thisLen))
        } else {
            fatalError("should not have reached here")
        }
    }

    /// Adds SUSP entries to the directory record
    private func updateDirRecordMeta(_ rec: inout DirectoryRecord, _ entry: FSEntry, susp: Bool) {
        rec.volumeSequenceNumber = 1
        rec.recordDate = recordDate
        if susp {
            let metadata = entry.metadata
            let mode = UInt32(metadata?.mode ?? (rec.isDirectory ? 0o755 : 0o644))
            let links = UInt32(1)
            let uid = UInt32(metadata?.uid ?? 0)
            let gid = UInt32(metadata?.gid ?? 0)

            var entries = [SUSPEntry.rrip(.PX(fileMode: mode, links: links, uid: uid, gid: gid))]
            if let altName = metadata?.alternateName {
                entries.append(SUSPEntry.rrip(.NM(flags: 0, name: altName.data(using: .utf8)!)))
            }
            if case .symlink(let name, let target, _) = entry {
                entries.append(SUSPEntry.RockRidge.Symlink.newSL(name: name, target: target))
            }
            entries.append(SUSPEntry.rrip(.TF(createdAt: metadata?.creationDate ?? recordDate, modifiedAt: metadata?.modificationDate ?? recordDate, longForm: false)))

            let suspBytes = entries.map { $0.serialize() }.reduce(Data(), +)

            rec.systemUse = suspBytes
            // TODO: deal with the case where the SUSP entries don't fit in the first record
            assert(rec.length < 255, "long SUSP entries not yet supported in writes")
        }
    }

    lazy var minLBAForDescriptors: Int = {
        ISOFileSystem.NUM_SYSTEM_SECTORS * media.sectorSize / options.blockSize
    }()

    lazy var minLBAForDirectoryRecords: Int = {
        minLBAForDescriptors + 16 * media.sectorSize / options.blockSize
    }()

    /// Write `descriptor` to the ISO image at the next available LBA
    private func writeDescriptor(_ descriptor: VolumeDescriptor) throws {
        let lba = nextAvailBlock(minLBAForDescriptors, numBlocksNeededFor(2048))
        switch descriptor {
        case .primary(let vdd):
            try writeDirectoryDescriptor(vdd, at: lba, susp: options.enableSUSP) { (entry: FSEntry, existingNames: [String]) in
                let name = entry.name
                let encoding = String.Encoding.ascii
                let maxNameLength: UInt8 = 12
                let idBytes = getLegacyFilename(name, existingNames, Int(maxNameLength)).data(using: encoding)!
                return (idBytes: idBytes, altName: name, encoding: encoding)
            }
        case .supplementary(let vdd), .enhanced(let vdd):
            try writeDirectoryDescriptor(vdd, at: lba, susp: false) { (entry: FSEntry, _) in
                let name = entry.name
                let encoding = vdd.encoding
                let maxNameLength: UInt8 = 207
                let idBytes = name.serializeClipped(encoding, Int(maxNameLength))
                return (idBytes: idBytes, altName: name, encoding: encoding)
            }
        default:
            _ = writeToBlockCache(descriptor.serialize(), at: lba)
        }
    }

    /// Write `descriptor` to the block cache at the next available LBA
    private func writeDirectoryDescriptor(
        _ descriptor: VolumeDirectoryDescriptor,
        at lba: Int,
        susp: Bool,
        nameContext: (FSEntry, [String]) -> (idBytes: Data, altName: String?, encoding: String.Encoding)
    ) throws {
        var descriptor = descriptor

        // add directory records
        var pathTable = [PathTableRecord(Data([0]))]
        let (rootLoc, extentLen) = self.createDirectoryRecord(
            self.root,
            lba,
            0,
            minLBA: Int(minLBAForDirectoryRecords),
            susp: susp,
            volPath: "",
            pathTable: &pathTable,
            parentDirectoryNumber: 1,
            nameContext: nameContext
        )
        pathTable[0].extentLocation = UInt32(rootLoc)
        pathTable[0].parentDirectoryNumber = 1

        // add L path table
        let lPathTableBytes = pathTable.map { $0.serialize(littleEndian: true) }.reduce(Data(), +)
        let numPTBlocks = numBlocksNeededFor(lPathTableBytes.count)
        let lPtLBA = nextAvailBlock(minLBAForDirectoryRecords, numPTBlocks)
        _ = writeToBlockCache(lPathTableBytes, at: lPtLBA)
        descriptor.lPathTableLocation = UInt32(lPtLBA)
        descriptor.lOptionalPathTableLocation = UInt32(0)
        descriptor.pathTableSize = UInt32(lPathTableBytes.count)

        // add M path table
        let mPathTableBytes = pathTable.map { $0.serialize(littleEndian: false) }.reduce(Data(), +)
        let mPtLBA = nextAvailBlock(minLBAForDirectoryRecords, numPTBlocks)
        _ = writeToBlockCache(mPathTableBytes, at: mPtLBA)
        descriptor.mPathTableLocation = UInt32(mPtLBA)
        descriptor.mOptionalPathTableLocation = UInt32(0)

        // update descriptor with root directory info
        var rootDirectory = DirectoryRecord(Data([0]), isDir: true, altName: nil)
        updateDirRecordMeta(&rootDirectory, FSEntry.directory(name: ".", metadata: nil), susp: false)
        rootDirectory.extentLocation = UInt32(rootLoc)
        rootDirectory.dataLength = UInt32(extentLen)
        descriptor.rootDirectory = rootDirectory

        // update descriptor with volume size info
        descriptor.volumeSizeInLogicalBlocks = UInt32(numFileBlocks + blocks.count)

        // persist directory descriptor
        let _ = writeToBlockCache(descriptor.serialize(), at: lba)

        // TODO: allow for optional backing of descriptors at a different location
    }

    /// Returns the next available block idx with a min index of `starting` and at least
    /// `count` blocks available after it.
    private func nextAvailBlock(_ starting: Int, _ count: Int) -> Int {
        var idx = starting
        while idx + count < blocks.count {
            var end = idx
            while end < idx+count {
                if blocks[end] != nil {
                    break
                } else {
                    end += 1
                }
            }
            if end == idx+count {
                return idx
            } else {
                idx = end + 1 // end was pointing to the last non-nil block
            }
        }
        // TODO: grow the blocks array dynamically
        fatalError("we've run out of available blocks to allocate")
    }

    /// Returns the number of blocks that will be needed to store `data`
    @inlinable func numBlocksNeededFor(_ data: Data) -> Int {
        return numBlocksNeededFor(data.count)
    }

    /// Returns the number of blocks that will be needed to store `len` bytes
    @inlinable func numBlocksNeededFor(_ len: Int) -> Int {
        // TODO: figure out what needs to be done for empty files
        return (len + options.blockSize - 1) / options.blockSize
    }

    /// Writes `data` to the block cache starting at LBA `at`, returning the number
    /// of blocks that were written.
    private func writeToBlockCache(_ data: Data, at: Int) -> Int {
        if data.count < options.blockSize {
            // pad the data to the block size
            if var blk = blocks[at] {
                blk.replaceSubrange(0..<data.count, with: data)
                blocks[at] = blk
            } else {
                blocks[at] = data.padded(options.blockSize, 0)
            }
            return 1
        } else if data.count == options.blockSize {
            // write the data to the block cache
            blocks[at] = data.startIndex == 0 && data.count == options.blockSize ? data : Data(data)
            return 1
        } else {
            // split the data into multiple blocks
            let numBlocks = (data.count + options.blockSize - 1) / options.blockSize
            for i in 0..<numBlocks {
                let start = i * options.blockSize
                let end = min(start + options.blockSize, data.count)
                blocks[at + i] = data.subdata(in: (start..<end).inc(by: data.startIndex))
            }
            return numBlocks
        }
    }

    /// Initialize a new ISO writer, with `media` as the underlying storage, and `options` for writing.
    ///
    /// - Parameters:
    ///   - media: The underlying storage to write to.
    ///   - options: The options to use when writing.
    ///   - contentCallback: A callback that will be invoked to get the contents for a file.
    public init(media: ISOImageMedia, options: WriteOptions, contentCallback: @escaping (String) -> InputStream) {
        self.media = media
        self.options = options
        self.contentCallback = contentCallback

        // we create 4MB (upper bound) of scratch space (2k blocks of 2kB each, or 4k blocks of 1kB each, or ...),
        // and pray to god that suffices (TODO: make this dynamic)
        self.blocks = Array<Data?>(repeating: nil, count: 2048 * 2048 / options.blockSize)

        // define descriptors
        let createVDD = { (type: UInt8, version: UInt8, encoding: String.Encoding?) -> VolumeDirectoryDescriptor in
            var vdd = VolumeDirectoryDescriptor(type: type, version: version, encoding: encoding)
            vdd.volumeIdentifier = options.volumeIdentifier
            vdd.logicalBlockSize = UInt16(options.blockSize)
            return vdd
        }
        var descriptors: [VolumeDescriptor] = [
            .primary(createVDD(1, 1, nil)),
        ]
        if options.includeSupplementaryVolDesc {
            descriptors.append(.supplementary(createVDD(2, 1, nil)))
        }
        if options.includeEnhancedVolDesc {
            descriptors.append(.enhanced(createVDD(2, 2, .utf8)))
        }
        descriptors.append(.terminator)
        self.descriptors = descriptors
    }

    /// Options that modify specific behaviors of the ISO writer.
    public struct WriteOptions {
        /// Whether to include the Supplementary/Joliet Vol Descriptor. Defaults to `false`.
        public var includeSupplementaryVolDesc: Bool = true
        /// Whether to include the Enhanced Vol Descriptor. Defaults to `false`.
        public var includeEnhancedVolDesc: Bool = false
        /// Whether to include the SUSP information in primary volume descriptor. Defaults to `true`.
        public var enableSUSP: Bool = true
        /// Logical block size to use. Defaults to `2048`.
        public var blockSize: Int = 2048
        /// Volume identifier to attach against ``VolumeDirectoryDescriptor/volumeIdentifier``
        public var volumeIdentifier: String
        /// Whether to create optional path tables. Defaults to `false`.
        public var createOptionalPathTables: Bool = false
        public var uid: UInt32 = 0
        public var gid: UInt32 = 0
        // public var fileMode: FileMode = .regular

        /// Initialize with the following default options:
        /// - ``WriteOptions/includeSupplementaryVolDesc`` = `true`
        /// - ``WriteOptions/includeEnhancedVolDesc`` = `false`
        /// - ``WriteOptions/enableSUSP`` = `true`
        /// - ``WriteOptions/blockSize`` = `2048`
        /// - ``WriteOptions/createOptionalPathTables`` = `false`
        ///
        /// - Parameter volumeIdentifier: The volume identifier to use.
        public init(volumeIdentifier: String) {
            self.volumeIdentifier = volumeIdentifier
        }
    }

    /// Maps that keep track of (key, array of locations to update). We use these to lazily update the LBA locations
    /// after they've been allocated.
    private var futureUpdateMap16 = [String: Array<(block: UInt32, offset: UInt32, kind: NumKind)>]()
    private var futureUpdateMap32 = [String: Array<(block: UInt32, offset: UInt32, kind: NumKind)>]()

    private func registerFutureUpdate(_ id: String, _ block: UInt32, _ offset: UInt32, _ kind: NumKind, _ size: Int) {
        var map = size == 16 ? futureUpdateMap16 : futureUpdateMap32
        if var arr = map[id] {
            arr.append((block, offset, kind))
            map[id] = arr
        } else {
            map[id] = [(block, offset, kind)]
        }
    }

    private func updateFuture16(_ id: String, _ value: UInt16, _ blocks: inout [Data?]) {
        if let arr = futureUpdateMap16[id] {
            for (block, offset, kind) in arr {
                let arr: Data, range: Range<Int>
                switch kind {
                    case .littleEndian:
                        arr = value.littleEndianBytes
                        range = 0..<2
                    case .bigEndian:
                        arr = value.bigEndianBytes
                        range = 0..<2
                    case .bothEndian:
                        arr = value.bothEndianBytes
                        range = 0..<4
                }
                if var block = blocks[Int(block)] {
                    block.replaceSubrange(range.inc(by: Int(offset)), with: arr)
                } else {
                    assertionFailure("lost bytes")
                }
            }
        }
    }

    /// Update 32-bit values that were registered for updates.
    private func updateFuture32(_ id: String, _ value: UInt32, _ blocks: inout [Data?]) {
        if let arr = futureUpdateMap32[id] {
            for (block, offset, kind) in arr {
                let arr: Data, range: Range<Int>
                switch kind {
                    case .littleEndian:
                        arr = value.littleEndianBytes
                        range = 0..<4
                    case .bigEndian:
                        arr = value.bigEndianBytes
                        range = 0..<4
                    case .bothEndian:
                        arr = value.bothEndianBytes
                        range = 0..<8
                }
                if var block = blocks[Int(block)] {
                    block.replaceSubrange(range.inc(by: Int(offset)), with: arr)
                } else {
                    assertionFailure("lost bytes")
                }
            }
        }
    }

    private class TreeNode {
        var children = [TreeNode]()
        var metadata: FSEntry.Metadata? = nil
        var entry: FSEntry

        init(entry: FSEntry) {
            self.entry = entry
        }
    }

    private enum NumKind {
        case littleEndian, bigEndian, bothEndian
    }
}

/// Returns the legacy filename in the 8.3;v format, possibly modifying it to make sure uniqueness
/// against `existingNames`.
func getLegacyFilename(_ name: String, _ existingNames: [String], _ maxNameLength: Int = 12) -> String {
    let name = name.uppercased()
    var fName = name.fileNameWithoutExtension.replaceNonCharset(D_CHARS, "_")
    var fExt = name.fileExtension?.replaceNonCharset(D_CHARS, "_")
    var fNameLen = fName.count
    var fExtLen = fExt?.count ?? -1

    // trim ext to 3 chars if required
    if fExtLen > 3 && (fNameLen + fExtLen + 1) > maxNameLength {
        fExtLen = 3
        fExt = String(fExt!.prefix(3))
    }

    // trim name if required
    if fNameLen + fExtLen + 1 > maxNameLength {
        fName = String(fName.prefix(maxNameLength - fExtLen - 1))
        fNameLen = fName.count
    }

    // keep modifying until we have a unique name
    var i = 1, j = 0
    while true {
        let fullName: String
        if let fExt = fExt {
            fullName = "\(fName).\(fExt);1"
        } else {
            fullName = "\(fName);1"
        }
        if !existingNames.contains(fullName) {
            return fullName
        }
        if fNameLen + fExtLen + 1 < maxNameLength {
            // there's space available, so let's try adding numbers to the end of the file name
            fName = "\(fName)\(j)"
        } else {
            // we try substituting last characters of file name to find a unique one
            if i >= fNameLen {
                break
            }
            fName = "\(fName.prefix(fNameLen - i))\(j)"
            fNameLen = fName.count
            if j >= 10^i {
                j = 0
                i += 1
            } else {
                j += 1
            }
        }
    }
    fatalError("ran out of unique name completions")
}

private extension InputStream {
    func readInto(_ buffer: UnsafeMutablePointer<UInt8>, _ count: Int) throws -> Int {
        var numRead = 0
        while hasBytesAvailable {
            if numRead >= count {
                break
            }
            // let res = read(&buffer[(numRead + buffer.startIndex)...], maxLength: count - numRead)
            let res = read(buffer.advanced(by: numRead), maxLength: count - numRead)
            if res < 0 {
                throw streamError!
            } else if res == 0 {
                break
            } else {
                numRead += res
            }
        }
        return numRead
    }

    func readInto(_ data: inout Data, _ count: Int) throws -> Int {
        return try data.withUnsafeMutableBytes { (ptr: UnsafeMutableRawBufferPointer) in
            return try readInto(ptr.bindMemory(to: UInt8.self).baseAddress!, count)
        }
    }
}

private class BlockSectorWriter {
    let blockSize: Int
    var sectorData: Data
    let media: ISOImageMedia
    var currentSectorId: Int = 0
    var dirty = false

    init(blockSize: Int, media: ISOImageMedia) {
        self.blockSize = blockSize
        self.media = media
        self.sectorData = Data(count: media.sectorSize)
    }

    /// Flushes any existing data onto the media
    func flush() throws {
        if dirty {
            try media.writeSectorData(currentSectorId, sectorData)
            sectorData.resetBytes(in: 0..<media.sectorSize)
            dirty = false
        }
    }

    /// Invoke `op` with the block buffer for the given block ID. This assumes
    /// that it's invoked strictly in increasing order of block IDs.
    func withBlockBuffer<R>(_ blockId: Int, op: (inout Data) throws -> R) throws -> R {
        let sectorId = blockId * blockSize / media.sectorSize
        let isNewSector = currentSectorId != sectorId

        // we flush any existing sector first
        if isNewSector {
            try flush()
        }
        currentSectorId = sectorId

        // now let's invoke `op` with the block buffer
        let offset = (blockId * blockSize) % media.sectorSize
        let result = try op(&sectorData[offset..<(offset + blockSize)])
        dirty = true

        return result
    }
}
