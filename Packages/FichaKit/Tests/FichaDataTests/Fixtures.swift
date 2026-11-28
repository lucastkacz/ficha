import FichaCore
import FichaData
import Foundation
import Testing
import ZIPFoundation

/// A card for a test to make: it always has a front and a back, and no tags,
/// source, images or sounds unless the test gives them. A nil type is no type.
func card(
    _ type: CardType?,
    front: String,
    back: String,
    tags: [String] = [],
    source: String? = nil,
    frontImage: ImageName? = nil,
    backImage: ImageName? = nil,
    frontSound: SoundName? = nil,
    backSound: SoundName? = nil
) throws -> CardContent {
    try #require(
        CardContent(
            type: type, front: front, back: back, tags: tags, source: source, frontImage: frontImage,
            backImage: backImage, frontSound: frontSound, backSound: backSound))
}

/// What `card` holds, its images and sounds included, as a card is made from
/// it, to compare with the content a test gave it.
func content(of card: Card) -> CardContent? {
    CardContent(
        type: card.type, front: card.front, back: card.back, tags: card.tags, source: card.source,
        frontImage: card.frontImage, backImage: card.backImage, frontSound: card.frontSound,
        backSound: card.backSound)
}

extension ReviewLogEntry {
    /// The entry as it was answered or placed, with the interval it set,
    /// without its ID unique across devices or the entry it answered, which
    /// are random, for a test to compare with the entries it expects.
    var withoutIDs: ReviewLogEntry {
        switch kind {
        case .placement(let placement):
            ReviewLogEntry(placing: cardID, way: way, on: placement, at: answeredAt)
        case .review:
            ReviewLogEntry(
                cardID: cardID, way: way, kind: kind, answeredAt: answeredAt, responseTime: responseTime,
                trigger: trigger, isAhead: isAhead, interval: interval)
        }
    }
}

/// Where a way stands, as a test compares it: its stage and when it's due,
/// without its interval and memory, which FSRS works out.
struct StageAndDue: Equatable, CustomStringConvertible {
    let stage: WayStanding.Stage
    let due: Date

    var description: String {
        "\(stage) due \(due)"
    }
}

/// A way on learning step `step`, counted from 0, due at `due`.
func learning(step: Int, due: Date) -> StageAndDue {
    StageAndDue(stage: .learning(step: step), due: due)
}

/// A way graduated, due at `due`.
func graduated(due: Date) -> StageAndDue {
    StageAndDue(stage: .graduated, due: due)
}

/// A way that lapsed, on relearning step `step`, counted from 0, due at
/// `due`.
func relearning(step: Int, due: Date) -> StageAndDue {
    StageAndDue(stage: .relearning(step: step), due: due)
}

extension WayStanding {
    /// Its stage and when it's due, or nil while it's new.
    var stageAndDue: StageAndDue? {
        guard let stage, let due else {
            return nil
        }
        return StageAndDue(stage: stage, due: due)
    }
}

/// Lucas's note on what to fix in a card he flags, which isn't blank.
func note(_ text: String) throws -> FlagNote {
    try #require(FlagNote(text))
}

/// Creates one word card with this front, in Default, as the Cards window's
/// form does, and returns it: a new card, after the ones before it.
@discardableResult
func newCard(_ front: String, in engine: Engine) throws -> Card {
    try newCard(card(.word, front: front, back: "Lo que quiere decir «\(front)»."), in: engine)
}

/// Creates one card with `content`, in Default, as the Cards window's form
/// does, and returns it: a new card, after the ones before it.
@discardableResult
func newCard(_ content: CardContent, in engine: Engine) throws -> Card {
    try engine.create(content)
}

extension Engine {
    /// The flagged cards, which wait in their decks to be fixed, as their
    /// standing says, the first flagged first: a card set aside on its own,
    /// flagged or not, stands set aside.
    func flaggedCards() throws -> [Card] {
        let flagged = try cards().compactMap { card -> (card: Card, flag: Flag)? in
            guard case .flagged(let flag) = card.standing else { return nil }
            return (card, flag)
        }
        return flagged.sorted { ($0.flag.flaggedAt, $0.card.id) < ($1.flag.flaggedAt, $1.card.id) }.map(\.card)
    }

    /// Records the first review of a card's new way, front first unless the
    /// test says otherwise, rated again, as the review panel does when Lucas
    /// rates it, from review now: the way stands on the first learning step,
    /// due an hour later.
    func meet(_ card: Card, way: Way = .frontFirst) throws {
        try record(
            .review(.again), of: card.id, way: way, responseTime: .seconds(8), trigger: .reviewNow, settings: .defaults)
    }

    /// Records a review of a card's due way, front first unless the test
    /// says otherwise, with `rating`, as the review panel does when Lucas
    /// rates it, from review now, with the default settings.
    func review(_ card: Card, _ rating: Rating, way: Way = .frontFirst) throws {
        try record(
            .review(rating), of: card.id, way: way, responseTime: .seconds(3), trigger: .reviewNow,
            settings: .defaults)
    }

    /// Moves a card's new way, front first unless the test says otherwise,
    /// on with the default settings: meets it now, and then rates it good
    /// `goods` times, each time it's due, moving `time` forward to it. One
    /// good puts it on the second learning step, due 4 hours later, and two
    /// graduate it.
    func climb(_ card: Card, goods: Int, way: Way = .frontFirst, movingForward time: ManualTimeSource) throws {
        try meet(card, way: way)
        for _ in 0..<goods {
            try reviewWhenDue(card, .good, way: way, movingForward: time)
        }
    }

    /// Climbs a card's way, front first unless the test says otherwise, from
    /// new if it is, with good each time it's due, moving `time` forward to
    /// it, until it's learned: graduated with an interval of 21 days or
    /// more, with the default settings.
    func climbUntilLearned(_ card: Card, way: Way = .frontFirst, movingForward time: ManualTimeSource) throws {
        let scheduler = ReviewSettings.defaults.scheduler
        if try standing(of: card.id, way: way, with: scheduler) == .new {
            try meet(card, way: way)
        }
        while try !standing(of: card.id, way: way, with: scheduler).isLearned {
            try reviewWhenDue(card, .good, way: way, movingForward: time)
        }
    }

    /// Graduates a new card's way, front first unless the test says
    /// otherwise, with two goods, and then makes it lapse `times` times, each
    /// an again when it's due and a good when it's due again, so it stays
    /// graduated, moving `time` forward to each.
    func lapse(_ card: Card, times: Int, way: Way = .frontFirst, movingForward time: ManualTimeSource) throws {
        try climb(card, goods: 2, way: way, movingForward: time)
        for _ in 0..<times {
            try reviewWhenDue(card, .again, way: way, movingForward: time)
            try reviewWhenDue(card, .good, way: way, movingForward: time)
        }
    }

    /// Moves `time` forward until a card's way, front first unless the test
    /// says otherwise, is due with the default settings, and reviews it with
    /// `rating`.
    func reviewWhenDue(
        _ card: Card, _ rating: Rating, way: Way = .frontFirst, movingForward time: ManualTimeSource
    ) throws {
        time.move(to: try #require(try standing(of: card.id, way: way, with: ReviewSettings.defaults.scheduler).due))
        try review(card, rating, way: way)
    }

    /// Opens the review panel with `cards` on a clock that never moves, for a
    /// test that doesn't time Lucas: it answers with a response time of its
    /// own.
    func openPanel(_ trigger: Trigger, with cards: [PanelCard], settings: ReviewSettings) throws -> ReviewPanelState {
        try openPanel(trigger, with: cards, settings: settings, clock: ManualClock())
    }

    /// Opens the review panel with `cards`, timing Lucas on `clock`, with the
    /// note it offers to flag a card forgotten often with, as the app writes
    /// it.
    func openPanel(
        _ trigger: Trigger, with cards: [PanelCard], settings: ReviewSettings, clock: some Clock<Duration>
    ) throws -> ReviewPanelState {
        try openPanel(
            trigger, with: cards, settings: settings, clock: clock,
            forgottenOftenNote: { forgotten in
                switch forgotten.way {
                case .frontFirst: "Forgotten \(forgotten.times) times"
                case .backFirst: "Forgotten \(forgotten.times) times back first"
                }
            })
    }
}

extension ManualTimeSource {
    /// Moves time forward to `date`.
    func move(to date: Date) {
        advance(by: date.timeIntervalSince(now))
    }
}

/// What a test's Mac tells the engine, as the app reads it from the OS: by
/// default, a Mac awake since Ficha started, which doesn't say how long Lucas
/// has been idle, with nothing holding appearances back.
struct FakeMac: DeviceSignals {
    var isAsleep = false
    var lastWake: Date? = nil
    var idleTime: Duration? = nil
    var suppressions: Set<Suppression> = []
    var suppressionEnds: [Suppression: Date] = [:]
}

/// The calendar of a Mac in Buenos Aires, by whose clock the tests count
/// Ficha's days, whatever time zone runs them.
func buenosAiresCalendar() throws -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "America/Argentina/Buenos_Aires"))
    return calendar
}

/// 9 in the morning of a day in October 2026, by `calendar`.
func morning(of day: Int, in calendar: Calendar) throws -> Date {
    try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 9)))
}

/// An appearance as it showed: when, and the cards it brought, in their
/// order.
struct ShownAppearance: Equatable {
    let time: Date
    let cards: [PanelCard]

    /// The new cards it brought, for their first reviews.
    var newCards: [Card] {
        cards.compactMap { card -> Card? in
            guard case .new(let new, _) = card else {
                return nil
            }
            return new
        }
    }
}

/// The appearances that come in the `dayCount` days from `start`, by
/// `settings`, in an engine in memory of their own, by `calendar`, with
/// `newCards` new cards created at `start`, on a Mac awake all along that
/// holds none back: Lucas answers each card of an appearance good a minute
/// after it shows, and closes it then. The engine is asked for one at the
/// time an appearance waits for, when it names one, and else every 10
/// minutes by the clock.
func appearances(
    over dayCount: Int, from start: Date, newCards: Int, settings: ReviewSettings, calendar: Calendar
) throws -> [ShownAppearance] {
    let time = ManualTimeSource(now: start)
    let engine = try Engine(location: .inMemory, time: time, ids: CountingIDSource(), calendar: calendar)
    for number in 1...newCards {
        try newCard("palabra \(number)", in: engine)
    }
    let end = start + days(dayCount)
    var shown: [ShownAppearance] = []
    while time.now < end {
        switch try engine.checkAppearance(settings, mac: FakeMac()) {
        case .show(let cards):
            shown.append(ShownAppearance(time: time.now, cards: cards))
            var panel = try engine.openPanel(.appearance, with: cards, settings: settings)
            time.advance(by: minutes(1))
            for _ in cards {
                try panel.answer(.review(.good), responseTime: .seconds(5))
            }
            panel.close(.byLucas)
        case .notNow(let reason):
            let tenMinutes = minutes(10)
            let nextTen = ((time.now.timeIntervalSince1970 / tenMinutes).rounded(.down) + 1) * tenMinutes
            time.move(to: reason.until ?? Date(timeIntervalSince1970: nextTen))
        }
    }
    return shown
}

/// A span of whole minutes, in seconds.
func minutes(_ count: Int) -> TimeInterval {
    TimeInterval(count * 60)
}

/// A span of whole hours, in seconds.
func hours(_ count: Int) -> TimeInterval {
    TimeInterval(count * 60 * 60)
}

/// A span of whole days, in seconds.
func days(_ count: Int) -> TimeInterval {
    TimeInterval(count * 24 * 60 * 60)
}

extension CardsWindowState {
    /// Opens `file` with Open Deck…, as the app does, and waits for the
    /// reading, after which How fast? asks for its deck.
    mutating func openDeckAndWait(_ file: URL) async {
        if let work = openDeck(file) {
            finishOpenDeck(await work.run())
        }
    }
}

/// Writes a deck's `.ficha` to `file`, as another Ficha, or a person by hand,
/// would: a zip holding `text`, a text file of cards named after the file,
/// `files` beside it, each a name and what it holds, such as its cards'
/// images and sounds, and a `deck.json` with no emoji or description.
func writeDeckFile(at file: URL, text: String, files: [(name: String, data: Data)] = []) throws {
    try writeDeckFile(at: file, textFile: Data(text.utf8), files: files)
}

/// Writes a deck's `.ficha` to `file` as `writeDeckFile(at:text:files:)`
/// does, with `textFile` as its text file's bytes, which needn't be UTF-8.
func writeDeckFile(at file: URL, textFile: Data, files: [(name: String, data: Data)] = []) throws {
    let archive = try Archive(url: file, accessMode: .create, pathEncoding: nil)
    let name = file.deletingPathExtension().lastPathComponent + ".txt"
    let held = Data(#"{"description": null, "emoji": null}"#.utf8)
    let all: [(name: String, data: Data)] = [(name, textFile), ("deck.json", held)] + files
    for (path, data) in all {
        try archive.addEntry(
            with: path, type: .file, uncompressedSize: Int64(data.count), compressionMethod: .deflate
        ) { position, size in
            data.subdata(in: Int(position)..<Int(position) + size)
        }
    }
}

extension Engine {
    /// Reads the deck's `.ficha` at `file` and adds its deck, as Open Deck…
    /// and How fast?'s Start do, and returns what the import did.
    @discardableResult
    func addDeck(at file: URL) async throws -> ImportOutcome {
        try addDeck(try await readDeckFile(at: file))
    }
}
