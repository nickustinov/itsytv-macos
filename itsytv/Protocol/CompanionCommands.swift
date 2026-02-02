import Foundation
import os.log

private let log = Logger(subsystem: "com.itsytv.app", category: "Commands")

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

    /// Start a companion session. Must be called after pair-verify before other commands.
    func startSession(completion: @escaping (Int64?) -> Void) {
        let localSID = Int64.random(in: 0...Int64(UInt32.max))
        log.info("Starting session with local SID=\(localSID)")
        sendRequest(
            eventName: "_sessionStart",
            content: .dictionary([
                ("_srvT", .string("com.apple.tvremoteservices")),
                ("_sid", .int(localSID)),
            ]),
            responseHandler: { response in
                if let content = response["_c"],
                   let remoteSID = content["_sid"]?.intValue {
                    let fullSID = (remoteSID << 32) | localSID
                    log.info("Session started: remoteSID=\(remoteSID) fullSID=0x\(String(fullSID, radix: 16))")
                    completion(fullSID)
                } else {
                    log.warning("Session start response missing _sid")
                    completion(nil)
                }
            }
        )
    }

    /// Fetch the list of launchable applications.
    func fetchApps(completion: @escaping ([(bundleID: String, name: String)]) -> Void) {
        log.info("Sending FetchLaunchableApplicationsEvent request")
        sendRequest(eventName: "FetchLaunchableApplicationsEvent", content: .dict([]), responseHandler: { response in
            log.info("Got FetchLaunchableApplicationsEvent response")
            var apps: [(bundleID: String, name: String)] = []
            if let content = response["_c"]?.dictValue {
                log.info("Response _c dict has \(content.count) entries")
                for pair in content {
                    guard let bundleID = pair.key.stringValue,
                          let name = pair.value.stringValue else {
                        log.warning("Skipping non-string pair: key=\(String(describing: pair.key)) value=\(String(describing: pair.value))")
                        continue
                    }
                    apps.append((bundleID: bundleID, name: name))
                }
            } else {
                log.warning("Response has no _c dict — keys: \(response.dictValue?.map { String(describing: $0.key) } ?? [])")
            }
            log.info("Parsed \(apps.count) apps")
            completion(apps)
        })
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
