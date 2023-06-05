import XCTest
@testable import ISO9660

final class ISOWriterTests: XCTestCase {
    func testLegacyFilenameUnique() {
        XCTAssertEqual(getLegacyFilename("abc.txt", []), "ABC.TXT;1")
        XCTAssertEqual(getLegacyFilename("boot.catalog", []), "BOOT.CATALOG;1")
        XCTAssertEqual(getLegacyFilename(".disk", []), ".DISK;1")
        XCTAssertEqual(getLegacyFilename("abc", []), "ABC;1")
        XCTAssertEqual(getLegacyFilename("abc.verylongextension", []), "ABC.VER;1")
        XCTAssertEqual(getLegacyFilename(".verylongextension", []), ".VER;1")
    }

    func testLegacyFilenameNonUnique() {
        XCTAssertEqual(getLegacyFilename("abc.txt", ["ABC.TXT;1"]), "ABC0.TXT;1")
        XCTAssertEqual(getLegacyFilename("abc.txt", ["ABC.TXT;1", "ABC0.TXT;1"]), "ABC00.TXT;1")
        XCTAssertEqual(getLegacyFilename("abcdefgh.txt", ["ABCDEFGH.TXT;1"]), "ABCDEFG0.TXT;1")
        XCTAssertEqual(getLegacyFilename("abcdefgh.txt", ["ABCDEFGH.TXT;1", "ABCDEFG0.TXT;1"]), "ABCDEFG1.TXT;1")
    }
}
