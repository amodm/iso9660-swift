import Foundation

/// The physical medium storing the ISO filesystem. It could be a disk image, or an optical media, so this
/// abstraction allows us to use the same library for both.
///
/// The spec (ECMA-119 6.1) defines the physical media to be addressed in sectors. Different kinds of media
/// may have different physical sector sizes, so the spec differentiates between logical sectors and physical
/// ones.
///
/// The spec deals only in logical sectors and logical blocks (subunit of sectors), and communicates
/// with this underlying media abstraction, using only the logical sector numbers. It is the responsibility of
/// this media implementation to translate the logical sector numbers to physical addresses on the media.
public protocol ISOImageMedia {
    /// Return true if the underlying media does not contain any data yet, or if the underlying media doesn't
    /// exist yet.
    var isBlank: Bool { get }

    /// The size of a logical sector in bytes. This is guaranteed to be a power of 2, and a minimum of 2048.
    /// This is also guaranteed to be called before any other methods, and will be called only once.
    var sectorSize: Int { get set }

    /// Maximum possible sectors in the media, incuding those reserved for system area. This is used to indicate
    /// to ``ISOFileSystem`` on how to split the content between different volumes in a volume set.
    var maximumSectors: Int { get }

    /// Reads the data for the given logical sector.
    /// - Parameter sector: The logical sector number to read
    /// - Returns: The data for the given sector
    /// - Throws: If the sector is out of bounds or there is an error reading the data
    func getSectorData(_ sector: Int) throws -> Data

    /// Writes the data for the given logical sector. `data` is guaranteed to be of appropriate sector size. If
    /// the sector is out of bounds, the underlying physical media is extended to fit the sector.
    /// - Parameter sector: The logical sector number to write
    /// - Parameter data: The data to write
    /// - Throws: If the sector is out of bounds or there is an error writing the data
    func writeSectorData(_ sector: Int, _ data: Data) throws

    /// Flushes any pending writes to the underlying media. This is guaranteed to be called before the media is
    /// closed.
    func sync() throws
}

/// A local file based ISO image media
public class ISOImageFileMedia {
    public let url: URL
    public var sectorSize: Int = 2048 {
        didSet {
            if sectorSize < 2048 || sectorSize.nonzeroBitCount != 1 {
                assertionFailure("Sector size must be a power of 2 and at least 2048. Rejecting.")
                sectorSize = 2048
            }
        }
    }
    public var maximumSectors: Int
    private let fileHandle: FileHandle
    private var fileLen: UInt64

    /// Initialize a new ``ISOImageMedia`` with `url` as the underlying physical source/target.
    ///
    /// - Parameter url: The URL to the ISO image file.
    /// - Parameter sectorSize: The size of a logical sector in bytes. This is guaranteed to be a power of 2, and a minimum of 2048.
    /// - Parameter maximumSectors: Maximum possible sectors to allow in this file. Default is to ensure a maximum file size of 4GB.
    /// - Parameter readOnly: If the file should be opened in read-only mode. If `nil`, the file is opened in read-write mode
    /// if not existing, and read-only mode if existing.
    /// - Throws: If the file cannot be opened for reading/writing
    public init(_ url: URL, sectorSize: Int = 2048, maximumSectors: Int? = nil, readOnly: Bool? = nil) throws {
        self.url = url
        if !url.isFileURL {
            throw APIError.invalidArgument(name: "url", message: "URL must be a file URL")
        }
        let fileExists = url.fileExists
        let readOnly = readOnly == nil ?? !fileExists
        if readOnly {
            self.fileHandle = try FileHandle(forReadingFrom: url)
            self.fileLen = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as! UInt64
        } else {
            if fileExists {
                self.fileHandle = try FileHandle(forUpdating: url)
                self.fileLen = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as! UInt64
            } else {
                FileManager.default.createFile(atPath: url.path, contents: nil, attributes: nil)
                self.fileHandle = try FileHandle(forWritingTo: url)
                self.fileLen = 0
            }
        }
        self.sectorSize = sectorSize
        self.maximumSectors = maximumSectors ?? (2 << 31) / sectorSize
    }

    /// Initialize a new ``ISOImageMedia`` with `path` as the underlying physical source/target.
    ///
    /// - Parameter path: The path to the ISO image file.
    /// - Parameter sectorSize: The size of a logical sector in bytes. This is guaranteed to be a power of 2, and a minimum of 2048.
    /// - Parameter maximumSectors: Maximum possible sectors to allow in this file. Default is to ensure a maximum file size of 4GB.
    /// - Parameter readOnly: If the file should be opened in read-only mode. If `nil`, the file is opened in read-write mode
    /// if not existing, and read-only mode if existing.
    /// - Throws: If the file cannot be opened for reading/writing
    convenience init(_ path: String, sectorSize: Int = 2048, maximumSectors: Int? = nil, readOnly: Bool? = nil) throws {
        try self.init(URL(fileURLWithPath: path), sectorSize: sectorSize, maximumSectors: maximumSectors, readOnly: readOnly)
    }

    deinit {
        fileHandle.closeFile()
    }
}

extension ISOImageFileMedia: ISOImageMedia {
    public var isBlank: Bool {
        return !url.fileExists
    }

    public func getSectorData(_ sector: Int) throws -> Data {
        let offset = sector * sectorSize
        if offset > self.fileLen {
            return Data(count: sectorSize)
        }
        fileHandle.seek(toFileOffset: UInt64(offset))
        return fileHandle.readData(ofLength: sectorSize)
    }

    public func writeSectorData(_ sector: Int, _ data: Data) throws {
        assert(data.count == sectorSize, "Data size \(data.count) must match sector size \(sectorSize)")
        let offset = sector * sectorSize
        fileHandle.seek(toFileOffset: UInt64(offset))
        fileHandle.write(data)

        let cursor = UInt64(offset) + UInt64(data.count)
        if cursor > fileLen {
            fileLen = cursor
        }
    }

    public func sync() throws {
        if #available(macOS 10.15, *) {
            try fileHandle.synchronize()
        } else {
            // TODO: what used to do sync's functionality before 10.15?
        }
    }
}
