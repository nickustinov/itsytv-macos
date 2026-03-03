import SwiftUI

/// An `NSTextField` wrapper that correctly handles IME composition (Korean, Japanese, Chinese, etc.).
///
/// During active IME composition the field editor holds a "marked" (underlined) range that represents
/// in-progress input. This view reports only the **committed** portion of the text – everything
/// outside that marked range – so callers never see intermediate composition states.
struct ComposeAwareTextField: NSViewRepresentable {
    @Binding var text: String
    var onCommittedTextChange: (String) -> Void
    var onSubmit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.stringValue = text
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        field.cell?.lineBreakMode = .byTruncatingTail
        field.delegate = context.coordinator
        // Auto-focus on appear
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            field.window?.makeFirstResponder(field)
        }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        // Only update if the field is not currently being edited (avoid fighting the user)
        guard nsView.currentEditor() == nil else { return }
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: ComposeAwareTextField

        init(_ parent: ComposeAwareTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            let fullText = field.stringValue
            parent.text = fullText

            // Extract committed text by excluding the marked (composing) range
            let committed: String
            if let editor = field.currentEditor() as? NSTextView,
               let markedRange = editor.markedRange().toRange(in: fullText) {
                var result = fullText
                result.removeSubrange(markedRange)
                committed = result
            } else {
                committed = fullText
            }

            parent.onCommittedTextChange(committed)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            return false
        }
    }
}

private extension NSRange {
    /// Convert an `NSRange` to a `Range<String.Index>` within the given string, returning `nil`
    /// if the range is not found or represents no marked text.
    func toRange(in string: String) -> Range<String.Index>? {
        guard location != NSNotFound, length > 0 else { return nil }
        guard let start = string.utf16.index(string.utf16.startIndex, offsetBy: location, limitedBy: string.utf16.endIndex),
              let end = string.utf16.index(start, offsetBy: length, limitedBy: string.utf16.endIndex) else {
            return nil
        }
        return start..<end
    }
}
