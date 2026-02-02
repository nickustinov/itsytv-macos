import XCTest
import CryptoKit
@testable import itsytv

final class CompanionCryptoTests: XCTestCase {

    private func makeKeyPair() -> (encrypt: Data, decrypt: Data) {
        let encKey = SymmetricKey(size: .bits256)
        let decKey = SymmetricKey(size: .bits256)
        return (
            encKey.withUnsafeBytes { Data($0) },
            decKey.withUnsafeBytes { Data($0) }
        )
    }

    // MARK: - Roundtrip

    func testEncryptDecryptRoundtrip() throws {
        let keys = makeKeyPair()
        let sender = CompanionCrypto(encryptKey: keys.encrypt, decryptKey: keys.decrypt)
        let receiver = CompanionCrypto(encryptKey: keys.decrypt, decryptKey: keys.encrypt)

        let plaintext = Data("Hello, Companion!".utf8)
        let aad = Data([0x08, 0x00, 0x00, 0x11])

        let ciphertext = try sender.encrypt(plaintext, aad: aad)
        let decrypted = try receiver.decrypt(ciphertext, aad: aad)

        XCTAssertEqual(decrypted, plaintext)
    }

    // MARK: - Nonce increment

    func testNonceIncrementProducesDifferentCiphertext() throws {
        let keys = makeKeyPair()
        let crypto = CompanionCrypto(encryptKey: keys.encrypt, decryptKey: keys.decrypt)

        let plaintext = Data("same input".utf8)
        let aad = Data([0x07, 0x00, 0x00, 0x0A])

        let first = try crypto.encrypt(plaintext, aad: aad)
        let second = try crypto.encrypt(plaintext, aad: aad)

        XCTAssertNotEqual(first, second)
    }

    // MARK: - Wrong AAD

    func testDecryptWithWrongAADThrows() throws {
        let keys = makeKeyPair()
        let sender = CompanionCrypto(encryptKey: keys.encrypt, decryptKey: keys.decrypt)
        let receiver = CompanionCrypto(encryptKey: keys.decrypt, decryptKey: keys.encrypt)

        let plaintext = Data("secret".utf8)
        let correctAAD = Data([0x08, 0x00, 0x00, 0x06])
        let wrongAAD = Data([0x07, 0x00, 0x00, 0x06])

        let ciphertext = try sender.encrypt(plaintext, aad: correctAAD)
        XCTAssertThrowsError(try receiver.decrypt(ciphertext, aad: wrongAAD))
    }

    // MARK: - Tampered ciphertext

    func testDecryptTamperedCiphertextThrows() throws {
        let keys = makeKeyPair()
        let sender = CompanionCrypto(encryptKey: keys.encrypt, decryptKey: keys.decrypt)
        let receiver = CompanionCrypto(encryptKey: keys.decrypt, decryptKey: keys.encrypt)

        let plaintext = Data("important data".utf8)
        let aad = Data([0x08, 0x00, 0x00, 0x0E])

        var ciphertext = try sender.encrypt(plaintext, aad: aad)
        ciphertext[0] ^= 0xFF // flip bits in first byte
        XCTAssertThrowsError(try receiver.decrypt(ciphertext, aad: aad))
    }

    // MARK: - Empty plaintext

    func testEmptyPlaintextRoundtrip() throws {
        let keys = makeKeyPair()
        let sender = CompanionCrypto(encryptKey: keys.encrypt, decryptKey: keys.decrypt)
        let receiver = CompanionCrypto(encryptKey: keys.decrypt, decryptKey: keys.encrypt)

        let plaintext = Data()
        let aad = Data([0x07, 0x00, 0x00, 0x00])

        let ciphertext = try sender.encrypt(plaintext, aad: aad)
        XCTAssertEqual(ciphertext.count, 16) // tag only
        let decrypted = try receiver.decrypt(ciphertext, aad: aad)
        XCTAssertEqual(decrypted, plaintext)
    }
}
