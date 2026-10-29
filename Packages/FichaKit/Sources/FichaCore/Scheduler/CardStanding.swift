import Foundation

/// Where a card stands: in Lucas's reviews, waiting in the inbox to be fixed,
/// buried, or set aside with one of its tags, or a tag one of them sits
/// inside (ADR 0021). Out of his reviews, it keeps its `LadderStanding`, so
/// it comes back on its step when it's fixed, unburied, or its tags are no
/// longer set aside.
public enum CardStanding: Sendable, Equatable {
    /// In Lucas's reviews: new, or on a ladder step until it's due.
    case inReviews
    /// Waiting in the inbox to be fixed, as Lucas's flag says.
    case inInbox(Flag)
    /// Buried since `at`: out of Lucas's reviews for good, and out of the
    /// inbox. With the flag it had, if any, since unburying it brings it back
    /// to the inbox.
    case buried(at: Date, flag: Flag?)
    /// Set aside by these tags, the card's or tags they sit inside, as the
    /// user set them aside, in alphabetical order: out of Lucas's reviews for
    /// now, while one of them is set aside (ADR 0011, ADR 0021).
    case setAside(by: [String])
}

extension CardStanding {
    /// Where a card with this flag, burial date and set-aside tags, as
    /// `setAsideTags(of:among:)` picks them, stands, the first of these that
    /// holds: buried, waiting in the inbox, set aside, or in Lucas's reviews.
    /// A burial wins over a flag: a flagged card Lucas buries leaves the
    /// inbox. Both win over set aside, which never hides a card Lucas needs to
    /// fix or brings back one he buried.
    public init(flag: Flag?, buriedAt: Date?, setAsideBy setAsideTags: [String]) {
        if let buriedAt {
            self = .buried(at: buriedAt, flag: flag)
        } else if let flag {
            self = .inInbox(flag)
        } else if !setAsideTags.isEmpty {
            self = .setAside(by: setAsideTags)
        } else {
            self = .inReviews
        }
    }

    /// Which of a card's `tags`, and of the tags they sit inside, are set
    /// aside while the tags in `setAsideTags` are, in alphabetical order as
    /// the Mac sorts text, whether the card is buried, flagged or neither:
    /// when it's neither, they set it aside. A parent set aside is named as
    /// the user set it aside, economía, not economía::Argentina.
    public static func setAsideTags(of tags: [String], among setAsideTags: Set<String>) -> [String] {
        TagPath.lineages(of: tags).filter(setAsideTags.contains).sortedAlphabetically()
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
