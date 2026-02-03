import Foundation
import os.log

private let log = Logger(subsystem: "com.itsytv.app", category: "Manager")

/// Orchestrates the full lifecycle of connecting to an Apple TV:
/// discovery -> pair-setup (if needed) -> pair-verify -> encrypted commands.
@Observable
final class AppleTVManager {
    var connectionStatus: ConnectionStatus = .disconnected
    var discoveredDevices: [AppleTVDevice] = []
    var connectedDeviceName: String?
    var isScanning = false
    var installedApps: [(bundleID: String, name: String)] = []
    var mrpManager = MRPManager()

    private(set) var connection: CompanionConnection?
    private var pairSetup: PairSetup?
    private var partialCredentials: HAPCredentials?
    private var currentCredentials: HAPCredentials?
    private var connectedDevice: AppleTVDevice?

    /// Text input session state — kept alive while connected.
    private var textInputSessionUUID: Data?
    private var sentText = ""

    let discovery = DeviceDiscovery()

    // MARK: - Discovery

    func startScanning() {
        isScanning = true
        discovery.start { [weak self] devices in
            self?.discoveredDevices = devices
        }
    }

    func stopScanning() {
        isScanning = false
        discovery.stop()
    }

    // MARK: - Connection

    func connect(to device: AppleTVDevice) {
        connectionStatus = .connecting
        self.connectedDevice = device

        let conn = CompanionConnection()
        self.connection = conn

        conn.onDisconnect = { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                // Once connected, MRP runs over the AirPlay tunnel — the companion
                // link TCP connection closing is expected and should be ignored.
                if self.connectionStatus == .connected {
                    log.info("Companion link closed while MRP tunnel active — reconnecting")
                    self.connection?.stopKeepAlive()
                    self.connection?.stopTextInput()
                    self.connection = nil
                    self.textInputSessionUUID = nil
                    self.sentText = ""
                    self.reconnectCompanion()
                    return
                }
                if let error {
                    self.connectionStatus = .error(error.localizedDescription)
                } else {
                    self.connectionStatus = .disconnected
                }
                self.connectedDeviceName = nil
                self.connectedDevice = nil
            }
        }

        conn.onFrame = { [weak self] frame in
            self?.handleFrame(frame)
        }

        // Check for stored credentials
        if let credentials = KeychainStorage.load(for: device.id) {
            // Already paired — do pair-verify
            self.currentCredentials = credentials
            connectedDeviceName = device.name
            conn.connectToService(name: device.name)

            // Wait for connection to be ready, then start verify
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.startPairVerify(credentials: credentials)
            }
        } else {
            // Need to pair first
            connectedDeviceName = device.name
            DispatchQueue.main.async {
                self.connectionStatus = .pairing
            }
            conn.connectToService(name: device.name)

            // Start pair-setup after connection is ready
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, let conn = self.connection else { return }
                let setup = PairSetup(connection: conn)
                self.pairSetup = setup
                let m1Frame = setup.startPairing()
                conn.send(frame: m1Frame)
            }
        }
    }

    func disconnect() {
        connection?.stopTextInput()
        mrpManager.disconnect()
        connection?.disconnect()
        connection = nil
        connectionStatus = .disconnected
        connectedDeviceName = nil
        connectedDevice = nil
        currentCredentials = nil
        textInputSessionUUID = nil
        sentText = ""
        installedApps = []
    }

    // MARK: - Pairing

    func submitPIN(_ pin: String) {
        guard let pairSetup, let connection else { return }

        // We should have received M2 by now (stored in pendingM2)
        guard let m2 = pendingM2 else {
            connectionStatus = .error("No challenge received from Apple TV")
            return
        }

        do {
            let m3Frame = try pairSetup.processChallengeAndProve(m2Frame: m2, pin: pin)
            connection.send(frame: m3Frame)
        } catch {
            DispatchQueue.main.async {
                self.connectionStatus = .error(error.localizedDescription)
            }
        }
    }

    // MARK: - Commands

    func pressButton(_ button: CompanionButton) {
        let hold: TimeInterval = button == .siri ? 1.0 : 0.05
        connection?.pressButton(button, holdDuration: hold)
    }

    func launchApp(bundleID: String) {
        connection?.launchApp(bundleID: bundleID)
    }

    /// Update the Apple TV text field to match `newText`.
    ///
    /// Sends only the diff: appends new characters when typing forward,
    /// or clears and re-types when characters are deleted (backspace).
    func updateRemoteText(_ newText: String) {
        guard let connection else { return }

        let ensureSession: (@escaping (Data) -> Void) -> Void = { [weak self] handler in
            if let uuid = self?.textInputSessionUUID {
                handler(uuid)
                return
            }
            connection.stopTextInput { _ in
                connection.startTextInput { response in
                    guard let content = response["_c"],
                          let tiData = content["_tiD"]?.dataValue,
                          let result = try? TextInputSession.decodeStartResponse(tiData) else {
                        log.debug("No active text field")
                        return
                    }
                    self?.textInputSessionUUID = result.sessionUUID
                    handler(result.sessionUUID)
                }
            }
        }

        ensureSession { [weak self] uuid in
            guard let self else { return }
            if newText.hasPrefix(self.sentText) {
                // Typed forward — send only the new characters
                let added = String(newText.dropFirst(self.sentText.count))
                if !added.isEmpty {
                    connection.sendTextInputEvent(added, sessionUUID: uuid)
                }
            } else {
                // Backspace or edit — atomic clear + replace in one event
                connection.replaceTextInputEvent(newText, sessionUUID: uuid)
            }
            self.sentText = newText
        }
    }

    /// Reset local text tracking (call when closing keyboard).
    func resetTextInputState() {
        sentText = ""
    }

    // MARK: - Frame handling

    private var pendingM2: CompanionFrame?
    private var pendingPairVerify: PairVerify?

    private func handleFrame(_ frame: CompanionFrame) {
        log.debug("Frame received: type=\(String(describing: frame.type)) payload=\(frame.payload.count) bytes")
        switch frame.type {
        case .pairSetupNext:
            handlePairSetupResponse(frame)
        case .pairVerifyNext:
            handlePairVerifyResponse(frame)
        case .opackEncrypted, .opackUnencrypted:
            handleOPACKMessage(frame)
        default:
            break
        }
    }

    private func handlePairSetupResponse(_ frame: CompanionFrame) {
        guard let pairSetup else { return }

        // Determine which step based on TLV seqNo
        guard let opack = try? OPACK.unpack(frame.payload),
              let pd = opack["_pd"]?.dataValue else { return }
        let tlv = TLV8.decode(pd)
        guard let seqData = TLV8.find(.seqNo, in: tlv), let seq = seqData.first else { return }

        switch seq {
        case 0x02: // M2: got salt + server public key, need PIN
            pendingM2 = frame
            DispatchQueue.main.async {
                self.connectionStatus = .pairing
            }

        case 0x04: // M4: got server proof, send M5
            do {
                let (m5Frame, partialCreds) = try pairSetup.verifyAndExchangeIdentity(m4Frame: frame)
                self.partialCredentials = partialCreds
                connection?.send(frame: m5Frame)
            } catch {
                log.error("Pair-setup M4/M5 failed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.connectionStatus = .error(error.localizedDescription)
                }
            }

        case 0x06: // M6: got server identity, pairing complete
            do {
                guard let partial = partialCredentials else { return }
                let credentials = try pairSetup.processServerIdentity(m6Frame: frame, partialCredentials: partial)
                log.info("Pair-setup complete — serverID: \(credentials.serverID)")

                if let deviceName = connectedDeviceName {
                    try? KeychainStorage.save(credentials: credentials, for: deviceName)
                }

                self.currentCredentials = credentials
                startPairVerify(credentials: credentials)
            } catch {
                log.error("Pair-setup M6 failed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.connectionStatus = .error(error.localizedDescription)
                }
            }

        default:
            break
        }
    }

    private func startPairVerify(credentials: HAPCredentials) {
        guard let connection else { return }
        let verify = PairVerify(credentials: credentials)
        self.pendingPairVerify = verify
        let m1 = verify.startVerify()
        connection.send(frame: m1)
    }

    private func handlePairVerifyResponse(_ frame: CompanionFrame) {
        guard let verify = pendingPairVerify else { return }

        guard let opack = try? OPACK.unpack(frame.payload),
              let pd = opack["_pd"]?.dataValue else { return }
        let tlv = TLV8.decode(pd)
        guard let seqData = TLV8.find(.seqNo, in: tlv), let seq = seqData.first else { return }

        switch seq {
        case 0x02: // M2: got server ephemeral + encrypted proof
            do {
                let m3Frame = try verify.processAndProve(m2Frame: frame)
                connection?.send(frame: m3Frame)
            } catch {
                log.error("Pair-verify M2 failed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.connectionStatus = .error(error.localizedDescription)
                }
            }

        case 0x04: // M4: verify complete, enable encryption
            if let crypto = verify.deriveTransportKeys() {
                connection?.enableEncryption(crypto)
                log.info("Pair-verify complete, encrypted session established")
                self.startSession()
            } else {
                log.error("Failed to derive transport keys")
                DispatchQueue.main.async {
                    self.connectionStatus = .error("Failed to derive session keys")
                }
            }

        default:
            break
        }
    }

    private func startSession() {
        startCompanionSession()
        startMRPViaTunnel()
    }

    private func startCompanionSession() {
        connection?.startSession { [weak self] sid in
            if let sid {
                log.info("Session ready, SID=0x\(String(sid, radix: 16))")
            } else {
                log.warning("Session start failed, attempting fetchApps anyway")
            }
            self?.connection?.startKeepAlive()
            // Start text input listener (like pyatv does on connect)
            self?.connection?.startTextInput { [weak self] response in
                if let content = response["_c"],
                   let tiData = content["_tiD"]?.dataValue,
                   let result = try? TextInputSession.decodeStartResponse(tiData) {
                    self?.textInputSessionUUID = result.sessionUUID
                }
            }
            DispatchQueue.main.async {
                self?.connectionStatus = .connected
                self?.fetchApps()
            }
        }
    }

    private func reconnectCompanion() {
        guard let device = connectedDevice, let credentials = currentCredentials else {
            log.warning("Cannot reconnect companion: no device or credentials")
            return
        }

        log.info("Reconnecting companion link to \(device.name)")
        let conn = CompanionConnection()
        self.connection = conn

        conn.onDisconnect = { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                if self.connectionStatus == .connected {
                    log.info("Companion link closed while MRP tunnel active — reconnecting")
                    self.connection?.stopKeepAlive()
                    self.connection?.stopTextInput()
                    self.connection = nil
                    self.textInputSessionUUID = nil
                    self.sentText = ""
                    self.reconnectCompanion()
                    return
                }
            }
        }

        conn.onFrame = { [weak self] frame in
            self?.handleFrame(frame)
        }

        conn.connectToService(name: device.name)

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.startPairVerify(credentials: credentials)
        }
    }

    private func startMRPViaTunnel() {
        guard !mrpManager.isConnected else { return }
        guard let device = connectedDevice, !device.host.isEmpty, let creds = currentCredentials else {
            log.warning("Cannot start MRP: no device host or credentials")
            return
        }

        // AirPlay runs on port 7000 on the same host as companion-link
        let airplayPort: UInt16 = 7000
        log.info("Starting MRP via AirPlay tunnel: \(device.host):\(airplayPort)")
        mrpManager.onDisconnect = { [weak self] error in
            guard let self else { return }
            // MRP tunnel dropped — this is the real connection loss
            if self.connectionStatus == .connected {
                log.info("MRP tunnel lost — disconnecting")
                self.connectionStatus = .disconnected
                self.connectedDeviceName = nil
                self.connectedDevice = nil
            }
        }
        mrpManager.connect(host: device.host, port: airplayPort, credentials: creds)
    }

    func fetchApps() {
        connection?.fetchApps { [weak self] apps in
            DispatchQueue.main.async {
                self?.installedApps = apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }
        }
    }

    private func handleOPACKMessage(_ frame: CompanionFrame) {
        guard let message = try? OPACK.unpack(frame.payload) else {
            log.warning("Failed to unpack OPACK payload (\(frame.payload.count) bytes)")
            return
        }
        let type = message["_t"]?.intValue
        let keys = message.dictValue?.map { String(describing: $0.key) } ?? []
        log.debug("OPACK message: _t=\(type ?? -1) keys=\(keys)")

        switch type {
        case CompanionMessageType.event.rawValue:
            let eventName = message["_i"]?.stringValue
            log.debug("Event: \(eventName ?? "?")")

        case CompanionMessageType.response.rawValue:
            let xid = message["_x"]?.intValue ?? -1
            connection?.dispatchResponse(xid: xid, message: message)

        default:
            log.debug("Unhandled OPACK message type: \(type ?? -1)")
        }
    }
}
