import Foundation

/// Apple's OPACK binary serialization format.
/// Used by the Companion Link protocol for all message payloads.
enum OPACK {

    enum Value: Equatable {
        case null
        case bool(Bool)
        case int(Int64)
        case float32(Float)
        case float64(Double)
        case string(String)
        case data(Data)
        case uuid(UUID)
        case date(UInt64)
        case array([Value])
        case dict([(key: Value, value: Value)])

        static func == (lhs: Value, rhs: Value) -> Bool {
            switch (lhs, rhs) {
            case (.null, .null): return true
            case (.bool(let a), .bool(let b)): return a == b
            case (.int(let a), .int(let b)): return a == b
            case (.float32(let a), .float32(let b)): return a == b
            case (.float64(let a), .float64(let b)): return a == b
            case (.string(let a), .string(let b)): return a == b
            case (.data(let a), .data(let b)): return a == b
            case (.uuid(let a), .uuid(let b)): return a == b
            case (.date(let a), .date(let b)): return a == b
            case (.array(let a), .array(let b)): return a == b
            case (.dict(let a), .dict(let b)):
                guard a.count == b.count else { return false }
                for (pairA, pairB) in zip(a, b) {
                    if pairA.key != pairB.key || pairA.value != pairB.value { return false }
                }
                return true
            default: return false
            }
        }

        // Convenience accessors

        var stringValue: String? {
            if case .string(let s) = self { return s }
            return nil
        }

        var intValue: Int64? {
            if case .int(let i) = self { return i }
            return nil
        }

        var dataValue: Data? {
            if case .data(let d) = self { return d }
            return nil
        }

        var boolValue: Bool? {
            if case .bool(let b) = self { return b }
            return nil
        }

        var dictValue: [(key: Value, value: Value)]? {
            if case .dict(let d) = self { return d }
            return nil
        }

        var arrayValue: [Value]? {
            if case .array(let a) = self { return a }
            return nil
        }

        /// Look up a value by string key in a dict.
        subscript(key: String) -> Value? {
            guard case .dict(let pairs) = self else { return nil }
            return pairs.first(where: { $0.key == .string(key) })?.value
        }
    }

    enum Error: Swift.Error {
        case unexpectedEnd
        case invalidTag(UInt8)
        case invalidUTF8
        case invalidPointer(Int)
    }

    // MARK: - Encoding

    static func pack(_ value: Value) -> Data {
        var data = Data()
        encode(value, into: &data)
        return data
    }

    private static func encode(_ value: Value, into data: inout Data) {
        switch value {
        case .null:
            data.append(0x04)

        case .bool(let b):
            data.append(b ? 0x01 : 0x02)

        case .int(let n):
            if n >= 0 && n <= 39 {
                data.append(UInt8(0x08 + n))
            } else if n >= 0 && n <= 0xFF {
                data.append(0x30)
                data.append(UInt8(n))
            } else if n >= 0 && n <= 0xFFFF {
                data.append(0x31)
                appendLE(UInt16(n), to: &data)
            } else if n >= 0 && n <= 0xFFFF_FFFF {
                data.append(0x32)
                appendLE(UInt32(n), to: &data)
            } else {
                data.append(0x33)
                appendLE(UInt64(bitPattern: n), to: &data)
            }

        case .float32(let f):
            data.append(0x35)
            appendLE(f.bitPattern, to: &data)

        case .float64(let f):
            data.append(0x36)
            appendLE(f.bitPattern, to: &data)

        case .string(let s):
            let utf8 = Array(s.utf8)
            let len = utf8.count
            if len <= 32 {
                data.append(UInt8(0x40 + len))
            } else if len <= 0xFF {
                data.append(0x61)
                data.append(UInt8(len))
            } else if len <= 0xFFFF {
                data.append(0x62)
                appendLE(UInt16(len), to: &data)
            } else if len <= 0xFF_FFFF {
                data.append(0x63)
                data.append(UInt8(len & 0xFF))
                data.append(UInt8((len >> 8) & 0xFF))
                data.append(UInt8((len >> 16) & 0xFF))
            } else {
                data.append(0x64)
                appendLE(UInt32(len), to: &data)
            }
            data.append(contentsOf: utf8)

        case .data(let d):
            let len = d.count
            if len <= 32 {
                data.append(UInt8(0x70 + len))
            } else if len <= 0xFF {
                data.append(0x91)
                data.append(UInt8(len))
            } else if len <= 0xFFFF {
                data.append(0x92)
                appendLE(UInt16(len), to: &data)
            } else if len <= 0xFFFF_FFFF {
                data.append(0x93)
                appendLE(UInt32(len), to: &data)
            } else {
                data.append(0x94)
                appendLE(UInt64(len), to: &data)
            }
            data.append(d)

        case .uuid(let uuid):
            data.append(0x05)
            let u = uuid.uuid
            data.append(contentsOf: [
                u.0, u.1, u.2, u.3, u.4, u.5, u.6, u.7,
                u.8, u.9, u.10, u.11, u.12, u.13, u.14, u.15,
            ])

        case .date(let t):
            data.append(0x06)
            appendLE(t, to: &data)

        case .array(let items):
            if items.count < 15 {
                data.append(UInt8(0xD0 + items.count))
            } else {
                data.append(0xDF)
            }
            for item in items {
                encode(item, into: &data)
            }
            if items.count >= 15 {
                data.append(0x03)
            }

        case .dict(let pairs):
            if pairs.count < 15 {
                data.append(UInt8(0xE0 + pairs.count))
            } else {
                data.append(0xEF)
            }
            for pair in pairs {
                encode(pair.key, into: &data)
                encode(pair.value, into: &data)
            }
            if pairs.count >= 15 {
                data.append(0x03)
            }
        }
    }

    private static func appendLE<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var v = value.littleEndian
        withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
    }

    // MARK: - Decoding

    static func unpack(_ data: Data) throws -> Value {
        var offset = 0
        var objectList: [Value] = []
        return try decode(data, offset: &offset, objectList: &objectList)
    }

    private static func decode(_ data: Data, offset: inout Int, objectList: inout [Value]) throws -> Value {
        guard offset < data.count else { throw Error.unexpectedEnd }
        let tag = data[offset]
        offset += 1

        switch tag {
        case 0x01:
            return .bool(true)
        case 0x02:
            return .bool(false)
        case 0x04:
            return .null

        case 0x05:
            let bytes = try readBytes(data, offset: &offset, count: 16)
            let uuid = UUID(uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3],
                bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11],
                bytes[12], bytes[13], bytes[14], bytes[15]
            ))
            let value = Value.uuid(uuid)
            objectList.append(value)
            return value

        case 0x06:
            let bytes = try readBytes(data, offset: &offset, count: 8)
            let t = readLEUInt64(bytes, at: 0)
            let value = Value.date(t)
            objectList.append(value)
            return value

        case 0x07:
            return .int(-1)

        case 0x08...0x2F:
            return .int(Int64(tag - 0x08))

        case 0x30...0x33:
            let byteCount = 1 << (tag & 0x03)
            let bytes = try readBytes(data, offset: &offset, count: byteCount)
            let n: Int64
            switch byteCount {
            case 1: n = Int64(bytes[0])
            case 2: n = Int64(readLEUInt16(bytes, at: 0))
            case 4: n = Int64(readLEUInt32(bytes, at: 0))
            case 8: n = Int64(bitPattern: readLEUInt64(bytes, at: 0))
            default: throw Error.invalidTag(tag)
            }
            let value = Value.int(n)
            objectList.append(value)
            return value

        case 0x35:
            let bytes = try readBytes(data, offset: &offset, count: 4)
            let bits = readLEUInt32(bytes, at: 0)
            let value = Value.float32(Float(bitPattern: bits))
            objectList.append(value)
            return value

        case 0x36:
            let bytes = try readBytes(data, offset: &offset, count: 8)
            let bits = readLEUInt64(bytes, at: 0)
            let value = Value.float64(Double(bitPattern: bits))
            objectList.append(value)
            return value

        case 0x40...0x60:
            let len = Int(tag - 0x40)
            let bytes = try readBytes(data, offset: &offset, count: len)
            guard let s = String(bytes: bytes, encoding: .utf8) else { throw Error.invalidUTF8 }
            let value = Value.string(s)
            if len > 0 { objectList.append(value) }
            return value

        case 0x61...0x64:
            let lenBytes = Int(tag & 0x0F)
            let len = try readLength(data, offset: &offset, byteCount: lenBytes)
            let bytes = try readBytes(data, offset: &offset, count: len)
            guard let s = String(bytes: bytes, encoding: .utf8) else { throw Error.invalidUTF8 }
            let value = Value.string(s)
            objectList.append(value)
            return value

        case 0x70...0x90:
            let len = Int(tag - 0x70)
            let bytes = try readBytes(data, offset: &offset, count: len)
            let value = Value.data(Data(bytes))
            if len > 0 { objectList.append(value) }
            return value

        case 0x91...0x94:
            let lenByteCount = 1 << (Int(tag & 0x0F) - 1)
            let len = try readLength(data, offset: &offset, byteCount: lenByteCount)
            let bytes = try readBytes(data, offset: &offset, count: len)
            let value = Value.data(Data(bytes))
            objectList.append(value)
            return value

        case 0xA0...0xC0:
            let index = Int(tag - 0xA0)
            guard index < objectList.count else { throw Error.invalidPointer(index) }
            return objectList[index]

        case 0xC1...0xC4:
            let lenByteCount = 1 << (Int(tag & 0x0F) - 1)
            let index = try readLength(data, offset: &offset, byteCount: lenByteCount)
            guard index < objectList.count else { throw Error.invalidPointer(index) }
            return objectList[index]

        case 0xD0...0xDF:
            let count = Int(tag & 0x0F)
            let endless = count == 0x0F
            var items: [Value] = []
            if endless {
                while offset < data.count && data[offset] != 0x03 {
                    items.append(try decode(data, offset: &offset, objectList: &objectList))
                }
                if offset < data.count { offset += 1 } // consume terminator
            } else {
                for _ in 0..<count {
                    items.append(try decode(data, offset: &offset, objectList: &objectList))
                }
            }
            return .array(items)

        case 0xE0...0xFF:
            let count = Int(tag & 0x0F)
            let endless = count == 0x0F
            var pairs: [(key: Value, value: Value)] = []
            if endless {
                while offset < data.count && data[offset] != 0x03 {
                    let key = try decode(data, offset: &offset, objectList: &objectList)
                    let val = try decode(data, offset: &offset, objectList: &objectList)
                    pairs.append((key: key, value: val))
                }
                if offset < data.count { offset += 1 } // consume terminator
            } else {
                for _ in 0..<count {
                    let key = try decode(data, offset: &offset, objectList: &objectList)
                    let val = try decode(data, offset: &offset, objectList: &objectList)
                    pairs.append((key: key, value: val))
                }
            }
            return .dict(pairs)

        default:
            throw Error.invalidTag(tag)
        }
    }

    // MARK: - Helpers

    private static func readBytes(_ data: Data, offset: inout Int, count: Int) throws -> [UInt8] {
        guard offset + count <= data.count else { throw Error.unexpectedEnd }
        let bytes = Array(data[offset..<offset + count])
        offset += count
        return bytes
    }

    private static func readLength(_ data: Data, offset: inout Int, byteCount: Int) throws -> Int {
        let bytes = try readBytes(data, offset: &offset, count: byteCount)
        var result: UInt64 = 0
        for i in 0..<byteCount {
            result |= UInt64(bytes[i]) << (i * 8)
        }
        return Int(result)
    }

    private static func readLEUInt16(_ bytes: [UInt8], at i: Int) -> UInt16 {
        UInt16(bytes[i]) | UInt16(bytes[i + 1]) << 8
    }

    private static func readLEUInt32(_ bytes: [UInt8], at i: Int) -> UInt32 {
        UInt32(bytes[i]) | UInt32(bytes[i + 1]) << 8 |
        UInt32(bytes[i + 2]) << 16 | UInt32(bytes[i + 3]) << 24
    }

    private static func readLEUInt64(_ bytes: [UInt8], at i: Int) -> UInt64 {
        UInt64(bytes[i]) | UInt64(bytes[i + 1]) << 8 |
        UInt64(bytes[i + 2]) << 16 | UInt64(bytes[i + 3]) << 24 |
        UInt64(bytes[i + 4]) << 32 | UInt64(bytes[i + 5]) << 40 |
        UInt64(bytes[i + 6]) << 48 | UInt64(bytes[i + 7]) << 56
    }
}

// MARK: - Dictionary builder convenience

extension OPACK.Value {
    /// Build an OPACK dict from Swift-friendly key-value pairs.
    static func dictionary(_ pairs: [(String, OPACK.Value)]) -> OPACK.Value {
        .dict(pairs.map { (key: .string($0.0), value: $0.1) })
    }
}
