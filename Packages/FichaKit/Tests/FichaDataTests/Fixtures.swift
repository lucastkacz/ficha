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

    /// Records the first view of a card's new way, front first unless the
    /// test says otherwise, as the review panel does when Lucas ends it, from
    /// review now.
    func meet(_ card: Card, way: Way = .frontFirst) throws {
        try record(
            .firstView, of: card.id, way: way, responseTime: .seconds(8), trigger: .reviewNow, settings: .defaults)
    }

    /// Records a review of a card's due way, front first unless the test
    /// says otherwise, with `rating`, as the review panel does when Lucas
    /// rates it, from review now, with the default settings.
    func review(_ card: Card, _ rating: Rating, way: Way = .frontFirst) throws {
        try record(
            .review(rating), of: card.id, way: way, responseTime: .seconds(3), trigger: .reviewNow,
            settings: .defaults)
    }

    /// Puts a card's new way, front first unless the test says otherwise, on
    /// `step` of the default ladder: its first view now, and then good each
    /// time it's due, moving `time` forward to it.
    func climb(_ card: Card, to step: Int, way: Way = .frontFirst, movingForward time: ManualTimeSource) throws {
        try meet(card, way: way)
        for _ in 0..<step {
            try reviewWhenDue(card, .good, way: way, movingForward: time)
        }
    }

    /// Moves `time` forward until a card's way on the default ladder, front
    /// first unless the test says otherwise, is due, and reviews it with
    /// `rating`.
    func reviewWhenDue(
        _ card: Card, _ rating: Rating, way: Way = .frontFirst, movingForward time: ManualTimeSource
    ) throws {
        time.move(to: try #require(try standing(of: card.id, way: way, on: ReviewSettings.defaults.ladder).due))
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
            trigger, with: cards, settings: settings, clock: clock, forgottenOftenNote: { "Forgotten \($0) times" })
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
