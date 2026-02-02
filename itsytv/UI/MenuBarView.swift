import SwiftUI

struct MenuBarView: View {
    @Environment(AppleTVManager.self) private var manager

    var body: some View {
        VStack(spacing: 0) {
            switch manager.connectionStatus {
            case .disconnected:
                DeviceListView()
            case .connecting:
                ProgressView("Connecting...")
                    .padding()
            case .pairing:
                PairingView()
            case .connected:
                RemoteControlView()
            case .error(let message):
                ErrorView(message: message)
            }
        }
        .frame(width: 280)
        .onAppear {
            manager.startScanning()
        }
    }
}

struct DeviceListView: View {
    @Environment(AppleTVManager.self) private var manager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Apple TVs")
                    .font(.headline)
                Spacer()
                if manager.isScanning {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            if manager.discoveredDevices.isEmpty {
                Text("Scanning for devices...")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ForEach(manager.discoveredDevices) { device in
                    DeviceRow(device: device) {
                        manager.connect(to: device)
                    }
                }
            }

            Divider()

            Button("Quit itsytv") {
                NSApplication.shared.terminate(nil)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }
}

struct DeviceRow: View {
    let device: AppleTVDevice
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: "appletv.fill")
                    .foregroundStyle(.secondary)
                Text(device.name)
                    .font(.body)
                Spacer()
                if KeychainStorage.load(for: device.id) != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                } else {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}

struct PairingView: View {
    @Environment(AppleTVManager.self) private var manager
    @State private var pin: String = ""

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "appletv.fill")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text("Enter the PIN shown\non your Apple TV")
                .multilineTextAlignment(.center)
                .font(.subheadline)

            TextField("0000", text: $pin)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .frame(width: 120)
                .font(.title2.monospacedDigit())

            HStack(spacing: 12) {
                Button("Cancel") {
                    manager.disconnect()
                }

                Button("Pair") {
                    manager.submitPIN(pin)
                }
                .buttonStyle(.borderedProminent)
                .disabled(pin.count != 4)
            }
        }
        .padding(24)
    }
}

enum RemoteTab: String, CaseIterable {
    case remote = "Remote"
    case apps = "Apps"
}

struct RemoteControlView: View {
    @Environment(AppleTVManager.self) private var manager
    @State private var selectedTab: RemoteTab = .remote

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Image(systemName: "appletv.fill")
                    .foregroundStyle(.green)
                Text(manager.connectedDeviceName ?? "Apple TV")
                    .font(.subheadline)
                Spacer()
                Button {
                    manager.disconnect()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            // Tab picker
            Picker("", selection: $selectedTab) {
                ForEach(RemoteTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)

            switch selectedTab {
            case .remote:
                RemoteTabContent()
            case .apps:
                AppGridView()
            }

            // Now playing bar
            if manager.mrpManager.nowPlaying != nil {
                NowPlayingBar()
            }
        }
    }
}

struct NowPlayingBar: View {
    @Environment(AppleTVManager.self) private var manager

    var body: some View {
        let mrp = manager.mrpManager
        if let np = mrp.nowPlaying {
            VStack(spacing: 6) {
                Divider()

                // Artwork + title + artist
                HStack(spacing: 10) {
                    if let data = np.artworkData, let image = NSImage(data: data) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 40, height: 40)
                            .cornerRadius(4)
                    }

                    VStack(spacing: 2) {
                        Text(np.title ?? "Unknown")
                            .font(.caption.bold())
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if np.artist != nil || np.album != nil {
                            Text([np.artist, np.album].compactMap { $0 }.joined(separator: " — "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.horizontal, 16)

                // Controls
                HStack(spacing: 24) {
                    Button {
                        mrp.sendCommand(.previousTrack)
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(!mrp.supportedCommands.contains(.previousTrack))

                    Button {
                        mrp.sendCommand(.togglePlayPause)
                    } label: {
                        Image(systemName: np.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16))
                    }
                    .buttonStyle(.plain)

                    Button {
                        mrp.sendCommand(.nextTrack)
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(!mrp.supportedCommands.contains(.nextTrack))
                }
                .foregroundStyle(.secondary)

                // Progress bar
                if let duration = np.duration, duration > 0 {
                    NowPlayingProgress(nowPlaying: np, duration: duration)
                        .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 10)
        }
    }
}

struct NowPlayingProgress: View {
    let nowPlaying: NowPlayingState
    let duration: TimeInterval

    @State private var currentTime: TimeInterval = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 2) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(.quaternary)
                        .frame(height: 3)

                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(.secondary)
                        .frame(width: max(0, geo.size.width * min(1, currentTime / duration)), height: 3)
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
        .onAppear { currentTime = nowPlaying.currentPosition }
        .onReceive(timer) { _ in currentTime = nowPlaying.currentPosition }
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

    var body: some View {
        VStack(spacing: 16) {
            // D-pad
            DPadView { button in
                manager.pressButton(button)
            }
            .padding(.horizontal, 24)

            // Bottom controls
            HStack(spacing: 20) {
                RemoteButton(systemImage: "arrow.uturn.backward", label: "Back") {
                    manager.pressButton(.menu)
                }
                RemoteButton(systemImage: "house.fill", label: "Home") {
                    manager.pressButton(.home)
                }
                RemoteButton(systemImage: "playpause.fill", label: "Play") {
                    manager.pressButton(.playPause)
                }
            }

            HStack(spacing: 20) {
                RemoteButton(systemImage: "speaker.minus.fill", label: "Vol-") {
                    manager.pressButton(.volumeDown)
                }
                RemoteButton(systemImage: "speaker.plus.fill", label: "Vol+") {
                    manager.pressButton(.volumeUp)
                }
            }
            .padding(.bottom, 16)
        }
    }
}

struct AppGridView: View {
    @Environment(AppleTVManager.self) private var manager
    @Environment(AppIconLoader.self) private var iconLoader

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
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(manager.installedApps, id: \.bundleID) { app in
                        AppButton(
                            name: app.name,
                            icon: iconLoader.icons[app.bundleID]
                        ) {
                            manager.launchApp(bundleID: app.bundleID)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .frame(maxHeight: 280)
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

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .frame(height: 40)
                    .overlay {
                        if let icon {
                            Image(nsImage: icon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
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

struct DPadView: View {
    let onPress: (CompanionButton) -> Void
    let size: CGFloat = 160

    var body: some View {
        ZStack {
            Circle()
                .fill(.quaternary)
                .frame(width: size, height: size)

            // Center select button
            Button { onPress(.select) } label: {
                Circle()
                    .fill(.quinary)
                    .frame(width: size * 0.35, height: size * 0.35)
            }
            .buttonStyle(.plain)

            VStack {
                DPadArrow(direction: .up) { onPress(.up) }
                Spacer()
                DPadArrow(direction: .down) { onPress(.down) }
            }
            .frame(height: size)

            HStack {
                DPadArrow(direction: .left) { onPress(.left) }
                Spacer()
                DPadArrow(direction: .right) { onPress(.right) }
            }
            .frame(width: size)
        }
    }
}

enum DPadDirection {
    case up, down, left, right

    var systemImage: String {
        switch self {
        case .up: "chevron.up"
        case .down: "chevron.down"
        case .left: "chevron.left"
        case .right: "chevron.right"
        }
    }
}

struct DPadArrow: View {
    let direction: DPadDirection
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: direction.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct RemoteButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 18))
                Text(label)
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
            .frame(width: 48, height: 40)
        }
        .buttonStyle(.plain)
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
