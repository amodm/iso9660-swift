import Foundation

extension Data {
    /// Returns a padded/trimmed array to fit `length` bytes.
    ///
    /// - Parameter length: The length of the resulting array
    /// - Parameter filler: The filler byte to use
    /// - Returns: The padded/trimmed array
    func padded(_ length: Int, _ filler: UInt8 = 0) -> Data {
        if count == length {
            return self
        } else if count > length {
            // return trimmed if we're larger than requested length
            return self.prefix(length)
        } else {
            // else return padded with filler
            return self + Data(repeating: filler, count: length - count)
        }
    }

    /// Replaces the bytes in the given range with the given data, but while making sure that `data`
    /// is clipped or padded to fit `subrange`, using `filler` if required.
    ///
    /// - Parameter subrange: The range of bytes to replace
    /// - Parameter data: The data to replace the bytes with
    /// - Parameter filler: The filler byte to use
    mutating func replaceVariableSubrange(_ subrange: Range<Int>, with data: Data, filler: UInt8 = 0) {
        self.replaceSubrange(subrange, with: data.padded(subrange.count, filler))
    }

    /// Serialize a string into this byte buffer, padding or trimming as necessary.
    ///
    /// - Parameter str: The string to serialize
    /// - Parameter encoding: The string encoding to use
    /// - Parameter filler: The filler character to use
    mutating func replaceSerializedString(_ subrange: Range<Int>, with str: String, encoding: String.Encoding, filler: Character = FILLER_CHAR) {
        self.replaceSubrange(subrange, with: str.serialize(subrange.count, encoding, filler: filler))
    }

    /// Serialize a ``IdentifierOrFile`` into this byte buffer, padding or trimming as necessary.
    ///
    /// - Parameter idOrFile: The identifier to serialize.
    /// - Parameter encoding: The string encoding to use.
    mutating func replaceSerializedIdOrFile(_ subrange: Range<Int>, with idOrFile: IdentifierOrFile, encoding: String.Encoding) {
        self.replaceSubrange(subrange, with: idOrFile.serialize(subrange.count, encoding))
    }
}

extension Range where Bound == Int {
    /// Reduces the upper bound by the given amount, clamping to the lower bound.
    ///
    /// - Parameter by: The amount by which to reduce the upper bound
    /// - Returns: The reduced range
    @inlinable func reduceUpper(by: Int) -> Range<Bound> {
        return Range(uncheckedBounds: (lower: self.lowerBound, upper: Swift.max(self.lowerBound, self.upperBound - by)))
    }

    /// Returns a new range with the given offset added to both bounds.
    ///
    /// - Parameter delta: The offset to add to both bounds
    /// - Returns: The new range
    @inlinable func inc(by delta: Int) -> Range<Bound> {
        return Range(uncheckedBounds: (lower: self.lowerBound + delta, upper: self.upperBound + delta))
    }
}
