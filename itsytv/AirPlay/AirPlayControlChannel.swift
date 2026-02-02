import Foundation
import Network
import os.log

private let log = Logger(subsystem: "com.itsytv.app", category: "AirPlayControl")

/// HTTP/RTSP client over a raw TCP connection to the AirPlay control port (7000).
/// Handles pair-verify, HAP encryption, RTSP SETUP/RECORD, and /feedback keep-alive.
final class AirPlayControlChannel {

    enum Error: Swift.Error, LocalizedError {
        case connectionFailed(String)
        case pairVerifyFailed(String)
        case httpError(Int, String)
        case invalidResponse
        case timeout

        var errorDescription: String? {
            switch self {
            case .connectionFailed(let m): return "AirPlay connection failed: \(m)"
            case .pairVerifyFailed(let m): return "AirPlay pair-verify failed: \(m)"
            case .httpError(let code, let msg): return "AirPlay HTTP \(code): \(msg)"
            case .invalidResponse: return "Invalid AirPlay response"
            case .timeout: return "AirPlay connection timed out"
            }
        }
    }

    private var connection: NWConnection?
    private var hapSession: HAPSession?
    private var receiveBuffer = Data()
    private var cSeq = 0
    private var feedbackTimer: DispatchSourceTimer?
    private let sessionID = UUID().uuidString.uppercased()

    var onDisconnect: ((Swift.Error?) -> Void)?

    // MARK: - Connect

    func connect(host: String, port: UInt16, completion: @escaping (Result<Void, Swift.Error>) -> Void) {
        log.info("AirPlay connecting to \(host):\(port)")
        let nwHost = NWEndpoint.Host(host)
        let nwPort = NWEndpoint.Port(integerLiteral: port)
        let conn = NWConnection(host: nwHost, port: nwPort, using: .tcp)
        self.connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                log.info("AirPlay control channel connected")
                completion(.success(()))
            case .failed(let error):
                log.error("AirPlay control channel failed: \(error.localizedDescription)")
                completion(.failure(Error.connectionFailed(error.localizedDescription)))
            case .cancelled:
                self?.onDisconnect?(nil)
            default:
                break
            }
        }

        conn.start(queue: .global(qos: .userInitiated))
    }

    func disconnect() {
        stopFeedback()
        connection?.cancel()
        connection = nil
        hapSession = nil
        receiveBuffer = Data()
    }

    // MARK: - Pair-verify

    func pairVerify(credentials: HAPCredentials, completion: @escaping (Result<AirPlayPairVerify, Swift.Error>) -> Void) {
        let verify = AirPlayPairVerify(credentials: credentials)
        let m1 = verify.makeM1()

        sendHTTPRequest(method: "POST", path: "/pair-verify", body: m1, headers: pairVerifyHeaders()) { [weak self] result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let m2Data):
                do {
                    let m3 = try verify.processM2AndMakeM3(m2Data)
                    self?.sendHTTPRequest(method: "POST", path: "/pair-verify", body: m3, headers: self?.pairVerifyHeaders() ?? [:]) { result in
                        switch result {
                        case .failure(let error):
                            completion(.failure(error))
                        case .success:
                            log.info("AirPlay pair-verify complete")
                            completion(.success(verify))
                        }
                    }
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }

    // MARK: - Enable encryption

    func enableEncryption(verify: AirPlayPairVerify) -> Bool {
        guard let keys = verify.deriveKeys(
            salt: "Control-Salt",
            outputInfo: "Control-Write-Encryption-Key",
            inputInfo: "Control-Read-Encryption-Key"
        ) else {
            log.error("Failed to derive control channel keys")
            return false
        }
        hapSession = HAPSession(outputKey: keys.output, inputKey: keys.input)
        log.info("AirPlay control channel encryption enabled")
        return true
    }

    // MARK: - RTSP commands

    func setupEventChannel(completion: @escaping (Result<UInt16, Swift.Error>) -> Void) {
        let body = try! PropertyListSerialization.data(
            fromPropertyList: [
                "isRemoteControlOnly": true,
                "qualifier": ["txtAirPlay"],
                "timingProtocol": "None",
                "name": "itsytv",
                "deviceID": "FF:FF:FF:FF:FF:FF",
                "model": "iPhone14,3",
                "sourceVersion": "320.20",
                "sessionUUID": sessionID,
                "osName": "iPhone OS",
                "osVersion": "15.0",
                "osBuildVersion": "19A346",
            ] as [String: Any],
            format: .binary,
            options: 0
        )

        sendRTSPRequest(method: "SETUP", path: "rtsp://localhost/\(sessionID)", body: body, extraHeaders: [
            "Content-Type": "application/x-apple-binary-plist",
        ]) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let responseBody):
                guard let plist = try? PropertyListSerialization.propertyList(from: responseBody, format: nil) as? [String: Any],
                      let eventPort = plist["eventPort"] as? Int else {
                    completion(.failure(Error.invalidResponse))
                    return
                }
                log.info("AirPlay event port: \(eventPort)")
                completion(.success(UInt16(eventPort)))
            }
        }
    }

    func setupDataStream(seed: UInt64, completion: @escaping (Result<UInt16, Swift.Error>) -> Void) {
        let body = try! PropertyListSerialization.data(
            fromPropertyList: [
                "streams": [[
                    "type": 130,
                    "controlType": 2,
                    "seed": Int(seed),
                    "channelID": UUID().uuidString.uppercased(),
                    "clientUUID": UUID().uuidString.uppercased(),
                    "wantsDedicatedSocket": true,
                    "clientTypeUUID": "1910A70F-DBC0-4242-AF95-115DB30604E1",
                ] as [String: Any]],
            ] as [String: Any],
            format: .binary,
            options: 0
        )

        sendRTSPRequest(method: "SETUP", path: "rtsp://localhost/\(sessionID)", body: body, extraHeaders: [
            "Content-Type": "application/x-apple-binary-plist",
        ]) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let responseBody):
                guard let plist = try? PropertyListSerialization.propertyList(from: responseBody, format: nil) as? [String: Any],
                      let streams = plist["streams"] as? [[String: Any]],
                      let first = streams.first,
                      let dataPort = first["dataPort"] as? Int else {
                    completion(.failure(Error.invalidResponse))
                    return
                }
                log.info("AirPlay data port: \(dataPort)")
                completion(.success(UInt16(dataPort)))
            }
        }
    }

    func sendRecord(completion: @escaping (Result<Void, Swift.Error>) -> Void) {
        sendRTSPRequest(method: "RECORD", path: "rtsp://localhost/\(sessionID)", body: nil, extraHeaders: [:]) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success:
                log.info("AirPlay RECORD sent")
                completion(.success(()))
            }
        }
    }

    // MARK: - Feedback keep-alive

    func startFeedback() {
        stopFeedback()
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.sendHTTPRequest(method: "POST", path: "/feedback", body: nil, headers: [
                "User-Agent": "AirPlay/320.20",
                "X-Apple-Session-ID": self.sessionID,
            ]) { _ in }
        }
        timer.resume()
        feedbackTimer = timer
        log.info("AirPlay feedback keep-alive started")
    }

    private func stopFeedback() {
        feedbackTimer?.cancel()
        feedbackTimer = nil
    }

    // MARK: - HTTP request/response

    private func pairVerifyHeaders() -> [String: String] {
        [
            "User-Agent": "AirPlay/320.20",
            "Content-Type": "application/octet-stream",
            "X-Apple-HKP": "3",
        ]
    }

    private func sendHTTPRequest(
        method: String,
        path: String,
        body: Data?,
        headers: [String: String],
        completion: @escaping (Result<Data, Swift.Error>) -> Void
    ) {
        var request = "\(method) \(path) HTTP/1.1\r\n"
        for (key, value) in headers {
            request += "\(key): \(value)\r\n"
        }
        if let body {
            request += "Content-Length: \(body.count)\r\n"
        }
        request += "\r\n"

        var data = Data(request.utf8)
        if let body {
            data.append(body)
        }

        sendRaw(data) { [weak self] in
            self?.receiveHTTPResponse(completion: completion)
        }
    }

    private func sendRTSPRequest(
        method: String,
        path: String,
        body: Data?,
        extraHeaders: [String: String],
        completion: @escaping (Result<Data, Swift.Error>) -> Void
    ) {
        cSeq += 1
        var request = "\(method) \(path) RTSP/1.0\r\n"
        request += "CSeq: \(cSeq)\r\n"
        request += "User-Agent: AirPlay/320.20\r\n"
        request += "X-Apple-Session-ID: \(sessionID)\r\n"
        request += "DACP-ID: \(sessionID)\r\n"
        request += "Active-Remote: 0\r\n"
        for (key, value) in extraHeaders {
            request += "\(key): \(value)\r\n"
        }
        if let body {
            request += "Content-Length: \(body.count)\r\n"
        }
        request += "\r\n"

        var data = Data(request.utf8)
        if let body {
            data.append(body)
        }

        sendRaw(data) { [weak self] in
            self?.receiveHTTPResponse(completion: completion)
        }
    }

    // MARK: - Raw I/O (with optional HAP encryption)

    private func sendRaw(_ data: Data, completion: @escaping () -> Void) {
        guard let connection else { return }

        let wireData: Data
        if let hapSession {
            do {
                wireData = try hapSession.encrypt(data)
            } catch {
                log.error("AirPlay encrypt failed: \(error.localizedDescription)")
                return
            }
        } else {
            wireData = data
        }

        connection.send(content: wireData, completion: .contentProcessed { error in
            if let error {
                log.error("AirPlay send failed: \(error.localizedDescription)")
            }
            completion()
        })
    }

    private func receiveHTTPResponse(completion: @escaping (Result<Data, Swift.Error>) -> Void) {
        receiveRaw { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let data):
                self.receiveBuffer.append(data)
                if let response = self.parseHTTPResponse() {
                    completion(.success(response))
                } else {
                    // Need more data
                    self.receiveHTTPResponse(completion: completion)
                }
            }
        }
    }

    private func receiveRaw(completion: @escaping (Result<Data, Swift.Error>) -> Void) {
        guard let connection else {
            completion(.failure(Error.connectionFailed("No connection")))
            return
        }

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let content else {
                if isComplete {
                    self?.onDisconnect?(nil)
                }
                return
            }

            if let hapSession = self?.hapSession {
                do {
                    let decrypted = try hapSession.decrypt(content)
                    completion(.success(decrypted))
                } catch {
                    log.error("AirPlay decrypt failed: \(error.localizedDescription)")
                    completion(.failure(error))
                }
            } else {
                completion(.success(content))
            }
        }
    }

    // MARK: - HTTP response parsing

    private func parseHTTPResponse() -> Data? {
        guard let headerEnd = findHeaderEnd(in: receiveBuffer) else { return nil }

        let headerData = Data(receiveBuffer[..<headerEnd])
        guard let headerStr = String(data: headerData, encoding: .utf8) else { return nil }

        let bodyStart = headerEnd + 4 // skip \r\n\r\n

        // Parse Content-Length
        var contentLength = 0
        for line in headerStr.components(separatedBy: "\r\n") {
            if line.lowercased().hasPrefix("content-length:") {
                let value = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                contentLength = Int(value) ?? 0
            }
        }

        let totalNeeded = bodyStart + contentLength
        guard receiveBuffer.count >= totalNeeded else { return nil }

        let body = Data(receiveBuffer[bodyStart..<totalNeeded])
        receiveBuffer = Data(receiveBuffer[totalNeeded...])

        // Log full response headers for debugging
        log.info("AirPlay response headers:\n\(headerStr)")

        return body
    }

    private func findHeaderEnd(in data: Data) -> Int? {
        let pattern: [UInt8] = [0x0D, 0x0A, 0x0D, 0x0A] // \r\n\r\n
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
}
