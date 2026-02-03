import XCTest
import CryptoKit
@testable import itsytv

final class PairVerifyTests: XCTestCase {

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

    // MARK: - M1 frame structure

    func testStartVerifyProducesValidFrame() {
        let creds = makeCredentials()
        let verify = PairVerify(credentials: creds)
        let frame = verify.startVerify()

        XCTAssertEqual(frame.type, .pairVerifyStart)
        XCTAssertFalse(frame.payload.isEmpty)
    }

    func testStartVerifyContainsTLVWithSeqAndPublicKey() throws {
        let creds = makeCredentials()
        let verify = PairVerify(credentials: creds)
        let frame = verify.startVerify()

        // Payload is OPACK-wrapped
        let opack = try OPACK.unpack(frame.payload)
        let pd = try XCTUnwrap(opack["_pd"]?.dataValue)
        let tlv = TLV8.decode(pd)

        let seqNo = TLV8.find(.seqNo, in: tlv)
        XCTAssertEqual(seqNo, Data([0x01]))

        let pubKey = TLV8.find(.publicKey, in: tlv)
        XCTAssertNotNil(pubKey)
        XCTAssertEqual(pubKey?.count, 32) // Curve25519 public key
    }

    func testStartVerifyIncludesAuthType() throws {
        let creds = makeCredentials()
        let verify = PairVerify(credentials: creds)
        let frame = verify.startVerify()

        let opack = try OPACK.unpack(frame.payload)
        let auTy = opack["_auTy"]?.intValue
        XCTAssertEqual(auTy, 4)
    }

    // MARK: - Transport keys

    func testDeriveTransportKeysReturnsNilWithoutM2() {
        let creds = makeCredentials()
        let verify = PairVerify(credentials: creds)
        _ = verify.startVerify()

        // Without processing M2, there's no shared secret
        let keys = verify.deriveTransportKeys()
        XCTAssertNil(keys)
    }

    // MARK: - Each call produces unique ephemeral key

    func testEachInstanceUsesUniqueEphemeralKey() throws {
        let creds = makeCredentials()
        let verify1 = PairVerify(credentials: creds)
        let verify2 = PairVerify(credentials: creds)

        let frame1 = verify1.startVerify()
        let frame2 = verify2.startVerify()

        let opack1 = try OPACK.unpack(frame1.payload)
        let opack2 = try OPACK.unpack(frame2.payload)
        let pk1 = opack1["_pd"]?.dataValue.flatMap { TLV8.find(.publicKey, in: TLV8.decode($0)) }
        let pk2 = opack2["_pd"]?.dataValue.flatMap { TLV8.find(.publicKey, in: TLV8.decode($0)) }

        XCTAssertNotEqual(pk1, pk2)
    }
}
