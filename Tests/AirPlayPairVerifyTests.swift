import XCTest
import CryptoKit
@testable import itsytv

final class AirPlayPairVerifyTests: XCTestCase {

    private func makeCredentials() -> HAPCredentials {
        let signingKey = Curve25519.Signing.PrivateKey()
        return HAPCredentials(
            clientLTSK: signingKey.rawRepresentation,
            clientLTPK: signingKey.publicKey.rawRepresentation,
            clientID: "test-client-id",
            serverLTPK: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation,
            serverID: "test-server-id"
        )
    }

    // MARK: - M1 structure

    func testMakeM1ProducesValidTLV() {
        let creds = makeCredentials()
        let verify = AirPlayPairVerify(credentials: creds)
        let m1 = verify.makeM1()

        let tlv = TLV8.decode(m1)
        let seqNo = TLV8.find(.seqNo, in: tlv)
        XCTAssertEqual(seqNo, Data([0x01]))

        let pubKey = TLV8.find(.publicKey, in: tlv)
        XCTAssertNotNil(pubKey)
        XCTAssertEqual(pubKey?.count, 32)
    }

    func testMakeM1EachInstanceUsesUniqueKey() {
        let creds = makeCredentials()
        let v1 = AirPlayPairVerify(credentials: creds)
        let v2 = AirPlayPairVerify(credentials: creds)

        let m1a = v1.makeM1()
        let m1b = v2.makeM1()

        let pk1 = TLV8.find(.publicKey, in: TLV8.decode(m1a))
        let pk2 = TLV8.find(.publicKey, in: TLV8.decode(m1b))
        XCTAssertNotEqual(pk1, pk2)
    }

    // MARK: - deriveKeys

    func testDeriveKeysReturnsNilWithoutM2() {
        let creds = makeCredentials()
        let verify = AirPlayPairVerify(credentials: creds)
        _ = verify.makeM1()

        let keys = verify.deriveKeys(
            salt: "MediaRemote-Salt",
            outputInfo: "MediaRemote-Write-Encryption-Key",
            inputInfo: "MediaRemote-Read-Encryption-Key"
        )
        XCTAssertNil(keys)
    }

    // MARK: - processM2AndMakeM3 error handling

    func testProcessM2WithServerErrorThrows() {
        let creds = makeCredentials()
        let verify = AirPlayPairVerify(credentials: creds)
        _ = verify.makeM1()

        // Build a TLV response with error code
        let errorResponse = TLV8.encode([
            (.seqNo, Data([0x02])),
            (.error, Data([0x06])), // auth error
        ])

        XCTAssertThrowsError(try verify.processM2AndMakeM3(errorResponse)) { error in
            if case AirPlayPairVerify.Error.serverError(let code) = error {
                XCTAssertEqual(code, 0x06)
            } else {
                XCTFail("Expected serverError, got \(error)")
            }
        }
    }

    func testProcessM2WithMissingPublicKeyThrows() {
        let creds = makeCredentials()
        let verify = AirPlayPairVerify(credentials: creds)
        _ = verify.makeM1()

        // TLV with seq but no publicKey
        let response = TLV8.encode([
            (.seqNo, Data([0x02])),
        ])

        XCTAssertThrowsError(try verify.processM2AndMakeM3(response)) { error in
            if case AirPlayPairVerify.Error.missingTLVField(let field) = error {
                XCTAssertEqual(field, "publicKey")
            } else {
                XCTFail("Expected missingTLVField, got \(error)")
            }
        }
    }
}
