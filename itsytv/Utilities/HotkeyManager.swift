import AppKit
import Carbon.HIToolbox

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

    func unregisterAll() {
        for entry in hotkeys.values {
            if let ref = entry.ref {
                UnregisterEventHotKey(ref)
            }
        }
        hotkeys.removeAll()
        nextId = 1
    }

    func reregisterAll() {
        unregisterAll()

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
