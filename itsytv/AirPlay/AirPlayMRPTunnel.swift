import Foundation
import os.log

private let log = Logger(subsystem: "com.itsytv.app", category: "AirPlayMRPTunnel")

/// Orchestrates the full AirPlay 2 tunnel setup sequence to transport MRP protobufs.
/// Provides the same interface as the old MRPConnection: connect, send, onMessage, onReady, onDisconnect.
///
/// Sequence: TCP connect → pair-verify → enable HAP encryption → SETUP event channel →
/// connect event channel → RECORD → SETUP data channel → connect data channel →
/// start feedback → call onReady.
final class AirPlayMRPTunnel {

    var onMessage: ((MRP_ProtocolMessage) -> Void)?
    var onDisconnect: ((Swift.Error?) -> Void)?
    var onReady: (() -> Void)?

    private var controlChannel: AirPlayControlChannel?
    private var eventChannel: HAPChannel?
    private var dataChannel: DataStreamChannel?
    private var host: String = ""
    private var heartbeatTimer: DispatchSourceTimer?

    // MARK: - Connect

    func connect(host: String, port: UInt16, credentials: HAPCredentials) {
        log.info("AirPlayMRPTunnel starting: \(host):\(port)")
        self.host = host

        let control = AirPlayControlChannel()
        self.controlChannel = control

        control.onDisconnect = { [weak self] error in
            log.info("AirPlay control channel disconnected")
            self?.handleDisconnect(error)
        }

        control.connect(host: host, port: port) { [weak self] result in
            switch result {
            case .failure(let error):
                log.error("AirPlay connect failed: \(error.localizedDescription)")
                self?.onDisconnect?(error)
            case .success:
                self?.startPairVerify(credentials: credentials)
            }
        }
    }

    func disconnect() {
        stopHeartbeat()
        dataChannel?.disconnect()
        dataChannel = nil
        eventChannel?.disconnect()
        eventChannel = nil
        controlChannel?.disconnect()
        controlChannel = nil
    }

    // MARK: - Send

    func send(_ message: MRP_ProtocolMessage) {
        dataChannel?.sendProtobuf(message)
    }

    // MARK: - Heartbeat

    func startHeartbeat(interval: TimeInterval = 30) {
        stopHeartbeat()
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            guard self?.dataChannel != nil else { return }
            var msg = MRP_ProtocolMessage()
            msg.type = .genericMessage
            msg.uniqueIdentifier = UUID().uuidString.uppercased()
            self?.send(msg)
        }
        timer.resume()
        heartbeatTimer = timer
    }

    private func stopHeartbeat() {
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
    }

    // MARK: - Setup sequence

    private func startPairVerify(credentials: HAPCredentials) {
        guard let controlChannel else { return }
        log.info("AirPlay starting pair-verify")

        controlChannel.pairVerify(credentials: credentials) { [weak self] result in
            switch result {
            case .failure(let error):
                log.error("AirPlay pair-verify failed: \(error.localizedDescription)")
                self?.onDisconnect?(error)
            case .success(let verify):
                self?.enableControlEncryption(verify: verify, credentials: credentials)
            }
        }
    }

    private func enableControlEncryption(verify: AirPlayPairVerify, credentials: HAPCredentials) {
        guard let controlChannel else { return }

        guard controlChannel.enableEncryption(verify: verify) else {
            onDisconnect?(AirPlayControlChannel.Error.pairVerifyFailed("Failed to derive control keys"))
            return
        }

        log.info("AirPlay control encryption enabled, setting up event channel")
        setupEventChannel(verify: verify)
    }

    private func setupEventChannel(verify: AirPlayPairVerify) {
        guard let controlChannel else { return }

        controlChannel.setupEventChannel { [weak self] result in
            switch result {
            case .failure(let error):
                log.error("AirPlay event channel setup failed: \(error.localizedDescription)")
                self?.onDisconnect?(error)
            case .success(let eventPort):
                self?.connectEventChannel(port: eventPort, verify: verify)
            }
        }
    }

    private func connectEventChannel(port: UInt16, verify: AirPlayPairVerify) {
        // Event channel keys — note: output/input are REVERSED because the connection
        // comes FROM the receiver
        guard let keys = verify.deriveKeys(
            salt: "Events-Salt",
            outputInfo: "Events-Read-Encryption-Key",  // reversed: Read becomes our Output
            inputInfo: "Events-Write-Encryption-Key"    // reversed: Write becomes our Input
        ) else {
            onDisconnect?(AirPlayControlChannel.Error.pairVerifyFailed("Failed to derive event keys"))
            return
        }

        let event = HAPChannel()
        self.eventChannel = event

        // The Apple TV sends HTTP requests on the event channel.
        // We must reply with 200 OK or it tears down the session.
        event.onData = { [weak self] data in
            self?.handleEventChannelData(data)
        }

        event.onDisconnect = { [weak self] error in
            log.info("AirPlay event channel disconnected")
            self?.handleDisconnect(error)
        }

        event.connect(host: host, port: port, outputKey: keys.output, inputKey: keys.input) { [weak self] result in
            switch result {
            case .failure(let error):
                log.error("AirPlay event channel connect failed: \(error.localizedDescription)")
                self?.onDisconnect?(error)
            case .success:
                log.info("AirPlay event channel connected")
                self?.sendRecordThenSetupData(verify: verify)
            }
        }
    }

    private func sendRecordThenSetupData(verify: AirPlayPairVerify) {
        guard let controlChannel else { return }

        controlChannel.sendRecord { [weak self] result in
            switch result {
            case .failure(let error):
                log.error("AirPlay RECORD failed: \(error.localizedDescription)")
                self?.onDisconnect?(error)
            case .success:
                log.info("AirPlay RECORD sent, setting up data channel")
                self?.setupDataChannel(verify: verify)
            }
        }
    }

    private func setupDataChannel(verify: AirPlayPairVerify) {
        guard let controlChannel else { return }

        let seed = UInt64.random(in: 0...UInt64(Int.max))

        controlChannel.setupDataStream(seed: seed) { [weak self] result in
            switch result {
            case .failure(let error):
                log.error("AirPlay data channel setup failed: \(error.localizedDescription)")
                self?.onDisconnect?(error)
            case .success(let dataPort):
                self?.connectDataChannel(port: dataPort, seed: seed, verify: verify)
            }
        }
    }

    private func connectDataChannel(port: UInt16, seed: UInt64, verify: AirPlayPairVerify) {
        // Data stream keys — seed appended to salt as string
        let salt = "DataStream-Salt" + String(seed)
        guard let keys = verify.deriveKeys(
            salt: salt,
            outputInfo: "DataStream-Output-Encryption-Key",
            inputInfo: "DataStream-Input-Encryption-Key"
        ) else {
            onDisconnect?(AirPlayControlChannel.Error.pairVerifyFailed("Failed to derive data stream keys"))
            return
        }

        let data = DataStreamChannel()
        self.dataChannel = data

        data.onProtobuf = { [weak self] message in
            self?.onMessage?(message)
        }

        data.onDisconnect = { [weak self] error in
            log.info("AirPlay data channel disconnected")
            self?.handleDisconnect(error)
        }

        data.connect(host: host, port: port, outputKey: keys.output, inputKey: keys.input) { [weak self] result in
            switch result {
            case .failure(let error):
                log.error("AirPlay data channel connect failed: \(error.localizedDescription)")
                self?.onDisconnect?(error)
            case .success:
                log.info("AirPlay tunnel fully established")
                self?.controlChannel?.startFeedback()
                self?.onReady?()
            }
        }
    }

    // MARK: - Event channel handling

    private var eventBuffer = Data()

    private func handleEventChannelData(_ data: Data) {
        eventBuffer.append(data)

        // Look for HTTP request header end (\r\n\r\n)
        guard let headerEnd = findCRLFCRLF(in: eventBuffer) else { return }

        let headerData = Data(eventBuffer[..<headerEnd])
        guard let headerStr = String(data: headerData, encoding: .utf8) else {
            eventBuffer = Data()
            return
        }

        // Parse Content-Length to know if there's a body
        var contentLength = 0
        var cseq = ""
        var server = ""
        var proto = "RTSP/1.0"
        for line in headerStr.components(separatedBy: "\r\n") {
            if line.lowercased().hasPrefix("content-length:") {
                contentLength = Int(line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) ?? 0
            } else if line.lowercased().hasPrefix("cseq:") {
                cseq = line.dropFirst("cseq:".count).trimmingCharacters(in: .whitespaces)
            } else if line.lowercased().hasPrefix("server:") {
                server = line.dropFirst("server:".count).trimmingCharacters(in: .whitespaces)
            }
        }
        // Extract protocol from first line
        let lines = headerStr.components(separatedBy: "\r\n")
        if let firstLine = lines.first {
            let parts = firstLine.components(separatedBy: " ")
            if parts.count >= 3 {
                proto = parts.last ?? "RTSP/1.0"
            }
        }

        let bodyStart = headerEnd + 4
        let totalNeeded = bodyStart + contentLength
        guard eventBuffer.count >= totalNeeded else { return }

        log.info("Event channel request: \(lines.first ?? "?")")

        // Consume this request from the buffer
        eventBuffer = Data(eventBuffer[totalNeeded...])

        // Send 200 OK response
        var response = "\(proto) 200 OK\r\n"
        response += "Content-Length: 0\r\n"
        response += "Audio-Latency: 0\r\n"
        if !server.isEmpty {
            response += "Server: \(server)\r\n"
        }
        if !cseq.isEmpty {
            response += "CSeq: \(cseq)\r\n"
        }
        response += "\r\n"

        eventChannel?.send(Data(response.utf8))
        log.info("Event channel responded with 200 OK")
    }

    private func findCRLFCRLF(in data: Data) -> Int? {
        let pattern: [UInt8] = [0x0D, 0x0A, 0x0D, 0x0A]
        guard data.count >= 4 else { return nil }
        for i in 0..<(data.count - 3) {
            if data[data.startIndex + i] == pattern[0]
                && data[data.startIndex + i + 1] == pattern[1]
                && data[data.startIndex + i + 2] == pattern[2]
                && data[data.startIndex + i + 3] == pattern[3] {
                return i
            }
        }
        return nil
    }

    // MARK: - Disconnect handling

    private func handleDisconnect(_ error: Swift.Error?) {
        disconnect()
        onDisconnect?(error)
    }
}
