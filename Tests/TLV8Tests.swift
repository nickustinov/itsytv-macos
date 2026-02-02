import XCTest
@testable import itsytv

final class TLV8Tests: XCTestCase {

    func testEncodeSimple() {
        let data = TLV8.encode([
            (.seqNo, Data([0x01])),
            (.method, Data([0x00])),
        ])
        XCTAssertEqual(data, Data([0x06, 0x01, 0x01, 0x00, 0x01, 0x00]))
    }

    func testEncodeEmpty() {
        let data = TLV8.encode([
            (.seqNo, Data()),
        ])
        XCTAssertEqual(data, Data([0x06, 0x00]))
    }

    func testEncodeFragmentation() {
        // Value of 300 bytes should be split into 255 + 45
        let value = Data(repeating: 0xAA, count: 300)
        let data = TLV8.encode([(.publicKey, value)])

        // First fragment: tag(1) + len(1) + data(255) = 257 bytes
        // Second fragment: tag(1) + len(1) + data(45) = 47 bytes
        XCTAssertEqual(data.count, 257 + 47)
        XCTAssertEqual(data[0], TLV8.Tag.publicKey.rawValue)
        XCTAssertEqual(data[1], 255)
        XCTAssertEqual(data[257], TLV8.Tag.publicKey.rawValue)
        XCTAssertEqual(data[258], 45)
    }

    func testDecodeSimple() {
        let data = Data([0x06, 0x01, 0x01, 0x00, 0x01, 0x00])
        let items = TLV8.decode(data)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].0, .seqNo)
        XCTAssertEqual(items[0].1, Data([0x01]))
        XCTAssertEqual(items[1].0, .method)
        XCTAssertEqual(items[1].1, Data([0x00]))
    }

    func testDecodeFragmented() {
        // Two consecutive publicKey entries should merge
        var data = Data()
        data.append(TLV8.Tag.publicKey.rawValue)
        data.append(255)
        data.append(Data(repeating: 0xBB, count: 255))
        data.append(TLV8.Tag.publicKey.rawValue)
        data.append(45)
        data.append(Data(repeating: 0xCC, count: 45))

        let items = TLV8.decode(data)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].0, .publicKey)
        XCTAssertEqual(items[0].1.count, 300)
    }

    func testRoundtrip() {
        let original: [(TLV8.Tag, Data)] = [
            (.seqNo, Data([0x03])),
            (.publicKey, Data(repeating: 0x42, count: 384)),
            (.proof, Data(repeating: 0x99, count: 64)),
        ]
        let encoded = TLV8.encode(original)
        let decoded = TLV8.decode(encoded)

        XCTAssertEqual(decoded.count, 3)
        for (orig, dec) in zip(original, decoded) {
            XCTAssertEqual(orig.0, dec.0)
            XCTAssertEqual(orig.1, dec.1)
        }
    }

    func testFind() {
        let items: [(TLV8.Tag, Data)] = [
            (.seqNo, Data([0x01])),
            (.salt, Data([0xAA, 0xBB])),
        ]
        XCTAssertEqual(TLV8.find(.salt, in: items), Data([0xAA, 0xBB]))
        XCTAssertNil(TLV8.find(.proof, in: items))
    }
}
