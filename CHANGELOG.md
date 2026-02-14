# Changelog

## 1.4.1

- Fix system dock becoming inoperative after quitting itsytv (magnification and hover effects stopped working until another app was activated)

## 1.4.0

- Add keyboard shortcuts for Apple TV volume control (+/- keys when panel is focused)
- Add ⌘K shortcut to toggle keyboard input
- Add tooltip hints showing keyboard shortcuts when hovering over remote buttons
- Make global hotkey toggle the remote panel (pressing it when already open closes it)
- Add visual blink feedback when pressing remote buttons via keyboard

## 1.3.0

- Add drag-to-reorder in the Apps tab — custom order is saved per device
- Add Shortcuts action "Open itsytv remote" for quick access from Control Center, Shortcuts app, and Spotlight
- Fix pairing credentials lost due to rpBA (Bluetooth address) rotation — device ID reverted to stable service name

## 1.2.1

- Fix two Apple TVs with the same name overwriting each other's credentials by using hardware-unique device ID
- Fix factory-reset Apple TV requiring manual unpair/re-pair — stale credentials are now auto-deleted and fresh pairing starts automatically
- Fix seek bar drag moving the window instead of scrubbing playback
- Fix seek bar snapping back to old position before jumping to the seeked position

## 1.2.0

- Keep remote buttons dark in both light and dark mode instead of inverting to white
- Add subtle blink feedback when pressing remote buttons
- Eliminate ~300ms click delay on remote buttons by replacing SwiftUI gesture recognizers with native event handling
- Swap Escape and Backspace keyboard mappings (Escape = Back, Backspace = Home) for more intuitive navigation

## 1.1.1

- Fix remote panel not receiving keyboard focus when opened via global hotkey

## 1.1.0

- Add global hotkeys for Apple TVs (assign a keyboard shortcut to quickly open the remote for a specific device)
- Show green Apple TV icon for paired devices in the menu
- Add ⌘W and ⌘H shortcuts to close the remote panel

## 1.0.6

- Fix volume buttons only responding to clicks on the +/- icons instead of the entire button area

## 1.0.5

- Add seekable progress bar in now-playing widget (click or drag to jump to position)

## 1.0.4

- Fix now-playing play/pause button not working with YouTube and other third-party apps
- Fix infinite artwork request loop when app doesn't provide album art (e.g. YouTube)

## 1.0.3

- Add "Check for updates..." menu item that checks GitHub releases for new versions
- Fix missing app icons for Apple Arcade games

## 1.0.2

- Fix remote panel not coming to front via Mission Control when "Always on top" is disabled

## 1.0.1

- Fix visual glitch where now-playing artwork and app icons could overflow the panel width, causing content to be clipped on both sides

## 1.0.0

- Initial release
