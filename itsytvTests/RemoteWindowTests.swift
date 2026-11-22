import XCTest

final class RemoteWindowTests: XCTestCase {
    // MARK: - Picking an Apple TV (menu, Shortcuts)

    func testWithTheRemoteClosedPickingConnects() {
        XCTAssertEqual(RemoteWindow().pick("living-room", connectionOpen: false), .connect)
    }

    func testPickingTheAppleTVTheRemoteShowsBringsItForward() {
        var window = RemoteWindow()
        window.opened(for: "living-room")
        XCTAssertEqual(window.pick("living-room", connectionOpen: true), .bringForward)
    }

    func testPickingAnotherAppleTVConnectsToIt() {
        var window = RemoteWindow()
        window.opened(for: "living-room")
        XCTAssertEqual(window.pick("bedroom", connectionOpen: true), .connect)
    }

    func testSwitchingBackToTheFirstAppleTVConnectsToIt() {
        // 1.9.0: after one switch, picking the first Apple TV again only brought the remote forward.
        var window = RemoteWindow()
        window.opened(for: "living-room")
        window.connecting(to: "bedroom")
        XCTAssertEqual(window.deviceID, "bedroom")
        XCTAssertEqual(window.pick("living-room", connectionOpen: true), .connect)

        window.connecting(to: "living-room")
        XCTAssertEqual(window.pick("bedroom", connectionOpen: true), .connect)
        XCTAssertEqual(window.pick("living-room", connectionOpen: true), .bringForward)
    }

    func testConnectingWithTheRemoteClosedLeavesItClosed() {
        var window = RemoteWindow()
        window.connecting(to: "living-room")
        XCTAssertNil(window.deviceID)
        XCTAssertFalse(window.isOpen)
    }

    func testARemoteWhoseConnectionEndedReconnects() {
        var window = RemoteWindow()
        window.opened(for: "living-room")
        XCTAssertEqual(window.pick("living-room", connectionOpen: false), .connect)
    }

    func testClosingTheRemoteForgetsItsAppleTV() {
        var window = RemoteWindow()
        window.opened(for: "living-room")
        window.closed()
        XCTAssertNil(window.deviceID)
        XCTAssertEqual(window.pick("living-room", connectionOpen: true), .connect)
    }

    // MARK: - An Apple TV's hotkey

    func testHotkeyClosesItsRemoteOnTheCurrentDesktop() {
        var window = RemoteWindow()
        window.opened(for: "living-room")
        XCTAssertEqual(window.hotkey("living-room", remoteOnCurrentDesktop: true), .close)
    }

    func testHotkeyOpensItsRemoteFromAnotherDesktop() {
        var window = RemoteWindow()
        window.opened(for: "living-room")
        XCTAssertEqual(window.hotkey("living-room", remoteOnCurrentDesktop: false), .open)
    }

    func testHotkeyOfAnotherAppleTVOpensIt() {
        var window = RemoteWindow()
        window.opened(for: "living-room")
        XCTAssertEqual(window.hotkey("bedroom", remoteOnCurrentDesktop: true), .open)
    }

    func testHotkeyOfTheFirstAppleTVAfterASwitchOpensIt() {
        // 1.9.0: it closed the remote instead.
        var window = RemoteWindow()
        window.opened(for: "living-room")
        window.connecting(to: "bedroom")
        XCTAssertEqual(window.hotkey("living-room", remoteOnCurrentDesktop: true), .open)
        XCTAssertEqual(window.hotkey("bedroom", remoteOnCurrentDesktop: true), .close)
    }

    func testHotkeyWithTheRemoteClosedOpensIt() {
        XCTAssertEqual(RemoteWindow().hotkey("living-room", remoteOnCurrentDesktop: false), .open)
    }
}
