import Foundation

/// Volume Partition Descriptor as defined in ECMA-119 8.6
public struct VolumePartitionDescriptor {
    private var data: Data

    /// Volume Descriptor Type as defined in ECMA-119 8.6.1. This is 3 for Volume Partition Descriptors.
    public private(set) var type: UInt8 {
        get { data[data.startIndex + VPD_TYPE_IDX] }
        set { data[data.startIndex + VPD_TYPE_IDX] = newValue }
    }

    /// Volume Descriptor Version as defined in ECMA-119 8.6.3. This is 1 for Volume Partition Descriptors.
    public private(set) var version: UInt8 {
        get { data[data.startIndex + VPD_VERSION_IDX] }
        set { data[data.startIndex + VPD_VERSION_IDX] = newValue }
    }

    /// System Identifier as defined in ECMA-119 8.6.5. Must be an A-String.
    public var systemIdentifier: String {
        get { String.deserialize(data[VPD_SYSTEM_ID_RANGE.inc(by: data.startIndex)], .ascii) }
        set { data.replaceSerializedString(VPD_SYSTEM_ID_RANGE.inc(by: data.startIndex), with: newValue, encoding: .ascii) }
    }

    /// Partition Identifier as defined in ECMA-119 8.6.6. Must be a D-String.
    public var partitionIdentifier: String {
        get { String.deserialize(data[VPD_PARTITION_ID_RANGE.inc(by: data.startIndex)], .ascii) }
        set { data.replaceSerializedString(VPD_PARTITION_ID_RANGE.inc(by: data.startIndex), with: newValue, encoding: .ascii) }
    }

    /// Location (LBA) of the first sector of the partition as defined in ECMA-119 8.6.7
    public var partitionLocation: UInt32 {
        get { UInt32(fromBothEndian: data[VPD_PARTITION_LOC_RANGE.inc(by: data.startIndex)]) }
        set { data.replaceSubrange(VPD_PARTITION_LOC_RANGE.inc(by: data.startIndex), with: newValue.bothEndianBytes) }
    }

    /// Number of logical blocks in the partition as defined in ECMA-119 8.6.8
    public var partitionSizeInBlocks: UInt32 {
        get { UInt32(fromBothEndian: data[VPD_PARTITION_SIZE_RANGE.inc(by: data.startIndex)]) }
        set { data.replaceSubrange(VPD_PARTITION_SIZE_RANGE.inc(by: data.startIndex), with: newValue.bothEndianBytes) }
    }

    /// Use not specified in spec
    public var systemUse: Data {
        get { data[VPD_SYSTEM_USE_RANGE.inc(by: data.startIndex)] }
        set { data.replaceVariableSubrange(VPD_SYSTEM_USE_RANGE.inc(by: data.startIndex), with: newValue) }
    }

    /// Initialize a new Volume Partition Descriptor
    internal init() {
        self.data = Data(count: 2048)
        self.data.replaceSubrange(VPD_MAGIC_RANGE, with: CD001) // Standard Identifier
        self.type = 3
        self.version = 1
        self.systemIdentifier = DEFAULT_SYSTEM_IDENTIFIER
    }

    /// Initialize a new Volume Partition Descriptor from the given data.
    /// - Parameter data: The data to initialize from. Must be at least 2048 bytes in size.
    internal init?(from data: Data) {
        guard data.count >= 2048 else { return nil }
        guard data[VPD_MAGIC_RANGE.inc(by: data.startIndex)] == CD001 else { return nil }
        guard data[data.startIndex + VPD_TYPE_IDX] == 3 else { return nil }
        guard data[data.startIndex + VPD_VERSION_IDX] == 1 else { return nil }
        self.data = data
    }

    /// Validates the volume partition descriptor for spec adherence.
    /// - Throws: `SpecError` if the descriptor is invalid.
    public func validate() throws {
        guard systemIdentifier.isAStr else {
            throw SpecError.invalidIdentifier(field: "systemIdentifier", id: systemIdentifier)
        }
        guard partitionIdentifier.isDStr else {
            throw SpecError.invalidIdentifier(field: "partitionIdentifier", id: partitionIdentifier)
        }
    }

    /// Serializes the volume partition descriptor to a `Data` object.
    public func serialize() -> Data {
        data
    }
}

// MARK: - Volume Partition Descriptor Field Locations
// as specified in ECMA-119 Table 7

private let VPD_TYPE_IDX = 0
private let VPD_MAGIC_RANGE = 1..<6
private let VPD_VERSION_IDX = 6
private let VPD_SYSTEM_ID_RANGE = 8..<40
private let VPD_PARTITION_ID_RANGE = 40..<72
private let VPD_PARTITION_LOC_RANGE = 72..<80
private let VPD_PARTITION_SIZE_RANGE = 80..<88
private let VPD_SYSTEM_USE_RANGE = 88..<2048
