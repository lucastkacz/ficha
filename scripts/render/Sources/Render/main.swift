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

/// A window the tool can draw, by the name its arguments give it.
enum Window: String {
    case cards
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
    /// A click, in points from the window's top-left corner.
    case click(CGPoint)
    /// A key, pressed with its modifier keys held down.
    case key(Key)
    /// Text, typed into what holds the focus.
    case type(String)

    /// The action as its arguments ask for it, like `--key cmd+f`.
    var description: String {
        switch self {
        case .click(let point): "--click \(String(format: "%g,%g", point.x, point.y))"
        case .key(let key): "--key \(key.name)"
        case .type(let text): "--type \"\(text)\""
        }
    }
}

/// A key the tool presses, like `cmd+f`.
struct Key {
    /// The key as its arguments name it.
    let name: String
    let modifiers: NSEvent.ModifierFlags
    /// What the key types.
    let characters: String
    /// Its key's code on a US keyboard, one of Carbon's `kVK_` constants.
    let code: Int
}

/// The keys the tool presses, by name, with their keys' codes.
let keyCodes = [
    "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F,
    "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
    "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R,
    "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
    "y": kVK_ANSI_Y, "z": kVK_ANSI_Z, "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
    "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
    "return": kVK_Return, "escape": kVK_Escape, "tab": kVK_Tab, "space": kVK_Space, "delete": kVK_Delete,
]

/// What the keys with a name type; a letter or a digit types itself.
let namedKeyCharacters = ["return": "\r", "escape": "\u{1B}", "tab": "\t", "space": " ", "delete": "\u{7F}"]

/// The modifier keys the tool holds down, by name.
let modifiersByName: [String: NSEvent.ModifierFlags] = [
    "cmd": .command, "shift": .shift, "option": .option, "ctrl": .control,
]

/// A request the tool can't draw, with what to do about it.
struct RenderError: Error, CustomStringConvertible {
    let description: String
}

let usage = """
    Usage: make render ARGS="<window> [--dark] [--click <x>,<y> | --key <keys> | --type <text>]... [--out <file.png>]"
      <window>   cards
      --dark     dark mode instead of light
      --click    a click on a table's or the sidebar's row, or on a column header, in points from the window's top-left corner
      --key      a key, after the modifiers held down: cmd+f, cmd+s, escape, return
                 keys: a-z, 0-9, return, escape, tab, space, delete; modifiers: cmd, shift, option, ctrl
      --type     text typed into what holds the focus, like a text field
      --out      the PNG, by default .build/render/<window>-<light|dark>.png
    --click, --key and --type run in the order given, and after each one the tool prints what holds the focus.
    """

/// The key `name` names, like `cmd+f` or `escape`.
func key(named name: String) throws(RenderError) -> Key {
    var parts = name.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
    guard let last = parts.popLast(), let code = keyCodes[last] else {
        throw RenderError(description: "--key takes a key after its modifiers, like cmd+f or escape.\n\(usage)")
    }
    var modifiers: NSEvent.ModifierFlags = []
    for part in parts {
        guard let modifier = modifiersByName[part] else {
            throw RenderError(description: "Unknown modifier \(part) in --key \(name).\n\(usage)")
        }
        modifiers.insert(modifier)
    }
    let characters = namedKeyCharacters[last] ?? (modifiers.contains(.shift) ? last.uppercased() : last)
    return Key(name: name, modifiers: modifiers, characters: characters, code: code)
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
            let parts = (arguments.popFirst() ?? "").split(separator: ",", omittingEmptySubsequences: false)
            let numbers = parts.compactMap { Double($0) }
            guard parts.count == 2, numbers.count == 2 else {
                throw RenderError(description: "--click takes a point as <x>,<y>, like 300,120.\n\(usage)")
            }
            request.actions.append(.click(CGPoint(x: numbers[0], y: numbers[1])))
        case "--key":
            request.actions.append(.key(try key(named: arguments.popFirst() ?? "")))
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

/// An engine on an in-memory database with Ficha Dev's sample cards, as Lucas
/// would have them after twelve days of reviews, starting on 8 October 2026:
/// twenty met the first day and climbing at different paces, two sent back to
/// the first step, one flagged with a note and one buried, and the rest new.
func sampleEngine() throws -> Engine {
    var calendar = Calendar(identifier: .gregorian)
    guard let buenosAires = TimeZone(identifier: "America/Argentina/Buenos_Aires") else {
        throw RenderError(description: "This Mac doesn't know Buenos Aires's time zone.")
    }
    calendar.timeZone = buenosAires
    guard let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 9)) else {
        throw RenderError(description: "Couldn't make the sample's start date.")
    }
    let time = ManualTimeSource(now: start)
    let engine = try Engine(location: .inMemory, time: time, calendar: calendar)
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
    time.advance(by: hours(4 * 24 + 3))
    guard let note = FlagNote("El ejemplo no se entiende: cambiarlo por uno más cotidiano.") else {
        throw RenderError(description: "The sample's flag note is blank.")
    }
    try engine.flag(cards[2].id, note: note)
    try engine.bury(cards[5].id)
    return engine
}

/// A span of whole hours, in seconds.
func hours(_ count: Int) -> TimeInterval {
    TimeInterval(count * 60 * 60)
}

/// The app's window for `name`, closed, with its content.
func window(_ name: Window, model: AppModel) -> NSWindow {
    switch name {
    case .cards:
        let window = CardsWindow(model: model)
        window.makeContent()
        return window
    }
}

/// Clicks `point`, in points from the window's top-left corner, as the mouse
/// would. The click goes straight to the view under it, which the window does
/// only in the active app.
func click(_ point: CGPoint, in window: NSWindow) throws {
    let location = CGPoint(x: point.x, y: window.frame.height - point.y)
    guard let frameView = window.contentView?.superview, let view = frameView.hitTest(location) else {
        throw RenderError(description: "Nothing to click at \(point).")
    }
    let events = try [NSEvent.EventType.leftMouseDown, .leftMouseUp].map { type in
        guard
            let event = NSEvent.mouseEvent(
                with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
        else {
            throw RenderError(description: "Couldn't make a click at \(point).")
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
        window.makeFirstResponder(responder)
    }
    // AppKit's views, like the table's rows and headers, follow the mouse until
    // it's released, reading the release from the app's queue; SwiftUI's
    // buttons don't react to a click sent this way.
    NSApplication.shared.postEvent(events[1], atStart: false)
    view.mouseDown(with: events[0])
    if let up = NSApplication.shared.nextEvent(
        matching: .leftMouseUp, until: .distantPast, inMode: .default, dequeue: true)
    {
        view.mouseUp(with: up)
    }
}

/// Presses `key` as AppKit sends it to the key window: first as a key
/// equivalent, which a SwiftUI button's keyboard shortcut takes, and then, when
/// nothing took it, to what holds the focus.
func press(_ key: Key, in window: NSWindow) throws {
    guard let code = UInt16(exactly: key.code),
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: key.modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
            characters: key.characters, charactersIgnoringModifiers: key.characters, isARepeat: false, keyCode: code)
    else {
        throw RenderError(description: "Couldn't make a press of \(key.name).")
    }
    if !window.performKeyEquivalent(with: event) {
        (window.firstResponder ?? window).keyDown(with: event)
    }
}

/// Types `text` into what holds the focus, as the keyboard's input does: in a
/// text field, into its field editor.
func typeText(_ text: String, in window: NSWindow) throws {
    guard let input = window.firstResponder as? NSTextInputClient else {
        throw RenderError(
            description: """
                Nothing to type "\(text)" into: the focus is on \(focus(in: window)). Click a text field, or press \
                its shortcut, before --type.
                """)
    }
    input.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
}

/// What holds the focus in `window`, its first responder, by class. For a
/// field editor, which types into a text field, also the field and its
/// placeholder, which tell the fields apart.
func focus(in window: NSWindow) -> String {
    guard let responder = window.firstResponder, responder !== window else {
        return "the window itself"
    }
    let name = String(describing: type(of: responder))
    guard let editor = responder as? NSTextView, editor.isFieldEditor, let field = editor.delegate as? NSTextField
    else {
        return name
    }
    let placeholder = field.placeholderString.map { " \"\($0)\"" } ?? ""
    return "\(name), the field editor of \(type(of: field))\(placeholder)"
}

/// Makes `window` act and look as the key window, the one the keyboard and
/// clicks go to: views check it before they react to a click, and macOS draws
/// its title bar's buttons in color, though not its selections. This tool's app
/// never becomes active, so it doesn't take Lucas's keyboard, and none of its
/// windows can become key. The window becomes an instance of a subclass, made
/// as the tool runs, that says it's the key and main window and overrides
/// AppKit's private `_hasActiveAppearance`: fine for a tool that draws
/// pictures, never for the app.
func actAsKey(_ window: NSWindow) throws {
    guard let subclass: AnyClass = objc_allocateClassPair(type(of: window), "RenderKeyWindow", 0) else {
        throw RenderError(description: "Couldn't make the window act as the key window.")
    }
    let yes: @convention(block) (AnyObject) -> Bool = { _ in true }
    let getters = [
        #selector(getter: NSWindow.isKeyWindow), #selector(getter: NSWindow.isMainWindow),
        NSSelectorFromString("_hasActiveAppearance"),
    ]
    for getter in getters {
        class_addMethod(subclass, getter, imp_implementationWithBlock(yes), "B@:")
    }
    objc_registerClassPair(subclass)
    object_setClass(window, subclass)
}

/// Lets the window draw and react for `seconds`.
func wait(_ seconds: TimeInterval) {
    RunLoop.main.run(until: Date.now.addingTimeInterval(seconds))
}

/// Saves the window as a PNG at `output`, as the screen draws it, without
/// its shadow.
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
    // The app's preferences, such as the window's frame, go to a scratch home,
    // never to Lucas's.
    guard ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"] != nil else {
        throw RenderError(description: "Run the tool through make render, which gives it a scratch home.\n\(usage)")
    }
    let request = try request(from: Array(CommandLine.arguments.dropFirst()))
    guard let name = request.window else {
        throw RenderError(description: "Which window? Name one.\n\(usage)")
    }
    NSApplication.shared.setActivationPolicy(.accessory)
    let model = AppModel(engine: try sampleEngine())
    let window = window(name, model: model)
    window.appearance = NSAppearance(named: request.isDark ? .darkAqua : .aqua)
    window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)
    window.ignoresMouseEvents = true
    try actAsKey(window)
    window.orderFrontRegardless()
    wait(1.5)
    for action in request.actions {
        switch action {
        case .click(let point): try click(point, in: window)
        case .key(let key): try press(key, in: window)
        case .type(let text): try typeText(text, in: window)
        }
        wait(0.5)
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
