import XCTest
import CryptoKit
@testable import itsytv

final class HAPSessionTests: XCTestCase {

    private func makeSessionPair() -> (sender: HAPSession, receiver: HAPSession) {
        let outKey = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        let inKey = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        return (
            HAPSession(outputKey: outKey, inputKey: inKey),
            HAPSession(outputKey: inKey, inputKey: outKey)
        )
    }

    // MARK: - Small payload

    func testSmallPayloadRoundtrip() throws {
        let (sender, receiver) = makeSessionPair()
        let plaintext = Data("short message".utf8)

        let encrypted = try sender.encrypt(plaintext)
        let decrypted = try receiver.decrypt(encrypted)

        XCTAssertEqual(decrypted, plaintext)
    }

    // MARK: - Exact block size

    func testExact1024BytePayload() throws {
        let (sender, receiver) = makeSessionPair()
        let plaintext = Data(repeating: 0xAB, count: 1024)

        let encrypted = try sender.encrypt(plaintext)
        // Single block: 2 (length) + 1024 (ciphertext) + 16 (tag) = 1042
        XCTAssertEqual(encrypted.count, 1042)

        let decrypted = try receiver.decrypt(encrypted)
        XCTAssertEqual(decrypted, plaintext)
    }

    // MARK: - Multi-block

    func testLargePayloadSplitsIntoMultipleBlocks() throws {
        let (sender, receiver) = makeSessionPair()
        let plaintext = Data(repeating: 0xCD, count: 2048)

        let encrypted = try sender.encrypt(plaintext)
        // Two full blocks: 2 * (2 + 1024 + 16) = 2084
        XCTAssertEqual(encrypted.count, 2084)

        let decrypted = try receiver.decrypt(encrypted)
        XCTAssertEqual(decrypted, plaintext)
    }

    // MARK: - Incremental decrypt

    func testIncrementalDecrypt() throws {
        let (sender, receiver) = makeSessionPair()
        let plaintext = Data(repeating: 0xEF, count: 500)

        let encrypted = try sender.encrypt(plaintext)

        // Feed data in two parts
        let split = encrypted.count / 2
        let firstPart = encrypted.prefix(split)
        let secondPart = encrypted.suffix(from: split)

        let partial = try receiver.decrypt(firstPart)
        let rest = try receiver.decrypt(secondPart)

        XCTAssertEqual(partial + rest, plaintext)
    }

    // MARK: - Empty data

    func testEmptyDataEncryptReturnsEmptyData() throws {
        let (sender, receiver) = makeSessionPair()
        let encrypted = try sender.encrypt(Data())
        XCTAssertEqual(encrypted.count, 0)

        let decrypted = try receiver.decrypt(encrypted)
        XCTAssertEqual(decrypted.count, 0)
    }
}
