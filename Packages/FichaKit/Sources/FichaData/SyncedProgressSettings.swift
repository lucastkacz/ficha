import FichaCore
import Foundation
internal import GRDB

// The settings that decide a card's progress, in the database (#315): the
// scheduler's settings (#404), the new cards a day and the forgotten-often
// count, in one row, which syncs as one record named by its type (ADR 0017).
// Each setting keeps its latest change, as a tag's color does, so a change on
// one device and another on a second one both survive: each of the
// scheduler's too, the learning steps, the relearning steps, the desired
// retention, the longest interval and FSRS's parameters. Each holds a whole
// value, a list of steps or of parameters included, which is valid on its
// own, so settings that take some from one device and the rest from another
// are always valid. No row means Ficha's. The ladder that a version of Ficha
// before FSRS kept in the record stays there, unread.

extension Engine {
    /// The settings that decide a card's progress, as the database holds
    /// them: Ficha's, until they're saved or moved in, or come from another
    /// device.
    public func progressSettings() throws(EngineError) -> ProgressSettings {
        try read(FichaData.progressSettings(in:))
    }

    /// Keeps those of `settings` that the user changed in Settings from
    /// `old`, which Settings showed before: each waits to be sent to the
    /// user's other devices. The others keep what the database holds, which
    /// another device or the CLI may have changed since Settings read it.
    /// When none changed, the database doesn't either, and no engine hears of
    /// it.
    public func saveProgressSettings(_ settings: ProgressSettings, changedFrom old: ProgressSettings)
        throws(EngineError)
    {
        try changeStoredProgressSettings { stored in
            (stored ?? ReviewSettings.defaults.progress).taking(settings, changedFrom: old)
        }
    }

    /// Moves in the settings that decide a card's progress as this device
    /// kept them before they synced, in the app's preferences, which `kept`
    /// reads, when the database holds none yet: as the app opens it after the
    /// update, whether the CLI, which can't read the app's preferences,
    /// opened it first, and after a restore of a copy from before the update.
    /// It reads `kept` only then, on the caller's thread. Ficha's own move in
    /// nothing, so preferences that come later, as #309 brings them into the
    /// sandboxed app, still move in. Those that aren't Ficha's count as
    /// changed now, and wait to be sent to the user's other devices.
    public func moveInProgressSettings(keptBeforeSync kept: () -> ProgressSettings) throws(EngineError) {
        guard try read(storedProgressSettings(in:)) == nil else {
            return
        }
        let kept = kept()
        try changeStoredProgressSettings { stored in stored == nil ? kept : nil }
    }

    /// Keeps, in one transaction, the settings that decide a card's progress
    /// that `change` makes of those the database holds, or of nil when it
    /// holds none, unless it makes none, or the same as the database holds,
    /// which is Ficha's when it holds none. Only when the database changed
    /// does every engine on it hear so.
    private func changeStoredProgressSettings(_ change: (ProgressSettings?) -> ProgressSettings?)
        throws(EngineError)
    {
        let changed = try writeWithoutTelling { db in
            let stored = try storedProgressSettings(in: db)
            guard let settings = change(stored), settings != (stored ?? ReviewSettings.defaults.progress) else {
                return false
            }
            try storeProgressSettings(settings, in: db)
            return true
        }
        if changed {
            databaseChanges.post()
        }
    }
}

/// The fields of the settings that decide progress, each of which keeps when
/// it last changed. Each is the key of its value in the settings' record too,
/// and the name of the column that holds it.
private let progressFields: [SyncedField] = [
    .newCardsPerDay, .forgottenOftenAfter, .learningSteps, .relearningSteps, .desiredRetention,
    .longestIntervalInDays, .fsrsParameters,
]

/// The record of the settings that decide progress, as they are now, without
/// what iCloud said of it, or nil while the device holds Ficha's, which it
/// has nothing to send of.
func progressSettingsRecord(in db: Database) throws -> ICloudRecord? {
    try storedProgressSettings(in: db).map { settings in try recordHolding(settings, in: db) }
}

/// Applies `record`, from iCloud, to the settings that decide progress: they
/// take each one whose change in the record is the latest, or come in with
/// it, beside Ficha's for the others. A record whose settings this version
/// of Ficha can't read throws, so it waits.
func applyProgressSettings(_ record: ICloudRecord, in db: Database) throws -> Bool {
    let theirs = try StoredProgressSettings(record: record)
    _ = try theirs.checked()
    let ours = try progressSettings(in: db)
    try takeLatestChanges(
        of: progressFields, in: record, over: try recordHolding(ours, in: db), to: .progressSettings, in: db
    ) { won in
        var settings = try StoredProgressSettings(ours)
        /// Takes theirs of the setting at `keyPath`, `field`, when its change
        /// in the record won.
        func take<Value>(_ field: SyncedField, _ keyPath: WritableKeyPath<StoredProgressSettings, Value>) {
            if won.contains(field) {
                settings[keyPath: keyPath] = theirs[keyPath: keyPath]
            }
        }
        take(.newCardsPerDay, \.newCardsPerDay)
        take(.forgottenOftenAfter, \.forgottenOftenAfter)
        take(.learningSteps, \.learningSteps)
        take(.relearningSteps, \.relearningSteps)
        take(.desiredRetention, \.desiredRetention)
        take(.longestIntervalInDays, \.longestIntervalInDays)
        take(.fsrsParameters, \.fsrsParameters)
        try storeProgressSettings(try settings.checked(), in: db)
    }
    return true
}

/// The record of the settings that decide progress when the device holds
/// `settings`, with when each of them last changed, of those that did.
private func recordHolding(_ settings: ProgressSettings, in db: Database) throws -> ICloudRecord {
    try syncedRecord(
        of: .progressSettings, holding: try StoredProgressSettings(settings).recordValues, andTimesOf: progressFields,
        in: db)
}

/// The settings that decide a card's progress, as `db` holds them: Ficha's,
/// until they're saved or moved in, or come from another device.
func progressSettings(in db: Database) throws -> ProgressSettings {
    try storedProgressSettings(in: db) ?? ReviewSettings.defaults.progress
}

/// The settings that decide a card's progress, as the database holds them,
/// or nil before it holds any.
private func storedProgressSettings(in db: Database) throws -> ProgressSettings? {
    try Row.fetchOne(db, sql: "SELECT * FROM progressSettings").map { row in
        try StoredProgressSettings(row: row).checked()
    }
}

/// Keeps `settings` as the settings that decide a card's progress: the row
/// comes in with Ficha's defaults, if it isn't there yet, and then takes
/// them, so that what differs from Ficha's counts as changed.
private func storeProgressSettings(_ settings: ProgressSettings, in db: Database) throws {
    if try storedProgressSettings(in: db) == nil {
        let fichas = try StoredProgressSettings(ReviewSettings.defaults.progress).columnValues
        try db.execute(
            sql: """
                INSERT INTO progressSettings (id, \(fichas.map(\.field.rawValue).joined(separator: ", ")))
                VALUES (1, \(fichas.map { _ in "?" }.joined(separator: ", ")))
                """,
            arguments: StatementArguments(fichas.map(\.value)))
    }
    let values = try StoredProgressSettings(settings).columnValues
    try db.execute(
        sql: "UPDATE progressSettings SET \(values.map { "\($0.field.rawValue) = ?" }.joined(separator: ", "))",
        arguments: StatementArguments(values.map(\.value)))
}

/// The settings that decide a card's progress as the database's row and the
/// settings' record keep them, each under its field's name.
private struct StoredProgressSettings {
    var newCardsPerDay: Int
    /// Nil when the review panel never offers to flag a card.
    var forgottenOftenAfter: Int?
    /// Each learning step's interval in whole seconds, from the first, as a
    /// JSON array: an empty one for none.
    var learningSteps: String
    /// Each relearning step's interval, as the learning steps are.
    var relearningSteps: String
    /// A fraction, from 0.70 to 0.99.
    var desiredRetention: Double
    var longestIntervalInDays: Int
    /// FSRS's parameters, in fsrs-rs's order, as a JSON array of numbers,
    /// each the exact value of its 32-bit float, so that it reads back bit
    /// for bit: an empty one for FSRS-6's defaults.
    var fsrsParameters: String

    /// `settings`, as they're kept.
    init(_ settings: ProgressSettings) throws {
        newCardsPerDay = settings.newCardsPerDay
        forgottenOftenAfter = settings.forgottenOftenAfter
        learningSteps = try jsonText(settings.scheduler.learningSteps.map(\.components.seconds))
        relearningSteps = try jsonText(settings.scheduler.relearningSteps.map(\.components.seconds))
        desiredRetention = settings.scheduler.desiredRetention
        longestIntervalInDays = settings.scheduler.longestIntervalInDays
        // A Double holds every Float exactly, and JSON every Double.
        fsrsParameters = try jsonText(settings.scheduler.parameters.map(Double.init))
    }

    /// The settings the database's row holds.
    init(row: Row) throws {
        newCardsPerDay = try row.decode(forColumn: SyncedField.newCardsPerDay.rawValue)
        forgottenOftenAfter = try row.decode(forColumn: SyncedField.forgottenOftenAfter.rawValue)
        learningSteps = try row.decode(forColumn: SyncedField.learningSteps.rawValue)
        relearningSteps = try row.decode(forColumn: SyncedField.relearningSteps.rawValue)
        desiredRetention = try row.decode(forColumn: SyncedField.desiredRetention.rawValue)
        longestIntervalInDays = try row.decode(forColumn: SyncedField.longestIntervalInDays.rawValue)
        fsrsParameters = try row.decode(forColumn: SyncedField.fsrsParameters.rawValue)
    }

    /// The settings `record`, from iCloud, holds. A record from a version of
    /// Ficha before the scheduler's settings holds none of them, nor when
    /// they changed: it reads as holding Ficha's, which never win over the
    /// device's own (`FieldChange`).
    init(record: ICloudRecord) throws {
        let fichas = try StoredProgressSettings(ReviewSettings.defaults.progress)
        newCardsPerDay = try record.integer(SyncedField.newCardsPerDay.rawValue)
        forgottenOftenAfter = try record.optionalInteger(SyncedField.forgottenOftenAfter.rawValue)
        learningSteps = try record.optionalText(SyncedField.learningSteps.rawValue) ?? fichas.learningSteps
        relearningSteps = try record.optionalText(SyncedField.relearningSteps.rawValue) ?? fichas.relearningSteps
        desiredRetention =
            try record.optionalNumber(SyncedField.desiredRetention.rawValue) ?? fichas.desiredRetention
        longestIntervalInDays =
            try record.optionalInteger(SyncedField.longestIntervalInDays.rawValue) ?? fichas.longestIntervalInDays
        fsrsParameters = try record.optionalText(SyncedField.fsrsParameters.rawValue) ?? fichas.fsrsParameters
    }

    /// The value of each of the row's columns, beside the field that names
    /// the column, so that each statement takes its columns and its values
    /// from the same pairs.
    var columnValues: [(field: SyncedField, value: (any DatabaseValueConvertible)?)] {
        [
            (.newCardsPerDay, newCardsPerDay), (.forgottenOftenAfter, forgottenOftenAfter),
            (.learningSteps, learningSteps), (.relearningSteps, relearningSteps),
            (.desiredRetention, desiredRetention), (.longestIntervalInDays, longestIntervalInDays),
            (.fsrsParameters, fsrsParameters),
        ]
    }

    /// The values of the record's fields, each under its key.
    var recordValues: [String: ICloudValue?] {
        [
            SyncedField.newCardsPerDay.rawValue: .int(Int64(newCardsPerDay)),
            SyncedField.forgottenOftenAfter.rawValue: forgottenOftenAfter.map { .int(Int64($0)) },
            SyncedField.learningSteps.rawValue: .string(learningSteps),
            SyncedField.relearningSteps.rawValue: .string(relearningSteps),
            SyncedField.desiredRetention.rawValue: .double(desiredRetention),
            SyncedField.longestIntervalInDays.rawValue: .int(Int64(longestIntervalInDays)),
            SyncedField.fsrsParameters.rawValue: .string(fsrsParameters),
        ]
    }

    /// The settings that decide a card's progress these values make, or an
    /// error when they don't make them: scheduling settings by `Scheduler`'s
    /// rules, steps from 10 minutes to less than a day, each longer than the
    /// one before, or none, a desired retention from 0.70 to 0.99, a longest
    /// interval from 1 to 36,500 days, and 21 parameters or none; at least 0
    /// new cards a day; and a forgotten-often count of 1 at least, or none.
    func checked() throws -> ProgressSettings {
        let parameters = try JSONDecoder().decode([Double].self, from: Data(fsrsParameters.utf8))
        guard
            let scheduler = Scheduler(
                learningSteps: try wholeSeconds(in: learningSteps),
                relearningSteps: try wholeSeconds(in: relearningSteps),
                desiredRetention: desiredRetention, longestIntervalInDays: longestIntervalInDays,
                parameters: parameters.map(Float.init))
        else {
            throw unreadable("The settings that decide progress have scheduling settings that break their rules")
        }
        guard newCardsPerDay >= 0, (forgottenOftenAfter ?? 1) >= 1 else {
            throw unreadable("The settings that decide progress have a count below its least")
        }
        return ProgressSettings(
            scheduler: scheduler, newCardsPerDay: newCardsPerDay, forgottenOftenAfter: forgottenOftenAfter)
    }
}

/// `values` as a JSON array.
private func jsonText(_ values: [some Encodable]) throws -> String {
    String(decoding: try JSONEncoder().encode(values), as: UTF8.self)
}

/// The spans of time that `text`, a JSON array of whole seconds, holds.
private func wholeSeconds(in text: String) throws -> [Duration] {
    try JSONDecoder().decode([Int64].self, from: Data(text.utf8)).map { .seconds($0) }
}
