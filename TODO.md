# Itsytv roadmap

## Companion protocol features

- [x] **App list and launch** — Fetch installed apps via `FetchLaunchableApplicationsEvent`, launch by bundle ID via `_launchApp`
- [ ] **Power state** — Monitor awake/asleep/screensaver via `FetchAttentionState`, subscribe to `SystemStatus` events
- [ ] **Event subscription** — Subscribe to `_iMC` (media control flags), `SystemStatus` (power state) via `_interest` command
- [ ] **User accounts** — List and switch between Apple TV user profiles via `FetchUserAccountsEvent`/`SwitchUserAccountEvent`
- [ ] **Text input** — Remote keyboard input via `_tiStart`/`_tiC` for search fields (requires NSKeyedArchiver encoding)
- [ ] **Session management** — Proper `_sessionStart`/`_sessionStop` lifecycle with `_systemInfo` exchange

## MRP protocol features

- [ ] **Media controls** — Play, pause, next/prev track, skip forward/back via MRP commands (more reliable than HID for playback control)
- [ ] **Now playing** — Title, artist, album, playback state, position, duration via MRP `SetStateMessage` push updates
- [ ] **Artwork** — Album art / video thumbnail via MRP `PlaybackQueueRequestMessage`
- [ ] **Mini player UI** — Compact now-playing widget in the menu bar with artwork, metadata, and transport controls

## App polish

- [ ] **Clean up debug logging** — Remove verbose os.log statements added during development
- [ ] **Launch at login** — SMAppService for auto-start
- [ ] **Keyboard shortcuts** — Global hotkeys for common actions (play/pause, volume, navigation)
- [ ] **DMG packaging** — Notarized DMG for distribution
- [ ] **Homebrew cask** — `brew install --cask itsytv`
