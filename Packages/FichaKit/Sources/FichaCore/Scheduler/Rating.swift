/// How well Lucas says he knew a card in a review: Anki's four ratings, in
/// the order of Anki's buttons, again's first. Each raw value is how the
/// review log names it.
public enum Rating: String, Sendable, CaseIterable {
    /// He didn't know it: the scheduler sends the card to the first learning
    /// or relearning step.
    case again
    /// He sort of knew it, with effort: the scheduler counts it as
    /// remembered.
    case hard
    /// He knew it: the scheduler moves the card to its next step, or gives it
    /// a longer interval.
    case good
    /// He knew it at once: the scheduler graduates the card from its steps,
    /// or gives it a longer interval than good.
    case easy
}

extension Rating {
    /// Where a review with this rating goes among reviews answered at the
    /// same moment, as the scheduler replays a way's log: easy first, then
    /// good, hard and again, so that again, answered on another device at the
    /// same moment, has the last word (ADR 0017).
    var orderAtTheSameMoment: Int {
        switch self {
        case .easy: 0
        case .good: 1
        case .hard: 2
        case .again: 3
        }
    }
}
