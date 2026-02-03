import XCTest
@testable import itsytv

final class BinaryPlistTests: XCTestCase {

    // MARK: - Magic header

    func testOutputStartsWithBplist00() {
        let data = BinaryPlist.writeArchive(
            archiver: "NSKeyedArchiver",
            top: [],
            objects: [.string("$null")]
        )
        let header = String(data: data.prefix(8), encoding: .utf8)
        XCTAssertEqual(header, "bplist00")
    }

    // MARK: - Roundtrip with PropertyListSerialization

    func testSimpleArchiveIsValidPlist() throws {
        let data = BinaryPlist.writeArchive(
            archiver: "NSKeyedArchiver",
            top: [("root", .uid(1))],
            objects: [.string("$null"), .string("hello")]
        )

        let plist = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        )
        let dict = try XCTUnwrap(plist as? [String: Any])
        XCTAssertEqual(dict["$archiver"] as? String, "NSKeyedArchiver")
        XCTAssertEqual(dict["$version"] as? Int, 100000)

        let objects = try XCTUnwrap(dict["$objects"] as? [Any])
        XCTAssertEqual(objects[0] as? String, "$null")
        XCTAssertEqual(objects[1] as? String, "hello")
    }

    // MARK: - UID objects

    func testUIDObjectsArePreserved() throws {
        let data = BinaryPlist.writeArchive(
            archiver: "NSKeyedArchiver",
            top: [("root", .uid(1))],
            objects: [.string("$null"), .int(42)]
        )

        let plist = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        )
        let dict = try XCTUnwrap(plist as? [String: Any])
        let top = try XCTUnwrap(dict["$top"] as? [String: Any])

        // UIDs come through as dictionaries with CF$UID key when decoded by PropertyListSerialization
        // or as native UID type on macOS
        XCTAssertNotNil(top["root"])
    }

    // MARK: - Data objects

    func testDataObjectRoundtrip() throws {
        let testData = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let output = BinaryPlist.writeArchive(
            archiver: "NSKeyedArchiver",
            top: [("root", .uid(1))],
            objects: [.string("$null"), .data(testData)]
        )

        let plist = try PropertyListSerialization.propertyList(
            from: output,
            options: [],
            format: nil
        )
        let dict = try XCTUnwrap(plist as? [String: Any])
        let objects = try XCTUnwrap(dict["$objects"] as? [Any])
        XCTAssertEqual(objects[1] as? Data, testData)
    }

    // MARK: - Integer objects

    func testIntegerObjectRoundtrip() throws {
        let output = BinaryPlist.writeArchive(
            archiver: "NSKeyedArchiver",
            top: [("root", .uid(1))],
            objects: [.string("$null"), .int(12345)]
        )

        let plist = try PropertyListSerialization.propertyList(
            from: output,
            options: [],
            format: nil
        )
        let dict = try XCTUnwrap(plist as? [String: Any])
        let objects = try XCTUnwrap(dict["$objects"] as? [Any])
        XCTAssertEqual(objects[1] as? Int, 12345)
    }

    // MARK: - Nested dict objects

    func testNestedDictRoundtrip() throws {
        let output = BinaryPlist.writeArchive(
            archiver: "NSKeyedArchiver",
            top: [("root", .uid(1))],
            objects: [
                .string("$null"),
                .dict([("key", .string("value")), ("num", .int(7))]),
            ]
        )

        let plist = try PropertyListSerialization.propertyList(
            from: output,
            options: [],
            format: nil
        )
        let dict = try XCTUnwrap(plist as? [String: Any])
        let objects = try XCTUnwrap(dict["$objects"] as? [Any])
        // The nested dict is at index 1 in $objects
        let nested = try XCTUnwrap(objects[1] as? [String: Any])
        XCTAssertEqual(nested["key"] as? String, "value")
        XCTAssertEqual(nested["num"] as? Int, 7)
    }

    // MARK: - Array objects

    func testArrayObjectRoundtrip() throws {
        let output = BinaryPlist.writeArchive(
            archiver: "NSKeyedArchiver",
            top: [("root", .uid(1))],
            objects: [
                .string("$null"),
                .array(["alpha", "beta"]),
            ]
        )

        let plist = try PropertyListSerialization.propertyList(
            from: output,
            options: [],
            format: nil
        )
        let dict = try XCTUnwrap(plist as? [String: Any])
        let objects = try XCTUnwrap(dict["$objects"] as? [Any])
        let arr = try XCTUnwrap(objects[1] as? [String])
        XCTAssertEqual(arr, ["alpha", "beta"])
    }

    // MARK: - Large string (>14 chars triggers extended length)

    func testLongStringEncoding() throws {
        let longString = String(repeating: "x", count: 20)
        let output = BinaryPlist.writeArchive(
            archiver: "NSKeyedArchiver",
            top: [("root", .uid(1))],
            objects: [.string("$null"), .string(longString)]
        )

        let plist = try PropertyListSerialization.propertyList(
            from: output,
            options: [],
            format: nil
        )
        let dict = try XCTUnwrap(plist as? [String: Any])
        let objects = try XCTUnwrap(dict["$objects"] as? [Any])
        XCTAssertEqual(objects[1] as? String, longString)
    }

    // MARK: - Multiple top keys

    func testMultipleTopKeys() throws {
        let output = BinaryPlist.writeArchive(
            archiver: "RTIKeyedArchiver",
            top: [("a", .uid(1)), ("b", .uid(2))],
            objects: [.string("$null"), .string("first"), .string("second")]
        )

        let plist = try PropertyListSerialization.propertyList(
            from: output,
            options: [],
            format: nil
        )
        let dict = try XCTUnwrap(plist as? [String: Any])
        XCTAssertEqual(dict["$archiver"] as? String, "RTIKeyedArchiver")
    }
}
