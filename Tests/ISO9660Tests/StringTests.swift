import XCTest
@testable import ISO9660

final class StringTests: XCTestCase {
    func testAString() {
        XCTAssertTrue("ABCDEF3247".isAStr)
        XCTAssertTrue("ABCDEF3247//+!".isAStr)
        XCTAssertFalse("AbCD".isAStr)
    }

    func testDString() {
        XCTAssertTrue("ABCDEF3247".isDStr)
        XCTAssertFalse("ABCDEF3247//+!".isDStr)
        XCTAssertFalse("AbCD".isAStr)
    }

    func testDSep1Sep2String() {
        XCTAssertTrue("ABCDEF3247".hasOnlyDOrSepChars)
        XCTAssertTrue("ABCD.EF32;47".hasOnlyDOrSepChars)
        XCTAssertFalse("ABCDEF3247//+!".isDStr)
        XCTAssertFalse("AbCD".isAStr)
    }

    func testSerialize() {
        let bytes = "ABCD😄".serialize(16, .utf16BigEndian)
        XCTAssertEqual(bytes, Data([0, 65, 0, 66, 0, 67, 0, 68, 216, 61, 222, 4, 0, 0x20, 0, 0x20]))
    }

    func testSerializeTrimmed() {
        let bytes = "ABCD😄".serialize(4, .utf16BigEndian)
        XCTAssertEqual(bytes, Data([0, 65, 0, 66]))
    }

    func testSerializeTrimmedOdd() {
        let bytes = "ABCD😄".serialize(5, .utf16BigEndian)
        XCTAssertEqual(bytes, Data([0, 65, 0, 66, 0]))
    }

    func testDeserialize() {
        let string = String.deserialize([0, 65, 0, 66, 0, 67, 0, 68, 216, 61, 222, 4, 0, 0x20, 0, 0x20],  .utf16BigEndian)
        XCTAssertEqual(string, "ABCD😄")
    }

    func testDeserializeNoFiller() {
        let string = String.deserialize([0, 65, 0, 66, 0, 67, 0, 68, 216, 61, 222, 4],  .utf16BigEndian)
        XCTAssertEqual(string, "ABCD😄")
    }

    func testDeserializeBadBoundary() {
        let string = String.deserialize([0, 65, 0, 66, 0, 67, 0, 68, 216, 61, 222],  .utf16BigEndian)
        XCTAssertTrue(string.starts(with: "ABCD"))
    }

    func testClippedStringNoClip() {
        let bytes = "ABCD😄".serializeClipped(.utf16BigEndian)
        XCTAssertEqual(bytes, Data([0, 65, 0, 66, 0, 67, 0, 68, 216, 61, 222, 4]))
    }

    func testClippedStringHigherClip() {
        let bytes = "ABCD😄".serializeClipped(.utf16BigEndian, 30)
        XCTAssertEqual(bytes, Data([0, 65, 0, 66, 0, 67, 0, 68, 216, 61, 222, 4]))
    }

    func testClippedStringSmallerClip() {
        let bytes = "ABCD😄".serializeClipped(.utf16BigEndian, 4)
        XCTAssertEqual(bytes, Data([0, 65, 0, 66]))
    }

    func testClippedStringSmallerClipBadBoundary() {
        let bytes = "ABCD😄".serializeClipped(.utf16BigEndian, 5)
        XCTAssertEqual(bytes, Data([0, 65, 0, 66]))
    }

    func testFileExtension() {
        XCTAssertEqual("/a/b/filename.txt".fileExtension, "txt")
        XCTAssertEqual("/a/b/filename.a.txt".fileExtension, "txt")
        XCTAssertEqual("/a/b/filename.".fileExtension, "")
        XCTAssertNil("/a/b/filename".fileExtension)
        XCTAssertEqual(".disk".fileExtension, "disk")
    }

    func testFilenameWithoutExtension() {
        XCTAssertEqual("/a/b/filename.txt".fileNameWithoutExtension, "filename")
        XCTAssertEqual("/a/b/filename.a.txt".fileNameWithoutExtension, "filename")
        XCTAssertEqual(".disk".fileNameWithoutExtension, "")
    }

    func testReplaceNonCharset() {
        XCTAssertEqual("TeSTing".replaceNonCharset(D_CHARS, "_"), "T_ST___")
    }
}

extension String {
    var utf8Bytes: [UInt8] {
        return Array(utf8)
    }
}
