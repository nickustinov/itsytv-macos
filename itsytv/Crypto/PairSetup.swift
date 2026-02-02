import Foundation
import CryptoKit
import SRP
import os.log

private let log = Logger(subsystem: "com.itsytv.app", category: "PairSetup")

/// Credentials stored after successful pair-setup.
struct HAPCredentials: Codable {
    let clientLTSK: Data   // Ed25519 private key (32 bytes)
    let clientLTPK: Data   // Ed25519 public key (32 bytes)
    let clientID: String   // Client pairing UUID
    let serverLTPK: Data   // Apple TV's Ed25519 public key (32 bytes)
    let serverID: String   // Apple TV's identifier
}

/// Handles the SRP-based pair-setup flow (M1-M6) for the Companion protocol.
final class PairSetup {

    enum Error: Swift.Error, LocalizedError {
        case invalidServerResponse
        case srpVerificationFailed
        case decryptionFailed
        case missingTLVField(String)
        case serverError(UInt8)

        var errorDescription: String? {
            switch self {
            case .invalidServerResponse: return "Invalid response from Apple TV"
            case .srpVerificationFailed: return "PIN verification failed"
            case .decryptionFailed: return "Failed to decrypt server identity"
            case .missingTLVField(let f): return "Missing TLV field: \(f)"
            case .serverError(let c): return "Apple TV error: \(c)"
            }
        }
    }

    private let connection: CompanionConnection
    private let configuration = SRPConfiguration<SHA512>(.N3072)
    private lazy var client = SRPClient(configuration: configuration)
    private var clientKeys: SRPKeyPair!
    private var serverPublicKey: SRPKey!
    private var sharedSecret: SRPKey!
    private var clientProofBytes: [UInt8]!
    private var sessionKey: [UInt8]! // K = H(S), using minimal bytes of S

    // Ed25519 long-term identity
    private let signingKey = Curve25519.Signing.PrivateKey()
    private let clientID = UUID().uuidString

    init(connection: CompanionConnection) {
        self.connection = connection
    }

    // MARK: - M1: initiate pairing

    func startPairing() -> CompanionFrame {
        clientKeys = client.generateKeys()

        let tlv = TLV8.encode([
            (.seqNo, Data([0x01])),
            (.method, Data([0x00])),
        ])
        let payload = OPACK.pack(.dictionary([
            ("_pd", .data(tlv)),
            ("_pwTy", .int(1)),
        ]))
        return CompanionFrame(type: .pairSetupStart, payload: payload)
    }

    // MARK: - M3: process server's salt+pubkey (M2), send SRP proof

    func processChallengeAndProve(m2Frame: CompanionFrame, pin: String) throws -> CompanionFrame {
        let response = try OPACK.unpack(m2Frame.payload)
        guard let pdData = response["_pd"]?.dataValue else {
            throw Error.invalidServerResponse
        }

        let tlvItems = TLV8.decode(pdData)

        if let errorData = TLV8.find(.error, in: tlvItems), let code = errorData.first {
            throw Error.serverError(code)
        }

        guard let salt = TLV8.find(.salt, in: tlvItems) else {
            throw Error.missingTLVField("salt")
        }
        guard let serverPubKeyData = TLV8.find(.publicKey, in: tlvItems) else {
            throw Error.missingTLVField("publicKey")
        }

        log.info("M2 received — salt: \(salt.count) bytes, serverPubKey: \(serverPubKeyData.count) bytes")

        let serverPubKey = SRPKey(Array(serverPubKeyData))
        self.serverPublicKey = serverPubKey

        // Use swift-srp for the core DH math (computing S)
        let sharedSecret = try client.calculateSharedSecret(
            username: "Pair-Setup",
            password: pin,
            salt: Array(salt),
            clientKeys: clientKeys,
            serverPublicKey: serverPubKey
        )
        self.sharedSecret = sharedSecret

        // Compute K and M1 manually to match pyatv's srptools encoding.
        // srptools uses minimal-length big-endian bytes (no zero-padding) for:
        //   - S when computing K = H(S)
        //   - A and B in the M1 proof
        //   - H(N) XOR H(g) as integer XOR

        let sBytes = trimLeadingZeros(sharedSecret.bytes)
        let aBytes = trimLeadingZeros(clientKeys.public.bytes)
        let bBytes = trimLeadingZeros(Array(serverPubKeyData))
        let nBytes = srpN3072Bytes
        let gBytes: [UInt8] = [5]

        // K = H(S) with minimal bytes
        let K = sha512(sBytes)
        self.sessionKey = K

        // M1 = H( (H(N) XOR H(g)) | H(I) | salt | A | B | K )
        let hN = sha512AsBigInt(nBytes)
        let hG = sha512AsBigInt(gBytes)
        let xorResult = bigIntXOR(hN, hG)
        let hI = sha512(Array("Pair-Setup".utf8))

        var m1Input = Data()
        m1Input.append(contentsOf: bigIntToMinimalBytes(xorResult))
        m1Input.append(contentsOf: hI)
        m1Input.append(salt)
        m1Input.append(contentsOf: aBytes)
        m1Input.append(contentsOf: bBytes)
        m1Input.append(contentsOf: K)

        let M1 = sha512(Array(m1Input))
        self.clientProofBytes = M1

        let tlvOut = TLV8.encode([
            (.seqNo, Data([0x03])),
            (.publicKey, Data(clientKeys.public.bytes)),
            (.proof, Data(M1)),
        ])
        let payload = OPACK.pack(.dictionary([
            ("_pd", .data(tlvOut)),
            ("_pwTy", .int(1)),
        ]))
        return CompanionFrame(type: .pairSetupNext, payload: payload)
    }

    // MARK: - M5: verify server proof (M4), send encrypted identity

    func verifyAndExchangeIdentity(m4Frame: CompanionFrame) throws -> (frame: CompanionFrame, credentials: HAPCredentials) {
        let response = try OPACK.unpack(m4Frame.payload)
        guard let pdData = response["_pd"]?.dataValue else {
            throw Error.invalidServerResponse
        }

        let tlvItems = TLV8.decode(pdData)

        if let errorData = TLV8.find(.error, in: tlvItems), let code = errorData.first {
            throw Error.serverError(code)
        }

        guard let serverProof = TLV8.find(.proof, in: tlvItems) else {
            throw Error.missingTLVField("proof")
        }

        // Verify server's proof: M2 = H(A | M1 | K) with minimal bytes for A
        let aBytes = trimLeadingZeros(clientKeys.public.bytes)
        var m2Input = Data()
        m2Input.append(contentsOf: aBytes)
        m2Input.append(contentsOf: clientProofBytes)
        m2Input.append(contentsOf: sessionKey)
        let expectedM2 = sha512(Array(m2Input))

        guard Array(serverProof) == expectedM2 else {
            log.error("Server proof mismatch")
            throw Error.srpVerificationFailed
        }

        log.info("Server proof verified, building M5 identity exchange")

        // Derive signing material for our identity
        // IMPORTANT: the HKDF input key material is K (session key), not raw S
        let signingMaterial = hkdf(
            inputKey: Data(sessionKey),
            salt: "Pair-Setup-Controller-Sign-Salt",
            info: "Pair-Setup-Controller-Sign-Info"
        )

        // Derive encryption key for M5/M6
        let encryptionKey = hkdf(
            inputKey: Data(sessionKey),
            salt: "Pair-Setup-Encrypt-Salt",
            info: "Pair-Setup-Encrypt-Info"
        )

        // Construct device info and sign it
        let clientIDData = Data(clientID.utf8)
        let ltpk = signingKey.publicKey.rawRepresentation
        var deviceInfo = Data()
        deviceInfo.append(signingMaterial)
        deviceInfo.append(clientIDData)
        deviceInfo.append(ltpk)
        let signature = try signingKey.signature(for: deviceInfo)

        // Build inner TLV
        let innerTLV = TLV8.encode([
            (.identifier, clientIDData),
            (.publicKey, ltpk),
            (.signature, Data(signature)),
        ])

        // Encrypt with ChaCha20-Poly1305
        let nonce = padNonce("PS-Msg05")
        let symmetricKey = SymmetricKey(data: encryptionKey)
        let sealed = try ChaChaPoly.seal(innerTLV, using: symmetricKey, nonce: nonce)
        let encryptedData = Data(sealed.ciphertext) + Data(sealed.tag)

        let tlvOut = TLV8.encode([
            (.seqNo, Data([0x05])),
            (.encryptedData, encryptedData),
        ])
        let payload = OPACK.pack(.dictionary([
            ("_pd", .data(tlvOut)),
            ("_pwTy", .int(1)),
        ]))
        let frame = CompanionFrame(type: .pairSetupNext, payload: payload)

        let credentials = HAPCredentials(
            clientLTSK: signingKey.rawRepresentation,
            clientLTPK: Data(ltpk),
            clientID: clientID,
            serverLTPK: Data(),
            serverID: ""
        )
        return (frame, credentials)
    }

    // MARK: - M6: process server's encrypted identity

    func processServerIdentity(m6Frame: CompanionFrame, partialCredentials: HAPCredentials) throws -> HAPCredentials {
        let response = try OPACK.unpack(m6Frame.payload)
        guard let pdData = response["_pd"]?.dataValue else {
            throw Error.invalidServerResponse
        }

        let tlvItems = TLV8.decode(pdData)

        if let errorData = TLV8.find(.error, in: tlvItems), let code = errorData.first {
            throw Error.serverError(code)
        }

        guard let encryptedData = TLV8.find(.encryptedData, in: tlvItems) else {
            throw Error.missingTLVField("encryptedData")
        }

        let encryptionKey = hkdf(
            inputKey: Data(sessionKey),
            salt: "Pair-Setup-Encrypt-Salt",
            info: "Pair-Setup-Encrypt-Info"
        )
        let nonce = padNonce("PS-Msg06")
        let symmetricKey = SymmetricKey(data: encryptionKey)

        let edBytes = Data(encryptedData)
        let tagStart = edBytes.count - 16
        let sealedBox = try ChaChaPoly.SealedBox(
            nonce: nonce,
            ciphertext: edBytes.prefix(tagStart),
            tag: edBytes.suffix(16)
        )
        let decrypted = try ChaChaPoly.open(sealedBox, using: symmetricKey)

        let innerTLV = TLV8.decode(decrypted)
        guard let serverID = TLV8.find(.identifier, in: innerTLV) else {
            throw Error.missingTLVField("identifier")
        }
        guard let serverLTPK = TLV8.find(.publicKey, in: innerTLV) else {
            throw Error.missingTLVField("publicKey")
        }

        return HAPCredentials(
            clientLTSK: partialCredentials.clientLTSK,
            clientLTPK: partialCredentials.clientLTPK,
            clientID: partialCredentials.clientID,
            serverLTPK: Data(serverLTPK),
            serverID: String(data: Data(serverID), encoding: .utf8) ?? ""
        )
    }

    // MARK: - SRP math helpers (matching pyatv's srptools encoding)

    private func sha512(_ data: [UInt8]) -> [UInt8] {
        Array(SHA512.hash(data: data))
    }

    /// Hash bytes, return result as a big integer (array of bytes, minimal representation).
    private func sha512AsBigInt(_ data: [UInt8]) -> [UInt8] {
        sha512(data)
    }

    /// XOR two big-endian byte arrays as integers.
    /// Result is minimal-length (leading zeros stripped).
    private func bigIntXOR(_ a: [UInt8], _ b: [UInt8]) -> [UInt8] {
        let maxLen = max(a.count, b.count)
        // Right-align both arrays
        let aPadded = [UInt8](repeating: 0, count: maxLen - a.count) + a
        let bPadded = [UInt8](repeating: 0, count: maxLen - b.count) + b
        var result = [UInt8](repeating: 0, count: maxLen)
        for i in 0..<maxLen {
            result[i] = aPadded[i] ^ bPadded[i]
        }
        return trimLeadingZeros(result)
    }

    private func bigIntToMinimalBytes(_ bytes: [UInt8]) -> [UInt8] {
        trimLeadingZeros(bytes)
    }

    private func trimLeadingZeros(_ bytes: [UInt8]) -> [UInt8] {
        guard let firstNonZero = bytes.firstIndex(where: { $0 != 0 }) else {
            return [0]
        }
        return Array(bytes[firstNonZero...])
    }

    // MARK: - Crypto helpers

    private func hkdf(inputKey: Data, salt: String, info: String) -> Data {
        let key = SymmetricKey(data: inputKey)
        let derived = HKDF<SHA512>.deriveKey(
            inputKeyMaterial: key,
            salt: Data(salt.utf8),
            info: Data(info.utf8),
            outputByteCount: 32
        )
        return derived.withUnsafeBytes { Data($0) }
    }

    private func padNonce(_ string: String) -> ChaChaPoly.Nonce {
        var bytes = [UInt8](repeating: 0, count: 12)
        let utf8 = Array(string.utf8)
        let offset = 12 - utf8.count
        for i in 0..<utf8.count {
            bytes[offset + i] = utf8[i]
        }
        return try! ChaChaPoly.Nonce(data: bytes)
    }
}

// MARK: - RFC 5054 3072-bit SRP group constants

/// The standard RFC 5054 3072-bit prime N as big-endian bytes (384 bytes).
private let srpN3072Bytes: [UInt8] = {
    let hex =
        "FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD1" +
        "29024E088A67CC74020BBEA63B139B22514A08798E3404DD" +
        "EF9519B3CD3A431B302B0A6DF25F14374FE1356D6D51C245" +
        "E485B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7ED" +
        "EE386BFB5A899FA5AE9F24117C4B1FE649286651ECE45B3D" +
        "C2007CB8A163BF0598DA48361C55D39A69163FA8FD24CF5F" +
        "83655D23DCA3AD961C62F356208552BB9ED529077096966D" +
        "670C354E4ABC9804F1746C08CA18217C32905E462E36CE3B" +
        "E39E772C180E86039B2783A2EC07A28FB5C55DF06F4C52C9" +
        "DE2BCBF6955817183995497CEA956AE515D2261898FA0510" +
        "15728E5A8AAAC42DAD33170D04507A33A85521ABDF1CBA64" +
        "ECFB850458DBEF0A8AEA71575D060C7DB3970F85A6E1E4C7" +
        "ABF5AE8CDB0933D71E8C94E04A25619DCEE3D2261AD2EE6B" +
        "F12FFA06D98A0864D87602733EC86A64521F2B18177B200C" +
        "BBE117577A615D6C770988C0BAD946E208E24FA074E5AB31" +
        "43DB5BFCE0FD108E4B82D120A93AD2CAFFFFFFFFFFFFFFFF"
    var bytes = [UInt8]()
    bytes.reserveCapacity(384)
    var i = hex.startIndex
    while i < hex.endIndex {
        let j = hex.index(i, offsetBy: 2)
        bytes.append(UInt8(hex[i..<j], radix: 16)!)
        i = j
    }
    assert(bytes.count == 384, "N3072 must be 384 bytes")
    return bytes
}()
