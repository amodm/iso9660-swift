import XCTest
@testable import ISO9660

final class SUSPSerializeTests: XCTestCase {
    func testCE() {
        let susp = SUSPEntry.susp(.CE(block: 0x1e, offset: 0, length: 0xed))
        XCTAssertEqual(susp.serialize(), CEData)
    }

    func testPD() {
        let susp = SUSPEntry.susp(.PD(padLength: 2))
        XCTAssertEqual(susp.serialize(), PDData)
    }

    func testSP() {
        let susp = SUSPEntry.susp(.SP(lengthToSkip: 3))
        XCTAssertEqual(susp.serialize(), SPData)
    }

    func testST() {
        let susp = SUSPEntry.susp(.ST)
        XCTAssertEqual(susp.serialize(), STData)
    }
}

final class SUSPDeserializeTests: XCTestCase {
    func testCE() {
        let susp = SUSPEntry.deserialize(from: CEData + ExtraneousData)
        XCTAssertEqual(susp.count, 1)
        if case .susp(.CE(let block, let offset, let length)) = susp[0] {
            XCTAssertEqual(block, 0x1e)
            XCTAssertEqual(offset, 0)
            XCTAssertEqual(length, 0xed)
        } else {
            XCTFail("Expected CE")
        }
    }

    func testSP() {
        let susp = SUSPEntry.deserialize(from: SPData)
        XCTAssertEqual(susp.count, 1)
        if case .susp(.SP(let skipLen)) = susp[0] {
            XCTAssertEqual(skipLen, 3)
        } else {
            XCTFail("Expected SP")
        }
    }

    func testCEPDST() {
        let susp = SUSPEntry.deserialize(from: CEData + PDData + STData)
        XCTAssertEqual(susp.count, 3)
        if case .susp(.CE(let block, let offset, let length)) = susp[0] {
            XCTAssertEqual(block, 0x1e)
            XCTAssertEqual(offset, 0)
            XCTAssertEqual(length, 0xed)
        } else {
            XCTFail("Expected CE")
        }
        if case .susp(.PD(let padLen)) = susp[1] {
            XCTAssertEqual(padLen, 2)
        } else {
            XCTFail("Expected PD")
        }
        if case .susp(.ST) = susp[2] {
        } else {
            XCTFail("Expected ST")
        }
    }
}

final class SUSPRockRidgeTests: XCTestCase {
    func testSLWithTargetRoot() {
        let entry = SUSPEntry.RockRidge.Symlink.newSL(name: "src", target: "/a/../b")
        if let sl = SUSPEntry.RockRidge.Symlink(entry) {
            let components = sl.components
            XCTAssertEqual(components.count, 4)
            XCTAssertEqual(components[0], .rootDirectory)
            XCTAssertEqual(components[1], .named("a".data(using: .ascii)!))
            XCTAssertEqual(components[2], .parentDirectory)
            XCTAssertEqual(components[3], .named("b".data(using: .ascii)!))
        } else {
            XCTFail("Expected SL")
        }
    }

    func testSLWithTargetVolRoot() {
        let entry = SUSPEntry.RockRidge.Symlink.newSL(name: "src", target: "//a/../b")
        if let sl = SUSPEntry.RockRidge.Symlink(entry) {
            let components = sl.components
            XCTAssertEqual(components.count, 4)
            XCTAssertEqual(components[0], .volumeRoot)
            XCTAssertEqual(components[1], .named("a".data(using: .ascii)!))
            XCTAssertEqual(components[2], .parentDirectory)
            XCTAssertEqual(components[3], .named("b".data(using: .ascii)!))
        } else {
            XCTFail("Expected SL")
        }
    }

    func testSLWithTargetRelative() {
        let entry = SUSPEntry.RockRidge.Symlink.newSL(name: "src", target: "a/b")
        if let sl = SUSPEntry.RockRidge.Symlink(entry) {
            let components = sl.components
            XCTAssertEqual(components.count, 2)
            XCTAssertEqual(components[0], .named("a".data(using: .ascii)!))
            XCTAssertEqual(components[1], .named("b".data(using: .ascii)!))
        } else {
            XCTFail("Expected SL")
        }
    }
}

final class SplitTestsSL: XCTestCase {
    func testBasicSplit(_ x: Int) {
        let name = "some long name"
        let u8 = name.utf8
        let entry: SUSPEntry = .rrip(.SL(continuesInNext: false, recordsData: Data([0x00, UInt8(u8.count)] + u8)))
        if let (first, second) = entry.splitAt(lessThanOrEqualTo: x + 5) {
            XCTAssertEqual(first, .rrip(.SL(continuesInNext: true, recordsData: Data([0x01, UInt8(x - 2)] + u8.prefix(x - 2)))))
            XCTAssertEqual(first.serialize().count, x + 5)
            let remainingLen = u8.count - (x - 2)
            XCTAssertEqual(second, .rrip(.SL(continuesInNext: false, recordsData: Data([0x00, UInt8(remainingLen)] + u8.suffix(remainingLen)))))
        } else {
            XCTFail("Expected split")
        }
    }

    func testEvenSplit() {
        testBasicSplit(4)
    }

    func testOddSplit() {
        testBasicSplit(5)
    }

    func testImpossibleSplit() {
        let name = "some long name"
        let u8 = name.utf8
        let entry: SUSPEntry = .rrip(.SL(continuesInNext: false, recordsData: Data([0x00, UInt8(u8.count)] + u8)))
        XCTAssertNil(entry.splitAt(lessThanOrEqualTo: 7))
    }

    func testBoundarySplit() {
        let name = "some name"
        let c1 = Data([0x02, 0x00]) // current dir
        let c2 = Data([0x00, UInt8(name.utf8.count)] + name.utf8)
        let entry: SUSPEntry = .rrip(.SL(continuesInNext: false, recordsData: c1 + c2))
        if let (first, second) = entry.splitAt(lessThanOrEqualTo: 2 + 5) {
            XCTAssertEqual(first, .rrip(.SL(continuesInNext: true, recordsData: Data([0x02, 0x00]))))
            XCTAssertEqual(second, .rrip(.SL(continuesInNext: false, recordsData: Data([0x00, UInt8(name.utf8.count)] + name.utf8))))
        } else {
            XCTFail("Expected split")
        }
    }

    func testBoundarySplitWithContinue() {
        let name = "some name"
        let c1 = Data([0x02, 0x00]) // current dir
        let c2 = Data([0x00, UInt8(name.utf8.count)] + name.utf8)
        let entry: SUSPEntry = .rrip(.SL(continuesInNext: true, recordsData: c1 + c2))
        if let (first, second) = entry.splitAt(lessThanOrEqualTo: 2 + 5) {
            XCTAssertEqual(first, .rrip(.SL(continuesInNext: true, recordsData: Data([0x02, 0x00]))))
            XCTAssertEqual(second, .rrip(.SL(continuesInNext: true, recordsData: Data([0x00, UInt8(name.utf8.count)] + name.utf8))))
        } else {
            XCTFail("Expected split")
        }
    }
}

final class SplitTestsNM: XCTestCase {
    func testBasicSplit(_ x: Int) {
        let name = "some long name"
        let u8 = Data(name.utf8)
        let entry: SUSPEntry = .rrip(.NM(flags: 0, name: u8))
        if let (first, second) = entry.splitAt(lessThanOrEqualTo: x + 5) {
            XCTAssertEqual(first, .rrip(.NM(flags: 1, name: u8.prefix(x))))
            XCTAssertEqual(first.serialize().count, x + 5)
            let remainingLen = u8.count - x
            XCTAssertEqual(second, .rrip(.NM(flags: 0, name: u8.suffix(remainingLen))))
        } else {
            XCTFail("Expected split")
        }
    }

    func testEvenSplit() {
        testBasicSplit(4)
    }

    func testOddSplit() {
        testBasicSplit(5)
    }

    func testImpossibleSplit() {
        let name = "some long name"
        let u8 = Data(name.utf8)
        let entry: SUSPEntry = .rrip(.NM(flags: 0, name: u8))
        XCTAssertNil(entry.splitAt(lessThanOrEqualTo: 5))
    }

    func testLowerBoundarySplit() {
        let name = "name"
        let u8 = Data(name.utf8)
        let entry: SUSPEntry = .rrip(.NM(flags: 0, name: u8))
        XCTAssertNil(entry.splitAt(lessThanOrEqualTo: 5))
    }

    func testUpperBoundarySplit() {
        let name = "name"
        let u8 = Data(name.utf8)
        let entry: SUSPEntry = .rrip(.NM(flags: 0, name: u8))
        if let (first, second) = entry.splitAt(lessThanOrEqualTo: u8.count + 5) {
            XCTAssertEqual(first, entry)
            XCTAssertEqual(second, .rrip(.NM(flags: 0, name: Data())))
        } else {
            XCTFail("Expected split")
        }
    }
}

extension SUSPEntry: CustomStringConvertible {
    public var description: String {
        switch self {
        case .rrip(let rirp):
            switch rirp {
            case .SL(let cin, let data):
                return ".rirp(SL(continuesInNext: \(cin), recordsData: \(data.map { String(format: "%02x", $0) }.joined(separator: ", "))))"
            default:
                return ".rirp(\(rirp))"
            }
        case .susp(let susp):
            return ".susp(\(susp))"
        default:
            return ".\(self)"
        }
    }
}

private let CEData = Data([
    0x43, 0x45, // CE
    0x1c, // length
    0x01, // version
    0x1e, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x1e, // block location
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // offset
    0xed, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xed, // length
])

private let PDData = Data([
    0x50, 0x44, // PD
    0x06, // length
    0x01, // version
    0x00, 0x00, // padding
])

private let SPData = Data([
    0x53, 0x50, // SP
    0x07, // length
    0x01, // version
    0xbe, 0xef, // check bytes
    0x03, // num bytes to skip
])

private let STData = Data([
    0x53, 0x54, // ST
    0x04, // length
    0x01, // version
])

private let ExtraneousData = Data([
    0x00, 0x00, 0x00, // some additional data to check if it's ignored
])
