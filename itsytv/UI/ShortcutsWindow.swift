import SwiftUI

/// "Keyboard shortcuts…" window: a copy of the remote with every key labelled,
/// plus the full list. Pressing a shortcut or clicking a control lights it up;
/// nothing is sent to the Apple TV.
enum ShortcutsWindow {
    private static var window: NSWindow?

    static func show(beside anchor: NSWindow?) {
        let window = self.window ?? makeWindow()
        self.window = window
        if !window.isVisible { position(window, beside: anchor) }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private static func makeWindow() -> NSWindow {
        let hostingView = NSHostingView(rootView: ShortcutsSheetView())
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Keyboard shortcuts"
        window.contentView = hostingView
        window.setContentSize(hostingView.fittingSize)
        window.isReleasedWhenClosed = false
        // The remote panel floats at status-bar level; stay visible next to it.
        window.level = .statusBar
        return window
    }

    private static func position(_ window: NSWindow, beside anchor: NSWindow?) {
        guard let anchor, let screen = anchor.screen ?? NSScreen.main else {
            window.center()
            return
        }
        let gap: CGFloat = 12
        let size = window.frame.size
        let visible = screen.visibleFrame
        var x = anchor.frame.minX - gap - size.width
        if x < visible.minX { x = anchor.frame.maxX + gap }
        x = min(max(x, visible.minX), visible.maxX - size.width)
        let y = min(max(anchor.frame.maxY - size.height, visible.minY), visible.maxY - size.height)
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

struct ShortcutsSheetView: View {
    @State private var active: RemoteShortcut?
    @State private var flashID = 0
    private var settings: ShortcutSettings { .shared }

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            ShortcutsRemotePreview(active: active, onPress: flash)

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Try it")
                        .font(.headline)
                    Text("Press a shortcut or click a button – nothing is sent to your Apple TV. Click the keys in a row to change them.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(RemoteShortcut.groups, id: \.title) { group in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.title.uppercased())
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 8)
                            .padding(.bottom, 2)
                        ForEach(group.items) { shortcut in
                            ShortcutRow(shortcut: shortcut, isActive: active == shortcut, onTap: { flash(shortcut) })
                        }
                    }
                }

                Text("Shortcuts work while the remote is the active window. Hold esc to go Home, hold ⌫ for Control Center, hold ↩ for the context menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Always laid out (just disabled) so the window never has to resize.
                Button("Restore default shortcuts") {
                    settings.recording = nil
                    settings.resetAll()
                }
                .controlSize(.small)
                .disabled(!settings.hasCustomizations)
            }
            .frame(width: 290)
        }
        .padding(20)
        .background(ShortcutKeyCatcher(onShortcut: flash, onRecord: record))
        .onDisappear { settings.recording = nil }
    }

    private func record(_ keys: ShortcutKeys) {
        guard let shortcut = settings.recording else { return }
        settings.recording = nil
        settings.set(keys, for: shortcut)
        flash(shortcut)
    }

    private func flash(_ shortcut: RemoteShortcut) {
        active = shortcut
        flashID &+= 1
        let id = flashID
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard id == flashID else { return }
            withAnimation(.easeOut(duration: 0.25)) { active = nil }
        }
    }
}

private struct ShortcutRow: View {
    let shortcut: RemoteShortcut
    let isActive: Bool
    let onTap: () -> Void
    private var settings: ShortcutSettings { .shared }

    private var isRecording: Bool { settings.recording == shortcut }

    var body: some View {
        HStack(spacing: 10) {
            Text(shortcut.title)
                .font(.system(size: 13))
            Spacer(minLength: 8)
            Group {
                if isRecording {
                    Text("Type new keys…")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(Color.accentColor, lineWidth: 1)
                        )
                } else {
                    HStack(spacing: 3) {
                        ForEach(Array(shortcut.keyCaps.enumerated()), id: \.offset) { _, cap in
                            KeyCap(text: cap, isActive: isActive)
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { settings.recording = isRecording ? nil : shortcut }
            .help(isRecording ? "Click to cancel" : "Click to change")

            // Fixed slot keeps the key caps aligned whether or not a row is customized.
            Button {
                settings.reset(shortcut)
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Restore default (\(ShortcutKeys.caps(shortcut.defaultKeys).joined()))")
            .opacity(settings.isCustomized(shortcut) ? 1 : 0)
            .disabled(!settings.isCustomized(shortcut))
            .frame(width: 14)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(isActive ? 0.22 : 0))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

private struct KeyCap: View {
    let text: String
    let isActive: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(isActive ? Color.white : Color.primary)
            .frame(minWidth: 20)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isActive ? Color.accentColor : Color.secondary.opacity(0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.secondary.opacity(isActive ? 0 : 0.25), lineWidth: 0.5)
            )
    }
}

// MARK: - Remote copy

/// Same layout and sizes as `RemoteTabContent`, but inert: clicks only light up.
private struct ShortcutsRemotePreview: View {
    let active: RemoteShortcut?
    let onPress: (RemoteShortcut) -> Void

    private let dpadSize: CGFloat = 150
    private let buttonSize: CGFloat = 60
    private let gap: CGFloat = 12

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Image(systemName: "keyboard")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(lit(.keyboard) ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.12)))
                    .overlay(alignment: .leading) { badge(.keyboard).offset(x: 28) }
                    .contentShape(Circle())
                    .onTapGesture { onPress(.keyboard) }
                Spacer()
            }
            .padding(.horizontal, 16)

            dpad

            VStack(spacing: gap) {
                HStack(spacing: gap) {
                    circle("btnBack", .back)
                    circle("btnHome", .home)
                }
                HStack(alignment: .top, spacing: gap) {
                    VStack(spacing: gap) {
                        circle("btnPlayPause", .playPause)
                        circle("btnMute", .mute)
                    }
                    volumePill
                }
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .frame(width: 176)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Color(nsColor: .underPageBackgroundColor))
        )
    }

    private var dpad: some View {
        ZStack {
            Circle()
                .fill(Color(nsColor: DS.Colors.remoteButton))
                .frame(width: dpadSize, height: dpadSize)
            Circle()
                .fill(lit(.select) ? Color.accentColor.opacity(0.5) : Color(nsColor: DS.Colors.remoteButtonForeground).opacity(0.08))
                .frame(width: dpadSize * 0.5, height: dpadSize * 0.5)
                .overlay(badge(.select))
                .contentShape(Circle())
                .onTapGesture { onPress(.select) }
            VStack {
                arrow(.up)
                Spacer()
                arrow(.down)
            }
            .frame(height: dpadSize)
            .padding(.vertical, 12)
            HStack {
                arrow(.left)
                Spacer()
                arrow(.right)
            }
            .frame(width: dpadSize)
            .padding(.horizontal, 12)
        }
    }

    private func arrow(_ shortcut: RemoteShortcut) -> some View {
        badge(shortcut)
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
            .onTapGesture { onPress(shortcut) }
    }

    private func circle(_ image: String, _ shortcut: RemoteShortcut) -> some View {
        Image(image)
            .resizable()
            .scaledToFit()
            .frame(width: buttonSize * 0.33, height: buttonSize * 0.33)
            .frame(width: buttonSize, height: buttonSize)
            .background(Circle().fill(Color(nsColor: DS.Colors.remoteButton)))
            .overlay(Circle().fill(Color.accentColor.opacity(lit(shortcut) ? 0.45 : 0)))
            .overlay(alignment: .bottom) { badge(shortcut).offset(y: -7) }
            .contentShape(Circle())
            .onTapGesture { onPress(shortcut) }
    }

    private var volumePill: some View {
        VStack(spacing: 0) {
            pillHalf("plus", .volumeUp, alignment: .top, badgeOffset: 7)
            pillHalf("minus", .volumeDown, alignment: .bottom, badgeOffset: -7)
        }
        .frame(width: buttonSize, height: buttonSize * 2 + gap)
        .background(Capsule().fill(Color(nsColor: DS.Colors.remoteButton)))
        .clipShape(Capsule())
    }

    private func pillHalf(_ symbol: String, _ shortcut: RemoteShortcut, alignment: Alignment, badgeOffset: CGFloat) -> some View {
        Image(systemName: symbol)
            .font(.system(size: buttonSize * 0.3, weight: .medium))
            .foregroundStyle(Color(nsColor: DS.Colors.remoteButtonForeground))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.accentColor.opacity(lit(shortcut) ? 0.45 : 0))
            .overlay(alignment: alignment) { badge(shortcut).offset(y: badgeOffset) }
            .contentShape(Rectangle())
            .onTapGesture { onPress(shortcut) }
    }

    private func badge(_ shortcut: RemoteShortcut) -> some View {
        ShortcutBadge(shortcut: shortcut, isActive: lit(shortcut))
            .scaleEffect(lit(shortcut) ? 1.25 : 1)
            .animation(.spring(duration: 0.2), value: lit(shortcut))
    }

    private func lit(_ shortcut: RemoteShortcut) -> Bool { active == shortcut }
}

// MARK: - Key capture

/// Catches remote shortcuts typed into this window so they light up instead of
/// beeping. Only events addressed to this window are touched.
private struct ShortcutKeyCatcher: NSViewRepresentable {
    let onShortcut: (RemoteShortcut) -> Void
    let onRecord: (ShortcutKeys) -> Void

    func makeNSView(context: Context) -> KeyCatcherView {
        let view = KeyCatcherView()
        view.onShortcut = onShortcut
        view.onRecord = onRecord
        return view
    }

    func updateNSView(_ nsView: KeyCatcherView, context: Context) {
        nsView.onShortcut = onShortcut
        nsView.onRecord = onRecord
    }
}

private final class KeyCatcherView: NSView {
    var onShortcut: ((RemoteShortcut) -> Void)?
    var onRecord: ((ShortcutKeys) -> Void)?
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            // While a row is recording, a key (with or without modifiers) becomes its new shortcut.
            if ShortcutSettings.shared.recording != nil {
                switch ShortcutRecording(ShortcutKeys(event: event)) {
                case .cancel:
                    ShortcutSettings.shared.recording = nil
                    return nil
                case .passThrough:
                    return event
                case .record(let keys):
                    if !event.isARepeat { self.onRecord?(keys) }
                    return nil
                }
            }
            guard let shortcut = RemoteShortcut.match(event) else { return event }
            self.onShortcut?(shortcut)
            return nil
        }
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}
