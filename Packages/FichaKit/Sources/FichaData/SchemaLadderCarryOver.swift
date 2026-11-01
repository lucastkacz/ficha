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
/// the scheduler reads as graduated, Anki's starting ease. Nil for a step
/// below the first, 0, which the ladder refused, as the review log's check
/// did from "v14 placements in the review log" on.
func ladderPlacement(onStep step: Int64, of waits: [Int64]) -> (interval: Duration, ease: Double?)? {
    guard step >= 0 else {
        return nil
    }
    let waits = waits.isEmpty ? shippedLadderWaits : waits
    let wait = Duration.seconds(waits[Int(min(step, Int64(waits.count - 1)))])
    return (wait, wait >= .seconds(24 * 60 * 60) ? ankiStartingEase : nil)
}

/// The kind and rating, as the review log's columns and records name them,
/// of an entry that a version of Ficha before FSRS kept, as this version
/// keeps it: a first view, which put a new way on the ladder's first step,
/// becomes a review rated again, which puts it on the first learning step,
/// as the scheduler reads a new way's first review; a review and a
/// placement keep their own.
func carriedOver(kind: String, rating: String?) -> (kind: String, rating: String?) {
    kind == "firstView" ? ("review", Rating.again.rawValue) : (kind, rating)
}

/// The scheduling settings the review log is carried over with, by the
/// migration and on arrival alike, whatever the device's are, so that every
/// device carries over the log they share alike: Ficha's as FSRS came
/// (#407), written out here, so that a later change to Ficha's own leaves
/// them alone. Learning steps of 1 hour and 4 hours, a relearning step of 1
/// hour, a desired retention of 90%, a longest interval of 36,500 days, and
/// FSRS-6's 21 default parameters as fsrs-rs 6.6.2 has them
/// (`DEFAULT_PARAMETERS` in its `src/inference.rs`), so that a later fsrs-rs
/// leaves them alone too. The replay itself, Anki's step rules and fsrs-rs's
/// arithmetic (`Scheduler.keepingIntervals(of:)`), is live code: a change to
/// either changes what a device that migrates, or takes an older device's
/// entry, after it carries over.
func carryOverScheduler() throws -> Scheduler {
    guard
        let scheduler = Scheduler(
            learningSteps: [.seconds(3_600), .seconds(14_400)], relearningSteps: [.seconds(3_600)],
            desiredRetention: 0.9, longestIntervalInDays: 36_500,
            parameters: [
                0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001, 1.8722, 0.1666, 0.796, 1.4835, 0.0614,
                0.2629, 1.6483, 0.6014, 1.8729, 0.5425, 0.0912, 0.0658, 0.1542,
            ])
    else {
        throw unreadable("The settings the review log is carried over with aren't valid: fix carryOverScheduler()")
    }
    return scheduler
}

/// One way's entries, `wayLog`, in any order, in the order the scheduler
/// replays them, with the reviews among them that `carriedOver` names by
/// their IDs carried over: each, whatever interval and answered entry it
/// held, answering the entry replayed just before it, or none as the way's
/// first, and keeping the interval the replay gives it there with
/// `carryOverScheduler()`, so that the scheduler keeps it, and a later change
/// to the device's settings leaves the way's due time alone (#404). The
/// other entries stay as they are, and the replay follows them as any
/// device's does.
func carryingOver(_ carriedOver: Set<UUID>, in wayLog: [ReviewLogEntry]) throws -> [ReviewLogEntry] {
    let unkept = wayLog.map { entry in
        guard let uuid = entry.uuid, carriedOver.contains(uuid) else {
            return entry
        }
        return ReviewLogEntry(
            cardID: entry.cardID, way: entry.way, kind: entry.kind, answeredAt: entry.answeredAt,
            responseTime: entry.responseTime, trigger: entry.trigger, isAhead: entry.isAhead, uuid: uuid)
    }
    return try carryOverScheduler().keepingIntervals(of: unkept)
}

/// Applies `record`, the review log's entry with this ID from iCloud, as
/// `SyncedTable.reviewLog` applies it, an entry new to the device carried
/// over first when a version of Ficha before FSRS sent it: its first view as
/// a review rated again, its placement on a step of the ladder with that
/// step's interval and ease on the ladder Ficha shipped, since the sending
/// device's isn't known, and its review without an interval as a review the
/// carry-over gives one, among the entries of its way the device holds, and
/// marks as carried over. iCloud gives a way's entries in any order (ADR
/// 0017), so every entry new to the device has its way's carried-over
/// reviews carried over again (`carryingOver(_:in:)`): whichever came first,
/// each ends up answering the entry before it, with the interval the
/// carry-over gives it there, as the migration carries over a review.
/// Returns false, changing nothing, when the entry's card isn't here yet,
/// for it to wait.
func applyReviewLogEntry(_ record: ICloudRecord, as uuid: UUID, in db: Database) throws -> Bool {
    guard try !SyncedTable.reviewLog.holdsRow(with: uuid, in: db) else {
        return try SyncedTable.reviewLog.apply(record, toRowWith: uuid, in: db)
    }
    var fields = record.fields
    // The ladder's step, which no column keeps any longer.
    fields["step"] = nil
    let (kind, rating) = carriedOver(kind: try record.text("kind"), rating: try record.optionalText("rating"))
    fields["kind"] = ICloudValue.string(kind)
    fields["rating"] = rating.map(ICloudValue.string)
    let isCarriedOver = kind == "review" && record.value(of: "interval") == nil
    if kind == "placement", record.value(of: "interval") == nil {
        guard case .int(let step)? = record.value(of: "step"),
            let placed = ladderPlacement(onStep: step, of: shippedLadderWaits)
        else {
            throw unreadable("A placement from iCloud has neither its interval nor a step on the ladder")
        }
        fields["interval"] = ICloudValue.double(placed.interval.timeInterval)
        fields["ease"] = placed.ease.map(ICloudValue.double)
    }
    let carried = ICloudRecord(id: record.id, type: record.type, fields: fields, systemFields: record.systemFields)
    guard
        try SyncedTable.reviewLog.apply(
            isCarriedOver ? try givenItsInterval(carried, as: uuid, in: db) : carried, toRowWith: uuid, in: db)
    else {
        return false
    }
    if isCarriedOver {
        try db.execute(sql: "UPDATE reviewLog SET isCarriedOver = 1 WHERE uuid = ?", arguments: [uuid.uuidString])
    }
    try carryOverAgain(theWayOf: uuid, in: db)
    return true
}

/// `review`, a review with this ID from iCloud that holds no interval, which
/// the device doesn't hold yet, given the interval the carry-over gives it,
/// and the entry it answers, among the entries of its way the device holds,
/// as `carryingOver(_:in:)` says; or as it is, when the device doesn't hold
/// its card yet, to wait for it.
private func givenItsInterval(_ review: ICloudRecord, as uuid: UUID, in db: Database) throws -> ICloudRecord {
    guard let cardName = try review.optionalText("card"), let cardUUID = UUID(uuidString: cardName),
        let wayName = try review.optionalText("way"), let way = Way(rawValue: wayName),
        let rating = Rating(rawValue: try review.text("rating")), let answeredAt = try review.time("answeredAt")
    else {
        throw unreadable("A review from iCloud lacks its card, its way, its rating or when it was answered")
    }
    guard
        let cardID = try Int64.fetchOne(
            db, sql: "SELECT id FROM card WHERE uuid = ?", arguments: [cardUUID.uuidString])
    else {
        return review
    }
    let held = try wayLog(of: CardWay(cardID: cardID, way: way), in: db)
    let entry = ReviewLogEntry(
        cardID: cardID, way: way, kind: .review(rating), answeredAt: answeredAt, responseTime: nil, trigger: nil,
        uuid: uuid)
    guard
        let carried = try carryingOverOnArrival(held.carriedOver.union([uuid]), in: held.entries + [entry])
            .first(where: { $0.uuid == uuid }),
        let interval = carried.interval
    else {
        throw unreadable("A review from iCloud can't be given its interval")
    }
    var fields = review.fields
    fields["interval"] = ICloudValue.double(interval.timeInterval)
    fields["answeredEntry"] = carried.answeredEntry.map { ICloudValue.string($0.uuidString) }
    return ICloudRecord(id: review.id, type: review.type, fields: fields, systemFields: review.systemFields)
}

/// Carries over again, as `carryingOver(_:in:)` says, the reviews that were
/// carried over of the way of the review log's entry with this ID, which
/// just joined it: one that comes before them in the replay changes the
/// entry each answers, or the interval it's spaced from, and the way's first
/// entry seeds the fuzz of every review after it. Only the reviews it changes
/// are written.
private func carryOverAgain(theWayOf uuid: UUID, in db: Database) throws {
    guard
        let joined = try Row.fetchOne(db, sql: "SELECT * FROM reviewLog WHERE uuid = ?", arguments: [uuid.uuidString])
            .map(ReviewLogEntry.init(row:))
    else {
        throw unreadable("A review log entry from iCloud isn't there once applied")
    }
    let held = try wayLog(of: CardWay(cardID: joined.cardID, way: joined.way), in: db)
    guard !held.carriedOver.isEmpty else {
        return
    }
    for review in try carryingOverOnArrival(held.carriedOver, in: held.entries) {
        guard let id = review.uuid, held.carriedOver.contains(id), !held.entries.contains(review) else {
            continue
        }
        try db.execute(
            sql: "UPDATE reviewLog SET interval = ?, answeredEntryUuid = ? WHERE uuid = ?",
            arguments: [review.interval?.timeInterval, review.answeredEntry?.uuidString, id.uuidString])
    }
}

/// `carryingOver(_:in:)`, whose failure says the entry from iCloud can't be
/// read here, so that it waits, and the log says why.
private func carryingOverOnArrival(_ carriedOver: Set<UUID>, in wayLog: [ReviewLogEntry]) throws
    -> [ReviewLogEntry]
{
    do {
        return try carryingOver(carriedOver, in: wayLog)
    } catch let error as SchedulingError {
        throw unreadable("A review log entry from iCloud can't be carried over: \(error.description)")
    }
}

/// The entries of `cardWay`, one way of a card the device holds, in the
/// review log, in the order the device recorded them, and the IDs of the
/// reviews among them that were carried over.
private func wayLog(of cardWay: CardWay, in db: Database) throws -> (
    entries: [ReviewLogEntry], carriedOver: Set<UUID>
) {
    let rows = try Row.fetchAll(
        db, sql: "SELECT * FROM reviewLog WHERE cardId = ? AND way = ? ORDER BY id",
        arguments: [cardWay.cardID, cardWay.way.rawValue])
    var entries: [ReviewLogEntry] = []
    var carriedOver: Set<UUID> = []
    for row in rows {
        let entry = try ReviewLogEntry(row: row)
        entries.append(entry)
        if try row.decode(forColumn: "isCarriedOver") as Bool, let uuid = entry.uuid {
            carriedOver.insert(uuid)
        }
    }
    return (entries, carriedOver)
}
