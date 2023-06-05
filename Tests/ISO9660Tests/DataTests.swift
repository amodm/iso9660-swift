import XCTest
@testable import ISO9660

final class DataTests: XCTestCase {
    func testPaddedOnSmallerData() {
        let data = Data([0, 1, 2, 3, 4, 5, 6, 7])[1..<6]
            .padded(7, 100)
        XCTAssertEqual(data, Data([1, 2, 3, 4, 5, 100, 100]))
    }

    func testPaddedOnBiggerData() {
        let data = Data([0, 1, 2, 3, 4, 5, 6, 7])[1..<6]
            .padded(3)
        XCTAssertEqual(data, Data([1, 2, 3]))
    }

    func testPaddedOnSameSizedData() {
        let data = Data([0, 1, 2, 3, 4, 5, 6, 7])[1..<6]
            .padded(5, 100)
        XCTAssertEqual(data, Data([1, 2, 3, 4, 5]))
    }

    func testReplaceVariableSubrangeWithLargerData() {
        var data = Data([0, 1, 2, 3, 4, 5, 6, 7])[1..<6]
        data.replaceVariableSubrange(2..<5, with: Data([12, 13, 14, 15, 16, 17]))
        XCTAssertEqual(data, Data([1, 12, 13, 14, 5]))
    }

    func testReplaceVariableSubrangeWithSmallerData() {
        var data = Data([0, 1, 2, 3, 4, 5, 6, 7])[1..<6]
        data.replaceVariableSubrange(2..<5, with: Data([12]), filler: 100)
        XCTAssertEqual(data, Data([1, 12, 100, 100, 5]))
    }

    func testReplaceVariableSubrangeWithEqualSizedData() {
        var data = Data([0, 1, 2, 3, 4, 5, 6, 7])[1..<6]
        data.replaceVariableSubrange(2..<5, with: Data([12, 13, 14]))
        XCTAssertEqual(data, Data([1, 12, 13, 14, 5]))
    }

    func testReplaceSerializedStringLargerSub() {
        var data = Data([0, 1, 2, 3, 4, 5, 6, 7])[1..<6]
        data.replaceSerializedString(2..<5, with: "abcdef", encoding: .ascii)
        XCTAssertEqual(data, Data([1, 0x61, 0x62, 0x63, 5]))
    }

    func testReplaceSerializedStringSmallerSub() {
        var data = Data([0, 1, 2, 3, 4, 5, 6, 7])[1..<6]
        data.replaceSerializedString(2..<5, with: "a", encoding: .ascii, filler: Character(" "))
        XCTAssertEqual(data, Data([1, 0x61, 0x20, 0x20, 5]))
    }

    func testReplaceSerializedStringEqualSub() {
        var data = Data([0, 1, 2, 3, 4, 5, 6, 7])[1..<6]
        data.replaceSerializedString(2..<5, with: "abc", encoding: .ascii, filler: Character(" "))
        XCTAssertEqual(data, Data([1, 0x61, 0x62, 0x63, 5]))
    }
}

final class RangeTests: XCTestCase {
    func testReduceUpper() {
        XCTAssertEqual((3..<7).reduceUpper(by: 2), 3..<5)
    }

    func testReduceUpperClipped() {
        XCTAssertEqual((3..<7).reduceUpper(by: 9), 3..<3)
    }

    func testInc() {
        XCTAssertEqual((3..<7).inc(by: 2), 5..<9)
    }
}