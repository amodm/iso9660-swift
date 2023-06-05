import XCTest
@testable import ISO9660

final class DateTests: XCTestCase {
    func test17BSerialization() {
        let date = ISO8601DateFormatter().date(from: "2021-02-03T04:05:06+0530")!
        XCTAssertEqual(date.iso9660Format17B, Array<UInt8>("2021020304050600".utf8) + Data([22]))
    }

    func test7BSerialization() {
        let date = ISO8601DateFormatter().date(from: "2021-02-03T04:05:06+0530")!
        XCTAssertEqual(date.iso9660Format7B, Data([121, 2, 3, 4, 5, 6, 22]))
    }

    func test17BDeserialization() {
        let data = Data([1, 2]) + Data("2021020304050600".utf8Bytes) + Data([22])
        XCTAssertEqual(
            Date.decode(from: data[2...], format: .format17B),
            ISO8601DateFormatter().date(from: "2021-02-03T04:05:06+0530")
        )
    }

    func test7BDeserialization() {
        let data = Data([1, 2, 121, 2, 3, 4, 5, 6, 22, 5, 6, 7])
        XCTAssertEqual(
            Date.decode(from: data[2...], format: .format7B),
            ISO8601DateFormatter().date(from: "2021-02-03T04:05:06+0530")
        )
    }

    func test17BSerializationNil() {
        let date: Date? = nil
        XCTAssertEqual(date.iso9660Format17B, Data(count: 17))
    }

    func test7BSerializationNil() {
        let date: Date? = nil
        XCTAssertEqual(date.iso9660Format7B, Data(count: 7))
    }

    func test17BDeserializationNil() {
        let nullDate = Data(repeating: 0x30, count: 16) + [0]
        XCTAssertNil(Date.decode(from: nullDate, format: .format17B))
    }

    func test7BDeserializationNil() {
        XCTAssertNil(Date.decode(from: Data(count: 7), format: .format7B))
    }
}