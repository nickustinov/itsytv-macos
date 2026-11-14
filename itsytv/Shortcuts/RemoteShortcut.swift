import AppKit
import Carbon.HIToolbox
import Observation

/// Every keyboard shortcut of the remote panel. The panel's key handler, the
/// on-remote hints and the Keyboard shortcuts window all read this one table;
/// the keys themselves can be changed in the Keyboard shortcuts window.
enum RemoteShortcut: String, CaseIterable, Identifiable {
    case up, down, left, right, select, back, home
    case playPause, volumeUp, volumeDown, mute
    case keyboard, appSearch, close

    var id: String { rawValue }

    var defaultKeys: ShortcutKeys {
        let command = NSEvent.ModifierFlags.command.rawValue
        let shift = NSEvent.ModifierFlags.shift.rawValue
        return switch self {
        case .up: ShortcutKeys(modifiers: 0, keyCode: UInt16(kVK_UpArrow))
        case .down: ShortcutKeys(modifiers: 0, keyCode: UInt16(kVK_DownArrow))
        case .left: ShortcutKeys(modifiers: 0, keyCode: UInt16(kVK_LeftArrow))
        case .right: ShortcutKeys(modifiers: 0, keyCode: UInt16(kVK_RightArrow))
        case .select: ShortcutKeys(modifiers: 0, keyCode: UInt16(kVK_Return))
        case .back: ShortcutKeys(modifiers: 0, keyCode: UInt16(kVK_Escape))
        case .home: ShortcutKeys(modifiers: 0, keyCode: UInt16(kVK_Delete))
        case .playPause: ShortcutKeys(modifiers: 0, keyCode: UInt16(kVK_Space))
        case .volumeUp: ShortcutKeys(modifiers: 0, keyCode: UInt16(kVK_ANSI_Equal))
        case .volumeDown: ShortcutKeys(modifiers: 0, keyCode: UInt16(kVK_ANSI_Minus))
        case .mute: ShortcutKeys(modifiers: command | shift, keyCode: UInt16(kVK_ANSI_M))
        case .keyboard: ShortcutKeys(modifiers: command, keyCode: UInt16(kVK_ANSI_K))
        case .appSearch: ShortcutKeys(modifiers: command, keyCode: UInt16(kVK_ANSI_F))
        case .close: ShortcutKeys(modifiers: command, keyCode: UInt16(kVK_ANSI_W))
        }
    }

    /// Current keys (custom or default); nil when the user cleared the shortcut.
    var keys: ShortcutKeys? { ShortcutSettings.shared.keys(for: self) }

    /// Key caps as drawn on screen, one string per cap.
    var keyCaps: [String] { keys.map(ShortcutKeys.caps) ?? ["–"] }

    var label: String { keyCaps.joined() }

    var title: String {
        switch self {
        case .up: "Up"
        case .down: "Down"
        case .left: "Left"
        case .right: "Right"
        case .select: "Select"
        case .back: "Back"
        case .home: "TV / Home"
        case .playPause: "Play / Pause"
        case .volumeUp: "Volume up"
        case .volumeDown: "Volume down"
        case .mute: "Mute"
        case .keyboard: "Type on Apple TV"
        case .appSearch: "Search apps"
        case .close: "Close remote"
        }
    }

    /// ⌘ shortcuts also work while a text field has focus.
    var usesCommand: Bool { keys?.modifierFlags.contains(.command) ?? false }

    /// Held down, these do something different from a click (Back → Home screen,
    /// TV → Control Center, Select → context menu), so key repeat is not forwarded.
    var hasHoldAction: Bool {
        switch self {
        case .back, .home, .select, .playPause: true
        default: false
        }
    }

    static let groups: [(title: String, items: [RemoteShortcut])] = [
        ("Navigation", [.up, .down, .left, .right, .select, .back, .home]),
        ("Playback", [.playPause, .volumeUp, .volumeDown, .mute]),
        ("Remote", [.keyboard, .appSearch, .close]),
    ]

    static func match(_ event: NSEvent) -> RemoteShortcut? {
        match(ShortcutKeys(event: event))
    }

    static func match(_ pressed: ShortcutKeys, settings: ShortcutSettings = .shared) -> RemoteShortcut? {
        if let shortcut = allCases.first(where: { settings.keys(for: $0) == pressed }) {
            return shortcut
        }
        // ⌘H has always closed the remote too; keep it while ⌘W is the default.
        if pressed == ShortcutKeys(modifiers: NSEvent.ModifierFlags.command.rawValue, keyCode: UInt16(kVK_ANSI_H)),
           settings.keys(for: .close) == close.defaultKeys {
            return .close
        }
        return nil
    }
}

/// What a key press does while a row of the Keyboard shortcuts window waits for new keys.
enum ShortcutRecording: Equatable {
    /// esc stops recording, as in System Settings.
    case cancel
    /// ⌘Q still quits the app.
    case passThrough
    case record(ShortcutKeys)

    init(_ keys: ShortcutKeys) {
        switch keys {
        case ShortcutKeys(modifiers: 0, keyCode: UInt16(kVK_Escape)):
            self = .cancel
        case ShortcutKeys(modifiers: NSEvent.ModifierFlags.command.rawValue, keyCode: UInt16(kVK_ANSI_Q)):
            self = .passThrough
        default:
            self = .record(keys)
        }
    }
}

// MARK: - Custom keys

/// User-chosen keys for the remote shortcuts, stored in UserDefaults.
@Observable
final class ShortcutSettings {
    static let shared = ShortcutSettings(defaults: .standard)

    private static let storageKey = "customRemoteShortcuts"
    /// Stored for a shortcut the user cleared (assigned its keys elsewhere).
    private static let unassigned = ShortcutKeys(modifiers: 0, keyCode: .max)

    @ObservationIgnored private let defaults: UserDefaults

    /// Overrides keyed by `RemoteShortcut.rawValue`; defaults are not stored.
    private var custom: [String: ShortcutKeys]

    /// The shortcut whose new keys are being recorded in the shortcuts window.
    var recording: RemoteShortcut?

    init(defaults: UserDefaults) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let stored = try? JSONDecoder().decode([String: ShortcutKeys].self, from: data) {
            custom = stored
        } else {
            custom = [:]
        }
    }

    func keys(for shortcut: RemoteShortcut) -> ShortcutKeys? {
        let keys = custom[shortcut.rawValue] ?? shortcut.defaultKeys
        return keys == Self.unassigned ? nil : keys
    }

    func isCustomized(_ shortcut: RemoteShortcut) -> Bool {
        custom[shortcut.rawValue] != nil
    }

    var hasCustomizations: Bool { !custom.isEmpty }

    /// Gives `keys` to `shortcut`. A shortcut that already had those keys takes
    /// over the old keys of `shortcut`, so nothing ends up with two meanings.
    func set(_ keys: ShortcutKeys, for shortcut: RemoteShortcut) {
        let previous = self.keys(for: shortcut) ?? Self.unassigned
        if let other = RemoteShortcut.allCases.first(where: { $0 != shortcut && self.keys(for: $0) == keys }) {
            assign(previous, to: other)
        }
        assign(keys, to: shortcut)
        save()
    }

    func reset(_ shortcut: RemoteShortcut) {
        set(shortcut.defaultKeys, for: shortcut)
    }

    func resetAll() {
        custom = [:]
        save()
    }

    private func assign(_ keys: ShortcutKeys, to shortcut: RemoteShortcut) {
        custom[shortcut.rawValue] = keys == shortcut.defaultKeys ? nil : keys
    }

    private func save() {
        if custom.isEmpty {
            defaults.removeObject(forKey: Self.storageKey)
        } else if let data = try? JSONEncoder().encode(custom) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}
