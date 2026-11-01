import FichaCore
import Foundation

// What the scheduler's tests share: the moments they start from, spans of
// time, the scheduler's settings they change, and the review log entries of
// card 1's front-first way, as recording an answer and an import will write
// them.

// Spans of time in seconds, as dates count them: `start + 4 * hour`. A span
// the scheduler keeps, such as a step or an interval, is a `Duration`, which
// `.minutes(_:)`, `.hours(_:)` and `.days(_:)` below give.
let minute: TimeInterval = 60
let hour: TimeInterval = 60 * minute
let day: TimeInterval = 24 * hour
let start = Date(timeIntervalSince1970: 1_760_000_000)

/// Card 1's front-first way, whose log the tests replay.
let wayOne = CardWay(cardID: 1, way: .frontFirst)

/// Card 1's front-first way as an import from Anki brings it graduated: its
/// interval 10 days, due at the tests' start.
let graduated = placement(interval: .days(10), due: start, at: start - 10 * day)

extension Duration {
    /// A span of whole minutes.
    static func minutes(_ count: Int64) -> Duration {
        .seconds(count * 60)
    }

    /// A span of whole hours.
    static func hours(_ count: Int64) -> Duration {
        .seconds(count * 60 * 60)
    }

    /// A span of whole days.
    static func days(_ count: Int64) -> Duration {
        .seconds(count * 24 * 60 * 60)
    }
}

/// The standard scheduler, but for the settings given.
func scheduler(
    learningSteps: [Duration] = Scheduler.standard.learningSteps,
    relearningSteps: [Duration] = Scheduler.standard.relearningSteps,
    desiredRetention: Double = Scheduler.standard.desiredRetention,
    longestIntervalInDays: Int = Scheduler.standard.longestIntervalInDays
) throws -> Scheduler {
    guard
        let scheduler = Scheduler(
            learningSteps: learningSteps, relearningSteps: relearningSteps, desiredRetention: desiredRetention,
            longestIntervalInDays: longestIntervalInDays, parameters: [])
    else {
        throw InvalidSettings()
    }
    return scheduler
}

/// Settings a test gave that don't make a scheduler.
struct InvalidSettings: Error {}

/// A review of the card with the id `cardID`, front first unless `way` says
/// otherwise, rated `rating` at `time`, keeping `interval`, when it kept one,
/// answering `answeredEntry`, or none, as a new way's first review does,
/// with an ID of its own that the same review always gets, so that the
/// fuzz the scheduler seeds with it is the same in every run, or `uuid`.
func review(
    _ rating: Rating, at time: Date, keeping interval: Duration? = nil, cardID: Int64 = 1,
    way: Way = .frontFirst, answering answeredEntry: UUID? = nil, uuid: UUID? = nil
) -> ReviewLogEntry {
    ReviewLogEntry(
        cardID: cardID, way: way, kind: .review(rating), answeredAt: time, responseTime: .seconds(3),
        trigger: .reviewNow, uuid: uuid ?? fixedID(at: time, kind: Rating.allCases.firstIndex(of: rating) ?? 0),
        answeredEntry: answeredEntry, interval: interval)
}

/// An ID unique across devices made of an entry's moment and kind, the same
/// in every run, unlike a random one.
func fixedID(at time: Date, kind: Int) -> UUID {
    let high = time.timeIntervalSince1970.bitPattern
    let low = UInt64(kind)
    let bytes = withUnsafeBytes(of: (high.bigEndian, low.bigEndian)) { Array($0) }
    return UUID(
        uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9],
            bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
}

/// `log`, card 1's front-first way's, with a review rated `rating` at `time`
/// as recording an answer will write it on a device that knows `log`:
/// keeping the interval `scheduler`'s preview gives the rating then, and
/// answering the entry it replays last.
func answering(
    _ rating: Rating, at time: Date, after log: [ReviewLogEntry], on scheduler: Scheduler = .standard
) throws -> [ReviewLogEntry] {
    let kept = try scheduler.preview(of: wayOne, after: log, at: time)[rating]
    let last = log.max { $0.precedes($1) }
    return log + [review(rating, at: time, keeping: kept, answering: last?.uuid)]
}

/// Card 1's front-first way's placement, as an import from Anki gives it at
/// `time`: due at `due`, with Anki's interval and ease.
func placement(interval: Duration?, ease: Double? = 2.5, due: Date, at time: Date) -> ReviewLogEntry {
    ReviewLogEntry(
        placing: 1, on: Placement(step: 0, due: due, interval: interval, ease: ease), at: time,
        uuid: fixedID(at: time, kind: 4))
}

extension WayStanding {
    /// The interval of a graduated way in whole days, or nil for another.
    var graduatedDays: Int64? {
        guard stage == .graduated, let interval else {
            return nil
        }
        return interval.components.seconds / Int64(day)
    }
}

extension IntervalPreview {
    /// Each rating's interval in whole days, again's first.
    var days: [Int64] {
        Rating.allCases.map { self[$0].components.seconds / Int64(day) }
    }
}
