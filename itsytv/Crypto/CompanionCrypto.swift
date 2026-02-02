import Foundation
import CryptoKit

/// ChaCha20-Poly1305 encryption for the Companion protocol.
/// Each direction has its own key and nonce counter.
final class CompanionCrypto {
    private let encryptKey: SymmetricKey
    private let decryptKey: SymmetricKey
    private var encryptNonce: UInt64 = 0
    private var decryptNonce: UInt64 = 0

    init(encryptKey: Data, decryptKey: Data) {
        self.encryptKey = SymmetricKey(data: encryptKey)
        self.decryptKey = SymmetricKey(data: decryptKey)
    }

    /// Encrypt payload with AAD = frame header. Returns ciphertext + 16-byte tag.
    func encrypt(_ plaintext: Data, aad: Data) throws -> Data {
        let nonce = makeNonce(encryptNonce)
        encryptNonce += 1
        let sealedBox = try ChaChaPoly.seal(plaintext, using: encryptKey, nonce: nonce, authenticating: aad)
        return Data(sealedBox.ciphertext) + Data(sealedBox.tag)
    }

    /// Decrypt ciphertext (with 16-byte tag appended) using AAD = frame header.
    func decrypt(_ ciphertextAndTag: Data, aad: Data) throws -> Data {
        let nonce = makeNonce(decryptNonce)
        decryptNonce += 1
        let data = Data(ciphertextAndTag)
        let tagStart = data.count - 16
        let sealedBox = try ChaChaPoly.SealedBox(
            nonce: nonce,
            ciphertext: data.prefix(tagStart),
            tag: data.suffix(16)
        )
        return try ChaChaPoly.open(sealedBox, using: decryptKey, authenticating: aad)
    }

    /// 12-byte nonce: counter as a 12-byte little-endian integer.
    private func makeNonce(_ counter: UInt64) -> ChaChaPoly.Nonce {
        var nonceBytes = [UInt8](repeating: 0, count: 12)
        var c = counter.littleEndian
        withUnsafeBytes(of: &c) { src in
            for i in 0..<8 { nonceBytes[i] = src[i] }
        }
        return try! ChaChaPoly.Nonce(data: nonceBytes)
    }
}
