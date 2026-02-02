import SwiftUI

@main
struct itsytvApp: App {
    @State private var manager = AppleTVManager()
    @State private var iconLoader = AppIconLoader()

    var body: some Scene {
        MenuBarExtra("itsytv", systemImage: "appletv") {
            MenuBarView()
                .environment(manager)
                .environment(iconLoader)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(manager)
        }
    }
}
