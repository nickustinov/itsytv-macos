import Foundation
import Network
import os.log

private let log = Logger(subsystem: "com.itsytv.app", category: "HAPChannel")

/// Base class for HAP-encrypted TCP channels (event channel, data stream channel).
/// Handles TCP connect + HAP session encryption for all data.
class HAPChannel {
    private var connection: NWConnection?
    private var hapSession: HAPSession?
    private var receiveLoop = false

    var onData: ((Data) -> Void)?
    var onDisconnect: ((Swift.Error?) -> Void)?

    // MARK: - Connect

    func connect(
        host: String,
        port: UInt16,
        outputKey: Data,
        inputKey: Data,
        completion: @escaping (Result<Void, Swift.Error>) -> Void
    ) {
        log.info("HAPChannel connecting to \(host):\(port)")
        let nwHost = NWEndpoint.Host(host)
        let nwPort = NWEndpoint.Port(integerLiteral: port)
        let conn = NWConnection(host: nwHost, port: nwPort, using: .tcp)
        self.connection = conn
        self.hapSession = HAPSession(outputKey: outputKey, inputKey: inputKey)

        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                log.info("HAPChannel connected")
                self?.startReceiving()
                completion(.success(()))
            case .failed(let error):
                log.error("HAPChannel failed: \(error.localizedDescription)")
                completion(.failure(error))
            case .cancelled:
                self?.onDisconnect?(nil)
            default:
                break
            }
        }

        conn.start(queue: .global(qos: .userInitiated))
    }

    func disconnect() {
        receiveLoop = false
        connection?.cancel()
        connection = nil
        hapSession = nil
    }

    // MARK: - Send

    func send(_ data: Data) {
        guard let connection, let hapSession else { return }
        do {
            let encrypted = try hapSession.encrypt(data)
            log.info("HAPChannel sending \(data.count) plain → \(encrypted.count) encrypted bytes")
            connection.send(content: encrypted, completion: .contentProcessed { error in
                if let error {
                    log.error("HAPChannel send failed: \(error.localizedDescription)")
                }
            })
        } catch {
            log.error("HAPChannel encrypt failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Receive

    private func startReceiving() {
        receiveLoop = true
        receiveNext()
    }

    private func receiveNext() {
        guard receiveLoop, let connection else { return }

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self else { return }

            if let content {
                log.info("HAPChannel received \(content.count) raw bytes, isComplete=\(isComplete)")
                if let hapSession = self.hapSession {
                    do {
                        let decrypted = try hapSession.decrypt(content)
                        if !decrypted.isEmpty {
                            log.info("HAPChannel decrypted \(decrypted.count) bytes")
                            self.onData?(decrypted)
                        }
                    } catch {
                        log.error("HAPChannel decrypt failed: \(error.localizedDescription)")
                        self.onDisconnect?(error)
                        return
                    }
                }
            } else {
                log.info("HAPChannel receive: no content, isComplete=\(isComplete), error=\(error?.localizedDescription ?? "nil")")
            }

            if isComplete {
                log.info("HAPChannel connection complete (remote closed)")
                self.onDisconnect?(nil)
            } else if let error {
                log.error("HAPChannel receive error: \(error.localizedDescription)")
                self.onDisconnect?(error)
            } else {
                self.receiveNext()
            }
        }
    }
}
