import Foundation

/// Frame types used by the Companion Link protocol.
enum CompanionFrameType: UInt8 {
    case unknown = 0
    case noOp = 1
    case pairSetupStart = 3
    case pairSetupNext = 4
    case pairVerifyStart = 5
    case pairVerifyNext = 6
    case opackUnencrypted = 7
    case opackEncrypted = 8
    case opackPacked = 9
    case pairingRequest = 10
    case pairingResponse = 11
    case sessionStartRequest = 16
    case sessionStartResponse = 17
    case sessionData = 18
    case familyIdentityRequest = 32
    case familyIdentityResponse = 33
    case familyIdentityUpdate = 34
}

/// A single Companion protocol frame: 1-byte type + 3-byte big-endian length + payload.
struct CompanionFrame {
    let type: CompanionFrameType
    let payload: Data

    static let headerLength = 4

    /// Serialize this frame into wire bytes (unencrypted).
    func serialize() -> Data {
        var data = Data(capacity: Self.headerLength + payload.count)
        data.append(type.rawValue)
        let len = UInt32(payload.count)
        data.append(UInt8((len >> 16) & 0xFF))
        data.append(UInt8((len >> 8) & 0xFF))
        data.append(UInt8(len & 0xFF))
        data.append(payload)
        return data
    }

    /// Try to parse a frame from a buffer. Returns nil if not enough data.
    /// On success, returns the frame and the number of bytes consumed.
    static func parse(from buffer: Data) -> (frame: CompanionFrame, consumed: Int)? {
        guard buffer.count >= headerLength else { return nil }

        let rawType = buffer[0]
        let payloadLength = Int(buffer[1]) << 16 | Int(buffer[2]) << 8 | Int(buffer[3])
        let totalLength = headerLength + payloadLength

        guard buffer.count >= totalLength else { return nil }

        let frameType = CompanionFrameType(rawValue: rawType) ?? .unknown
        let payload = buffer[headerLength..<totalLength]

        return (CompanionFrame(type: frameType, payload: Data(payload)), totalLength)
    }

    /// The 4-byte header, needed as AAD for encryption.
    var header: Data {
        var data = Data(capacity: Self.headerLength)
        data.append(type.rawValue)
        let len = UInt32(payload.count)
        data.append(UInt8((len >> 16) & 0xFF))
        data.append(UInt8((len >> 8) & 0xFF))
        data.append(UInt8(len & 0xFF))
        return data
    }
}

/// Message type identifiers used in OPACK command frames.
enum CompanionMessageType: Int64 {
    case event = 1
    case request = 2
    case response = 3
}
