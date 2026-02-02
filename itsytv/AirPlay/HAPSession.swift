import Foundation
import CryptoKit
import os.log

private let log = Logger(subsystem: "com.itsytv.app", category: "HAPSession")

/// HAP session encryption using 1024-byte block framing with ChaCha20-Poly1305.
/// Used on AirPlay control, event, and data stream channels.
///
/// Sending: split plaintext into 1024-byte chunks, encrypt each with AAD = 2-byte LE length.
/// Receiving: parse 2-byte LE length + (length + 16) bytes of ciphertext+tag per block.
/// Nonce: 4 zero bytes + 8-byte LE counter (increments per block).
final class HAPSession {
    private let outputKey: SymmetricKey
    private let inputKey: SymmetricKey
    private var outputCounter: UInt64 = 0
    private var inputCounter: UInt64 = 0
    private var decryptBuffer = Data()

    private static let blockSize = 1024

    init(outputKey: Data, inputKey: Data) {
        self.outputKey = SymmetricKey(data: outputKey)
        self.inputKey = SymmetricKey(data: inputKey)
    }

    // MARK: - Encrypt

    /// Encrypt data using 1024-byte block framing.
    /// Each block: [2-byte LE length][encrypted chunk + 16-byte tag]
    func encrypt(_ data: Data) throws -> Data {
        var result = Data()
        var offset = 0

        while offset < data.count {
            let remaining = data.count - offset
            let chunkSize = min(remaining, HAPSession.blockSize)
            let chunk = data[offset..<offset + chunkSize]

            // AAD is the 2-byte LE length of the plaintext chunk
            var lengthBytes = Data(count: 2)
            lengthBytes[0] = UInt8(chunkSize & 0xFF)
            lengthBytes[1] = UInt8((chunkSize >> 8) & 0xFF)

            let nonce = makeNonce(outputCounter)
            outputCounter += 1

            let sealedBox = try ChaChaPoly.seal(
                chunk, using: outputKey, nonce: nonce, authenticating: lengthBytes
            )

            result.append(lengthBytes)
            result.append(Data(sealedBox.ciphertext))
            result.append(Data(sealedBox.tag))

            offset += chunkSize
        }

        return result
    }

    // MARK: - Decrypt

    /// Feed received data into the decrypt buffer and return any complete decrypted plaintext.
    func decrypt(_ data: Data) throws -> Data {
        decryptBuffer.append(data)
        var result = Data()

        while true {
            // Need at least 2 bytes for length
            guard decryptBuffer.count >= 2 else { break }

            let length = Int(decryptBuffer[decryptBuffer.startIndex])
                | (Int(decryptBuffer[decryptBuffer.startIndex + 1]) << 8)

            // Need length + 16 bytes of ciphertext+tag after the 2-byte header
            let totalNeeded = 2 + length + 16
            guard decryptBuffer.count >= totalNeeded else { break }

            let lengthBytes = Data(decryptBuffer[decryptBuffer.startIndex..<decryptBuffer.startIndex + 2])
            let ciphertextStart = decryptBuffer.startIndex + 2
            let ciphertextEnd = ciphertextStart + length
            let tagEnd = ciphertextEnd + 16

            let ciphertext = decryptBuffer[ciphertextStart..<ciphertextEnd]
            let tag = decryptBuffer[ciphertextEnd..<tagEnd]

            let nonce = makeNonce(inputCounter)
            inputCounter += 1

            let sealedBox = try ChaChaPoly.SealedBox(
                nonce: nonce,
                ciphertext: ciphertext,
                tag: tag
            )
            let plaintext = try ChaChaPoly.open(
                sealedBox, using: inputKey, authenticating: lengthBytes
            )

            result.append(plaintext)
            decryptBuffer = Data(decryptBuffer[tagEnd...])
        }

        return result
    }

    // MARK: - Nonce

    /// 12-byte nonce: 4 zero bytes + 8-byte LE counter.
    private func makeNonce(_ counter: UInt64) -> ChaChaPoly.Nonce {
        var nonceBytes = [UInt8](repeating: 0, count: 12)
        var c = counter.littleEndian
        withUnsafeBytes(of: &c) { src in
            for i in 0..<8 { nonceBytes[4 + i] = src[i] }
        }
        return try! ChaChaPoly.Nonce(data: nonceBytes)
    }
}
