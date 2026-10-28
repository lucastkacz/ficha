import FichaCore
import Foundation
internal import GRDB

// The settings that decide a card's progress, in the database (#315): the
// ladder, the new cards a day and the forgotten-often count, in one row,
// which syncs as one record named by its type (ADR 0017). Each of the three
// keeps its latest change, as a tag's color does, so a change on one device
// and another on a second one both survive. No row means Ficha's.

extension Engine {
    /// The settings that decide a card's progress, as the database holds
    /// them: Ficha's, until they're saved or moved in, or come from another
    /// device.
    public func progressSettings() throws(EngineError) -> ProgressSettings {
        try read { db in try storedProgressSettings(in: db) ?? ReviewSettings.defaults.progress }
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
/// it last changed. Each is the key of its value in the settings' record too.
private let progressFields: [SyncedField] = [.ladder, .newCardsPerDay, .forgottenOftenAfter]

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
    let theirs = try checkedProgressSettings(
        ladder: try record.text(SyncedField.ladder.rawValue),
        newCardsPerDay: try record.integer(SyncedField.newCardsPerDay.rawValue),
        forgottenOftenAfter: try record.optionalInteger(SyncedField.forgottenOftenAfter.rawValue))
    let ours = try storedProgressSettings(in: db) ?? ReviewSettings.defaults.progress
    try takeLatestChanges(
        of: progressFields, in: record, over: try recordHolding(ours, in: db), to: .progressSettings, in: db
    ) { won in
        var settings = ours
        if won.contains(.ladder) {
            settings.ladder = theirs.ladder
        }
        if won.contains(.newCardsPerDay) {
            settings.newCardsPerDay = theirs.newCardsPerDay
        }
        if won.contains(.forgottenOftenAfter) {
            settings.forgottenOftenAfter = theirs.forgottenOftenAfter
        }
        try storeProgressSettings(settings, in: db)
    }
    return true
}

/// The record of the settings that decide progress when the device holds
/// `settings`, with when each of them last changed, of those that did.
private func recordHolding(_ settings: ProgressSettings, in db: Database) throws -> ICloudRecord {
    try syncedRecord(
        of: .progressSettings,
        holding: [
            SyncedField.ladder.rawValue: .string(try ladderText(settings.ladder)),
            SyncedField.newCardsPerDay.rawValue: .int(Int64(settings.newCardsPerDay)),
            SyncedField.forgottenOftenAfter.rawValue: settings.forgottenOftenAfter.map { .int(Int64($0)) },
        ],
        andTimesOf: progressFields, in: db)
}

/// The settings that decide a card's progress, as the database holds them,
/// or nil before it holds any.
func storedProgressSettings(in db: Database) throws -> ProgressSettings? {
    guard let row = try Row.fetchOne(db, sql: "SELECT * FROM progressSettings") else {
        return nil
    }
    return try checkedProgressSettings(
        ladder: row.decode(forColumn: "ladder"), newCardsPerDay: row.decode(forColumn: "newCardsPerDay"),
        forgottenOftenAfter: row.decode(forColumn: "forgottenOftenAfter"))
}

/// Keeps `settings` as the settings that decide a card's progress: the row
/// comes in with Ficha's defaults, if it isn't there yet, and then takes
/// them, so that what differs from Ficha's counts as changed.
private func storeProgressSettings(_ settings: ProgressSettings, in db: Database) throws {
    if try storedProgressSettings(in: db) == nil {
        let defaults = ReviewSettings.defaults.progress
        try db.execute(
            sql: "INSERT INTO progressSettings (id, ladder, newCardsPerDay, forgottenOftenAfter) VALUES (1, ?, ?, ?)",
            arguments: [try ladderText(defaults.ladder), defaults.newCardsPerDay, defaults.forgottenOftenAfter])
    }
    try db.execute(
        sql: "UPDATE progressSettings SET ladder = ?, newCardsPerDay = ?, forgottenOftenAfter = ?",
        arguments: [try ladderText(settings.ladder), settings.newCardsPerDay, settings.forgottenOftenAfter])
}

/// The settings that decide a card's progress made of the values the
/// database or a record keeps, or an error when they don't make them: a
/// ladder, at least 0 new cards a day, and a forgotten-often count of 1 at
/// least, or none.
private func checkedProgressSettings(ladder text: String, newCardsPerDay: Int, forgottenOftenAfter: Int?) throws
    -> ProgressSettings
{
    let seconds = try JSONDecoder().decode([Int64].self, from: Data(text.utf8))
    guard let ladder = Ladder(waits: seconds.map { .seconds($0) }) else {
        throw unreadable("The settings that decide progress have waits that don't make a ladder")
    }
    guard newCardsPerDay >= 0, (forgottenOftenAfter ?? 1) >= 1 else {
        throw unreadable("The settings that decide progress have a count below its least")
    }
    return ProgressSettings(ladder: ladder, newCardsPerDay: newCardsPerDay, forgottenOftenAfter: forgottenOftenAfter)
}

/// The ladder as the database and the record keep it: each step's wait in
/// whole seconds, from the first step up, as a JSON array.
private func ladderText(_ ladder: Ladder) throws -> String {
    String(decoding: try JSONEncoder().encode(ladder.waits.map { $0.components.seconds }), as: UTF8.self)
}
