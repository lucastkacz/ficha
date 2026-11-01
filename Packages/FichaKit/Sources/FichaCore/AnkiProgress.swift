import Foundation

// Where an Anki card stands in Anki, and the reviews of its history that
// brought it there, as an import that brings its progress reads them (ADR
// 0013, #409). The columns' meanings follow Anki's source,
// `rslib/src/card/mod.rs` and `rslib/src/revlog/mod.rs`; how Anki counts its
// days, `rslib/src/scheduler/timing.rs`; how its importer moves a card's due
// day into the collection it imports into,
// `rslib/src/import_export/package/apkg/import/cards.rs`; and which reviews
// its FSRS reads, `rslib/src/scheduler/fsrs/`.

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
        // A range rather than `abs`, which has no answer for the smallest
        // number.
        if let creationOffset, !(1 - 24 * 60..<24 * 60).contains(creationOffset) {
            throw AnkiCollectionProblem("The collection's creation offset is \(creationOffset) minutes")
        }
        if let rollover, !(0..<24).contains(rollover) {
            throw AnkiCollectionProblem("The collection's day starts at \(rollover) o'clock")
        }
        self.creationOffset = creationOffset
        self.rollover = rollover ?? 4
    }
}

/// The version of Anki's scheduler an Anki collection is on, as its
/// configuration's `schedVer` says (`SchedulerVersion` in
/// `rslib/src/config/mod.rs`): the key Anki 2.0 left out, which schema 11
/// keeps in `col.conf` and schema 18 in its `config` table.
public enum AnkiSchedulerVersion: Int, Sendable, Equatable {
    /// Anki 2.0's scheduler, which gave a card in learning steps three
    /// buttons: again, good and easy.
    case v1 = 1
    /// Anki 2.1's v2 scheduler, and its v3 scheduler, which keeps this
    /// version and turns itself on with another key.
    case v2 = 2

    /// The version `schedVer` names: v1 when the configuration has none, as
    /// Anki takes it (`scheduler_version`), or a problem when it names one
    /// Anki doesn't have, which Anki takes for v1 too, and Ficha doesn't
    /// guess.
    public init(schedVer: Int?) throws(AnkiCollectionProblem) {
        guard let schedVer else {
            self = .v1
            return
        }
        guard let version = AnkiSchedulerVersion(rawValue: schedVer) else {
            throw AnkiCollectionProblem("The collection's scheduler is at version \(schedVer)")
        }
        self = version
    }
}

/// An Anki card's type, its `type` column (`CardType` in
/// `rslib/src/card/mod.rs`).
private enum AnkiCardType: Int {
    case new = 0
    case learning = 1
    case review = 2
    case relearning = 3
}

/// The queue an Anki card is in, its `queue` column (`CardQueue` in
/// `rslib/src/card/mod.rs`).
private enum AnkiQueue: Int {
    case new = 0
    case learning = 1
    case review = 2
    case learningAcrossDays = 3
    case preview = 4
    case suspended = -1
    case buriedByTheScheduler = -2
    case buriedByTheUser = -3
}

/// What an entry of an Anki card's review history records, its `type`
/// (`RevlogReviewKind` in `rslib/src/revlog/mod.rs`).
private enum AnkiRevlogKind: Int64 {
    case learning = 0
    case review = 1
    case relearning = 2
    /// A review in a filtered deck: of a card not due yet, or cramming, with
    /// rescheduling off.
    case filtered = 3
    /// Set Due Date, or a reset to new.
    case manual = 4
    /// FSRS rescheduling the card as its settings changed.
    case rescheduled = 5
}

extension AnkiCollection {
    /// Where `card` stands in Anki, as an import brings it, with its due
    /// days as dates in `calendar`, the user's, and the reviews of
    /// `history`, its review history, that Anki's FSRS reads, as
    /// `importedHistory(of:)` says; or a problem when its type isn't one Anki
    /// has, a date can't be made, or a review's button or interval isn't one
    /// Anki gives.
    ///
    /// A card in a filtered deck stands as it would back in its home deck,
    /// as Anki puts it when it empties the deck: its home deck's due when
    /// it kept one, and the queue its type gives it unless it's suspended or
    /// buried. A review card in Anki 2.0's learning queues is being
    /// relearned, as Anki relabels it when it imports a package of its v1
    /// scheduler. A new card brings no history, as after a reset, whose
    /// reviews Anki no longer reads.
    func progress(of card: AnkiCard, history: [AnkiRevlogEntry], in calendar: Calendar)
        throws(AnkiCollectionProblem) -> ImportedProgress
    {
        guard let type = AnkiCardType(rawValue: card.type) else {
            throw AnkiCollectionProblem("Card \(card.id) is of the type \(card.type)")
        }
        // A queue Anki doesn't have says nothing more than the type does.
        let queue = AnkiQueue(rawValue: card.queue)
        let isInFilteredDeck = card.originalDeckID != 0
        let due = isInFilteredDeck && card.originalDue != 0 ? card.originalDue : card.due
        // Suspended stays suspended, out of a filtered deck too.
        let isSuspended = queue == .suspended
        let stage: ImportedProgress.Stage
        switch type {
        case .new:
            return ImportedProgress(stage: .new, isSuspended: isSuspended, history: .none)
        case .learning, .relearning:
            stage = .learning(due: try learningDue(due, in: calendar))
        case .review where !isInFilteredDeck && (queue == .learning || queue == .learningAcrossDays):
            stage = .learning(due: try learningDue(due, in: calendar))
        case .review:
            let (seconds, overflows) = card.interval.multipliedReportingOverflow(by: 24 * 60 * 60)
            guard !overflows else {
                throw AnkiCollectionProblem("Card \(card.id) has an interval of \(card.interval) days")
            }
            stage = .review(interval: .seconds(seconds), ease: ease(of: card), due: .on(try day(due, in: calendar)))
        }
        let isOnAStep = if case .learning = stage { true } else { false }
        return ImportedProgress(
            stage: stage, isSuspended: isSuspended, history: try importedHistory(of: history, endingOnAStep: isOnAStep))
    }

    /// The reviews of `entries`, a card's review history, that Anki's FSRS
    /// reads to work out the card's memory (`reviews_for_fsrs` in
    /// `rslib/src/scheduler/fsrs/params.rs`, and `fsrs_item_for_memory_state`
    /// in `memory_state.rs`, without a deck's "Ignore cards reviewed before",
    /// which Ficha doesn't read): the reviews from the first of its last run
    /// of learning steps, or, in a history without them, from its first
    /// review with an interval of a day or more, which becomes the history's
    /// start, with the interval and ease it set, as Anki starts FSRS from
    /// them; in either case after the card's last reset, and none when it had
    /// no review since. Reviews with a button only, so Set Due Date, resets
    /// and FSRS's rescheduling stay out, and so does cramming in a filtered
    /// deck with rescheduling off, which changes nothing. On Anki 2.0's
    /// scheduler, a learning or relearning step's 2 and 3 are good and easy,
    /// as Anki reads them once it upgrades such a collection
    /// (`rslib/src/storage/revlog/v2_upgrade.sql`).
    ///
    /// Each review left the card graduated when the next one is of a
    /// graduated card, or, for the last, when the card isn't left
    /// `endingOnAStep`, on a learning or relearning step: Anki logs an
    /// interval in days both for a graduation and, since its v3 scheduler,
    /// for a step that waits past the start of its next day
    /// (`RevlogEntryPartial::new` in `rslib/src/scheduler/answering/
    /// revlog.rs`, and `maybe_as_days` in `states/interval_kind.rs`), so only
    /// the card's next review tells them apart.
    private func importedHistory(of entries: [AnkiRevlogEntry], endingOnAStep: Bool)
        throws(AnkiCollectionProblem) -> ImportedHistory
    {
        let entries = try entries.sorted { $0.id < $1.id }.map { row throws(AnkiCollectionProblem) in
            try TypedRevlogEntry(row)
        }
        var firstOfTheLastLearningSteps: Int?
        var firstInterdayReview: Int?
        // From the last entry back, as Anki reads them.
        for (index, entry) in entries.enumerated().reversed() where !entry.isCramming {
            if entry.hasButton && (entry.row.interval >= 1 || entry.row.interval <= -24 * 60 * 60) {
                firstInterdayReview = index
            }
            if entry.hasButton && entry.kind == .learning {
                firstOfTheLastLearningSteps = index
            } else if entry.isReset {
                guard firstOfTheLastLearningSteps != nil || firstInterdayReview != nil else {
                    return .none
                }
                break
            } else if firstOfTheLastLearningSteps != nil {
                // Anki before 2.1.50 reset a card without an entry, so a
                // review before its learning steps is from before a reset.
                break
            }
        }
        guard let first = firstOfTheLastLearningSteps ?? firstInterdayReview else {
            return .none
        }
        let rated = entries[first...].filter { $0.hasButton && !$0.isCramming }
        let reviews = try rated.indices.map { index throws(AnkiCollectionProblem) in
            let next = index + 1
            return try importedReview(
                of: rated[index],
                leavingItGraduated: next < rated.count ? rated[next].isOfAGraduatedCard : !endingOnAStep)
        }
        guard firstOfTheLastLearningSteps == nil, let start = reviews.first else {
            return ImportedHistory(start: nil, reviews: reviews)
        }
        // A history that lacks its learning steps starts from the interval
        // its first review set, in days, a day at least, as Anki's FSRS
        // takes it (`first_user_grade.interval.max(1)` in `memory_state.rs`),
        // and the ease it left: Anki's starting one, 2.5, when it kept none,
        // and when it kept FSRS's difficulty there, from 100 to 1100, which
        // Anki puts in the memory it starts, and a placement doesn't hold.
        let factor = entries[first].row.factor
        let interval = Duration.days(max(1, entries[first].row.interval))
        let placement = Placement(
            interval: interval, due: start.answeredAt.adding(interval),
            ease: factor > 1100 ? Double(factor) / 1000 : 2.5)
        return ImportedHistory(
            start: ImportedStart(at: start.answeredAt, placement: placement), reviews: Array(reviews.dropFirst()))
    }

    /// `entry`, an entry of a card's review history with a button, as an
    /// import brings it, graduated when it's `leavingItGraduated` and its
    /// interval is in days, as no step's in seconds is; or a problem when its
    /// button or its interval isn't one Anki gives.
    private func importedReview(of entry: TypedRevlogEntry, leavingItGraduated: Bool)
        throws(AnkiCollectionProblem) -> ImportedReview
    {
        let row = entry.row
        let isStep = entry.kind == .learning || entry.kind == .relearning
        let button =
            schedulerVersion == .v1 && isStep && (row.button == 2 || row.button == 3) ? row.button + 1 : row.button
        let ratings: [Int64: Rating] = [1: .again, 2: .hard, 3: .good, 4: .easy]
        guard let rating = ratings[button] else {
            throw AnkiCollectionProblem("Card \(row.cardID) has a review with the button \(row.button)")
        }
        let (seconds, overflows) =
            row.interval > 0
            ? row.interval.multipliedReportingOverflow(by: 24 * 60 * 60)
            : (0 as Int64).subtractingReportingOverflow(row.interval)
        guard !overflows else {
            throw AnkiCollectionProblem("Card \(row.cardID) has a review with an interval of \(row.interval)")
        }
        return ImportedReview(
            answeredAt: Date(timeIntervalSince1970: TimeInterval(row.id) / 1000), rating: rating,
            interval: .seconds(seconds), graduated: leavingItGraduated && row.interval > 0,
            responseTime: row.milliseconds > 0 ? .milliseconds(row.milliseconds) : nil)
    }

    /// The ease of `card`, a review card, as a multiplier, such as 2.5 for
    /// its factor of 2500, or Anki's starting ease, 2.5, when it has none
    /// (`INITIAL_EASE_FACTOR` in `rslib/src/scheduler/states/review.rs`, and
    /// `initial_ease` in `rslib/src/deckconfig/mod.rs`).
    private func ease(of card: AnkiCard) -> Double {
        card.factor > 0 ? Double(card.factor) / 1000 : 2.5
    }

    /// When a card Anki is learning is due, from its `due`: a time in
    /// seconds since 1970, or, for a card whose learning steps last a day or
    /// more, a day of the collection, which Anki tells apart by size
    /// (`scheduler/timing.rs`, `is_unix_epoch_timestamp`).
    private func learningDue(_ due: Int64, in calendar: Calendar) throws(AnkiCollectionProblem) -> ImportedDue {
        due > 1_000_000_000 ? .at(Date(timeIntervalSince1970: TimeInterval(due))) : .on(try day(due, in: calendar))
    }

    /// The collection's day `day` in `calendar`, the user's, from its start,
    /// as `start(ofDay:in:)` gives it, to the next day's.
    private func day(_ day: Int64, in calendar: Calendar) throws(AnkiCollectionProblem) -> Range<Date> {
        let (next, overflows) = day.addingReportingOverflow(1)
        guard !overflows else {
            throw AnkiCollectionProblem("Day \(day) of the collection isn't a date")
        }
        return try start(ofDay: day, in: calendar)..<start(ofDay: next, in: calendar)
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
            let days = Int(exactly: day),
            let dueDate = dates.date(byAdding: .day, value: days, to: creationDate),
            // Foundation answers a day beyond what it counts to with another
            // date, which counting back tells apart.
            dates.dateComponents([.day], from: creationDate, to: dueDate).day == days
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

/// An entry of an Anki card's review history, its `revlog` row, with what
/// it records read from its `type`.
private struct TypedRevlogEntry {
    let row: AnkiRevlogEntry
    let kind: AnkiRevlogKind

    /// `row` with its type read, or a problem when its type isn't one Anki
    /// writes, which Anki reads as a learning step, and Ficha doesn't guess.
    init(_ row: AnkiRevlogEntry) throws(AnkiCollectionProblem) {
        guard let kind = AnkiRevlogKind(rawValue: row.kind) else {
            throw AnkiCollectionProblem("Card \(row.cardID) has an entry in its history of the type \(row.kind)")
        }
        self.row = row
        self.kind = kind
    }

    /// Whether a button made it: a review, and not Set Due Date, a reset or
    /// FSRS's rescheduling.
    var hasButton: Bool {
        row.button > 0
    }

    /// Whether it's cramming, a review in a filtered deck with rescheduling
    /// off, which changes nothing, and which Anki tells by its ease of 0
    /// (`is_cramming`).
    var isCramming: Bool {
        kind == .filtered && row.factor == 0
    }

    /// Whether it's a review of a graduated card, out of its learning and
    /// relearning steps: of the type Review, or Filtered, for a card Anki
    /// showed early in a filtered deck, as Anki gives an entry the type of
    /// where the card stood before it (`revlog_kind` of the current state, in
    /// `RevlogEntryPartial::new`).
    var isOfAGraduatedCard: Bool {
        kind == .review || kind == .filtered
    }

    /// Whether it's a reset of the card to new, a manual entry Anki tells
    /// from Set Due Date's by its ease of 0 (`is_reset`).
    var isReset: Bool {
        kind == .manual && row.factor == 0
    }
}
