import XCTest
import CryptoKit
@testable import itsytv

final class CryptoHelpersTests: XCTestCase {

    // MARK: - padNonce

    func testPadNonceProduces12Bytes() {
        let nonce = CryptoHelpers.padNonce("PS-Msg05")
        let data = nonce.withUnsafeBytes { Data($0) }
        XCTAssertEqual(data.count, 12)
    }

    func testPadNonceRightAligns() {
        let nonce = CryptoHelpers.padNonce("AB")
        let data = nonce.withUnsafeBytes { Data($0) }
        // "AB" is 2 bytes, should be at positions 10-11 with zeros before
        XCTAssertEqual(data, Data([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x41, 0x42]))
    }

    func testPadNonceKnownValues() {
        // Verify specific nonces used in the protocol
        for label in ["PS-Msg05", "PS-Msg06", "PV-Msg02", "PV-Msg03"] {
            let nonce = CryptoHelpers.padNonce(label)
            let data = nonce.withUnsafeBytes { Data($0) }
            XCTAssertEqual(data.count, 12, "Nonce for \(label) should be 12 bytes")
            // Leading bytes should be zero
            let padding = 12 - label.utf8.count
            for i in 0..<padding {
                XCTAssertEqual(data[i], 0, "Byte \(i) should be zero for \(label)")
            }
            // Trailing bytes should match the label
            let utf8 = Array(label.utf8)
            for i in 0..<utf8.count {
                XCTAssertEqual(data[padding + i], utf8[i])
            }
        }
    }

    func testPadNonceEmptyString() {
        let nonce = CryptoHelpers.padNonce("")
        let data = nonce.withUnsafeBytes { Data($0) }
        XCTAssertEqual(data, Data(count: 12))
    }

    func testPadNonceExact12Bytes() {
        let label = "123456789012" // exactly 12 bytes
        let nonce = CryptoHelpers.padNonce(label)
        let data = nonce.withUnsafeBytes { Data($0) }
        XCTAssertEqual(data, Data(label.utf8))
    }

    // MARK: - hkdfFromShared

    func testHkdfFromSharedProduces32Bytes() throws {
        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        let otherKey = Curve25519.KeyAgreement.PrivateKey()
        let shared = try privateKey.sharedSecretFromKeyAgreement(
            with: otherKey.publicKey
        )

        let derived = CryptoHelpers.hkdfFromShared(
            shared,
            salt: "test-salt",
            info: "test-info"
        )
        XCTAssertEqual(derived.count, 32)
    }

    func testHkdfFromSharedDeterministic() throws {
        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        let otherKey = Curve25519.KeyAgreement.PrivateKey()
        let shared = try privateKey.sharedSecretFromKeyAgreement(
            with: otherKey.publicKey
        )

        let first = CryptoHelpers.hkdfFromShared(shared, salt: "s", info: "i")
        let second = CryptoHelpers.hkdfFromShared(shared, salt: "s", info: "i")
        XCTAssertEqual(first, second)
    }

    func testHkdfFromSharedDifferentSaltProducesDifferentKey() throws {
        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        let otherKey = Curve25519.KeyAgreement.PrivateKey()
        let shared = try privateKey.sharedSecretFromKeyAgreement(
            with: otherKey.publicKey
        )

        let a = CryptoHelpers.hkdfFromShared(shared, salt: "salt-a", info: "info")
        let b = CryptoHelpers.hkdfFromShared(shared, salt: "salt-b", info: "info")
        XCTAssertNotEqual(a, b)
    }

    func testHkdfFromSharedDifferentInfoProducesDifferentKey() throws {
        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        let otherKey = Curve25519.KeyAgreement.PrivateKey()
        let shared = try privateKey.sharedSecretFromKeyAgreement(
            with: otherKey.publicKey
        )

        let a = CryptoHelpers.hkdfFromShared(shared, salt: "salt", info: "info-a")
        let b = CryptoHelpers.hkdfFromShared(shared, salt: "salt", info: "info-b")
        XCTAssertNotEqual(a, b)
    }
}
