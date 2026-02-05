import AppKit
import Carbon.HIToolbox

struct ShortcutKeys: Codable, Equatable {
    var modifiers: UInt
    var keyCode: UInt16

    var displayString: String {
        var result = ""
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        if flags.contains(.control) { result += "⌃" }
        if flags.contains(.option) { result += "⌥" }
        if flags.contains(.shift) { result += "⇧" }
        if flags.contains(.command) { result += "⌘" }
        result += keyCodeToString(keyCode)
        return result
    }

    private func keyCodeToString(_ keyCode: UInt16) -> String {
        switch Int(keyCode) {
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Space: return "Space"
        case kVK_Delete: return "⌫"
        case kVK_Escape: return "⎋"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_Home: return "↖"
        case kVK_End: return "↘"
        case kVK_PageUp: return "⇞"
        case kVK_PageDown: return "⇟"
        default:
            if let char = keyCodeToCharacter(keyCode) {
                return char.uppercased()
            }
            return "?"
        }
    }

    private func keyCodeToCharacter(_ keyCode: UInt16) -> String? {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let layoutDataPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutDataPtr).takeUnretainedValue() as Data
        return layoutData.withUnsafeBytes { bytes -> String? in
            guard let ptr = bytes.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var deadKeyState: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                ptr,
                keyCode,
                UInt16(kUCKeyActionDown),
                0,
                UInt32(LMGetKbdType()),
                UInt32(kUCKeyTranslateNoDeadKeysMask),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: chars, count: length)
        }
    }
}

final class HotkeyManager {
    static let shared = HotkeyManager()

    private var hotkeys: [UInt32: (id: EventHotKeyID, ref: EventHotKeyRef?, deviceID: String)] = [:]
    private var nextId: UInt32 = 1
    var onHotkeyPressed: ((String) -> Void)?

    private init() {
        installCarbonHandler()
    }

    private func installCarbonHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, _) -> OSStatus in
                var hotkeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotkeyID
                )
                HotkeyManager.shared.handleHotkey(id: hotkeyID.id)
                return noErr
            },
            1,
            &eventType,
            nil,
            nil
        )
    }

    private func handleHotkey(id: UInt32) {
        guard let entry = hotkeys[id] else { return }
        DispatchQueue.main.async {
            self.onHotkeyPressed?(entry.deviceID)
        }
    }

    func register(deviceID: String, keys: ShortcutKeys) {
        unregister(deviceID: deviceID)

        let id = nextId
        nextId += 1

        let hotkeyID = EventHotKeyID(signature: OSType(0x4954_5359), id: id) // "ITSY"
        var hotkeyRef: EventHotKeyRef?

        let modifiers = carbonModifiers(from: NSEvent.ModifierFlags(rawValue: keys.modifiers))

        let status = RegisterEventHotKey(
            UInt32(keys.keyCode),
            modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        if status == noErr {
            hotkeys[id] = (hotkeyID, hotkeyRef, deviceID)
        }
    }

    func unregister(deviceID: String) {
        for (id, entry) in hotkeys where entry.deviceID == deviceID {
            if let ref = entry.ref {
                UnregisterEventHotKey(ref)
            }
            hotkeys.removeValue(forKey: id)
        }
    }

    func reregisterAll() {
        // Unregister all existing
        for entry in hotkeys.values {
            if let ref = entry.ref {
                UnregisterEventHotKey(ref)
            }
        }
        hotkeys.removeAll()
        nextId = 1

        // Re-register from storage
        for (deviceID, keys) in HotkeyStorage.loadAll() {
            register(deviceID: deviceID, keys: keys)
        }
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        return modifiers
    }
}

enum HotkeyStorage {
    private static let storageKey = "deviceHotkeys"

    static func save(deviceID: String, keys: ShortcutKeys?) {
        var all = loadAll()
        if let keys {
            all[deviceID] = keys
        } else {
            all.removeValue(forKey: deviceID)
        }
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        HotkeyManager.shared.reregisterAll()
    }

    static func load(deviceID: String) -> ShortcutKeys? {
        loadAll()[deviceID]
    }

    static func loadAll() -> [String: ShortcutKeys] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let all = try? JSONDecoder().decode([String: ShortcutKeys].self, from: data) else {
            return [:]
        }
        return all
    }
}
