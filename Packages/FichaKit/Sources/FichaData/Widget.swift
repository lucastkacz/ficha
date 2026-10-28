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

extension WidgetTimeline {
    /// What it shows from `now` on: what it shows then, from the last entry
    /// at or before it, if any, then each later entry, and when WidgetKit
    /// asks for it again.
    fileprivate func shown(from now: Date) -> (current: WidgetContent?, later: [Entry], refreshAt: Date?) {
        (entries.last { $0.date <= now }?.content, entries.filter { $0.date > now }, refreshAt)
    }
}

/// When the app asks WidgetKit to reload the widget, whose reloads WidgetKit
/// counts against a daily budget ("Keeping a widget up to date"): the first
/// time, as the database may have changed while the app didn't run, and then
/// only when what the widget shows from then on changes, so a write that
/// changes no card it shows, or a sync, spends none.
public struct WidgetReloading: Sendable {
    /// The timeline of the last reload, or nil before the first.
    private var reloaded: WidgetTimeline?

    public init() {}

    /// Whether the app asks WidgetKit to reload the widget, now that it shows
    /// `timeline`, as the engine works it out now: when that shows something
    /// else than the timeline of the last reload from now on, or when there
    /// was none. A reload makes `timeline` the last one.
    public mutating func reloads(for timeline: WidgetTimeline) -> Bool {
        if let reloaded, let now = timeline.entries.first?.date, reloaded.shown(from: now) == timeline.shown(from: now)
        {
            return false
        }
        reloaded = timeline
        return true
    }
}

/// The link a click on the widget opens in the app: a review now, which
/// starts with the card the widget showed, the way it showed it, when it
/// showed one. In a URL with the app's own scheme, like
/// `ficha://review-now?card=12&way=backFirst`, which the app's Info.plist
/// claims (`FICHA_URL_SCHEME` in `project.yml`).
public struct WidgetLink: Sendable, Equatable {
    /// The card the review now starts with, or nil for a review now as usual.
    public let startingWith: CardWay?

    public init(startingWith: CardWay?) {
        self.startingWith = startingWith
    }

    /// The link a URL with `scheme` names, or nil when it names none, as
    /// another app's link may not.
    public init?(_ url: URL, scheme: String) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme == scheme, components.host == reviewNowHost, components.path.isEmpty
        else {
            return nil
        }
        let items = components.queryItems ?? []
        let card = items.first { $0.name == "card" }?.value
        let way = items.first { $0.name == "way" }?.value
        switch (card, way) {
        case (nil, nil):
            startingWith = nil
        case (let card?, let way?):
            guard let cardID = Int64(card), let way = Way(rawValue: way) else {
                return nil
            }
            startingWith = CardWay(cardID: cardID, way: way)
        case (_?, nil), (nil, _?):
            return nil
        }
    }

    /// The link as a URL with `scheme`, the app's, or nil when the scheme
    /// can't make one.
    public func url(scheme: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = reviewNowHost
        if let startingWith {
            components.queryItems = [
                URLQueryItem(name: "card", value: String(startingWith.cardID)),
                URLQueryItem(name: "way", value: startingWith.way.rawValue),
            ]
        }
        return components.url
    }
}

/// The part of the widget's link that names a review now.
private let reviewNowHost = "review-now"

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

    /// The cards a review now brings when Lucas clicks the widget on `first`,
    /// a card the way it showed it: those `reviewNow(_:)` brings, with `first`
    /// first when review now brings it. When it no longer does, as when he
    /// reviewed it meanwhile, review now starts as usual.
    public func reviewNow(_ settings: ReviewSettings, startingWith first: CardWay) throws(EngineError)
        -> [PanelCard]
    {
        var cards = try reviewNow(settings)
        if let index = cards.firstIndex(where: { $0.cardWay == first }) {
            cards.insert(cards.remove(at: index), at: 0)
        }
        return cards
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
