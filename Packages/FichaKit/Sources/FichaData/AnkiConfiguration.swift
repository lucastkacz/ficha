import FichaCore
import Foundation
internal import GRDB

// How an Anki collection counts its days, and which of Anki's schedulers it's
// on, read from its configuration, which a package's reader passes on to
// `AnkiCollection`. Each schema keeps the configuration its own way
// (`rslib/src/storage/config/`): schema 11 in `col.conf`, one JSON object,
// and schema 18 in the `config` table, one row for each key, whose `val` is
// the key's JSON value. Both give the same keys, `creationOffset` and
// `rollover`, which `AnkiDaySettings` checks, and `schedVer`.

/// What the configuration of an Anki collection says of its days and its
/// scheduler.
struct AnkiConfiguration {
    let daySettings: AnkiDaySettings
    /// Its `schedVer`, or 1 when it has none, as Anki takes it
    /// (`scheduler_version` in `rslib/src/config/mod.rs`).
    let schedulerVersion: Int

    /// The configuration of the collection whose `col.conf` is `conf`, schema
    /// 11's JSON object.
    init(conf: String) throws {
        let keys = try JSONDecoder().decode(ConfigurationKeys.self, from: Data(conf.utf8))
        daySettings = try AnkiDaySettings(creationOffset: keys.creationOffset, rollover: keys.rollover)
        schedulerVersion = keys.schedVer ?? 1
    }

    /// The configuration of the collection in `db`, an Anki database at
    /// schema 18, from its `config` table. Its keys are read whole and picked
    /// here, since Anki may give its text columns a collation only it has.
    init(configTableOf db: Database) throws {
        var values: [String: Data] = [:]
        for row in try Row.fetchAll(db, sql: "SELECT KEY, val FROM config") {
            values[try row.decode(forColumn: "KEY")] = try row.decode(forColumn: "val")
        }
        /// The value of `key`, an integer or null, or nil when the table hasn't
        /// the key.
        func integer(_ key: String) throws -> Int? {
            try values[key].flatMap { try JSONDecoder().decode(Int?.self, from: $0) }
        }
        daySettings = try AnkiDaySettings(creationOffset: integer("creationOffset"), rollover: integer("rollover"))
        schedulerVersion = try integer("schedVer") ?? 1
    }
}

/// The keys of an Anki collection's configuration that Ficha reads, each nil
/// when it's missing or null.
private struct ConfigurationKeys: Decodable {
    /// Minutes west of UTC.
    let creationOffset: Int?
    /// An hour of the day.
    let rollover: Int?
    /// The scheduler's version.
    let schedVer: Int?
}
