import AppKit
import SwiftUI
import Combine
import ServiceManagement
import os.log
import ObjectiveC

private let log = Logger(subsystem: "com.itsytv.app", category: "Panel")

final class AppController: NSObject, NSMenuDelegate {

    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let menu = NSMenu()
    private let manager: AppleTVManager
    private let iconLoader: AppIconLoader
    private var observation: AnyCancellable?
    private var panel: NSPanel?
    private var panelDeviceID: String?
    private var keyboardMonitor: Any?
    private var alwaysOnTopObserver: NSObjectProtocol?

    init(manager: AppleTVManager, iconLoader: AppIconLoader) {
        self.manager = manager
        self.iconLoader = iconLoader
        super.init()
        setupStatusItem()
        rebuildMenu()
        startObserving()
        setupHotkeyHandler()
        manager.startScanning()
    }

    private func setupHotkeyHandler() {
        HotkeyManager.shared.reregisterAll()
        HotkeyManager.shared.onHotkeyPressed = { [weak self] deviceID in
            self?.openRemote(for: deviceID)
        }
    }

    private var pendingOpenDeviceID: String?

    func openRemote(for deviceID: String? = nil) {
        let targetID: String?
        if let deviceID {
            targetID = deviceID
        } else {
            // Pick the first discovered device that has stored credentials
            targetID = manager.discoveredDevices.first(where: { KeychainStorage.load(for: $0.id) != nil })?.id
        }
        let discoveredCount = manager.discoveredDevices.count
        log.error("openRemote: targetID=\(targetID ?? "nil", privacy: .public) discoveredCount=\(discoveredCount, privacy: .public)")
        guard let targetID else {
            log.error("openRemote: no targetID, returning")
            return
        }

        if let device = manager.discoveredDevices.first(where: { $0.id == targetID }) {
            log.error("openRemote: device found, connecting")
            connectAndShow(device)
        } else {
            log.error("openRemote: device not discovered yet, setting pendingOpenDeviceID")
            pendingOpenDeviceID = targetID
        }
    }

    private func connectAndShow(_ device: AppleTVDevice) {
        manager.connect(to: device)
        if KeychainStorage.load(for: device.id) != nil {
            showPanel()
        }
    }

    // MARK: - Setup

    private func setupStatusItem() {
        if let button = statusItem.button {
            if let icon = Bundle.main.image(forResource: "MenuBarIcon") {
                icon.isTemplate = true
                icon.size = NSSize(width: 18, height: 18)
                button.image = icon
            }
        }
        statusItem.menu = menu
        menu.delegate = self
    }

    private func startObserving() {
        observation = Timer.publish(every: 0.3, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.handleStateChange()
            }
    }

    private var lastKnownStatus: ConnectionStatus = .disconnected
    private var lastKnownDeviceCount: Int = 0
    private var hasPairedDevice = false

    private func handleStateChange() {
        let currentStatus = manager.connectionStatus
        let currentDeviceCount = manager.discoveredDevices.count

        // Fulfill pending openRemote when the target device is discovered
        if let pendingID = pendingOpenDeviceID,
           let device = manager.discoveredDevices.first(where: { $0.id == pendingID }) {
            pendingOpenDeviceID = nil
            connectAndShow(device)
            return
        }

        guard currentStatus != lastKnownStatus || currentDeviceCount != lastKnownDeviceCount else { return }
        lastKnownStatus = currentStatus
        lastKnownDeviceCount = currentDeviceCount

        switch currentStatus {
        case .disconnected:
            dismissPanel()
            rebuildMenu()
        case .connecting:
            if panel != nil {
                // Panel already open — SwiftUI will update content
            } else {
                rebuildMenu()
            }
        case .pairing, .error:
            rebuildMenu()
        case .connected:
            menu.cancelTracking()
            showPanel()
        }
    }

    private var shouldShowItsyhomePromo: Bool {
        let hasDevices = hasPairedDevice
        let isInstalled: Bool = {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.nickustinov.itsyhome") else {
                return false
            }
            let path = url.path
            return path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/")
        }()
        return hasDevices && !isInstalled
    }

    // MARK: - Menu building

    private func rebuildMenu() {
        menu.removeAllItems()

        switch manager.connectionStatus {
        case .disconnected:
            buildDeviceList()
        case .connecting:
            if panel != nil { return }
            let item = NSMenuItem(title: "Connecting...", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        case .pairing:
            let pairing = PairingMenuItem(manager: manager)
            menu.addItem(pairing)
        case .error(let message):
            let errorItem = NSMenuItem(title: message, action: nil, keyEquivalent: "")
            errorItem.isEnabled = false
            menu.addItem(errorItem)
            menu.addItem(NSMenuItem.separator())
            let dismissItem = createActionItem(title: "Dismiss") { [weak self] in
                self?.manager.disconnect()
            }
            menu.addItem(dismissItem)
        case .connected:
            buildDeviceList()
        }

        switch manager.connectionStatus {
        case .pairing, .connecting:
            break
        default:
            menu.addItem(NSMenuItem.separator())
            if shouldShowItsyhomePromo {
                menu.addItem(createItsyhomePromoItem())
                menu.addItem(NSMenuItem.separator())
            }
            let loginItem = createCheckboxItem(
                title: "Launch at login",
                isOn: SMAppService.mainApp.status == .enabled
            ) {
                do {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                    } else {
                        try SMAppService.mainApp.register()
                    }
                } catch {
                    log.error("Failed to toggle login item: \(error.localizedDescription)")
                }
            }
            menu.addItem(loginItem)
            let updateItem = createActionItem(title: "Check for updates...", symbolName: "arrow.triangle.2.circlepath") {
                UpdateChecker.check()
            }
            menu.addItem(updateItem)
            let quitItem = createActionItem(title: "Quit", symbolName: "power") {
                NSApplication.shared.terminate(nil)
            }
            menu.addItem(quitItem)
        }
    }

    private func buildDeviceList() {
        hasPairedDevice = false
        if manager.discoveredDevices.isEmpty {
            let scanning = NSMenuItem(title: "Scanning for devices...", action: nil, keyEquivalent: "")
            scanning.isEnabled = false
            menu.addItem(scanning)
        } else {
            let sorted = manager.discoveredDevices.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            for device in sorted {
                let isPaired = KeychainStorage.load(for: device.id) != nil
                if isPaired { hasPairedDevice = true }
                let item = createDeviceItem(device: device, isPaired: isPaired)
                menu.addItem(item)
            }
        }
    }

    private func createDeviceItem(device: AppleTVDevice, isPaired: Bool) -> NSMenuItem {
        let height = DS.ControlSize.menuItemHeight
        let width = DS.ControlSize.menuItemWidth

        let containerView = HighlightingMenuItemView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        containerView.closesMenuOnAction = isPaired

        // Icon (green for paired devices)
        let iconSize = DS.ControlSize.iconMedium
        let iconY = (height - iconSize) / 2
        let iconView = NSImageView(frame: NSRect(x: DS.Spacing.md, y: iconY, width: iconSize, height: iconSize))
        iconView.image = NSImage(systemSymbolName: "appletv.fill", accessibilityDescription: nil)
        iconView.contentTintColor = isPaired ? .systemGreen : DS.Colors.iconForeground
        iconView.imageScaling = .scaleProportionallyUpOrDown
        containerView.addSubview(iconView)

        // Hotkey (right-aligned, for paired devices with assigned hotkey)
        let rightPadding: CGFloat = 20
        var labelRightEdge = width - rightPadding
        if isPaired, let keys = HotkeyStorage.load(deviceID: device.id) {
            let hotkeyFont = NSFont.menuFont(ofSize: 13)
            let hotkeyStr = keys.displayString
            let hotkeyAttr = NSAttributedString(string: hotkeyStr, attributes: [.font: hotkeyFont])
            let hotkeyTextSize = hotkeyAttr.size()
            let hotkeyW = ceil(hotkeyTextSize.width) + 4
            let hotkeyX = width - rightPadding - hotkeyW
            let hotkeyY = (height - hotkeyTextSize.height) / 2

            let hotkeyLabel = NSTextField(labelWithString: hotkeyStr)
            hotkeyLabel.frame = NSRect(x: hotkeyX, y: hotkeyY, width: hotkeyW, height: hotkeyTextSize.height)
            hotkeyLabel.font = hotkeyFont
            hotkeyLabel.textColor = .tertiaryLabelColor
            containerView.addSubview(hotkeyLabel)
            labelRightEdge = hotkeyX - DS.Spacing.sm
        }

        // Name label
        let labelX = DS.Spacing.md + iconSize + DS.Spacing.sm
        let labelY = (height - 17) / 2
        let labelWidth = labelRightEdge - labelX
        let nameLabel = NSTextField(labelWithString: device.name)
        nameLabel.frame = NSRect(x: labelX, y: labelY, width: labelWidth, height: 17)
        nameLabel.font = DS.Typography.label
        nameLabel.textColor = DS.Colors.foreground
        nameLabel.lineBreakMode = .byTruncatingTail
        containerView.addSubview(nameLabel)

        containerView.onAction = { [weak self] in
            self?.openRemote(for: device.id)
        }

        let item = NSMenuItem(title: device.name, action: nil, keyEquivalent: "")
        item.view = containerView
        return item
    }

    private func createActionItem(title: String, symbolName: String? = nil, action: @escaping () -> Void) -> NSMenuItem {
        let height = DS.ControlSize.menuItemHeight
        let width = DS.ControlSize.menuItemWidth

        let containerView = HighlightingMenuItemView(frame: NSRect(x: 0, y: 0, width: width, height: height))

        var labelX = DS.Spacing.md
        if let symbolName {
            let iconSize = DS.ControlSize.iconMedium
            let iconY = (height - iconSize) / 2
            let iconView = NSImageView(frame: NSRect(x: DS.Spacing.md, y: iconY, width: iconSize, height: iconSize))
            iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
            iconView.contentTintColor = DS.Colors.iconForeground
            iconView.imageScaling = .scaleProportionallyUpOrDown
            containerView.addSubview(iconView)
            labelX = DS.Spacing.md + iconSize + DS.Spacing.sm
        }

        let labelY = (height - 17) / 2
        let labelWidth = width - labelX - DS.Spacing.md
        let nameLabel = NSTextField(labelWithString: title)
        nameLabel.frame = NSRect(x: labelX, y: labelY, width: labelWidth, height: 17)
        nameLabel.font = DS.Typography.label
        nameLabel.textColor = DS.Colors.foreground
        nameLabel.lineBreakMode = .byTruncatingTail
        containerView.addSubview(nameLabel)

        containerView.onAction = action

        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.view = containerView
        return item
    }

    private func createCheckboxItem(title: String, isOn: Bool, action: @escaping () -> Void) -> NSMenuItem {
        let height = DS.ControlSize.menuItemHeight
        let width = DS.ControlSize.menuItemWidth

        let containerView = HighlightingMenuItemView(frame: NSRect(x: 0, y: 0, width: width, height: height))

        let iconSize = DS.ControlSize.iconMedium
        let checkX = DS.Spacing.md
        let checkY = (height - iconSize) / 2
        let checkmark = NSTextField(labelWithString: isOn ? "✓" : "")
        checkmark.frame = NSRect(x: checkX, y: checkY, width: iconSize, height: iconSize)
        checkmark.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        checkmark.textColor = DS.Colors.foreground
        checkmark.alignment = .center
        containerView.addSubview(checkmark)

        let labelX = DS.Spacing.md + iconSize + DS.Spacing.sm
        let labelY = (height - 17) / 2
        let labelWidth = width - labelX - DS.Spacing.md
        let nameLabel = NSTextField(labelWithString: title)
        nameLabel.frame = NSRect(x: labelX, y: labelY, width: labelWidth, height: 17)
        nameLabel.font = DS.Typography.label
        nameLabel.textColor = DS.Colors.foreground
        nameLabel.lineBreakMode = .byTruncatingTail
        containerView.addSubview(nameLabel)

        containerView.onAction = action

        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.view = containerView
        return item
    }

    private func createItsyhomePromoItem() -> NSMenuItem {
        let width = DS.ControlSize.menuItemWidth
        let height: CGFloat = 64

        let containerView = ItsyhomePromoView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        containerView.onAction = {
            if let url = URL(string: "macappstore://apps.apple.com/app/itsyhome/id6758070650") {
                NSWorkspace.shared.open(url)
            }
        }

        let item = NSMenuItem(title: "Itsyhome", action: nil, keyEquivalent: "")
        item.view = containerView
        return item
    }

    // MARK: - Panel

    private func showPanel() {
        if panel != nil {
            return
        }

        let panelContent = PanelContentView()
            .environment(manager)
            .environment(iconLoader)

        let hostingView = ArrowCursorHostingView(rootView: panelContent)
        hostingView.safeAreaRegions = []
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        // Vibrancy view as the contentView itself
        let vibrancy = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 176, height: 400))
        vibrancy.material = .menu
        vibrancy.state = .active
        vibrancy.wantsLayer = true
        vibrancy.layer?.cornerRadius = 10
        vibrancy.layer?.masksToBounds = true
        vibrancy.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: vibrancy.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: vibrancy.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: vibrancy.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: vibrancy.trailingAnchor),
        ])

        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 176, height: 400),
            styleMask: [.nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = vibrancy
        let alwaysOnTop = UserDefaults.standard.object(forKey: "alwaysOnTop") as? Bool ?? true
        panel.isFloatingPanel = alwaysOnTop
        panel.level = alwaysOnTop ? .statusBar : .normal
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.fullScreenAuxiliary]
        if !alwaysOnTop {
            panel.styleMask.remove(.nonactivatingPanel)
            panel.syncActivationBehavior()
        }
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.hasShadow = true

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        // Position after makeKeyAndOrderFront — AppKit constrains the
        // frame during ordering for .statusBar level panels, so we must
        // set the origin after the window is on screen.
        if let origin = savedPanelOrigin(panelHeight: panel.frame.height), isPointOnScreen(origin, panelSize: panel.frame.size) {
            log.info("showPanel: using saved origin (\(origin.x), \(origin.y))")
            panel.setFrameOrigin(origin)
        } else if let buttonFrame = statusItem.button?.window?.frame {
            let x = buttonFrame.midX - 88
            let y = buttonFrame.minY - panel.frame.height
            log.info("showPanel: using status bar fallback (\(x), \(y))")
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            log.warning("showPanel: no saved origin and no status bar button frame")
        }

        self.panel = panel
        self.panelDeviceID = manager.connectedDeviceID
        installKeyboardMonitor()

        // Observe "Always on top" toggle changes while panel is open
        alwaysOnTopObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, let panel = self.panel else { return }
            let onTop = UserDefaults.standard.object(forKey: "alwaysOnTop") as? Bool ?? true
            panel.isFloatingPanel = onTop
            panel.level = onTop ? .statusBar : .normal
            if onTop {
                panel.styleMask.insert(.nonactivatingPanel)
            } else {
                panel.styleMask.remove(.nonactivatingPanel)
            }
            panel.syncActivationBehavior()
            if !onTop {
                NSApp.activate(ignoringOtherApps: true)
                panel.makeKeyAndOrderFront(nil)
            }
        }
    }

    private func dismissPanel() {
        removeKeyboardMonitor()
        if let observer = alwaysOnTopObserver {
            NotificationCenter.default.removeObserver(observer)
            alwaysOnTopObserver = nil
        }
        savePanelPosition()
        panel?.close()
        panel = nil
        panelDeviceID = nil
    }

    private func savePanelPosition() {
        guard let frame = panel?.frame else {
            log.debug("save: no panel frame")
            return
        }
        guard let deviceID = panelDeviceID else {
            log.debug("save: no panelDeviceID")
            return
        }
        // Save top-left corner (x, maxY) — the visual anchor point.
        // AppKit origin is bottom-left, but top-left stays stable
        // regardless of panel height changes from SwiftUI layout.
        let dict: [String: CGFloat] = ["x": frame.minX, "topY": frame.maxY]
        UserDefaults.standard.set(dict, forKey: "panelOrigin_\(deviceID)")
        log.info("save: topLeft (\(frame.minX), \(frame.maxY)) for device \(deviceID)")
    }

    private func savedPanelOrigin(panelHeight: CGFloat) -> NSPoint? {
        guard let deviceID = manager.connectedDeviceID else {
            log.debug("restore: no connectedDeviceID")
            return nil
        }
        let key = "panelOrigin_\(deviceID)"
        guard let dict = UserDefaults.standard.dictionary(forKey: key) else {
            log.debug("restore: no saved value for key \(key)")
            return nil
        }
        guard let x = dict["x"] as? CGFloat, let topY = dict["topY"] as? CGFloat else {
            log.debug("restore: bad dict format: \(dict)")
            return nil
        }
        // Convert top-left back to AppKit bottom-left origin
        let origin = NSPoint(x: x, y: topY - panelHeight)
        log.info("restore: topLeft (\(x), \(topY)) → origin (\(origin.x), \(origin.y)) for device \(deviceID)")
        return origin
    }

    private func isPointOnScreen(_ origin: NSPoint, panelSize: NSSize) -> Bool {
        let panelRect = NSRect(origin: origin, size: panelSize)
        let onScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(panelRect) }
        log.info("onScreen check: (\(origin.x), \(origin.y)) size \(panelSize.width)x\(panelSize.height) → \(onScreen)")
        return onScreen
    }

    private func installKeyboardMonitor() {
        removeKeyboardMonitor()
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel?.isVisible == true else { return event }
            if self.handleRemoteKeyDown(event) { return nil }
            return event
        }
    }

    private func removeKeyboardMonitor() {
        if let monitor = keyboardMonitor {
            NSEvent.removeMonitor(monitor)
            keyboardMonitor = nil
        }
    }

    private func handleRemoteKeyDown(_ event: NSEvent) -> Bool {
        // Ignore when any text input is focused (field editor, NSTextField, or SwiftUI text)
        if let responder = panel?.firstResponder {
            var r: NSResponder? = responder
            while let current = r {
                if current is NSText || current is NSTextField { return false }
                r = current.nextResponder
            }
        }

        // Cmd+W or Cmd+H closes the panel
        if event.modifierFlags.contains(.command) {
            switch event.keyCode {
            case 13, 4: // W, H
                manager.disconnect()
                return true
            default:
                break
            }
        }

        switch event.keyCode {
        case 126: manager.pressButton(.up); return true       // ↑
        case 125: manager.pressButton(.down); return true     // ↓
        case 123: manager.pressButton(.left); return true     // ←
        case 124: manager.pressButton(.right); return true    // →
        case 36:  manager.pressButton(.select); return true   // Return
        case 51:  manager.pressButton(.home); return true     // Backspace
        case 53:  manager.pressButton(.menu); return true     // Escape
        case 49:  manager.pressButton(.playPause); return true // Space
        default:  return false
        }
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        manager.refreshScanning()
        rebuildMenu()
    }
}

// MARK: - Panel SwiftUI content

// MARK: - Key-capable panel

private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

extension NSPanel {
    /// Sync the WindowServer activation tag after changing `.nonactivatingPanel`.
    /// AppKit bug: toggling the style mask flag alone does not update the
    /// underlying `kCGSPreventsActivationTagBit` tag (FB16484811).
    func syncActivationBehavior() {
        let prevents = styleMask.contains(.nonactivatingPanel)
        let sel = Selector(("_setPreventsActivation:"))
        guard let method = class_getMethodImplementation(type(of: self), sel) else { return }
        typealias Fn = @convention(c) (AnyObject, Selector, ObjCBool) -> Void
        let fn = unsafeBitCast(method, to: Fn.self)
        fn(self, sel, ObjCBool(prevents))
    }
}

// MARK: - Arrow cursor hosting view

private final class ArrowCursorHostingView<Content: View>: NSHostingView<Content> {
    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: .arrow)
    }

    override func addCursorRect(_ rect: NSRect, cursor: NSCursor) {
        super.addCursorRect(rect, cursor: .arrow)
    }
}

struct PanelMenuButton: View {
    let deviceID: String
    let onUnpair: () -> Void
    @AppStorage("alwaysOnTop") private var alwaysOnTop = true
    @State private var showingHotkeyRecorder = false
    @State private var currentHotkey: ShortcutKeys?

    var body: some View {
        Menu {
            Toggle("Always on top", isOn: $alwaysOnTop)
            Divider()
            Button(hotkeyButtonTitle) {
                showingHotkeyRecorder = true
            }
            if currentHotkey != nil {
                Button("Remove hotkey", role: .destructive) {
                    HotkeyStorage.save(deviceID: deviceID, keys: nil)
                    currentHotkey = nil
                }
            }
            Divider()
            Button("Unpair", role: .destructive, action: onUnpair)
        } label: {
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 20, height: 20)
                Image(systemName: "ellipsis")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .popover(isPresented: $showingHotkeyRecorder) {
            ShortcutRecorderView(deviceID: deviceID) { keys in
                currentHotkey = keys
                showingHotkeyRecorder = false
            }
        }
        .onAppear {
            currentHotkey = HotkeyStorage.load(deviceID: deviceID)
        }
    }

    private var hotkeyButtonTitle: String {
        if let keys = currentHotkey {
            return "Change hotkey (\(keys.displayString))"
        }
        return "Assign hotkey..."
    }
}

struct ShortcutRecorderView: View {
    let deviceID: String
    let onRecorded: (ShortcutKeys?) -> Void
    @State private var isRecording = false
    @State private var recordedKeys: ShortcutKeys?

    var body: some View {
        VStack(spacing: 12) {
            Text(displayText)
                .font(.system(.title2, design: .monospaced))
                .foregroundStyle(isRecording && recordedKeys == nil ? .secondary : .primary)
                .frame(minWidth: 100, minHeight: 30)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(8)

            Text("Use ⌘, ⌥, ⌃, ⇧ with a key")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("Cancel") {
                    onRecorded(HotkeyStorage.load(deviceID: deviceID))
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    if let keys = recordedKeys {
                        HotkeyStorage.save(deviceID: deviceID, keys: keys)
                    }
                    onRecorded(recordedKeys)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(recordedKeys == nil)
            }
        }
        .padding(20)
        .frame(width: 220)
        .background(ShortcutRecorderHelper(isRecording: $isRecording, recordedKeys: $recordedKeys))
        .onAppear {
            isRecording = true
            recordedKeys = HotkeyStorage.load(deviceID: deviceID)
        }
        .onDisappear {
            isRecording = false
        }
    }

    private var displayText: String {
        if let keys = recordedKeys {
            return keys.displayString
        }
        return isRecording ? "Press keys..." : "None"
    }
}

struct ShortcutRecorderHelper: NSViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var recordedKeys: ShortcutKeys?

    func makeNSView(context: Context) -> ShortcutRecorderNSView {
        let view = ShortcutRecorderNSView()
        view.onShortcutRecorded = { keys in
            recordedKeys = keys
        }
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderNSView, context: Context) {
        nsView.isRecording = isRecording
    }
}

final class ShortcutRecorderNSView: NSView {
    var isRecording = false
    var onShortcutRecorded: ((ShortcutKeys) -> Void)?
    private var monitor: Any?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            setupMonitor()
        } else {
            removeMonitor()
        }
    }

    private func setupMonitor() {
        removeMonitor()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isRecording else { return event }

            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            // Require at least one modifier
            guard !modifiers.isEmpty else { return event }

            // Ignore if only modifier keys pressed (no actual key)
            let keyCode = event.keyCode
            let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63] // Cmd, Shift, Option, Ctrl variants
            if modifierKeyCodes.contains(keyCode) { return event }

            let keys = ShortcutKeys(modifiers: modifiers.rawValue, keyCode: keyCode)
            DispatchQueue.main.async {
                self.onShortcutRecorded?(keys)
            }
            return nil
        }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    deinit {
        removeMonitor()
    }
}

struct PanelCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 20, height: 20)
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

struct PanelContentView: View {
    @Environment(AppleTVManager.self) private var manager

    var body: some View {
        VStack(spacing: 0) {
            switch manager.connectionStatus {
            case .connecting, .connected:
                RemoteControlView()
            case .error(let message):
                ErrorView(message: message)
            default:
                EmptyView()
            }
        }
        .frame(width: 176)
    }
}

// MARK: - NSWindowDelegate

extension AppController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSPanel) === panel {
            savePanelPosition()
            if manager.connectionStatus != .disconnected {
                manager.disconnect()
            }
            panel = nil
            panelDeviceID = nil
        }
    }
}

// MARK: - Pairing menu item

final class PairingMenuItem: NSMenuItem {

    private let manager: AppleTVManager
    private var digits: [Int?] = [nil, nil, nil, nil]
    private var digitLabels: [NSTextField] = []
    private var digitBoxes: [NSView] = []
    private weak var containerView: PairingContainerView?

    init(manager: AppleTVManager) {
        self.manager = manager
        super.init(title: "Pairing", action: nil, keyEquivalent: "")
        self.view = buildView()
    }

    required init(coder: NSCoder) {
        fatalError()
    }

    private var currentIndex: Int {
        digits.firstIndex(where: { $0 == nil }) ?? 4
    }

    private func buildView() -> NSView {
        let width = DS.ControlSize.menuItemWidth
        let padding = DS.Spacing.lg

        // Layout
        let digitBoxSize: CGFloat = 44
        let digitBoxSpacing: CGFloat = DS.Spacing.sm
        let allDigitsWidth = digitBoxSize * 4 + digitBoxSpacing * 3
        let titleHeight: CGFloat = 17
        let closeButtonSize: CGFloat = 20
        let topPadding = DS.Spacing.md
        let afterTitle = DS.Spacing.md
        let bottomPadding = DS.Spacing.lg

        let totalHeight = topPadding + titleHeight + afterTitle + digitBoxSize + bottomPadding

        let container = PairingContainerView(
            frame: NSRect(x: 0, y: 0, width: width, height: totalHeight),
            onDigit: { [weak self] digit in self?.enterDigit(digit) },
            onBackspace: { [weak self] in self?.backspace() }
        )
        containerView = container

        // Title
        let titleY = totalHeight - topPadding - titleHeight
        let title = NSTextField(labelWithString: "Enter PIN from your Apple TV")
        title.frame = NSRect(x: padding, y: titleY, width: width - padding * 2 - closeButtonSize - DS.Spacing.sm, height: titleHeight)
        title.font = DS.Typography.labelMedium
        title.textColor = DS.Colors.foreground
        container.addSubview(title)

        // Close (X) button — top right
        let closeX = width - padding - closeButtonSize
        let closeY = titleY + (titleHeight - closeButtonSize) / 2
        let closeButton = CloseButton(frame: NSRect(x: closeX, y: closeY, width: closeButtonSize, height: closeButtonSize))
        closeButton.onPress = { [weak self] in
            self?.manager.disconnect()
        }
        container.addSubview(closeButton)

        // Digit boxes — centered
        let digitsY = titleY - afterTitle - digitBoxSize
        let digitsX = (width - allDigitsWidth) / 2
        let digitBoxBg = NSColor(name: nil) { $0.isDark ? NSColor(white: 0.22, alpha: 1) : NSColor(white: 0.82, alpha: 1) }
        let digitBoxBorder = NSColor(name: nil) { $0.isDark ? NSColor(white: 0.40, alpha: 1) : NSColor(white: 0.60, alpha: 1) }
        let digitBoxFocusBorder = NSColor(name: nil) { $0.isDark ? NSColor(white: 0.70, alpha: 1) : NSColor(white: 0.30, alpha: 1) }

        for i in 0..<4 {
            let boxX = digitsX + CGFloat(i) * (digitBoxSize + digitBoxSpacing)
            let box = DigitBoxView(frame: NSRect(x: boxX, y: digitsY, width: digitBoxSize, height: digitBoxSize))
            box.bgColor = digitBoxBg
            box.borderColor = digitBoxBorder
            box.focusBorderColor = digitBoxFocusBorder
            container.addSubview(box)
            digitBoxes.append(box)

            let labelHeight: CGFloat = 22
            let labelY = (digitBoxSize - labelHeight) / 2
            let label = NSTextField(labelWithString: "")
            label.frame = NSRect(x: 0, y: labelY, width: digitBoxSize, height: labelHeight)
            label.font = NSFont.monospacedDigitSystemFont(ofSize: 18, weight: .semibold)
            label.textColor = DS.Colors.foreground
            label.alignment = .center
            box.addSubview(label)
            digitLabels.append(label)
        }

        updateDigitDisplay()
        return container
    }

    func enterDigit(_ digit: Int) {
        guard currentIndex < 4 else { return }
        digits[currentIndex] = digit
        updateDigitDisplay()
        if currentIndex == 4 {
            let pin = digits.compactMap { $0 }.map(String.init).joined()
            manager.submitPIN(pin)
        }
    }

    func backspace() {
        let idx = currentIndex - 1
        guard idx >= 0 else { return }
        digits[idx] = nil
        updateDigitDisplay()
    }

    private func updateDigitDisplay() {
        for (i, label) in digitLabels.enumerated() {
            label.stringValue = digits[i].map(String.init) ?? ""
        }
        for (i, box) in digitBoxes.enumerated() {
            if let digitBox = box as? DigitBoxView {
                digitBox.isFocused = i == currentIndex
                digitBox.needsDisplay = true
            }
        }
    }
}

// MARK: - Digit box

private final class DigitBoxView: NSView {

    var bgColor: NSColor = .gray
    var borderColor: NSColor = .darkGray
    var focusBorderColor: NSColor = .black
    var isFocused = false

    override func draw(_ dirtyRect: NSRect) {
        bgColor.setFill()
        let path = NSBezierPath(roundedRect: bounds, xRadius: DS.Radius.md, yRadius: DS.Radius.md)
        path.fill()

        let strokeColor = isFocused ? focusBorderColor : borderColor
        strokeColor.setStroke()
        let strokePath = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: DS.Radius.md, yRadius: DS.Radius.md)
        strokePath.lineWidth = 2
        strokePath.stroke()
    }
}

// MARK: - Itsyhome promo banner

private final class ItsyhomePromoView: HighlightingMenuItemView {

    private var isHovered = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        onMouseEnter = { [weak self] in self?.isHovered = true }
        onMouseExit = { [weak self] in self?.isHovered = false }
        setupContent()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupContent() {
        let width = bounds.width
        let height = bounds.height
        let insetX: CGFloat = 4
        let insetRect = NSRect(x: insetX, y: 0, width: width - insetX * 2, height: height)

        // Icon
        let iconSize: CGFloat = 32
        let iconX = insetRect.minX + DS.Spacing.md
        let iconY = (height - iconSize) / 2
        let iconView = NSImageView(frame: NSRect(x: iconX, y: iconY, width: iconSize, height: iconSize))
        iconView.image = Bundle.main.image(forResource: "itsyhome-icon")
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 6
        iconView.layer?.masksToBounds = true
        addSubview(iconView)

        // Title
        let textX = iconX + iconSize + DS.Spacing.sm
        let chevronSize: CGFloat = 10
        let textMaxWidth = insetRect.maxX - textX - DS.Spacing.md - chevronSize - DS.Spacing.xs
        let titleLabel = NSTextField(labelWithString: "HomeKit in menu bar")
        titleLabel.frame = NSRect(x: textX, y: height / 2 + 1, width: textMaxWidth, height: 17)
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        // Subtitle
        let subtitleLabel = NSTextField(labelWithString: "Try Itsyhome – it's free")
        subtitleLabel.frame = NSRect(x: textX, y: height / 2 - 16, width: textMaxWidth, height: 15)
        subtitleLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.75)
        subtitleLabel.lineBreakMode = .byTruncatingTail
        addSubview(subtitleLabel)

        // Chevron
        let chevronX = insetRect.maxX - DS.Spacing.md - chevronSize
        let chevronY = (height - chevronSize) / 2
        let chevronView = NSImageView(frame: NSRect(x: chevronX, y: chevronY, width: chevronSize, height: chevronSize))
        chevronView.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
        chevronView.contentTintColor = NSColor.white.withAlphaComponent(0.75)
        chevronView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(chevronView)
    }

    override func draw(_ dirtyRect: NSRect) {
        let insetRect = bounds.insetBy(dx: 4, dy: 0)

        if isHovered {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: insetRect, xRadius: 4, yRadius: 4).fill()
        } else {
            let gradient = NSGradient(
                starting: DS.Colors.promoGradientStart,
                ending: DS.Colors.promoGradientEnd
            )
            gradient?.draw(in: NSBezierPath(roundedRect: insetRect, xRadius: 6, yRadius: 6), angle: 0)
        }
    }
}

// MARK: - Pairing container (captures keyboard)

private final class PairingContainerView: NSView {

    var onDigit: ((Int) -> Void)?
    var onBackspace: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    init(frame: NSRect, onDigit: @escaping (Int) -> Void, onBackspace: @escaping () -> Void) {
        self.onDigit = onDigit
        self.onBackspace = onBackspace
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            DispatchQueue.main.async { [weak self] in
                self?.window?.makeFirstResponder(self)
            }
        }
    }

    override func keyDown(with event: NSEvent) {
        guard let chars = event.characters else { return }
        for ch in chars {
            if let digit = ch.wholeNumberValue {
                onDigit?(digit)
            } else if ch == "\u{7F}" || ch == "\u{08}" {
                onBackspace?()
            }
        }
    }
}

// MARK: - Close button (X)

private final class CloseButton: NSView {

    var onPress: (() -> Void)?
    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            enclosingMenuItem?.menu?.cancelTracking()
            onPress?()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        // Circle background
        let circleBg: NSColor = isHovered
            ? DS.Colors.muted
            : DS.Colors.secondary
        circleBg.setFill()
        NSBezierPath(ovalIn: bounds).fill()

        // X mark
        let inset: CGFloat = 6
        let path = NSBezierPath()
        path.move(to: NSPoint(x: inset, y: inset))
        path.line(to: NSPoint(x: bounds.width - inset, y: bounds.height - inset))
        path.move(to: NSPoint(x: bounds.width - inset, y: inset))
        path.line(to: NSPoint(x: inset, y: bounds.height - inset))
        path.lineWidth = 1.5
        path.lineCapStyle = .round
        DS.Colors.mutedForeground.setStroke()
        path.stroke()
    }
}
