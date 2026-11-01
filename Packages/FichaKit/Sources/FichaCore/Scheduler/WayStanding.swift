import Foundation

/// Where a card's way stands in Lucas's reviews, as the scheduler works it
/// out from that way's entries in the review log (#404): new until its first
/// review, or until an import places it, and then in a learning step,
/// graduated or in a relearning step, waiting its interval from its last
/// entry until it's due. A flagged, buried or set-aside card keeps it, so it
/// comes back as it was; `CardStanding` says whether the card is in Lucas's
/// reviews.
public enum WayStanding: Sendable, Equatable {
    /// It has no entries: it hasn't had its first review, nor been placed by
    /// an import.
    case new
    /// It's at `stage`, and due at `due`, `interval` after its last entry,
    /// with `memory` once FSRS has one for it.
    case started(Stage, interval: Duration, due: Date, memory: Memory?)

    /// Where a way that isn't new is.
    public enum Stage: Sendable, Equatable {
        /// On this learning step, counted from 0, the first: a step the
        /// learning steps may no longer have, after they changed, which its
        /// next review counts as the last.
        case learning(step: Int)
        /// Out of its steps, its interval FSRS's, in whole days.
        case graduated
        /// On this relearning step, after a lapse, counted from 0, the first,
        /// and maybe no longer there, as a learning step.
        case relearning(step: Int)
    }

    /// The way's memory, as FSRS estimates it from its reviews, or from the
    /// interval and ease an import brought for it.
    public struct Memory: Sendable, Equatable {
        /// How long the memory lasts: the days it takes the chance of
        /// remembering the way to fall to 90%.
        public let stability: Float
        /// How hard the way is, from 1 to 10.
        public let difficulty: Float
        /// When the way was last reviewed, from which its retrievability
        /// falls: for a way an import brought without reviews, its due time
        /// less its interval, as Anki reckons it.
        public let lastReview: Date

        public init(stability: Float, difficulty: Float, lastReview: Date) {
            self.stability = stability
            self.difficulty = difficulty
            self.lastReview = lastReview
        }

        /// How hard the way is, from 0 to 1, as Anki's Card Info shows the
        /// difficulty, as a percentage: FSRS's 1 to 10 shifted to start at
        /// 0, (difficulty − 1) / 9.
        public var difficultyAsAnkiShowsIt: Float {
            (difficulty - 1) / 9
        }
    }
}

extension WayStanding {
    /// Where the way is, or nil while it's new.
    public var stage: Stage? {
        guard case .started(let stage, _, _, _) = self else {
            return nil
        }
        return stage
    }

    /// How long the way waits after its last entry, or nil while it's new.
    public var interval: Duration? {
        guard case .started(_, let interval, _, _) = self else {
            return nil
        }
        return interval
    }

    /// When the way is due, or nil while it's new.
    public var due: Date? {
        guard case .started(_, _, let due, _) = self else {
            return nil
        }
        return due
    }

    /// The way's memory, or nil until FSRS has one for it.
    public var memory: Memory? {
        guard case .started(_, _, _, let memory) = self else {
            return nil
        }
        return memory
    }

    /// Whether the way is due at `time`: started, with its interval over.
    public func isDue(at time: Date) -> Bool {
        guard let due else {
            return false
        }
        return due <= time
    }

    /// Whether the way is learned: graduated with an interval of 21 days or
    /// more, as Anki counts a card mature. The menu counts these cards, by
    /// their front-first way, and the Cards window lists them.
    public var isLearned: Bool {
        guard stage == .graduated, let interval else {
            return false
        }
        return interval >= .days(21)
    }

    /// Checks that Lucas can answer the way with `kind` at `time`: a review
    /// of a new way, whatever its rating, or of one that's due, or due within
    /// `lookAhead`, as when an appearance brings it along. A placement is
    /// never an answer: only an import places a card.
    public func check(_ kind: ReviewLogEntry.Kind, at time: Date, lookingAhead lookAhead: Duration)
        throws(RefusedAnswer)
    {
        switch (kind, self) {
        case (.review, .new):
            return
        case (.review, .started):
            guard isDue(at: time.adding(lookAhead)) else {
                throw .notDue
            }
        case (.placement, _):
            throw .notAnAnswer
        }
    }

    /// Whether answering the way with `kind` at `time` is a review ahead: a
    /// review of a started way that isn't due yet, not even within
    /// `lookAhead`.
    public func isReviewAhead(_ kind: ReviewLogEntry.Kind, at time: Date, lookingAhead lookAhead: Duration) -> Bool {
        guard case .review = kind, case .started = self else {
            return false
        }
        return !isDue(at: time.adding(lookAhead))
    }
}

/// Why an answer can't go into a card's review log.
public enum RefusedAnswer: Error, Equatable {
    /// A review, for a way that isn't due yet.
    case notDue
    /// A placement, which only an import gives a card, as it comes in.
    case notAnAnswer
}
