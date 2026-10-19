import Carbon.HIToolbox
import Observation
import SwiftUI
import os

private let logger = Logger(subsystem: "com.lucastkacz.ficha", category: "capture shortcut")

/// A keyboard shortcut that opens "Capture…" from any app: a key with
/// modifiers, Command, Control or Option among them, so it never takes a key
/// Lucas types.
struct CaptureShortcut: Equatable {
    /// The key, as the system's hot keys name it: a virtual key code.
    let keyCode: UInt32
    /// What the key types without modifiers, in lowercase, as a menu shows it.
    let key: Character
    /// The modifier keys: Control, Option, Shift and Command, and no others.
    let modifiers: SwiftUI.EventModifiers

    /// The real Ficha's: ⌃⌥⌘C, which common apps and macOS leave free.
    static let ficha = CaptureShortcut(checkedKey: "c", keyCode: kVK_ANSI_C, modifiers: [.control, .option, .command])

    /// The one Ficha Dev's debug menu turns on: ⌃⌥⇧⌘C, so it never takes the
    /// real Ficha's and both apps can run side by side.
    static let fichaDev = CaptureShortcut(
        checkedKey: "c", keyCode: kVK_ANSI_C, modifiers: [.control, .option, .shift, .command])

    /// The shortcut of the key that types `key` without modifiers, whose
    /// virtual key code is `keyCode`, with `modifiers`, or nil unless `key` is
    /// a letter, a digit, a punctuation mark or a symbol and `modifiers` holds
    /// Command, Control or Option. Modifiers other than those and Shift are
    /// left out.
    init?(key: Character, keyCode: Int, modifiers: SwiftUI.EventModifiers) {
        let key = Character(key.lowercased())
        let modifiers = modifiers.intersection([.control, .option, .shift, .command])
        guard
            key.isLetter || key.isNumber || key.isPunctuation || key.isSymbol,
            !modifiers.isDisjoint(with: [.control, .option, .command]),
            let keyCode = UInt32(exactly: keyCode)
        else {
            return nil
        }
        self.key = key
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// A shortcut whose key and modifiers are known to make one.
    private init(checkedKey key: Character, keyCode: Int, modifiers: SwiftUI.EventModifiers) {
        self.key = key
        self.keyCode = UInt32(keyCode)
        self.modifiers = modifiers
    }

    /// The modifier keys, as the system's hot keys name them.
    var carbonModifiers: UInt32 {
        modifierNames.filter { modifiers.contains($0.modifier) }.reduce(0) { $0 | UInt32($1.carbon) }
    }

    /// The same shortcut, as a menu shows it next to "Capture…".
    var keyboardShortcut: KeyboardShortcut {
        KeyboardShortcut(KeyEquivalent(key), modifiers: modifiers)
    }

    /// The shortcut in symbols, like "⌃⌥⌘C", for Settings, the debug menu and
    /// the log.
    var symbols: String {
        modifierNames.filter { modifiers.contains($0.modifier) }.map(\.symbol).joined() + key.uppercased()
    }
}

extension CaptureShortcut {
    /// The shortcut as the app's preferences store it: its key, its key code
    /// and its modifiers' names.
    var stored: [String: Any] {
        [
            "key": String(key), "keyCode": Int(keyCode),
            "modifiers": modifierNames.filter { modifiers.contains($0.modifier) }.map(\.name),
        ]
    }

    /// The shortcut the preferences stored as `stored`, or nil when that
    /// doesn't make one.
    init?(stored: [String: Any]) {
        guard
            let key = stored["key"] as? String, key.count == 1, let character = key.first,
            let keyCode = stored["keyCode"] as? Int,
            let names = stored["modifiers"] as? [String]
        else {
            return nil
        }
        let modifiers = names.compactMap { name in modifierNames.first { $0.name == name }?.modifier }
        guard modifiers.count == names.count else {
            return nil
        }
        self.init(key: character, keyCode: keyCode, modifiers: SwiftUI.EventModifiers(modifiers))
    }
}

/// Each modifier key, in the order macOS writes them, as SwiftUI, the
/// system's hot keys, its symbol and the app's preferences name it.
private let modifierNames: [(modifier: SwiftUI.EventModifiers, carbon: Int, symbol: String, name: String)] = [
    (.control, controlKey, "⌃", "control"), (.option, optionKey, "⌥", "option"), (.shift, shiftKey, "⇧", "shift"),
    (.command, cmdKey, "⌘", "command"),
]

extension AppVariant {
    /// The shortcut the app opens "Capture…" with until Lucas picks another
    /// in Settings: the real Ficha's, and none in Ficha Dev.
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

    /// Turns `shortcut` on in place of the one that's on, or turns that one
    /// off when it's nil, and keeps it in the app's preferences for the next
    /// launches. When macOS refuses it, `fallback` is turned on instead, as
    /// it was, and the error says why.
    func change(to shortcut: CaptureShortcut?, fallback: CaptureShortcut?) throws(CaptureShortcutError) {
        guard let shortcut else {
            turnOff()
            Preferences.captureShortcut = nil
            return
        }
        do {
            try turnOn(shortcut)
        } catch {
            if let fallback {
                do {
                    try turnOn(fallback)
                } catch {
                    // `turnOn` logged why; the error Lucas sees is the new
                    // shortcut's.
                }
            }
            throw error
        }
        Preferences.captureShortcut = shortcut
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
                localized: """
                    Another app already uses this shortcut. Pick another in Settings, or quit that app, or turn its \
                    shortcut off, and try again.
                    """)
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
