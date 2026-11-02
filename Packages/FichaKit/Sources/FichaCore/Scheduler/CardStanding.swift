import Foundation

/// Where a card stands: in Lucas's reviews, waiting in the inbox to be fixed,
/// buried, or set aside with its deck, or a deck its deck sits inside (ADR
/// 0024). Out of his reviews, each of its ways keeps its `WayStanding`, so it
/// comes back as it was when it's fixed, unburied, or its deck is no longer
/// set aside.
public enum CardStanding: Sendable, Equatable {
    /// In Lucas's reviews: new, or waiting its interval until it's due.
    case inReviews
    /// Waiting in the inbox to be fixed, as Lucas's flag says.
    case inInbox(Flag)
    /// Buried since `at`: out of Lucas's reviews for good, and out of the
    /// inbox. With the flag it had, if any, since unburying it brings it back
    /// to the inbox.
    case buried(at: Date, flag: Flag?)
    /// Set aside by these decks, the card's own or decks it sits inside, as
    /// the user set them aside, the outermost first: out of Lucas's reviews
    /// for now, while one of them is set aside (ADR 0011, ADR 0024).
    case setAside(by: [String])
}

extension CardStanding {
    /// Where a card with this flag, burial date and set-aside decks, as
    /// `setAsideDecks(of:among:)` picks them, stands, the first of these that
    /// holds: buried, waiting in the inbox, set aside, or in Lucas's reviews.
    /// A burial wins over a flag: a flagged card Lucas buries leaves the
    /// inbox. Both win over set aside, which never hides a card Lucas needs to
    /// fix or brings back one he buried.
    public init(flag: Flag?, buriedAt: Date?, setAsideBy setAsideDecks: [String]) {
        if let buriedAt {
            self = .buried(at: buriedAt, flag: flag)
        } else if let flag {
            self = .inInbox(flag)
        } else if !setAsideDecks.isEmpty {
            self = .setAside(by: setAsideDecks)
        } else {
            self = .inReviews
        }
    }

    /// Which of a card's `deck`, by its whole name, and the decks it sits
    /// inside, as `TagPath` reads a deck's levels, are set aside while the
    /// decks in `setAsideDecks` are, the outermost first, whether the card is
    /// buried, flagged or neither: when it's neither, they set it aside. A
    /// parent set aside is named as the user set it aside, Idiomas, not
    /// Idiomas::Inglés. A card's tags never set it aside.
    public static func setAsideDecks(of deck: String, among setAsideDecks: Set<String>) -> [String] {
        TagPath.lineage(of: deck).reversed().filter(setAsideDecks.contains)
    }
}

// What a way's standing means depends on where its card stands: out of
// Lucas's reviews, it keeps its progress, but it won't show up.
extension CardStanding {
    /// When the way is due, standing as `wayStanding` says: nil unless the
    /// card is in Lucas's reviews and the way started.
    public func due(given wayStanding: WayStanding) -> Date? {
        guard case .inReviews = self else {
            return nil
        }
        return wayStanding.due
    }

    /// Whether the way is due at `time`, standing as `wayStanding` says: the
    /// card in Lucas's reviews, and the way's interval over.
    public func isDue(at time: Date, given wayStanding: WayStanding) -> Bool {
        guard case .inReviews = self else {
            return false
        }
        return wayStanding.isDue(at: time)
    }

    /// Whether the way is new in Lucas's reviews, as `wayStanding` says.
    public func isNew(given wayStanding: WayStanding) -> Bool {
        guard case .inReviews = self else {
            return false
        }
        return wayStanding == .new
    }

    /// Whether the way is learned in Lucas's reviews, standing as
    /// `wayStanding` says: graduated with an interval of 21 days or more.
    public func isLearned(given wayStanding: WayStanding) -> Bool {
        guard case .inReviews = self else {
            return false
        }
        return wayStanding.isLearned
    }
}
