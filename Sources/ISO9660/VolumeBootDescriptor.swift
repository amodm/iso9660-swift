import Foundation

/// Volume Boot Descriptor as defined in ECMA-119 8.2
public struct VolumeBootDescriptor {
    private var data: Data

    /// Volume Descriptor Type as defined in ECMA-119 8.2.1. This is 0 for Boot Descriptors.
    public private(set) var type: UInt8 {
        get { data[data.startIndex + VBD_TYPE_IDX] }
        set { data[data.startIndex + VBD_TYPE_IDX] = newValue }
    }

    /// Volume Descriptor Version as defined in ECMA-119 8.2.3. This is 1 for Boot Descriptors.
    public private(set) var version: UInt8 {
        get { data[data.startIndex + VBD_VERSION_IDX] }
        set { data[data.startIndex + VBD_VERSION_IDX] = newValue }
    }

    /// System Identifier as defined in ECMA-119 8.2.4. Must be an A-String.
    public var systemIdentifier: String {
        get { String.deserialize(data[VBD_SYSTEM_ID_RANGE.inc(by: data.startIndex)], .ascii) }
        set { data.replaceSerializedString(VBD_SYSTEM_ID_RANGE.inc(by: data.startIndex), with: newValue, encoding: .ascii) }
    }

    /// Boot Identifier as defined in ECMA-119 8.6.6. Must be an A-String.
    public var bootIdentifier: String {
        get { String.deserialize(data[VBD_BOOT_ID_RANGE.inc(by: data.startIndex)], .ascii) }
        set { data.replaceSerializedString(VBD_BOOT_ID_RANGE.inc(by: data.startIndex), with: newValue, encoding: .ascii) }
    }

    /// Use not specified in spec
    public var systemUse: Data {
        get { data[VBD_SYSTEM_USE_RANGE.inc(by: data.startIndex)] }
        set { data.replaceVariableSubrange(VBD_SYSTEM_USE_RANGE.inc(by: data.startIndex), with: newValue) }
    }

    /// Initialize a new Volume Boot Descriptor
    internal init() {
        self.data = Data(count: 2048)
        self.data.replaceSubrange(VBD_MAGIC_RANGE, with: CD001) // Standard Identifier
        self.type = 3
        self.version = 1
        self.systemIdentifier = "EL TORITO SPECIFICATION"
    }

    /// Initialize a new Volume Boot Descriptor from the given data.
    /// - Parameter data: The data to initialize from. Must be at least 2048 bytes in size.
    internal init?(from data: Data) {
        guard data.count >= 2048 else { return nil }
        guard data[VBD_MAGIC_RANGE.inc(by: data.startIndex)] == CD001 else { return nil }
        guard data[data.startIndex + VBD_TYPE_IDX] == 0 else { return nil }
        guard data[data.startIndex + VBD_VERSION_IDX] == 1 else { return nil }
        self.data = data
    }

    /// Validates the volume boot descriptor for spec adherence.
    /// - Throws: `SpecError` if the descriptor is invalid.
    public func validate() throws {
        guard systemIdentifier.isAStr else {
            throw SpecError.invalidIdentifier(field: "systemIdentifier", id: systemIdentifier)
        }
        guard bootIdentifier.isAStr else {
            throw SpecError.invalidIdentifier(field: "bootIdentifier", id: bootIdentifier)
        }
    }

    /// Serializes the volume boot descriptor to a `Data` object.
    public func serialize() -> Data {
        data
    }
}

// MARK: - Volume Boot Descriptor Field Locations
// as specified in ECMA-119 Table 2

private let VBD_TYPE_IDX = 0
private let VBD_MAGIC_RANGE = 1..<6
private let VBD_VERSION_IDX = 6
private let VBD_SYSTEM_ID_RANGE = 7..<39
private let VBD_BOOT_ID_RANGE = 39..<71
private let VBD_SYSTEM_USE_RANGE = 71..<2048
