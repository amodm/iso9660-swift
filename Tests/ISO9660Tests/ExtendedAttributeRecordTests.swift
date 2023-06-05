import XCTest
@testable import ISO9660

final class ExtendedAttributeRecordTests: XCTestCase {
    func testBasic() {
        let ext = ExtendedAttributeRecord(from: paddedTestRecord[5...])
        XCTAssertEqual(ext.ownerId, 0x0102)
        XCTAssertEqual(ext.groupId, 0x0103)
        XCTAssertEqual(ext.permissions, 0xa0a1)
        XCTAssertNil(ext.creationTime)
        XCTAssertNil(ext.modificationTime)
        XCTAssertNil(ext.expirationTime)
        XCTAssertNil(ext.effectiveTime)
        XCTAssertEqual(ext.recordFormat, 0)
        XCTAssertEqual(ext.recordAttributes, 0)
        XCTAssertEqual(ext.recordLength, 0)
        XCTAssertEqual(ext.systemIdentifier, "MACOS")
        XCTAssertEqual(ext.systemUse, Data(count: 64))
        XCTAssertEqual(ext.version, 1)
        XCTAssertEqual(ext.escapeSequenceLength, 0)
        XCTAssertEqual(ext.applicationUse, Data())
    }
}

private let paddedTestRecord = Data([
    1, 2, 3, 4, 5, // general nonsense
    0x02, 0x01, 0x01, 0x02, // owner id
    0x03, 0x01, 0x01, 0x03, // group id
    0xa0, 0xa1, // permissions
    0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x00, // creation time
    0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x00, // modification time
    0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x00, // expiration time
    0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x00, // effective time
    0x00, // record format
    0x00, // record attributes
    0x00, 0x00, 0x00, 0x00, // record length
    0x4d, 0x41, 0x43, 0x4f, 0x53, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, // system identifier
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // system use
    1, // version
    0, // length of escape seq
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // reserved
    0, 0, 0, 0, // length of application use
    1, 2, 3, 4, 5, // general nonsense
])