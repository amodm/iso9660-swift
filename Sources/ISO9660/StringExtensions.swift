import Foundation

extension String {
    /// Serialize this string to bytes based on `encoding`. The bytes are clipped to `maxLength` (if provided), making
    /// sure to clip at a well formed character boundary.
    /// - Parameter encoding: The string encoding to use
    /// - Parameter maxLength: The maximum length of the resulting byte array
    /// - Returns: A byte buffer of size less than or equal to `maxLength`
    func serializeClipped(_ encoding: String.Encoding, _ maxLength: Int? = nil) -> Data {
        if let maxLength = maxLength {
            var bytes = Data(count: maxLength)
            var offset = 0
            for char in self.unicodeScalars {
                if let encodedChar = String(char).data(using: encoding) {
                    let chEnd = encodedChar.count + offset
                    if chEnd <= maxLength {
                        bytes.replaceSubrange(offset..<chEnd, with: encodedChar)
                        offset = chEnd
                    } else {
                        break
                    }
                }
            }
            return offset < maxLength ? bytes[0..<offset] : bytes
        } else {
            return self.data(using: encoding) ?? Data([])
        }
    }

    /// Converts the string to a byte array padded with filler characters to the given length.
    /// - Parameters:
    ///   - length: The length of the resulting byte array. Bytes may be padded or trimmed to ensure this
    ///   - encoding: The string encoding to use
    ///   - filler: The filler character to use
    /// - Returns: A byte buffer of size `length`
    func serialize(_ length: Int, _ encoding: String.Encoding, filler: Character = FILLER_CHAR) -> Data {
        var bytes = Data(count: length)
        let fillerBytes = String(filler).data(using: encoding) ?? Data([0])
        let fillerLen = fillerBytes.count
        var offset = 0
        for char in self.unicodeScalars {
            if let encodedChar = String(char).data(using: encoding) {
                let chEnd = encodedChar.count + offset
                if chEnd <= length {
                    bytes.replaceSubrange(offset..<chEnd, with: encodedChar)
                    offset = chEnd
                } else {
                    break
                }
            }
        }
        while offset < length {
            let fillerEnd = offset + fillerLen
            if fillerEnd > length {
                bytes.replaceSubrange(offset..<length, with: Array(repeating: 0, count: length - offset))
                break
            } else {
                bytes.replaceSubrange(offset..<fillerEnd, with: fillerBytes)
                offset = fillerEnd
            }
        }
        return bytes
    }

    /// Deserializes a String from the given bytes, trimming off trailing filler characters.
    /// - Parameters:
    ///   - data: the byte buffer to deserialize from
    ///   - encoding: The string encoding to use
    ///   - filler: The filler character to use
    /// - Returns: the deserialized String
    static func deserialize(_ data: any Collection<UInt8>, _ encoding: String.Encoding, _ filler: Character = FILLER_CHAR) -> String {
        guard let str = String(bytes: data, encoding: encoding) else {
            return ""
        }

        if let lastNonFillerCharIdx = str.lastIndex(where: { $0 != filler }) {
            return String(str[...lastNonFillerCharIdx])
        } else {
            return str
        }
    }

    var isAStr: Bool {
        return hasOnlyCharacters(A_CHARS)
    }

    var isDStr: Bool {
        return hasOnlyCharacters(D_CHARS)
    }

    var hasOnlyDOrSepChars: Bool {
        return hasOnlyCharacters(D_CHARS, CharacterSet(charactersIn: ".;"))
    }

    private func hasOnlyCharacters(_ characterSet: CharacterSet, _ otherCharacterSets: CharacterSet...) -> Bool {
        var characterSet = characterSet
        for otherCharacterSet in otherCharacterSets {
            characterSet = characterSet.union(otherCharacterSet)
        }
        return self.rangeOfCharacter(from: characterSet.inverted) == nil
    }

    /// Assuming this string to be a path, return the individual components of that path.
    var pathComponents: [String] {
        return self
            .trimmingCharacters(in: PATH_SEP_CHARSET)
            .split(separator: DEFAULT_PATH_SEPARATOR)
            .map { String($0) }
    }

    /// Returns the file path extension of this string, or nil if it has no extension.
    var fileExtension: String? {
        if let lastComponent = pathComponents.last {
            if lastComponent.contains(".") {
                let arr = lastComponent.split(separator: ".", omittingEmptySubsequences: false)
                return arr.count > 1 ? String(arr.last!) : ""
            }
        }
        return nil
    }

    /// Returns the file name of this string, without the extension.
    var fileNameWithoutExtension: String {
        if let fileName = self.pathComponents.last {
            if let fileNameWithoutExtension = fileName.split(separator: ".", omittingEmptySubsequences: false).first {
                return String(fileNameWithoutExtension)
            } else {
                return fileName
            }
        } else {
            return ""
        }
    }

    /// Replaces all characters in this string that are not in `charset` with `replacement`.
    func replaceNonCharset(_ charset: CharacterSet, _ replacement: Character) -> String {
        var s = String()
        for us in unicodeScalars {
            if charset.contains(us) {
                s.unicodeScalars.append(us)
            } else {
                s.unicodeScalars.append(contentsOf: replacement.unicodeScalars)
            }
        }
        return s
    }
}

/// Filler character as defined in ECMA-119 7.4.3.2
let FILLER: UInt8 = 0x20 // ASCII space
let FILLER_CHAR = Character(UnicodeScalar(FILLER))

/// Separator characters as defined in ECMA-119 7.4.3.1
let SEPARATOR1_CHAR = Character(UnicodeScalar(0x2e)) // ASCII period

/// Separator characters as defined in ECMA-119 7.4.3.1
let SEPARATOR2_CHAR = Character(UnicodeScalar(0x3b)) // ASCII semicolon

private let SEPARATOR_CHARS = CharacterSet(charactersIn: String("\(SEPARATOR1_CHAR)\(SEPARATOR2_CHAR)"))

/// d-characters as defined in ECMA-119 7.4.1
let D_CHARS = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")

/// a-characters as defined in ECMA-119 7.4.1
private let A_CHARS = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_ !\"%&'()*+,-./:;<=>?")

/// Just the filler character
private let FILLER_CHARACTER_SET = CharacterSet(charactersIn: String(Character(UnicodeScalar(FILLER))))

/// D_CHARS + SEPARATOR1 + SEPARATOR2
private let D_SEP1_SEP2_CHARS = D_CHARS.union(SEPARATOR_CHARS)

private let CTL_CODES_CHARS = CharacterSet(charactersIn: Range<Unicode.Scalar>(uncheckedBounds: (lower: Unicode.Scalar(0x0), upper: Unicode.Scalar(0x1f))))
private let C_CHARS = CTL_CODES_CHARS.union(CharacterSet(charactersIn: "*/:;?\\")).inverted
private let D1_SEP1_SEP2_CHARS = C_CHARS.union(SEPARATOR_CHARS)

/// Default path separator for the current platform.
#if os(Windows)
private let DEFAULT_PATH_SEPARATOR = Character("\\")
#else
private let DEFAULT_PATH_SEPARATOR = Character("/")
#endif
private let PATH_SEP_CHARSET = CharacterSet(charactersIn: String(DEFAULT_PATH_SEPARATOR))
