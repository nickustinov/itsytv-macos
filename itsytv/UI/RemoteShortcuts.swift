import SwiftUI
import ItsytvCore

extension RemoteShortcut {
    /// The Apple TV button a plain key presses; nil for app-level actions.
    var companionButton: CompanionButton? {
        switch self {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .select: .select
        case .back: .menu
        case .home: .home
        case .playPause: .playPause
        case .volumeUp: .volumeUp
        case .volumeDown: .volumeDown
        case .mute, .keyboard, .appSearch, .close: nil
        }
    }
}

// MARK: - Hints on the remote

/// Small key label drawn on top of a remote control.
struct ShortcutBadge: View {
    let shortcut: RemoteShortcut
    var isActive = false

    var body: some View {
        Text(shortcut.label)
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(Color.accentColor.opacity(isActive ? 1 : 0.85)))
            .fixedSize()
            .allowsHitTesting(false)
    }
}

private struct ShortcutHintModifier: ViewModifier {
    let shortcut: RemoteShortcut
    let alignment: Alignment
    let offset: CGSize
    @AppStorage("showShortcutHints") private var showHints = false

    func body(content: Content) -> some View {
        content.overlay(alignment: alignment) {
            if showHints {
                ShortcutBadge(shortcut: shortcut).offset(offset)
            }
        }
    }
}

extension View {
    /// Shows the shortcut's key label over this control while "Show shortcut hints" is on.
    func shortcutHint(_ shortcut: RemoteShortcut, alignment: Alignment = .center, offset: CGSize = .zero) -> some View {
        modifier(ShortcutHintModifier(shortcut: shortcut, alignment: alignment, offset: offset))
    }
}
