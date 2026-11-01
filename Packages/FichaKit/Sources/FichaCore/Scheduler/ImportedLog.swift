import Foundation

// The review log an import that brings a card's progress from another app,
// such as Anki, gives each of the card's ways (#409): the app's reviews of
// it, which the scheduler replays as it replays the user's own, and a
// placement where they leave the way elsewhere than the app had it, as after
// Anki's Set Due Date, which no review replays.

extension ImportedProgress {
    /// The entries an import that brings this progress gives the review log
    /// of `cardWay`, a way of a card that comes in new to Ficha at
    /// `importedAt`, in the order `scheduler`, the user's settings, replays
    /// them, each with its ID unique across devices: none for a new card.
    ///
    /// Each of its reviews comes in with its moment, its rating and its
    /// response time, with no trigger, answering the entry before it, so that
    /// only the first, when the app kept the card's first review, is a new
    /// way's first review. It keeps the interval it set there when the
    /// scheduler reads that interval as the app meant it: a graduated one, in
    /// whole days, and a step's wait, onto the step its rating moves the way
    /// to. Any other, an interval of zero, a step's wait of whole days, which
    /// the scheduler reads as graduated since Ficha's steps last less than a
    /// day, or a step's wait after a rating that takes the way out of its
    /// steps, keeps the interval `scheduler` works out for its rating. When
    /// the app kept none of the card's first reviews, they start from the
    /// placement of `start`, at the moment of the first it kept.
    ///
    /// A placement then holds the interval, due time and ease the card had
    /// there whenever the reviews leave the way elsewhere, or there are none:
    /// for a card in review, not graduated with its interval, or not due when
    /// it was due there; for a card on a learning or relearning step, not on
    /// a step, or not due then. A card on a step comes with the wait of the
    /// step its reviews leave it on, when it's less than a day, as Ficha's
    /// steps are, and with none otherwise: without reviews, it starts on the
    /// first learning step, and after reviews that graduated it, it goes onto
    /// the first relearning step. The placement comes at `importedAt`, or a
    /// millisecond after the last review, the finest Anki keeps, when the
    /// app's clock put that review later.
    ///
    /// Throws when fsrs-rs fails, or the scheduler can't follow the
    /// placement: a graduated one whose ease isn't above zero.
    public func log(of cardWay: CardWay, importedAt: Date, with scheduler: Scheduler) throws(SchedulingError)
        -> [ReviewLogEntry]
    {
        if case .new = stage {
            return []
        }
        var replay = try WayReplay(of: [], with: scheduler)
        var log: [ReviewLogEntry] = []
        if let start {
            let entry = ReviewLogEntry(
                placing: cardWay.cardID, way: cardWay.way, on: start.placement, at: start.answeredAt, uuid: UUID())
            try replay.replay(entry)
            log.append(entry)
        }
        for review in reviews {
            let answered = log.last?.uuid
            let kept = review.keptInterval(after: replay.stage)
            let entry = ReviewLogEntry(
                cardID: cardWay.cardID, way: cardWay.way, kind: .review(review.rating), answeredAt: review.answeredAt,
                responseTime: review.responseTime, trigger: nil, uuid: UUID(), answeredEntry: answered, interval: kept)
            try replay.replay(entry)
            log.append(kept == nil ? entry.answering(answered, keeping: replay.interval) : entry)
        }
        if let placement = placement(after: replay.standing) {
            let afterTheReviews = log.last.map { $0.answeredAt.addingTimeInterval(0.001) } ?? importedAt
            log.append(
                ReviewLogEntry(
                    placing: cardWay.cardID, way: cardWay.way, on: placement, at: max(importedAt, afterTheReviews),
                    uuid: UUID()))
        }
        return log
    }

    /// The placement that follows the card's reviews, which leave its way at
    /// `standing`, as `log(of:importedAt:with:)` says, or nil
    /// when they leave it where the card stood.
    private func placement(after standing: WayStanding) -> Placement? {
        let isOnAStep =
            switch standing.stage {
            case .learning?, .relearning?: true
            case .graduated?, nil: false
            }
        let isDueThen = { (due: ImportedDue) in standing.due.map(due.isMet(by:)) ?? false }
        switch stage {
        case .new:
            return nil
        case .learning(let due):
            guard !isOnAStep || !isDueThen(due) else {
                return nil
            }
            let wait = standing.interval.flatMap { isOnAStep && $0 < .days(1) ? $0 : nil }
            return Placement(interval: wait ?? .zero, due: due.time)
        case .review(let interval, let ease, let due):
            guard standing.stage != .graduated || standing.interval != interval || !isDueThen(due) else {
                return nil
            }
            return Placement(interval: interval, due: due.time, ease: ease)
        }
    }
}

extension ImportedReview {
    /// The interval this review keeps in Ficha's log after its way stood at
    /// `stage`, or was new, for nil: its own, when the scheduler reads it as
    /// the app meant it, a graduated interval in whole days, and a step's
    /// wait that isn't, onto the step its rating moves the way to; or nil for
    /// any other, which keeps the one the scheduler works out.
    fileprivate func keptInterval(after stage: WayStanding.Stage?) -> Duration? {
        guard interval > .zero else {
            return nil
        }
        if graduated {
            return interval.isWholeDays ? interval : nil
        }
        guard !interval.isWholeDays, case .onto = rating.move(from: stage) else {
            return nil
        }
        return interval
    }
}
