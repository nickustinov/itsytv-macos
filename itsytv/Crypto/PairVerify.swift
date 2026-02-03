import Foundation
import CryptoKit

/// Handles the pair-verify flow (M1-M4) to establish an encrypted session
/// using previously stored credentials.
final class PairVerify {

    enum Error: Swift.Error, LocalizedError {
        case invalidServerResponse
        case verificationFailed
        case decryptionFailed
        case missingTLVField(String)
        case serverError(UInt8)
        case identityMismatch

        var errorDescription: String? {
            switch self {
            case .invalidServerResponse: return "Invalid verify response"
            case .verificationFailed: return "Signature verification failed"
            case .decryptionFailed: return "Decryption failed during verify"
            case .missingTLVField(let f): return "Missing TLV field: \(f)"
            case .serverError(let c): return "Apple TV error: \(c)"
            case .identityMismatch: return "Server identity mismatch"
            }
        }
    }

    private let credentials: HAPCredentials
    private let ephemeralKey = Curve25519.KeyAgreement.PrivateKey()
    private var sharedSecret: SharedSecret?
    private var sessionKey: Data?

    init(credentials: HAPCredentials) {
        self.credentials = credentials
    }

    // MARK: - M1: send ephemeral public key

    func startVerify() -> CompanionFrame {
        let tlv = TLV8.encode([
            (.seqNo, Data([0x01])),
            (.publicKey, ephemeralKey.publicKey.rawRepresentation),
        ])
        let payload = OPACK.pack(.dictionary([
            ("_pd", .data(tlv)),
            ("_auTy", .int(4)),
        ]))
        return CompanionFrame(type: .pairVerifyStart, payload: payload)
    }

    // MARK: - M3: process server's M2, send encrypted proof

    func processAndProve(m2Frame: CompanionFrame) throws -> CompanionFrame {
        let response = try OPACK.unpack(m2Frame.payload)
        guard let pdData = response["_pd"]?.dataValue else {
            throw Error.invalidServerResponse
        }

        let tlvItems = TLV8.decode(pdData)

        if let errorData = TLV8.find(.error, in: tlvItems), let code = errorData.first {
            throw Error.serverError(code)
        }

        guard let serverEphemeralData = TLV8.find(.publicKey, in: tlvItems) else {
            throw Error.missingTLVField("publicKey")
        }
        guard let encryptedData = TLV8.find(.encryptedData, in: tlvItems) else {
            throw Error.missingTLVField("encryptedData")
        }

        // Compute shared secret via X25519
        let serverEphemeral = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: serverEphemeralData)
        let shared = try ephemeralKey.sharedSecretFromKeyAgreement(with: serverEphemeral)
        self.sharedSecret = shared

        // Derive session key for verify encryption
        let sessionKeyData = CryptoHelpers.hkdfFromShared(
            shared,
            salt: "Pair-Verify-Encrypt-Salt",
            info: "Pair-Verify-Encrypt-Info"
        )
        self.sessionKey = sessionKeyData

        // Decrypt server's proof
        let nonce = CryptoHelpers.padNonce("PV-Msg02")
        let symmetricKey = SymmetricKey(data: sessionKeyData)
        let edBytes = Data(encryptedData)
        let tagStart = edBytes.count - 16
        let sealedBox = try ChaChaPoly.SealedBox(
            nonce: nonce,
            ciphertext: edBytes.prefix(tagStart),
            tag: edBytes.suffix(16)
        )
        let decrypted = try ChaChaPoly.open(sealedBox, using: symmetricKey)

        let innerTLV = TLV8.decode(decrypted)
        guard let serverIDData = TLV8.find(.identifier, in: innerTLV) else {
            throw Error.missingTLVField("identifier")
        }
        guard let serverSignature = TLV8.find(.signature, in: innerTLV) else {
            throw Error.missingTLVField("signature")
        }

        // Verify server identity matches stored credentials
        let serverID = String(data: Data(serverIDData), encoding: .utf8) ?? ""
        guard serverID == credentials.serverID else {
            throw Error.identityMismatch
        }

        // Verify server's Ed25519 signature
        var serverInfo = Data()
        serverInfo.append(serverEphemeralData)
        serverInfo.append(serverIDData)
        serverInfo.append(ephemeralKey.publicKey.rawRepresentation)

        let serverLTPK = try Curve25519.Signing.PublicKey(rawRepresentation: credentials.serverLTPK)
        guard serverLTPK.isValidSignature(serverSignature, for: serverInfo) else {
            throw Error.verificationFailed
        }

        // Build our encrypted proof (M3)
        let clientIDData = Data(credentials.clientID.utf8)
        var deviceInfo = Data()
        deviceInfo.append(ephemeralKey.publicKey.rawRepresentation)
        deviceInfo.append(clientIDData)
        deviceInfo.append(serverEphemeralData)

        let clientLTSK = try Curve25519.Signing.PrivateKey(rawRepresentation: credentials.clientLTSK)
        let deviceSignature = try clientLTSK.signature(for: deviceInfo)

        let innerTLVOut = TLV8.encode([
            (.identifier, clientIDData),
            (.signature, Data(deviceSignature)),
        ])

        let nonceOut = CryptoHelpers.padNonce("PV-Msg03")
        let sealed = try ChaChaPoly.seal(innerTLVOut, using: symmetricKey, nonce: nonceOut)
        let encryptedOut = Data(sealed.ciphertext) + Data(sealed.tag)

        let tlvOut = TLV8.encode([
            (.seqNo, Data([0x03])),
            (.encryptedData, encryptedOut),
        ])
        let payload = OPACK.pack(.dictionary([
            ("_pd", .data(tlvOut)),
        ]))
        return CompanionFrame(type: .pairVerifyNext, payload: payload)
    }

    // MARK: - Derive transport encryption keys

    func deriveTransportKeys() -> CompanionCrypto? {
        guard let shared = sharedSecret else { return nil }

        let encryptKey = CryptoHelpers.hkdfFromShared(shared, salt: "", info: "ClientEncrypt-main")
        let decryptKey = CryptoHelpers.hkdfFromShared(shared, salt: "", info: "ServerEncrypt-main")
        return CompanionCrypto(encryptKey: encryptKey, decryptKey: decryptKey)
    }

}
