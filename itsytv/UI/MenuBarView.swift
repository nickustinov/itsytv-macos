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
                PanelMenuButton {
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
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 160)
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

            // Controls
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
                    mrp.sendCommand(.togglePlayPause)
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
                duration: np?.duration ?? 0
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

    @State private var currentTime: TimeInterval = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, currentTime / duration)
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
            }
            .frame(height: 3)

            HStack {
                Text(formatTime(currentTime))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(formatTime(duration))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .onAppear { currentTime = nowPlaying?.currentPosition ?? 0 }
        .onReceive(timer) { _ in currentTime = nowPlaying?.currentPosition ?? 0 }
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
            DPadView(onPress: { manager.pressButton($0) }, size: dpadSize)
                .padding(.top, 15)

            // Buttons matching Apple TV remote layout
            VStack(spacing: buttonGap) {
                // Row 1: Back + TV/Home
                HStack(spacing: buttonGap) {
                    RemoteCircleButton(imageName: "btnBack", size: buttonSize) {
                        manager.pressButton(.menu)
                    }
                    RemoteCircleButton(imageName: "btnHome", size: buttonSize) {
                        manager.pressButton(.home)
                    }
                }

                // Rows 2-3: Play/Pause + Keyboard left, Volume pill right
                HStack(alignment: .top, spacing: buttonGap) {
                    VStack(spacing: buttonGap) {
                        RemoteCircleButton(imageName: "btnPlayPause", size: buttonSize) {
                            manager.pressButton(.playPause)
                        }
                        RemoteCircleButton(imageName: "btnKeyboard", size: buttonSize) {
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
    }
}


struct AppGridView: View {
    @Environment(AppleTVManager.self) private var manager
    @Environment(AppIconLoader.self) private var iconLoader

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    private var thirdPartyApps: [(bundleID: String, name: String)] {
        manager.installedApps.filter { AppIconLoader.builtInSymbols[$0.bundleID] == nil }
    }

    private var appleApps: [(bundleID: String, name: String)] {
        manager.installedApps.filter { AppIconLoader.builtInSymbols[$0.bundleID] != nil }
    }

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
                VStack(spacing: 0) {
                    // Third-party apps with real icons
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(thirdPartyApps, id: \.bundleID) { app in
                            AppButton(
                                name: app.name,
                                icon: iconLoader.icons[app.bundleID]
                            ) {
                                manager.launchApp(bundleID: app.bundleID)
                            }
                        }
                    }

                    // Divider + Apple built-in apps
                    if !appleApps.isEmpty {
                        Divider()
                            .padding(.vertical, 10)

                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(appleApps, id: \.bundleID) { app in
                                AppleAppButton(
                                    name: app.name,
                                    symbolName: AppIconLoader.builtInSymbols[app.bundleID]
                                ) {
                                    manager.launchApp(bundleID: app.bundleID)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
            .onChange(of: manager.installedApps.map(\.bundleID)) {
                iconLoader.loadIcons(for: manager.installedApps.map(\.bundleID))
            }
            .onAppear {
                iconLoader.loadIcons(for: manager.installedApps.map(\.bundleID))
            }
        }
    }
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
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .frame(height: iconHeight)
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

struct DPadView: View {
    let onPress: (CompanionButton) -> Void
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(nsColor: DS.Colors.primary))
                .frame(width: size, height: size)

            // Center select button — larger, subtly distinct from outer ring
            Button { onPress(.select) } label: {
                Circle()
                    .fill(Color(nsColor: DS.Colors.primaryForeground).opacity(0.08))
                    .frame(width: size * 0.5, height: size * 0.5)
            }
            .buttonStyle(.plain)

            // Direction dots
            VStack {
                DPadDot { onPress(.up) }
                Spacer()
                DPadDot { onPress(.down) }
            }
            .frame(height: size)
            .padding(.vertical, 12)

            HStack {
                DPadDot { onPress(.left) }
                Spacer()
                DPadDot { onPress(.right) }
            }
            .frame(width: size)
            .padding(.horizontal, 12)
        }
    }
}

struct DPadDot: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(nsColor: DS.Colors.primaryForeground))
                .frame(width: 5, height: 5)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct RemoteCircleButton: View {
    let imageName: String
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(imageName)
                .resizable()
                .scaledToFit()
                .frame(width: size * 0.33, height: size * 0.33)
                .frame(width: size, height: size)
                .background(Circle().fill(Color(nsColor: DS.Colors.primary)))
        }
        .buttonStyle(.plain)
    }
}

struct VolumePill: View {
    let width: CGFloat
    let height: CGFloat
    let onUp: () -> Void
    let onDown: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onUp) {
                Image(systemName: "plus")
                    .font(.system(size: width * 0.3, weight: .medium))
                    .foregroundStyle(Color(nsColor: DS.Colors.primaryForeground))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.plain)

            Color(nsColor: DS.Colors.primaryForeground).opacity(0.15)
                .frame(height: 1)

            Button(action: onDown) {
                Image(systemName: "minus")
                    .font(.system(size: width * 0.3, weight: .medium))
                    .foregroundStyle(Color(nsColor: DS.Colors.primaryForeground))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.plain)
        }
        .frame(width: width, height: height)
        .background(Capsule().fill(Color(nsColor: DS.Colors.primary)))
        .clipShape(Capsule())
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
