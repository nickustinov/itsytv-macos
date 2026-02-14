import SwiftUI

enum RemoteTab: String, CaseIterable {
    case remote = "Remote"
    case apps = "Apps"
}

struct RemoteControlView: View {
    @Environment(AppleTVManager.self) private var manager
    @State private var selectedTab: RemoteTab = .remote

    private var isConnected: Bool {
        manager.connectionStatus == .connected
    }

    var body: some View {
        VStack(spacing: 10) {
            // Header — always interactive
            HStack(spacing: 8) {
                Text(manager.connectedDeviceName ?? "Apple TV")
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer()
                PanelMenuButton(deviceID: manager.connectedDeviceID ?? "") {
                    if let deviceID = manager.connectedDeviceID {
                        KeychainStorage.delete(for: deviceID)
                    }
                    manager.disconnect()
                }
                PanelCloseButton { manager.disconnect() }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            // Controls — dimmed while connecting
            VStack(spacing: 10) {
                // Tab picker
                CapsuleSegmentPicker(
                    selection: $selectedTab,
                    options: RemoteTab.allCases.map { ($0, $0.rawValue) }
                )
                .padding(.horizontal, 8)

                // Content — remote is always rendered to maintain size
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        // Remote always rendered (hidden when on apps to keep size)
                        VStack(spacing: 10) {
                            RemoteTabContent()
                            NowPlayingBar()
                        }
                        .opacity(selectedTab == .remote ? 1 : 0)
                        .allowsHitTesting(selectedTab == .remote)

                        // Apps overlaid on top when selected
                        if selectedTab == .apps {
                            AppGridView()
                                .transition(.identity)
                        }
                    }
                    .animation(nil, value: selectedTab)

                    // Power button (Control Center) — floats over content
                    if selectedTab == .remote {
                        Button { manager.pressButton(.pageDown) } label: {
                            Image(systemName: "power")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(Color.secondary.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 24)
                    }
                }
            }
            .opacity(isConnected ? 1 : 0.4)
            .allowsHitTesting(isConnected)
        }
    }
}

struct NowPlayingBar: View {
    @Environment(AppleTVManager.self) private var manager

    var body: some View {
        let mrp = manager.mrpManager
        let np = mrp.nowPlaying
        let hasContent = np != nil

        VStack(spacing: 6) {
            // Artwork — full width, square
            if let data = np?.artworkData, let image = NSImage(data: data) {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 160)
                    .overlay {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                    .clipped()
                    .cornerRadius(6)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 160)
            }

            // Title + artist
            VStack(spacing: 2) {
                Text(np?.title ?? " ")
                    .font(.subheadline.bold())
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(np.flatMap { [$0.artist, $0.album].compactMap { $0 }.joined(separator: " — ") } ?? " ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .opacity(hasContent ? 1 : 0)

            // Controls — use HID button presses (not MRP commands) for play/pause
            // because apps like YouTube ignore MRP SendCommandMessage.
            HStack(spacing: 28) {
                Button {
                    mrp.sendCommand(.previousTrack)
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
                .disabled(!hasContent || !mrp.supportedCommands.contains(.previousTrack))

                Button {
                    manager.pressButton(.playPause)
                } label: {
                    Image(systemName: np?.isPlaying == true ? "pause.fill" : "play.fill")
                        .font(.system(size: 22))
                }
                .buttonStyle(.plain)
                .disabled(!hasContent)

                Button {
                    mrp.sendCommand(.nextTrack)
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
                .disabled(!hasContent || !mrp.supportedCommands.contains(.nextTrack))
            }
            .foregroundStyle(.secondary)

            // Progress bar
            NowPlayingProgress(
                nowPlaying: np,
                duration: np?.duration ?? 0,
                onSeek: { position in mrp.seekToPosition(position) }
            )
            .opacity(hasContent && (np?.duration ?? 0) > 0 ? 1 : 0.3)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
}

struct NowPlayingProgress: View {
    let nowPlaying: NowPlayingState?
    let duration: TimeInterval
    var onSeek: ((Double) -> Void)?

    @State private var currentTime: TimeInterval = 0
    @State private var isSeeking = false
    @State private var seekTime: TimeInterval = 0
    /// After seeking, hold the seeked position until the server catches up.
    @State private var pendingSeekTarget: TimeInterval?
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var displayTime: TimeInterval {
        if isSeeking { return seekTime }
        if let target = pendingSeekTarget { return target }
        return currentTime
    }

    private var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, displayTime / duration)
    }

    var body: some View {
        VStack(spacing: 2) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(.quaternary)
                        .frame(height: 3)

                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(.secondary)
                        .frame(width: max(0, geo.size.width * progress), height: 3)
                }
                .frame(height: 12)
                .contentShape(Rectangle())
                .background(WindowDragBlocker())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard duration > 0 else { return }
                            isSeeking = true
                            let fraction = max(0, min(1, value.location.x / geo.size.width))
                            seekTime = fraction * duration
                        }
                        .onEnded { value in
                            guard duration > 0 else { return }
                            let fraction = max(0, min(1, value.location.x / geo.size.width))
                            let position = fraction * duration
                            onSeek?(position)
                            currentTime = position
                            pendingSeekTarget = position
                            isSeeking = false
                        }
                )
            }
            .frame(height: 12)

            HStack {
                Text(formatTime(displayTime))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(formatTime(duration))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .onAppear { currentTime = nowPlaying?.currentPosition ?? 0 }
        .onReceive(timer) { _ in
            if !isSeeking {
                let serverTime = nowPlaying?.currentPosition ?? 0
                if let target = pendingSeekTarget {
                    // Clear hold once the server reports a position near the seek target
                    if abs(serverTime - target) < 3 {
                        pendingSeekTarget = nil
                        currentTime = serverTime
                    }
                } else {
                    currentTime = serverTime
                }
            }
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

struct RemoteTabContent: View {
    @Environment(AppleTVManager.self) private var manager
    @State private var showingKeyboard = false
    @State private var keyboardText = ""
    @FocusState private var isKeyboardFocused: Bool

    private let padding: CGFloat = 8
    private let buttonSize: CGFloat = 60
    private let buttonGap: CGFloat = 12

    var body: some View {
        let dpadSize: CGFloat = 150

        VStack(spacing: 4) {
            // D-pad
            DPadView(onPress: { button, action in manager.pressButton(button, action: action) }, size: dpadSize)
                .padding(.top, 15)

            // Buttons matching Apple TV remote layout
            VStack(spacing: buttonGap) {
                // Row 1: Back + TV/Home
                HStack(spacing: buttonGap) {
                    RemoteCircleButton(imageName: "btnBack", button: .menu, shortcut: "Esc", size: buttonSize) { action in
                        manager.pressButton(.menu, action: action)
                    }
                    RemoteCircleButton(imageName: "btnHome", button: .home, shortcut: "⌫", size: buttonSize) { action in
                        manager.pressButton(.home, action: action)
                    }
                }

                // Rows 2-3: Play/Pause + Keyboard left, Volume pill right
                HStack(alignment: .top, spacing: buttonGap) {
                    VStack(spacing: buttonGap) {
                        RemoteCircleButton(imageName: "btnPlayPause", button: .playPause, shortcut: "Space", size: buttonSize) { action in
                            manager.pressButton(.playPause, action: action)
                        }
                        RemoteCircleButton(imageName: "btnKeyboard", button: .siri, shortcut: "⌘K", size: buttonSize) { action in
                            guard action == .click else { return }
                            showingKeyboard.toggle()
                            if !showingKeyboard {
                                keyboardText = ""
                                manager.resetTextInputState()
                            }
                        }
                    }

                    VolumePill(
                        width: buttonSize,
                        height: buttonSize * 2 + buttonGap,
                        onUp: { manager.pressButton(.volumeUp) },
                        onDown: { manager.pressButton(.volumeDown) }
                    )
                }
            }

            if showingKeyboard {
                TextField("", text: $keyboardText)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Capsule().fill(Color(nsColor: DS.Colors.muted)))
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                    .focused($isKeyboardFocused)
                    .onAppear {
                        NSApp.activate(ignoringOtherApps: true)
                        DispatchQueue.main.async { isKeyboardFocused = true }
                    }
                    .onChange(of: keyboardText) { _, newValue in
                        manager.updateRemoteText(newValue)
                    }
                    .onSubmit {
                        keyboardText = ""
                        showingKeyboard = false
                        manager.resetTextInputState()
                    }
            }
        }
        .padding(.horizontal, padding)
        .padding(.bottom, 12)
        .onChange(of: manager.keyboardToggleCounter) { _, _ in
            showingKeyboard.toggle()
            if !showingKeyboard {
                keyboardText = ""
                manager.resetTextInputState()
            }
        }
    }
}


struct AppGridView: View {
    @Environment(AppleTVManager.self) private var manager
    @Environment(AppIconLoader.self) private var iconLoader
    @State private var apps: [(bundleID: String, name: String)] = []
    @State private var draggingBundleID: String?

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        if manager.installedApps.isEmpty {
            VStack(spacing: 8) {
                ProgressView()
                Text("Loading apps...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(apps, id: \.bundleID) { app in
                        appView(for: app)
                            .opacity(draggingBundleID == app.bundleID ? 0.5 : 1)
                            .onDrag {
                                draggingBundleID = app.bundleID
                                return NSItemProvider(object: app.bundleID as NSString)
                            }
                            .onDrop(
                                of: [.text],
                                delegate: AppReorderDropDelegate(
                                    targetBundleID: app.bundleID,
                                    apps: $apps,
                                    draggingBundleID: $draggingBundleID,
                                    onReorder: { manager.saveAppOrder($0.map(\.bundleID)) }
                                )
                            )
                            .background(WindowDragBlocker())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
            .onAppear {
                apps = manager.orderedApps
                iconLoader.loadIcons(for: manager.installedApps.map(\.bundleID))
            }
            .onChange(of: manager.installedApps.map(\.bundleID)) {
                apps = manager.orderedApps
                iconLoader.loadIcons(for: manager.installedApps.map(\.bundleID))
            }
        }
    }

    @ViewBuilder
    private func appView(for app: (bundleID: String, name: String)) -> some View {
        if let symbolName = AppIconLoader.builtInSymbols[app.bundleID] {
            AppleAppButton(name: app.name, symbolName: symbolName) {
                manager.launchApp(bundleID: app.bundleID)
            }
        } else {
            AppButton(name: app.name, icon: iconLoader.icons[app.bundleID]) {
                manager.launchApp(bundleID: app.bundleID)
            }
        }
    }
}

private struct AppReorderDropDelegate: DropDelegate {
    let targetBundleID: String
    @Binding var apps: [(bundleID: String, name: String)]
    @Binding var draggingBundleID: String?
    let onReorder: ([(bundleID: String, name: String)]) -> Void

    func dropEntered(info: DropInfo) {
        guard let dragging = draggingBundleID,
              dragging != targetBundleID,
              let fromIndex = apps.firstIndex(where: { $0.bundleID == dragging }),
              let toIndex = apps.firstIndex(where: { $0.bundleID == targetBundleID }) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            apps.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        onReorder(apps)
        draggingBundleID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {}
}

struct AppButton: View {
    let name: String
    let icon: NSImage?
    let action: () -> Void

    private let iconHeight: CGFloat = 42
    private let cornerRadius: CGFloat = 10

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                if let icon {
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: iconHeight)
                        .overlay {
                            Image(nsImage: icon)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.quaternary)
                        .frame(maxWidth: .infinity)
                        .frame(height: iconHeight)
                        .overlay {
                            Image(systemName: "app.fill")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                }
                Text(name)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .buttonStyle(.plain)
    }
}

struct AppleAppButton: View {
    let name: String
    let symbolName: String?
    let action: () -> Void

    private let iconHeight: CGFloat = 42
    private let cornerRadius: CGFloat = 10

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.quaternary)
                    .frame(maxWidth: .infinity)
                    .frame(height: iconHeight)
                    .overlay {
                        Image(systemName: symbolName ?? "app.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                Text(name)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Native gesture handler (no 300ms SwiftUI tap disambiguation delay)

private struct RemoteButtonGesture: NSViewRepresentable {
    let onInput: (InputAction) -> Void

    func makeNSView(context: Context) -> RemoteButtonGestureNSView {
        let view = RemoteButtonGestureNSView()
        view.onInput = onInput
        return view
    }

    func updateNSView(_ nsView: RemoteButtonGestureNSView, context: Context) {
        nsView.onInput = onInput
    }
}

private class RemoteButtonGestureNSView: NSView {
    var onInput: ((InputAction) -> Void)?
    private var holdTimer: Timer?
    private var holdFired = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        holdFired = false
        holdTimer?.invalidate()
        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.holdFired = true
            self.onInput?(.hold)
        }
    }

    override func mouseUp(with event: NSEvent) {
        holdTimer?.invalidate()
        holdTimer = nil
        guard !holdFired else { return }
        onInput?(.click)
    }
}

struct DPadView: View {
    @Environment(AppleTVManager.self) private var manager
    let onPress: (CompanionButton, InputAction) -> Void
    let size: CGFloat
    @State private var blinkOpacity: Double = 0

    private static let dpadButtons: Set<CompanionButton> = [.up, .down, .left, .right, .select]

    private func press(_ button: CompanionButton, _ action: InputAction) {
        blink()
        onPress(button, action)
    }

    private func blink() {
        blinkOpacity = 0.25
        withAnimation(.easeOut(duration: 0.2)) { blinkOpacity = 0 }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(nsColor: DS.Colors.remoteButton))
                .frame(width: size, height: size)

            // Center select button — larger, subtly distinct from outer ring
            Circle()
                .fill(Color(nsColor: DS.Colors.remoteButtonForeground).opacity(0.08))
                .frame(width: size * 0.5, height: size * 0.5)
                .overlay(RemoteButtonGesture { action in press(.select, action) })
                .help("Return")

            // Direction dots
            VStack {
                DPadDot(shortcut: "↑") { action in press(.up, action) }
                Spacer()
                DPadDot(shortcut: "↓") { action in press(.down, action) }
            }
            .frame(height: size)
            .padding(.vertical, 12)

            HStack {
                DPadDot(shortcut: "←") { action in press(.left, action) }
                Spacer()
                DPadDot(shortcut: "→") { action in press(.right, action) }
            }
            .frame(width: size)
            .padding(.horizontal, 12)

            Circle()
                .fill(.white.opacity(blinkOpacity))
                .frame(width: size, height: size)
                .allowsHitTesting(false)
        }
        .onChange(of: manager.keyboardBlinkCounter) { _, _ in
            if Self.dpadButtons.contains(manager.keyboardBlinkButton) { blink() }
        }
    }
}

struct DPadDot: View {
    let shortcut: String
    let action: (InputAction) -> Void

    var body: some View {
        Circle()
            .fill(Color(nsColor: DS.Colors.remoteButtonForeground))
            .frame(width: 5, height: 5)
            .frame(width: 30, height: 30)
            .overlay(RemoteButtonGesture(onInput: action))
            .help(shortcut)
    }
}

struct RemoteCircleButton: View {
    @Environment(AppleTVManager.self) private var manager
    let imageName: String
    let button: CompanionButton
    let shortcut: String
    let size: CGFloat
    let action: (InputAction) -> Void
    @State private var blinkOpacity: Double = 0

    private func press(_ input: InputAction) {
        blink()
        action(input)
    }

    private func blink() {
        blinkOpacity = 0.25
        withAnimation(.easeOut(duration: 0.2)) { blinkOpacity = 0 }
    }

    var body: some View {
        Image(imageName)
            .resizable()
            .scaledToFit()
            .frame(width: size * 0.33, height: size * 0.33)
            .frame(width: size, height: size)
            .background(Circle().fill(Color(nsColor: DS.Colors.remoteButton)))
            .overlay(Circle().fill(.white.opacity(blinkOpacity)).allowsHitTesting(false))
            .overlay(RemoteButtonGesture { input in press(input) })
            .help(shortcut)
            .onChange(of: manager.keyboardBlinkCounter) { _, _ in
                if manager.keyboardBlinkButton == button { blink() }
            }
    }
}

struct VolumePill: View {
    @Environment(AppleTVManager.self) private var manager
    let width: CGFloat
    let height: CGFloat
    let onUp: () -> Void
    let onDown: () -> Void
    @State private var blinkOpacity: Double = 0

    private func blink() {
        blinkOpacity = 0.25
        withAnimation(.easeOut(duration: 0.2)) { blinkOpacity = 0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: { blink(); onUp() }) {
                Image(systemName: "plus")
                    .font(.system(size: width * 0.3, weight: .medium))
                    .foregroundStyle(Color(nsColor: DS.Colors.remoteButtonForeground))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("+")

            Color(nsColor: DS.Colors.remoteButtonForeground).opacity(0.15)
                .frame(height: 1)

            Button(action: { blink(); onDown() }) {
                Image(systemName: "minus")
                    .font(.system(size: width * 0.3, weight: .medium))
                    .foregroundStyle(Color(nsColor: DS.Colors.remoteButtonForeground))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("−")
        }
        .frame(width: width, height: height)
        .background(Capsule().fill(Color(nsColor: DS.Colors.remoteButton)))
        .overlay(Capsule().fill(.white.opacity(blinkOpacity)).allowsHitTesting(false))
        .clipShape(Capsule())
        .onChange(of: manager.keyboardBlinkCounter) { _, _ in
            if manager.keyboardBlinkButton == .volumeUp || manager.keyboardBlinkButton == .volumeDown {
                blink()
            }
        }
    }
}

struct ErrorView: View {
    @Environment(AppleTVManager.self) private var manager
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
            Button("Dismiss") {
                manager.disconnect()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
    }
}

struct SettingsView: View {
    @Environment(AppleTVManager.self) private var manager

    var body: some View {
        Form {
            Section("Paired devices") {
                let deviceIDs = KeychainStorage.allPairedDeviceIDs()
                if deviceIDs.isEmpty {
                    Text("No paired devices")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(deviceIDs, id: \.self) { id in
                        HStack {
                            Image(systemName: "appletv.fill")
                            Text(id)
                            Spacer()
                            Button("Remove") {
                                KeychainStorage.delete(for: id)
                            }
                            .foregroundStyle(.red)
                        }
                    }
                }
            }
            Section("General") {
                Toggle("Launch at login", isOn: .constant(false))
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 300)
    }
}

/// Prevents `isMovableByWindowBackground` from intercepting drags on this view.
/// Place as a `.background()` on any interactive area that needs to handle its own drag gestures.
struct WindowDragBlocker: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NonDraggableView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class NonDraggableView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
}
