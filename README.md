# Itsytv

A native macOS menu bar app for controlling your Apple TV using the Companion Link Protocol.

## Features

- **Menu bar remote** — Control your Apple TV from the macOS menu bar with a compact remote interface
- **Automatic discovery** — Finds Apple TVs on your network via Bonjour (`_companion-link._tcp`)
- **Secure pairing** — SRP-based pair-setup with PIN verification, identical to HomeKit authentication
- **Encrypted communication** — ChaCha20-Poly1305 transport encryption with HKDF-derived session keys
- **Credential storage** — Pairing credentials stored securely in macOS Keychain
- **D-pad navigation** — Up, down, left, right, select with a circular remote layout
- **Playback controls** — Play/pause, volume up/down
- **System buttons** — Home, menu, back, sleep/wake
- **Multiple devices** — Pair and switch between multiple Apple TVs

## How it works

itsytv communicates with Apple TV using the **Companion Link Protocol**, the same protocol used by the iOS Remote app. The connection flow:

1. **Discovery** — NWBrowser finds Apple TVs advertising `_companion-link._tcp` on the local network
2. **Pair-setup** (first time) — SRP-6a handshake with a 4-digit PIN displayed on the TV, exchanging Ed25519 long-term keys
3. **Pair-verify** (subsequent connections) — Curve25519 ephemeral key exchange using stored credentials
4. **Encrypted session** — All commands sent as OPACK-encoded messages over ChaCha20-Poly1305 encrypted frames

Commands are sent as HID events matching the physical Siri Remote button values.

## Requirements

- macOS 14.0 or later
- Xcode 15.0 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) for project generation
- Apple TV running tvOS 15 or later on the same local network

## Setup

### 1. Install XcodeGen

```bash
brew install xcodegen
```

### 2. Clone the repository

```bash
git clone https://github.com/nickustinov/itsytv-macos.git
cd itsytv-macos
```

### 3. Generate the Xcode project

```bash
xcodegen generate
```

### 4. Open and run

```bash
open itsytv.xcodeproj
```

Select the **itsytv** scheme and run.

## Architecture

```
itsytv/
├── itsytvApp.swift              # App entry point with MenuBarExtra
├── AppState.swift               # Shared types (ConnectionStatus, AppleTVDevice)
├── Info.plist                   # Bundle config, network permissions
├── itsytv.entitlements          # Sandbox entitlements
├── Discovery/
│   └── DeviceDiscovery.swift    # NWBrowser for Bonjour discovery
├── Protocol/
│   ├── OPACK.swift              # Apple's OPACK binary serialization (encode/decode)
│   ├── TLV8.swift               # TLV8 encoding with 255-byte fragmentation
│   ├── CompanionFrame.swift     # Frame type enum + 4-byte header parse/serialize
│   ├── CompanionConnection.swift # TCP connection, frame buffering, encryption
│   ├── CompanionCommands.swift  # HID button commands, app launching
│   └── AppleTVManager.swift     # Orchestrator: discovery → pairing → commands
├── Crypto/
│   ├── PairSetup.swift          # SRP pair-setup (M1-M6) with Ed25519 identity exchange
│   ├── PairVerify.swift         # Curve25519 pair-verify (M1-M4) for session establishment
│   ├── CompanionCrypto.swift    # ChaCha20-Poly1305 transport encryption
│   └── KeychainStorage.swift    # Secure credential persistence
└── UI/
    └── MenuBarView.swift        # SwiftUI views: device list, pairing, remote, settings

Tests/
├── OPACKTests.swift             # 22 tests for OPACK encode/decode
└── TLV8Tests.swift              # 7 tests for TLV8 encode/decode
```

## Building

The project uses XcodeGen to generate the Xcode project from `project.yml`. After making changes to project configuration:

```bash
xcodegen generate
```

## Testing

```bash
xcodebuild test -scheme itsytvTests -destination "platform=macOS"
```

## License

MIT License © 2026 Nick Ustinov — see [LICENSE](LICENSE) for details.

## Author

**Nick Ustinov**
- GitHub: [@nickustinov](https://github.com/nickustinov)

## Acknowledgements

Protocol implementation informed by [pyatv](https://github.com/postlund/pyatv), the comprehensive Python library for Apple TV control.
