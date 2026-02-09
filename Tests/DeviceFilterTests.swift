import XCTest
@testable import itsytv

/// Tests for the rpFl flag parsing and filtering logic used in device discovery.
/// The filter requires the 0x4000 bit to be set (Apple TV with PIN pairing support).
final class DeviceFilterTests: XCTestCase {

    private func parseFlags(_ str: String) -> UInt64 {
        UInt64(str.replacingOccurrences(of: "0x", with: ""), radix: 16) ?? 0
    }

    private func passesFilter(_ flags: UInt64) -> Bool {
        flags & 0x4000 != 0
    }

    // MARK: - Filter logic

    func testFlagWithAppleTVBitPassesFilter() {
        let flags = parseFlags("0x44C4")
        XCTAssertTrue(passesFilter(flags), "0x44C4 should pass (has 0x4000)")
    }

    func testFlagWithoutAppleTVBitIsFilteredOut() {
        let flags = parseFlags("0x04C4")
        XCTAssertFalse(passesFilter(flags), "0x04C4 should be filtered out (no 0x4000)")
    }

    // MARK: - Hex parsing

    func testHexStringParsing() {
        XCTAssertEqual(parseFlags("0x44C4"), 0x44C4)
        XCTAssertEqual(parseFlags("0x4000"), 0x4000)
    }

    func testZeroHexStringFilteredOut() {
        let flags = parseFlags("0x0")
        XCTAssertEqual(flags, 0)
        XCTAssertFalse(passesFilter(flags))
    }

    func testZeroWithoutPrefixFilteredOut() {
        // "0" without 0x prefix — the replacingOccurrences still works, parsed as hex 0
        let flags = parseFlags("0")
        XCTAssertEqual(flags, 0)
        XCTAssertFalse(passesFilter(flags))
    }

    // MARK: - Unique device ID extraction

    func testExtractUniqueIDUsesRpBAWhenPresent() {
        let props = ["rpBA": "AA:BB:CC:DD:EE:FF", "rpMd": "AppleTV6,2"]
        let id = DeviceDiscovery.extractUniqueID(props: props, serviceName: "Living Room")
        XCTAssertEqual(id, "AA:BB:CC:DD:EE:FF")
    }

    func testExtractUniqueIDFallsBackToServiceName() {
        let props = ["rpMd": "AppleTV6,2"]
        let id = DeviceDiscovery.extractUniqueID(props: props, serviceName: "Living Room")
        XCTAssertEqual(id, "Living Room")
    }

    func testExtractUniqueIDIgnoresEmptyRpBA() {
        let props = ["rpBA": "", "rpMd": "AppleTV6,2"]
        let id = DeviceDiscovery.extractUniqueID(props: props, serviceName: "Living Room")
        XCTAssertEqual(id, "Living Room")
    }

    // MARK: - Credential migration

    func testMigrateMovesCredentialsFromOldToNewID() throws {
        let oldID = "test-old-\(UUID().uuidString)"
        let newID = "test-new-\(UUID().uuidString)"
        defer {
            KeychainStorage.delete(for: oldID)
            KeychainStorage.delete(for: newID)
        }

        let creds = HAPCredentials(
            clientLTSK: Data(repeating: 0x01, count: 32),
            clientLTPK: Data(repeating: 0x01, count: 32),
            clientID: "client",
            serverLTPK: Data(repeating: 0x02, count: 32),
            serverID: "server"
        )
        try KeychainStorage.save(credentials: creds, for: oldID)

        DeviceDiscovery.migrateDeviceData(from: oldID, to: newID)

        XCTAssertNotNil(KeychainStorage.load(for: newID), "Credentials should exist under new ID")
        XCTAssertNil(KeychainStorage.load(for: oldID), "Credentials should be removed from old ID")
    }

    func testMigrateSkipsWhenNewIDAlreadyHasCredentials() throws {
        let oldID = "test-old-\(UUID().uuidString)"
        let newID = "test-new-\(UUID().uuidString)"
        defer {
            KeychainStorage.delete(for: oldID)
            KeychainStorage.delete(for: newID)
        }

        let oldCreds = HAPCredentials(
            clientLTSK: Data(repeating: 0x01, count: 32),
            clientLTPK: Data(repeating: 0x01, count: 32),
            clientID: "old-client",
            serverLTPK: Data(repeating: 0x02, count: 32),
            serverID: "old-server"
        )
        let newCreds = HAPCredentials(
            clientLTSK: Data(repeating: 0x03, count: 32),
            clientLTPK: Data(repeating: 0x03, count: 32),
            clientID: "new-client",
            serverLTPK: Data(repeating: 0x04, count: 32),
            serverID: "new-server"
        )
        try KeychainStorage.save(credentials: oldCreds, for: oldID)
        try KeychainStorage.save(credentials: newCreds, for: newID)

        DeviceDiscovery.migrateDeviceData(from: oldID, to: newID)

        // New credentials should be untouched
        let loaded = KeychainStorage.load(for: newID)
        XCTAssertEqual(loaded?.clientID, "new-client")
        // Old credentials should still exist (not deleted since migration was skipped)
        XCTAssertNotNil(KeychainStorage.load(for: oldID))
    }
}
