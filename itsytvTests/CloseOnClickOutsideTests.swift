import XCTest

final class CloseOnClickOutsideTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "itsytv.tests.close-on-click-outside"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func option() -> CloseOnClickOutside { CloseOnClickOutside(defaults: defaults) }

    func testItIsOffByDefault() {
        XCTAssertFalse(option().isOn)
        XCTAssertFalse(option().closes(remoteOnCurrentDesktop: true))
    }

    func testWhenOnAClickOutsideClosesTheRemoteOnThisDesktop() {
        defaults.set(true, forKey: CloseOnClickOutside.key)
        XCTAssertTrue(option().closes(remoteOnCurrentDesktop: true))
    }

    func testWhenOnTheRemoteLeftOnAnotherDesktopStaysOpen() {
        defaults.set(true, forKey: CloseOnClickOutside.key)
        XCTAssertFalse(option().closes(remoteOnCurrentDesktop: false))
    }

    func testTurningItOffTakesEffectStraightAway() {
        let option = option()
        defaults.set(true, forKey: CloseOnClickOutside.key)
        XCTAssertTrue(option.closes(remoteOnCurrentDesktop: true))
        defaults.set(false, forKey: CloseOnClickOutside.key)
        XCTAssertFalse(option.closes(remoteOnCurrentDesktop: true))
    }
}
