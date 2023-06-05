import XCTest
@testable import ISO9660

final class DirectoryRecordTests: XCTestCase {
    func testDirectoryRecord() {
        let rootDirectoryRecord = paddedDirRecord[5...]
        let record = DirectoryRecord(from: rootDirectoryRecord)
        XCTAssertEqual(record.length, 34)
        XCTAssertEqual(record.extendedAttributeRecordLength, 0)
        XCTAssertEqual(record.extentLocation, 28)
        XCTAssertEqual(record.dataLength, 2048)
        XCTAssertTrue(record.isDirectory)
        XCTAssertEqual(record.flags, 2)
        XCTAssertEqual(record.volumeSequenceNumber, 1)
        XCTAssertEqual(record.getIdentifier(encoding: .ascii), DirectoryRecord.Identifier.dot)
    }

    func testDirectoryFileId() {
        let fileDirectoryRecord = paddedfileDirectoryRecord[5...]
        let record = DirectoryRecord(from: fileDirectoryRecord)
        XCTAssertEqual(record.length, 126)
        XCTAssertEqual(record.extendedAttributeRecordLength, 0)
        XCTAssertEqual(record.extentLocation, 31)
        XCTAssertEqual(record.dataLength, 342)
        XCTAssertTrue(!record.isDirectory)
        XCTAssertEqual(record.flags, 0)
        XCTAssertEqual(record.volumeSequenceNumber, 1)
        XCTAssertEqual(record.getIdentifier(encoding: .ascii), DirectoryRecord.Identifier.file("META_DAT.;1"))
    }

    func testSystemUseModification() {
        let rootDirectoryRecord = paddedDirRecord[5...]
        var record = DirectoryRecord(from: rootDirectoryRecord)
        XCTAssertEqual(record.length, 34)

        let systemUse = Data([0, 1, 2, 3, 4, 5])

        record.systemUse = systemUse
        XCTAssertEqual(record.length, 40)
        XCTAssertEqual(record.systemUse, systemUse)

        record.systemUse = systemUse[0..<3]
        XCTAssertEqual(record.length, 37)
        XCTAssertEqual(record.systemUse, systemUse[0..<3])

        record.systemUse = nil
        XCTAssertEqual(record.length, 34)
        XCTAssertNil(record.systemUse)
    }
}

let paddedDirRecord = Data([
    1, 2, 3, 4, 5, // general nonsense
    0x22, // record length
    0x00, // ext attribute record length
    0x1c, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x1c, // LBA location of extent
    0x00, 0x08, 0x00, 0x00, 0x00, 0x00, 0x08, 0x00, // data length of extent
    0x45, 0x0c, 0x1f, 0x10, 0x00, 0x00, 0xe0, // recording date and time
    0x02, // file flags
    0x00, // file unit size
    0x00, // interleave gap size
    0x01, 0x00, 0x00, 0x01, // volume sequence number
    0x01, // file identifier length
    0x00, // file identifier - dot
    1, 2, 3, 4, 5, // general nonsense
])

let paddedfileDirectoryRecord = Data([
    1, 2, 3, 4, 5, // general nonsense
    0x7e, // record length
    0x00, // ext attribute record length
    0x1f, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x1f, // LBA location of extent
    0x56, 0x01, 0x00, 0x00, 0x00, 0x00, 0x01, 0x56, // data length of extent
    0x76, 0x04, 0x03, 0x16, 0x3b, 0x0a, 0xe4, // recording date and time
    0x00, // file flags
    0x00, // file unit size
    0x00, // interleave gap size
    0x01, 0x00, 0x00, 0x01, // volume sequence number
    0x0b, // file identifier length
    0x4d, 0x45, 0x54, 0x41, 0x5f, 0x44, 0x41, 0x54, 0x2e, 0x3b, 0x31, // file identifier - META_DAT.;1
    0x52, 0x52, 0x05, 0x01, 0x89, // RR
    0x4e, 0x4d, 0x0e, 0x01, 0x00, 0x6d, 0x65, 0x74, 0x61, 0x2d, 0x64, 0x61, 0x74, 0x61, // NM: meta-data
    0x50, 0x58, 0x24, 0x01, // PX
        0xa4, 0x81, 0x00, 0x00, 0x00, 0x00, 0x81, 0xa4, // PX: fileMode = 0100644
        0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, // PX: links = 1
        0x71, 0x51, 0xa7, 0x54, 0x54, 0xa7, 0x51, 0x71, // PX: uid = 0x54a75171
        0x01, 0x02, 0xa0, 0x54, 0x54, 0xa0, 0x02, 0x01, // PX: gid = 0x54a00201
    0x54, 0x46, 0x1a, 0x01, // TF
        0x0e, // TF flags
        0x76, 0x04, 0x03, 0x16, 0x3b, 0x0a, 0xe4, // TF: created  at, 7B
        0x76, 0x04, 0x03, 0x16, 0x3b, 0x0a, 0xe4, // TF: modified at, 7B
        0x76, 0x04, 0x06, 0x0f, 0x19, 0x2b, 0xe4, // TF: accessed at, 7B
    1, 2, 3, 4, 5, // general nonsense
])
