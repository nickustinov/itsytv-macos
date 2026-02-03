# Itsytv

[![Tests](https://github.com/nickustinov/itsytv-macos/actions/workflows/tests.yml/badge.svg)](https://github.com/nickustinov/itsytv-macos/actions/workflows/tests.yml)

A native macOS menu bar app for controlling your Apple TV.

![itsytv hero](https://itsytv.app/itsytv-hero.png)

## Features

- **Menu bar remote** — Control your Apple TV from a compact floating panel
- **D-pad and buttons** — Circular d-pad with directional navigation, select, home, menu/back, play/pause
- **Keyboard navigation** — Arrow keys, Return, Backspace, Escape, Space mapped to remote buttons
- **Text input** — Type directly into Apple TV text fields with a live keyboard
- **Now playing** — Artwork, title, artist, progress bar, and playback controls
- **App launcher** — Grid of installed apps with icons fetched from the App Store
- **Multiple devices** — Pair and switch between multiple Apple TVs
- **Per-device panel position** — Remembers where you placed the remote for each Apple TV
- **Launch at login** — Optional auto-start from the menu bar
- **Unpair** — Remove pairing credentials from the panel menu

## Perfect companion to Itsyhome

Itsytv pairs naturally with [Itsyhome](https://itsyhome.app) — a free macOS menu bar app for controlling your HomeKit devices. Manage lights, cameras, thermostats, locks, scenes, and 18+ accessory types without ever opening the Home app.

![Itsyhome](https://itsytv.app/itsyhome.png)

## Install

```bash
brew install --cask nickustinov/tap/itsytv
```

Or download the latest DMG from [GitHub releases](https://github.com/nickustinov/itsytv-macos/releases).

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
├── itsytvApp.swift                # App entry point
├── AppState.swift                 # Shared types (ConnectionStatus, AppleTVDevice)
├── Discovery/
│   └── DeviceDiscovery.swift      # Bonjour discovery of Apple TVs on the local network
├── Protocol/
│   ├── AppleTVManager.swift       # Orchestrator: discovery → pairing → session → commands
│   ├── CompanionConnection.swift  # TCP connection and frame handling
│   ├── CompanionCommands.swift    # HID buttons, session start, app launching
│   └── TextInputSession.swift     # Live text input to Apple TV text fields
├── Crypto/
│   └── KeychainStorage.swift      # Secure credential persistence in macOS Keychain
├── AirPlay/
│   └── AirPlayMRPTunnel.swift     # AirPlay tunnel for media remote protocol
├── MRP/
│   ├── MRPManager.swift           # Now-playing state and media commands
│   └── Proto/                     # Protobuf definitions and generated Swift code
├── DesignSystem/
│   ├── DesignSystem.swift         # Colours, typography, spacing, sizing tokens
│   └── HighlightingMenuItemView.swift # Custom NSView for interactive menu items
└── UI/
    ├── AppController.swift        # NSStatusItem, menu, floating panel, keyboard monitor
    ├── MenuBarView.swift          # SwiftUI views: remote, now playing, app grid
    └── AppIconLoader.swift        # App icons from iTunes Lookup API
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
