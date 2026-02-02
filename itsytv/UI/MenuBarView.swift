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
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.body)
                    if let model = device.modelName {
                        Text(model)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
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

struct RemoteControlView: View {
    @Environment(AppleTVManager.self) private var manager

    var body: some View {
        VStack(spacing: 16) {
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
