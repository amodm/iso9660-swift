import Foundation

/// Volume Descriptor as defined in ECMA-119 8.4 and 8.5, which acts as a container for Directory Records. Can come in three types:
/// - Primary Volume Descriptor (PVD) - this has `type` 1 and `version` 1
/// - Supplementary Volume Descriptor (SVD) - this has `type` 2 and `version` 1
/// - Enhanced Volume Descriptor (EVD) - this has `type` 2 and `version` 2
public struct VolumeDirectoryDescriptor {
    private var data: Data
    internal let encoding: String.Encoding

    /// Volume Descriptor Type as defined in ECMA-119 8.3.1. This is 1 for Primary, 2 for Supplementary & Enhanced Volume Descriptors.
    public private(set) var type: UInt8 {
        get { data[data.startIndex + VD_TYPE_IDX] }
        set { data[data.startIndex + VD_TYPE_IDX] = newValue }
    }

    /// Volume Descriptor Version as defined in ECMA-119 8.3.3. This is 1 for both Primary and Supplementary Volume Descriptors,
    /// but is 2 for Enhanced Volume Descriptors
    public private(set) var version: UInt8 {
        get { data[data.startIndex + VD_VERSION_IDX] }
        set { data[data.startIndex + VD_VERSION_IDX] = newValue }
    }

    /// Flags as defined in ECMA-119 8.5.3. Valid only for Supplementary & Enhanced Volume Descriptors.
    public var volumeFlags: UInt8 {
        get { data[data.startIndex + VD_VOL_FLAGS_IDX] }
        set { data[data.startIndex + VD_VOL_FLAGS_IDX] = newValue }
    }

    /// System Identifier as defined in ECMA-119 8.4.5. Must be an A-String.
    public var systemIdentifier: String {
        get { String.deserialize(data[VD_SYSTEM_ID_RANGE.inc(by: data.startIndex)], encoding) }
        set { data.replaceSerializedString(VD_SYSTEM_ID_RANGE.inc(by: data.startIndex), with: newValue, encoding: encoding) }
    }

    /// Volume Identifier as defined in ECMA-119 8.4.6. Must be a D-String for PVDs.
    public var volumeIdentifier: String {
        get { String.deserialize(data[VD_VOL_ID_RANGE.inc(by: data.startIndex)], encoding) }
        set { data.replaceSerializedString(VD_VOL_ID_RANGE.inc(by: data.startIndex), with: newValue, encoding: encoding) }
    }

    /// Volume Space Size as defined in ECMA-119 8.4.8. This times the logical block size gives the total size of the volume.
    public var volumeSizeInLogicalBlocks: UInt32 {
        get { UInt32(fromBothEndian: data[VD_VOL_SPACE_SIZE_RANGE.inc(by: data.startIndex)]) }
        set { data.replaceSubrange(VD_VOL_SPACE_SIZE_RANGE.inc(by: data.startIndex), with: newValue.bothEndianBytes) }
    }

    /// Volume Size in bytes. This is simply `volumeSizeInLogicalBlocks` times `logicalBlockSize`.
    public var volumeSizeInBytes: UInt64 {
        get { UInt64(volumeSizeInLogicalBlocks) * UInt64(logicalBlockSize) }
    }

    /// Escape Sequences as defined in ECMA-119 8.5.6. Valid only for supplementary/enhanced volume descriptors.
    public var escapeSequences: Data {
        get { data[VD_ESCAPE_SEQ_RANGE] }
        set { data.replaceVariableSubrange(VD_ESCAPE_SEQ_RANGE.inc(by: data.startIndex), with: newValue) }
    }

    /// Volume Set Size as defined in ECMA-119 8.4.9
    public var volumeSetSize: UInt16 {
        get { UInt16(fromBothEndian: data[VD_VOL_SET_SIZE_RANGE.inc(by: data.startIndex)]) }
        set { data.replaceSubrange(VD_VOL_SET_SIZE_RANGE.inc(by: data.startIndex), with: newValue.bothEndianBytes) }
    }

    /// Volume Sequence Number as defined in ECMA-119 8.4.11
    public var volumeSequenceNumber: UInt16 {
        get { UInt16(fromBothEndian: data[VD_VOL_SEQ_NUM_RANGE.inc(by: data.startIndex)]) }
        set { data.replaceSubrange(VD_VOL_SEQ_NUM_RANGE.inc(by: data.startIndex), with: newValue.bothEndianBytes) }
    }

    /// Logical Block Size (in bytes) as defined in ECMA-119 8.4.12. Must be a power of 2.
    public var logicalBlockSize: UInt16 {
        get { UInt16(fromBothEndian: data[VD_LOGICAL_BLOCK_SIZE_RANGE.inc(by: data.startIndex)]) }
        set { data.replaceSubrange(VD_LOGICAL_BLOCK_SIZE_RANGE.inc(by: data.startIndex), with: newValue.bothEndianBytes) }
    }

    /// Path Table Size as defined in ECMA-119 8.4.13. This is the size of the path table in bytes.
    public var pathTableSize: UInt32 {
        get { UInt32(fromBothEndian: data[VD_PATH_TABLE_SIZE_RANGE.inc(by: data.startIndex)]) }
        set { data.replaceSubrange(VD_PATH_TABLE_SIZE_RANGE.inc(by: data.startIndex), with: newValue.bothEndianBytes) }
    }

    /// Location (LBA) of the first L-Path Table as defined in ECMA-119 8.4.14
    public var lPathTableLocation: UInt32 {
        get { UInt32(data[VD_L_PATH_TABLE_LOC_RANGE.inc(by: data.startIndex)], littleEndian: true) }
        set { data.replaceSubrange(VD_L_PATH_TABLE_LOC_RANGE.inc(by: data.startIndex), with: newValue.littleEndianBytes) }
    }

    /// Location (LBA) of the optional second L-Path Table as defined in ECMA-119 8.4.15
    public var lOptionalPathTableLocation: UInt32 {
        get { UInt32(data[VD_OPT_L_PATH_TABLE_LOC_RANGE.inc(by: data.startIndex)], littleEndian: true) }
        set { data.replaceSubrange(VD_OPT_L_PATH_TABLE_LOC_RANGE.inc(by: data.startIndex), with: newValue.littleEndianBytes) }
    }

    /// Location (LBA) of the first M-Path Table as defined in ECMA-119 8.4.16
    public var mPathTableLocation: UInt32 {
        get { UInt32(data[VD_M_PATH_TABLE_LOC_RANGE.inc(by: data.startIndex)], littleEndian: false) }
        set { data.replaceSubrange(VD_M_PATH_TABLE_LOC_RANGE.inc(by: data.startIndex), with: newValue.bigEndianBytes) }
    }

    /// Location (LBA) of the optional second M-Path Table as defined in ECMA-119 8.4.17
    public var mOptionalPathTableLocation: UInt32 {
        get { UInt32(data[VD_OPT_M_PATH_TABLE_LOC_RANGE.inc(by: data.startIndex)], littleEndian: false) }
        set { data.replaceSubrange(VD_OPT_M_PATH_TABLE_LOC_RANGE.inc(by: data.startIndex), with: newValue.bigEndianBytes) }
    }

    /// Directory Record for the root directory as defined in ECMA-119 8.4.18
    public var rootDirectory: DirectoryRecord {
        get { DirectoryRecord(from: data[VD_ROOT_DIR_RANGE.inc(by: data.startIndex)]) }
        set { data.replaceSubrange(VD_ROOT_DIR_RANGE.inc(by: data.startIndex), with: newValue.serialize()) }
    }

    /// Volume Set Identifier as defined in ECMA-119 8.4.19.
    public var volumeSetIdentifier: String {
        get { String.deserialize(data[VD_VOL_SET_ID_RANGE.inc(by: data.startIndex)], encoding) }
        set { data.replaceSerializedString(VD_VOL_SET_ID_RANGE.inc(by: data.startIndex), with: newValue, encoding: encoding) }
    }

    /// Publisher Identifier as defined in ECMA-119 8.4.20.
    public var publisherIdentifier: IdentifierOrFile {
        get { IdentifierOrFile.deserialize(data[VD_PUBLISHER_ID_RANGE.inc(by: data.startIndex)], encoding) }
        set { data.replaceSerializedIdOrFile(VD_PUBLISHER_ID_RANGE.inc(by: data.startIndex), with: newValue, encoding: encoding) }
    }

    /// Data Preparer Identifier as defined in ECMA-119 8.4.21.
    public var dataPreparerIdentifier: IdentifierOrFile {
        get { IdentifierOrFile.deserialize(data[VD_DATA_PREPARER_ID_RANGE.inc(by: data.startIndex)], encoding) }
        set { data.replaceSerializedIdOrFile(VD_DATA_PREPARER_ID_RANGE.inc(by: data.startIndex), with: newValue, encoding: encoding) }
    }

    /// Application Identifier as defined in ECMA-119 8.4.22.
    public var applicationIdentifier: IdentifierOrFile {
        get { IdentifierOrFile.deserialize(data[VD_APP_ID_RANGE.inc(by: data.startIndex)], encoding) }
        set { data.replaceSerializedIdOrFile(VD_APP_ID_RANGE.inc(by: data.startIndex), with: newValue, encoding: encoding) }
    }

    /// Copyright File Identifier as defined in ECMA-119 8.4.23.
    public var copyrightFileIdentifier: String {
        get { String.deserialize(data[VD_COPYRIGHT_FILE_ID_RANGE.inc(by: data.startIndex)], encoding) }
        set { data.replaceSerializedString(VD_COPYRIGHT_FILE_ID_RANGE.inc(by: data.startIndex), with: newValue, encoding: encoding) }
    }

    /// Abstract File Identifier as defined in ECMA-119 8.4.24.
    public var abstractFileIdentifier: String {
        get { String.deserialize(data[VD_ABSTRACT_FILE_ID_RANGE.inc(by: data.startIndex)], encoding) }
        set { data.replaceSerializedString(VD_ABSTRACT_FILE_ID_RANGE.inc(by: data.startIndex), with: newValue, encoding: encoding) }
    }

    /// Bibliographic File Identifier as defined in ECMA-119 8.4.25.
    public var bibliographicFileIdentifier: String {
        get { String.deserialize(data[VD_BIBLIOGRAPHIC_FILE_ID_RANGE.inc(by: data.startIndex)], encoding) }
        set { data.replaceSerializedString(VD_BIBLIOGRAPHIC_FILE_ID_RANGE.inc(by: data.startIndex), with: newValue, encoding: encoding) }
    }

    /// Date and Time at which the information in the volume was created, as defined in ECMA-119 8.4.26.
    public var creationDate: Date? {
        get { Date.decode(from: data[VD_VOL_CREATION_DATE_TIME_RANGE.inc(by: data.startIndex)], format: .format17B) }
        set { data.replaceSubrange(VD_VOL_CREATION_DATE_TIME_RANGE.inc(by: data.startIndex), with: newValue.iso9660Format17B) }
    }

    /// Date and Time which the information in the volume was last modified, as defined in ECMA-119 8.4.27.
    /// If this is not specified, the information shall not be regarded as obsolete.
    public var modificationDate: Date? {
        get { Date.decode(from: data[VD_VOL_MOD_DATE_TIME_RANGE.inc(by: data.startIndex)], format: .format17B) }
        set { data.replaceSubrange(VD_VOL_MOD_DATE_TIME_RANGE.inc(by: data.startIndex), with: newValue.iso9660Format17B) }
    }

    /// Date and Time which the information in the volume can be considered obsolete, as defined in ECMA-119 8.4.28.
    ///
    /// This is effectively a "not after" date, and as such depends upon the reading program as the enforcer.
    public var expirationDate: Date? {
        get { Date.decode(from: data[VD_VOL_EXPIRATION_DATE_TIME_RANGE.inc(by: data.startIndex)], format: .format17B) }
        set { data.replaceSubrange(VD_VOL_EXPIRATION_DATE_TIME_RANGE.inc(by: data.startIndex), with: newValue.iso9660Format17B) }
    }

    /// Date and Time of volume after which the information in this volume can be used, as defined in ECMA-119 8.4.29.
    /// If not specified, then the information can be used at once.
    ///
    /// This is effectively a "not before" date, and as such depends upon the reading program as the enforcer.
    public var effectiveDate: Date? {
        get { Date.decode(from: data[VD_VOL_EFFECTIVE_DATE_TIME_RANGE.inc(by: data.startIndex)], format: .format17B) }
        set { data.replaceSubrange(VD_VOL_EFFECTIVE_DATE_TIME_RANGE.inc(by: data.startIndex), with: newValue.iso9660Format17B) }
    }

    /// File Structure Version as defined in ECMA-119 8.4.30. Is 1 for Primary/Supplementary Volume Descriptors, but is 2
    /// for Enhanced Volume Descriptors.
    public var fileStructureVersion: UInt8 {
        get { data[data.startIndex + VD_FILE_STRUCTURE_VERSION_IDX] }
        set { data[data.startIndex + VD_FILE_STRUCTURE_VERSION_IDX] = newValue }
    }

    /// Application Use as defined in ECMA-119 8.4.32. This contents of this field is not defined by the spec, but the
    /// field must be at most 512 bytes in size.
    public var applicationUse: Data {
        get { data[VD_APP_USE_RANGE.inc(by: data.startIndex)] }
        set { data.replaceVariableSubrange(VD_APP_USE_RANGE.inc(by: data.startIndex), with: newValue) }
    }

    /// True if this is a Primary Volume Descriptor, false otherwise.
    public var isPrimary: Bool { type == 1 }

    /// True if this is a Supplementary Volume Descriptor, false otherwise.
    public var isSupplementary: Bool { type == 2 && version == 1 }

    /// True if this is an Enhanced Volume Descriptor, false otherwise.
    public var isEnhanced: Bool { type == 2 && version == 2 }

    /// Initialize a new Volume Descriptor of the given type and version.
    /// - Parameter type: The type of the Volume Descriptor
    /// - Parameter version: The version of the Volume Descriptor
    /// - Parameter encoding: The encoding to use for strings. Default depends upon `type`: `ascii` for `type=1` and `utf16BigEndian`
    ///                      for all others.
    internal init(type: UInt8, version: UInt8, encoding: String.Encoding? = nil) {
        self.data = Data(count: 2048)
        self.data.replaceSubrange(VD_MAGIC_RANGE, with: CD001) // Standard Identifier
        self.encoding = encoding ?? (type == 1 ? .ascii : .utf16BigEndian)
        self.type = type
        self.version = version
        self.systemIdentifier = DEFAULT_SYSTEM_IDENTIFIER
        self.volumeSetSize = 1
        self.volumeSequenceNumber = 1
        self.logicalBlockSize = DEFAULT_BLOCK_SIZE
        self.applicationIdentifier = .identifier("ISO9660/SWIFT BY AMOD MALVIYA")
        if self.encoding == .utf16BigEndian {
            self.escapeSequences = Data([0x25, 0x2f, 0x45])
        } else if self.encoding == .utf8 {
            self.escapeSequences = Data([0x25, 0x2f, 0x49])
        }
    }

    /// Initialize a new Volume Descriptor from the given data.
    /// - Parameter data: The data to initialize from. Must be at least 2048 bytes in size.
    internal init?(from data: Data) {
        guard data.count >= 2048 else { return nil }
        guard data[VD_MAGIC_RANGE.inc(by: data.startIndex)] == CD001 else { return nil }

        let type = data[data.startIndex + VD_TYPE_IDX]
        guard type == 1 || type == 2 else { return nil }

        let escapeSequences = data.subdata(in: VD_ESCAPE_SEQ_RANGE)

        var encoding: String.Encoding = .ascii
        if type == 2 {
            // by default we use UTF-16 Big Endian for type 2
            encoding = .utf16BigEndian
            // but allow it to be overridden by known escape sequences
            let escIdx = escapeSequences[0] == 0x1b ? 0 : -1 // we ignore the opening ESC of the sequence
            if escapeSequences[escIdx + 1] == 0x25 {
                let e0 = escapeSequences[escIdx + 2]
                let e1 = escapeSequences[escIdx + 3]
                if e0 == 0x47 || (e0 == 0x2f && e1 == 0x47) || (e0 == 0x2f && e1 == 0x48) || (e0 == 0x2f && e1 == 0x49) {
                    encoding = .utf8
                } else if e0 == 0x2f && (e1 == 0x40 || e1 == 0x43 || e1 == 0x45 || e1 == 0x4a || e1 == 0x4b || e1 == 0x4c) {
                    encoding = .utf16BigEndian
                }
                // we don't support any other encoding
            }
        }

        self.data = data.count == 2048 ? data : data[(0..<2048).inc(by: data.startIndex)]
        self.encoding = encoding
    }

    /// Validates the volume descriptor for spec adherence.
    /// - Parameter charsetValidation: If true, the charset validation is performed, otherwise it is skipped.
    /// - Throws: `SpecError` if the descriptor is invalid.
    public func validate(charsetValidation: Bool) throws {
        guard logicalBlockSize > 0 && logicalBlockSize.nonzeroBitCount == 1 else {
            throw SpecError.invalidLogicalBlockSize(size: logicalBlockSize)
        }
        guard applicationUse.count <= 512 else {
            throw SpecError.invalidApplicationUseSize(size: UInt32(applicationUse.count))
        }

        // we do the charset validation only when asked for
        if charsetValidation {
            guard systemIdentifier.isAStr else {
                throw SpecError.invalidIdentifier(field: "systemIdentifier", id: systemIdentifier)
            }
            guard volumeIdentifier.isDStr else {
                throw SpecError.invalidIdentifier(field: "volumeIdentifier", id: volumeIdentifier)
            }
            guard volumeSetIdentifier.isDStr else {
                throw SpecError.invalidIdentifier(field: "volumeSetIdentifier", id: volumeSetIdentifier)
            }
            try publisherIdentifier.validateIdentifier("publisherIdentifier") { $0.isAStr }
            try dataPreparerIdentifier.validateIdentifier("dataPreparerIdentifier") { $0.isAStr }
            try applicationIdentifier.validateIdentifier("applicationIdentifier") { $0.isAStr }
            guard copyrightFileIdentifier.hasOnlyDOrSepChars else {
                throw SpecError.invalidIdentifier(field: "copyrightFileIdentifier", id: copyrightFileIdentifier)
            }
            guard abstractFileIdentifier.hasOnlyDOrSepChars else {
                throw SpecError.invalidIdentifier(field: "abstractFileIdentifier", id: abstractFileIdentifier)
            }
            guard bibliographicFileIdentifier.hasOnlyDOrSepChars else {
                throw SpecError.invalidIdentifier(field: "bibliographicFileIdentifier", id: bibliographicFileIdentifier)
            }
        }
    }

    /// Serialize the volume descriptor to a byte buffer.
    public func serialize() -> Data {
        return data
    }
}

/// Some identifiers can be either an identifier or a file name. This enum is used to represent that
public enum IdentifierOrFile: Equatable {
    /// An identifier enclosing the associated value
    case identifier(String)
    /// The associated value is a file name which contains the actual identifier
    case file(String)
    /// An empty identifier
    case empty

    /// Serialize the identifier or file name to the given length.
    /// - Parameter length: The length to serialize to.
    /// - Parameter encoding: The encoding to use.
    /// - Returns: The serialized identifier or file name as a byte buffer.
    internal func serialize(_ length: Int, _ encoding: String.Encoding) -> Data {
        switch self {
        case .identifier(let id):
            return id.serialize(length, encoding)
        case .file(let file):
            return "_\(file)".serialize(length, encoding)
        case .empty:
            return String(FILLER_CHAR).serialize(length, encoding)
        }
    }

    /// Deserialize an identifier or file name from the given bytes.
    /// - Parameter data: The byte buffer to deserialize from.
    /// - Parameter encoding: The encoding to use.
    /// - Returns: The identifier or file name.
    internal static func deserialize(_ data: Data, _ encoding: String.Encoding, _ forceFile: Bool = false) -> IdentifierOrFile {
        let id = String.deserialize(data, encoding)
        if id.isEmpty {
            return .empty
        } else if forceFile {
            return .file(id)
        } else if id.hasPrefix("_") {
            return .file(String(id.dropFirst()))
        } else {
            return .identifier(id)
        }
    }

    /// Validate the identifier or file name for spec adherence.
    /// - Parameter field: The name of the field being validated.
    /// - Parameter isIdValid: A closure that returns true if the identifier is valid.
    func validateIdentifier(_ field: String, _ isIdValid: (String) -> Bool) throws {
        switch self {
        case .identifier(let id):
            if !isIdValid(id) {
                throw SpecError.invalidIdentifier(field: field, id: id)
            }
        case .file(let file):
            guard file.isDStr else {
                throw SpecError.invalidIdentifier(field: field, id: file)
            }
        case .empty:
            break
        }
    }
}

// MARK: - Volume Descriptor Field Locations
// as specified in ECMA-119 Table 4 and Table 6

private let VD_TYPE_IDX = 0
private let VD_MAGIC_RANGE = 1..<6
private let VD_VERSION_IDX = 6
private let VD_VOL_FLAGS_IDX = 7
private let VD_SYSTEM_ID_RANGE = 8..<40
private let VD_VOL_ID_RANGE = 40..<72
private let VD_VOL_SPACE_SIZE_RANGE = 80..<88
private let VD_ESCAPE_SEQ_RANGE = 88..<120
private let VD_VOL_SET_SIZE_RANGE = 120..<124
private let VD_VOL_SEQ_NUM_RANGE = 124..<128
private let VD_LOGICAL_BLOCK_SIZE_RANGE = 128..<132
private let VD_PATH_TABLE_SIZE_RANGE = 132..<140
private let VD_L_PATH_TABLE_LOC_RANGE = 140..<144
private let VD_OPT_L_PATH_TABLE_LOC_RANGE = 144..<148
private let VD_M_PATH_TABLE_LOC_RANGE = 148..<152
private let VD_OPT_M_PATH_TABLE_LOC_RANGE = 152..<156
private let VD_ROOT_DIR_RANGE = 156..<190
private let VD_VOL_SET_ID_RANGE = 190..<318
private let VD_PUBLISHER_ID_RANGE = 318..<446
private let VD_DATA_PREPARER_ID_RANGE = 446..<574
private let VD_APP_ID_RANGE = 574..<702
private let VD_COPYRIGHT_FILE_ID_RANGE = 702..<739
private let VD_ABSTRACT_FILE_ID_RANGE = 739..<776
private let VD_BIBLIOGRAPHIC_FILE_ID_RANGE = 776..<813
private let VD_VOL_CREATION_DATE_TIME_RANGE = 813..<830
private let VD_VOL_MOD_DATE_TIME_RANGE = 830..<847
private let VD_VOL_EXPIRATION_DATE_TIME_RANGE = 847..<864
private let VD_VOL_EFFECTIVE_DATE_TIME_RANGE = 864..<881
private let VD_FILE_STRUCTURE_VERSION_IDX = 882
private let VD_APP_USE_RANGE = 883..<1395
