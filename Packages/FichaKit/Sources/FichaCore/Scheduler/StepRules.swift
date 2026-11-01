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

/// Where a review leaves a way, and the interval it waits from then.
struct StageAndInterval: Equatable {
    let stage: WayStanding.Stage
    let interval: Duration
}

/// Where a rating moves a way among its learning or relearning steps, by
/// their indices alone, whatever steps the settings have.
enum StepMove: Equatable {
    /// Onto this learning or relearning step, which the settings may not
    /// have: past their last one, or with none, the way leaves its steps.
    case onto(WayStanding.Stage)
    /// Out of its steps, or, for a graduated way, still out of them.
    case outOfTheSteps
}

extension Rating {
    /// Where this rating moves a way at `stage`, or a new way, which counts
    /// as one on the first learning step, when it's nil: again back to the
    /// first step, or, for a graduated way, a lapse, to the first relearning
    /// step; hard onto the step it's on; good onto the next; and easy out of
    /// the steps, as a graduated way's hard and good keep it out of them. The
    /// steps the settings have decide the rest: how long each step waits,
    /// and that one past their last takes the way out of them.
    func move(from stage: WayStanding.Stage?) -> StepMove {
        switch (stage ?? .learning(step: 0), self) {
        case (.learning, .again): .onto(.learning(step: 0))
        case (.relearning, .again), (.graduated, .again): .onto(.relearning(step: 0))
        case (.learning(let step), .hard): .onto(.learning(step: step))
        case (.relearning(let step), .hard): .onto(.relearning(step: step))
        case (.learning(let step), .good): .onto(.learning(step: step + 1))
        case (.relearning(let step), .good): .onto(.relearning(step: step + 1))
        case (_, .easy), (.graduated, .hard), (.graduated, .good): .outOfTheSteps
        }
    }
}

extension Scheduler {
    /// Where `rating` moves a way at `stage`, or a new way when it's nil,
    /// whose last entry set `lastInterval`, and the interval it waits from
    /// then: onto a step, as `Rating.move(from:)` says, when these settings
    /// have it, counting one they no longer have as their last, and
    /// otherwise graduated, with the interval `intervals` gives it.
    ///
    /// A step waits its own interval, but for hard on the first, which waits
    /// halfway to the second, or 1.5 times the step when there's only one.
    /// So with no steps at all, any rating graduates a new way.
    func stageAndInterval(
        rating: Rating, from stage: WayStanding.Stage?, lastInterval: Duration, intervals: GraduatedIntervals
    ) -> StageAndInterval {
        let stage = stage.map(onAStepTheseSettingsHave)
        if case .onto(let step) = rating.move(from: stage), let wait = wait(of: rating, on: step) {
            return StageAndInterval(stage: step, interval: wait)
        }
        let days =
            stage == .graduated
            ? intervals.ofGraduatedWay(rating, after: Int(lastInterval.inDays.rounded()))
            : intervals.leavingTheSteps(rating)
        return StageAndInterval(stage: .graduated, interval: .days(Int64(days)))
    }

    /// The interval of the learning or relearning step `stage` is on,
    /// counting one these settings no longer have as their last, or nil when
    /// they have no such steps, or `stage` is graduated.
    func interval(ofStep stage: WayStanding.Stage) -> Duration? {
        switch onAStepTheseSettingsHave(stage) {
        case .learning(let step): learningSteps.indices.contains(step) ? learningSteps[step] : nil
        case .relearning(let step): relearningSteps.indices.contains(step) ? relearningSteps[step] : nil
        case .graduated: nil
        }
    }

    /// `stage`, or the last of these settings' steps when it's on a step they
    /// no longer have, as after they changed.
    private func onAStepTheseSettingsHave(_ stage: WayStanding.Stage) -> WayStanding.Stage {
        switch stage {
        case .learning(let step) where step >= learningSteps.count && !learningSteps.isEmpty:
            .learning(step: learningSteps.count - 1)
        case .relearning(let step) where step >= relearningSteps.count && !relearningSteps.isEmpty:
            .relearning(step: relearningSteps.count - 1)
        case .learning, .relearning, .graduated:
            stage
        }
    }

    /// How long a way that `rating` moved onto `stage`'s step waits there, or
    /// nil when these settings don't have that step: the step's interval, or,
    /// for hard on the first, which Anki keeps apart from again, halfway to
    /// the second step, or 1.5 times the step when there's only one.
    private func wait(of rating: Rating, on stage: WayStanding.Stage) -> Duration? {
        let steps: [Duration]
        let step: Int
        switch stage {
        case .learning(let index): (steps, step) = (learningSteps, index)
        case .relearning(let index): (steps, step) = (relearningSteps, index)
        case .graduated: return nil
        }
        guard steps.indices.contains(step) else {
            return nil
        }
        guard rating == .hard, step == 0 else {
            return steps[step]
        }
        return steps.count > 1 ? (steps[0] + steps[1]) / 2 : steps[0] * 3 / 2
    }
}

/// What a review's graduated intervals come from, and how Anki works them out
/// in whole days: `next`, what fsrs-rs works out for each rating, the memory
/// it leaves and its interval; rounded, from a day to the longest interval,
/// `longestIntervalInDays`; and fuzzed by `fuzzFactor`, from 0 up to 1, which
/// picks where in Anki's range around each interval it falls.
struct GraduatedIntervals {
    let next: NextStates
    let fuzzFactor: Double
    let longestIntervalInDays: Int

    /// The days a way leaving its learning or relearning steps with `rating`
    /// waits: FSRS's interval for it, rounded, a day at least, and fuzzed;
    /// for easy, at least a day longer than good would have been.
    func leavingTheSteps(_ rating: Rating) -> Int {
        switch rating {
        case .again, .hard, .good:
            fuzzed(wholeDays(of: next[rating].interval), atLeast: 1)
        case .easy:
            fuzzed(wholeDays(of: next.easy.interval), atLeast: fuzzed(Double(next.good.interval), atLeast: 1) + 1)
        }
    }

    /// The days a graduated way whose last interval was `previous` days waits
    /// after `rating`. Again, a lapse when there are no relearning steps,
    /// gets FSRS's interval rounded, a day at least, and up to the longest
    /// interval, without the fuzz, as Anki's `answer_again` in `review.rs`
    /// gives it: Anki fuzzes such an interval only when a card leaves its
    /// relearning steps (`failing_review_interval`). Hard, good and easy each
    /// get FSRS's interval in whole days, fuzzed, good at least a day longer
    /// than hard and easy at least a day longer than good, and none shorter
    /// than Anki's least for it.
    func ofGraduatedWay(_ rating: Rating, after previous: Int) -> Int {
        let (hardDays, goodDays, easyDays) = (
            Double(next.hard.interval), Double(next.good.interval), Double(next.easy.interval)
        )
        let hard = fuzzed(hardDays, atLeast: max(1, leastInterval(for: hardDays, after: previous)))
        let good = fuzzed(goodDays, atLeast: max(hard + 1, leastInterval(for: goodDays, after: previous)))
        return switch rating {
        case .again: min(Int(wholeDays(of: next.again.interval)), longestIntervalInDays)
        case .hard: hard
        case .good: good
        case .easy: fuzzed(easyDays, atLeast: max(good + 1, leastInterval(for: easyDays, after: previous)))
        }
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
    /// the longest interval, fuzzed as Anki fuzzes it: picked by the fuzz
    /// factor from `fuzzRange(of:atLeast:)`.
    private func fuzzed(_ days: Double, atLeast minimum: Int) -> Int {
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
/// recorded it, which keeps its interval: FichaCore knows a card by no name
/// that's the same on every device.
///
/// The seed's numbers go through SplitMix64's mixing function (Steele, Lea
/// and Flood, 2014), integer arithmetic alone, so every device, run and
/// version of Swift gives the same factor: Swift's `Hasher` is seeded anew
/// in each run, and Foundation has no seeded generator.
func fuzzFactor(of card: FuzzSeedCard, way: Way, reviewsBefore reviews: Int) -> Double {
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
enum FuzzSeedCard {
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
