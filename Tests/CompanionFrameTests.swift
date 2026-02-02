import XCTest
@testable import itsytv

final class CompanionFrameTests: XCTestCase {

    // MARK: - Roundtrip

    func testSerializeParseRoundtrip() {
        let cases: [(CompanionFrameType, Data)] = [
            (.noOp, Data()),
            (.opackEncrypted, Data([0xDE, 0xAD])),
            (.pairSetupStart, Data(repeating: 0x42, count: 100)),
            (.sessionData, Data(repeating: 0xFF, count: 300)),
        ]

        for (type, payload) in cases {
            let frame = CompanionFrame(type: type, payload: payload)
            let serialized = frame.serialize()
            let result = CompanionFrame.parse(from: serialized)

            XCTAssertNotNil(result, "Parse failed for type \(type)")
            XCTAssertEqual(result!.frame.type, type, "Type mismatch for \(type)")
            XCTAssertEqual(result!.frame.payload, payload, "Payload mismatch for \(type)")
            XCTAssertEqual(result!.consumed, serialized.count, "Consumed mismatch for \(type)")
        }
    }

    // MARK: - Parse edge cases

    func testParseReturnsNilWithInsufficientData() {
        XCTAssertNil(CompanionFrame.parse(from: Data()))
        XCTAssertNil(CompanionFrame.parse(from: Data([0x01, 0x00, 0x00])))

        // Header says 2-byte payload but only 1 byte follows
        XCTAssertNil(CompanionFrame.parse(from: Data([0x07, 0x00, 0x00, 0x02, 0xAA])))
    }

    // MARK: - Length encoding

    func testBigEndianLengthEncoding() {
        // Small payload: length fits in 1 byte
        let small = CompanionFrame(type: .noOp, payload: Data(repeating: 0x00, count: 5))
        let smallData = small.serialize()
        XCTAssertEqual(smallData[1], 0x00)
        XCTAssertEqual(smallData[2], 0x00)
        XCTAssertEqual(smallData[3], 0x05)

        // Large payload: 300 bytes = 0x00012C
        let large = CompanionFrame(type: .noOp, payload: Data(repeating: 0x00, count: 300))
        let largeData = large.serialize()
        XCTAssertEqual(largeData[1], 0x00)
        XCTAssertEqual(largeData[2], 0x01)
        XCTAssertEqual(largeData[3], 0x2C)
    }

    // MARK: - Header

    func testHeaderMatchesFirstFourBytesOfSerialize() {
        let frame = CompanionFrame(type: .opackEncrypted, payload: Data([0x01, 0x02, 0x03]))
        let serialized = frame.serialize()
        XCTAssertEqual(frame.header, serialized.prefix(4))
    }

    // MARK: - Unknown type

    func testUnknownRawTypeMapsToUnknown() {
        // Raw value 0xFF is not defined in CompanionFrameType
        let data = Data([0xFF, 0x00, 0x00, 0x01, 0xAA])
        let result = CompanionFrame.parse(from: data)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.frame.type, .unknown)
        XCTAssertEqual(result!.frame.payload, Data([0xAA]))
    }

    // MARK: - Empty payload

    func testEmptyPayloadFrame() {
        let frame = CompanionFrame(type: .noOp, payload: Data())
        let serialized = frame.serialize()
        XCTAssertEqual(serialized.count, 4)
        XCTAssertEqual(serialized, Data([0x01, 0x00, 0x00, 0x00]))

        let result = CompanionFrame.parse(from: serialized)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.frame.type, .noOp)
        XCTAssertEqual(result!.frame.payload, Data())
        XCTAssertEqual(result!.consumed, 4)
    }
}
