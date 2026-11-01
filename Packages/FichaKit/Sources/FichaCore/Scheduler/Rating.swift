/// How well Lucas says he knew a card in a review: Anki's four ratings, in
/// the order of Anki's buttons, again's first. Each raw value is how the
/// review log names it.
public enum Rating: String, Sendable, CaseIterable {
    /// He didn't know it: the ladder sends the card back to the first step,
    /// and the scheduler to the first learning or relearning step.
    case again
    /// He sort of knew it, with effort: the ladder keeps the card on its
    /// step, and the scheduler counts it as remembered.
    case hard
    /// He knew it: the ladder moves the card up one step, and the scheduler
    /// to its next step, or a longer interval.
    case good
    /// He knew it at once: the scheduler graduates the card from its steps,
    /// or gives it a longer interval than good. The ladder reads it as good.
    case easy
}

extension Rating {
    /// Where a review with this rating goes among reviews answered at the
    /// same moment, as both the ladder and the scheduler replay a way's log:
    /// easy first, then good, hard and again, so that again, answered on
    /// another device at the same moment, has the last word (ADR 0017).
    var orderAtTheSameMoment: Int {
        switch self {
        case .easy: 0
        case .good: 1
        case .hard: 2
        case .again: 3
        }
    }
}
