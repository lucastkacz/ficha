import AppKit
import Carbon.HIToolbox
import FichaCore
import FichaData

// Draws one of the app's windows as a PNG, with Ficha Dev's sample cards,
// without showing anything on screen: `make render ARGS="cards --dark"`. The
// window goes below the desktop picture, where macOS still draws it but nobody
// sees it and nothing takes the mouse or the keyboard; the tool clicks, presses
// keys and types in it where it's told, as Lucas would, and captures it with
// `screencapture`. `docs/development.md` explains how to use it.
//
// This file shares its module with `App/`'s files, which the target compiles
// through `Sources/Render/App`, so a top-level name here that `App/` also uses
// breaks the build, even when `App/`'s is `private`: in #116, a `modifierNames`
// table here broke `CaptureShortcut.swift`. Give what you add at the top level
// a name of its own.

/// A window the tool can draw, by the name its arguments give it.
enum Window: String {
    case cards
    /// Settings, on its Backups tab.
    case backups
    /// Settings, on its Backups tab, once a backup failed.
    case backupsFailed = "backups-failed"
}

/// What the tool was asked to draw.
struct Request {
    var window: Window?
    var isDark = false
    /// What to do in the window before the capture, in order.
    var actions: [Action] = []
    /// Where the PNG goes.
    var output: URL?
}

/// Something the tool does in the window before the capture, as Lucas would.
enum Action: CustomStringConvertible {
    /// A click, with its modifier keys held down.
    case click(MouseClick)
    /// A key, pressed with its modifier keys held down.
    case key(KeyPress)
    /// Text, typed into what holds the focus.
    case type(String)

    /// The action as its arguments ask for it, like `--key cmd+f`.
    var description: String {
        switch self {
        case .click(let mouseClick): "--click \(mouseClick.name)"
        case .key(let press): "--key \(press.name)"
        case .type(let text): "--type \"\(text)\""
        }
    }
}

/// A click, with the modifier keys held down, like `cmd+280,121`.
struct MouseClick {
    /// The click as its arguments name it.
    let name: String
    /// Where, in points from the window's top-left corner.
    let point: CGPoint
    let modifiers: NSEvent.ModifierFlags
}

/// A press of a key, with the modifier keys held down, like `cmd+f`.
struct KeyPress {
    /// The press as its arguments name it.
    let name: String
    let modifiers: NSEvent.ModifierFlags
    /// The key's code on a US keyboard, one of Carbon's `kVK_` constants.
    let code: Int
    /// The letter or digit the key types on a US keyboard, which the Mac's
    /// keyboard layout must type too, or nil for a key that types the same in
    /// every layout, like Return.
    let character: String?
}

/// The letters and digits the tool presses, with their keys' codes on a US
/// keyboard.
let characterKeyCodes = [
    "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F,
    "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
    "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R,
    "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
    "y": kVK_ANSI_Y, "z": kVK_ANSI_Z, "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
    "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
]

/// The other keys the tool presses, by name, with their keys' codes. Each one
/// types the same in every keyboard layout.
let namedKeys = [
    "return": kVK_Return, "escape": kVK_Escape, "tab": kVK_Tab, "space": kVK_Space, "delete": kVK_Delete,
]

/// The modifier keys the tool holds down for a key or a click, by name.
/// Option and Control are left out: what a key types with them depends on the
/// keyboard, and no window's shortcut uses them.
let modifiersByName: [String: NSEvent.ModifierFlags] = ["cmd": .command, "shift": .shift]

/// The Edit menu's items that have a shortcut, as SwiftUI gives them to the
/// app on macOS 26: each one's title, action, key and the modifier keys held
/// for it. It's our own copy, since the tool doesn't run the app's `App`, so a
/// command the app adds with `.commands` needs adding here too. What AppKit
/// adds to the app's menu, like Emoji & Symbols, stays out: its shortcuts take
/// Control or fn, which the tool doesn't press, and open the system's windows.
let editMenuItems: [(title: String, action: String, key: String, modifiers: NSEvent.ModifierFlags)] = [
    ("Undo", "undo:", "z", .command), ("Redo", "redo:", "z", [.shift, .command]), ("Cut", "cut:", "x", .command),
    ("Copy", "copy:", "c", .command), ("Paste", "paste:", "v", .command), ("Select All", "selectAll:", "a", .command),
]

/// The level below the desktop picture, where macOS still draws a window but
/// nobody sees it: the window's, and each sheet's it opens.
let belowDesktop = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)

/// A request the tool can't draw, with what to do about it.
struct RenderError: Error, CustomStringConvertible {
    let description: String
}

/// What to do when AppKit or the Objective-C runtime refuses what the tool
/// asks, which they don't on the macOS the tool was written for.
let whenMacOSRefuses = "This doesn't fail on macOS 26, which the tool was written for: open an issue with this message."

let usage = """
    Usage: make render ARGS="<window> [--dark] [--click <point> | --key <keys> | --type <text>]... [--out <file.png>]"
      <window>   cards, backups (Settings, on its Backups tab) or backups-failed (once a backup failed)
      --dark     dark mode instead of light
      --click    a click, in points from the window's top-left corner, after the modifiers held down: 280,121,
                 cmd+280,121, shift+280,145; on a row of a table or the sidebar, a column header, or a sheet
      --key      a key, after the modifiers held down: cmd+f, cmd+a, escape, return, shift+tab
                 keys: a-z, 0-9, return, escape, tab, space, delete; modifiers: cmd, shift
      --type     text typed into what holds the focus, like a text field
      --out      the PNG, by default .build/render/<window>-<light|dark>.png
    --click, --key and --type run in the order given, and after each one the tool prints what holds the focus.
    While the window has a sheet, an alert or a confirmation open, they go to it.
    """

/// Splits the modifier keys held down off `name`, an argument of `option`:
/// for `--key cmd+f`, Command and `f`.
func splitModifiers(off name: String, in option: String) throws(RenderError) -> (NSEvent.ModifierFlags, String) {
    var parts = name.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
    let rest = parts.popLast() ?? ""
    var modifiers: NSEvent.ModifierFlags = []
    for part in parts {
        guard let modifier = modifiersByName[part] else {
            throw RenderError(description: "Unknown modifier \(part) in \(option) \(name).\n\(usage)")
        }
        modifiers.insert(modifier)
    }
    return (modifiers, rest)
}

/// The press `name` names, like `cmd+f` or `escape`.
func keyPress(named name: String) throws(RenderError) -> KeyPress {
    let (modifiers, key) = try splitModifiers(off: name, in: "--key")
    guard !key.isEmpty else {
        throw RenderError(description: "--key takes a key after its modifiers, like cmd+f or escape.\n\(usage)")
    }
    if let code = namedKeys[key] {
        return KeyPress(name: name, modifiers: modifiers, code: code, character: nil)
    }
    guard let code = characterKeyCodes[key] else {
        throw RenderError(description: "Unknown key \(key) in --key \(name).\n\(usage)")
    }
    guard !modifiers.contains(.shift) || key.allSatisfy(\.isLetter) else {
        throw RenderError(
            description: "--key \(name): Shift with a digit types a symbol that depends on the keyboard.\n\(usage)")
    }
    return KeyPress(name: name, modifiers: modifiers, code: code, character: key)
}

/// The click `name` names, like `280,121` or `cmd+280,121`.
func mouseClick(named name: String) throws(RenderError) -> MouseClick {
    let (modifiers, point) = try splitModifiers(off: name, in: "--click")
    let coordinates = point.split(separator: ",", omittingEmptySubsequences: false)
    let numbers = coordinates.compactMap { Double($0) }
    guard coordinates.count == 2, numbers.count == 2 else {
        throw RenderError(
            description: """
                --click takes a point as <x>,<y>, after the modifiers held down, like 300,120 or cmd+300,120.
                \(usage)
                """)
    }
    return MouseClick(name: name, point: CGPoint(x: numbers[0], y: numbers[1]), modifiers: modifiers)
}

/// The request in the tool's arguments.
func request(from arguments: [String]) throws(RenderError) -> Request {
    var request = Request()
    var arguments = arguments[...]
    while let argument = arguments.popFirst() {
        switch argument {
        case "--dark":
            request.isDark = true
        case "--click":
            request.actions.append(.click(try mouseClick(named: arguments.popFirst() ?? "")))
        case "--key":
            request.actions.append(.key(try keyPress(named: arguments.popFirst() ?? "")))
        case "--type":
            guard let text = arguments.popFirst(), !text.isEmpty else {
                throw RenderError(description: "--type takes the text to type.\n\(usage)")
            }
            request.actions.append(.type(text))
        case "--out":
            guard let path = arguments.popFirst() else {
                throw RenderError(description: "--out takes the PNG's path.\n\(usage)")
            }
            request.output = URL(filePath: path)
        case _ where request.window == nil && !argument.hasPrefix("-"):
            guard let window = Window(rawValue: argument) else {
                throw RenderError(description: "Unknown window \(argument).\n\(usage)")
            }
            request.window = window
        default:
            throw RenderError(description: "Unknown argument \(argument).\n\(usage)")
        }
    }
    return request
}

/// An engine at `location` with Ficha Dev's sample cards, as Lucas would have
/// them after twelve days of reviews, starting on 8 October 2026: twenty met
/// the first day and climbing at different paces, two sent back to the first
/// step, one flagged with a note and one buried, and the rest new, with a
/// capture waiting in the inbox; and then two new cards made by hand, with no
/// type and no capture. The time it's on stays where the twelve days left it.
func sampleEngine(at location: DatabaseLocation) throws -> (engine: Engine, time: ManualTimeSource) {
    var calendar = Calendar(identifier: .gregorian)
    guard let buenosAires = TimeZone(identifier: "America/Argentina/Buenos_Aires") else {
        throw RenderError(description: "This Mac doesn't know Buenos Aires's time zone.")
    }
    calendar.timeZone = buenosAires
    guard let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 9)) else {
        throw RenderError(description: "Couldn't make the sample's start date.")
    }
    let time = ManualTimeSource(now: start)
    let engine = try Engine(location: location, time: time, calendar: calendar)
    let settings = ReviewSettings.defaults
    try SampleCards.load(into: engine)
    let cards = try engine.cards()

    /// Reviews the cards in `range` that are due with `rating`.
    func review(_ range: Range<Int>, _ rating: Rating) throws {
        for card in cards[range] where try engine.standing(of: card.id, on: settings.ladder).isDue(at: time.now) {
            try engine.record(
                .review(rating), of: card.id, responseTime: .seconds(3), trigger: .reviewNow, settings: settings)
        }
    }

    for card in cards[0..<20] {
        try engine.record(.firstView, of: card.id, responseTime: .seconds(8), trigger: .reviewNow, settings: settings)
    }
    time.advance(by: hours(1))
    try review(0..<18, .good)
    time.advance(by: hours(4))
    try review(0..<16, .good)
    try review(16..<18, .hard)
    time.advance(by: hours(2 * 24))
    try review(0..<12, .good)
    try review(12..<14, .again)
    time.advance(by: hours(5 * 24))
    try review(0..<8, .good)
    // A capture that waits in the inbox, for Convert to Card: the inbox lists
    // it after the flagged card, which comes later.
    let capture = try engine.capture(
        text: "La paradoja de Teseo: si le cambiás todas las tablas a un barco, ¿sigue siendo el mismo barco?",
        note: "Una tarjeta para la paradoja y otra para la pregunta", source: "Un video de filosofía")
    guard case .saved = capture else {
        throw RenderError(description: "The sample's capture repeats a sample card.")
    }
    time.advance(by: hours(4 * 24 + 3))
    guard let note = FlagNote("El ejemplo no se entiende: cambiarlo por uno más cotidiano.") else {
        throw RenderError(description: "The sample's flag note is blank.")
    }
    try engine.flag(cards[2].id, note: note)
    try engine.bury(cards[5].id)
    // The sample cards all have a type, and cards from a capture: these two
    // are as someone who doesn't refine with Claude makes them.
    let madeByHand = [
        ("¿Cuál es la capital de Mongolia?", "Ulán Bator."),
        ("mitocondria", "La parte de la célula que produce su energía."),
    ]
    for (front, back) in madeByHand {
        guard let content = CardContent(type: nil, front: front, back: back, tags: [], source: nil) else {
            throw RenderError(description: "A card made by hand for the sample has a blank front or back.")
        }
        try engine.create(content)
    }
    return (engine, time)
}

/// Ficha Dev's data folder in the tool's scratch home, which the Backups tab
/// shows as `~/Library/Application Support/Ficha Dev/Backups`, as on a Mac.
let renderDataFolder = URL.applicationSupportDirectory.appending(path: "Ficha Dev", directoryHint: .isDirectory)

/// An engine with the sample cards in `renderDataFolder`, and copies of
/// every kind in its Backups folder: a backup each of the last 8 days, of
/// which Ficha kept 7, a copy before a restore of the last one, and a copy
/// before an update from before them.
func backupsEngine() throws -> Engine {
    try? FileManager.default.removeItem(at: renderDataFolder)
    let (engine, time) = try sampleEngine(at: .folder(renderDataFolder))
    let today = time.now
    time.advance(by: -hours(8 * 24))
    let firstBackup = try engine.backUpNow(.defaults)
    guard let backups = engine.backupsFolder else {
        throw RenderError(description: "The sample's engine has no Backups folder.")
    }
    try FileManager.default.copyItem(
        at: backups.appending(path: firstBackup.name),
        to: backups.appending(path: "Before update 2026-10-09T231512Z.sqlite"))
    for _ in 0..<7 {
        time.advance(by: hours(24))
        try engine.backUpIfDue(.defaults)
    }
    time.advance(by: today.timeIntervalSince(time.now))
    if let newest = try engine.copies().first {
        try engine.restore(newest.name)
    }
    return engine
}

/// A span of whole hours, in seconds.
func hours(_ count: Int) -> TimeInterval {
    TimeInterval(count * 60 * 60)
}

/// The app's model for `name`'s window: on the sample cards in memory, and
/// for Settings' Backups tab, in `renderDataFolder`, with copies to list.
func model(for name: Window) throws -> AppModel {
    switch name {
    case .cards: return AppModel(engine: try sampleEngine(at: .inMemory).engine)
    case .backups: return AppModel(engine: try backupsEngine())
    case .backupsFailed:
        let model = AppModel(engine: try backupsEngine())
        // A file where the Backups folder goes, so no backup can be saved.
        let backups = renderDataFolder.appending(path: "Backups")
        try FileManager.default.removeItem(at: backups)
        try Data().write(to: backups)
        model.backups.backUpNow(model.backupSettings)
        return model
    }
}

/// The app's window for `name`, closed, with its content, at the size it
/// opens at.
func window(_ name: Window, model: AppModel) -> NSWindow {
    switch name {
    case .cards:
        let window = CardsWindow(model: model)
        window.makeContent()
        return window
    case .backups, .backupsFailed:
        let window = AppWindow(
            tabs: SettingsTabViewController(
                model: model, captureShortcut: CaptureShortcutRegistration(), closeReviewPanel: {},
                openingOn: .backups))
        if let content = window.contentView {
            window.setContentSize(content.fittingSize)
        }
        return window
    }
}

/// The window the keyboard goes to while `window` is open, as AppKit makes it
/// the key window: the sheet `window` has open, or `window` itself.
func keyWindow(of window: NSWindow) -> NSWindow {
    var key = window
    while let sheet = key.attachedSheet {
        key = sheet
    }
    return key
}

/// Clicks `mouseClick`'s point, in points from the window's top-left corner,
/// with its modifier keys held down, as the mouse would. The click goes to the
/// sheet the window has open, which takes the clicks until it closes, or else
/// to the window, and straight to the view under it, which a window does only
/// in the active app.
func click(_ mouseClick: MouseClick, in window: NSWindow) throws {
    // On the screen, from its bottom-left corner, as windows' frames are.
    let point = CGPoint(x: window.frame.minX + mouseClick.point.x, y: window.frame.maxY - mouseClick.point.y)
    let target = keyWindow(of: window)
    guard target === window || target.frame.contains(point) else {
        let left = target.frame.minX - window.frame.minX
        let top = window.frame.maxY - target.frame.maxY
        throw RenderError(
            description: """
                --click \(mouseClick.name) misses the sheet the window has open, which takes the clicks until it \
                closes: click inside it, at x \(String(format: "%g–%g", left, left + target.frame.width)) and y \
                \(String(format: "%g–%g", top, top + target.frame.height)).
                """)
    }
    let location = CGPoint(x: point.x - target.frame.minX, y: point.y - target.frame.minY)
    guard let frameView = target.contentView?.superview, let view = frameView.hitTest(location) else {
        throw RenderError(
            description: """
                --click \(mouseClick.name) lands outside the window, which is \
                \(String(format: "%g × %g", window.frame.width, window.frame.height)) pt: click inside it.
                """)
    }
    let events = try [NSEvent.EventType.leftMouseDown, .leftMouseUp].map { type in
        guard
            let event = NSEvent.mouseEvent(
                with: type, location: location, modifierFlags: mouseClick.modifiers,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: target.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1)
        else {
            throw RenderError(description: "Couldn't make the click --click \(mouseClick.name). \(whenMacOSRefuses)")
        }
        return event
    }
    // As the window does with a click: the nearest view that takes the keyboard
    // gets it.
    var responder: NSView? = view
    while let candidate = responder, !candidate.acceptsFirstResponder {
        responder = candidate.superview
    }
    if let responder {
        target.makeFirstResponder(responder)
    }
    // AppKit's views, like the table's rows and headers, follow the mouse until
    // it's released, reading the release from the app's queue; macOS 26's
    // buttons, SwiftUI's and an alert's, don't react to a click sent this way.
    NSApplication.shared.postEvent(events[1], atStart: false)
    view.mouseDown(with: events[0])
    if let up = NSApplication.shared.nextEvent(
        matching: .leftMouseUp, until: .distantPast, inMode: .default, dequeue: true)
    {
        view.mouseUp(with: up)
    }
}

/// Makes `press` as AppKit sends it to the key window, the window or the sheet
/// it has open: first as a key equivalent, which a SwiftUI button's keyboard
/// shortcut takes; then to the main menu, whose Edit menu takes ⌘A, ⌘C or ⌘Z;
/// and then, when nothing took it, to what holds the focus. The press is made
/// as the keyboard makes it, from its key's code, and never posted: the Mac's
/// keyboard layout says what it types, and AppKit matches it to the shortcuts
/// as it does the keyboard's, which ⇧⌘Z needs to reach Redo.
func press(_ press: KeyPress, in window: NSWindow) throws(RenderError) {
    let target = keyWindow(of: window)
    guard let code = CGKeyCode(exactly: press.code),
        let keyboardEvent = CGEvent(
            keyboardEventSource: CGEventSource(stateID: .privateState), virtualKey: code, keyDown: true)
    else {
        throw RenderError(description: "Couldn't make a keyboard event for --key \(press.name). \(whenMacOSRefuses)")
    }
    // AppKit's modifier flags and Quartz's share their bits, IOKit's `NX_` masks.
    keyboardEvent.flags = CGEventFlags(rawValue: UInt64(press.modifiers.rawValue))
    guard let shortcut = NSEvent(cgEvent: keyboardEvent), let characters = shortcut.characters,
        let unmodified = shortcut.charactersIgnoringModifiers
    else {
        throw RenderError(
            description: "AppKit couldn't read the keyboard event for --key \(press.name). \(whenMacOSRefuses)")
    }
    if let character = press.character, unmodified.lowercased() != character {
        throw RenderError(
            description: """
                This Mac's keyboard layout types "\(unmodified)" with the key that types "\(character)" on a US \
                keyboard, and --key presses keys by their place on one: switch to a layout with its letters and \
                digits, like ABC, Spanish or Latin American, in System Settings › Keyboard › Text Input.
                """)
    }
    if target.performKeyEquivalent(with: shortcut)
        || NSApplication.shared.mainMenu?.performKeyEquivalent(with: shortcut) == true
    {
        return
    }
    // What holds the focus gets the press as an event of the key window's,
    // which a text field needs to move the focus with Tab.
    guard
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: press.modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: target.windowNumber, context: nil,
            characters: characters, charactersIgnoringModifiers: unmodified, isARepeat: false, keyCode: code)
    else {
        throw RenderError(description: "Couldn't make the key event for --key \(press.name). \(whenMacOSRefuses)")
    }
    (target.firstResponder ?? target).keyDown(with: event)
}

/// Types `text` into what holds the focus in the key window, the window or the
/// sheet it has open, as the keyboard's input does: in a text field, into its
/// field editor.
func typeText(_ text: String, in window: NSWindow) throws(RenderError) {
    guard let input = keyWindow(of: window).firstResponder as? NSTextInputClient else {
        throw RenderError(
            description: """
                Nothing to type "\(text)" into: the focus is on \(focus(in: window)). Click a text field, or press \
                its shortcut, before --type.
                """)
    }
    input.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
}

/// What holds the focus in the key window, the window or the sheet it has
/// open: its first responder, by class. For a field editor, which types into
/// a text field, also the field and its placeholder, which tell the fields
/// apart.
func focus(in window: NSWindow) -> String {
    let target = keyWindow(of: window)
    let place = target === window ? "" : ", in the sheet"
    guard let responder = target.firstResponder, responder !== target else {
        return target === window ? "the window itself" : "the sheet itself"
    }
    let name = String(describing: type(of: responder))
    guard let editor = responder as? NSTextView, editor.isFieldEditor, let field = editor.delegate as? NSTextField
    else {
        return name + place
    }
    let placeholder = field.placeholderString.map { " \"\($0)\"" } ?? ""
    return "\(name), the field editor of \(type(of: field))\(placeholder)\(place)"
}

/// AppKit's `beginSheet(_:completionHandler:)` and
/// `beginCriticalSheet(_:completionHandler:)`, called by their address.
typealias SheetOpening = @convention(c) (NSWindow, Selector, NSWindow, AnyObject?) -> Void

/// The subclasses the tool made as it ran, by the window class each one
/// subclasses.
var keyWindowClasses: [ObjectIdentifier: AnyClass] = [:]

/// Why a sheet the window opened couldn't act as the key window, if one
/// couldn't: the action that opened it fails with it.
var sheetError: RenderError?

/// Makes `window` act and look as the key window, the one the keyboard and
/// clicks go to: views check it before they react to a click, and macOS draws
/// its title bar's buttons in color, though not its selections. This tool's app
/// never becomes active, so it doesn't take Lucas's keyboard, and none of its
/// windows can become key. The window becomes an instance of a subclass, made
/// as the tool runs, that says it's the key window, and the main one when
/// `isMain`, and overrides AppKit's private `_hasActiveAppearance`: fine for a
/// tool that draws pictures, never for the app. A sheet the window opens, as
/// SwiftUI's sheets, alerts and confirmations are, goes below the desktop
/// picture with it before macOS shows it, and acts as the key window the same
/// way, as AppKit makes it while it's open.
func actAsKey(_ window: NSWindow, isMain: Bool) throws(RenderError) {
    let base: AnyClass = type(of: window)
    if let subclass = keyWindowClasses[ObjectIdentifier(base)] {
        object_setClass(window, subclass)
        return
    }
    guard let subclass: AnyClass = objc_allocateClassPair(base, "RenderKeyWindow\(keyWindowClasses.count + 1)", 0)
    else {
        throw RenderError(description: "Couldn't make the window act as the key window. \(whenMacOSRefuses)")
    }
    let yes: @convention(block) (NSWindow) -> Bool = { _ in true }
    var getters = [#selector(getter: NSWindow.isKeyWindow), NSSelectorFromString("_hasActiveAppearance")]
    if isMain {
        getters.append(#selector(getter: NSWindow.isMainWindow))
    }
    for getter in getters {
        class_addMethod(subclass, getter, imp_implementationWithBlock(yes), "B@:")
    }
    let openings = [
        #selector(NSWindow.beginSheet(_:completionHandler:)),
        #selector(NSWindow.beginCriticalSheet(_:completionHandler:)),
    ]
    for opening in openings {
        guard let inherited = class_getMethodImplementation(base, opening) else {
            throw RenderError(description: "Couldn't keep the window's sheets offscreen. \(whenMacOSRefuses)")
        }
        let open = unsafeBitCast(inherited, to: SheetOpening.self)
        let keepingOffscreen: @convention(block) (NSWindow, NSWindow, AnyObject?) -> Void = { parent, sheet, handler in
            sheet.level = belowDesktop
            sheet.ignoresMouseEvents = true
            do throws(RenderError) {
                try actAsKey(sheet, isMain: false)
            } catch {
                sheetError = error
            }
            open(parent, opening, sheet, handler)
        }
        class_addMethod(subclass, opening, imp_implementationWithBlock(keepingOffscreen), "v@:@@?")
    }
    objc_registerClassPair(subclass)
    keyWindowClasses[ObjectIdentifier(base)] = subclass
    object_setClass(window, subclass)
}

/// Makes the app say `window` is its main window, and that its key window is
/// the sheet `window` has open, or `window` itself, though the app never
/// becomes active: the Edit menu's actions, which go to what holds the focus
/// in the key window, reach it as in the app. The app becomes an instance of a
/// subclass made as the tool runs, as the window does.
func makeKeyWindowOfApp(_ window: NSWindow) throws(RenderError) {
    let app = NSApplication.shared
    guard let subclass: AnyClass = objc_allocateClassPair(type(of: app), "RenderApplication", 0) else {
        throw RenderError(description: "Couldn't make the window the app's key window. \(whenMacOSRefuses)")
    }
    let key: @convention(block) (NSApplication) -> NSWindow = { _ in keyWindow(of: window) }
    let main: @convention(block) (NSApplication) -> NSWindow = { _ in window }
    class_addMethod(subclass, #selector(getter: NSApplication.keyWindow), imp_implementationWithBlock(key), "@@:")
    class_addMethod(subclass, #selector(getter: NSApplication.mainWindow), imp_implementationWithBlock(main), "@@:")
    objc_registerClassPair(subclass)
    object_setClass(app, subclass)
}

/// Gives the app the Edit menu's shortcuts SwiftUI gives it, in the main
/// menu's only menu: the app's others hold shortcuts that quit it or hide or
/// minimize its windows.
func installEditMenu() {
    let edit = NSMenu(title: "Edit")
    for item in editMenuItems {
        let menuItem = NSMenuItem(title: item.title, action: NSSelectorFromString(item.action), keyEquivalent: item.key)
        menuItem.keyEquivalentModifierMask = item.modifiers
        edit.addItem(menuItem)
    }
    let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
    editItem.submenu = edit
    let menuBar = NSMenu(title: "Main")
    menuBar.addItem(editItem)
    NSApplication.shared.mainMenu = menuBar
}

/// Gives the app a pasteboard of its own in place of the general one, which
/// the Edit menu's Cut, Copy and Paste use, so the tool never pastes Lucas's
/// clipboard into a picture, nor changes it while he works. The tool releases
/// it when it's done.
func usePasteboardOfItsOwn() throws(RenderError) -> NSPasteboard {
    let pasteboard = NSPasteboard.withUniqueName()
    guard let general = class_getClassMethod(NSPasteboard.self, #selector(getter: NSPasteboard.general)) else {
        throw RenderError(
            description: """
                Couldn't give the tool a pasteboard of its own, so it stopped before Cut, Copy or Paste could reach \
                yours. \(whenMacOSRefuses)
                """)
    }
    let own: @convention(block) (AnyObject) -> NSPasteboard = { _ in pasteboard }
    method_setImplementation(general, imp_implementationWithBlock(own))
    return pasteboard
}

/// Lets the window draw and react for `seconds`. A sheet it opens meanwhile
/// that couldn't act as the key window fails the tool.
func wait(_ seconds: TimeInterval) throws(RenderError) {
    RunLoop.main.run(until: Date.now.addingTimeInterval(seconds))
    if let sheetError {
        throw sheetError
    }
}

/// Saves the window as a PNG at `output`, as the screen draws it, without
/// its shadow. On macOS 26, `screencapture -l` captures a window with the
/// sheet it has open, over it where macOS puts it.
func capture(_ window: NSWindow, to output: URL) throws {
    try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
    let screencapture = Process()
    screencapture.executableURL = URL(filePath: "/usr/sbin/screencapture")
    screencapture.arguments = ["-x", "-o", "-l", "\(window.windowNumber)", output.path(percentEncoded: false)]
    try screencapture.run()
    screencapture.waitUntilExit()
    guard screencapture.terminationStatus == 0 else {
        throw RenderError(
            description: """
                screencapture couldn't capture the window (exit \(screencapture.terminationStatus)). Check that the \
                terminal running the tool has Screen & System Audio Recording in System Settings › Privacy & Security.
                """)
    }
}

do {
    // The app's files go to a scratch home, never to Lucas's.
    guard ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"] != nil else {
        throw RenderError(description: "Run the tool through make render, which gives it a scratch home.\n\(usage)")
    }
    // Its preferences don't: macOS keeps the tool's, such as the window's
    // frame and the Cards window's columns and order, in your home's
    // Library/Preferences/Render.plist, whatever CFFIXED_USER_HOME says. The
    // tool empties them as it starts, so the window opens as it does the first
    // time, and as it ends, so none is left there.
    let preferencesDomain = ProcessInfo.processInfo.processName
    UserDefaults.standard.removePersistentDomain(forName: preferencesDomain)
    defer { UserDefaults.standard.removePersistentDomain(forName: preferencesDomain) }
    let request = try request(from: Array(CommandLine.arguments.dropFirst()))
    guard let name = request.window else {
        throw RenderError(description: "Which window? Name one.\n\(usage)")
    }
    let pasteboard = try usePasteboardOfItsOwn()
    defer { pasteboard.releaseGlobally() }
    NSApplication.shared.setActivationPolicy(.accessory)
    // The app's appearance, which its sheets take too.
    NSApplication.shared.appearance = NSAppearance(named: request.isDark ? .darkAqua : .aqua)
    installEditMenu()
    // The data folder a window may leave in the scratch home goes as the
    // tool ends.
    defer { try? FileManager.default.removeItem(at: renderDataFolder) }
    let model = try model(for: name)
    let window = window(name, model: model)
    window.level = belowDesktop
    window.ignoresMouseEvents = true
    try actAsKey(window, isMain: true)
    try makeKeyWindowOfApp(window)
    window.orderFrontRegardless()
    try wait(1.5)
    for action in request.actions {
        switch action {
        case .click(let mouseClick): try click(mouseClick, in: window)
        case .key(let keyPress): try press(keyPress, in: window)
        case .type(let text): try typeText(text, in: window)
        }
        try wait(0.5)
        print("\(action): the focus is on \(focus(in: window))")
    }
    let output =
        request.output ?? URL(filePath: ".build/render/\(name.rawValue)-\(request.isDark ? "dark" : "light").png")
    try capture(window, to: output)
    print(
        "\(output.path(percentEncoded: false)): a \(Int(window.frame.width)) × \(Int(window.frame.height)) pt window"
    )
} catch {
    FileHandle.standardError.write(Data("render: \(error)\n".utf8))
    exit(1)
}
