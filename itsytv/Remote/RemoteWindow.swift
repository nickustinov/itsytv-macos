/// The Apple TV the remote window shows, and what picking an Apple TV – in the menu, from Shortcuts
/// or with its hotkey – does with the window.
///
/// Picking another Apple TV while the remote is open keeps the window and connects it to the new
/// one, so the window's Apple TV follows every connection, not only the one that opened it. In 1.9.0
/// it stayed on the first Apple TV: after one switch, picking that Apple TV again only brought the
/// remote forward, and its hotkey closed the remote.
struct RemoteWindow {
    /// The Apple TV the open remote shows; nil while the remote is closed.
    private(set) var deviceID: String?

    var isOpen: Bool { deviceID != nil }

    enum Pick {
        /// The remote already shows this Apple TV: bring it to the current desktop.
        case bringForward
        /// Connect to this Apple TV – in the open remote, or in a new one.
        case connect
    }

    enum Hotkey {
        case close
        /// Open the Apple TV's remote, as picking it would.
        case open
    }

    mutating func opened(for deviceID: String) {
        self.deviceID = deviceID
    }

    /// Itsytv connects to `deviceID`. An open remote now shows it; a closed one stays closed.
    mutating func connecting(to deviceID: String) {
        if isOpen { self.deviceID = deviceID }
    }

    mutating func closed() {
        deviceID = nil
    }

    /// - Parameter connectionOpen: The connection hasn't ended – it's connecting, pairing or connected.
    func pick(_ deviceID: String, connectionOpen: Bool) -> Pick {
        self.deviceID == deviceID && connectionOpen ? .bringForward : .connect
    }

    /// The hotkey closes the remote only when it shows that Apple TV on the current desktop.
    func hotkey(_ deviceID: String, remoteOnCurrentDesktop: Bool) -> Hotkey {
        self.deviceID == deviceID && remoteOnCurrentDesktop ? .close : .open
    }
}
