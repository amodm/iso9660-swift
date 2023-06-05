import Foundation

/// A volume descriptor as defined in ECMA-119 8.1. These describe the top level structure of
/// an ISO 9660 volume, and a volume contains multiple descriptors, each serving a different
/// purpose. The most important ones are those that describe the directory structure of the
/// volume.
///
/// An ISO 9660 volume contains a series of descriptors starting at the ``NUM_SYSTEM_SECTORS``,
/// each of which is represented by one of the variants of this enum. The series of descriptors
/// is terminated by a ``terminator`` descriptor.
///
/// Directory descriptors (those which capture a ``VolumeDirectoryDescriptor``) describe the
/// directory structure of the volume.
public enum VolumeDescriptor {
    /// Primary Volume Descriptor as defined in ECMA-119 8.4. This is the _original_ volume descriptor, but
    /// suffers from a dated file naming scheme, and hence was updated via other mechanisms (see Overview).
    ///
    /// This descriptor stores its names in a very restricted ASCII encoding (see ECMA-119 7.4.1), and filenames
    /// are limited to 8.3 characters (3 for the extension). To support larger character sets, this was later
    /// extended by repurposing the ``VolumeDirectoryDescriptor/systemUse`` field to store SUSP information (
    /// see ``SUSPArea`` and ``SUSPEntry``). If SUSP information is not present, this descriptor will yield
    /// very dated (but fully backwards compatible) names.
    ///
    /// If you encounter a volume without SUSP information in its primary descriptor, you should use ``supplementary``
    /// or ``enhanced`` descriptors to get the correct names.
    case primary(VolumeDirectoryDescriptor)

    /// Supplementary Volume Descriptor as defined in ECMA-119 8.5. Also known as Joliet, this was introduced
    /// by Microsoft, and encodes its names in UCS-2 encoding.
    case supplementary(VolumeDirectoryDescriptor)
    /// Enhanced Volume Descriptor as defined in ECMA-119 8.5. This is like the ``supplementary``
    /// descriptor, but with custom characterset support (via ``VolumeDirectoryDescriptor/escapeSequences``).
    case enhanced(VolumeDirectoryDescriptor)
    /// Boot Descriptor as defined in ECMA-119 8.2
    case boot(VolumeBootDescriptor)
    /// Volume Partition Descriptor as defined in ECMA-119 8.6
    case partition(VolumePartitionDescriptor)
    /// Volume Descriptor Set Terminator as defined in ECMA-119 8.3. This is used to mark the
    /// end of the volume descriptor set, i.e. no more descriptors are defined after this.
    case terminator
    /// Generic Volume Descriptor, for which we don't have semantic understanding yet.
    case generic(VolumeGenericDescriptor)

    /// Volume Descriptor Type as defined in ECMA-119
    var type: UInt8 {
        switch self {
        case .primary(let x), .supplementary(let x), .enhanced(let x):
            return x.type
        case .boot(let x):
            return x.type
        case .partition(let x):
            return x.type
        case .terminator:
            return 0xff
        case .generic(let x):
            return x.type
        }
    }

    /// Volume Descriptor Version as defined in ECMA-119
    public var version: UInt8 {
        switch self {
        case .primary(let x), .supplementary(let x), .enhanced(let x):
            return x.version
        case .boot(let x):
            return x.version
        case .partition(let x):
            return x.version
        case .terminator:
            return 1
        case .generic(let x):
            return x.version
        }
    }

    /// Validates the volume descriptor for spec adherence.
    /// - Throws: `SpecError` if the descriptor is invalid.
    public func validate() throws {
        switch self {
        case .primary(let record):
            try record.validate(charsetValidation: true)
        case .supplementary(let record):
            // we do not validate charset because as per ECMA-119 7.4.2, a1/d1-characters are
            // a matter of agreement between originator and recipient of the volume
            try record.validate(charsetValidation: false)
        case .enhanced(let record):
            // we do not validate charset because as per ECMA-119 7.4.2, a1/d1-characters are
            // a matter of agreement between originator and recipient of the volume
            try record.validate(charsetValidation: false)
        case .boot(let record):
            try record.validate()
        case .partition(let record):
            try record.validate()
        case .terminator:
            break
        case .generic:
            break
        }
    }

    /// Serializes this volume descriptor to a `Data` object.
    public func serialize() -> Data {
        switch self {
        case .primary(let record):
            return record.serialize()
        case .supplementary(let record):
            return record.serialize()
        case .enhanced(let record):
            return record.serialize()
        case .boot(let record):
            return record.serialize()
        case .partition(let record):
            return record.serialize()
        case .terminator:
            var data = Data(repeating: 0, count: 2048)
            data[0] = 0xff
            data.replaceSubrange((0..<CD001.count).inc(by: 1), with: CD001)
            data[CD001.count + 1] = 1
            return data
        case .generic(let record):
            return record.serialize()
        }
    }

    /// Loads a volume descriptor from `data`
    /// - Parameter data: The data to load from.
    /// - Returns: The loaded volume descriptor, or nil if the data does not represent a valid volume descriptor.
    static func from(_ data: Data) -> VolumeDescriptor? {
        if let vdd = VolumeDirectoryDescriptor(from: data) {
            if vdd.isPrimary {
                return .primary(vdd)
            } else if vdd.isSupplementary {
                return .supplementary(vdd)
            } else if vdd.isEnhanced {
                return .enhanced(vdd)
            }
        }
        if let vbd = VolumeBootDescriptor(from: data) {
            return .boot(vbd)
        }
        if let vpd = VolumePartitionDescriptor(from: data) {
            return .partition(vpd)
        }
        if let vgd = VolumeGenericDescriptor(from: data) {
            return vgd.type == 0xff ? .terminator : .generic(vgd)
        }
        return nil
    }
}

let DEFAULT_SECTOR_SIZE: UInt16 = 2048
let DEFAULT_BLOCK_SIZE: UInt16 = 2048

/// The default system identifier to use when creating a new volume. We map this to the current platform.
#if os(Linux)
    let DEFAULT_SYSTEM_IDENTIFIER = "LINUX"
#elseif os(Windows)
    let DEFAULT_SYSTEM_IDENTIFIER = "WINDOWS"
#else
    let DEFAULT_SYSTEM_IDENTIFIER = "MACOS"
#endif

/// Standard Identifier magic, as defined in ECMA-119 sec 8.3.2
internal let CD001 = "CD001".serialize(5, .ascii)[...]
