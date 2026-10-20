import AppKit
import FichaCore
import FichaData

// Draws one of the app's windows as a PNG, with Ficha Dev's sample cards,
// without showing anything on screen: `make render ARGS="cards --dark"`. The
// window goes below the desktop picture, where macOS still draws it but nobody
// sees it and nothing takes the mouse or the keyboard; the tool clicks in it
// where it's told, as Lucas would, and captures it with `screencapture`.
// `docs/development.md` explains how to use it.

/// A window the tool can draw, by the name its arguments give it.
enum Window: String {
    case cards
}

/// What the tool was asked to draw.
struct Request {
    var window: Window?
    var isDark = false
    /// Where to click before the capture, in order: points from the window's
    /// top-left corner.
    var clicks: [CGPoint] = []
    /// Where the PNG goes.
    var output: URL?
}

/// A request the tool can't draw, with what to do about it.
struct RenderError: Error, CustomStringConvertible {
    let description: String
}

let usage = """
    Usage: make render ARGS="<window> [--dark] [--click <x>,<y>]... [--out <file.png>]"
      <window>   cards
      --dark     dark mode instead of light
      --click    a click on a table's row or column header, in points from the window's top-left corner
      --out      the PNG, by default .build/render/<window>-<light|dark>.png
    """

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
            request.clicks.append(CGPoint(x: numbers[0], y: numbers[1]))
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
    for point in request.clicks {
        try click(point, in: window)
        wait(0.5)
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
