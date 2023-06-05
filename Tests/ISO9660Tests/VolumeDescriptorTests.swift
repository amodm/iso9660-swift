import XCTest
@testable import ISO9660

final class VolumeDescriptorTests: XCTestCase {
    func testBadSystemIdentifier() {
        let descriptor = newPrimaryVolumeDescriptor {
            $0.systemIdentifier = "AbCD"
        }
        XCTAssertThrowsError(try descriptor.validate()) { error in
            XCTAssertEqual(error as? SpecError, SpecError.invalidIdentifier(field: "systemIdentifier", id: "AbCD"))
        }
    }

    func testBadVolumedentifier() {
        let descriptor = newPrimaryVolumeDescriptor {
            $0.volumeIdentifier = "TeST"
        }
        XCTAssertThrowsError(try descriptor.validate()) { error in
            XCTAssertEqual(error as? SpecError, SpecError.invalidIdentifier(field: "volumeIdentifier", id: "TeST"))
        }
    }

    func testBadLogicalBlockSize() {
        let descriptor = newPrimaryVolumeDescriptor {
            $0.logicalBlockSize = 2043
        }
        XCTAssertThrowsError(try descriptor.validate()) { error in
            XCTAssertEqual(error as? SpecError, SpecError.invalidLogicalBlockSize(size: 2043))
        }
    }

    func testIdentifierOrFileSerializeFile() {
        let file = IdentifierOrFile.file("TEST")
        XCTAssertEqual(file.serialize(8, .ascii), "_TEST  ".serialize(8, .ascii))
    }

    func testIdentifierOrFileDeserializeFile() {
        let iorf = IdentifierOrFile.deserialize("_TEST   ".serialize(8, .ascii)[...], .ascii)
        XCTAssertEqual(iorf, .file("TEST"))
    }
}

private func newPrimaryVolumeDescriptor(_ op: (inout VolumeDirectoryDescriptor) -> Void) -> VolumeDescriptor {
    var descriptor = VolumeDirectoryDescriptor(type: 1, version: 1)
    descriptor.systemIdentifier = "ABCD"
    descriptor.volumeIdentifier = "TEST"
 
    op(&descriptor)
    return VolumeDescriptor.primary(descriptor)
}
