import AVFoundation
import AppKit
import Carbon.HIToolbox
import FichaCore
import FichaData
import SQLite3

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
    /// The Cards window with its Import sheet showing the preview of a file,
    /// which the tool can't choose in the open panel.
    case cardsImport = "cards-import"
    /// The Cards window with its Import sheet showing the preview of an Anki
    /// package.
    case cardsImportAnki = "cards-import-anki"
    /// The Cards window once that Anki package came in with its progress,
    /// with a card it put on a step selected, and reviewed since.
    case cardsAnkiImported = "cards-anki-imported"
    /// Settings, on its Backups tab.
    case backups
    /// Settings, on its Backups tab, once a backup failed.
    case backupsFailed = "backups-failed"
    /// Settings, on its Appearances tab, which holds the new cards a day,
    /// with the settings that decide progress in the database not Ficha's.
    case appearances
    /// Settings, on its Review panel tab, which holds the forgotten-often
    /// count, with those settings not Ficha's.
    case reviewPanel = "review-panel"
    /// Settings, on its Ladder tab, with those settings not Ficha's.
    case ladder
    /// Settings, on its About tab.
    case about
    /// The alert the real Ficha shows at its first launch, which asks whether
    /// it opens at login.
    case startAtLogin = "start-at-login"
    /// The Diagnostics window, while a Focus holds appearances back, once it
    /// held one back.
    case diagnostics
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
    /// A picture, copied to the tool's own pasteboard, for ⌘V to paste.
    case copyImage(SamplePicture)
    /// A sound file, copied to the tool's own pasteboard as Finder copies
    /// one, for ⌘V to paste.
    case copySound

    /// The action as its arguments ask for it, like `--key cmd+f`.
    var description: String {
        switch self {
        case .click(let mouseClick): "--click \(mouseClick.name)"
        case .key(let press): "--key \(press.name)"
        case .type(let text): "--type \"\(text)\""
        case .copyImage(let picture): "--copy-image \(picture.rawValue)"
        case .copySound: "--copy-sound"
        }
    }
}

/// Writes a tone to `file`, a WAV file, for the sample's card with a sound
/// and for `--copy-sound`, since the tool can't drag a file: an A, 440 Hz,
/// lasting `seconds`, at half its loudest.
func writeSampleTone(seconds: Double, to file: URL) throws {
    let frames = AVAudioFrameCount(44_100 * seconds)
    guard
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 1, interleaved: false),
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
        let samples = buffer.floatChannelData
    else {
        throw RenderError(description: "Couldn't make the sample tone. \(whenMacOSRefuses)")
    }
    buffer.frameLength = frames
    for frame in 0..<Int(frames) {
        samples[0][frame] = Float(sin(2 * Double.pi * 440 * Double(frame) / 44_100) * 0.5)
    }
    // The file is written once it's let go, at the end of this scope.
    let wav = try AVAudioFile(
        forWriting: file,
        settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
    try wav.write(from: buffer)
}

/// The sample tone lasting `seconds`, added to `engine` as the Cards window
/// adds a sound dropped on a side: converted as every sound that comes in.
func addSampleTone(seconds: Double, to engine: Engine) async throws -> SoundName {
    let file = URL.temporaryDirectory.appending(path: "RenderTone-\(UUID().uuidString).wav")
    defer { try? FileManager.default.removeItem(at: file) }
    try writeSampleTone(seconds: seconds, to: file)
    return try await engine.addSound(Data(contentsOf: file), named: file.lastPathComponent)
}

/// What `work` returns, or throws, waited for on the main run loop. The
/// tool's top-level code stays synchronous, and doesn't await: awaiting
/// there would run all of it as one job of the main actor, during which
/// `wait(_:)` lets no other job of the main actor run, such as the window's
/// tasks, which read its cards.
func waitFor<Value>(_ work: @escaping () async throws -> Value) throws -> Value {
    let awaited = Awaited<Value>()
    Task {
        do {
            awaited.result = .success(try await work())
        } catch {
            awaited.result = .failure(error)
        }
    }
    while true {
        if let result = awaited.result {
            return try result.get()
        }
        RunLoop.main.run(until: Date.now.addingTimeInterval(0.05))
    }
}

/// What `waitFor(_:)` waits for, once it's there.
final class Awaited<Value> {
    var result: Result<Value, any Error>?
}

/// A picture the tool draws, for the sample's card with images and for
/// `--copy-image`, since it can't drag a file nor reach a clipboard with an
/// image on it.
enum SamplePicture: String, CaseIterable {
    /// Argentina's flag, 1,800 × 1,125 pixels, which Ficha shrinks as it
    /// comes in.
    case flag
    /// The flag's Sun of May alone, 600 × 600 pixels, on a transparent
    /// background, which Ficha keeps as a PNG.
    case sun

    /// The picture, as a PNG.
    func png() throws(RenderError) -> Data {
        let size = self == .flag ? CGSize(width: 1800, height: 1125) : CGSize(width: 600, height: 600)
        guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else {
            throw RenderError(description: "Couldn't draw the sample picture \(rawValue). \(whenMacOSRefuses)")
        }
        switch self {
        case .flag:
            let stripe = size.height / 3
            context.setFillColor(CGColor(srgbRed: 0.455, green: 0.675, blue: 0.875, alpha: 1))
            context.fill(CGRect(origin: .zero, size: size))
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: stripe, width: size.width, height: stripe))
            drawSunOfMay(in: context, center: CGPoint(x: size.width / 2, y: size.height / 2), radius: stripe * 0.45)
        case .sun:
            drawSunOfMay(in: context, center: CGPoint(x: size.width / 2, y: size.height / 2), radius: 290)
        }
        guard let image = context.makeImage(),
            let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else {
            throw RenderError(description: "Couldn't draw the sample picture \(rawValue). \(whenMacOSRefuses)")
        }
        return png
    }
}

/// Draws the Sun of May in `context`: a golden disk and 32 rays, the longest
/// reaching `radius` from `center`.
func drawSunOfMay(in context: CGContext, center: CGPoint, radius: CGFloat) {
    /// The point `distance` from `center` at `angle`, in radians.
    func point(_ distance: CGFloat, _ angle: CGFloat) -> CGPoint {
        CGPoint(x: center.x + distance * cos(angle), y: center.y + distance * sin(angle))
    }
    context.setFillColor(CGColor(srgbRed: 0.965, green: 0.706, blue: 0.055, alpha: 1))
    context.setStrokeColor(CGColor(srgbRed: 0.522, green: 0.204, blue: 0.039, alpha: 1))
    context.setLineWidth(radius * 0.02)
    let disk = radius * 0.45
    for index in 0..<32 {
        let angle = CGFloat(index) * .pi / 16
        let ray = CGMutablePath()
        ray.move(to: point(disk * 0.9, angle - .pi / 40))
        ray.addLine(to: point(index.isMultiple(of: 2) ? radius : radius * 0.8, angle))
        ray.addLine(to: point(disk * 0.9, angle + .pi / 40))
        ray.closeSubpath()
        context.addPath(ray)
        context.drawPath(using: .fillStroke)
    }
    context.addEllipse(in: CGRect(x: center.x - disk, y: center.y - disk, width: disk * 2, height: disk * 2))
    context.drawPath(using: .fillStroke)
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
      <window>   cards, cards-import (its Import sheet, previewing a file), cards-import-anki (previewing an Anki
                 package), cards-anki-imported (once it came in, a card it put on a step selected), backups
                 (Settings, on its Backups tab), backups-failed (once a backup failed), appearances, review-panel
                 or ladder (Settings on those tabs, with the settings that decide progress not Ficha's), about
                 (Settings, on its About tab), start-at-login (the alert the real Ficha shows at its first launch)
                 or diagnostics (while a Focus holds appearances back, once it held one back)
      --dark     dark mode instead of light
      --click    a click, in points from the window's top-left corner, after the modifiers held down: 280,121,
                 cmd+280,121, shift+280,145; on a row of a table or the sidebar, a column header, or a sheet
      --key      a key, after the modifiers held down: cmd+f, cmd+a, escape, return, shift+tab
                 keys: a-z, 0-9, return, escape, tab, space, delete; modifiers: cmd, shift
      --type     text typed into what holds the focus, like a text field
      --copy-image  a picture, flag or sun, copied to the tool's own pasteboard, for --key cmd+v to paste
      --copy-sound  a sound file, a tone of 12 seconds, copied to the tool's own pasteboard, for --key cmd+v
      --out      the PNG, by default .build/render/<window>-<light|dark>.png
    --click, --key, --type, --copy-image and --copy-sound run in the order given, and after each one the tool
    prints what holds the focus.
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
        case "--copy-image":
            guard let name = arguments.popFirst(), let picture = SamplePicture(rawValue: name) else {
                throw RenderError(description: "--copy-image takes a picture: flag or sun.\n\(usage)")
            }
            request.actions.append(.copyImage(picture))
        case "--copy-sound":
            request.actions.append(.copySound)
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
/// capture waiting in the inbox; and then a new card with a flag on its front
/// and the Sun of May and a sound on its back, and two new cards made by
/// hand, with no type and no capture. The time it's on stays where the twelve
/// days left it.
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
    // A card made in the Cards window with an image on each side, and a
    // sound on its back, as the anthem would be.
    guard
        let withImages = CardContent(
            type: nil, front: "¿De qué país es esta bandera?", back: "De la Argentina. En el centro, el Sol de Mayo.",
            tags: ["geografía"], source: nil, frontImage: try engine.addImage(SamplePicture.flag.png()),
            backImage: try engine.addImage(SamplePicture.sun.png()),
            backSound: try waitFor { try await addSampleTone(seconds: 12, to: engine) })
    else {
        throw RenderError(description: "The sample's card with images has a blank side.")
    }
    try engine.create(withImages)
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
/// shows as `~/Library/Application Support/Ficha Dev/Backups`: where Ficha
/// Dev kept it before its sandbox, which the tool runs outside. On a Mac,
/// Ficha Dev's own is in its App Group's folder (ADR 0018).
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

/// The Cards window's state partway through an import, as the Import sheet
/// shows it once the user chose a file: the preview of a text file the tool
/// writes in its scratch home, with words from other languages as someone
/// might type them in a spreadsheet, two of which the sample cards have, and
/// three lines that can't be read. The file goes once it's read.
func importingState(of model: AppModel) throws -> CardsWindowState {
    let file = URL.documentsDirectory.appending(path: "Palabras del mundo.txt")
    let lines = [
        "#separator:tab",
        "#html:false",
        "#columns:Front\tBack\tTags\tType\tSource",
        "hygge\tPalabra danesa: el bienestar de un rato cálido y sencillo con gente querida.\tdanés\tword\t",
        "wabi-sabi\tIdea japonesa: la belleza de lo imperfecto, lo pasajero y lo incompleto.\tjaponés\tconcept\t",
        "lagom\tPalabra sueca: ni mucho ni poco, lo justo.\tsueco\tword\t",
        "sisu",
        "ubuntu\tPalabra zulú: soy porque somos.\tzulú\tword\tDesmond Tutu",
        "Fernweh\tPalabra alemana: las ganas de estar lejos, en lugares que no conocés.\talemán\tword\t",
        "Kummerspeck\tPalabra alemana: los kilos que se ganan comiendo por tristeza.\talemán\tsustantivo\t",
        "tsundoku\tPalabra japonesa: comprar libros y dejarlos apilados sin leer.\tjaponés\tword\t",
        "\tPalabra yagán: la mirada entre dos que esperan que el otro dé el primer paso.\tyagán\tword\t",
        "mamihlapinatapai\tPalabra yagán: la mirada entre dos que esperan que el otro dé el primer paso.\tyagán\tword\t",
    ]
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(lines.joined(separator: "\n").utf8).write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    var state = model.openCardsWindow()
    state.startImport()
    try previewImportAtOnce(of: file, in: &state)
    guard state.importing?.preview != nil else {
        throw RenderError(
            description: "The sample file to import has no preview: \(String(describing: state.importing))")
    }
    return state
}

/// Reads `file` for the Import sheet in `state`, as the app does once the
/// user chose it, and waits for the reading, so that the picture shows its
/// preview.
func previewImportAtOnce(of file: URL, in state: inout CardsWindowState) throws {
    if let work = state.previewImport(of: file) {
        state.finishImportWork(try waitFor { await work.run() })
    }
}

/// The Cards window's state partway through importing an Anki package, as
/// the Import sheet shows it once the user chose one: the preview of a deck
/// of medicine the tool writes in its scratch home, with two subdecks and
/// Anki tags, two cards Anki was reviewing, which Bring progress puts on a
/// step, a card the sample cards have, a card with two images on its front,
/// of which the first comes in, and a card whose back is only a sound, one
/// whose front is only an image the package lacks and an Image Occlusion
/// note, which stay out. The file goes once it's read.
func ankiImportingState(of model: AppModel) throws -> CardsWindowState {
    let file = URL.documentsDirectory.appending(path: "Medicina.apkg")
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try writeSampleAnkiPackage(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    var state = model.openCardsWindow()
    state.startImport()
    try previewImportAtOnce(of: file, in: &state)
    guard state.importing?.preview != nil else {
        throw RenderError(
            description: "The sample Anki package has no preview: \(String(describing: state.importing))")
    }
    return state
}

/// The app's model on the sample cards, once the sample Anki package came in
/// with its progress, and four days later, the card of the femur, which it
/// put on the 12-day step, was reviewed with Know it, on time.
func ankiImportedModel() throws -> AppModel {
    let (engine, time) = try sampleEngine(at: .inMemory)
    let file = URL.documentsDirectory.appending(path: "Medicina.apkg")
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try writeSampleAnkiPackage(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    let settings = ReviewSettings.defaults
    _ = try engine.importCards(
        waitFor { try await engine.previewImport(of: file) },
        choosing: ImportChoices(progress: .brought(onto: settings.ladder)))
    guard let femur = try engine.cards().first(where: { $0.front == "fémur" }) else {
        throw RenderError(description: "The sample Anki package's card of the femur didn't come in.")
    }
    time.advance(by: hours(4 * 24))
    try engine.record(.review(.good), of: femur.id, responseTime: .seconds(4), trigger: .reviewNow, settings: settings)
    return try AppModel(engine: engine)
}

/// The app's model on the sample cards, whose settings that decide progress,
/// in the database, aren't Ficha's, as another device may have left them: a
/// ladder of five steps, from 20 minutes to 60 days, 8 new cards a day, and
/// the offer to flag a card forgotten often after 6 reviews rated again.
func progressSettingsModel() throws -> AppModel {
    let engine = try sampleEngine(at: .inMemory).engine
    let day = 24 * 60
    guard let ladder = Ladder(waits: [20, day, 4 * day, 14 * day, 60 * day].map { Duration.minutes($0) }) else {
        throw RenderError(
            description: "The sample's ladder has waits that don't grow step by step: fix progressSettingsModel().")
    }
    try engine.saveProgressSettings(
        ProgressSettings(ladder: ladder, newCardsPerDay: 8, forgottenOftenAfter: 6),
        changedFrom: ReviewSettings.defaults.progress)
    return try AppModel(engine: engine)
}

/// The app's model on the sample cards, an hour after their last review, once
/// a Focus held an appearance back, for Diagnostics' latest appearances.
func focusHeldBackModel() throws -> AppModel {
    let (engine, time) = try sampleEngine(at: .inMemory)
    time.advance(by: hours(1))
    let model = try AppModel(engine: engine)
    let decision = try model.checkAppearance(mac: MacInAFocus())
    guard decision == .notNow(.suppressed(.focus)) else {
        throw RenderError(
            description: "A Focus didn't hold the sample's appearance back: \(decision). Fix focusHeldBackModel().")
    }
    return model
}

/// A Mac that's awake and in use, in a Focus with Ficha's filter on.
struct MacInAFocus: DeviceSignals {
    var isAsleep: Bool { false }
    var lastWake: Date? { nil }
    var idleTime: Duration? { .zero }
    var suppressions: Set<Suppression> { [.focus] }
    var suppressionEnds: [Suppression: Date] { [:] }
}

/// The Cards window's state once the sample Anki package came in, with the
/// card of the femur selected, so the detail shows its review log.
func ankiImportedState(of model: AppModel) throws -> CardsWindowState {
    var state = model.openCardsWindow()
    state.read(on: state.ladder)
    guard case .success(.cards(let rows)) = state.listing, let femur = rows.first(where: { $0.card.front == "fémur" })
    else {
        throw RenderError(description: "The Cards window doesn't list the sample Anki package's card of the femur.")
    }
    state.select([femur.id])
    return state
}

/// Writes the sample Anki package to `file`, as current Anki exports a deck
/// with "Support older Anki versions" ticked: a zip with `meta` at version
/// 2, `collection.anki21`, a SQLite database at schema 11 with only what
/// Ficha reads, and its media, the flag and the Sun of May, in members `0`
/// and `1`, with the JSON list that names them. The tests'
/// `AnkiPackages.swift` writes such packages too, from Anki's source.
func writeSampleAnkiPackage(to file: URL) throws {
    let folder = file.deletingLastPathComponent().appending(path: "Anki package", directoryHint: .isDirectory)
    try? FileManager.default.removeItem(at: folder)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let collection = folder.appending(path: "collection.anki21")
    try runSQLite(try sampleAnkiCollectionSQL(), in: collection)
    let meta = folder.appending(path: "meta")
    try Data([0x08, 0x02]).write(to: meta)
    let flag = folder.appending(path: "0")
    try SamplePicture.flag.png().write(to: flag)
    let sun = folder.appending(path: "1")
    try SamplePicture.sun.png().write(to: sun)
    let media = folder.appending(path: "media")
    try Data(#"{"0":"bandera.png","1":"sol.png"}"#.utf8).write(to: media)
    try? FileManager.default.removeItem(at: file)
    let zip = Process()
    zip.executableURL = URL(filePath: "/usr/bin/zip")
    zip.arguments = ["-q", "-j"] + [file, meta, collection, flag, sun, media].map { $0.path(percentEncoded: false) }
    try zip.run()
    zip.waitUntilExit()
    guard zip.terminationStatus == 0 else {
        throw RenderError(
            description:
                "zip couldn't make the sample Anki package (exit \(zip.terminationStatus)). \(whenMacOSRefuses)"
        )
    }
}

/// Runs `sql` on the SQLite database at `file`, which it makes.
func runSQLite(_ sql: String, in file: URL) throws {
    var database: OpaquePointer?
    defer { sqlite3_close(database) }
    guard sqlite3_open(file.path(percentEncoded: false), &database) == SQLITE_OK,
        sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK
    else {
        throw RenderError(
            description: "SQLite couldn't write the sample Anki package: \(String(cString: sqlite3_errmsg(database)))")
    }
}

/// The SQL that makes the sample Anki package's collection: Anki's tables at
/// schema 11 (`rslib/src/storage/schema11.sql`), created on 1 October 2026
/// at 4 in the morning in Buenos Aires, its Basic, Cloze and Image Occlusion
/// note types, a deck of medicine with two subdecks, and the notes, with
/// their cards: the femur's in review, every 10 days, due on Anki's day 22,
/// 23 October; the systole's relearning, due on day 20, 21 October; and the
/// rest new, among them one in Default whose front shows the flag and the
/// Sun of May, of which the first comes in, and one whose front is only an
/// image the package lacks.
func sampleAnkiCollectionSQL() throws -> String {
    let basicAnswer = "{{FrontSide}}\n\n<hr id=answer>\n\n{{Back}}"
    let noteTypes: [String: Any] = [
        "1": [
            "id": 1, "name": "Basic", "type": 0, "originalStockKind": 1,
            "flds": [["name": "Front"], ["name": "Back"]],
            "tmpls": [["name": "Card 1", "qfmt": "{{Front}}", "afmt": basicAnswer]],
        ],
        "2": [
            "id": 2, "name": "Cloze", "type": 1, "originalStockKind": 5,
            "flds": [["name": "Text"], ["name": "Back Extra"]],
            "tmpls": [["name": "Cloze", "qfmt": "{{cloze:Text}}", "afmt": "{{cloze:Text}}<br>\n{{Back Extra}}"]],
        ],
        "3": [
            "id": 3, "name": "Image Occlusion", "type": 1, "originalStockKind": 6,
            "flds": [["name": "Occlusion"], ["name": "Image"], ["name": "Header"], ["name": "Back Extra"]],
            "tmpls": [
                [
                    "name": "Image Occlusion", "qfmt": "{{cloze:Occlusion}}{{Image}}",
                    "afmt": "{{cloze:Occlusion}}{{Image}}<br>{{Back Extra}}",
                ]
            ],
        ],
    ]
    let decks: [String: Any] = [
        "1": ["id": 1, "name": "Default"], "2": ["id": 2, "name": "Medicina"],
        "3": ["id": 3, "name": "Medicina::Anatomía"], "4": ["id": 4, "name": "Medicina::Fisiología"],
    ]
    // Each note: its note type, its deck, its tags, its fields, and its
    // cards' template indexes.
    let notes: [(type: Int, deck: Int, tags: String, fields: [String], cards: [Int])] = [
        (1, 3, "huesos", ["fémur", "El hueso del muslo, el más largo del cuerpo."], [0]),
        (2, 4, "repaso", ["El {{c1::corazón}} bombea la sangre por las {{c2::arterias::unos vasos}}.", ""], [0, 1]),
        (1, 4, "", ["mitocondria", "La parte de la célula que produce su energía."], [0]),
        (1, 4, "", ["latido", "[sound:latido.mp3]"], [0]),
        (
            3, 3, "huesos",
            ["{{c1::image-occlusion:rect:left=.2:top=.3:width=.1:height=.1}}", "<img src=\"pie.png\">", "", ""],
            [0]
        ),
        (1, 4, "corazón leech", ["sístole", "La contracción del corazón, que empuja la sangre."], [0]),
        (1, 1, "", ["<img src=\"bandera.png\"><img src=\"sol.png\">", "La bandera de la Argentina."], [0]),
        (1, 3, "huesos", ["<img src=\"tibia.png\">", "La tibia."], [0]),
    ]
    // The `type`, `queue`, `due` and `ivl` of the cards of the notes not new,
    // by the notes' places above: in review, and relearning across days.
    let progress: [Int: (type: Int, queue: Int, due: Int, interval: Int)] = [0: (2, 2, 22, 10), 5: (3, 3, 20, 1)]
    var sql = """
        CREATE TABLE col (id integer PRIMARY KEY, crt integer NOT NULL, mod integer NOT NULL, scm integer NOT NULL,
          ver integer NOT NULL, dty integer NOT NULL, usn integer NOT NULL, ls integer NOT NULL, conf text NOT NULL,
          models text NOT NULL, decks text NOT NULL, dconf text NOT NULL, tags text NOT NULL);
        CREATE TABLE notes (id integer PRIMARY KEY, guid text NOT NULL, mid integer NOT NULL, mod integer NOT NULL,
          usn integer NOT NULL, tags text NOT NULL, flds text NOT NULL, sfld integer NOT NULL, csum integer NOT NULL,
          flags integer NOT NULL, data text NOT NULL);
        CREATE TABLE cards (id integer PRIMARY KEY, nid integer NOT NULL, did integer NOT NULL, ord integer NOT NULL,
          mod integer NOT NULL, usn integer NOT NULL, type integer NOT NULL, queue integer NOT NULL,
          due integer NOT NULL, ivl integer NOT NULL, factor integer NOT NULL, reps integer NOT NULL,
          lapses integer NOT NULL, left integer NOT NULL, odue integer NOT NULL, odid integer NOT NULL,
          flags integer NOT NULL, data text NOT NULL);
        INSERT INTO col VALUES (1, 1790838000, 0, 0, 11, 0, 0, 0, '{"schedVer":2,"creationOffset":180}', \
        \(sqlText(try jsonText(noteTypes))), \(sqlText(try jsonText(decks))), '{}', '{}');

        """
    for (index, note) in notes.enumerated() {
        let noteID = 1_700_000_000_000 + index
        let tags = note.tags.isEmpty ? "" : " \(note.tags) "
        sql += """
            INSERT INTO notes VALUES (\(noteID), 'n\(index)', \(note.type), 0, 0, \(sqlText(tags)), \
            \(sqlText(note.fields.joined(separator: "\u{1F}"))), '', 0, 0, '');

            """
        // A new card's due is its position.
        let (type, queue, due, interval) = progress[index] ?? (0, 0, index + 1, 0)
        for ordinal in note.cards {
            sql += """
                INSERT INTO cards VALUES (\(noteID * 10 + ordinal), \(noteID), \(note.deck), \(ordinal), 0, 0, \
                \(type), \(queue), \(due), \(interval), 2500, 0, 0, 0, 0, 0, 0, '');

                """
        }
    }
    return sql
}

/// `object` as JSON text.
func jsonText(_ object: Any) throws -> String {
    String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
}

/// `text` as a string literal of SQL.
func sqlText(_ text: String) -> String {
    "'\(text.replacingOccurrences(of: "'", with: "''"))'"
}

/// A span of whole hours, in seconds.
func hours(_ count: Int) -> TimeInterval {
    TimeInterval(count * 60 * 60)
}

/// The app's model for `name`'s window: on the sample cards in memory, and
/// for Settings' Backups tab, in `renderDataFolder`, with copies to list.
func model(for name: Window) throws -> AppModel {
    switch name {
    case .cards, .cardsImport, .cardsImportAnki, .about, .startAtLogin:
        return try AppModel(engine: try sampleEngine(at: .inMemory).engine)
    case .cardsAnkiImported: return try ankiImportedModel()
    case .appearances, .reviewPanel, .ladder: return try progressSettingsModel()
    case .diagnostics: return try focusHeldBackModel()
    case .backups: return try AppModel(engine: try backupsEngine())
    case .backupsFailed:
        let model = try AppModel(engine: try backupsEngine())
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
func window(_ name: Window, model: AppModel) throws -> NSWindow {
    switch name {
    case .cards:
        let window = CardsWindow(model: model)
        window.makeContent()
        return window
    case .cardsImport:
        let window = CardsWindow(model: model)
        window.makeContent(opening: try importingState(of: model))
        return window
    case .cardsImportAnki:
        let window = CardsWindow(model: model)
        window.makeContent(opening: try ankiImportingState(of: model))
        return window
    case .cardsAnkiImported:
        let window = CardsWindow(model: model)
        window.makeContent(opening: try ankiImportedState(of: model))
        return window
    case .backups, .backupsFailed: return settingsTabWindow(model: model, openingOn: .backups)
    case .appearances: return settingsTabWindow(model: model, openingOn: .appearances)
    case .reviewPanel: return settingsTabWindow(model: model, openingOn: .reviewPanel)
    case .ladder: return settingsTabWindow(model: model, openingOn: .ladder)
    case .about: return settingsTabWindow(model: model, openingOn: .about)
    case .startAtLogin:
        // The alert's own window, laid out as `runModal()` would show it,
        // for the real Ficha, the only one that asks.
        let alert = StartAtLogin.questionAlert(for: .real)
        alert.layout()
        return alert.window
    case .diagnostics:
        let mac = SystemMacSignals { model.now }
        mac.focusChanged(holdsBack: true)
        return AppWindow(title: "Diagnostics", content: DiagnosticsView(model: model, mac: mac))
    }
}

/// Settings, at the size it opens at, on `tab`.
func settingsTabWindow(model: AppModel, openingOn tab: SettingsTab) -> NSWindow {
    let window = AppWindow(
        tabs: SettingsTabViewController(
            model: model, captureShortcut: CaptureShortcutRegistration(), closeReviewPanel: {}, openingOn: tab))
    if let content = window.contentView {
        window.setContentSize(content.fittingSize)
    }
    return window
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
    // The sound file `--copy-sound` copies, which goes too.
    let copiedSound = URL.temporaryDirectory.appending(path: "RenderSound-\(UUID().uuidString).wav")
    defer { try? FileManager.default.removeItem(at: copiedSound) }
    let model = try model(for: name)
    let window = try window(name, model: model)
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
        case .copyImage(let picture):
            pasteboard.clearContents()
            pasteboard.setData(try picture.png(), forType: .png)
        case .copySound:
            try writeSampleTone(seconds: 12, to: copiedSound)
            pasteboard.clearContents()
            pasteboard.writeObjects([copiedSound as NSURL])
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
