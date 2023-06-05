import XCTest
@testable import ISO9660

final class NumericsTests: XCTestCase {
    /// ECMA-119 7.2.1
    func testUInt16LSB() {
        XCTAssertEqual(UInt16(0x1234).littleEndianBytes, Data([0x34, 0x12]))
    }

    /// ECMA-119 7.2.2
    func testUInt16MSB() {
        XCTAssertEqual(UInt16(0x1234).bigEndianBytes, Data([0x12, 0x34]))
    }

    /// ECMA-119 7.2.3
    func testUInt16BothEndian() {
        XCTAssertEqual(UInt16(0x1234).bothEndianBytes, Data([0x34, 0x12, 0x12, 0x34]))
    }

    /// ECMA-119 7.3.1
    func testUInt32LSB() {
        XCTAssertEqual(UInt32(0x12345678).littleEndianBytes, Data([0x78, 0x56, 0x34, 0x12]))
    }

    /// ECMA-119 7.3.2
    func testUInt32MSB() {
        XCTAssertEqual(UInt32(0x12345678).bigEndianBytes, Data([0x12, 0x34, 0x56, 0x78]))
    }

    /// ECMA-119 7.3.3
    func testUInt32BothEndian() {
        XCTAssertEqual(UInt32(0x12345678).bothEndianBytes, Data([0x78, 0x56, 0x34, 0x12, 0x12, 0x34, 0x56, 0x78]))
    }
}
