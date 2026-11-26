import AppKit
import SwiftUI

/// Whether the welcome is in its hidden-icon form – updated while the window is open, so turning the
/// icon back on in Menu Bar settings switches it to the normal welcome.
@Observable
final class WelcomeModel {
    var iconHidden: Bool

    init(iconHidden: Bool) {
        self.iconHidden = iconHidden
    }
}

/// The welcome (`WelcomeGate` decides when). Itsytv has no window and – unless chosen – no Dock icon,
/// so a new user whose menu bar icon is hidden sees nothing. While the icon is hidden, every choice
/// leaves a lasting way in: there's no "Got it" and no close button.
struct WelcomeView: View {
    let model: WelcomeModel
    let onShowMe: () -> Void
    let onDismiss: () -> Void
    let onMenuBarSettings: () -> Void
    let onShowInDock: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
            Text("Itsytv lives in your menu bar")
                .font(.title2.weight(.semibold))
            if model.iconHidden {
                Text("Its icon is hidden right now – your menu bar is full, or Itsytv is turned off in System Settings → Menu Bar.")
                    .multilineTextAlignment(.center)
                Text("Turn it on there (or turn off icons you don’t need), or keep Itsytv in the Dock – click it any time to open the remote.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                HStack(spacing: 10) {
                    Button("Menu Bar Settings", action: onMenuBarSettings)
                    Button("Show in Dock", action: onShowInDock)
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 4)
            } else {
                Text("Click the remote icon at the top of your screen to pick your Apple TV and pair it.")
                    .multilineTextAlignment(.center)
                Text("Can’t see the icon? Your menu bar may be full, or Itsytv is turned off in System Settings → Menu Bar. Open Itsytv again from Spotlight or Finder and it opens at the top of your screen.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                HStack(spacing: 10) {
                    Button("Got it", action: onDismiss)
                        .keyboardShortcut(.cancelAction)
                    Button("Show me", action: onShowMe)
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 4)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(28)
        .frame(width: 400)
    }
}

enum WelcomeWindow {
    private static var window: NSWindow?
    private static var occlusionObserver: NSObjectProtocol?

    static func show(iconHidden: @escaping () -> Bool, showDevices: @escaping () -> Void) {
        guard window == nil else { return }
        let model = WelcomeModel(iconHidden: iconHidden())
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        let hostingView = NSHostingView(rootView: WelcomeView(
            model: model,
            onShowMe: { close(); showDevices() },
            onDismiss: { close() },
            onMenuBarSettings: {
                // Behind System Settings from here on, so it doesn't cover the switch.
                window.level = .normal
                SystemSettingsPane.menuBar.open()
            },
            onShowInDock: { DockIcon.set(true); close(); showDevices() }
        ))
        // The title bar is invisible; without this SwiftUI pads the content below it as well.
        hostingView.safeAreaRegions = []
        window.contentView = hostingView
        fit(window, hostingView: hostingView, iconHidden: model.iconHidden)
        window.center()

        // The icon can come back while the welcome is open – turned on in Menu Bar settings, or room
        // made in the menu bar – which changes its window's occlusion.
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main
        ) { _ in
            let hidden = iconHidden()
            guard hidden != model.iconHidden else { return }
            model.iconHidden = hidden
            fit(window, hostingView: hostingView, iconHidden: hidden)
        }

        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Closable only while the icon can be seen, sized to whichever welcome is showing.
    private static func fit(_ window: NSWindow, hostingView: NSView, iconHidden: Bool) {
        if iconHidden {
            window.styleMask.remove(.closable)
        } else {
            window.styleMask.insert(.closable)
        }
        window.setContentSize(hostingView.fittingSize)
    }

    private static func close() {
        if let occlusionObserver {
            NotificationCenter.default.removeObserver(occlusionObserver)
        }
        occlusionObserver = nil
        window?.close()
        window = nil
    }
}
