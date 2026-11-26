import Foundation

/// When the user will have met every new card of a deck (ADR 0034): a range
/// of days, each the start of its day, from the pace and the new cards of
/// the decks ahead of it in the queue.
public struct FinishDate: Sendable, Hashable, Codable {
    /// The day, if the user has appearances every day.
    public let soonest: Date
    /// The day, if the user has appearances five days a week.
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
    /// At this index among the other decks of the queue, from 0, the first.
    case at(Int)
}

extension ReviewSettings {
    /// The queue new cards come from at `now`, out of `cards` (ADR 0034):
    /// each deck at the top of the tree that has new ways, in the order its
    /// first new way comes, a priority card's first, as `pickCards` brings
    /// them, one deck at a time. A card that goes both ways counts its
    /// back-first way, still to come, beside its front-first one.
    /// Each deck's finish date counts, from the start of `now`'s day, by
    /// `calendar`, the days `newCardsPerDay` takes to bring its last new way
    /// and those ahead of it, but for those today may still bring: none once
    /// active hours are over, and none past the day's limit. Soonest if every
    /// day has appearances, latest if five days a week do; so days without
    /// appearances move it later. With no new cards a day, it has none.
    public func queue(of cards: CardsInReviews, now: Date, calendar: Calendar) -> [QueuedDeck] {
        let new = cards.splitByPriority(cards.newWays)
        let ranks = Dictionary(uniqueKeysWithValues: cards.queue.enumerated().map { ($0.element.deck, $0.offset) })
        // `ways` in the order of their decks in the queue, each deck's in
        // the order they had.
        func byDeck(_ ways: [CardWay]) -> [(way: CardWay, deck: String)] {
            ways.enumerated()
                .map { (way: $0.element, deck: cards.topDecks[$0.element.cardID] ?? "", order: $0.offset) }
                .sorted { (ranks[$0.deck] ?? .max, $0.order) < (ranks[$1.deck] ?? .max, $1.order) }
                .map { (way: $0.way, deck: $0.deck) }
        }
        var decks: [String] = []
        var newCards: [String: Int] = [:]
        var lastSlot: [String: Int] = [:]
        var slot = 0
        for (way, deck) in byDeck(new.priority) + byDeck(new.others) {
            let count = way.way == .frontFirst && cards.backFirstWaysToCome.contains(way.cardID) ? 2 : 1
            slot += count
            if newCards[deck] == nil {
                decks.append(deck)
            }
            newCards[deck, default: 0] += count
            lastSlot[deck] = slot
        }
        let metToday = cards.firstReviews(onTheDayOf: now, calendar: calendar).count
        let leftToday =
            calendar.component(.hour, from: now) < activeHours.upperBound ? max(0, newCardsPerDay - metToday) : 0
        let today = calendar.startOfDay(for: now)
        return decks.map { deck in
            QueuedDeck(
                deck: deck, newCards: newCards[deck] ?? 0,
                finish: finishDate(after: lastSlot[deck] ?? 0, leftToday: leftToday, from: today, calendar: calendar))
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
    /// The place that puts `deck`, a deck at the top of the tree, at
    /// `position` in the queue among the other decks that have new ways, as
    /// of `now` (ADR 0034): a second before the first, a second after the
    /// last, or halfway between the two it goes between. With no other deck,
    /// it's `now`.
    public func place(putting deck: String, at position: QueuePosition, now: Date) -> Date {
        let withNewWays = Set(newWays.compactMap { topDecks[$0.cardID] })
        let others = queue.filter { $0.deck != deck && withNewWays.contains($0.deck) }.map(\.place)
        guard let first = others.first, let last = others.last else {
            return now
        }
        switch position {
        case .at(let index) where index > 0 && index < others.count:
            return others[index - 1] + others[index].timeIntervalSince(others[index - 1]) / 2
        case .first, .at(...0):
            return first - 1
        case .last, .at:
            return last + 1
        }
    }
}
