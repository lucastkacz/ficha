internal import FichaFSRS
import Foundation

// Anki's rules around FSRS (#404, ADR 0026): how a rating moves a way through
// its learning and relearning steps, and the interval in whole days FSRS's
// gives a graduated one, within its bounds, a day apart, never shortened by
// the fuzz alone, and fuzzed. They follow Anki's
// `rslib/src/scheduler/states/` (learning.rs, relearning.rs, review.rs,
// steps.rs and fuzz.rs), without its options Ficha doesn't have: FSRS's
// short-term scheduling without steps, and the load balancer. Ficha's own:
// hard on a single step waits 1.5 times the step even past a day, where Anki
// rounds such a wait to whole days, since Anki's cards fall due by the day and
// Ficha's at a time of day.

/// Where a rating moves a way, and the interval it waits from then.
struct Outcome: Equatable {
    let stage: WayStanding.Stage
    let interval: Duration
}

extension Scheduler {
    /// Where `rating` moves a way at `stage`, or a new way when it's nil,
    /// whose last entry set `interval`, given the memory and interval fsrs-rs
    /// works out for each rating, with `fuzzFactor`, from 0 up to 1, picking
    /// where in Anki's range around it a graduated interval falls.
    ///
    /// A new way goes as one on the first learning step. In a learning or
    /// relearning step, again goes back to the first step, hard repeats the
    /// step, or, on the first, waits halfway to the second, or 1.5 times the
    /// step when there's only one, good moves to the next step, or graduates
    /// after the last, and easy graduates. A step these settings no longer
    /// have counts as the last, and with no steps at all any rating
    /// graduates. A graduated way's again is a lapse, to the first
    /// relearning step, or to FSRS's interval after it when there are none;
    /// hard, good and easy get FSRS's interval for them.
    func outcome(
        of rating: Rating, at stage: WayStanding.Stage?, after interval: Duration, given next: NextStates,
        fuzzFactor: Double
    ) -> Outcome {
        switch stage {
        case nil:
            outcome(of: rating, onStep: 0, of: learningSteps, given: next, fuzzFactor: fuzzFactor) {
                .learning(step: $0)
            }
        case .learning(let step):
            outcome(of: rating, onStep: step, of: learningSteps, given: next, fuzzFactor: fuzzFactor) {
                .learning(step: $0)
            }
        case .relearning(let step):
            outcome(of: rating, onStep: step, of: relearningSteps, given: next, fuzzFactor: fuzzFactor) {
                .relearning(step: $0)
            }
        case .graduated:
            graduatedOutcome(
                of: rating, after: Int((interval.timeInterval / oneDay.timeInterval).rounded()), given: next,
                fuzzFactor: fuzzFactor)
        }
    }

    /// Where `rating` moves a way on `step` of `steps`, its learning or
    /// relearning steps, which `stage` names its stage on.
    private func outcome(
        of rating: Rating, onStep step: Int, of steps: [Duration], given next: NextStates, fuzzFactor: Double,
        stagedAs stage: (Int) -> WayStanding.Stage
    ) -> Outcome {
        guard !steps.isEmpty else {
            return graduation(with: rating, given: next, fuzzFactor: fuzzFactor)
        }
        let current = min(step, steps.count - 1)
        switch rating {
        case .again:
            return Outcome(stage: stage(0), interval: steps[0])
        case .hard:
            return Outcome(stage: stage(current), interval: current == 0 ? hardOnFirstStep(of: steps) : steps[current])
        case .good where current + 1 < steps.count:
            return Outcome(stage: stage(current + 1), interval: steps[current + 1])
        case .good, .easy:
            return graduation(with: rating, given: next, fuzzFactor: fuzzFactor)
        }
    }

    /// How long hard on the first of `steps` waits, as Anki keeps it apart
    /// from again: halfway to the second step, or 1.5 times the step when
    /// there's only one.
    private func hardOnFirstStep(of steps: [Duration]) -> Duration {
        steps.count > 1 ? (steps[0] + steps[1]) / 2 : steps[0] * 3 / 2
    }

    /// A way leaving its steps with `rating`: FSRS's interval for it, rounded
    /// to whole days, at least one, and fuzzed; for easy, at least a day
    /// longer than good would have been.
    private func graduation(with rating: Rating, given next: NextStates, fuzzFactor: Double) -> Outcome {
        let days =
            switch rating {
            case .again, .hard, .good:
                fuzzed(wholeDays(of: next[rating].interval), atLeast: 1, by: fuzzFactor)
            case .easy:
                fuzzed(
                    wholeDays(of: next.easy.interval),
                    atLeast: fuzzed(Double(next.good.interval), atLeast: 1, by: fuzzFactor) + 1, by: fuzzFactor)
            }
        return Outcome(stage: .graduated, interval: oneDay * days)
    }

    /// Where `rating` moves a graduated way whose last interval was
    /// `previous` days: hard, good and easy each get FSRS's interval in whole
    /// days, fuzzed, good at least a day longer than hard and easy at least
    /// a day longer than good, and none shorter than Anki's least for it.
    private func graduatedOutcome(of rating: Rating, after previous: Int, given next: NextStates, fuzzFactor: Double)
        -> Outcome
    {
        if rating == .again, let firstStep = relearningSteps.first {
            return Outcome(stage: .relearning(step: 0), interval: firstStep)
        }
        let (hardDays, goodDays, easyDays) = (
            Double(next.hard.interval), Double(next.good.interval), Double(next.easy.interval)
        )
        let hard = fuzzed(hardDays, atLeast: max(1, leastInterval(for: hardDays, after: previous)), by: fuzzFactor)
        let good = fuzzed(
            goodDays, atLeast: max(hard + 1, leastInterval(for: goodDays, after: previous)), by: fuzzFactor)
        let days =
            switch rating {
            case .again: fuzzed(wholeDays(of: next.again.interval), atLeast: 1, by: fuzzFactor)
            case .hard: hard
            case .good: good
            case .easy:
                fuzzed(easyDays, atLeast: max(good + 1, leastInterval(for: easyDays, after: previous)), by: fuzzFactor)
            }
        return Outcome(stage: .graduated, interval: oneDay * days)
    }

    /// Anki's least interval, in days, for a graduated way's hard, good or
    /// easy whose interval from FSRS is `days`, after a last interval of
    /// `previous` days: a day longer than that when FSRS's has grown past
    /// it, and as long when the fuzz could reach it, so the fuzz never
    /// shortens an interval FSRS didn't, as for a second review the same
    /// day; and none when FSRS's has shrunk, as after the settings changed.
    private func leastInterval(for days: Double, after previous: Int) -> Int {
        if Int(days.rounded()) > previous {
            return previous + 1
        }
        return previous <= fuzzRange(of: days, atLeast: 1).upperBound ? previous : 0
    }

    /// FSRS's interval of `days` rounded to whole days, one at least.
    private func wholeDays(of days: Float) -> Double {
        max(1, Double(days).rounded())
    }

    /// An interval of `days` in whole days, at least `minimum` and at most
    /// the longest interval, fuzzed as Anki fuzzes it: picked by
    /// `fuzzFactor`, from 0 up to 1, from `fuzzRange(of:atLeast:)`.
    private func fuzzed(_ days: Double, atLeast minimum: Int, by fuzzFactor: Double) -> Int {
        let range = fuzzRange(of: days, atLeast: minimum)
        return range.lowerBound + Int((fuzzFactor * Double(range.count)).rounded(.down))
    }

    /// The whole days Anki's fuzz picks an interval of `days` from, which
    /// grows with it: none under 2.5 days, and then a day plus 15% of its
    /// days from 2.5 to 7, 10% of those from 7 to 20 and 5% of those past
    /// 20, each way. It keeps from `minimum` to the longest interval, and
    /// spans two days at least once it's past 2 days and under the longest
    /// interval.
    private func fuzzRange(of days: Double, atLeast minimum: Int) -> ClosedRange<Int> {
        let maximum = longestIntervalInDays
        let minimum = min(minimum, maximum)
        let interval = min(max(days, Double(minimum)), Double(maximum))
        let delta = fuzzDelta(of: interval)
        let lower = min(max(Int((interval - delta).rounded()), minimum), maximum)
        let upper = min(max(Int((interval + delta).rounded()), minimum), maximum)
        return lower...(upper == lower && upper > 2 && upper < maximum ? lower + 1 : upper)
    }

    /// How far, in days, Anki's fuzz reaches each way from an interval of
    /// `days`.
    private func fuzzDelta(of days: Double) -> Double {
        guard days >= 2.5 else {
            return 0
        }
        let ranges: [(start: Double, end: Double, factor: Double)] = [
            (2.5, 7, 0.15), (7, 20, 0.1), (20, .greatestFiniteMagnitude, 0.05),
        ]
        return ranges.reduce(1) { delta, range in delta + range.factor * max(0, min(days, range.end) - range.start) }
    }
}

extension NextStates {
    /// What fsrs-rs works out for `rating`.
    subscript(rating: Rating) -> NextState {
        switch rating {
        case .again: again
        case .hard: hard
        case .good: good
        case .easy: easy
        }
    }
}

/// The fuzz factor of a way's review, from 0 up to 1, which picks where in
/// Anki's range around FSRS's interval a graduated interval falls: seeded by
/// the card, its way and how many reviews that way had before, as Anki seeds
/// it by card and repetitions, so that each review's preview gives the
/// interval it keeps, and every device works out the same one when it works
/// it out again. The card is named by its way's first entry's ID unique
/// across devices, since its id differs on each, or, for a way's first
/// review, which has no entry before it, by its id on the device that
/// recorded it, which keeps its interval.
///
/// The seed's numbers go through SplitMix64's mixing function (Steele, Lea
/// and Flood, 2014), integer arithmetic alone, so every device, run and
/// version of Swift gives the same factor: Swift's `Hasher` is seeded anew
/// in each run, and Foundation has no seeded generator.
func fuzzFactor(of card: FuzzCard, way: Way, reviewsBefore reviews: Int) -> Double {
    let wayNumber: UInt64 =
        switch way {
        case .frontFirst: 0
        case .backFirst: 1
        }
    let words = card.words + [wayNumber, UInt64(clamping: reviews)]
    let mixed = words.reduce(0) { state, word in splitMix64(state ^ word) }
    // The top 53 bits, as a Double holds them exactly, from 0 up to 1.
    return Double(mixed >> 11) * 0x1p-53
}

/// What names a card in the fuzz's seed.
enum FuzzCard {
    /// Its way's first entry, by its ID unique across devices.
    case firstEntry(UUID)
    /// The card, by its id on this device.
    case cardID(Int64)

    /// The numbers it adds to the seed, each kind with its own first, so
    /// that an id never seeds as an entry's ID does.
    fileprivate var words: [UInt64] {
        switch self {
        case .firstEntry(let uuid):
            let bytes = withUnsafeBytes(of: uuid.uuid) { Array($0) }
            let high = bytes[0..<8].reduce(0) { $0 << 8 | UInt64($1) }
            let low = bytes[8..<16].reduce(0) { $0 << 8 | UInt64($1) }
            return [1, high, low]
        case .cardID(let id):
            return [0, UInt64(bitPattern: id)]
        }
    }
}

/// SplitMix64's step: the state advanced by its golden-ratio increment, then
/// mixed so that every bit of it moves every bit of the result.
private func splitMix64(_ state: UInt64) -> UInt64 {
    var mixed = state &+ 0x9E37_79B9_7F4A_7C15
    mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
    mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
    return mixed ^ (mixed >> 31)
}
