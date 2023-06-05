import Foundation

/// A generic volume descriptor, for which we don't know how to process the body.
public struct VolumeGenericDescriptor {
    private var data: Data

    /// Volume Descriptor Type.
    public var type: UInt8 {
        get { data[data.startIndex + VGD_TYPE_IDX] }
        set { data[data.startIndex + VGD_TYPE_IDX] = newValue }
    }

    /// Volume Descriptor Version.
    public var version: UInt8 {
        get { data[data.startIndex + VGD_VERSION_IDX] }
        set { data[data.startIndex + VGD_VERSION_IDX] = newValue }
    }

    /// The body of this descriptor.
    public var body: Data {
        get { data[VGD_BODY_RANGE.inc(by: data.startIndex)] }
        set { data.replaceVariableSubrange(VGD_BODY_RANGE.inc(by: data.startIndex), with: newValue) }
    }

    /// Initialize a new Volume Descriptor
    internal init(type: UInt8, version: UInt8) {
        self.data = Data(count: 2048)
        self.data.replaceSubrange(VGD_MAGIC_RANGE, with: CD001) // Standard Identifier
        self.type = 3
        self.version = 1
    }

    /// Initialize a new Volume Descriptor from the given data.
    /// - Parameter data: The data to initialize from. Must be at least 2048 bytes in size.
    internal init?(from data: Data) {
        guard data.count >= 2048 else { return nil }
        guard data[VGD_MAGIC_RANGE.inc(by: data.startIndex)] == CD001 else { return nil }
        guard data[data.startIndex + VGD_TYPE_IDX] > 3 else { return nil }
        self.data = data
    }

    /// Serializes this descriptor to a `Data` instance.
    public func serialize() -> Data {
        data
    }
}

// MARK: - Volume Descriptor Field Locations

private let VGD_TYPE_IDX = 0
private let VGD_MAGIC_RANGE = 1..<6
private let VGD_VERSION_IDX = 6
private let VGD_BODY_RANGE = 7..<2048