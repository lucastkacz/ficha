import Carbon.HIToolbox
import Observation
import SwiftUI
import os

private let logger = Logger(subsystem: "com.lucastkacz.ficha", category: "capture shortcut")

/// A keyboard shortcut that opens "Capture…" from any app: a letter key with
/// modifiers.
struct CaptureShortcut {
    /// The key, as the system's hot keys name it: a virtual key code.
    let keyCode: UInt32
    /// The modifier keys, as the system's hot keys name them.
    let carbonModifiers: UInt32
    /// The same shortcut, as a menu shows it next to "Capture…".
    let keyboardShortcut: KeyboardShortcut
    /// The shortcut in symbols, like "⌃⌥⌘C", for the debug menu and the log.
    let symbols: String

    /// The real Ficha's: ⌃⌥⌘C, which common apps and macOS leave free.
    static let ficha = CaptureShortcut("c", keyCode: kVK_ANSI_C, modifiers: [.control, .option, .command])

    /// The one Ficha Dev's debug menu turns on: ⌃⌥⇧⌘C, so it never takes the
    /// real Ficha's and both apps can run side by side.
    static let fichaDev = CaptureShortcut("c", keyCode: kVK_ANSI_C, modifiers: [.control, .option, .shift, .command])

    /// The shortcut of `key`, whose virtual key code is `keyCode`, with
    /// `modifiers`, each as the system's hot keys, a menu and the symbols
    /// name it.
    private init(_ key: Character, keyCode: Int, modifiers: SwiftUI.EventModifiers) {
        let named = modifierNames.filter { modifiers.contains($0.modifier) }
        self.keyCode = UInt32(keyCode)
        carbonModifiers = named.reduce(0) { $0 | UInt32($1.carbon) }
        keyboardShortcut = KeyboardShortcut(KeyEquivalent(key), modifiers: modifiers)
        symbols = named.map(\.symbol).joined() + key.uppercased()
    }
}

/// Each modifier key, in the order macOS writes them, as SwiftUI, the
/// system's hot keys and its symbol name it.
private let modifierNames: [(modifier: SwiftUI.EventModifiers, carbon: Int, symbol: String)] = [
    (.control, controlKey, "⌃"), (.option, optionKey, "⌥"), (.shift, shiftKey, "⇧"), (.command, cmdKey, "⌘"),
]

extension AppVariant {
    /// The shortcut the app opens "Capture…" with from launch: the real
    /// Ficha's, and none in Ficha Dev, until its debug menu turns one on.
    var captureShortcut: CaptureShortcut? {
        switch self {
        case .dev: nil
        case .real: .ficha
        }
    }
}

/// The shortcut that opens "Capture…" from any app, while one is on. It's one
/// of the system's hot keys (`RegisterEventHotKey`), which needs no permission:
/// the app gets only that shortcut, never the other keys Lucas types. It lives
/// as long as the app.
@Observable
final class CaptureShortcutRegistration {
    /// The shortcut that's on, or nil.
    private(set) var shortcut: CaptureShortcut?
    /// What the shortcut does: opens "Capture…".
    @ObservationIgnored var whenPressed: () -> Void = {}
    @ObservationIgnored private var hotKey: EventHotKeyRef?
    @ObservationIgnored private var handlerIsInstalled = false

    /// Turns `shortcut` on, instead of the one that was on, if any. It fails
    /// when another app has it.
    func turnOn(_ shortcut: CaptureShortcut) throws(CaptureShortcutError) {
        turnOff()
        try installHandler()
        var hotKey: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode, shortcut.carbonModifiers, EventHotKeyID(signature: hotKeySignature, id: 1),
            GetApplicationEventTarget(), 0, &hotKey)
        guard status == noErr, let hotKey else {
            logger.error("Couldn't turn on the capture shortcut: \(status, privacy: .public)")
            throw status == OSStatus(eventHotKeyExistsErr) ? .taken : .failed(status)
        }
        self.hotKey = hotKey
        self.shortcut = shortcut
        logger.info("Turned on the capture shortcut \(shortcut.symbols, privacy: .public)")
    }

    /// Turns the shortcut off, if one is on.
    func turnOff() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
        }
        hotKey = nil
        shortcut = nil
    }

    /// Has the system tell this registration when its shortcut is pressed,
    /// once. The registration lives as long as the app, so the handler never
    /// outlives it.
    private func installHandler() throws(CaptureShortcutError) {
        guard !handlerIsInstalled else { return }
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(), shortcutPressed, 1, &pressed, Unmanaged.passUnretained(self).toOpaque(), nil)
        guard status == noErr else {
            logger.error("Couldn't listen for the capture shortcut: \(status, privacy: .public)")
            throw .failed(status)
        }
        handlerIsInstalled = true
    }
}

/// Why the capture shortcut couldn't be turned on. Each message says what to
/// do about it.
enum CaptureShortcutError: LocalizedError {
    /// Another app has the shortcut.
    case taken
    /// The system refused it, with this status.
    case failed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .taken:
            String(
                localized: "Another app already uses this shortcut. Quit it, or turn its shortcut off, and try again.")
        case .failed(let status):
            String(
                localized: """
                    macOS refused the shortcut (error \(status)). Restart the app, and if it keeps failing, report \
                    it.
                    """)
        }
    }
}

/// The hot key's signature, which names it as Ficha's: "Fcha".
private let hotKeySignature: OSType = 0x4663_6861

/// Opens "Capture…" when the system says the shortcut was pressed. The system
/// calls it on the main thread, with the registration as `userData`.
private nonisolated func shortcutPressed(
    _ call: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else {
        return OSStatus(eventNotHandledErr)
    }
    let registration = Unmanaged<CaptureShortcutRegistration>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated {
        registration.whenPressed()
    }
    return noErr
}
