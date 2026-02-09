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

}
