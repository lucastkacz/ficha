import FichaCore
import Foundation
internal import GRDB

// The review log as a version of Ficha before FSRS kept it, on the ladder,
// carried over to the scheduler's (#404): by "v33 the scheduler replaces the
// ladder", and as each of its entries comes from iCloud, sent by a device
// that still runs that version. It lives beside the migrations, where the
// merge gate watches.

/// The ladder's waits as Ficha shipped them, in whole seconds, from the first
/// step up: 1 hour, 4 hours, 2 days, 5 days, 12 days, 30 days and 75 days,
/// which carry over a placement whose device's ladder isn't known.
let shippedLadderWaits: [Int64] = [3_600, 14_400, 172_800, 432_000, 1_036_800, 2_592_000, 6_480_000]

/// Anki's starting ease, 2.5 for 250% (`INITIAL_EASE_FACTOR` in
/// `rslib/src/scheduler/states/review.rs`), which a placement the ladder
/// graduated takes, since the ladder kept none.
private let ankiStartingEase = 2.5

/// The interval and ease of a placement on step `step` of a ladder with
/// `waits`, in whole seconds, as the ladder read it: the step's wait, or the
/// last step's when the ladder no longer has that one, or the shipped
/// ladder's when `waits` holds none; and, for a wait of a day or more, which
/// the scheduler reads as graduated, Anki's starting ease.
func ladderPlacement(onStep step: Int, of waits: [Int64]) -> (interval: Duration, ease: Double?) {
    let waits = waits.isEmpty ? shippedLadderWaits : waits
    let wait = Duration.seconds(waits[min(max(step, 0), waits.count - 1)])
    return (wait, wait >= .seconds(24 * 60 * 60) ? ankiStartingEase : nil)
}

/// The scheduling settings the review log is carried over with, by the
/// migration and on arrival alike: Ficha's, whatever the device's settings
/// are, so every device carries over the log they share alike, as #407 asks.
let carryOverScheduler = Scheduler.standard

/// `record`, the review log's entry with this ID from iCloud, which the
/// device doesn't hold yet, as this version of Ficha keeps it, when a
/// version before FSRS sent it: its first view becomes a review rated again,
/// as the scheduler reads one; its placement on a step of the ladder holds
/// that step's interval and ease on the ladder Ficha shipped, since the
/// device's isn't known; and its review without an interval holds the one
/// the scheduler works out for it with `carryOverScheduler`, from where it
/// falls in its way's log, answering the entry before it there, or none as
/// the way's first, as the migration carries over a review. A record whose
/// card the device doesn't hold yet comes back with what it can be given
/// without it, to wait for the card and be carried over then.
func carriedOver(_ record: ICloudRecord, as uuid: UUID, in db: Database) throws -> ICloudRecord {
    var fields = record.fields
    // The ladder's step, which no column keeps any longer.
    fields["step"] = nil
    switch try record.optionalText("kind") {
    case "firstView":
        fields["kind"] = ICloudValue.string("review")
        fields["rating"] = ICloudValue.string(Rating.again.rawValue)
    case "placement" where record.value(of: "interval") == nil:
        guard case .int(let step)? = record.value(of: "step") else {
            throw unreadable("A placement from iCloud has neither its interval nor its step on the ladder")
        }
        let placed = ladderPlacement(onStep: Int(clamping: step), of: shippedLadderWaits)
        fields["interval"] = ICloudValue.double(placed.interval.timeInterval)
        fields["ease"] = placed.ease.map(ICloudValue.double)
    default:
        break
    }
    let carried = ICloudRecord(id: record.id, type: record.type, fields: fields, systemFields: record.systemFields)
    guard try carried.optionalText("kind") == "review", carried.value(of: "interval") == nil else {
        return carried
    }
    guard let cardName = try carried.optionalText("card"), let cardUUID = UUID(uuidString: cardName),
        let wayName = try carried.optionalText("way"), let way = Way(rawValue: wayName),
        let rating = Rating(rawValue: try carried.text("rating")), let answeredAt = try carried.time("answeredAt")
    else {
        throw unreadable("A review from iCloud lacks its card, its way, its rating or when it was answered")
    }
    guard
        let cardID = try Int64.fetchOne(
            db, sql: "SELECT id FROM card WHERE uuid = ?", arguments: [cardUUID.uuidString])
    else {
        return carried
    }
    let review = ReviewLogEntry(
        cardID: cardID, way: way, kind: .review(rating), answeredAt: answeredAt, responseTime: nil, trigger: nil,
        uuid: uuid)
    let wayLog = try logEntries(ofExisting: cardID, in: db).filter { $0.way == way }
    let replayed: [ReviewLogEntry]
    do {
        replayed = try carryOverScheduler.keepingIntervals(of: wayLog + [review])
    } catch {
        throw unreadable("A review from iCloud can't be given its interval: \(error.description)")
    }
    guard let kept = replayed.first(where: { $0.uuid == uuid }), let interval = kept.interval else {
        throw unreadable("A review from iCloud can't be given its interval")
    }
    fields["interval"] = ICloudValue.double(interval.timeInterval)
    fields["answeredEntry"] = kept.answeredEntry.map { ICloudValue.string($0.uuidString) }
    return ICloudRecord(id: record.id, type: record.type, fields: fields, systemFields: record.systemFields)
}
