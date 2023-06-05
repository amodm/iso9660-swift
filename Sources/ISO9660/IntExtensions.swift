import Foundation

extension FixedWidthInteger {
    /// The little endian representation of this value. ECMA-119 7.2.1 and 7.3.1.
    var littleEndianBytes: Data {
        return withUnsafeBytes(of: littleEndian) { Data($0) }
    }

    /// The big endian representation of this value. ECMA-119 7.2.2 and 7.3.2.
    var bigEndianBytes: Data {
        return withUnsafeBytes(of: bigEndian) { Data($0) }
    }

    /// A concatenation of the little and big endian representations of this value. ECMA-119 7.2.3 and 7.3.3.
    var bothEndianBytes: Data {
        return self.littleEndianBytes + self.bigEndianBytes
    }

    /// Initializes the value from the little or big endian representation of `bytes`
    init(_ data: any ContiguousBytes, littleEndian: Bool = Int.isLittleEndian) {
        self = data.withUnsafeBytes {
            return littleEndian
                ? $0.loadUnaligned(as: Self.self).littleEndian
                : $0.loadUnaligned(as: Self.self).bigEndian
        }
    }

    /// Initializes the value from the both-bytes representation as specified in ECMA-119 7.2.3 and 7.3.3.
    init(fromBothEndian data: ContiguousBytes) {
        self = data.withUnsafeBytes {
            return $0.loadUnaligned(as: Self.self)
        }
    }
}

extension Int {
    /// True if the system is little endian, false otherwise
    static let isLittleEndian: Bool = 0x1.littleEndian == 0x1

    /// True if the system is big endian, false otherwise
    static let isBigEndian: Bool = !isLittleEndian
}
