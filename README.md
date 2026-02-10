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
- **App launcher** — Grid of installed apps with icons fetched from the App Store; drag to reorder
- **Multiple devices** — Pair and switch between multiple Apple TVs
- **Global hotkeys** — Assign keyboard shortcuts to instantly open the remote for specific Apple TVs
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

## Troubleshooting

### Nothing happens when I launch the app (MacBooks with notch)

Itsytv is a menu bar app — it lives in the top-right area of your screen as a small TV icon, not in the Dock. On MacBooks with a notch or Dynamic Island, macOS hides menu bar icons that don't fit behind the notch — silently, with no warning. If your menu bar is crowded, the Itsytv icon may be there but invisible.

**To fix this, free up menu bar space:**

Hold **⌘ Cmd** and drag any icons you don't need off the menu bar. Once Itsytv appears, ⌘-drag it to the right so it stays visible.

You can also hide system icons from System Settings:

- **macOS 26 Tahoe** — System Settings → Menu Bar → Menu Bar Controls. Toggle off "Show in menu bar" for icons you don't need (Wi-Fi, Bluetooth, Focus, etc.)
- **macOS 14–15 (Sonoma / Sequoia)** — System Settings → Control Center. Under each module, change "Show in menu bar" to "Don't show in menu bar"
### Apple TV not showing a PIN code when pairing

If your Apple TV doesn't display a pairing PIN, its settings are likely restricting connections.

On your Apple TV:

1. Open **Settings → AirPlay and HomeKit** (or AirPlay and Apple Home)
2. Set **Allow access** to **Everyone**
3. Go to **Settings → General → Restrictions**
4. Set both **AirPlay Settings** and **Remote App Pairing** to **Allow**

Once paired, you can revert these settings back.

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
│   ├── CompanionFrame.swift       # Companion Link frame structure (type + length + payload)
│   ├── CompanionCommands.swift    # HID buttons, session start, app launching
│   ├── TextInputSession.swift     # Live text input to Apple TV text fields
│   ├── OPACK.swift                # Apple's OPACK binary serialization format
│   ├── BinaryPlist.swift          # Binary plist encoder with NSKeyedArchiver UIDs
│   └── TLV8.swift                 # TLV8 encoding for HomeKit-style pairing
├── Crypto/
│   ├── CompanionCrypto.swift      # ChaCha20-Poly1305 encryption for Companion protocol
│   ├── CryptoHelpers.swift        # Shared helpers (nonce padding, HKDF-SHA512)
│   ├── PairSetup.swift            # SRP-based pair-setup flow (M1–M6)
│   ├── PairVerify.swift           # Pair-verify flow (M1–M4) with stored credentials
│   └── KeychainStorage.swift      # Secure credential persistence in macOS Keychain
├── AirPlay/
│   ├── AirPlayControlChannel.swift # HTTP/RTSP client with pair-verify and HAP encryption
│   ├── AirPlayPairVerify.swift    # Pair-verify flow (M1–M4) over AirPlay HTTP
│   ├── AirPlayMRPTunnel.swift     # AirPlay tunnel for media remote protocol
│   ├── DataStreamChannel.swift    # MRP protobuf transport over AirPlay 2 with framing
│   ├── HAPChannel.swift           # Base class for HAP-encrypted TCP channels
│   └── HAPSession.swift           # HAP session encryption with block framing
├── MRP/
│   ├── MRPManager.swift           # Now-playing state and media commands
│   ├── NowPlayingState.swift      # Now-playing metadata structure
│   └── Proto/                     # Protobuf definitions and generated Swift code
├── DesignSystem/
│   ├── DesignSystem.swift         # Colours, typography, spacing, sizing tokens
│   └── HighlightingMenuItemView.swift # Custom NSView for interactive menu items
├── AppIntents/
│   └── OpenRemoteIntent.swift     # Shortcuts action to open the remote for a specific Apple TV
├── UI/
│   ├── AppController.swift        # NSStatusItem, menu, floating panel, keyboard monitor
│   ├── MenuBarView.swift          # SwiftUI views: remote, now playing, app grid
│   └── AppIconLoader.swift        # App icons from iTunes Lookup API
└── Utilities/
    ├── AppOrderStorage.swift      # Per-device drag-to-reorder persistence
    ├── UpdateChecker.swift        # GitHub release checker
    └── HotkeyManager.swift        # Global hotkey registration
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

## Releasing

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `itsytv/Info.plist`
2. Update `CHANGELOG.md`
3. Build, sign, and package the DMG:

```bash
bash scripts/build-release.sh
```

4. Notarize and staple:

```bash
xcrun notarytool submit dist/itsytv-<VERSION>.dmg \
    --apple-id <APPLE_ID> --team-id <TEAM_ID> \
    --password <APP_SPECIFIC_PASSWORD> --wait
xcrun stapler staple dist/itsytv-<VERSION>.dmg
```

5. Create the GitHub release:

```bash
gh release create v<VERSION> dist/itsytv-<VERSION>.dmg \
    --title "v<VERSION>" --notes "Release notes here"
```

6. Update the Homebrew tap:

```bash
# Get SHA256 of the notarized DMG
shasum -a 256 dist/itsytv-<VERSION>.dmg

# Update Casks/itsytv.rb in homebrew-tap with new version and sha256
cd ../homebrew-tap
# Edit Casks/itsytv.rb
git commit -am "Update itsytv to <VERSION>"
git push
```

## License

MIT License © 2026 Nick Ustinov — see [LICENSE](LICENSE) for details.

## Author

**Nick Ustinov**
- GitHub: [@nickustinov](https://github.com/nickustinov)

## Acknowledgements

Protocol implementation informed by [pyatv](https://github.com/postlund/pyatv), the comprehensive Python library for Apple TV control.
