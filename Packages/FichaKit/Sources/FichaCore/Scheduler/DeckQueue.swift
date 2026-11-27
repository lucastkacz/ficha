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
    /// Ahead of every other deck, but one listed first for its priority
    /// cards alone.
    case first
    /// After every other deck.
    case last
    /// At this index among the other decks of the queue, as
    /// `ReviewSettings.queue(of:now:calendar:)` lists them, from 0, the
    /// first, but after one listed first for its priority cards alone.
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
        let leftToday = newCardsLeftToday(in: cards, now: now, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        return cards.decksWithNewWays().map { deck in
            QueuedDeck(
                deck: deck.deck, newCards: deck.newWays,
                finish: finishDate(after: deck.through, leftToday: leftToday, from: today, calendar: calendar))
        }
    }

    /// When the user will have met every new card of `deck`, a deck at the
    /// top of the tree, out of `cards`, at `now`, by `calendar`, as
    /// `queue(of:now:calendar:)` says it (ADR 0034): where the deck is in the
    /// queue, or, when `first`, once it's first, at the places
    /// `CardsInReviews.places(putting:at:now:)` gives it and the decks it
    /// passes, as `Engine.moveInQueue(deck:to:)` saves them, with the decks
    /// the move doesn't count where they were. Nil when the deck has no new
    /// card, or with no new cards a day. How fast? reads it at each pace, for
    /// a deck as it comes in, and for one of Ficha's decks before it comes
    /// in, with `cards` holding its cards as they'd come in (#458).
    public func finishDate(
        of deck: String, first: Bool, in cards: CardsInReviews, now: Date, calendar: Calendar
    ) -> FinishDate? {
        let decks = first ? cards.decksWithNewWays(putting: deck, at: .first, now: now) : cards.decksWithNewWays()
        guard let through = decks.first(where: { $0.deck == deck })?.through else {
            return nil
        }
        return finishDate(after: through, in: cards, now: now, calendar: calendar)
    }

    /// How many new ways today may still bring at `now`, by `calendar`, out
    /// of `cards`: none once `activeHours` are over, and none past the day's
    /// limit, which the first reviews of new ways on `now`'s day count
    /// against.
    private func newCardsLeftToday(in cards: CardsInReviews, now: Date, calendar: Calendar) -> Int {
        let metToday = cards.firstReviews(onTheDayOf: now, calendar: calendar).count
        return calendar.component(.hour, from: now) < activeHours.upperBound ? max(0, newCardsPerDay - metToday) : 0
    }

    /// When the new way at `slot`, counting from 1, the first to come, has
    /// come, out of `cards`, at `now`, by `calendar`, as
    /// `queue(of:now:calendar:)` counts it.
    private func finishDate(after slot: Int, in cards: CardsInReviews, now: Date, calendar: Calendar) -> FinishDate? {
        finishDate(
            after: slot, leftToday: newCardsLeftToday(in: cards, now: now, calendar: calendar),
            from: calendar.startOfDay(for: now), calendar: calendar)
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
        decksWithNewWays(queuedAs: queue)
    }

    /// The decks at the top of the tree that have new ways, as
    /// `decksWithNewWays()` lists them, once `deck`, a deck at the top of the
    /// tree, is at `position` in the queue, at the places
    /// `places(putting:at:now:)` gives it and the decks it passes or parts, as
    /// `Engine.moveInQueue(deck:to:)` saves them, and the other decks at
    /// theirs.
    func decksWithNewWays(
        putting deck: String, at position: QueuePosition, now: Date
    ) -> [(deck: String, newWays: Int, through: Int)] {
        let moved = places(putting: deck, at: position, now: now)
        return decksWithNewWays(
            queuedAs: queue.map { PlacedDeck(deck: $0.deck, place: moved[$0.deck] ?? $0.place) }.sorted())
    }

    /// The decks at the top of the tree met in full: those that hold cards in
    /// Lucas's reviews but no new way, as he met every new way they had
    /// there, so the queue new cards come from no longer lists them
    /// (ADR 0034). A card buried, flagged or set aside with a deck inside
    /// one leaves its ways out, and a card that goes both ways brings its
    /// back-first way once it's met. The review panel says "You've met them
    /// all" for a deck an answer puts here, and the Cards window's row of a
    /// deck here says "Met them all".
    public var decksMetInFull: Set<String> {
        Set(queue.map(\.deck)).subtracting(newWays.compactMap { topDecks[$0.cardID] })
    }

    /// The decks at the top of the tree that have new ways, as
    /// `decksWithNewWays()` lists them, with the decks in `queue`'s order,
    /// the queue's places.
    private func decksWithNewWays(queuedAs queue: [PlacedDeck]) -> [(deck: String, newWays: Int, through: Int)] {
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
            let count = countedAsNewCards(way)
            total += count
            counts[deck, default: 0] += count
            through[deck] = total
        }
        return through.sorted { $0.value < $1.value }
            .map { (deck: $0.key, newWays: counts[$0.key] ?? 0, through: $0.value) }
    }

    /// How many new cards `way`, a new way, counts as, as the new cards a day
    /// count them: a card's front-first way two, with its back-first way
    /// still to come, and any other way one.
    private func countedAsNewCards(_ way: CardWay) -> Int {
        way.way == .frontFirst && backFirstWaysToCome.contains(way.cardID) ? 2 : 1
    }

    /// The places that put `deck`, a deck at the top of the tree, at
    /// `position` among the other decks that have new ways, as
    /// `ReviewSettings.queue(of:now:calendar:)` lists them, as of `now`
    /// (ADR 0034): `deck` and the decks it passes take each other's places,
    /// the earliest for the first, `deck`'s being `now` when it has no card
    /// in Lucas's reviews. Those that would then go out of order, at one
    /// place, by name, go a second apart, so that decks that came in at once
    /// part: later, and earlier where the deck after them leaves no room,
    /// unless the deck before them leaves none either: then later, with the
    /// decks after them too, as far as such ties reach. The other decks keep
    /// their places, and so does a deck the move doesn't count: one with no
    /// new card in Lucas's reviews, such as one set aside or whose new cards
    /// are buried or flagged, or one listed first for its priority cards
    /// alone, whose new cards still come first, as do those of a priority
    /// deck `deck` holds. So a deck the move passes or parts can land on the
    /// other side of one it doesn't count. Only the places that change, by
    /// deck, `deck`'s too when it had none.
    public func places(putting deck: String, at position: QueuePosition, now: Date) -> [String: Date] {
        let held = Dictionary(uniqueKeysWithValues: queue.map { ($0.deck, $0.place) })
        let placeOf = { (name: String) in held[name] ?? now }
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
        // The same decks in the order their places put them now; the move
        // passes those between the first and the last that it changes.
        let before = order.sorted { (placeOf($0), $0) < (placeOf($1), $1) }
        guard let first = order.indices.first(where: { order[$0] != before[$0] }),
            let last = order.indices.last(where: { order[$0] != before[$0] })
        else {
            return held[deck] == nil ? [deck: now] : [:]
        }
        var swapped = order.map(placeOf)
        for index in first...last {
            swapped[index] = placeOf(before[index])
        }
        var parted = swapped
        func goesAfterTheOneBefore(_ index: Int) -> Bool {
            (parted[index - 1], order[index - 1]) < (parted[index], order[index])
        }
        // Ties among the decks the move passes, and with the deck before
        // them, go a second apart, later,
        for index in max(first, 1)...last where !goesAfterTheOneBefore(index) {
            parted[index] = parted[index - 1] + 1
        }
        if last + 1 < order.count, !goesAfterTheOneBefore(last + 1) {
            // or, when that runs into the deck after them, earlier,
            for index in stride(from: last, through: first, by: -1) where !goesAfterTheOneBefore(index + 1) {
                parted[index] = order[index] < order[index + 1] ? parted[index + 1] : parted[index + 1] - 1
            }
            // or, when that runs into the deck before them too, later, with
            // the decks after them, as far as such ties reach.
            if first > 0, !goesAfterTheOneBefore(first) {
                parted = swapped
                var index = max(first, 1)
                while index < order.count {
                    if !goesAfterTheOneBefore(index) {
                        parted[index] = parted[index - 1] + 1
                    } else if index > last {
                        break
                    }
                    index += 1
                }
            }
        }
        var places: [String: Date] = [:]
        for (name, place) in zip(order, parted) where place != held[name] {
            places[name] = place
        }
        return places
    }
}
