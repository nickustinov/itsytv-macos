import SwiftUI

@main
struct itsytvApp: App {
    @State private var manager = AppleTVManager()

    var body: some Scene {
        MenuBarExtra("itsytv", systemImage: "appletv") {
            MenuBarView()
                .environment(manager)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(manager)
        }
    }
}
