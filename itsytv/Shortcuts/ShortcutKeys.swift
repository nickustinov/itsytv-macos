import AppKit
import Carbon.HIToolbox

/// A key with its modifiers – the global hotkey and the remote's shortcuts.
struct ShortcutKeys: Codable, Equatable {
    var modifiers: UInt
    var keyCode: UInt16

    /// ⌃ ⌥ ⇧ ⌘ only – ignores caps lock, fn and the numeric-pad flag arrows carry.
    static let relevantModifiers: NSEvent.ModifierFlags = [.control, .option, .shift, .command]

    init(modifiers: UInt, keyCode: UInt16) {
        self.modifiers = modifiers
        self.keyCode = keyCode
    }

    init(event: NSEvent) {
        self.init(
            modifiers: event.modifierFlags.intersection(Self.relevantModifiers).rawValue,
            keyCode: event.keyCode
        )
    }

    var modifierFlags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var displayString: String { Self.caps(self).joined() }

    /// Key caps as drawn on screen, one string per cap.
    static func caps(_ keys: ShortcutKeys) -> [String] {
        let flags = keys.modifierFlags
        var caps: [String] = []
        if flags.contains(.control) { caps.append("⌃") }
        if flags.contains(.option) { caps.append("⌥") }
        if flags.contains(.shift) { caps.append("⇧") }
        if flags.contains(.command) { caps.append("⌘") }
        caps.append(keyName(keys.keyCode))
        return caps
    }

    private static let namedKeys: [Int: String] = [
        kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_LeftArrow: "←", kVK_RightArrow: "→",
        kVK_Return: "↩", kVK_ANSI_KeypadEnter: "⌤", kVK_Escape: "esc", kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦", kVK_Space: "space", kVK_Tab: "⇥", kVK_ANSI_Minus: "−",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    /// Key name on a Latin layout, so ⌘K stays ⌘K while a Cyrillic layout is active.
    static func keyName(_ keyCode: UInt16) -> String {
        if let name = namedKeys[Int(keyCode)] { return name }
        let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource().takeRetainedValue()
        guard let layoutPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return "#\(keyCode)"
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPtr).takeUnretainedValue() as Data
        let name: String? = layoutData.withUnsafeBytes { bytes in
            guard let layout = bytes.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var deadKeyState: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                layout, keyCode, UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                UInt32(kUCKeyTranslateNoDeadKeysMask), &deadKeyState, chars.count, &length, &chars
            )
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: chars, count: length)
        }
        return name.map { $0.uppercased() } ?? "#\(keyCode)"
    }
}
