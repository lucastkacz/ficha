import FichaCore
import Foundation
internal import GRDB

// How an Anki collection counts its days, read from its configuration, which
// a package's reader passes on to `AnkiCollection`. Each schema keeps the
// configuration its own way (`rslib/src/storage/config/`): schema 11 in
// `col.conf`, one JSON object, and schema 18 in the `config` table, one row
// for each key, whose `val` is the key's JSON value. Both give the same keys,
// `creationOffset` and `rollover`, which `AnkiDaySettings` checks.

/// How the collection whose `col.conf` is `conf`, schema 11's JSON object,
/// counts its days.
func ankiDaySettings(inConf conf: String) throws -> AnkiDaySettings {
    let keys = try JSONDecoder().decode(DayKeys.self, from: Data(conf.utf8))
    return try AnkiDaySettings(creationOffset: keys.creationOffset, rollover: keys.rollover)
}

/// How the collection in `db`, an Anki database at schema 18, counts its
/// days, from its `config` table. Its keys are read whole and picked here,
/// since Anki may give its text columns a collation only it has.
func ankiDaySettings(inConfigTableOf db: Database) throws -> AnkiDaySettings {
    var values: [String: Data] = [:]
    for row in try Row.fetchAll(db, sql: "SELECT KEY, val FROM config") {
        values[try row.decode(forColumn: "KEY")] = try row.decode(forColumn: "val")
    }
    /// The value of `key`, an integer or null, or nil when the table hasn't
    /// the key.
    func integer(_ key: String) throws -> Int? {
        try values[key].flatMap { try JSONDecoder().decode(Int?.self, from: $0) }
    }
    return try AnkiDaySettings(creationOffset: integer("creationOffset"), rollover: integer("rollover"))
}

/// The keys of an Anki collection's configuration that say how it counts its
/// days, each nil when it's missing or null.
private struct DayKeys: Decodable {
    /// Minutes west of UTC.
    let creationOffset: Int?
    /// An hour of the day.
    let rollover: Int?
}
