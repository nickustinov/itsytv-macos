import Foundation

/// Writes NSKeyedArchiver-compatible binary plists with proper UID objects.
///
/// `PropertyListSerialization` cannot write native binary plist UIDs — it writes
/// `["CF$UID": N]` as regular dictionaries. This encoder handles the full binary
/// plist format with real UID objects (type marker `0x80`).
enum BinaryPlist {

    /// Serialize an NSKeyedArchiver archive with proper UIDs.
    ///
    /// - Parameters:
    ///   - archiver: The `$archiver` string (e.g. "RTIKeyedArchiver")
    ///   - top: The `$top` dictionary with UID references as `uid(N)` tuples
    ///   - objects: The `$objects` array
    static func writeArchive(archiver: String, top: [(String, Obj)], objects: [Obj]) -> Data {
        var writer = Writer()

        // Encode all $objects entries first to get their indices
        var objectIndices: [Int] = []
        for obj in objects {
            objectIndices.append(writer.add(obj))
        }

        // Build $objects array object
        let objectsArrayIdx = writer.addArray(objectIndices)

        // Build $top dict
        var topKeyIndices: [Int] = []
        var topValIndices: [Int] = []
        for (key, val) in top {
            topKeyIndices.append(writer.add(.string(key)))
            topValIndices.append(writer.add(val))
        }
        let topDictIdx = writer.addDict(keys: topKeyIndices, values: topValIndices)

        // Build root archive dict
        let archiverKeyIdx = writer.add(.string("$archiver"))
        let archiverValIdx = writer.add(.string(archiver))
        let objectsKeyIdx = writer.add(.string("$objects"))
        let topKeyIdx = writer.add(.string("$top"))
        let topValIdx = topDictIdx
        let versionKeyIdx = writer.add(.string("$version"))
        let versionValIdx = writer.add(.int(100000))

        let rootIdx = writer.addDict(
            keys: [archiverKeyIdx, objectsKeyIdx, topKeyIdx, versionKeyIdx],
            values: [archiverValIdx, objectsArrayIdx, topValIdx, versionValIdx]
        )

        return writer.finalize(rootIndex: rootIdx)
    }

    /// A plist object for the archive.
    enum Obj {
        case string(String)
        case int(Int)
        case data(Data)
        case uid(Int)
        case dict([(String, Obj)])
        case array([String])
    }

    /// Internal binary plist writer.
    private struct Writer {
        private var objects: [(encoded: Data, refs: Refs)] = []

        enum Refs {
            case none
            case array([Int])
            case dict(keys: [Int], values: [Int])
        }

        mutating func add(_ obj: Obj) -> Int {
            let idx = objects.count
            switch obj {
            case .string(let s):
                objects.append((encodeString(s), .none))
            case .int(let n):
                objects.append((encodeInt(n), .none))
            case .data(let d):
                objects.append((encodeData(d), .none))
            case .uid(let n):
                objects.append((encodeUID(n), .none))
            case .dict(let pairs):
                // Recursively add keys and values
                var keyIndices: [Int] = []
                var valIndices: [Int] = []
                // Reserve our slot
                let dictIdx = objects.count
                objects.append((Data(), .none)) // placeholder
                for (key, val) in pairs {
                    keyIndices.append(add(.string(key)))
                    valIndices.append(add(val))
                }
                objects[dictIdx] = (Data(), .dict(keys: keyIndices, values: valIndices))
                return dictIdx
            case .array(let items):
                let arrIdx = objects.count
                objects.append((Data(), .none))
                var itemIndices: [Int] = []
                for item in items {
                    itemIndices.append(add(.string(item)))
                }
                objects[arrIdx] = (Data(), .array(itemIndices))
                return arrIdx
            }
            return idx
        }

        mutating func addArray(_ indices: [Int]) -> Int {
            let idx = objects.count
            objects.append((Data(), .array(indices)))
            return idx
        }

        mutating func addDict(keys: [Int], values: [Int]) -> Int {
            let idx = objects.count
            objects.append((Data(), .dict(keys: keys, values: values)))
            return idx
        }

        func finalize(rootIndex: Int) -> Data {
            let numObjects = objects.count
            let objectRefSize = byteSize(for: max(numObjects - 1, 1))

            // Encode all objects with correct ref sizes
            var body = Data("bplist00".utf8)
            var offsets: [Int] = []

            for i in 0..<numObjects {
                offsets.append(body.count)
                let (encoded, refs) = objects[i]
                switch refs {
                case .none:
                    body.append(encoded)
                case .array(let indices):
                    body.append(encodeArrayHeader(count: indices.count))
                    for idx in indices {
                        body.append(packBE(idx, size: objectRefSize))
                    }
                case .dict(let keys, let values):
                    body.append(encodeDictHeader(count: keys.count))
                    for idx in keys {
                        body.append(packBE(idx, size: objectRefSize))
                    }
                    for idx in values {
                        body.append(packBE(idx, size: objectRefSize))
                    }
                }
            }

            // Offset table
            let offsetTableOffset = body.count
            let offsetSize = byteSize(for: offsetTableOffset)
            for offset in offsets {
                body.append(packBE(offset, size: offsetSize))
            }

            // Trailer (32 bytes)
            body.append(Data(count: 6)) // unused
            body.append(UInt8(offsetSize))
            body.append(UInt8(objectRefSize))
            body.append(packBE(numObjects, size: 8))
            body.append(packBE(rootIndex, size: 8))
            body.append(packBE(offsetTableOffset, size: 8))

            return body
        }
    }

    // MARK: - Object encoders

    private static func encodeString(_ s: String) -> Data {
        let utf8 = Array(s.utf8)
        var result = Data()
        if utf8.count < 15 {
            result.append(0x50 | UInt8(utf8.count))
        } else {
            result.append(0x5F)
            result.append(contentsOf: encodeInt(utf8.count))
        }
        result.append(contentsOf: utf8)
        return result
    }

    private static func encodeInt(_ n: Int) -> Data {
        if n >= 0 && n <= 0xFF {
            return Data([0x10, UInt8(n)])
        } else if n >= 0 && n <= 0xFFFF {
            return Data([0x11]) + packBE(n, size: 2)
        } else if n >= 0 && n <= 0xFFFFFFFF {
            return Data([0x12]) + packBE(n, size: 4)
        }
        return Data([0x13]) + packBE(n, size: 8)
    }

    private static func encodeUID(_ n: Int) -> Data {
        let size = byteSize(for: max(n, 1))
        return Data([0x80 | UInt8(size - 1)]) + packBE(n, size: size)
    }

    private static func encodeData(_ d: Data) -> Data {
        var result = Data()
        if d.count < 15 {
            result.append(0x40 | UInt8(d.count))
        } else {
            result.append(0x4F)
            result.append(contentsOf: encodeInt(d.count))
        }
        result.append(d)
        return result
    }

    private static func encodeArrayHeader(count: Int) -> Data {
        if count < 15 {
            return Data([0xA0 | UInt8(count)])
        }
        var result = Data([0xAF])
        result.append(contentsOf: encodeInt(count))
        return result
    }

    private static func encodeDictHeader(count: Int) -> Data {
        if count < 15 {
            return Data([0xD0 | UInt8(count)])
        }
        var result = Data([0xDF])
        result.append(contentsOf: encodeInt(count))
        return result
    }

    // MARK: - Utilities

    private static func byteSize(for value: Int) -> Int {
        if value <= 0xFF { return 1 }
        if value <= 0xFFFF { return 2 }
        if value <= 0xFFFFFFFF { return 4 }
        return 8
    }

    private static func packBE(_ value: Int, size: Int) -> Data {
        var data = Data(count: size)
        for i in 0..<size {
            data[size - 1 - i] = UInt8((value >> (i * 8)) & 0xFF)
        }
        return data
    }
}
