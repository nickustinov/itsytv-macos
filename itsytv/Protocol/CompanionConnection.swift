import Foundation
import Network
import os.log

private let log = Logger(subsystem: "com.itsytv.app", category: "Connection")

/// Manages a TCP connection to an Apple TV's Companion Link service.
/// Handles frame parsing, encryption, and request/response correlation.
final class CompanionConnection {
    private var connection: NWConnection?
    private var buffer = Data()
    private var crypto: CompanionCrypto?
    private var nextXID: Int64

    var onFrame: ((CompanionFrame) -> Void)?
    var onDisconnect: ((Swift.Error?) -> Void)?

    init() {
        nextXID = Int64.random(in: 1...10000)
    }

    func connect(to endpoint: NWEndpoint) {
        let connection = NWConnection(to: endpoint, using: .tcp)

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.startReceiving()
            case .failed(let error):
                self?.onDisconnect?(error)
            case .cancelled:
                self?.onDisconnect?(nil)
            default:
                break
            }
        }

        connection.start(queue: .global(qos: .userInitiated))
        self.connection = connection
    }

    func connect(host: String, port: UInt16) {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!
        )
        connect(to: endpoint)
    }

    func connectToService(name: String) {
        let endpoint = NWEndpoint.service(
            name: name,
            type: "_companion-link._tcp",
            domain: "local.",
            interface: nil
        )
        connect(to: endpoint)
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        crypto = nil
        buffer = Data()
    }

    func enableEncryption(_ crypto: CompanionCrypto) {
        self.crypto = crypto
    }

    /// Send a raw frame. If encryption is active, encrypts the payload.
    func send(frame: CompanionFrame, completion: ((Swift.Error?) -> Void)? = nil) {
        var wireData: Data

        if let crypto, !frame.payload.isEmpty {
            // Build header with encrypted payload length (includes 16-byte tag)
            let encryptedLength = frame.payload.count + 16
            var header = Data(capacity: CompanionFrame.headerLength)
            header.append(frame.type.rawValue)
            header.append(UInt8((encryptedLength >> 16) & 0xFF))
            header.append(UInt8((encryptedLength >> 8) & 0xFF))
            header.append(UInt8(encryptedLength & 0xFF))

            do {
                let encrypted = try crypto.encrypt(frame.payload, aad: header)
                wireData = header + encrypted
            } catch {
                completion?(error)
                return
            }
        } else {
            wireData = frame.serialize()
        }

        connection?.send(content: wireData, completion: .contentProcessed { error in
            completion?(error)
        })
    }

    /// Send an OPACK command as an encrypted (or unencrypted) frame.
    func sendCommand(_ payload: OPACK.Value, completion: ((Swift.Error?) -> Void)? = nil) {
        let data = OPACK.pack(payload)
        let frameType: CompanionFrameType = crypto != nil ? .opackEncrypted : .opackUnencrypted
        send(frame: CompanionFrame(type: frameType, payload: data), completion: completion)
    }

    /// Send a request (type=2) with an auto-incrementing XID. Returns the XID used.
    @discardableResult
    func sendRequest(
        eventName: String? = nil,
        content: OPACK.Value? = nil,
        completion: ((Swift.Error?) -> Void)? = nil
    ) -> Int64 {
        let xid = nextXID
        nextXID += 1

        var pairs: [(String, OPACK.Value)] = [
            ("_t", .int(CompanionMessageType.request.rawValue)),
            ("_x", .int(xid)),
        ]
        if let eventName {
            pairs.append(("_i", .string(eventName)))
        }
        if let content {
            pairs.append(("_c", content))
        }

        sendCommand(.dictionary(pairs), completion: completion)
        return xid
    }

    /// Send an event (type=1).
    func sendEvent(name: String, content: OPACK.Value? = nil, completion: ((Swift.Error?) -> Void)? = nil) {
        var pairs: [(String, OPACK.Value)] = [
            ("_t", .int(CompanionMessageType.event.rawValue)),
            ("_i", .string(name)),
        ]
        if let content {
            pairs.append(("_c", content))
        }
        sendCommand(.dictionary(pairs), completion: completion)
    }

    // MARK: - Receiving

    private func startReceiving() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            if let content {
                self?.buffer.append(content)
                self?.processBuffer()
            }
            if isComplete {
                self?.onDisconnect?(nil)
            } else if let error {
                self?.onDisconnect?(error)
            } else {
                self?.startReceiving()
            }
        }
    }

    private func processBuffer() {
        while true {
            guard let (frame, consumed) = CompanionFrame.parse(from: buffer) else { break }

            var processed = frame

            // Decrypt if needed
            if let crypto, !frame.payload.isEmpty,
               (frame.type == .opackEncrypted || frame.type == .pairVerifyNext || frame.type == .pairSetupNext) {
                // Reconstruct the header as AAD
                let aad = Data([
                    frame.type.rawValue,
                    UInt8((frame.payload.count >> 16) & 0xFF),
                    UInt8((frame.payload.count >> 8) & 0xFF),
                    UInt8(frame.payload.count & 0xFF),
                ])
                do {
                    let decrypted = try crypto.decrypt(frame.payload, aad: aad)
                    processed = CompanionFrame(type: frame.type, payload: decrypted)
                } catch {
                    log.error("Decrypt failed: \(error.localizedDescription)")
                }
            }

            buffer = Data(buffer.dropFirst(consumed))
            onFrame?(processed)
        }
    }
}
