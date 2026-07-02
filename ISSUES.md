# Known issues

Codebase review findings from 2026-07-02, ranked by severity. Check off / delete as fixed.

## Bugs

### 1. SettingsView is broken
`itsytv/UI/MenuBarView.swift:1074-1105`

- "Launch at login" toggle is `isOn: .constant(false)` – always shows off, does nothing. The menu-bar item has a working implementation to reuse.
- "Remove" button deletes the keychain entry but the list never refreshes – `KeychainStorage.allPairedDeviceIDs()` is a plain `let` in `body` with nothing observable driving re-evaluation, so the row stays until the window reopens.
- Shows raw device IDs instead of names.

Fix: if the Settings scene isn't actually reachable/used, delete it. Otherwise fix all three.

### 2. Panel keyboard monitor hijacks keys from other windows
`itsytv/UI/AppController.swift:578-650`

The local `keyDown` monitor only checks `panel?.isVisible == true`, not whether the panel is the key window. With the remote panel open, typing in any other window of the app (Settings, iOS promo) sends arrow keys/Space/Esc to the Apple TV, and Cmd+W disconnects the remote instead of closing the focused window.

Fix: guard on `panel?.isKeyWindow == true` – but verify the always-on-top non-activating panel case, which can receive keys without being "key" in the usual sense.

### 3. pendingOpenDeviceID never expires
`itsytv/UI/AppController.swift:60-84, 156-161`

Press a hotkey for an offline Apple TV and the ID is parked forever; hours later, the moment that TV reappears on the network the remote panel pops up unprompted.

Fix: short timeout, or clear it when the menu opens.

### 4. Silent hotkey registration failure
`itsytv/Utilities/HotkeyManager.swift:141-153`

`RegisterEventHotKey` status ≠ `noErr` (shortcut taken by system/another app) is swallowed, but the shortcut was already persisted by `HotkeyStorage.save`, so the UI shows a hotkey that never fires.

Fix: at minimum log it; ideally surface the failure in the recorder popover.

### 5. Stale unpair-hint timers
`itsytv/UI/MenuBarView.swift:178-185`

`scheduleUnpairHint()` resets `showUnpairHint` but never cancels the previously scheduled `asyncAfter` block, so after a reconnect cycle the hint can appear well before 5 seconds of the latest "connecting" state.

Fix: stored `DispatchWorkItem` cancelled on re-arm, or a `Task` with cancellation.

### 6. pendingSeekTarget can stick forever
`itsytv/UI/MenuBarView.swift:350-362`

If a seek is rejected or playback jumps elsewhere (next track), the server never reports a position within 3 s of the target, so the progress bar freezes at the seeked position indefinitely.

Fix: clear the hold after a few timer ticks.

## Smaller issues

### 7. Debug logging at .error with .public privacy
`itsytv/UI/AppController.swift:71-81`, `itsytv/AppIntents/OpenRemoteIntent.swift:36, 52-56`

Device IDs and flow tracing logged as errors, visible to any log reader. Leftover debugging – drop or demote to `.debug` with default privacy.

### 8. 0.3 s polling timer runs forever
`itsytv/UI/AppController.swift:140-145`

The manager is `@Observable`; polling 3×/second for the lifetime of a menu-bar app is unnecessary energy drain. Make it event-driven via `withObservationTracking` or a publisher on the core. The app's only always-hot code path.

### 9. RemoteButtonGestureNSView.mouseUp has no bounds check
`itsytv/UI/MenuBarView.swift:701-707`

Press a remote button, drag off it, release – the click still fires. Standard buttons cancel on drag-out. `CloseButton` (`AppController.swift:1231`) already does this correctly:
`bounds.contains(convert(event.locationInWindow, from: nil))`.

### 10. hasPairedDevice is stale in pairing/error states
`itsytv/UI/AppController.swift:185-195, 265-280`

Only recomputed inside `buildDeviceList()`, but `shouldShowItsyhomePromo` reads it on every rebuild, so the promo decision uses whatever the last device-list build saw. Computing it directly from `KeychainStorage` in the getter removes the state entirely.

### 11. Empty deviceID fallback for hotkey storage
`itsytv/UI/MenuBarView.swift:30`

`PanelMenuButton(deviceID: manager.connectedDeviceID ?? "")` – a nil device ID silently saves hotkeys under the key `""`. Unlikely but cheap to guard.

### 12. Escape can't cancel pairing
`itsytv/UI/AppController.swift:1188-1197`

The PIN view handles digits and backspace only; the X button is the sole way out. Minor UX.

## Observations (not defects)

- `syncActivationBehavior` uses the private `_setPreventsActivation:` selector – correctly fenced out of the App Store build and documented with the FB number (FB16484811). Fine as is.
- The tvOS "26.5" gate (`MenuBarView.swift:461`) is a hard-coded version check – fine as a stopgap, remove when the fix lands.
- No tests in the repo. Pure logic like `UpdateChecker.isNewer` and `ShortcutKeys.displayString` is cheap to cover and silently breakable – e.g. `isNewer` treats "1.6.0-beta" as "1.6" because non-numeric parts are dropped by `compactMap`.
