import Foundation

/// HID button values for the Companion protocol `_hidC` command.
enum CompanionButton: Int64 {
    case up = 1
    case down = 2
    case left = 3
    case right = 4
    case menu = 5
    case select = 6
    case home = 7
    case volumeUp = 8
    case volumeDown = 9
    case siri = 10
    case screensaver = 11
    case sleep = 12
    case wake = 13
    case playPause = 14
    case channelUp = 15
    case channelDown = 16
    case guide = 17
    case pageUp = 18
    case pageDown = 19
}

/// High-level command helpers for the Companion protocol.
extension CompanionConnection {

    /// Send a button press (down + up) with configurable hold duration.
    func pressButton(_ button: CompanionButton, holdDuration: TimeInterval = 0.05, completion: ((Swift.Error?) -> Void)? = nil) {
        // Button down (sent as request, matching pyatv)
        sendRequest(eventName: "_hidC", content: .dictionary([
            ("_hBtS", .int(1)), // button state: down
            ("_hidC", .int(button.rawValue)),
        ]))
        // Button up after hold duration
        DispatchQueue.global().asyncAfter(deadline: .now() + holdDuration) { [weak self] in
            self?.sendRequest(eventName: "_hidC", content: .dictionary([
                ("_hBtS", .int(2)), // button state: up
                ("_hidC", .int(button.rawValue)),
            ]), completion: completion)
        }
    }

    /// Fetch the list of launchable applications.
    func fetchApps(completion: @escaping ([(bundleID: String, name: String)]) -> Void) {
        let xid = sendRequest(eventName: "FetchLaunchableApplicationsEvent")
        // The response will come asynchronously via onFrame
        // Caller needs to match on _x == xid
        _ = xid
    }

    /// Launch an app by bundle ID.
    func launchApp(bundleID: String, completion: ((Swift.Error?) -> Void)? = nil) {
        sendRequest(
            eventName: "_launchApp",
            content: .dictionary([
                ("_bundleID", .string(bundleID)),
            ]),
            completion: completion
        )
    }

    /// Send text input (keyboard).
    func sendText(_ text: String, completion: ((Swift.Error?) -> Void)? = nil) {
        sendEvent(name: "_kbS", content: .dictionary([
            ("_kbS", .string(text)),
        ]), completion: completion)
    }

    /// Fetch attention state (awake/asleep).
    func fetchAttentionState(completion: ((Swift.Error?) -> Void)? = nil) {
        sendRequest(eventName: "FetchAttentionState", completion: completion)
    }

    /// Put Apple TV to sleep.
    func sleep(completion: ((Swift.Error?) -> Void)? = nil) {
        pressButton(.sleep, completion: completion)
    }

    /// Wake Apple TV.
    func wake(completion: ((Swift.Error?) -> Void)? = nil) {
        pressButton(.wake, completion: completion)
    }
}
