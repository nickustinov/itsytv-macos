import Foundation
import os.log

private let log = Logger(subsystem: "com.itsytv.app", category: "DataStream")

/// Data stream channel for MRP protobuf transport over AirPlay 2.
/// Extends HAPChannel with data stream framing (32-byte header + binary plist payload).
///
/// Wire format (big-endian):
/// - 32-byte header: [size:4 BE][type:12][command:4][seqno:8 BE][padding:4]
/// - Payload: binary plist with `{"params": {"data": <varint-prefixed protobuf bytes>}}`
///
/// Outgoing messages use type="sync"+8*0x00, command="comm".
/// Incoming "sync" messages receive automatic "rply" responses.
final class DataStreamChannel: HAPChannel {

    var onProtobuf: ((MRP_ProtocolMessage) -> Void)?

    private var sendSeqNo: UInt64
    private var messageBuffer = Data()

    private static let syncType: Data = {
        var d = Data("sync".utf8)
        d.append(contentsOf: [UInt8](repeating: 0, count: 8))
        return d
    }()

    private static let rplyType: Data = {
        var d = Data("rply".utf8)
        d.append(contentsOf: [UInt8](repeating: 0, count: 8))
        return d
    }()

    private static let commCommand = Data("comm".utf8)
    private static let zeroCommand = Data(count: 4)
    private static let headerSize = 32

    override init() {
        // pyatv uses randrange(0x100000000, 0x1FFFFFFFF)
        sendSeqNo = UInt64.random(in: 0x100000000...0x1FFFFFFFF)
        super.init()

        onData = { [weak self] data in
            self?.handleData(data)
        }
    }

    // MARK: - Send MRP protobuf

    func sendProtobuf(_ message: MRP_ProtocolMessage) {
        do {
            let serialized = try message.serializedData()
            let varintPrefixed = varintEncode(serialized.count) + serialized

            // Wrap in binary plist
            let plistDict: [String: Any] = [
                "params": ["data": varintPrefixed] as [String: Any]
            ]
            let plistData = try PropertyListSerialization.data(
                fromPropertyList: plistDict, format: .binary, options: 0
            )

            // Build 32-byte data stream header + payload
            let frame = buildFrame(
                type: Self.syncType,
                command: Self.commCommand,
                seqNo: sendSeqNo,
                payload: plistData
            )
            sendSeqNo += 1
            send(frame)

            let typeStr = message.hasType ? String(describing: message.type) : "no-type"
            log.info("DataStream sent MRP: \(typeStr) (\(serialized.count) bytes)")
        } catch {
            log.error("DataStream send failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Receive

    private func handleData(_ data: Data) {
        messageBuffer.append(data)
        processMessageBuffer()
    }

    private func processMessageBuffer() {
        while messageBuffer.count >= Self.headerSize {
            // Parse 32-byte header (big-endian)
            // Size field includes the 32-byte header itself
            let totalSize = Int(readUInt32BE(messageBuffer, offset: 0))

            guard totalSize >= Self.headerSize else {
                log.error("DataStream invalid size: \(totalSize)")
                messageBuffer = Data()
                break
            }

            guard messageBuffer.count >= totalSize else { break }

            let msgType = Data(messageBuffer[4..<16])
            let seqNo = readUInt64BE(messageBuffer, offset: 20)
            let payload = Data(messageBuffer[Self.headerSize..<totalSize])
            messageBuffer = Data(messageBuffer[totalSize...])

            // Reply to "sync" messages
            if msgType.starts(with: Data("sync".utf8)) {
                sendReply(seqNo: seqNo)
            }

            let typeStr = String(data: msgType.prefix(4), encoding: .utf8) ?? "?"
            log.info("DataStream frame: type=\(typeStr) seqNo=\(seqNo) payloadSize=\(payload.count)")

            if !payload.isEmpty {
                processPayload(payload)
            }
        }
    }

    private func sendReply(seqNo: UInt64) {
        let frame = buildFrame(
            type: Self.rplyType,
            command: Self.zeroCommand,
            seqNo: seqNo,
            payload: Data()
        )
        send(frame)
    }

    private func processPayload(_ payload: Data) {
        if let plist = try? PropertyListSerialization.propertyList(from: payload, format: nil) {
            log.info("DataStream plist: \(String(describing: plist))")
        }

        guard let plistDict = try? PropertyListSerialization.propertyList(from: payload, format: nil) as? [String: Any],
              let params = plistDict["params"] as? [String: Any],
              let data = params["data"] as? Data else {
            log.debug("DataStream non-MRP payload (\(payload.count) bytes)")
            return
        }

        // Parse varint-prefixed protobufs (may contain multiple).
        // Protobuf field #1 (type) has tag 0x08. A varint starting with 0x08 means
        // length=8, but minimum ProtocolMessage is ~40 bytes, so 0x08 as first byte
        // means the message is NOT length-prefixed (e.g. ConfigureConnectionMessage).
        var remaining = data
        while !remaining.isEmpty {
            let firstByte = remaining[remaining.startIndex]

            if firstByte == 0x08 {
                // Bare protobuf (no length prefix) — consume all remaining data
                do {
                    let message = try MRP_ProtocolMessage(serializedBytes: remaining, extensions: MRP_ProtocolMessage_Extensions)
                    let typeStr = message.hasType ? String(describing: message.type) : "unknown"
                    log.info("DataStream received MRP (bare): \(typeStr) (\(remaining.count) bytes)")
                    onProtobuf?(message)
                } catch {
                    log.error("DataStream protobuf parse failed: \(error.localizedDescription)")
                }
                break
            }

            guard let (length, bytesRead) = varintDecode(remaining) else {
                log.error("DataStream invalid varint prefix (first byte=0x\(String(firstByte, radix: 16)))")
                break
            }

            let start = remaining.startIndex + bytesRead
            guard remaining.count >= bytesRead + length else {
                log.error("DataStream incomplete protobuf: need \(bytesRead + length), have \(remaining.count)")
                break
            }

            let end = start + length
            let protobufData = Data(remaining[start..<end])
            remaining = Data(remaining[end...])

            do {
                let message = try MRP_ProtocolMessage(serializedBytes: protobufData, extensions: MRP_ProtocolMessage_Extensions)
                let typeStr = message.hasType ? String(describing: message.type) : "unknown"
                log.info("DataStream received MRP (prefixed): \(typeStr) (\(length) bytes)")
                onProtobuf?(message)
            } catch {
                log.error("DataStream protobuf parse failed (\(length) bytes): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Frame building

    private func buildFrame(type: Data, command: Data, seqNo: UInt64, payload: Data) -> Data {
        var frame = Data(count: Self.headerSize)

        // Size (4 bytes BE) — total message size INCLUDING the 32-byte header
        writeUInt32BE(&frame, offset: 0, value: UInt32(Self.headerSize + payload.count))

        // Type (12 bytes)
        frame.replaceSubrange(4..<16, with: type)

        // Command (4 bytes)
        frame.replaceSubrange(16..<20, with: command)

        // SeqNo (8 bytes BE)
        writeUInt64BE(&frame, offset: 20, value: seqNo)

        // Padding (4 bytes) — already zero

        frame.append(payload)
        return frame
    }

    // MARK: - Varint

    private func varintEncode(_ value: Int) -> Data {
        var result = Data()
        var v = value
        while v > 0x7F {
            result.append(UInt8(v & 0x7F) | 0x80)
            v >>= 7
        }
        result.append(UInt8(v & 0x7F))
        return result
    }

    private func varintDecode(_ data: Data) -> (value: Int, bytesRead: Int)? {
        var value = 0
        var shift = 0
        for i in 0..<min(data.count, 10) {
            let byte = data[data.startIndex + i]
            value |= Int(byte & 0x7F) << shift
            if byte & 0x80 == 0 {
                return (value, i + 1)
            }
            shift += 7
        }
        return nil
    }

    // MARK: - Binary helpers (big-endian)

    private func readUInt32BE(_ data: Data, offset: Int) -> UInt32 {
        let base = data.startIndex + offset
        return UInt32(data[base]) << 24
            | UInt32(data[base + 1]) << 16
            | UInt32(data[base + 2]) << 8
            | UInt32(data[base + 3])
    }

    private func readUInt64BE(_ data: Data, offset: Int) -> UInt64 {
        let base = data.startIndex + offset
        var result: UInt64 = 0
        for i in 0..<8 {
            result = result << 8 | UInt64(data[base + i])
        }
        return result
    }

    private func writeUInt32BE(_ data: inout Data, offset: Int, value: UInt32) {
        data[offset] = UInt8((value >> 24) & 0xFF)
        data[offset + 1] = UInt8((value >> 16) & 0xFF)
        data[offset + 2] = UInt8((value >> 8) & 0xFF)
        data[offset + 3] = UInt8(value & 0xFF)
    }

    private func writeUInt64BE(_ data: inout Data, offset: Int, value: UInt64) {
        for i in 0..<8 {
            data[offset + i] = UInt8((value >> (56 - i * 8)) & 0xFF)
        }
    }
}
