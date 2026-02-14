import SwiftUI
import AppIntents

@main
struct itsytvApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environment(appDelegate.manager)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) weak var shared: AppDelegate?

    let manager = AppleTVManager()
    let iconLoader = AppIconLoader()
    var appController: AppController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        appController = AppController(manager: manager, iconLoader: iconLoader)
        ItsyTVShortcuts.updateAppShortcutParameters()
    }

    func applicationWillTerminate(_ notification: Notification) {
        appController?.cleanup()
    }
}
