import Darwin
import FichaCore
import FichaData
import FichaSVG
import Foundation

// `make preview-import` runs this through `scripts/preview-import.sh`, which
// builds it and watches it for a hang: "An import's numbers" in
// `docs/development.md` explains it. It reads a downloaded file through the
// engine alone, as the app does, in an engine in memory, so Lucas's cards stay
// out of it, and it writes nothing next to the file.

let usage = "Usage: ImportPreview [--dump <output>] <file>: run it through make preview-import, which builds it first."

/// What the command line asks for.
struct Request: Sendable {
    let file: URL
    /// Where to write the file's cards, one line each, or nil to only time
    /// the preview.
    let dump: URL?

    /// What `arguments` ask for, or nil when they aren't the usage's.
    init?(_ arguments: [String]) {
        switch arguments.count {
        case 1 where !arguments[0].hasPrefix("--"):
            file = URL(filePath: arguments[0])
            dump = nil
        case 3 where arguments[0] == "--dump" && !arguments[2].hasPrefix("--"):
            dump = URL(filePath: arguments[1])
            file = URL(filePath: arguments[2])
        default:
            return nil
        }
    }
}

/// A line of a dump for a card that came in: what the import put on each side
/// and where it put the card, with nothing that changes from one run to the
/// next, such as its id or when it came in.
struct CardLine: Encodable {
    let front: String
    let back: String
    let frontImage: ImageName?
    let backImage: ImageName?
    let frontSound: SoundName?
    let backSound: SoundName?
    let tags: [String]
    let deck: String
    let type: CardType?
    let source: String?
    let bothWays: Bool
    let buried: Bool

    init(_ card: Card) {
        front = card.front
        back = card.back
        frontImage = card.frontImage
        backImage = card.backImage
        frontSound = card.frontSound
        backSound = card.backSound
        tags = card.tags
        deck = card.deck
        type = card.type
        source = card.source
        bothWays = card.bothWays
        buried = if case .buried = card.standing { true } else { false }
    }
}

/// A line of a dump for a card, or a text file's line, that stays out: its
/// place in the file, as `LeftOutLine.line` says, and why, as the engine names
/// the reason.
struct LeftOutDumpLine: Encodable {
    let leftOut: String
    let line: Int

    init(_ line: LeftOutLine) {
        leftOut = String(describing: line.reason)
        self.line = line.line
    }
}

/// `cards` and then `leftOut`, one JSON object a line, so that two dumps diff
/// line by line and a script reads them: the cards sorted by their front and
/// back, whatever order they came in, and the lines left out by their place.
func dumpLines(of cards: [Card], leavingOut leftOut: [LeftOutLine]) throws -> [String] {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    func encoded(_ value: some Encodable) throws -> String {
        String(decoding: try encoder.encode(value), as: UTF8.self)
    }
    let cardLines = try cards.map { (front: $0.front, back: $0.back, line: try encoded(CardLine($0))) }
        .sorted { ($0.front, $0.back, $0.line) < ($1.front, $1.back, $1.line) }
        .map(\.line)
    return cardLines + (try leftOut.sorted { $0.line < $1.line }.map { try encoded(LeftOutDumpLine($0)) })
}

/// The number `/usr/bin/time -l` calls peak memory footprint, in bytes, for
/// this process so far, or nil when macOS doesn't say.
func peakMemoryFootprint() -> UInt64? {
    var resources = rusage_info_v4()
    let status = withUnsafeMutablePointer(to: &resources) { pointer in
        pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
            proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
        }
    }
    return status == 0 ? resources.ri_lifetime_max_phys_footprint : nil
}

/// How many stay out, and how many for each reason the engine names.
func leftOutSummary(of preview: ImportPreview) -> String {
    let reasons = preview.leftOutCounts.map { "\(String(describing: $0.reason)) \($0.count)" }
    return "left out \(preview.leftOut.count)" + (reasons.isEmpty ? "" : " (\(reasons.joined(separator: ", ")))")
}

/// Previews the file, in a new engine in memory, drawing its SVGs as the app
/// does, and prints one line with what it took and what it found. With a
/// dump, it also imports the file there, with the Import sheet's choices for
/// an Anki package: every card with its progress, none repeating any of an
/// empty engine's. So the line's peak memory footprint covers that import too.
func run(_ request: Request) async throws {
    let engine = try Engine(location: .inMemory, time: SystemTimeSource(), drawingSVGsWith: { InProcessSVGDrawer() })
    let clock = ContinuousClock()
    let started = clock.now
    let preview = try await engine.previewImport(of: request.file)
    let seconds = started.duration(to: clock.now) / .seconds(1)
    if let dump = request.dump {
        try engine.importCards(preview, choosing: ImportChoices(progress: .brought))
        let lines = try dumpLines(of: try engine.cards(), leavingOut: preview.leftOut)
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: dump, options: .atomic)
    }
    let peak = peakMemoryFootprint().map { String(format: "%.0f MB", Double($0) / 1_000_000) } ?? "unknown"
    print(
        "\(preview.fileName): \(String(format: "%.2f", seconds)) s, cards \(preview.cardCount), "
            + "with images dropped \(preview.cardsWithImagesDropped), "
            + "with sounds dropped \(preview.cardsWithSoundsDropped), "
            + "with unreadable sounds left out \(preview.cardsWithUnreadableSoundsLeftOut), "
            + "\(leftOutSummary(of: preview)), peak memory footprint \(peak)")
}

guard let request = Request(Array(CommandLine.arguments.dropFirst())) else {
    FileHandle.standardError.write(Data((usage + "\n").utf8))
    exit(2)
}

// Away from the main thread, which WebKit draws an import's SVGs on and an
// import waits for: `InProcessSVGDrawer` draws nothing when called from it. A
// run loop serves it, as it serves the main actor.
Task.detached {
    do {
        try await run(request)
        exit(0)
    } catch {
        let message = "\(request.file.lastPathComponent): \(error.localizedDescription)\n"
        FileHandle.standardError.write(Data(message.utf8))
        exit(1)
    }
}
RunLoop.main.run()
