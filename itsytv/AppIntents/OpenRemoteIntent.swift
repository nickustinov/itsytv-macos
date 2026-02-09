import AppIntents
import os.log

private let log = Logger(subsystem: "com.itsytv.app", category: "Intent")

struct OpenRemoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Open itsytv remote"
    static var description: IntentDescription = "Opens the itsytv remote control panel for an Apple TV"
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        log.error("Intent perform() called")
        log.error("AppDelegate.shared = \(AppDelegate.shared == nil ? "nil" : "set")")

        for i in 0..<20 {
            let delegate = AppDelegate.shared
            let controller = delegate?.appController
            log.error("Attempt \(i): delegate=\(delegate == nil ? "nil" : "set") controller=\(controller == nil ? "nil" : "set")")

            if let controller {
                let pairedIDs = KeychainStorage.allPairedDeviceIDs()
                let deviceCount = delegate?.manager.discoveredDevices.count ?? 0
                log.error("Calling openRemote — pairedIDs=\(pairedIDs) discoveredDevices=\(deviceCount)")
                controller.openRemote()
                return .result()
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        }

        log.error("Intent timed out waiting for app")
        throw IntentError.appNotReady
    }

    enum IntentError: Error, CustomLocalizedStringResourceConvertible {
        case appNotReady

        var localizedStringResource: LocalizedStringResource {
            switch self {
            case .appNotReady:
                "itsytv failed to start — please try again"
            }
        }
    }
}

struct ItsyTVShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenRemoteIntent(),
            phrases: ["Open \(.applicationName) remote"],
            shortTitle: "Open remote",
            systemImageName: "appletv.fill"
        )
    }
}
