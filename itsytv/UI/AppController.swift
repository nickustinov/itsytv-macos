import AppKit
import SwiftUI
import Combine

final class AppController: NSObject, NSMenuDelegate {

    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let menu = NSMenu()
    private let manager: AppleTVManager
    private let iconLoader: AppIconLoader
    private var observation: AnyCancellable?
    private var panel: NSPanel?
    private var keyboardMonitor: Any?

    init(manager: AppleTVManager, iconLoader: AppIconLoader) {
        self.manager = manager
        self.iconLoader = iconLoader
        super.init()
        setupStatusItem()
        rebuildMenu()
        startObserving()
        manager.startScanning()
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

    private func handleStateChange() {
        let currentStatus = manager.connectionStatus
        let currentDeviceCount = manager.discoveredDevices.count

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
            if panel == nil {
                menu.cancelTracking()
            }
            showPanel()
        }
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
            return
        }

        switch manager.connectionStatus {
        case .pairing, .connecting:
            break
        default:
            menu.addItem(NSMenuItem.separator())
            let quitItem = createActionItem(title: "Quit") { [weak self] in
                NSApplication.shared.terminate(nil)
            }
            menu.addItem(quitItem)
        }
    }

    private func buildDeviceList() {
        if manager.discoveredDevices.isEmpty {
            let scanning = NSMenuItem(title: "Scanning for devices...", action: nil, keyEquivalent: "")
            scanning.isEnabled = false
            menu.addItem(scanning)
        } else {
            let sorted = manager.discoveredDevices.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            for device in sorted {
                let isPaired = KeychainStorage.load(for: device.id) != nil
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

        // Icon
        let iconSize = DS.ControlSize.iconMedium
        let iconY = (height - iconSize) / 2
        let iconView = NSImageView(frame: NSRect(x: DS.Spacing.md, y: iconY, width: iconSize, height: iconSize))
        iconView.image = NSImage(systemSymbolName: "appletv.fill", accessibilityDescription: nil)
        iconView.contentTintColor = DS.Colors.iconForeground
        iconView.imageScaling = .scaleProportionallyUpOrDown
        containerView.addSubview(iconView)

        // "PAIRED" badge (right-aligned)
        var labelRightEdge = width - DS.Spacing.md
        if isPaired {
            let badgeFont = NSFont.systemFont(ofSize: 9, weight: .medium)
            let badgeAttr = NSAttributedString(string: "PAIRED", attributes: [.font: badgeFont])
            let badgeTextSize = badgeAttr.size()
            let badgePadH: CGFloat = 5
            let badgePadV: CGFloat = 2
            let badgeW = badgeTextSize.width + badgePadH * 2
            let badgeH = badgeTextSize.height + badgePadV * 2
            let badgeX = width - DS.Spacing.md - badgeW
            let badgeY = (height - badgeH) / 2

            let badge = PairedBadgeView(frame: NSRect(x: badgeX, y: badgeY, width: badgeW, height: badgeH))
            containerView.addSubview(badge)
            labelRightEdge = badgeX - DS.Spacing.xs
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
            self?.manager.connect(to: device)
            if isPaired {
                self?.showPanel()
            }
        }

        let item = NSMenuItem(title: device.name, action: nil, keyEquivalent: "")
        item.view = containerView
        return item
    }

    private func createActionItem(title: String, action: @escaping () -> Void) -> NSMenuItem {
        let height = DS.ControlSize.menuItemHeight
        let width = DS.ControlSize.menuItemWidth

        let containerView = HighlightingMenuItemView(frame: NSRect(x: 0, y: 0, width: width, height: height))

        let labelX = DS.Spacing.md
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

    // MARK: - Panel

    private func showPanel() {
        if let existing = panel {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
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
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.hasShadow = true

        if let buttonFrame = statusItem.button?.window?.frame {
            let x = buttonFrame.midX - 88
            let y = buttonFrame.minY - panel.frame.height
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.panel = panel
        installKeyboardMonitor()
    }

    private func dismissPanel() {
        removeKeyboardMonitor()
        panel?.close()
        panel = nil
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
        // Ignore when a text field is focused
        if let responder = panel?.firstResponder, responder is NSTextView {
            return false
        }
        switch event.keyCode {
        case 126: manager.pressButton(.up); return true       // ↑
        case 125: manager.pressButton(.down); return true     // ↓
        case 123: manager.pressButton(.left); return true     // ←
        case 124: manager.pressButton(.right); return true    // →
        case 36:  manager.pressButton(.select); return true   // Return
        case 51:  manager.pressButton(.menu); return true     // Backspace
        case 53:  manager.pressButton(.home); return true     // Escape
        case 49:  manager.pressButton(.playPause); return true // Space
        default:  return false
        }
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        if manager.connectionStatus == .disconnected {
            rebuildMenu()
        }
    }
}

// MARK: - Panel SwiftUI content

// MARK: - Key-capable panel

private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
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
            if manager.connectionStatus != .disconnected {
                manager.disconnect()
            }
            panel = nil
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

// MARK: - Paired badge

private final class PairedBadgeView: NSView {

    override func draw(_ dirtyRect: NSRect) {
        let bg = NSColor(name: nil) { $0.isDark ? NSColor(white: 0.30, alpha: 1) : NSColor(white: 0.85, alpha: 1) }
        let fg = DS.Colors.mutedForeground

        bg.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 3, yRadius: 3).fill()

        let font = NSFont.systemFont(ofSize: 9, weight: .medium)
        let str = NSAttributedString(string: "PAIRED", attributes: [
            .font: font,
            .foregroundColor: fg,
        ])
        let size = str.size()
        let x = (bounds.width - size.width) / 2
        let y = (bounds.height - size.height) / 2
        str.draw(at: NSPoint(x: x, y: y))
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
