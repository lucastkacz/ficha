import Foundation

// Where an Anki card stands in Anki, as an import that brings its progress
// reads it (ADR 0013). The columns' meanings follow Anki's source,
// `rslib/src/card/mod.rs`; how Anki counts its days, `rslib/src/scheduler/
// timing.rs`; and how its importer moves a card's due day into the collection
// it imports into, `rslib/src/import_export/package/apkg/import/cards.rs`.

/// How an Anki collection counts its days, as its configuration says: the
/// keys `creationOffset` and `rollover`, which schema 11 keeps in `col.conf`,
/// a JSON object, and schema 18 in its `config` table, a JSON value for each
/// key (`rslib/src/config/`). A review card's due day is one of these days,
/// counted from the day the collection was created, `col.crt`.
public struct AnkiDaySettings: Sendable, Equatable {
    /// The UTC offset the collection was created at, in minutes west of UTC,
    /// so UTC−3 is 180; or nil when its configuration doesn't say, as in one
    /// Anki 2.0 or its v1 scheduler wrote, for which Anki takes the offset
    /// the Mac that imports it has at the collection's creation.
    public let creationOffset: Int?
    /// The hour each of Anki's days starts at: 4 when the configuration
    /// doesn't say, as Anki takes it, and as current Anki's packages leave
    /// it out.
    public let rollover: Int

    /// The settings of a collection whose configuration holds
    /// `creationOffset` and `rollover`, each nil when it doesn't hold it, or
    /// a problem when either is out of range: an offset beyond a day, or a
    /// rollover that isn't an hour of the day.
    public init(creationOffset: Int?, rollover: Int?) throws(AnkiCollectionProblem) {
        if let creationOffset, abs(creationOffset) >= 24 * 60 {
            throw AnkiCollectionProblem("The collection's creation offset is \(creationOffset) minutes")
        }
        if let rollover, !(0..<24).contains(rollover) {
            throw AnkiCollectionProblem("The collection's day starts at \(rollover) o'clock")
        }
        self.creationOffset = creationOffset
        self.rollover = rollover ?? 4
    }
}

extension AnkiCollection {
    /// Where `card` stands in Anki, as an import brings it, with its due
    /// days as dates in `calendar`, the user's, or a problem when its type
    /// isn't one Anki has or a date can't be made.
    ///
    /// A card in a filtered deck stands as it would back in its home deck,
    /// as Anki puts it when it empties the deck: its home deck's due when
    /// it kept one, and the queue its type gives it unless it's suspended or
    /// buried. A review card in Anki 2.0's learning queues is being
    /// relearned, as Anki relabels it when it imports a package of its v1
    /// scheduler.
    func progress(of card: AnkiCard, in calendar: Calendar) throws(AnkiCollectionProblem) -> ImportedProgress {
        let isInFilteredDeck = card.originalDeckID != 0
        let due = isInFilteredDeck && card.originalDue != 0 ? card.originalDue : card.due
        // Suspended stays suspended, out of a filtered deck too.
        let isSuspended = card.queue == -1
        let stage: ImportedProgress.Stage
        switch card.type {
        case 0:
            stage = .new
        case 1, 3:
            stage = .learning(due: try learningDue(due, in: calendar))
        case 2 where !isInFilteredDeck && (card.queue == 1 || card.queue == 3):
            stage = .learning(due: try learningDue(due, in: calendar))
        case 2:
            stage = .review(interval: .seconds(card.interval * 24 * 60 * 60), due: try start(ofDay: due, in: calendar))
        default:
            throw AnkiCollectionProblem("Card \(card.id) is of the type \(card.type)")
        }
        return ImportedProgress(stage: stage, isSuspended: isSuspended)
    }

    /// When a card Anki is learning is due, from its `due`: a time in
    /// seconds since 1970, or, for a card whose learning steps last a day or
    /// more, a day of the collection, which Anki tells apart by size
    /// (`scheduler/timing.rs`, `is_unix_epoch_timestamp`).
    private func learningDue(_ due: Int64, in calendar: Calendar) throws(AnkiCollectionProblem) -> Date {
        due > 1_000_000_000 ? Date(timeIntervalSince1970: TimeInterval(due)) : try start(ofDay: due, in: calendar)
    }

    /// When the collection's day `day` starts in `calendar`, the user's, as
    /// Anki's importer moves a due day into the collection it imports into.
    /// The importer shifts the day by how far the package's today is from
    /// the user's (`collection_delta`), so the card falls due on the same
    /// date it would in the package: the date the collection was created on,
    /// at its creation offset, `day` days later. The day starts there at the
    /// collection's rollover hour, by the user's clock.
    func start(ofDay day: Int64, in calendar: Calendar) throws(AnkiCollectionProblem) -> Date {
        let created = Date(timeIntervalSince1970: TimeInterval(creationTime))
        var creationCalendar = Calendar(identifier: .gregorian)
        // Without an offset, Anki takes the user's at the creation time.
        if let creationOffset = daySettings.creationOffset {
            guard let zone = TimeZone(secondsFromGMT: -creationOffset * 60) else {
                throw AnkiCollectionProblem("The collection's creation offset is \(creationOffset) minutes")
            }
            creationCalendar.timeZone = zone
        } else {
            creationCalendar.timeZone = calendar.timeZone
        }
        let createdOn = creationCalendar.dateComponents([.year, .month, .day], from: created)
        // The date `day` days after it, counted as dates, in a calendar
        // whose days are all 24 hours long.
        var dates = Calendar(identifier: .gregorian)
        dates.timeZone = .gmt
        guard let creationDate = dates.date(from: createdOn),
            let dueDate = dates.date(byAdding: .day, value: Int(clamping: day), to: creationDate)
        else {
            throw AnkiCollectionProblem("Day \(day) of the collection isn't a date")
        }
        var dueOn = dates.dateComponents([.year, .month, .day], from: dueDate)
        dueOn.hour = daySettings.rollover
        guard let start = calendar.date(from: dueOn) else {
            throw AnkiCollectionProblem("Day \(day) of the collection isn't a date")
        }
        return start
    }
}
