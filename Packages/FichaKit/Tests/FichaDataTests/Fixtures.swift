import FichaCore
import FichaData
import Foundation
import Testing

/// A card for a test to approve a capture into: it always has a front and a
/// back, and no tags, source, images or sounds unless the test gives them. A
/// nil type is no type.
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

/// Approves a capture into one word card with this front, the way refining
/// saves cards, and returns the card: a new card, after the ones approved
/// before it.
@discardableResult
func approveCard(_ front: String, in engine: Engine) throws -> Card {
    try approve(card(.word, front: front, back: "Lo que quiere decir «\(front)»."), in: engine)
}

/// Approves a capture into one card with `content`, the way refining saves
/// cards, and returns the card: a new card, after the ones approved before it.
@discardableResult
func approve(_ content: CardContent, in engine: Engine) throws -> Card {
    let capture = try engine.newCapture(content.front)
    return try #require(try engine.approve(capture.id, into: [content]).first)
}

extension Engine {
    /// Saves a capture that repeats no card or capture, and returns it.
    @discardableResult
    func newCapture(_ text: String, note: String? = nil, source: String? = nil) throws -> Capture {
        try #require(try capture(text: text, note: note, source: source).saved)
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
    /// note it offers to flag a card forgotten often with in English, as the
    /// app writes it on a Mac in English.
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

/// The calendar of a Mac in Buenos Aires, whose days start at midnight there,
/// whatever time zone runs the tests.
func buenosAiresCalendar() throws -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "America/Argentina/Buenos_Aires"))
    return calendar
}

/// 9 in the morning of a day in October 2026, by `calendar`.
func morning(of day: Int, in calendar: Calendar) throws -> Date {
    try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 9)))
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

extension CaptureResult {
    /// The capture, when it was saved, or nil when it was a duplicate.
    var saved: Capture? {
        guard case .saved(let capture) = self else {
            return nil
        }
        return capture
    }
}

extension CardsWindowState {
    /// Reads `file` for the Import sheet's preview, as the app does, and
    /// waits for the reading.
    mutating func previewImportAndWait(of file: URL) async {
        if let work = previewImport(of: file) {
            finishImportWork(await work.run())
        }
    }

    /// Imports the cards the Import sheet previews, as the app does, and
    /// waits for the import.
    mutating func importCardsAndWait() async {
        if let work = importCards() {
            finishImportWork(await work.run())
        }
    }
}
