import Foundation

/// Where a card stands on the ladder: new until its first view, and on a step
/// from then on, as its review log says. A flagged, buried or set-aside card
/// keeps it, so it comes back on its step; `CardStanding` says whether the
/// card is in Lucas's reviews.
public enum LadderStanding: Sendable, Equatable {
    /// It hasn't had its first view yet.
    case new
    /// It's on this step of the ladder, counted from 0, the first step, and
    /// it's due once `due` comes.
    case onLadder(step: Int, due: Date)
}

extension LadderStanding {
    /// When the card is due, or nil while it's new.
    public var due: Date? {
        guard case .onLadder(_, let due) = self else {
            return nil
        }
        return due
    }

    /// Whether the card is due at `time`: on the ladder, with its wait over.
    public func isDue(at time: Date) -> Bool {
        guard let due else {
            return false
        }
        return due <= time
    }

    /// Checks that Lucas can answer the card with `kind` at `time`: a first
    /// view only while it's new, and a review only once it's due, or due
    /// within `lookAhead`, as when an appearance brings it along. That way a
    /// review ahead never counts as one on time (ADR 0002).
    public func check(_ kind: ReviewLogEntry.Kind, at time: Date, lookingAhead lookAhead: Duration)
        throws(RefusedAnswer)
    {
        switch (kind, self) {
        case (.firstView, .new):
            return
        case (.firstView, .onLadder):
            throw .notNew
        case (.review, .new):
            throw .stillNew
        case (.review, .onLadder):
            guard isDue(at: time.adding(lookAhead)) else {
                throw .notDue
            }
        }
    }
}

extension LadderStanding {
    /// Whether answering the card with `kind` at `time` is a review ahead: a
    /// review of a card on the ladder that isn't due yet, not even within
    /// `lookAhead`.
    public func isReviewAhead(_ kind: ReviewLogEntry.Kind, at time: Date, lookingAhead lookAhead: Duration) -> Bool {
        guard case .review = kind, case .onLadder = self else {
            return false
        }
        return !isDue(at: time.adding(lookAhead))
    }
}

/// Why an answer can't go into a card's review log.
public enum RefusedAnswer: Error, Equatable {
    /// A first view, for a card that already had one.
    case notNew
    /// A review, for a card that hasn't had its first view yet.
    case stillNew
    /// A review, for a card that isn't due yet.
    case notDue
}
