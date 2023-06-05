import Foundation

extension Optional where Wrapped == Date {
    /// 17 bytes ascii datetime format as specified in ECMA-119 8.4.26.1
    var iso9660Format17B: Data {
        guard let date = self else {
            return Data(count: 17)
        }
        return date.iso9660Format17B
    }

    /// 7 bytes binary datetime format as specified in ECMA-119 9.1.5
    var iso9660Format7B: Data {
        guard let date = self else {
            return Data(count: 7)
        }
        return date.iso9660Format7B
    }
}

extension Date {
    /// 17 bytes ascii datetime format as specified in ECMA-119 8.4.26.1
    var iso9660Format17B: Data {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond, .timeZone], from: self)

        var bytes = Data(count: 17)
        bytes.replaceSubrange(0..<4, with: String(format: "%04d", components.year ?? 2023).utf8)
        bytes.replaceSubrange(4..<6, with: String(format: "%02d", components.month ?? 1).utf8)
        bytes.replaceSubrange(6..<8, with: String(format: "%02d", components.day ?? 1).utf8)
        bytes.replaceSubrange(8..<10, with: String(format: "%02d", components.hour ?? 0).utf8)
        bytes.replaceSubrange(10..<12, with: String(format: "%02d", components.minute ?? 0).utf8)
        bytes.replaceSubrange(12..<14, with: String(format: "%02d", components.second ?? 0).utf8)
        bytes.replaceSubrange(14..<16, with: String(format: "%02d", (components.nanosecond ?? 0) / 10_000_000).utf8)
        bytes[16] = UInt8(((components.timeZone?.secondsFromGMT() ?? 0) / 900) & 0xff)

        return bytes
    }

    /// 7 bytes binary datetime format as specified in ECMA-119 9.1.5
    var iso9660Format7B: Data {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .timeZone], from: self)

        var bytes = Data(count: 7)
        bytes[0] = UInt8((components.year ?? 2023) - 1900)
        bytes[1] = UInt8(components.month ?? 1)
        bytes[2] = UInt8(components.day ?? 1)
        bytes[3] = UInt8(components.hour ?? 1)
        bytes[4] = UInt8(components.minute ?? 0)
        bytes[5] = UInt8(components.second ?? 0)
        bytes[6] = UInt8(((components.timeZone?.secondsFromGMT() ?? 0) / 900) & 0xff)

        return bytes
    }

    /// Parses and returns a date from the given bytes using the given format
    /// - Parameter from: The bytes to parse
    /// - Parameter format: The format to use
    static func decode(from: Data, format: ISO9660DateFormat) -> Date? {
        switch format {
        case .format7B:
            return decode7B(from)
        case .format17B:
            return decode17B(from)
        }
    }

    /// Parses and returns a date from the given 7 bytes binary datetime format as specified in ECMA-119 9.1.5.
    /// - Parameter from: The bytes to parse (must be exactly 7 bytes long)
    /// - Returns: The parsed date or nil if the date is all zeros
    private static func decode7B(_ from: Data) -> Date? {
        guard from.count >= 7 else {
            return nil
        }

        let year = Int(from[from.startIndex])
        let month = Int(from[from.startIndex + 1])
        let day = Int(from[from.startIndex + 2])
        let hour = Int(from[from.startIndex + 3])
        let minute = Int(from[from.startIndex + 4])
        let second = Int(from[from.startIndex + 5])
        let tzOffsetByte = Int(from[from.startIndex + 6])
        let timeZoneOffset = tzOffsetByte * 900

        if year == 0 && month == 0 && day == 0 && hour == 0 && minute == 0 && second == 0 && tzOffsetByte == 0 {
            return nil
        }

        var components = DateComponents()
        components.year = year + 1900
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        components.timeZone = TimeZone(secondsFromGMT: timeZoneOffset)

        return Calendar.current.date(from: components)
    }

    /// Parses and returns a date from the given 17 bytes ascii datetime format as specified in ECMA-119 8.4.26.1
    /// - Parameter from: The bytes to parse (must be exactly 17 bytes long)
    /// - Returns: The parsed date or nil if the date is all zeros
    private static func decode17B(_ from: Data) -> Date? {
        guard from.count >= 17 else {
            return nil
        }

        let year = Int(String(bytes: from[(0..<4).inc(by: from.startIndex)], encoding: .ascii) ?? "0")
        let month = Int(String(bytes: from[(4..<6).inc(by: from.startIndex)], encoding: .ascii) ?? "0")
        let day = Int(String(bytes: from[(6..<8).inc(by: from.startIndex)], encoding: .ascii) ?? "0")
        let hour = Int(String(bytes: from[(8..<10).inc(by: from.startIndex)], encoding: .ascii) ?? "0")
        let minute = Int(String(bytes: from[(10..<12).inc(by: from.startIndex)], encoding: .ascii) ?? "0")
        let second = Int(String(bytes: from[(12..<14).inc(by: from.startIndex)], encoding: .ascii) ?? "0")
        let tzOffsetByte = Int(from[from.startIndex + 16])
        let timeZoneOffset = tzOffsetByte * 900

        if year == 0 && month == 0 && day == 0 && hour == 0 && minute == 0 && second == 0 && tzOffsetByte == 0 {
            return nil
        }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        components.timeZone = TimeZone(secondsFromGMT: timeZoneOffset)

        return Calendar.current.date(from: components)
    }
}

/// The date representations used in the ISO9660 filesystem
enum ISO9660DateFormat {
    case format7B
    case format17B
}
