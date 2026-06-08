# Itsytv

[![Release](https://img.shields.io/github/v/release/nickustinov/itsytv-macos)](https://github.com/nickustinov/itsytv-macos/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/nickustinov/itsytv-macos/total)](https://github.com/nickustinov/itsytv-macos/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Swift 5.10](https://img.shields.io/badge/swift-5.10-orange.svg)](https://swift.org)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-brightgreen.svg)](https://www.apple.com/macos/sonoma/)
[![Homebrew](https://img.shields.io/badge/homebrew-cask-yellow.svg)](https://formulae.brew.sh/cask/itsytv)

A native macOS menu bar app for controlling your Apple TV.

[![Download on the Mac App Store](https://developer.apple.com/app-store/marketing/guidelines/images/badge-download-on-the-mac-app-store.svg)](https://apps.apple.com/app/itsytv/id6759216148)

![itsytv hero](https://itsytv.app/itsytv-hero.png)

## Also on iPhone

Itsytv is now available on iOS with the same core experience plus features designed for mobile:

- **TMDB lookup** for what's playing – poster art, ratings, and details for movies and TV shows
- **Ergonomic design** for left- and right-handed use

<p>
  <img src="https://itsytv.app/_next/image?url=%2Fiphone-main.png&w=3840&q=75" width="300" alt="Itsytv iPhone remote" />
  &nbsp;&nbsp;
  <img src="https://itsytv.app/_next/image?url=%2Fiphone-app-launcher.png&w=3840&q=75" width="300" alt="Itsytv iPhone app launcher" />
</p>

[![Download on the App Store](https://developer.apple.com/app-store/marketing/guidelines/images/badge-download-on-the-app-store.svg)](https://apps.apple.com/app/itsytv/id6759216148)

## Features

- **Menu bar remote** – control your Apple TV from a compact floating panel
- **D-pad and buttons** – circular d-pad with directional navigation, select, home, menu/back, play/pause
- **Keyboard navigation** – arrow keys, Return, Backspace, Escape, Space mapped to remote buttons
- **Text input** – type directly into Apple TV text fields with a live keyboard
- **Now playing** – artwork, title, artist, progress bar, and playback controls
- **App launcher** – grid of installed apps with icons fetched from the App Store; drag to reorder
- **Multiple devices** – pair and switch between multiple Apple TVs
- **Global hotkeys** – assign keyboard shortcuts to instantly open the remote for specific Apple TVs
- **Per-device panel position** – remembers where you placed the remote for each Apple TV
- **Launch at login** – optional auto-start from the menu bar
- **Unpair** – remove pairing credentials from the panel menu

## Perfect companion to Itsyhome

Itsytv pairs naturally with [Itsyhome](https://itsyhome.app) – a free macOS menu bar app for controlling your HomeKit devices. Manage lights, cameras, thermostats, locks, scenes, and 18+ accessory types without ever opening the Home app.

![Itsyhome](https://itsytv.app/itsyhome.png)

## Install

```bash
brew install --cask itsytv
```

Or download the latest DMG from [GitHub releases](https://github.com/nickustinov/itsytv-macos/releases).

## Troubleshooting

### Apple TV doesn't show a PIN code when pairing

If you send a pairing request but no PIN appears on your TV screen, your Apple TV is likely restricting which devices can connect to it. To fix this:

1. Open **Settings > AirPlay and Apple Home** on your Apple TV
2. Set **Allow access** to **Anyone on the same network**
3. Set **Require Password** to **Off** (after pairing is completed, Require Password can be turned back on)
4. Go to **Settings > General > Restrictions**
5. Set both **AirPlay Settings** and **Remote App Pairing** to **Allow**

The settings in step 2 and 5 need to stay on this value for itsytv to maintain a connection to your Apple TV.

### Remote disappears after a few seconds

If the remote panel closes on its own shortly after connecting, your Apple TV's AirPlay access setting is likely set to **Only people sharing this home**. Open **Settings** on your Apple TV, go to **AirPlay and Apple Home**, and change **Allow access** to **Anyone on the same network**.

### Nothing happens when I launch the app

Itsytv is a menu bar app – it lives in the top-right area of your screen as a small TV icon, not in the Dock. On MacBooks with a notch, macOS hides menu bar icons that don't fit behind the notch – silently, with no warning. If your menu bar is crowded, the itsytv icon may be there but invisible.

To fix this, hold **Cmd** and drag any icons you don't need off the menu bar. Once itsytv appears, Cmd-drag it to the right so it stays visible.

## Architecture

This app is a thin macOS UI layer on top of [itsytv-core](https://github.com/nickustinov/itsytv-core) – a Swift package that implements the Apple TV Companion Link and AirPlay protocols. The same core powers both the macOS and iOS apps.

```
itsytv-macos/
├── itsytvApp.swift              # App entry point
├── UI/
│   ├── AppController.swift      # NSStatusItem, menu, floating panel, keyboard monitor
│   ├── MenuBarView.swift        # SwiftUI views: remote, now playing, app grid
│   └── AppIconLoader.swift      # App icons from iTunes Lookup API
├── DesignSystem/
│   ├── DesignSystem.swift       # Colours, typography, spacing, sizing tokens
│   └── HighlightingMenuItemView.swift
├── AppIntents/
│   └── OpenRemoteIntent.swift   # Shortcuts action to open the remote for a specific Apple TV
├── MRP/
│   └── Proto/                   # Protobuf definitions (.proto files)
└── Utilities/
    ├── UpdateChecker.swift      # GitHub release checker
    └── HotkeyManager.swift      # Global hotkey registration
```

All protocol, crypto, discovery, and device management code lives in [itsytv-core](https://github.com/nickustinov/itsytv-core).

## Requirements

- macOS 14.0 or later
- Xcode 16.0 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) for project generation
- Apple TV running tvOS 15 or later on the same local network

## Setup

### 1. Clone the repositories

```bash
git clone https://github.com/nickustinov/itsytv-macos.git
git clone https://github.com/nickustinov/itsytv-core.git
```

Both repositories must be side by side – the Xcode project references `../itsytv-core` as a local Swift package.

### 2. Install XcodeGen

```bash
brew install xcodegen
```

### 3. Generate the Xcode project

```bash
cd itsytv-macos
xcodegen generate
```

### 4. Open and run

```bash
open itsytv.xcodeproj
```

Select the **itsytv** scheme and run.

## Building

The project uses XcodeGen to generate the Xcode project from `project.yml`. After making changes to project configuration:

```bash
xcodegen generate
```

## Releasing

1. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`
2. Update `CHANGELOG.md`
3. Build, sign, and package the DMG:

```bash
bash scripts/build-release.sh
```

4. Notarize and staple:

```bash
xcrun notarytool submit dist/Itsytv-<VERSION>.dmg \
    --apple-id <APPLE_ID> --team-id <TEAM_ID> \
    --password <APP_SPECIFIC_PASSWORD> --wait
xcrun stapler staple dist/Itsytv-<VERSION>.dmg
```

5. Create the GitHub release:

```bash
gh release create v<VERSION> dist/Itsytv-<VERSION>.dmg \
    --title "v<VERSION>" --notes "Release notes here"
```

6. **Homebrew cask** – itsytv is in the official [homebrew-cask](https://formulae.brew.sh/cask/itsytv) repository with autobump enabled. BrewTestBot automatically detects new GitHub releases and opens a PR within ~3 hours. No manual action needed.

## License

MIT License (c) 2026 Nick Ustinov – see [LICENSE](LICENSE) for details.

## Author

**Nick Ustinov** – [@nickustinov](https://github.com/nickustinov)

## Acknowledgements

Protocol implementation informed by [pyatv](https://github.com/postlund/pyatv), the comprehensive Python library for Apple TV control.
