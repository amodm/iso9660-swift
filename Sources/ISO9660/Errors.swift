import Foundation

/// Specification related errors
public enum SpecError: Error, Equatable {
    /// The specified path is invalid.
    /// - Parameter path: The path that was invalid
    case invalidPath(path: String)

    /// Sector size was invalid. Sector size must be more than 0 and a power of 2
    /// - Parameter size: The invalid sector size
    case invalidSectorSize(size: UInt16)

    /// The specified identifier was invalid for this field, e.g. if `field` is `systemIdentifier`,
    /// then `id` must be an A-String
    /// - Parameters:
    ///   - field: The name of the field that was invalid
    ///   - id: The invalid identifier
    case invalidIdentifier(field: String, id: String)

    /// Logical Block Size was invalid. Logical Block Size must be more than 0 and a power of 2
    /// - Parameter size: The invalid logical block size
    case invalidLogicalBlockSize(size: UInt16)

    /// The Application Use field was invalid. The Application Use field must be at most 512 bytes long
    /// - Parameter size: The size of the Application Use field
    case invalidApplicationUseSize(size: UInt32)

    /// Invalid SUSP signature. The signature must be 2 bytes long
    /// - Parameter signature: The invalid signature
    case invalidSUSPSignature(signature: String)

    /// No valid volume directory descriptor was found
    case invalidVolumeDirectoryDescriptor

    /// Specification failure. A mandatory criteria was not met.
    /// - Parameter reason: The reason for the failure
    case preconditionFailed(reason: String)
}

/// API related errors. Used when the library API is invoked incorrectly
public enum APIError: Error {
    /// One of the arguments was invalid
    /// - Parameters:
    ///   - name: The name of the argument
    ///   - message: The reason the argument was invalid
    case invalidArgument(name: String, message: String)

    /// The specified image is invalid.
    case invalidImage

    /// An attempt was made to write after the writer was closed
    case writerClosed
}
