import Foundation

/// Structure of a directory record, as defined in ECMA-119 9.1, Table 8
public struct DirectoryRecord {
    /// If set, means this dir or file is hidden
    public static let FLAG_IS_HIDDEN: UInt8 = 0b00000001
    /// If set, means this is a directory
    public static let FLAG_IS_DIRECTORY: UInt8 = 0b00000010
    /// If set, means this file is an associated file
    public static let FLAG_IS_ASSOCIATED: UInt8 = 0b00000100
    /// If set, means this file has a record format specified in extended attributes
    public static let FLAG_IS_RECORD: UInt8 = 0b0001000
    /// If set, means this dir or file has owner & group permissions defined in extended attributes
    public static let FLAG_PROTECTION: UInt8 = 0b0010000
    /// If set, means this is not the final directory record for this file
    public static let FLAG_IS_MULTIEXTENT: UInt8 = 0b10000000

    /// Identifies a file or directory
    public enum Identifier: Equatable {
        /// The special directory `.` which refers to the current directory
        case dot
        /// The special directory `..` which refers to the parent directory
        case dotdot
        /// A file with a name
        case file(String)
        /// A directory with a name
        case directory(String)
        /// An invalid identifier. Can happen if the identifier is not a valid string
        case invalid
    }

    private var data: Data

    /// The length of the directory record, as defined in ECMA-119 9.1
    public var length: UInt8 {
        data[data.startIndex + DR_LENGTH_IDX]
    }

    /// The length of the extended attribute record, as defined in ECMA-119 9.1
    public private(set) var extendedAttributeRecordLength: UInt8 {
        get { data[data.startIndex + DR_EXT_ATTRIB_RECORD_LENGTH_IDX] }
        set { data[data.startIndex + DR_EXT_ATTRIB_RECORD_LENGTH_IDX] = newValue }
    }

    /// The LBA location of the file section extent, as defined in ECMA-119 9.1
    public var extentLocation: UInt32 {
        get { UInt32(fromBothEndian: data[DR_EXT_LOCATION_RANGE.inc(by: data.startIndex)]) }
        set { data.replaceSubrange(DR_EXT_LOCATION_RANGE.inc(by: data.startIndex), with: newValue.bothEndianBytes) }
    }

    /// The data length of the file section, as defined in ECMA-119 9.1
    public var dataLength: UInt32 {
        get { UInt32(fromBothEndian: data[DR_DATA_LENGTH_RANGE.inc(by: data.startIndex)]) }
        set { data.replaceSubrange(DR_DATA_LENGTH_RANGE.inc(by: data.startIndex), with: newValue.bothEndianBytes) }
    }

    /// The date and time of recording, as defined in ECMA-119 9.1.5
    public var recordDate: Date? {
        get { Date.decode(from: data[DR_RECORD_DATE_RANGE.inc(by: data.startIndex)], format: .format7B) }
        set { data.replaceSubrange(DR_RECORD_DATE_RANGE.inc(by: data.startIndex), with: newValue.iso9660Format7B) }
    }

    /// The flags of the directory record, as defined in ECMA-119 9.1.6
    public var flags: UInt8 {
        get { data[data.startIndex + DR_FLAGS_IDX] }
        set { data[data.startIndex + DR_FLAGS_IDX] = newValue }
    }

    /// Does this record represent the last extent of this file?
    public private(set) var isLastExtent: Bool {
        get { flags & DirectoryRecord.FLAG_IS_MULTIEXTENT == 0 }
        set {
            if newValue {
                flags &= ~DirectoryRecord.FLAG_IS_MULTIEXTENT
            } else {
                flags |= DirectoryRecord.FLAG_IS_MULTIEXTENT
            }
        }
    }

    /// Does this directory record represent a directory?
    var isDirectory: Bool {
        get { flags & DirectoryRecord.FLAG_IS_DIRECTORY != 0 }
        set {
            if newValue {
                flags |= DirectoryRecord.FLAG_IS_DIRECTORY
                flags &= ~(DirectoryRecord.FLAG_IS_ASSOCIATED | DirectoryRecord.FLAG_IS_RECORD | DirectoryRecord.FLAG_IS_MULTIEXTENT)
            } else {
                flags &= ~DirectoryRecord.FLAG_IS_DIRECTORY
            }
        }
    }

    /// The file unit size of the file section if the file is stored in interleaved mode. See ECMA-119 9.1.7
    public var fileUnitSize: UInt8 {
        get { data[data.startIndex + DR_FILE_UNIT_SIZE_IDX] }
        set { data[data.startIndex + DR_FILE_UNIT_SIZE_IDX] = newValue }
    }

    /// The interleave gap size of the file section if the file is stored in interleaved mode. See ECMA-119 9.1.8
    public var interleaveGapSize: UInt8 {
        get { data[data.startIndex + DR_INTERLEAVE_GAP_SIZE_IDX] }
        set { data[data.startIndex + DR_INTERLEAVE_GAP_SIZE_IDX] = newValue }
    }

    /// The volume sequence number of the volume set on which this extent is stored. See ECMA-119 9.1.9
    public var volumeSequenceNumber: UInt16 {
        get { UInt16(fromBothEndian: data[DR_VOL_SEQUENCE_NUMBER_RANGE.inc(by: data.startIndex)]) }
        set { data.replaceSubrange(DR_VOL_SEQUENCE_NUMBER_RANGE.inc(by: data.startIndex), with: newValue.bothEndianBytes) }
    }

    /// The identifier, as defined in ECMA-119 9.1.11
    public func getIdentifier(encoding: String.Encoding) -> Identifier {
        let idBytes = identifierBytes
        if idBytes.count == 1 && idBytes.first == 0 {
            return .dot
        } else if idBytes.count == 1 && idBytes.first == 1 {
            return .dotdot
        } else if idBytes.count > 0 {
            let name = String.deserialize(idBytes, encoding)
            return isDirectory ? .directory(name) : .file(name)
        } else {
            return .invalid
        }
    }

    /// The identifier (as raw bytes), as defined in ECMA-119 9.1.11
    var identifierBytes: Data {
        get {
            let length = data[data.startIndex + DR_FILE_IDENTIFIER_LENGTH_IDX]
            let idx = data.startIndex + DR_FILE_IDENTIFIER_LENGTH_IDX + 1
            if length == 1 && data[idx] == 0 {
                return Data([0])
            } else if length == 1 && data[idx] == 1 {
                return Data([1])
            } else if length > 0 {
                return data[idx..<(idx + Int(length))]
            } else {
                return Data([])
            }
        }
        set {
            if newValue.isEmpty {
                assertionFailure("Invalid identifier")
            }
            // save existing system use data
            let existingSystemUse: Data
            if let su = systemUse {
                existingSystemUse = su
            } else {
                existingSystemUse = Data([])
            }

            // we calculate the appropriate length
            let newNameLen = newValue.count
            let padLen: UInt8 = newNameLen % 2 == 0 ? 1 : 0
            var correctLength = 33 + UInt8(newNameLen) + padLen + UInt8(existingSystemUse.count)
            if correctLength % 2 != 0 {
                correctLength += 1
            }
            if data.count < Int(correctLength) {
                data.append(Data(count: Int(correctLength) - data.count))
            }

            data[data.startIndex + DR_LENGTH_IDX] = correctLength // set record length
            let nameLenIdx = data.startIndex + DR_FILE_IDENTIFIER_LENGTH_IDX
            data[nameLenIdx] = UInt8(newNameLen) // set name length
            data.replaceSubrange((0..<newNameLen).inc(by: nameLenIdx+1), with: newValue) // set name
            if padLen != 0 {
                data[nameLenIdx + 1 + newNameLen] = 0 // set padding
            }
            if !existingSystemUse.isEmpty {
                let range = (0..<existingSystemUse.count).inc(by: nameLenIdx + 1 + newNameLen + Int(padLen))
                data.replaceSubrange(range, with: existingSystemUse) // restore system use data
            }
        }
    }

    /// The system use field, as defined in ECMA-119 9.1.13
    public var systemUse: Data? {
        get {
            let dirLength = data[data.startIndex + DR_LENGTH_IDX]
            let nameLength = data[data.startIndex + DR_FILE_IDENTIFIER_LENGTH_IDX]
            let padLen: UInt8 = nameLength % 2 == 0 ? 1 : 0
            let systemUseStart = 33 + nameLength + padLen
            let systemUseLength = Int(dirLength) - Int(systemUseStart)
            if systemUseLength > 0 {
                return data[(data.startIndex+Int(systemUseStart))...]
            } else {
                return nil
            }
        }
        set {
            let nameLength = data[data.startIndex + DR_FILE_IDENTIFIER_LENGTH_IDX]
            let padLen: UInt8 = nameLength % 2 == 0 ? 1 : 0
            let mainLen = Int(33 + nameLength + padLen)

            if let systemUse = newValue {
                self.data = self.data[(0..<mainLen).inc(by: data.startIndex)] + systemUse
                self.data[data.startIndex + DR_LENGTH_IDX] = UInt8(self.data.count)
            } else {
                self.data = self.data[(0..<mainLen).inc(by: self.data.startIndex)]
                self.data[data.startIndex + DR_LENGTH_IDX] = UInt8(self.data.count)
            }
        }
    }

    /// Serializes this directory record into a byte array, as per ECMA-119 section 9.1
    /// - Returns: The serialized byte buffer representing this directory record
    func serialize() -> Data {
        data
    }

    /// Reads a new directory record from the given data
    /// - Parameter data: The bytes from which to read the directory record
    init(from data: Data) {
        self.data = data
    }

    init(_ idBytes: Data, isDir: Bool, altName: String?) {
        let recLen = 33 + UInt8(idBytes.count) + (idBytes.count % 2 == 0 ? 1 : 0)
        self.data = Data(repeating: 0, count: Int(recLen))
        self.identifierBytes = idBytes
        self.volumeSequenceNumber = 1
        self.isDirectory = isDir
    }
}

private let DR_LENGTH_IDX = 0
private let DR_EXT_ATTRIB_RECORD_LENGTH_IDX = 1
private let DR_EXT_LOCATION_RANGE = 2..<10
private let DR_DATA_LENGTH_RANGE = 10..<18
private let DR_RECORD_DATE_RANGE = 18..<25
private let DR_FLAGS_IDX = 25
private let DR_FILE_UNIT_SIZE_IDX = 26
private let DR_INTERLEAVE_GAP_SIZE_IDX = 27
private let DR_VOL_SEQUENCE_NUMBER_RANGE = 28..<32
private let DR_FILE_IDENTIFIER_LENGTH_IDX = 32
