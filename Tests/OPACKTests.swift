import XCTest
@testable import itsytv

final class OPACKTests: XCTestCase {

    // MARK: - Encoding tests

    func testEncodeTrue() {
        let data = OPACK.pack(.bool(true))
        XCTAssertEqual(data, Data([0x01]))
    }

    func testEncodeFalse() {
        let data = OPACK.pack(.bool(false))
        XCTAssertEqual(data, Data([0x02]))
    }

    func testEncodeNull() {
        let data = OPACK.pack(.null)
        XCTAssertEqual(data, Data([0x04]))
    }

    func testEncodeSmallIntegers() {
        XCTAssertEqual(OPACK.pack(.int(0)), Data([0x08]))
        XCTAssertEqual(OPACK.pack(.int(15)), Data([0x17]))
        XCTAssertEqual(OPACK.pack(.int(39)), Data([0x2F]))
    }

    func testEncodeLargerIntegers() {
        // 40 requires extended encoding
        XCTAssertEqual(OPACK.pack(.int(40)), Data([0x30, 0x28]))
        // 0x1FF = 511
        XCTAssertEqual(OPACK.pack(.int(0x1FF)), Data([0x31, 0xFF, 0x01]))
    }

    func testEncodeFloat64() {
        let data = OPACK.pack(.float64(1.0))
        XCTAssertEqual(data, Data([0x36, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xF0, 0x3F]))
    }

    func testEncodeShortString() {
        let data = OPACK.pack(.string("a"))
        XCTAssertEqual(data, Data([0x41, 0x61]))
    }

    func testEncodeString3() {
        let data = OPACK.pack(.string("abc"))
        XCTAssertEqual(data, Data([0x43, 0x61, 0x62, 0x63]))
    }

    func testEncodeEmptyString() {
        let data = OPACK.pack(.string(""))
        XCTAssertEqual(data, Data([0x40]))
    }

    func testEncodeShortData() {
        let data = OPACK.pack(.data(Data([0xAC])))
        XCTAssertEqual(data, Data([0x71, 0xAC]))
    }

    func testEncodeData3() {
        let data = OPACK.pack(.data(Data([0x12, 0x34, 0x56])))
        XCTAssertEqual(data, Data([0x73, 0x12, 0x34, 0x56]))
    }

    func testEncodeEmptyArray() {
        let data = OPACK.pack(.array([]))
        XCTAssertEqual(data, Data([0xD0]))
    }

    func testEncodeArrayWithElements() {
        // [1, "test", false]
        let data = OPACK.pack(.array([.int(1), .string("test"), .bool(false)]))
        XCTAssertEqual(data, Data([0xD3, 0x09, 0x44, 0x74, 0x65, 0x73, 0x74, 0x02]))
    }

    func testEncodeEmptyDict() {
        let data = OPACK.pack(.dict([]))
        XCTAssertEqual(data, Data([0xE0]))
    }

    func testEncodeDictWithEntries() {
        // {"a": 12, false: null}
        let data = OPACK.pack(.dict([
            (key: .string("a"), value: .int(12)),
            (key: .bool(false), value: .null),
        ]))
        XCTAssertEqual(data, Data([0xE2, 0x41, 0x61, 0x14, 0x02, 0x04]))
    }

    func testEncodeUUID() {
        let uuid = UUID(uuidString: "12345678-1234-5678-1234-567812345678")!
        let data = OPACK.pack(.uuid(uuid))
        XCTAssertEqual(data, Data([
            0x05,
            0x12, 0x34, 0x56, 0x78,
            0x12, 0x34, 0x56, 0x78,
            0x12, 0x34, 0x56, 0x78,
            0x12, 0x34, 0x56, 0x78,
        ]))
    }

    // MARK: - Roundtrip tests

    func testRoundtripBool() throws {
        let value = OPACK.Value.bool(true)
        XCTAssertEqual(try OPACK.unpack(OPACK.pack(value)), value)
    }

    func testRoundtripInt() throws {
        for n: Int64 in [0, 1, 39, 40, 255, 256, 65535, 65536, 1_000_000] {
            let value = OPACK.Value.int(n)
            XCTAssertEqual(try OPACK.unpack(OPACK.pack(value)), value, "Failed for \(n)")
        }
    }

    func testRoundtripString() throws {
        for s in ["", "a", "hello", String(repeating: "x", count: 100)] {
            let value = OPACK.Value.string(s)
            XCTAssertEqual(try OPACK.unpack(OPACK.pack(value)), value)
        }
    }

    func testRoundtripNestedDict() throws {
        let value = OPACK.Value.dictionary([
            ("key", .string("value")),
            ("nested", .dict([
                (key: .string("a"), value: .int(42)),
            ])),
            ("list", .array([.bool(true), .null])),
        ])
        XCTAssertEqual(try OPACK.unpack(OPACK.pack(value)), value)
    }

    // MARK: - Decoding tests

    func testDecodeNegativeOne() throws {
        let value = try OPACK.unpack(Data([0x07]))
        XCTAssertEqual(value, .int(-1))
    }

    func testDecodePointer() throws {
        // Dict with two references to the same string
        // E2 (dict, 2 entries) 41 61 ("a") 41 61 ("a") A0 (pointer 0) 08 (int 0)
        // After decoding "a" the first time, it's in objectList[0]
        // A0 = pointer to objectList[0]
        let data = Data([0xE2, 0x41, 0x61, 0x09, 0xA0, 0x08])
        let value = try OPACK.unpack(data)
        if case .dict(let pairs) = value {
            XCTAssertEqual(pairs.count, 2)
            XCTAssertEqual(pairs[0].key, .string("a"))
            XCTAssertEqual(pairs[1].key, .string("a"))
        } else {
            XCTFail("Expected dict")
        }
    }
}
