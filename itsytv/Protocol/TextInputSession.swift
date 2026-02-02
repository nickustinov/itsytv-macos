import Foundation
import os.log

private let log = Logger(subsystem: "com.itsytv.app", category: "TextInput")

/// Encodes and decodes the binary plist payloads used by the RTI text input protocol.
///
/// The Apple TV companion protocol uses `_tiStart`/`_tiC`/`_tiStop` events for text input.
/// The `_tiD` field carries an NSKeyedArchiver-compatible binary plist with private RTI classes.
/// We build these plists manually using `PropertyListSerialization`.
enum TextInputSession {

    enum Error: Swift.Error {
        case invalidResponse
        case missingSessionUUID
        case plistSerializationFailed
    }

    // MARK: - Encode

    /// Build a binary plist payload that inserts text into the current text field.
    static func encodeInsertText(_ text: String, sessionUUID: Data) -> Data {
        typealias O = BinaryPlist.Obj
        let objects: [O] = [
            .string("$null"),
            // [1] RTITextOperations
            .dict([
                ("keyboardOutput", .uid(2)),
                ("$class", .uid(7)),
                ("targetSessionUUID", .uid(5)),
            ]),
            // [2] TIKeyboardOutput
            .dict([
                ("insertionText", .uid(3)),
                ("$class", .uid(4)),
            ]),
            // [3] the text string
            .string(text),
            // [4] TIKeyboardOutput class def
            .dict([
                ("$classname", .string("TIKeyboardOutput")),
                ("$classes", .array(["TIKeyboardOutput", "NSObject"])),
            ]),
            // [5] NSUUID
            .dict([
                ("NS.uuidbytes", .data(sessionUUID)),
                ("$class", .uid(6)),
            ]),
            // [6] NSUUID class def
            .dict([
                ("$classname", .string("NSUUID")),
                ("$classes", .array(["NSUUID", "NSObject"])),
            ]),
            // [7] RTITextOperations class def
            .dict([
                ("$classname", .string("RTITextOperations")),
                ("$classes", .array(["RTITextOperations", "NSObject"])),
            ]),
        ]
        return BinaryPlist.writeArchive(
            archiver: "RTIKeyedArchiver",
            top: [("textOperations", .uid(1))],
            objects: objects
        )
    }

    /// Build a binary plist payload that atomically clears and replaces the text field.
    ///
    /// Combines `textToAssert: ""` (clear) and `insertionText` (re-type) in a single
    /// `RTITextOperations` so the Apple TV processes both in one event without flashing.
    static func encodeReplaceText(_ text: String, sessionUUID: Data) -> Data {
        typealias O = BinaryPlist.Obj
        let objects: [O] = [
            .string("$null"),
            // [1] RTITextOperations
            .dict([
                ("$class", .uid(8)),
                ("targetSessionUUID", .uid(6)),
                ("keyboardOutput", .uid(2)),
                ("textToAssert", .uid(4)),
            ]),
            // [2] TIKeyboardOutput with insertionText
            .dict([
                ("insertionText", .uid(3)),
                ("$class", .uid(5)),
            ]),
            // [3] the replacement text
            .string(text),
            // [4] empty string for textToAssert (clear)
            .string(""),
            // [5] TIKeyboardOutput class def
            .dict([
                ("$classname", .string("TIKeyboardOutput")),
                ("$classes", .array(["TIKeyboardOutput", "NSObject"])),
            ]),
            // [6] NSUUID
            .dict([
                ("NS.uuidbytes", .data(sessionUUID)),
                ("$class", .uid(7)),
            ]),
            // [7] NSUUID class def
            .dict([
                ("$classname", .string("NSUUID")),
                ("$classes", .array(["NSUUID", "NSObject"])),
            ]),
            // [8] RTITextOperations class def
            .dict([
                ("$classname", .string("RTITextOperations")),
                ("$classes", .array(["RTITextOperations", "NSObject"])),
            ]),
        ]
        return BinaryPlist.writeArchive(
            archiver: "RTIKeyedArchiver",
            top: [("textOperations", .uid(1))],
            objects: objects
        )
    }

    // MARK: - Decode

    /// Decode the `_tiD` response from `_tiStart`, extracting the session UUID and current text.
    ///
    /// The response `$top` contains `sessionUUID` (UID ref to raw Data in `$objects`),
    /// plus `documentState` and `documentTraits`.
    static func decodeStartResponse(_ data: Data) throws -> (sessionUUID: Data, currentText: String) {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw Error.invalidResponse
        }
        guard let objects = plist["$objects"] as? [Any],
              let top = plist["$top"] as? [String: Any] else {
            throw Error.invalidResponse
        }

        // Extract sessionUUID from $top
        guard let uuidIdx = uidValue(top["sessionUUID"]),
              uuidIdx < objects.count else {
            throw Error.missingSessionUUID
        }

        // The sessionUUID object is either raw Data or an NSUUID dict with NS.uuidbytes
        let sessionUUID: Data
        if let rawBytes = objects[uuidIdx] as? Data {
            sessionUUID = rawBytes
        } else if let uuidObj = objects[uuidIdx] as? [String: Any],
                  let bytes = uuidObj["NS.uuidbytes"] as? Data {
            sessionUUID = bytes
        } else {
            throw Error.missingSessionUUID
        }

        // Extract current text from documentState if present
        var currentText = ""
        if let docStateIdx = uidValue(top["documentState"]),
           docStateIdx < objects.count,
           let docState = objects[docStateIdx] as? [String: Any],
           let docStIdx = uidValue(docState["docSt"]),
           docStIdx < objects.count,
           let innerState = objects[docStIdx] as? [String: Any] {
            // Look for contextBeforeInput in the TIDocumentState
            if let textIdx = uidValue(innerState["contextBeforeInput"]),
               textIdx < objects.count,
               let text = objects[textIdx] as? String {
                currentText = text
            }
        }

        return (sessionUUID: sessionUUID, currentText: currentText)
    }

    /// Extract the integer value from a UID reference. Handles both:
    /// - `["CF$UID": Int]` dictionaries (our own test fixtures)
    /// - `CFKeyedArchiverUID` objects (from PropertyListSerialization reading binary plists)
    ///
    /// `CFKeyedArchiverUID` is a private class that isn't KVC-compliant, so we parse
    /// its description string: `<CFKeyedArchiverUID 0x...>{value = N}`
    static func uidValue(_ obj: Any?) -> Int? {
        guard let obj else { return nil }
        // Dictionary form (test fixtures)
        if let dict = obj as? [String: Any], let val = dict["CF$UID"] as? Int {
            return val
        }
        // CFKeyedArchiverUID — parse from description
        let desc = String(describing: obj)
        guard desc.contains("CFKeyedArchiverUID"),
              let range = desc.range(of: "value = "),
              let endRange = desc[range.upperBound...].firstIndex(of: "}") else {
            return nil
        }
        return Int(desc[range.upperBound..<endRange].trimmingCharacters(in: .whitespaces))
    }

    // MARK: - Helpers

    /// Create a CF$UID reference dictionary for use in test fixtures.
    static func uid(_ index: Int) -> NSDictionary {
        ["CF$UID": index] as NSDictionary
    }
}
