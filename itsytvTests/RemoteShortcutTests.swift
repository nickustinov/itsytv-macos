import XCTest
import Carbon.HIToolbox

final class RemoteShortcutTests: XCTestCase {
    private var defaults: UserDefaults!
    private var settings: ShortcutSettings!
    private let suite = "RemoteShortcutTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
        settings = ShortcutSettings(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func keys(_ keyCode: Int, _ modifiers: NSEvent.ModifierFlags = []) -> ShortcutKeys {
        ShortcutKeys(modifiers: modifiers.rawValue, keyCode: UInt16(keyCode))
    }

    // MARK: - Matching

    func testDefaultKeysMatchTheirShortcuts() {
        XCTAssertEqual(RemoteShortcut.match(keys(kVK_Escape), settings: settings), .back)
        XCTAssertEqual(RemoteShortcut.match(keys(kVK_Return), settings: settings), .select)
        XCTAssertEqual(RemoteShortcut.match(keys(kVK_ANSI_W, .command), settings: settings), .close)
        XCTAssertEqual(RemoteShortcut.match(keys(kVK_ANSI_M, [.command, .shift]), settings: settings), .mute)
    }

    func testModifiersMustMatchExactly() {
        XCTAssertNil(RemoteShortcut.match(keys(kVK_UpArrow, .shift), settings: settings))
        XCTAssertNil(RemoteShortcut.match(keys(kVK_ANSI_W, [.command, .option]), settings: settings))
    }

    func testCommandHClosesTheRemoteWhileCloseKeepsItsDefault() {
        XCTAssertEqual(RemoteShortcut.match(keys(kVK_ANSI_H, .command), settings: settings), .close)
        settings.set(keys(kVK_F5), for: .close)
        XCTAssertNil(RemoteShortcut.match(keys(kVK_ANSI_H, .command), settings: settings))
    }

    func testKeysFromAnEventIgnoreCapsLockFunctionAndNumericPad() throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.capsLock, .function, .numericPad],
            timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: UInt16(kVK_UpArrow)))
        XCTAssertEqual(ShortcutKeys(event: event), keys(kVK_UpArrow))
    }

    // MARK: - Custom keys

    func testNewKeysAreUsedAndRemembered() {
        settings.set(keys(kVK_F5), for: .back)
        XCTAssertEqual(settings.keys(for: .back), keys(kVK_F5))
        XCTAssertTrue(settings.isCustomized(.back))
        XCTAssertEqual(ShortcutSettings(defaults: defaults).keys(for: .back), keys(kVK_F5))
    }

    func testTakingAnotherShortcutsKeysSwapsThem() {
        settings.set(keys(kVK_Delete), for: .back)
        XCTAssertEqual(settings.keys(for: .back), keys(kVK_Delete))
        XCTAssertEqual(settings.keys(for: .home), keys(kVK_Escape))
        XCTAssertEqual(RemoteShortcut.match(keys(kVK_Escape), settings: settings), .home)
    }

    func testGoingBackToTheDefaultKeysClearsTheOverride() {
        settings.set(keys(kVK_F5), for: .back)
        settings.set(keys(kVK_Escape), for: .back)
        XCTAssertFalse(settings.isCustomized(.back))
        XCTAssertFalse(settings.hasCustomizations)
        XCTAssertNil(defaults.object(forKey: "customRemoteShortcuts"))
    }

    func testRestoringOneShortcutTakesItsKeysBack() {
        settings.set(keys(kVK_F5), for: .back)
        settings.set(keys(kVK_Escape), for: .home)
        settings.reset(.back)
        XCTAssertEqual(settings.keys(for: .back), keys(kVK_Escape))
        XCTAssertEqual(settings.keys(for: .home), keys(kVK_F5))
    }

    func testRestoreAllForgetsEveryOverride() {
        settings.set(keys(kVK_F5), for: .back)
        settings.set(keys(kVK_F6), for: .mute)
        settings.resetAll()
        XCTAssertFalse(settings.hasCustomizations)
        XCTAssertEqual(settings.keys(for: .back), keys(kVK_Escape))
        XCTAssertNil(defaults.object(forKey: "customRemoteShortcuts"))
    }

    // MARK: - Recording new keys

    func testEscCancelsRecording() {
        XCTAssertEqual(ShortcutRecording(keys(kVK_Escape)), .cancel)
    }

    func testCommandQStillQuitsWhileRecording() {
        XCTAssertEqual(ShortcutRecording(keys(kVK_ANSI_Q, .command)), .passThrough)
    }

    func testOtherKeysAreRecorded() {
        XCTAssertEqual(ShortcutRecording(keys(kVK_ANSI_W, .command)), .record(keys(kVK_ANSI_W, .command)))
        XCTAssertEqual(ShortcutRecording(keys(kVK_Escape, .shift)), .record(keys(kVK_Escape, .shift)))
    }

    // MARK: - Key names

    func testKeyNamesFollowTheKeycaps() {
        XCTAssertEqual(ShortcutKeys.caps(keys(kVK_Escape)), ["esc"])
        XCTAssertEqual(ShortcutKeys.caps(keys(kVK_Space)), ["space"])
        XCTAssertEqual(ShortcutKeys.caps(keys(kVK_UpArrow)), ["↑"])
        XCTAssertEqual(ShortcutKeys.caps(keys(kVK_ANSI_M, [.command, .shift])), ["⇧", "⌘", "M"])
    }

    func testTheGlobalHotkeyUsesTheSameNames() {
        XCTAssertEqual(keys(kVK_Space, [.control, .option]).displayString, "⌃⌥space")
        XCTAssertEqual(keys(kVK_Escape, .command).displayString, "⌘esc")
    }
}
