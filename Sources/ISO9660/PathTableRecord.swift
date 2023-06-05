import Foundation

/// Structure of a path table record, as defined in ECMA-119 9.4. A list of these constitute
/// a Path Table. See Overview for more details.
///
/// Path table is a contiguous list of these records in a sorted fashion. Each record points
/// to the logical block containing the ``DirectoryRecord`` for that name. There are no
/// entries in the path table for non-directory files, and those must be looked up using
/// the corresponding ``DirectoryRecord``.
///
/// Because there is no SUSP information in path table, this must be used only where the
/// encoding of the name is proper, e.g. for supplementary volume descriptors.
public struct PathTableRecord {
    /// Directory identifier as bytes
    public private(set) var directoryIdentifierBytes: Data

    /// The length of the directory identifier in bytes, as defined in ECMA-119 9.4
    public var directoryIdentifierLength: UInt8 {
        UInt8(directoryIdentifierBytes.count)
    }

    /// The length of the extended attribute record, as defined in ECMA-119 9.4
    public internal(set) var extendedAttributeRecordLength: UInt8

    /// The LBA location of the file section extent, as defined in ECMA-119 9.4
    public internal(set) var extentLocation: UInt32

    /// The record number in the path table for the parent directory, as defined in ECMA-119 9.4
    public internal(set) var parentDirectoryNumber: UInt16

    /// Total length of this record in bytes.
    public var length: Int {
        let diLen = Int(directoryIdentifierLength)
        return PTR_DIR_ID_START_IDX + diLen + (diLen % 2)
    }

    /// The directory identifier, as defined in ECMA-119 9.4
    public func getDirectoryIdentifier(encoding: String.Encoding) -> String {
        if directoryIdentifierBytes.count == 1 && directoryIdentifierBytes[0] == 0 {
            return "/"
        } else {
            return String(data: directoryIdentifierBytes, encoding: encoding)
                ?? String(repeating: "?", count: directoryIdentifierBytes.count)
        }
    }

    /// Serializes this path table record into a byte array, as per ECMA-119 section 9.4
    /// - Returns: The serialized byte buffer representing this path table record
    func serialize(littleEndian: Bool) -> Data {
        var data = Data(count: length)
        data[PTR_DIR_ID_LENGTH_IDX] = directoryIdentifierLength
        data[PTR_EXTENDED_ATTRIBUTE_RECORD_LENGTH_IDX] = extendedAttributeRecordLength
        data.replaceSubrange(PTR_EXTENT_LOCATION_RANGE, with: littleEndian ? extentLocation.littleEndianBytes : extentLocation.bigEndianBytes)
        data.replaceSubrange(PTR_PARENT_DIRECTORY_NUMBER_RANGE, with: littleEndian ? parentDirectoryNumber.littleEndianBytes : parentDirectoryNumber.bigEndianBytes)
        let diLen = Int(directoryIdentifierLength)
        data.replaceSubrange((0..<diLen).inc(by: PTR_DIR_ID_START_IDX), with: directoryIdentifierBytes)
        return data
    }

    /// Reads a new path table record from the given data
    /// - Parameter data: The bytes from which to read the record
    /// - Returns: A new path table record, or nil if the data is too short
    init?(from data: Data) {
        let diLen = data[data.startIndex + PTR_DIR_ID_LENGTH_IDX]
        let len = 8 + diLen + (diLen % 2 == 0 ? 0 : 1)
        guard data.count >= len else { return nil }
        directoryIdentifierBytes = data[(0..<Int(diLen)).inc(by: PTR_DIR_ID_START_IDX + data.startIndex)]
        extendedAttributeRecordLength = data[data.startIndex + PTR_EXTENDED_ATTRIBUTE_RECORD_LENGTH_IDX]
        extentLocation = UInt32(fromBothEndian: data[PTR_EXTENT_LOCATION_RANGE.inc(by: data.startIndex)])
        parentDirectoryNumber = UInt16(fromBothEndian: data[PTR_PARENT_DIRECTORY_NUMBER_RANGE.inc(by: data.startIndex)])
    }

    /// Creates a new path table record with the given identifier
    /// - Parameters:
    ///   - identifier: The identifier of the directory
    init(_ identifier: Data) {
        self.directoryIdentifierBytes = identifier
        self.extendedAttributeRecordLength = 0
        self.extentLocation = 0
        self.parentDirectoryNumber = 0
    }

    /// Creates a new path table record with the given identifier
    /// - Parameters:
    ///   - identifier: The identifier of the directory
    ///   - encoding: The encoding to use for the identifier
    init(_ identifier: String, encoding: String.Encoding) {
        self.init(identifier.data(using: encoding) ?? Data())
    }
}

private let PTR_DIR_ID_LENGTH_IDX = 0
private let PTR_EXTENDED_ATTRIBUTE_RECORD_LENGTH_IDX = 1
private let PTR_EXTENT_LOCATION_RANGE = 2..<6
private let PTR_PARENT_DIRECTORY_NUMBER_RANGE = 6..<8
private let PTR_DIR_ID_START_IDX = 8
