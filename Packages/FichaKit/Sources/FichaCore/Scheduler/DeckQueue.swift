import Foundation

/// When the user will have met every new card of a deck (ADR 0034): a range
/// of days, each the start of its day, from the pace and the new cards of
/// the decks ahead of it in the queue.
public struct FinishDate: Sendable, Hashable, Codable {
    /// The day, if the user has appearances every day.
    public let soonest: Date
    /// The day, if the user has appearances on five days in seven: as many
    /// days from today as the soonest's, times seven fifths.
    public let latest: Date

    public init(soonest: Date, latest: Date) {
        self.soonest = soonest
        self.latest = latest
    }
}

/// A deck in the queue new cards come from (ADR 0034): a deck at the top of
/// the tree, with the decks inside it, which still has new cards.
public struct QueuedDeck: Sendable, Hashable {
    /// The deck's whole name, or `""` for Default.
    public let deck: String
    /// Its new cards still to meet, each way a card goes counting as one, as
    /// the day's new cards count them.
    public let newCards: Int
    /// When the user will have met them all, or nil when the pace brings no
    /// new card.
    public let finish: FinishDate?

    public init(deck: String, newCards: Int, finish: FinishDate?) {
        self.deck = deck
        self.newCards = newCards
        self.finish = finish
    }
}

/// Where a deck goes in the queue when the user moves it.
public enum QueuePosition: Sendable, Hashable {
    /// Ahead of every other deck.
    case first
    /// After every other deck.
    case last
    /// At this index among the other decks of the queue, as
    /// `ReviewSettings.queue(of:now:calendar:)` lists them, from 0, the
    /// first.
    case at(Int)
}

extension ReviewSettings {
    /// The queue new cards come from at `now`, out of `cards` (ADR 0034):
    /// each deck at the top of the tree that has new ways, in the order its
    /// last new way comes, as `pickCards` brings them, one deck at a time,
    /// a priority card's first, so a deck the user made a priority comes
    /// first, and a deck with one inside it where its other new ways come.
    /// A card that goes both ways counts its back-first way, still to come,
    /// beside its front-first one.
    /// Each deck's finish date counts, from the start of `now`'s day, by
    /// `calendar`, the days `newCardsPerDay` takes to bring its last new way
    /// and those ahead of it, but for those today may still bring: none once
    /// `activeHours` are over, and none past the day's limit. Soonest if
    /// every day has appearances, latest if five days in seven do; so days
    /// without appearances move it later. With no new cards a day, it has
    /// none.
    public func queue(of cards: CardsInReviews, now: Date, calendar: Calendar) -> [QueuedDeck] {
        let metToday = cards.firstReviews(onTheDayOf: now, calendar: calendar).count
        let leftToday =
            calendar.component(.hour, from: now) < activeHours.upperBound ? max(0, newCardsPerDay - metToday) : 0
        let today = calendar.startOfDay(for: now)
        return cards.decksWithNewWays().map { deck in
            QueuedDeck(
                deck: deck.deck, newCards: deck.newWays,
                finish: finishDate(after: deck.through, leftToday: leftToday, from: today, calendar: calendar))
        }
    }

    /// When the new way at `slot`, counting from 1, the first to come, has
    /// come, at `newCardsPerDay`, once today brings `leftToday`: the start
    /// of a day from `today`, by `calendar`, or nil with no new cards a day.
    private func finishDate(after slot: Int, leftToday: Int, from today: Date, calendar: Calendar) -> FinishDate? {
        guard newCardsPerDay > 0 else {
            return nil
        }
        let soonest = (max(0, slot - leftToday) + newCardsPerDay - 1) / newCardsPerDay
        let latest = (soonest * 7 + 4) / 5
        guard let soonestDay = calendar.date(byAdding: .day, value: soonest, to: today),
            let latestDay = calendar.date(byAdding: .day, value: latest, to: today)
        else {
            return nil
        }
        return FinishDate(soonest: soonestDay, latest: latestDay)
    }
}

extension CardsInReviews {
    /// The decks at the top of the tree that have new ways, in the order
    /// their last new ways come, as `pickCards` brings them: a priority
    /// card's first, and then one deck at a time, by the queue (ADR 0034).
    /// Each with its new ways, a card's back-first way still to come counting
    /// beside its front-first one, as the new cards a day count them, and how
    /// many new ways come up to its last, its own and those ahead of it.
    func decksWithNewWays() -> [(deck: String, newWays: Int, through: Int)] {
        let new = splitByPriority(newWays)
        let ranks = Dictionary(uniqueKeysWithValues: queue.enumerated().map { ($0.element.deck, $0.offset) })
        // `ways` in the order of their decks in the queue, each deck's in
        // the order they had.
        func byDeck(_ ways: [CardWay]) -> [(way: CardWay, deck: String)] {
            ways.enumerated()
                .map { (way: $0.element, deck: topDecks[$0.element.cardID] ?? "", order: $0.offset) }
                .sorted { (ranks[$0.deck] ?? Int.max, $0.order) < (ranks[$1.deck] ?? Int.max, $1.order) }
                .map { (way: $0.way, deck: $0.deck) }
        }
        var counts: [String: Int] = [:]
        var through: [String: Int] = [:]
        var total = 0
        for (way, deck) in byDeck(new.priority) + byDeck(new.others) {
            let count = way.way == .frontFirst && backFirstWaysToCome.contains(way.cardID) ? 2 : 1
            total += count
            counts[deck, default: 0] += count
            through[deck] = total
        }
        return through.sorted { $0.value < $1.value }
            .map { (deck: $0.key, newWays: counts[$0.key] ?? 0, through: $0.value) }
    }

    /// The places that put `deck`, a deck at the top of the tree, at
    /// `position` among the other decks that have new ways, as
    /// `ReviewSettings.queue(of:now:calendar:)` lists them, as of `now`
    /// (ADR 0034): `deck` and the decks it passes take each other's places,
    /// the earliest for the first, `deck`'s being `now` when it has no card
    /// in Lucas's reviews, each a second at least after the one before, so
    /// that decks that came in together part. A deck listed first for its
    /// priority cards alone keeps its place, and its new cards still come
    /// first, as do those of a priority deck `deck` holds. Only the places
    /// that change, by deck.
    public func places(putting deck: String, at position: QueuePosition, now: Date) -> [String: Date] {
        let held = Dictionary(uniqueKeysWithValues: queue.map { ($0.deck, $0.place) })
        var order = decksWithNewWays().map(\.deck).filter { $0 != deck }
        switch position {
        case .first:
            order.insert(deck, at: 0)
        case .last:
            order.append(deck)
        case .at(let index):
            order.insert(deck, at: min(max(index, 0), order.count))
        }
        let withOtherNewWays = Set(splitByPriority(newWays).others.compactMap { topDecks[$0.cardID] })
        order = order.filter { $0 == deck || withOtherNewWays.contains($0) }
        var places: [String: Date] = [:]
        var previous: Date?
        for (name, place) in zip(order, order.map { held[$0] ?? now }.sorted()) {
            let parted = previous.map { max(place, $0 + 1) } ?? place
            if parted != held[name] {
                places[name] = parted
            }
            previous = parted
        }
        return places
    }
}
