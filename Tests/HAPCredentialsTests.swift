import XCTest
import CryptoKit
@testable import itsytv

final class HAPCredentialsTests: XCTestCase {

    // MARK: - JSON roundtrip

    func testEncodeDecodeRoundtrip() throws {
        let signingKey = Curve25519.Signing.PrivateKey()
        let serverKey = Curve25519.Signing.PrivateKey()

        let original = HAPCredentials(
            clientLTSK: signingKey.rawRepresentation,
            clientLTPK: signingKey.publicKey.rawRepresentation,
            clientID: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
            serverLTPK: serverKey.publicKey.rawRepresentation,
            serverID: "Apple TV Living Room"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HAPCredentials.self, from: data)

        XCTAssertEqual(decoded.clientLTSK, original.clientLTSK)
        XCTAssertEqual(decoded.clientLTPK, original.clientLTPK)
        XCTAssertEqual(decoded.clientID, original.clientID)
        XCTAssertEqual(decoded.serverLTPK, original.serverLTPK)
        XCTAssertEqual(decoded.serverID, original.serverID)
    }

    func testKeySizesAreCorrect() {
        let signingKey = Curve25519.Signing.PrivateKey()
        let serverKey = Curve25519.Signing.PrivateKey()

        let creds = HAPCredentials(
            clientLTSK: signingKey.rawRepresentation,
            clientLTPK: signingKey.publicKey.rawRepresentation,
            clientID: "test",
            serverLTPK: serverKey.publicKey.rawRepresentation,
            serverID: "server"
        )

        XCTAssertEqual(creds.clientLTSK.count, 32)
        XCTAssertEqual(creds.clientLTPK.count, 32)
        XCTAssertEqual(creds.serverLTPK.count, 32)
    }

    func testDecodingCorruptedDataThrows() {
        let garbage = Data("not json".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(HAPCredentials.self, from: garbage))
    }

    func testDecodingMissingFieldThrows() {
        // JSON with missing serverID
        let json = """
        {"clientLTSK":"AA==","clientLTPK":"AA==","clientID":"id","serverLTPK":"AA=="}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(HAPCredentials.self, from: json))
    }

    // MARK: - Reconstructing keys from stored data

    func testStoredKeysCanReconstructSigningKey() throws {
        let original = Curve25519.Signing.PrivateKey()
        let creds = HAPCredentials(
            clientLTSK: original.rawRepresentation,
            clientLTPK: original.publicKey.rawRepresentation,
            clientID: "test",
            serverLTPK: Data(count: 32),
            serverID: "server"
        )

        let restored = try Curve25519.Signing.PrivateKey(rawRepresentation: creds.clientLTSK)
        XCTAssertEqual(restored.publicKey.rawRepresentation, creds.clientLTPK)
    }

    func testStoredServerKeyCanReconstructPublicKey() throws {
        let serverKey = Curve25519.Signing.PrivateKey()
        let creds = HAPCredentials(
            clientLTSK: Data(count: 32),
            clientLTPK: Data(count: 32),
            clientID: "test",
            serverLTPK: serverKey.publicKey.rawRepresentation,
            serverID: "server"
        )

        let restored = try Curve25519.Signing.PublicKey(rawRepresentation: creds.serverLTPK)
        XCTAssertEqual(restored.rawRepresentation, serverKey.publicKey.rawRepresentation)
    }
}
