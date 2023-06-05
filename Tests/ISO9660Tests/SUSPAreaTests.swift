import XCTest
@testable import ISO9660

final class SUSPAreaTests: XCTestCase {
    func testSingleFitArea() {
        let e1: SUSPEntry = .rrip(.NM(flags: 0, name: Data("hello".utf8)))
        let e2: SUSPEntry = .rrip(.SL(continuesInNext: false, recordsData: Data("somefile.txt".utf8)))
        let data = e1.serialize() + e2.serialize()
        guard let area = SUSPArea(continuation: data) else {
            XCTFail("Failed to create area")
            return
        }
        let (serializedData, others) = area.serialize(200) { _ in
            XCTFail("Should not be called")
            return (0, 0, 0)
        }
        XCTAssertEqual(serializedData, data)
        XCTAssertEqual(others.count, 0)
    }

    func testAdd() {
        let e1: SUSPEntry = .rrip(.NM(flags: 0, name: Data("hello".utf8)))
        let ce: SUSPEntry = .susp(.CE(block: 100, offset: 0, length: 100))
        var area = SUSPArea(continuation: e1.serialize() + ce.serialize())!
        if let (block, offset, length) = area.continuesAt {
            XCTAssertEqual(block, 100)
            XCTAssertEqual(offset, 0)
            XCTAssertEqual(length, 100)
        } else {
            XCTFail("Expected continuation")
        }
        let e2 = SUSPEntry.rrip(.SL(continuesInNext: false, recordsData: Data("somefile.txt".utf8)))
        XCTAssertTrue(area.add(continuation: e2.serialize()), "continuation addition failed")

        let (serializedData, others) = area.serialize(200) { _ in
            XCTFail("Should not be called")
            return (0, 0, 0)
        }
        XCTAssertEqual(serializedData, e1.serialize() + e2.serialize())
        XCTAssertEqual(others.count, 0)
    }

    func testSplitAreaCleanBoundary() {
        let e1: SUSPEntry = .rrip(.NM(flags: 0, name: Data("hello".utf8)))
        let e1Size = e1.serialize().count
        let e2: SUSPEntry = .rrip(.SL(continuesInNext: false, recordsData: Data("sdfjhsfjhsdfhjsdfiusydfshdfkjsdfjsdfjshdfksjhdfkhsdfkhsdfkhsdfishdfkjshdf.txt".utf8)))
        let e2Size = e2.serialize().count
        let data = e1.serialize() + e2.serialize()
        guard let area = SUSPArea(continuation: data) else {
            XCTFail("Failed to create area")
            return
        }
        let firstSize = UInt32(e1Size + SUSPArea.CE_LEN)
        let (first, others) = area.serialize(firstSize) { requestedSize in
            XCTAssertEqual(requestedSize, UInt32(e2Size))
            return (100, 0, requestedSize + 100) // we add 100 just to test that over-allocations are dealt with appropriately
        }
        let expectedCE: SUSPEntry = .susp(.CE(block: 100, offset: 0, length: UInt32(e2Size)))
        XCTAssertEqual(first, e1.serialize() + expectedCE.serialize())
        XCTAssertEqual(others.count, 1)
        let second = others[0]
        XCTAssertEqual(second.block, 100)
        XCTAssertEqual(second.offset, 0)
        XCTAssertEqual(second.data, e2.serialize())
    }

    func testSplitAreaNotCleanBoundary() {
        let e1: SUSPEntry = .rrip(.NM(flags: 0, name: Data("hello world".utf8)))
        let e1Size = e1.serialize().count
        let e2: SUSPEntry = .rrip(.SL(continuesInNext: false, recordsData: Data("sdfjhsfjhsdfhjsdfiusydfshdfkjsdfjsdfjshdfksjhdfkhsdfkhsdfkhsdfishdfkjshdf.txt".utf8)))
        let e2Size = e2.serialize().count
        let data = e1.serialize() + e2.serialize()
        guard let area = SUSPArea(continuation: data) else {
            XCTFail("Failed to create area")
            return
        }
        let shortBy = 4
        let firstSize = UInt32(e1Size - shortBy + SUSPArea.CE_LEN)
        let lenOfCarryoverFromFirst = 5 + shortBy // 5 bytes of NM header + `shortBy` bytes of name data
        let (first, others) = area.serialize(firstSize) { requestedSize in
            XCTAssertEqual(requestedSize, UInt32(lenOfCarryoverFromFirst + e2Size))
            return (100, 0, requestedSize + 100) // we add 100 just to test that over-allocations are dealt with appropriately
        }
        let expectedCE: SUSPEntry = .susp(.CE(block: 100, offset: 0, length: UInt32(lenOfCarryoverFromFirst + e2Size)))
        let e1Part1: SUSPEntry = .rrip(.NM(flags: 1, name: Data("hello w".utf8)))
        let e1Part2: SUSPEntry = .rrip(.NM(flags: 0, name: Data("orld".utf8)))
        XCTAssertEqual(first, e1Part1.serialize() + expectedCE.serialize())
        XCTAssertEqual(others.count, 1)
        let second = others[0]
        XCTAssertEqual(second.block, 100)
        XCTAssertEqual(second.offset, 0)
        XCTAssertEqual(second.data, e1Part2.serialize() + e2.serialize())
    }
}

extension Data {
    var hex: String {
        return "[\(self.map { String(format: "%02x", $0) }.joined(separator: ", "))]"
    }
}