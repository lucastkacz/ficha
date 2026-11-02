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
    /// them, each with the ID unique across devices `newID` gives it next:
    /// none for a new card.
    ///
    /// Each of its reviews comes in with its moment, its rating and its
    /// response time, with no trigger, answering the entry before it, so that
    /// only the first, when the app kept the card's first review, is a new
    /// way's first review. It keeps the interval it set there when the
    /// scheduler reads that interval as the app meant it: a graduated one, in
    /// whole days, and a step's interval, onto the step its rating moves the
    /// way to. Any other, an interval of zero, a step's interval of whole
    /// days, which the scheduler reads as graduated since Ficha's steps last
    /// less than a day, or a step's interval after a rating that takes the
    /// way out of its steps, keeps the interval `scheduler` works out for its
    /// rating. When the app kept none of the card's first reviews, they start
    /// from the placement of `start`, at the moment of the first it kept.
    ///
    /// A placement then holds the interval, due time and ease the card had
    /// there whenever the reviews leave the way elsewhere, or there are none:
    /// for a card in review, not graduated with its interval, or not due when
    /// it was due there; for a card on a learning or relearning step, not on
    /// a step, or not due then. A card on a step goes on with Ficha's steps:
    /// without reviews, on the first learning step; on the step its reviews
    /// leave it on; and after reviews that graduated it, as when the app has
    /// more steps than Ficha, on the last learning step, or, once they
    /// lapsed it, the last relearning step, as a step that no longer exists
    /// counts as the last. It comes with that step's interval, or the one its
    /// reviews set there, when it's less than a day, as Ficha's steps are;
    /// when the settings have no such step, a card its reviews graduated
    /// stays graduated, with the interval they set. The placement comes at
    /// `importedAt`, or a millisecond after the last review, the finest Anki
    /// keeps, when the app's clock put that review later.
    ///
    /// Throws when fsrs-rs fails, or the scheduler can't follow an entry, as
    /// `SchedulingError.unexpectedReviewLog` says: reviews out of the order
    /// the scheduler replays them in, a placement with a negative interval,
    /// or a graduated one whose ease isn't above zero.
    public func log(of cardWay: CardWay, importedAt: Date, with scheduler: Scheduler, newID: () -> UUID)
        throws(SchedulingError) -> [ReviewLogEntry]
    {
        if case .new = stage {
            return []
        }
        var replay = try WayReplay(of: [], with: scheduler)
        var last: ReviewLogEntry?
        if let start {
            let entry = ReviewLogEntry(
                placing: cardWay.cardID, way: cardWay.way, on: start.placement, at: start.answeredAt, uuid: newID())
            try replay.replay(entry)
            last = entry
        }
        for review in reviews {
            let entry = ReviewLogEntry(
                cardID: cardWay.cardID, way: cardWay.way, kind: .review(review.rating), answeredAt: review.answeredAt,
                responseTime: review.responseTime, trigger: nil, uuid: newID(), answeredEntry: last?.uuid,
                interval: review.keptInterval(after: replay.stage))
            try replay.replay(entry)
            last = entry
        }
        // A review that kept no interval keeps the one the replay gave it.
        var log = replay.keepingIntervals
        if let placement = placement(after: replay, with: scheduler) {
            let afterTheReviews = last.map { $0.answeredAt.adding(.milliseconds(1)) } ?? importedAt
            log.append(
                ReviewLogEntry(
                    placing: cardWay.cardID, way: cardWay.way, on: placement, at: max(importedAt, afterTheReviews),
                    uuid: newID()))
        }
        return log
    }

    /// The placement that follows the card's reviews, `replay` with
    /// `scheduler`, as `log(of:importedAt:with:newID:)` says, or nil when
    /// they leave its way where the card stood.
    private func placement(after replay: WayReplay, with scheduler: Scheduler) -> Placement? {
        let standing = replay.standing
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
            return Placement(interval: intervalOnAStep(after: replay, with: scheduler), due: due.time)
        case .review(let interval, let ease, let due):
            guard standing.stage != .graduated || standing.interval != interval || !isDueThen(due) else {
                return nil
            }
            return Placement(interval: interval, due: due.time, ease: ease)
        }
    }

    /// The interval of a placement that keeps the way of a card the app had
    /// on a step in its steps, after the card's reviews, `replay` with
    /// `scheduler`: the interval they set, when they left the way on a step
    /// for less than a day, as Ficha's steps last; otherwise the interval of
    /// the step the placement puts it on, as `WayReplay.stepOfAPlacement`
    /// says. When the settings have no such step, a way the reviews
    /// graduated keeps the interval they set, of a day or more, which leaves
    /// it graduated, as the settings would, and any other gets none.
    private func intervalOnAStep(after replay: WayReplay, with scheduler: Scheduler) -> Duration {
        let set = replay.interval
        switch replay.stage {
        case .learning?, .relearning?:
            if set < .days(1) {
                return set
            }
        case .graduated?:
            return scheduler.interval(ofStep: replay.stepOfAPlacement) ?? set
        case nil:
            break
        }
        return scheduler.interval(ofStep: replay.stepOfAPlacement) ?? .zero
    }
}

extension ImportedReview {
    /// The interval this review keeps in Ficha's log after its way stood at
    /// `stage`, or was new, for nil: its own, when the scheduler reads it as
    /// the app meant it, a graduated interval in whole days, and a step's
    /// interval that isn't, onto the step its rating moves the way to; or nil
    /// for any other, which keeps the one the scheduler works out.
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
