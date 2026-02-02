import XCTest
@testable import itsytv

final class CompanionButtonTests: XCTestCase {

    func testKeyButtonRawValues() {
        XCTAssertEqual(CompanionButton.up.rawValue, 1)
        XCTAssertEqual(CompanionButton.down.rawValue, 2)
        XCTAssertEqual(CompanionButton.left.rawValue, 3)
        XCTAssertEqual(CompanionButton.right.rawValue, 4)
        XCTAssertEqual(CompanionButton.menu.rawValue, 5)
        XCTAssertEqual(CompanionButton.select.rawValue, 6)
        XCTAssertEqual(CompanionButton.home.rawValue, 7)
        XCTAssertEqual(CompanionButton.volumeUp.rawValue, 8)
        XCTAssertEqual(CompanionButton.volumeDown.rawValue, 9)
        XCTAssertEqual(CompanionButton.siri.rawValue, 10)
        XCTAssertEqual(CompanionButton.playPause.rawValue, 14)
    }

    func testAllCasesAccountedFor() {
        let expected: [CompanionButton] = [
            .up, .down, .left, .right, .menu, .select, .home,
            .volumeUp, .volumeDown, .siri, .screensaver, .sleep,
            .wake, .playPause, .channelUp, .channelDown, .guide,
            .pageUp, .pageDown,
        ]
        XCTAssertEqual(expected.count, 19)

        // Verify each raw value is unique
        let rawValues = Set(expected.map(\.rawValue))
        XCTAssertEqual(rawValues.count, expected.count, "Duplicate raw values found")
    }
}
