import AppKit

/// System Settings panes Itsytv sends people to. Not API: `x-apple.systempreferences:` plus the
/// pane's extension identifier, checked on macOS 27.
enum SystemSettingsPane {
    /// Menu Bar ("Allow in the Menu Bar").
    case menuBar
    /// Privacy & Security. Its Local Network list has no link of its own (no `Privacy_LocalNetwork` anchor).
    case privacySecurity

    func open() {
        let id = switch self {
        case .menuBar: "com.apple.ControlCenter-Settings.extension"
        case .privacySecurity: "com.apple.settings.PrivacySecurity.extension"
        }
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:\(id)")!)
    }
}
