import Foundation

/// Where a card stands: in Lucas's reviews, waiting in the inbox to be fixed,
/// or buried. Out of his reviews, it keeps its `LadderStanding`, so it comes
/// back on its step when it's fixed or unburied.
public enum CardStanding: Sendable, Equatable {
    /// In Lucas's reviews: new, or on a ladder step until it's due.
    case inReviews
    /// Waiting in the inbox to be fixed, as Lucas's flag says.
    case inInbox(Flag)
    /// Buried since `at`: out of Lucas's reviews for good, and out of the
    /// inbox. With the flag it had, if any, since unburying it brings it back
    /// to the inbox.
    case buried(at: Date, flag: Flag?)
}

extension CardStanding {
    /// Where a card with this flag and burial date stands. A burial wins over
    /// a flag: a flagged card Lucas buries leaves the inbox.
    public init(flag: Flag?, buriedAt: Date?) {
        if let buriedAt {
            self = .buried(at: buriedAt, flag: flag)
        } else if let flag {
            self = .inInbox(flag)
        } else {
            self = .inReviews
        }
    }
}

// What a card's place on the ladder means depends on where it stands: out of
// Lucas's reviews, it keeps its step, but it won't show up.
extension CardStanding {
    /// When the card is due, standing on the ladder as `ladderStanding` says:
    /// nil unless it's in Lucas's reviews and on the ladder.
    public func due(given ladderStanding: LadderStanding) -> Date? {
        guard case .inReviews = self else {
            return nil
        }
        return ladderStanding.due
    }

    /// Whether the card is due at `time`, standing on the ladder as
    /// `ladderStanding` says: in Lucas's reviews, with its wait over.
    public func isDue(at time: Date, given ladderStanding: LadderStanding) -> Bool {
        guard case .inReviews = self else {
            return false
        }
        return ladderStanding.isDue(at: time)
    }

    /// Whether the card is new in Lucas's reviews, as `ladderStanding` says.
    public func isNew(given ladderStanding: LadderStanding) -> Bool {
        guard case .inReviews = self else {
            return false
        }
        return ladderStanding == .new
    }

    /// Whether the card is learned in Lucas's reviews, standing on `ladder` as
    /// `ladderStanding` says: on a step that waits 30 days or more.
    public func isLearned(given ladderStanding: LadderStanding, on ladder: Ladder) -> Bool {
        guard case .inReviews = self else {
            return false
        }
        return ladder.isLearned(ladderStanding)
    }
}
