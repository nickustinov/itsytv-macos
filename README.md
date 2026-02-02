# Itsytv

A native macOS menu bar app for controlling your Apple TV. 

## Features

- **Menu bar remote** — Control your Apple TV from the macOS menu bar with a compact remote interface
- **Now playing** — Live now-playing bar with title, artist, album, artwork, progress bar, and playback controls (play/pause, next, previous)
- **App launcher** — Browse installed apps in a grid with icons fetched from the App Store, launch with a click
- **Credential storage** — Pairing credentials stored securely in macOS Keychain
- **D-pad navigation** — Up, down, left, right, select with a circular remote layout
- **Playback controls** — Play/pause, volume up/down
- **System buttons** — Home, menu, back, sleep/wake
- **Multiple devices** — Pair and switch between multiple Apple TVs

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
│   └── DeviceDiscovery.swift    # NetServiceBrowser for Bonjour discovery + TXT record filtering
├── Protocol/
│   ├── OPACK.swift              # Apple's OPACK binary serialization (encode/decode)
│   ├── TLV8.swift               # TLV8 encoding with 255-byte fragmentation
│   ├── CompanionFrame.swift     # Frame type enum + 4-byte header parse/serialize
│   ├── CompanionConnection.swift # TCP connection, frame buffering, encryption, keep-alive
│   ├── CompanionCommands.swift  # HID buttons, session start, app fetching/launching
│   └── AppleTVManager.swift     # Orchestrator: discovery → pairing → session → commands
├── Crypto/
│   ├── PairSetup.swift          # SRP pair-setup (M1-M6) with Ed25519 identity exchange
│   ├── PairVerify.swift         # Curve25519 pair-verify (M1-M4) for session establishment
│   ├── CompanionCrypto.swift    # ChaCha20-Poly1305 transport encryption
│   └── KeychainStorage.swift    # Secure credential persistence
├── AirPlay/
│   ├── AirPlayMRPTunnel.swift   # Orchestrates full AirPlay tunnel setup for MRP
│   ├── AirPlayControlChannel.swift # HTTP/RTSP client over encrypted AirPlay connection
│   ├── AirPlayPairVerify.swift  # POST /pair-verify with TLV8/Curve25519
│   ├── HAPSession.swift         # 1024-byte block ChaCha20-Poly1305 framing
│   ├── HAPChannel.swift         # Encrypted TCP channel base for event/data streams
│   └── DataStreamChannel.swift  # Data stream framing + MRP protobuf wrapping
├── MRP/
│   ├── MRPManager.swift         # MRP session lifecycle, now-playing state, media commands
│   ├── NowPlayingState.swift    # Now-playing model (title, artist, album, artwork, progress)
│   └── Proto/                   # Protobuf definitions and generated Swift code
│       ├── ProtocolMessage.proto
│       ├── SetStateMessage.proto
│       ├── ContentItem.proto
│       ├── ContentItemMetadata.proto
│       ├── PlaybackQueue.proto
│       ├── ...                  # 15 proto files + Generated/ directory
│       └── Generated/           # Swift protobuf generated code
└── UI/
    ├── MenuBarView.swift        # SwiftUI views: device list, pairing, remote, now playing, app grid
    └── AppIconLoader.swift      # Fetches app icons from iTunes Lookup API

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
