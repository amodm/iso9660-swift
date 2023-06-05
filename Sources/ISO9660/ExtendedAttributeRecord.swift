import Foundation

/// Structure of an extended attribute record, as defined in ECMA-119 9.5
public struct ExtendedAttributeRecord {
    private var data: Data
    private let systemIdEncoding: String.Encoding

    /// The owner identifier, as defined in ECMA-119 9.5
    public var ownerId: UInt16 {
        get { UInt16(fromBothEndian: data[EXT_OWNER_ID_RANGE.inc(by: data.startIndex)]) }
        set { data.replaceSubrange(EXT_OWNER_ID_RANGE.inc(by: data.startIndex), with: newValue.bothEndianBytes) }
    }

    /// The group identifier, as defined in ECMA-119 9.5
    public var groupId: UInt16 {
        get { UInt16(fromBothEndian: data[EXT_GROUP_ID_RANGE.inc(by: data.startIndex)]) }
        set { data.replaceSubrange(EXT_GROUP_ID_RANGE.inc(by: data.startIndex), with: newValue.bothEndianBytes) }
    }

    /// Permissions for this entry, as defined in ECMA-119 9.5. See table 13 for the bit flags.
    public var permissions: UInt16 {
        get { UInt16(data[EXT_PERMISSIONS_RANGE.inc(by: data.startIndex)], littleEndian: false) }
        set {
            // set the bits that the spec expects to be 1
            let newValue = newValue | 0b1010_1010_1010_1010
            data.replaceSubrange(EXT_PERMISSIONS_RANGE.inc(by: data.startIndex), with: newValue.bigEndianBytes)
        }
    }

    /// Creation time, as defined in ECMA-119 9.5
    public var creationTime: Date? {
        get { Date.decode(from: data[EXT_FILE_CREATION_TIME_RANGE.inc(by: data.startIndex)], format: .format17B) }
        set { data.replaceSubrange(EXT_FILE_CREATION_TIME_RANGE.inc(by: data.startIndex), with: newValue.iso9660Format17B) }
    }

    /// Modification time, as defined in ECMA-119 9.5
    public var modificationTime: Date? {
        get { Date.decode(from: data[EXT_FILE_MODIFICATION_TIME_RANGE.inc(by: data.startIndex)], format: .format17B) }
        set { data.replaceSubrange(EXT_FILE_MODIFICATION_TIME_RANGE.inc(by: data.startIndex), with: newValue.iso9660Format17B) }
    }

    /// Expiration time, as defined in ECMA-119 9.5
    public var expirationTime: Date? {
        get { Date.decode(from: data[EXT_FILE_EXPIRATION_TIME_RANGE.inc(by: data.startIndex)], format: .format17B) }
        set { data.replaceSubrange(EXT_FILE_EXPIRATION_TIME_RANGE.inc(by: data.startIndex), with: newValue.iso9660Format17B) }
    }

    /// Effective time, as defined in ECMA-119 9.5
    public var effectiveTime: Date? {
        get { Date.decode(from: data[EXT_FILE_EFFECTIVE_TIME_RANGE.inc(by: data.startIndex)], format: .format17B) }
        set { data.replaceSubrange(EXT_FILE_EFFECTIVE_TIME_RANGE.inc(by: data.startIndex), with: newValue.iso9660Format17B) }
    }

    /// The record format, as defined in ECMA-119 9.5
    public var recordFormat: UInt8 {
        get { data[data.startIndex + EXT_RECORD_FORMAT_IDX] }
        set { data[data.startIndex + EXT_RECORD_FORMAT_IDX] = newValue }
    }

    /// The record attributes, as defined in ECMA-119 9.5
    public var recordAttributes: UInt8 {
        get { data[data.startIndex + EXT_RECORD_ATTRIBUTES_IDX] }
        set { data[data.startIndex + EXT_RECORD_ATTRIBUTES_IDX] = newValue }
    }

    /// The length of the record, as defined in ECMA-119 9.5. Note that this is NOT the length of the
    /// extended attribute record, but the length of the record as referred in ECMA-119 6.10 (Record
    /// Structure).
    public var recordLength: UInt16 {
        get { UInt16(fromBothEndian: data[EXT_RECORD_LENGTH_RANGE.inc(by: data.startIndex)]) }
        set { data.replaceSubrange(EXT_RECORD_LENGTH_RANGE.inc(by: data.startIndex), with: newValue.bothEndianBytes) }
    }

    /// The system identifier, as defined in ECMA-119 9.5
    public var systemIdentifier: String {
        get { String.deserialize(data[EXT_SYSTEM_ID_RANGE.inc(by: data.startIndex)], systemIdEncoding) }
        set {
            self.data.replaceSerializedString(EXT_SYSTEM_ID_RANGE.inc(by: data.startIndex), with: newValue, encoding: systemIdEncoding)
        }
    }

    /// System use area, as defined in ECMA-119 9.5. The size of this is fixed to 64 bytes.
    public var systemUse: Data {
        get { data[EXT_SYSTEM_USE_RANGE.inc(by: data.startIndex)] }
        set {
            data.replaceSubrange(EXT_SYSTEM_USE_RANGE.inc(by: data.startIndex), with: newValue.padded(EXT_SYSTEM_USE_RANGE.count))
        }
    }

    /// The version of the extended attribute record, as defined in ECMA-119 9.5. We currently understand
    /// only version 1.
    public private(set) var version: UInt8 {
        get { data[data.startIndex + EXT_ATTRIB_RECORD_VERSION_IDX] }
        set { data[data.startIndex + EXT_ATTRIB_RECORD_VERSION_IDX] = newValue }
    }

    /// The length of the escape sequences, as defined in ECMA-119 9.5.
    public private(set) var escapeSequenceLength: UInt8 {
        get { data[data.startIndex + EXT_ESCAPE_SEQ_LEN_IDX] }
        set { data[data.startIndex + EXT_ESCAPE_SEQ_LEN_IDX] = newValue }
    }

    /// The length of the application use area, as defined in ECMA-119 9.5.
    public private(set) var applicationUseLength: UInt16 {
        get { UInt16(fromBothEndian: data[EXT_APP_USE_LEN_RANGE.inc(by: data.startIndex)]) }
        set { data.replaceSubrange(EXT_APP_USE_LEN_RANGE.inc(by: data.startIndex), with: newValue.bothEndianBytes) }
    }

    /// The application use area, as defined in ECMA-119 9.5.
    public var applicationUse: Data {
        get { data[EXT_APP_USE_START_IDX..<(EXT_APP_USE_START_IDX + Int(applicationUseLength))] }
        set {
            let oldAppUseLen = self.applicationUseLength
            let oldEscapeStartIdx = EXT_APP_USE_START_IDX + Int(oldAppUseLen)
            self.data = self.data[(0..<EXT_APP_USE_START_IDX).inc(by: data.startIndex)]
                + newValue
                + self.data[(data.startIndex + oldEscapeStartIdx)...]
            self.applicationUseLength = UInt16(newValue.count)
        }
    }

    /// The escape sequence area, as defined in ECMA-119 9.5.
    public var escapeSequence: Data {
        get {
            let escapeStartIdx = EXT_APP_USE_START_IDX + Int(applicationUseLength)
            return data[(escapeStartIdx..<(escapeStartIdx + Int(escapeSequenceLength))).inc(by: data.startIndex)]
        }
        set {
            let newValue = newValue.count > 256 ? newValue[..<256] : newValue
            let escapeStartIdx = EXT_APP_USE_START_IDX + Int(applicationUseLength)
            self.data = self.data[(0..<escapeStartIdx).inc(by: data.startIndex)] + newValue
            self.escapeSequenceLength = UInt8(newValue.count)
        }
    }

    /// Initialize a new extended attribute record from the given data
    /// - Parameter data: The data to initialize from
    /// - Parameter systemIdEncoding: The encoding of the system identifier
    init(from data: Data, systemIdEncoding: String.Encoding = .ascii) {
        self.data = data
        self.systemIdEncoding = systemIdEncoding
    }

    /// Initialize a new empty extended attribute record
    /// - Parameter systemIdEncoding: The encoding of the system identifier
    init(_ systemIdEncoding: String.Encoding = .ascii) {
        defer {
            self.creationTime = nil
            self.modificationTime = nil
            self.expirationTime = nil
            self.effectiveTime = nil
        }
        self.data = Data(repeating: 0, count: 256)
        self.systemIdEncoding = systemIdEncoding
        self.version = 1
    }
}

private let EXT_OWNER_ID_RANGE = 0..<4
private let EXT_GROUP_ID_RANGE = 4..<8
private let EXT_PERMISSIONS_RANGE = 8..<10
private let EXT_FILE_CREATION_TIME_RANGE = 10..<27
private let EXT_FILE_MODIFICATION_TIME_RANGE = 27..<44
private let EXT_FILE_EXPIRATION_TIME_RANGE = 44..<61
private let EXT_FILE_EFFECTIVE_TIME_RANGE = 61..<78
private let EXT_RECORD_FORMAT_IDX = 78
private let EXT_RECORD_ATTRIBUTES_IDX = 79
private let EXT_RECORD_LENGTH_RANGE = 80..<84
private let EXT_SYSTEM_ID_RANGE = 84..<116
private let EXT_SYSTEM_USE_RANGE = 116..<180
private let EXT_ATTRIB_RECORD_VERSION_IDX = 180
private let EXT_ESCAPE_SEQ_LEN_IDX = 181
private let EXT_APP_USE_LEN_RANGE = 246..<250
private let EXT_APP_USE_START_IDX = 250
