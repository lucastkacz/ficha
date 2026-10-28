import FichaCore
import Foundation
internal import GRDB

/// What the widget shows at a time, as the engine decides it (#171).
public enum WidgetContent: Sendable, Equatable {
    /// The card a review now would start with, the way it would show it.
    case card(WidgetCard)
    /// No card waits, and the next one comes at this time, by the engine's
    /// time.
    case nextCard(at: Date)
    /// No card waits, and none comes as time passes: those Lucas has are
    /// buried, flagged or set aside, or new while he meets none a day.
    case noneComing
    /// Lucas has no cards at all.
    case noCards
}

/// The card the widget shows: the side the review panel would show first,
/// with that side's image, so the widget never gives away the side Lucas
/// tries to remember.
public struct WidgetCard: Sendable, Equatable {
    /// The card, by id, and the way review now would show it, which a click
    /// on the widget asks review now to start with.
    public let way: CardWay
    /// Whether it's a new way, for its first view.
    public let isNew: Bool
    /// The side it shows: the front front first, and the back back first.
    public let side: CardSide
    /// That side's text, or empty when it has none.
    public let text: String
    /// That side's image, or nil when it has none.
    public let image: ImageName?
    /// Whether the side holds only a sound, which the widget shows as a
    /// speaker.
    public let showsSpeaker: Bool

    public init(way: CardWay, isNew: Bool, side: CardSide, text: String, image: ImageName?, showsSpeaker: Bool) {
        self.way = way
        self.isNew = isNew
        self.side = side
        self.text = text
        self.image = image
        self.showsSpeaker = showsSpeaker
    }
}

/// What the widget shows from now on, as if Lucas rated nothing in between,
/// by the engine's time.
public struct WidgetTimeline: Sendable, Equatable {
    /// What the widget shows from a time on, until the next entry.
    public struct Entry: Sendable, Equatable {
        public let date: Date
        public let content: WidgetContent

        public init(date: Date, content: WidgetContent) {
            self.date = date
            self.content = content
        }
    }

    /// The entries, the first one now.
    public let entries: [Entry]
    /// When WidgetKit asks for the timeline again, by the engine's time, as
    /// it stopped before what the widget shows stops changing, or nil when
    /// only a change to the cards changes it.
    public let refreshAt: Date?
}

extension Engine {
    /// What the widget shows from now on, as `NextWayTimeline` says, or that
    /// Lucas has no cards at all. It picks the cards with the settings that
    /// decide a card's progress, which the database holds, and Ficha's own
    /// for the rest, which the app keeps in preferences the widget can't
    /// read: the card it shows differs from the one review now starts with
    /// only when review now brings a single card and a priority card is new.
    public func widgetTimeline() throws(EngineError) -> WidgetTimeline {
        let now = time.now
        return try read { db in
            guard try Table("card").fetchCount(db) > 0 else {
                return WidgetTimeline(entries: [WidgetTimeline.Entry(date: now, content: .noCards)], refreshAt: nil)
            }
            var settings = ReviewSettings.defaults
            settings.progress = try storedProgressSettings(in: db) ?? settings.progress
            let cards = try cardsThatShowUp(in: db)
            let timeline = try settings.nextWayTimeline(cards: cards.inReviews, from: now, calendar: calendar)
            return WidgetTimeline(
                entries: try timeline.entries.map { entry in
                    WidgetTimeline.Entry(date: entry.date, content: try widgetContent(entry.nextWay, in: db))
                },
                refreshAt: timeline.refreshAt)
        }
    }
}

/// What the widget shows for `nextWay`, out of the cards in `db`.
private func widgetContent(_ nextWay: NextWay, in db: Database) throws -> WidgetContent {
    switch nextWay {
    case .waiting(let way, let isNew):
        let card = try existingCard(way.cardID, in: db)
        let side = way.way.upperSide
        let text = card.text(on: side)
        let image = card.image(on: side)
        return .card(
            WidgetCard(
                way: way, isNew: isNew, side: side, text: text, image: image,
                showsSpeaker: text.isEmpty && image == nil && card.sound(on: side) != nil))
    case .comesAt(let time):
        return .nextCard(at: time)
    case .noneComing:
        return .noneComing
    }
}
