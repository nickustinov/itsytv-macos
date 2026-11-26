import Foundation

/// "Close when clicking outside" in the remote's ⋯ menu (#68), off by default: a click in another
/// app – the desktop, another app's window or menu bar item – closes the remote, as ⌘W does.
/// Clicks on the remote, its menus, Itsytv's menu bar icon and Itsytv's other windows go to Itsytv
/// itself, so they never count as outside.
struct CloseOnClickOutside {
    static let key = "closeOnClickOutside"

    let defaults: UserDefaults

    var isOn: Bool { defaults.bool(forKey: Self.key) }

    /// A remote left open on another desktop stays open: the click wasn't next to it.
    func closes(remoteOnCurrentDesktop: Bool) -> Bool {
        isOn && remoteOnCurrentDesktop
    }
}
