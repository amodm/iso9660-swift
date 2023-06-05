import XCTest
@testable import ISO9660

final class PathTableRecordTests: XCTest {
    func testSerializeNoPad() {
        let name = "TEST"
        var ptr = PathTableRecord(name, encoding: .ascii)
        ptr.parentDirectoryNumber = 2
        ptr.extentLocation = 3
        ptr.extendedAttributeRecordLength = 128
        let data = ptr.serialize(littleEndian: true)
        XCTAssertEqual(data, Data([
            0x04, // lenth of identifier
            0x80, // extended attribute record length
            0x03, 0x00, 0x00, 0x03, // extent location
            0x02, 0x00, 0x00, 0x02, // parent directory number
            0x54, 0x45, 0x53, 0x54, // identifier
        ]))
    }

    func testSerializeWithPad() {
        let name = "TEST1"
        var ptr = PathTableRecord(name, encoding: .ascii)
        ptr.parentDirectoryNumber = 2
        ptr.extentLocation = 3
        ptr.extendedAttributeRecordLength = 128
        let data = ptr.serialize(littleEndian: true)
        XCTAssertEqual(data, Data([
            0x05, // lenth of identifier
            0x80, // extended attribute record length
            0x03, 0x00, 0x00, 0x03, // extent location
            0x02, 0x00, 0x00, 0x02, // parent directory number
            0x54, 0x45, 0x53, 0x54, 0x31, // identifier
            0x00, // padding
        ]))
    }

    func testDeserializeNoPad() {
        let data = Data([
            0x04, // lenth of identifier
            0x80, // extended attribute record length
            0x03, 0x00, 0x00, 0x03, // extent location
            0x02, 0x00, 0x00, 0x02, // parent directory number
            0x54, 0x45, 0x53, 0x54, // identifier
        ])
        let ptr = PathTableRecord(from: data)!
        XCTAssertEqual(ptr.directoryIdentifierLength, 4)
        XCTAssertEqual(ptr.getDirectoryIdentifier(encoding: .ascii), "TEST")
        XCTAssertEqual(ptr.parentDirectoryNumber, 2)
        XCTAssertEqual(ptr.extentLocation, 3)
        XCTAssertEqual(ptr.extendedAttributeRecordLength, 128)
    }

    func testDeserializeWithPad() {
        let data = Data([
            0x05, // lenth of identifier
            0x80, // extended attribute record length
            0x03, 0x00, 0x00, 0x03, // extent location
            0x02, 0x00, 0x00, 0x02, // parent directory number
            0x54, 0x45, 0x53, 0x54, 0x31, // identifier
            0x00, // padding
        ])
        let ptr = PathTableRecord(from: data)!
        XCTAssertEqual(ptr.directoryIdentifierLength, 5)
        XCTAssertEqual(ptr.getDirectoryIdentifier(encoding: .ascii), "TEST1")
        XCTAssertEqual(ptr.parentDirectoryNumber, 2)
        XCTAssertEqual(ptr.extentLocation, 3)
        XCTAssertEqual(ptr.extendedAttributeRecordLength, 128)
    }
}