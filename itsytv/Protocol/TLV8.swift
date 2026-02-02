import Foundation

/// TLV8 encoding used in HomeKit-style pairing handshakes.
/// Each item is a (tag, value) pair. Values > 255 bytes are fragmented
/// across multiple consecutive entries with the same tag.
enum TLV8 {

    enum Tag: UInt8 {
        case method = 0x00
        case identifier = 0x01
        case salt = 0x02
        case publicKey = 0x03
        case proof = 0x04
        case encryptedData = 0x05
        case seqNo = 0x06
        case error = 0x07
        case backOff = 0x08
        case certificate = 0x09
        case signature = 0x0A
        case permissions = 0x0B
        case fragmentData = 0x0C
        case fragmentLast = 0x0D
        case name = 0x11
        case flags = 0x13
    }

    static func encode(_ items: [(Tag, Data)]) -> Data {
        var result = Data()
        for (tag, rawValue) in items {
            // Rebase to ensure 0-based indices (Data slices may have non-zero startIndex)
            let value = Data(rawValue)
            var pos = 0
            repeat {
                let chunkSize = min(value.count - pos, 255)
                result.append(tag.rawValue)
                result.append(UInt8(chunkSize))
                if chunkSize > 0 {
                    result.append(value[pos..<pos + chunkSize])
                }
                pos += chunkSize
            } while pos < value.count
            // Handle empty value: already written one (tag, 0) entry above
        }
        return result
    }

    static func decode(_ data: Data) -> [(Tag, Data)] {
        var merged: [(tag: Tag, data: Data)] = []
        var offset = 0
        while offset + 1 < data.count {
            let rawTag = data[offset]
            let length = Int(data[offset + 1])
            offset += 2

            let value: Data
            if length > 0 && offset + length <= data.count {
                value = data[offset..<offset + length]
                offset += length
            } else {
                value = Data()
                offset += min(length, data.count - offset)
            }

            guard let tag = Tag(rawValue: rawTag) else { continue }

            // Consecutive entries with the same tag are concatenated
            if let last = merged.last, last.tag == tag {
                merged[merged.count - 1].data.append(value)
            } else {
                merged.append((tag: tag, data: value))
            }
        }
        return merged
    }

    /// Look up a tag's value in decoded TLV data.
    static func find(_ tag: Tag, in items: [(Tag, Data)]) -> Data? {
        items.first(where: { $0.0 == tag })?.1
    }
}
