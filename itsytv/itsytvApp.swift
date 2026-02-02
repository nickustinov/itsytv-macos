import SwiftUI

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
    let manager = AppleTVManager()
    let iconLoader = AppIconLoader()
    var appController: AppController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        appController = AppController(manager: manager, iconLoader: iconLoader)
    }
}
