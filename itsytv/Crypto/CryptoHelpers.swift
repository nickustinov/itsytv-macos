import Foundation
import CryptoKit

/// Shared cryptographic helpers used across pair-setup, pair-verify, and AirPlay.
enum CryptoHelpers {

    /// Pad a short string (e.g. "PS-Msg05") into a 12-byte right-aligned ChaCha20 nonce.
    static func padNonce(_ string: String) -> ChaChaPoly.Nonce {
        var bytes = [UInt8](repeating: 0, count: 12)
        let utf8 = Array(string.utf8)
        let offset = 12 - utf8.count
        for i in 0..<utf8.count {
            bytes[offset + i] = utf8[i]
        }
        // Nonce init only fails if data isn't exactly 12 bytes, which is guaranteed here.
        return try! ChaChaPoly.Nonce(data: bytes)
    }

    /// Derive a 32-byte key from a Curve25519 shared secret via HKDF-SHA512.
    static func hkdfFromShared(_ shared: SharedSecret, salt: String, info: String) -> Data {
        let derived = shared.hkdfDerivedSymmetricKey(
            using: SHA512.self,
            salt: Data(salt.utf8),
            sharedInfo: Data(info.utf8),
            outputByteCount: 32
        )
        return derived.withUnsafeBytes { Data($0) }
    }
}
