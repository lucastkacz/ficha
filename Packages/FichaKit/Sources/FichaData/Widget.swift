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

    /// The link a click on the widget opens while it shows this: a review now
    /// that starts with its card, when it shows one, and as usual otherwise.
    public var link: WidgetLink {
        switch self {
        case .card(let card): WidgetLink(startingWith: card.way)
        case .nextCard, .noneComing, .noCards: WidgetLink(startingWith: nil)
        }
    }
}

/// The card the widget shows: the side the review panel would show first,
/// with that side's image, so the widget never gives away the side Lucas
/// tries to remember.
public struct WidgetCard: Sendable, Equatable {
    /// The card, by id, and the way review now would show it, which a click
    /// on the widget asks review now to start with.
    public let way: CardWay
    /// Whether it's a new way, for its first review.
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

/// What the widget needs of this Mac's own settings to pick the card a review
/// now would start with, which the app keeps in its preferences, where the
/// widget can't read them, so it hands them over: the rest, the settings that
/// decide a card's progress, the widget reads in the database.
public struct WidgetSettings: Sendable, Equatable {
    /// How many cards an appearance or a review now brings at most.
    public let cardsPerAppearance: Int

    /// What the widget needs of `settings`, this Mac's.
    public init(_ settings: ReviewSettings) {
        cardsPerAppearance = settings.cardsPerAppearance
    }

    /// The settings with `cardsPerAppearance` cards per appearance, or nil
    /// when that's fewer than one, which Settings never keeps.
    public init?(cardsPerAppearance: Int) {
        guard cardsPerAppearance >= 1 else { return nil }
        self.cardsPerAppearance = cardsPerAppearance
    }
}

/// What the widget shows from now on, as if Lucas rated nothing in between,
/// by the system's time, which WidgetKit's timeline runs on.
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

    /// The entries, the first one now, then one at the very time what the
    /// widget shows changes, each time it does.
    public let entries: [Entry]
    /// When WidgetKit asks for the timeline again, as it stopped before what
    /// the widget shows stops changing, or nil when only a change to the
    /// cards changes it.
    public let refreshAt: Date?

    /// The entries as WidgetKit takes them, at least about 5 minutes apart
    /// ("Keeping a widget up to date"): what changes sooner after an entry
    /// shows 5 minutes after it.
    public var spacedEntries: [Entry] {
        guard let first = entries.first else { return [] }
        var spaced = [first]
        for entry in entries.dropFirst() {
            guard let last = spaced.last, entry.date > last.date else { continue }
            let date = max(entry.date, last.date.addingTimeInterval(entrySpacing))
            if let content = content(at: date), content != last.content {
                spaced.append(Entry(date: date, content: content))
            }
        }
        return spaced
    }

    /// What it shows at `time`, from its last entry at or before it, or nil
    /// before its first.
    func content(at time: Date) -> WidgetContent? {
        entries.last { $0.date <= time }?.content
    }

    /// The same timeline `shift` sooner: by the system's time, when it was
    /// worked out on an engine's that runs `shift` ahead of it.
    fileprivate func sooner(by shift: Duration) -> WidgetTimeline {
        WidgetTimeline(
            entries: entries.map { entry in
                let content: WidgetContent =
                    if case .nextCard(let time) = entry.content {
                        .nextCard(at: time.adding(.zero - shift))
                    } else {
                        entry.content
                    }
                return Entry(date: entry.date.adding(.zero - shift), content: content)
            },
            refreshAt: refreshAt?.adding(.zero - shift))
    }
}

/// The least time between two entries of the widget's timeline in WidgetKit,
/// which asks for entries "at least about 5 minutes apart" ("Keeping a widget
/// up to date").
private let entrySpacing: TimeInterval = 5 * 60

extension WidgetTimeline {
    /// Whether the widget shows the same by `later`, worked out since, as by
    /// this one, at every time from `later`'s start until either is asked
    /// for again: where they stop, and where they put an entry, which only
    /// says what they look at, doesn't count. When this one was asked for
    /// again already, WidgetKit holds a timeline the app doesn't know, which
    /// is never the same.
    fileprivate func showsTheSame(as later: WidgetTimeline) -> Bool {
        guard let now = later.entries.first?.date else { return false }
        let until = [refreshAt, later.refreshAt].compactMap(\.self).min()
        if let until, until <= now {
            return false
        }
        let changes = (entries + later.entries).map(\.date).filter { date in
            date > now && until.map { date < $0 } ?? true
        }
        return ([now] + changes).allSatisfy { content(at: $0) == later.content(at: $0) }
    }
}

/// When the app looks at what the widget shows, and asks WidgetKit to reload
/// it, whose reloads WidgetKit counts against a daily budget of 40 to 70
/// ("Keeping a widget up to date"). The app, in the menu bar, with a review
/// panel that never activates it, is never in the foreground, which alone
/// would make them free. So it looks as it launches, since the database may
/// have changed while it didn't run, and then once a burst of changes to the
/// database stops, as a refine session's writes or a sync's do, and once the
/// review panel closes, which holds them back while it's open: each card
/// Lucas rates in it changes what the widget shows. And it reloads only when
/// what the widget shows from then on changed, so a write that changes no
/// card it shows spends none.
public struct WidgetReloading: Sendable {
    /// How long the app waits after a change to the database for another,
    /// before it looks at what the widget shows.
    public static let quietPeriod: Duration = .seconds(30)

    /// The timeline of the last reload, or nil before the first.
    private var reloaded: WidgetTimeline?
    /// When the last change to the database the app hasn't looked at came,
    /// or nil when it looked at them all.
    private var changedAt: Date?
    /// Whether the review panel is open.
    private var panelIsOpen = false

    public init() {}

    /// Notes a change to the database at `time`, and says when the app looks
    /// at what the widget shows for it: once the quiet period passed, unless
    /// another change comes first, or, while the review panel is open, as it
    /// closes, which it says by nil.
    public mutating func databaseChanged(at time: Date) -> Date? {
        changedAt = time
        return panelIsOpen ? nil : time.adding(Self.quietPeriod)
    }

    /// Whether the app looks at what the widget shows at `time`, for the
    /// changes to the database since its last look: once none came for the
    /// quiet period, while the review panel is closed. Then it takes them.
    public mutating func looks(at time: Date) -> Bool {
        guard !panelIsOpen, let changedAt, time >= changedAt.adding(Self.quietPeriod) else {
            return false
        }
        self.changedAt = nil
        return true
    }

    /// Notes that the review panel opened.
    public mutating func panelOpened() {
        panelIsOpen = true
    }

    /// Notes that the review panel closed, and says whether the app looks at
    /// what the widget shows now, for the changes to the database since its
    /// last look: any, made while the panel was open or just before.
    public mutating func panelClosed() -> Bool {
        panelIsOpen = false
        guard changedAt != nil else { return false }
        changedAt = nil
        return true
    }

    /// Whether the app asks WidgetKit to reload the widget, now that it shows
    /// `timeline`, as the engine works it out now: when that shows something
    /// else than the timeline of the last reload from now on, or when there
    /// was none.
    public func needsReload(for timeline: WidgetTimeline) -> Bool {
        reloaded.map { !$0.showsTheSame(as: timeline) } ?? true
    }

    /// Notes that the app asked WidgetKit to reload the widget, which shows
    /// `timeline` from then on.
    public mutating func recordReload(of timeline: WidgetTimeline) {
        reloaded = timeline
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
    /// Lucas has no cards at all, by the system's time, which WidgetKit's
    /// timeline runs on, and so does the clock Lucas reads the next card's
    /// time by. In Ficha Dev, whose debug menu moves the engine's time
    /// `shift` ahead of the system's, each entry, the next card's time and
    /// the refresh come `shift` sooner, as Ficha Dev's own time gets there;
    /// elsewhere `shift` is zero. It picks the cards as review now does, with
    /// the settings that decide a card's progress, which the database holds,
    /// and with `widgetSettings`, this Mac's own, which the app hands over.
    public func widgetTimeline(_ widgetSettings: WidgetSettings, engineAheadBy shift: Duration) throws(EngineError)
        -> WidgetTimeline
    {
        let now = time.now
        return try read { db in
            guard try Table("card").fetchCount(db) > 0 else {
                return WidgetTimeline(entries: [WidgetTimeline.Entry(date: now, content: .noCards)], refreshAt: nil)
            }
            // The pick reads the scheduler, the new cards a day and the cards per
            // appearance alone: Ficha's own fill in the rest, which it never
            // reads.
            var settings = ReviewSettings.defaults
            settings.progress = try FichaData.progressSettings(in: db)
            settings.cardsPerAppearance = widgetSettings.cardsPerAppearance
            let cards = try cardsThatShowUp(in: db)
            let timeline = try settings.nextWayTimeline(cards: cards.inReviews, from: now, calendar: calendar)
            return WidgetTimeline(
                entries: try timeline.entries.map { entry in
                    WidgetTimeline.Entry(date: entry.date, content: try widgetContent(entry.nextWay, in: db))
                },
                refreshAt: timeline.refreshAt)
        }
        .sooner(by: shift)
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
