import FichaCore
import Foundation
internal import GRDB

/// The database's schema, built by versioned migrations in order. A migration
/// that has shipped never changes: every change to the schema is a new
/// migration at the end. Every migration lives here, where the merge gate
/// (`.claude/hooks/merge-gate.sh`) watches: changing this file makes a pull
/// request risk:high.
enum Schema {
    static let migrator: DatabaseMigrator = {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1 captures") { db in
            try db.create(table: "capture") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("text", .text).notNull()
                table.column("note", .text)
                table.column("source", .text)
                table.column("createdAt", .datetime).notNull()
            }
        }
        migrator.registerMigration("v2 cards") { db in
            // A capture leaves the inbox when it's refined, into cards or into
            // none, and stays in the table, so a card can say where it came from.
            try db.alter(table: "capture") { table in
                table.add(column: "refinedAt", .datetime)
            }
            try db.create(table: "card") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("type", .text).notNull()
                table.column("front", .text).notNull()
                table.column("back", .text).notNull()
                // A JSON array of strings.
                table.column("tags", .jsonText).notNull()
                table.column("source", .text)
                table.column("createdAt", .datetime).notNull()
                table.belongsTo("capture").notNull()
            }
        }
        migrator.registerMigration("v3 review log") { db in
            // One entry per first view or review, which a card's step and due
            // time are worked out from (ADR 0002). Only a review has a rating.
            try db.create(table: "reviewLog") { table in
                table.autoIncrementedPrimaryKey("id")
                table.belongsTo("card").notNull()
                // "firstView" or "review".
                table.column("kind", .text).notNull()
                // A review's rating: "again", "hard" or "good".
                table.column("rating", .text)
                table.column("answeredAt", .datetime).notNull()
                // From showing the card to the answer, in seconds.
                table.column("responseTime", .double).notNull()
                // What opened the review panel, as `Trigger` names it.
                table.column("trigger", .text).notNull()
                table.check(
                    sql: """
                        (kind = 'firstView' AND rating IS NULL)
                        OR (kind = 'review' AND rating IN ('again', 'hard', 'good'))
                        """
                )
            }
        }
        migrator.registerMigration("v4 appearance log") { db in
            // One entry per appearance, or review now that brought cards,
            // written when the review panel closes: the next appearance waits
            // from the last closing.
            try db.create(table: "appearanceLog") { table in
                table.autoIncrementedPrimaryKey("id")
                // What opened the review panel, as `Trigger` names it.
                table.column("trigger", .text).notNull()
                table.column("shownAt", .datetime).notNull()
                table.column("closedAt", .datetime).notNull()
                // How it closed: "finished", "snoozed" or "autoClosed".
                table.column("outcome", .text).notNull()
            }
        }
        migrator.registerMigration("v5 flagged and buried cards") { db in
            // A flagged card waits in the inbox, with Lucas's note on what to
            // fix, until it's fixed, and a buried card is out of his reviews
            // for good. Either way it keeps its review log, and a card that's
            // neither is in his reviews.
            try db.alter(table: "card") { table in
                table.add(column: "flagNote", .text)
                table.add(column: "flaggedAt", .datetime)
                    .check(sql: "(flagNote IS NULL) = (flaggedAt IS NULL)")
                table.add(column: "buriedAt", .datetime)
            }
        }
        migrator.registerMigration("v6 expansions") { db in
            // A capture that repeats a card's front, which Lucas chose to
            // expand: it waits in the inbox attached to that card, so that
            // refining adds it to the card.
            try db.alter(table: "capture") { table in
                table.add(column: "expandsCardId", .integer).references("card")
            }
        }
        migrator.registerMigration("v7 reviews ahead") { db in
            // Whether a review was ahead: of a card that wasn't due yet, which
            // Lucas asked for with "See more". Only its again counts (ADR
            // 0002). The reviews before it were all on time.
            try db.alter(table: "reviewLog") { table in
                table.add(column: "isAhead", .boolean).notNull().defaults(to: false)
                    .check(sql: "isAhead = 0 OR kind = 'review'")
            }
        }
        migrator.registerMigration("v8 held-back appearances") { db in
            // An appearance a suppression held back goes into the appearance
            // log once, with "heldBack" as its outcome and the suppression, as
            // `Suppression` names it. Its shownAt is when the hold started,
            // and its closedAt when it ended, or its shownAt while it's on. It
            // never showed, so the next appearance doesn't wait from it.
            try db.alter(table: "appearanceLog") { table in
                table.add(column: "heldBackBy", .text)
                    .check(sql: "(outcome = 'heldBack') = (heldBackBy IS NOT NULL)")
            }
        }
        migrator.registerMigration("v9 answers from card notifications") { db in
            // An answer from a card notification, on the iPhone, has no
            // response time: nothing measures how long Lucas looked at the
            // card. SQLite can't drop a column's NOT NULL, so the review log
            // is made again, with every entry as it was, the way GRDB's guide
            // to migrations recreates a table.
            try db.create(table: "new_reviewLog") { table in
                table.autoIncrementedPrimaryKey("id")
                // Its index comes once the table has its name.
                table.belongsTo("card", indexed: false).notNull()
                // "firstView" or "review".
                table.column("kind", .text).notNull()
                // A review's rating: "again", "hard" or "good".
                table.column("rating", .text)
                table.column("answeredAt", .datetime).notNull()
                // From showing the card to the answer, in seconds, when
                // something measured it.
                table.column("responseTime", .double)
                // What brought the card, as `Trigger` names it.
                table.column("trigger", .text).notNull()
                table.column("isAhead", .boolean).notNull().defaults(to: false)
                    .check(sql: "isAhead = 0 OR kind = 'review'")
                table.check(
                    sql: """
                        (kind = 'firstView' AND rating IS NULL)
                        OR (kind = 'review' AND rating IN ('again', 'hard', 'good'))
                        """
                )
            }
            try db.execute(
                sql: """
                    INSERT INTO new_reviewLog (id, cardId, kind, rating, answeredAt, responseTime, trigger, isAhead)
                    SELECT id, cardId, kind, rating, answeredAt, responseTime, trigger, isAhead FROM reviewLog
                    """
            )
            try db.drop(table: "reviewLog")
            try db.rename(table: "new_reviewLog", to: "reviewLog")
            try db.create(index: "reviewLog_on_cardId", on: "reviewLog", columns: ["cardId"])
        }
        migrator.registerMigration("v10 planned appearances") { db in
            // The appearances the engine last planned ahead for the iPhone,
            // which schedules them as card notifications (ADR 0010), by when
            // each comes. The next plan replaces them, once those whose time
            // came and that Lucas never touched are in the appearance log, as
            // snoozes.
            try db.create(table: "plannedAppearance") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("time", .datetime).notNull()
            }
        }
        migrator.registerMigration("v11 tags") { db in
            // What a tag has of its own (ADR 0011), one row per tag that has
            // something: a tag with nothing of its own has no row, and the
            // engine deletes a row once it has nothing left. Cards keep their
            // tags in their own JSON column, and a tag's name is the key: a
            // rename moves its row ("v27 tags inside tags").
            try db.create(table: "tag") { table in
                // Exactly as cards carry it.
                table.primaryKey("name", .text)
                // The switch the tag has on, as `TagSwitch` names it:
                // "priority" or "setAside", or NULL for neither. One column,
                // so a tag is never both.
                table.column("switchedOn", .text)
                    .check(sql: "switchedOn IN ('priority', 'setAside')")
                // One of Finder's seven tag colors, as `TagColor` names it,
                // or NULL for none.
                table.column("color", .text)
                    .check(sql: "color IN ('red', 'orange', 'yellow', 'green', 'blue', 'purple', 'gray')")
                // One emoji, or NULL for none.
                table.column("emoji", .text)
                table.check(sql: "switchedOn IS NOT NULL OR color IS NOT NULL OR emoji IS NOT NULL")
            }
        }
        migrator.registerMigration("v12 cards without a type or a capture") { db in
            // A card's type is optional, and so is its capture, since cards
            // come in by hand and from files too (ADR 0012). SQLite can't
            // drop a column's NOT NULL, so the card table is made again, with
            // every card as it was, the way GRDB's guide to migrations
            // recreates a table, as "v9 answers from card notifications" did.
            try db.create(table: "new_card") { table in
                table.autoIncrementedPrimaryKey("id")
                // As `CardType` names it, or NULL for none.
                table.column("type", .text)
                table.column("front", .text).notNull()
                table.column("back", .text).notNull()
                // A JSON array of strings.
                table.column("tags", .jsonText).notNull()
                table.column("source", .text)
                table.column("createdAt", .datetime).notNull()
                // The capture it was approved from, or NULL when it came in
                // another way. Its index comes once the table has its name.
                table.belongsTo("capture", indexed: false)
                table.column("flagNote", .text)
                table.column("flaggedAt", .datetime)
                    .check(sql: "(flagNote IS NULL) = (flaggedAt IS NULL)")
                table.column("buriedAt", .datetime)
            }
            try db.execute(
                sql: """
                    INSERT INTO new_card
                        (id, type, front, back, tags, source, createdAt, captureId, flagNote, flaggedAt, buriedAt)
                    SELECT id, type, front, back, tags, source, createdAt, captureId, flagNote, flaggedAt, buriedAt
                    FROM card
                    """
            )
            // A deleted card's id is never given again, so a refine session
            // that names an old card never reaches another one. Dropping the
            // table drops its last id too, so the new one starts from it.
            let lastID = try Int64.fetchOne(db, sql: "SELECT seq FROM sqlite_sequence WHERE name = 'card'")
            try db.drop(table: "card")
            try db.rename(table: "new_card", to: "card")
            if let lastID {
                try db.execute(sql: "DELETE FROM sqlite_sequence WHERE name = 'card'")
                try db.execute(sql: "INSERT INTO sqlite_sequence (name, seq) VALUES ('card', ?)", arguments: [lastID])
            }
            try db.create(index: "card_on_captureId", on: "card", columns: ["captureId"])
        }
        migrator.registerMigration("v13 images on cards") { db in
            // Each side of a card holds text, an image, or both, one image at
            // most, so a side with only an image has an empty text. An image
            // is a file of its own in the Images folder beside the database,
            // named by its content, as `ImageName` says, and a side refers to
            // it by that name, or is NULL for none. Many sides can refer to
            // one image.
            try db.alter(table: "card") { table in
                table.add(column: "frontImage", .text)
                table.add(column: "backImage", .text)
            }
        }
        migrator.registerMigration("v14 placements in the review log") { db in
            // An import that brings a card's progress from another app, such
            // as Anki, starts the card's log with a placement in place of a
            // first view: the step it puts the card on, and when the card is
            // due there (ADR 0013). Nothing brought a placement and no one
            // answered it, so it has no trigger and no response time. SQLite
            // can't drop the trigger's NOT NULL, so the review log is made
            // again, with every entry as it was, as "v9 answers from card
            // notifications" did.
            try db.create(table: "new_reviewLog") { table in
                table.autoIncrementedPrimaryKey("id")
                // Its index comes once the table has its name.
                table.belongsTo("card", indexed: false).notNull()
                // "firstView", "review" or "placement".
                table.column("kind", .text).notNull()
                // A review's rating: "again", "hard" or "good".
                table.column("rating", .text)
                // A placement's step, counted from 0, the first step, and
                // when the card is due on it.
                table.column("step", .integer)
                table.column("due", .datetime)
                // When the user answered, or when the import placed the card.
                table.column("answeredAt", .datetime).notNull()
                // From showing the card to the answer, in seconds, when
                // something measured it.
                table.column("responseTime", .double)
                // What brought the card, as `Trigger` names it, or NULL for a
                // placement.
                table.column("trigger", .text)
                table.column("isAhead", .boolean).notNull().defaults(to: false)
                    .check(sql: "isAhead = 0 OR kind = 'review'")
                table.check(
                    sql: """
                        (kind = 'firstView' AND rating IS NULL)
                        OR (kind = 'review' AND rating IN ('again', 'hard', 'good'))
                        OR (kind = 'placement' AND rating IS NULL)
                        """
                )
                table.check(sql: "(kind = 'placement') = (step IS NOT NULL)")
                table.check(sql: "step IS NULL OR step >= 0")
                table.check(sql: "(kind = 'placement') = (due IS NOT NULL)")
                table.check(sql: "(kind = 'placement') = (trigger IS NULL)")
                table.check(sql: "kind <> 'placement' OR responseTime IS NULL")
            }
            try db.execute(
                sql: """
                    INSERT INTO new_reviewLog (id, cardId, kind, rating, answeredAt, responseTime, trigger, isAhead)
                    SELECT id, cardId, kind, rating, answeredAt, responseTime, trigger, isAhead FROM reviewLog
                    """
            )
            try db.drop(table: "reviewLog")
            try db.rename(table: "new_reviewLog", to: "reviewLog")
            try db.create(index: "reviewLog_on_cardId", on: "reviewLog", columns: ["cardId"])
        }
        migrator.registerMigration("v15 when a card's sides last changed") { db in
            // When the card's front or back last changed, a side's image
            // included: an edit, a fix, an approved expansion or an import
            // that updated it. NULL while neither changed since the card came
            // in, as for every card from before this migration.
            try db.alter(table: "card") { table in
                table.add(column: "editedAt", .datetime)
            }
        }
        migrator.registerMigration("v16 follow-ups") { db in
            // A follow-up: a capture Lucas jots down in the review panel
            // about the card in front of him, such as a question it raised,
            // which waits in the inbox tied to that card, so that refining
            // turns it into new cards beside it. A capture expands a card,
            // follows one up, or neither, never both.
            try db.alter(table: "capture") { table in
                table.add(column: "followsUpCardId", .integer).references("card")
                    .check(sql: "followsUpCardId IS NULL OR expandsCardId IS NULL")
            }
        }
        migrator.registerMigration("v17 sounds on cards") { db in
            // Each side of a card holds text, an image, a sound, or any of
            // them together, one sound at most, so a side with only a sound
            // has an empty text and no image. A sound is a file of its own in
            // the Sounds folder beside the database, named by its content, as
            // `SoundName` says, and a side refers to it by that name, or is
            // NULL for none. Many sides can refer to one sound.
            try db.alter(table: "card") { table in
                table.add(column: "frontSound", .text)
                table.add(column: "backSound", .text)
            }
        }
        migrator.registerMigration("v18 cards that go both ways") { db in
            // Whether the user also reviews the card back first: its back,
            // and its front once they flip it (ADR 0016). Off for every card
            // until the user turns it on, so each one from before this
            // migration goes one way, as it did.
            try db.alter(table: "card") { table in
                table.add(column: "bothWays", .boolean).notNull().defaults(to: false)
            }
        }
        migrator.registerMigration("v19 the way each answer went") { db in
            // Which of the card's ways an entry went, as `Way` names it:
            // "frontFirst" or "backFirst". Each way has its own progress,
            // worked out from its own entries (ADR 0016). Every entry from
            // before this migration went front first, as every card did.
            try db.alter(table: "reviewLog") { table in
                table.add(column: "way", .text).notNull().defaults(to: "frontFirst")
                    .check(sql: "way IN ('frontFirst', 'backFirst')")
            }
        }
        migrator.registerMigration("v20 IDs unique across devices") { db in
            // Every row that syncs gets an ID unique across devices beside
            // its integer one (ADR 0017): each card, capture and entry of the
            // review log. The integer stays the local key, the id the CLI
            // prints, and iCloud names the row's record by this ID. Tags are
            // already named by their name, and images and sounds by their
            // content. A row gets its ID as it comes in, whoever writes it,
            // from the column's default: a random UUID, of version 4 and in
            // capitals, as Foundation writes one. Each row from before this
            // migration gets one too, as it's copied: SQLite can't add a
            // column with such a default to a table, so the three tables are
            // made again, with every row as it was, the way GRDB's guide to
            // migrations recreates a table, as "v12 cards without a type or a
            // capture" did. The review log, made again, also keeps from now
            // on the entry each review answered.
            let uuid = """
                (hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)), 2) || '-' \
                || substr('89AB', 1 + (random() & 3), 1) || substr(hex(randomblob(2)), 2) || '-' \
                || hex(randomblob(6)))
                """
            // A deleted row's id is never given again, so a refine session
            // that names an old card never reaches another one. Dropping a
            // table drops its last id too, so the new one starts from it.
            let lastIDs = try Row.fetchAll(
                db, sql: "SELECT name, seq FROM sqlite_sequence WHERE name IN ('card', 'capture', 'reviewLog')")
            try db.create(table: "new_card") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("uuid", .text).notNull().unique().defaults(sql: uuid)
                // As `CardType` names it, or NULL for none.
                table.column("type", .text)
                table.column("front", .text).notNull()
                table.column("back", .text).notNull()
                // A JSON array of strings.
                table.column("tags", .jsonText).notNull()
                table.column("source", .text)
                table.column("createdAt", .datetime).notNull()
                // The capture it was approved from, or NULL when it came in
                // another way. Its index comes once the table has its name.
                table.belongsTo("capture", indexed: false)
                table.column("flagNote", .text)
                table.column("flaggedAt", .datetime)
                    .check(sql: "(flagNote IS NULL) = (flaggedAt IS NULL)")
                table.column("buriedAt", .datetime)
                table.column("frontImage", .text)
                table.column("backImage", .text)
                table.column("editedAt", .datetime)
                table.column("frontSound", .text)
                table.column("backSound", .text)
                table.column("bothWays", .boolean).notNull().defaults(to: false)
            }
            try db.execute(
                sql: """
                    INSERT INTO new_card (
                        id, type, front, back, tags, source, createdAt, captureId, flagNote, flaggedAt, buriedAt,
                        frontImage, backImage, editedAt, frontSound, backSound, bothWays)
                    SELECT id, type, front, back, tags, source, createdAt, captureId, flagNote, flaggedAt, buriedAt,
                        frontImage, backImage, editedAt, frontSound, backSound, bothWays
                    FROM card
                    """
            )
            try db.drop(table: "card")
            try db.rename(table: "new_card", to: "card")
            try db.create(index: "card_on_captureId", on: "card", columns: ["captureId"])
            try db.create(table: "new_capture") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("uuid", .text).notNull().unique().defaults(sql: uuid)
                table.column("text", .text).notNull()
                table.column("note", .text)
                table.column("source", .text)
                table.column("createdAt", .datetime).notNull()
                table.column("refinedAt", .datetime)
                table.column("expandsCardId", .integer).references("card")
                table.column("followsUpCardId", .integer).references("card")
                    .check(sql: "followsUpCardId IS NULL OR expandsCardId IS NULL")
            }
            try db.execute(
                sql: """
                    INSERT INTO new_capture (id, text, note, source, createdAt, refinedAt, expandsCardId, followsUpCardId)
                    SELECT id, text, note, source, createdAt, refinedAt, expandsCardId, followsUpCardId FROM capture
                    """
            )
            try db.drop(table: "capture")
            try db.rename(table: "new_capture", to: "capture")
            try db.create(table: "new_reviewLog") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("uuid", .text).notNull().unique().defaults(sql: uuid)
                // Its index comes once the table has its name.
                table.belongsTo("card", indexed: false).notNull()
                // "firstView", "review" or "placement".
                table.column("kind", .text).notNull()
                // A review's rating: "again", "hard" or "good".
                table.column("rating", .text)
                // A placement's step, counted from 0, the first step, and
                // when the card is due on it.
                table.column("step", .integer)
                table.column("due", .datetime)
                // When the user answered, or when the import placed the card.
                table.column("answeredAt", .datetime).notNull()
                // From showing the card to the answer, in seconds, when
                // something measured it.
                table.column("responseTime", .double)
                // What brought the card, as `Trigger` names it, or NULL for a
                // placement.
                table.column("trigger", .text)
                table.column("isAhead", .boolean).notNull().defaults(to: false)
                    .check(sql: "isAhead = 0 OR kind = 'review'")
                // Which of the card's ways the entry went, as `Way` names it.
                table.column("way", .text).notNull().defaults(to: "frontFirst")
                    .check(sql: "way IN ('frontFirst', 'backFirst')")
                // For a review, the entry it answered, by its ID: the last
                // entry of its way that the device knew when the user rated
                // the card, so that a log that joins two devices' reviews
                // tells two answers to one wait from answers to two (#302).
                // NULL for a first view or a placement, which answer none,
                // and for a review from before this migration, which answered
                // the entry before it. Not a reference: the entry can come
                // from another device, after this one.
                table.column("answeredEntryUuid", .text)
                    .check(sql: "answeredEntryUuid IS NULL OR kind = 'review'")
                table.check(
                    sql: """
                        (kind = 'firstView' AND rating IS NULL)
                        OR (kind = 'review' AND rating IN ('again', 'hard', 'good'))
                        OR (kind = 'placement' AND rating IS NULL)
                        """
                )
                table.check(sql: "(kind = 'placement') = (step IS NOT NULL)")
                table.check(sql: "step IS NULL OR step >= 0")
                table.check(sql: "(kind = 'placement') = (due IS NOT NULL)")
                table.check(sql: "(kind = 'placement') = (trigger IS NULL)")
                table.check(sql: "kind <> 'placement' OR responseTime IS NULL")
            }
            try db.execute(
                sql: """
                    INSERT INTO new_reviewLog
                        (id, cardId, kind, rating, step, due, answeredAt, responseTime, trigger, isAhead, way)
                    SELECT id, cardId, kind, rating, step, due, answeredAt, responseTime, trigger, isAhead, way
                    FROM reviewLog
                    """
            )
            try db.drop(table: "reviewLog")
            try db.rename(table: "new_reviewLog", to: "reviewLog")
            try db.create(index: "reviewLog_on_cardId", on: "reviewLog", columns: ["cardId"])
            for lastID in lastIDs {
                let table: String = try lastID.decode(forColumn: "name")
                try db.execute(sql: "DELETE FROM sqlite_sequence WHERE name = ?", arguments: [table])
                try db.execute(
                    sql: "INSERT INTO sqlite_sequence (name, seq) VALUES (?, ?)",
                    arguments: [table, try lastID.decode(forColumn: "seq") as Int64])
            }
        }
        migrator.registerMigration("v21 changes recorded to sync") { db in
            // What Ficha keeps track of to sync (ADR 0017), filled by the
            // triggers below on every write, the CLI's too, since only the
            // app syncs, and it doesn't see on its own what another process
            // wrote. A row that syncs is named as iCloud names its record: a
            // card, a capture or an entry of the review log by its ID unique
            // across devices, and a tag by its name. Its type is "card",
            // "capture", "reviewLogEntry" or "tag", as `SyncedRow` names it,
            // which refuses a type it doesn't know. A migration that makes
            // one of these four tables again makes its triggers again too,
            // since dropping a table drops them.
            //
            // What this device keeps for itself, which never syncs: whether
            // sync is on, as Settings' switch says, which it is until the
            // user turns it off, and the state CKSyncEngine saved last, or
            // NULL before it saves one. One row.
            try db.create(table: "syncDevice") { table in
                table.column("id", .integer).primaryKey().check(sql: "id = 1")
                table.column("isOn", .boolean).notNull()
                table.column("engineState", .blob)
            }
            try db.execute(sql: "INSERT INTO syncDevice (id, isOn) VALUES (1, 1)")
            // The write in progress, as the triggers read it: when it
            // happens, by the engine's time, which each of the engine's
            // writes sets as it starts, and whether its changes are recorded.
            // A change from iCloud isn't, so it's never sent back: that write
            // turns recording off as it starts, and on again before it ends,
            // so it's always on between writes. Until the engine's first
            // write, there's no time, so a change before it, which nothing
            // makes, fails rather than guess one. One row.
            try db.create(table: "syncWrite") { table in
                table.column("id", .integer).primaryKey().check(sql: "id = 1")
                table.column("at", .datetime)
                table.column("recordsChanges", .boolean).notNull()
            }
            try db.execute(sql: "INSERT INTO syncWrite (id, at, recordsChanges) VALUES (1, NULL, 1)")
            // What waits to be sent to iCloud, one change per row that
            // syncs: it was saved, as when it came in or changed, or deleted.
            // Each change replaces the one before it, and gets the next id,
            // so a change sent is forgotten by its id, and one made while it
            // was being sent stays. It survives an iCloud account change,
            // which empties CKSyncEngine's own queue. While sync is off,
            // nothing waits: turning it on sends everything. Since "v24 how
            // sync stands", a deletion waits while it's off too.
            try db.create(table: "syncPending") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("recordType", .text).notNull()
                table.column("recordName", .text).notNull()
                table.column("isDeletion", .boolean).notNull()
                table.uniqueKey(["recordType", "recordName"])
            }
            // When each field of a card, a capture or a tag last changed,
            // as `SyncedField` names it, which "the latest change wins"
            // compares, also while sync is off. A field without a time
            // hasn't changed since its row came in. An entry of the review
            // log never changes. A tag's times stay once it has nothing of
            // its own and its row goes, since that's a change too.
            try db.create(table: "syncFieldTime") { table in
                table.column("recordType", .text).notNull()
                table.column("recordName", .text).notNull()
                table.column("field", .text).notNull()
                table.column("changedAt", .datetime).notNull()
                table.primaryKey(["recordType", "recordName", "field"])
            }
            // Sync starts on, so everything waits to be sent, as when the
            // user turns it on.
            try db.execute(
                sql: """
                    INSERT INTO syncPending (recordType, recordName, isDeletion)
                    SELECT 'card', uuid, 0 FROM card ORDER BY id;
                    INSERT INTO syncPending (recordType, recordName, isDeletion)
                    SELECT 'capture', uuid, 0 FROM capture ORDER BY id;
                    INSERT INTO syncPending (recordType, recordName, isDeletion)
                    SELECT 'reviewLogEntry', uuid, 0 FROM reviewLog ORDER BY id;
                    INSERT INTO syncPending (recordType, recordName, isDeletion)
                    SELECT 'tag', name, 0 FROM tag ORDER BY name;
                    """)

            // The triggers that record each change: a row that comes in,
            // changes or is deleted waits to be sent, and a field that
            // changes keeps when. A deleted row forgets when its fields
            // changed, and no longer waits as it was, even while the write
            // doesn't record its changes, as a deletion from iCloud. An
            // entry of the review log never changes: it only comes in or
            // goes. A tag is never deleted: one whose row goes, with nothing
            // of its own left, changed the fields it had. A row's fields
            // that sync, as `SyncedField` names them, each with its columns.
            let cardFields = [
                ("front", ["front"]), ("back", ["back"]), ("frontImage", ["frontImage"]),
                ("backImage", ["backImage"]), ("frontSound", ["frontSound"]), ("backSound", ["backSound"]),
                ("tags", ["tags"]), ("type", ["type"]), ("source", ["source"]), ("bothWays", ["bothWays"]),
                ("flag", ["flagNote", "flaggedAt"]), ("burial", ["buriedAt"]),
            ]
            let captureFields = [
                ("text", ["text"]), ("note", ["note"]), ("source", ["source"]), ("refined", ["refinedAt"]),
                ("expandedCard", ["expandsCardId"]), ("followedUpCard", ["followsUpCardId"]),
            ]
            let tagFields = [("switchedOn", ["switchedOn"]), ("color", ["color"]), ("emoji", ["emoji"])]
            let recording = "(SELECT recordsChanges FROM syncWrite)"
            let isOn = "(SELECT isOn FROM syncDevice)"
            /// The fields among `fields` for which `changed` holds of one of
            /// their columns, as a query of one column, `field`.
            func fields(among fields: [(String, [String])], where changed: (String) -> String) -> String {
                fields.map { field, columns in
                    "SELECT '\(field)' AS field WHERE \(columns.map(changed).joined(separator: " OR "))"
                }
                .joined(separator: " UNION ALL ")
            }
            /// Whether `changed` holds of any column of `fields`.
            func anyColumn(of fields: [(String, [String])], where changed: (String) -> String) -> String {
                fields.flatMap(\.1).map(changed).joined(separator: " OR ")
            }
            /// Records that `fields`, a query of one column, `field`, of the
            /// row of `type` named `name`, changed as the write happens.
            func stamp(_ fields: String, of type: String, named name: String) -> String {
                """
                INSERT INTO syncFieldTime (recordType, recordName, field, changedAt)
                SELECT '\(type)', \(name), field, (SELECT at FROM syncWrite) FROM (\(fields)) WHERE true
                ON CONFLICT (recordType, recordName, field) DO UPDATE SET changedAt = excluded.changedAt;
                """
            }
            /// Leaves the row of `type` named `name` waiting to be sent, saved
            /// or deleted, in place of its change before, while sync is on and,
            /// when `onlyWhileRecording` says so, while the write records its
            /// changes.
            func wait(_ type: String, named name: String, deleted: Bool, onlyWhileRecording: Bool = false) -> String {
                """
                DELETE FROM syncPending WHERE recordType = '\(type)' AND recordName = \(name);
                INSERT INTO syncPending (recordType, recordName, isDeletion)
                SELECT '\(type)', \(name), \(deleted ? 1 : 0) WHERE \(isOn)\(onlyWhileRecording ? " AND \(recording)" : "");
                """
            }
            let changed = { (column: String) in "OLD.\(column) IS NOT NEW.\(column)" }
            // A card's type is its table's name, and so is a capture's.
            for (table, tableFields) in [("card", cardFields), ("capture", captureFields)] {
                try db.execute(
                    sql: """
                        CREATE TRIGGER sync_\(table)_inserted AFTER INSERT ON \(table) WHEN \(recording) BEGIN
                        \(wait(table, named: "NEW.uuid", deleted: false))
                        END;
                        CREATE TRIGGER sync_\(table)_updated AFTER UPDATE ON \(table)
                        WHEN \(recording) AND (\(anyColumn(of: tableFields, where: changed))) BEGIN
                        \(stamp(fields(among: tableFields, where: changed), of: table, named: "NEW.uuid"))
                        \(wait(table, named: "NEW.uuid", deleted: false))
                        END;
                        CREATE TRIGGER sync_\(table)_deleted AFTER DELETE ON \(table) BEGIN
                        DELETE FROM syncFieldTime WHERE recordType = '\(table)' AND recordName = OLD.uuid;
                        \(wait(table, named: "OLD.uuid", deleted: true, onlyWhileRecording: true))
                        END;
                        """)
            }
            try db.execute(
                sql: """
                    CREATE TRIGGER sync_reviewLog_inserted AFTER INSERT ON reviewLog WHEN \(recording) BEGIN
                    \(wait("reviewLogEntry", named: "NEW.uuid", deleted: false))
                    END;
                    CREATE TRIGGER sync_reviewLog_deleted AFTER DELETE ON reviewLog BEGIN
                    \(wait("reviewLogEntry", named: "OLD.uuid", deleted: true, onlyWhileRecording: true))
                    END;
                    CREATE TRIGGER sync_tag_inserted AFTER INSERT ON tag WHEN \(recording) BEGIN
                    \(stamp(fields(among: tagFields) { "NEW.\($0) IS NOT NULL" }, of: "tag", named: "NEW.name"))
                    \(wait("tag", named: "NEW.name", deleted: false))
                    END;
                    CREATE TRIGGER sync_tag_updated AFTER UPDATE ON tag
                    WHEN \(recording) AND (\(anyColumn(of: tagFields, where: changed))) BEGIN
                    \(stamp(fields(among: tagFields, where: changed), of: "tag", named: "NEW.name"))
                    \(wait("tag", named: "NEW.name", deleted: false))
                    END;
                    CREATE TRIGGER sync_tag_deleted AFTER DELETE ON tag WHEN \(recording) BEGIN
                    \(stamp(fields(among: tagFields) { "OLD.\($0) IS NOT NULL" }, of: "tag", named: "OLD.name"))
                    \(wait("tag", named: "OLD.name", deleted: false))
                    END;
                    """)
        }
        migrator.registerMigration("v22 what this device knows of iCloud") { db in
            // What this device knows of the records iCloud holds (ADR 0017),
            // which never syncs, each record by its zone and its name, as
            // `ICloudRecordID` names it.
            //
            // What iCloud said last of each record this device heard of: its
            // system fields, as CKRecord encodes them, which a save sends
            // back so that iCloud knows which version it changes, and refuses
            // it when another device changed it since.
            try db.create(table: "syncRecord") { table in
                table.column("zone", .text).notNull()
                table.column("name", .text).notNull()
                table.column("systemFields", .blob).notNull()
                table.primaryKey(["zone", "name"])
            }
            // The records from other devices that wait to be applied, each
            // as `ICloudRecord` encodes it in JSON: one that refers to a row
            // this device doesn't hold yet, such as a card whose capture
            // hasn't come, or one this version of Ficha can't read. Each is
            // tried again whenever records come, and a later version of it
            // replaces it.
            try db.create(table: "syncIncoming") { table in
                table.column("zone", .text).notNull()
                table.column("name", .text).notNull()
                table.column("record", .blob).notNull()
                table.primaryKey(["zone", "name"])
            }
            // Whether an entry of the review log came from another device,
            // whose answer the review panel's ⌘Z never takes back. Every
            // entry from before this migration was answered on this device.
            // Adding a column keeps the table's triggers.
            try db.alter(table: "reviewLog") { table in
                table.add(column: "isFromAnotherDevice", .boolean).notNull().defaults(to: false)
            }
        }
        migrator.registerMigration("v23 the settings that decide progress") { db in
            // The three settings that decide a card's progress, which sync,
            // so they're the same on each of the user's devices (ADR 0017):
            // the ladder, the new cards a day and the forgotten-often count.
            // Until now the app kept them in its preferences, where the rest
            // of its settings stay, each device's own. One row, which isn't
            // there until the app moves in what its preferences kept, since
            // the CLI, which may run this migration, can't read them; or
            // until it comes from iCloud. Meanwhile, Ficha's defaults hold.
            // It comes in with them, and then takes its settings. The ladder
            // is each step's wait in whole seconds, from the first step up,
            // as a JSON array; the forgotten-often count is NULL when the
            // review panel never offers to flag a card.
            try db.create(table: "progressSettings") { table in
                table.column("id", .integer).primaryKey().check(sql: "id = 1")
                table.column("ladder", .text).notNull()
                table.column("newCardsPerDay", .integer).notNull()
                table.column("forgottenOftenAfter", .integer)
            }
            // The row syncs as one record named by its type, each setting a
            // field that keeps when it last changed, as `SyncedField` names
            // it, of which the latest change wins. Its trigger is a tag's,
            // in "v21 changes recorded to sync", written out: a change to a
            // setting keeps when, and leaves the row waiting to be sent. Its
            // coming in, with Ficha's defaults, is no change, and it's never
            // deleted.
            try db.execute(
                sql: """
                    CREATE TRIGGER sync_progressSettings_updated AFTER UPDATE ON progressSettings
                    WHEN (SELECT recordsChanges FROM syncWrite) AND (
                        OLD.ladder IS NOT NEW.ladder OR OLD.newCardsPerDay IS NOT NEW.newCardsPerDay
                        OR OLD.forgottenOftenAfter IS NOT NEW.forgottenOftenAfter) BEGIN
                    INSERT INTO syncFieldTime (recordType, recordName, field, changedAt)
                    SELECT 'progressSettings', 'progressSettings', field, (SELECT at FROM syncWrite) FROM (
                        SELECT 'ladder' AS field WHERE OLD.ladder IS NOT NEW.ladder
                        UNION ALL SELECT 'newCardsPerDay' AS field WHERE OLD.newCardsPerDay IS NOT NEW.newCardsPerDay
                        UNION ALL SELECT 'forgottenOftenAfter' AS field
                        WHERE OLD.forgottenOftenAfter IS NOT NEW.forgottenOftenAfter) WHERE true
                    ON CONFLICT (recordType, recordName, field) DO UPDATE SET changedAt = excluded.changedAt;
                    DELETE FROM syncPending WHERE recordType = 'progressSettings' AND recordName = 'progressSettings';
                    INSERT INTO syncPending (recordType, recordName, isDeletion)
                    SELECT 'progressSettings', 'progressSettings', 0 WHERE (SELECT isOn FROM syncDevice);
                    END;
                    """)
        }
        migrator.registerMigration("v24 how sync stands") { db in
            // How sync stands on this device, for Settings' Sync tab and the
            // menu (ADR 0017), which never syncs: why the switch is off,
            // "user" when the user turned it off and "purge" when they
            // deleted Ficha's data in iCloud's settings, or NULL while it's
            // on; whether the device is signed into iCloud, NULL until the
            // app first asks; whether iCloud was full when the device last
            // sent something; when the device last synced, NULL before it
            // first did; and how many times sync turned off, which tells the
            // app's engine that saw an off, however brief, to stop
            // (`SyncStretch`). Adding columns keeps the triggers that read
            // whether sync is on.
            try db.alter(table: "syncDevice") { table in
                table.add(column: "offBecause", .text)
                table.add(column: "hasICloudAccount", .boolean)
                table.add(column: "iCloudIsFull", .boolean).notNull().defaults(to: false)
                table.add(column: "lastSyncedAt", .datetime)
                table.add(column: "timesTurnedOff", .integer).notNull().defaults(to: 0)
            }
            try db.execute(sql: "UPDATE syncDevice SET offBecause = 'user' WHERE NOT isOn")
            // A deletion now waits to be sent while sync is off too, so that
            // turning sync on deletes from iCloud what the device deleted
            // meanwhile, instead of leaving it there for the other devices:
            // the triggers of "v21 changes recorded to sync" that record a
            // deletion, made again without asking whether sync is on. A
            // change of any other kind still waits only while it's on, since
            // turning it on sends every row as it is. A migration that makes
            // the card, capture or reviewLog table again makes these.
            for (table, type) in [("card", "card"), ("capture", "capture"), ("reviewLog", "reviewLogEntry")] {
                let forgetsFieldTimes =
                    table == "reviewLog"
                    ? "" : "DELETE FROM syncFieldTime WHERE recordType = '\(type)' AND recordName = OLD.uuid;"
                try db.execute(
                    sql: """
                        DROP TRIGGER sync_\(table)_deleted;
                        CREATE TRIGGER sync_\(table)_deleted AFTER DELETE ON \(table) BEGIN
                        \(forgetsFieldTimes)
                        DELETE FROM syncPending WHERE recordType = '\(type)' AND recordName = OLD.uuid;
                        INSERT INTO syncPending (recordType, recordName, isDeletion)
                        SELECT '\(type)', OLD.uuid, 1 WHERE (SELECT recordsChanges FROM syncWrite);
                        END;
                        """)
            }
        }
        migrator.registerMigration("v25 the cards' zone in iCloud") { db in
            // Where the device stands among the zones the cards have had in
            // iCloud, which never syncs (`CardsZoneStanding`): the cards'
            // zone it syncs in, or while it chooses one, the one it last
            // synced in, by its name among Ficha's own, such as "Cards" or
            // "Cards.1761650000000.restore", NULL when it never synced in
            // one in this account; whether it chooses one, waiting for a
            // fetch before it sends anything, as a device does before its
            // first sync; the zone it left as it turned sync on after a
            // restore, which its next engine deletes, or NULL; and the user
            // it last synced as, by their user record's name, as its engine
            // tells of an account change, which tells another account's zones
            // from this one's, or NULL until it tells of one. A device that
            // synced before this migration synced in "Cards", the only cards'
            // zone there was: it goes on there once its engine saved a state,
            // and one a purge turned off, which has none, chooses, as one
            // the purge turns off now does. "restore" joins the reasons why
            // the switch is off. Adding columns keeps the triggers that read
            // whether sync is on.
            try db.alter(table: "syncDevice") { table in
                table.add(column: "cardsZone", .text)
                table.add(column: "choosesCardsZone", .boolean).notNull().defaults(to: true)
                table.add(column: "cardsZoneLeft", .text)
                table.add(column: "iCloudUser", .text)
            }
            try db.execute(
                sql: """
                    UPDATE syncDevice SET cardsZone = 'Cards' WHERE engineState IS NOT NULL OR offBecause = 'purge';
                    UPDATE syncDevice SET choosesCardsZone = 0 WHERE engineState IS NOT NULL;
                    """)
        }
        migrator.registerMigration("v26 selective sync") { db in
            // Selective sync (ADR 0020): sync can carry only the cards with a
            // tag the user chose. Whether it does is one choice for all the
            // user's devices, which syncs: one row, which syncs as one record
            // named by its type, "syncChoice", as `SyncedRow` names it, and
            // keeps its latest change, as a tag's color does. It starts with
            // every card syncing, and its coming in is no change.
            try db.create(table: "syncChoice") { table in
                table.column("id", .integer).primaryKey().check(sql: "id = 1")
                table.column("onlyChosenTags", .boolean).notNull()
            }
            try db.execute(sql: "INSERT INTO syncChoice (id, onlyChosenTags) VALUES (1, 0)")
            // Its trigger is the settings' that decide progress, in "v23 the
            // settings that decide progress", written out.
            try db.execute(
                sql: """
                    CREATE TRIGGER sync_syncChoice_updated AFTER UPDATE ON syncChoice
                    WHEN (SELECT recordsChanges FROM syncWrite) AND OLD.onlyChosenTags IS NOT NEW.onlyChosenTags BEGIN
                    INSERT INTO syncFieldTime (recordType, recordName, field, changedAt)
                    VALUES ('syncChoice', 'syncChoice', 'onlyChosenTags', (SELECT at FROM syncWrite))
                    ON CONFLICT (recordType, recordName, field) DO UPDATE SET changedAt = excluded.changedAt;
                    DELETE FROM syncPending WHERE recordType = 'syncChoice' AND recordName = 'syncChoice';
                    INSERT INTO syncPending (recordType, recordName, isDeletion)
                    SELECT 'syncChoice', 'syncChoice', 0 WHERE (SELECT isOn FROM syncDevice);
                    END;
                    """)

            // Whether the user chose a tag to sync, a switch of its own beside
            // priority and set aside, so a tag can be both. A tag that's only
            // chosen has a row too, so the table is made again, with the
            // check that a row holds something counting it, and so are its
            // triggers, from "v21 changes recorded to sync", which dropping
            // the table drops, with the new field, `chosenToSync` as
            // `SyncedField` names it. A tag isn't chosen until the user ticks
            // it.
            try db.create(table: "newTag") { table in
                table.primaryKey("name", .text)
                table.column("switchedOn", .text)
                    .check(sql: "switchedOn IN ('priority', 'setAside')")
                table.column("color", .text)
                    .check(sql: "color IN ('red', 'orange', 'yellow', 'green', 'blue', 'purple', 'gray')")
                table.column("emoji", .text)
                table.column("chosenToSync", .boolean).notNull().defaults(to: false)
                table.check(
                    sql: "switchedOn IS NOT NULL OR color IS NOT NULL OR emoji IS NOT NULL OR chosenToSync")
            }
            try db.execute(
                sql: """
                    INSERT INTO newTag (name, switchedOn, color, emoji) SELECT name, switchedOn, color, emoji FROM tag;
                    DROP TABLE tag;
                    ALTER TABLE newTag RENAME TO tag;
                    """)
            // A field changed as a row comes in or goes when it held
            // something; as it changes, when it holds something else.
            let tagFields = [
                ("switchedOn", "IS NOT NULL"), ("color", "IS NOT NULL"), ("emoji", "IS NOT NULL"),
                ("chosenToSync", ""),
            ]
            /// The fields of the tag `row`, NEW or OLD, that hold something,
            /// as a query of one column, `field`.
            func fieldsHoldingSomething(of row: String) -> String {
                tagFields.map { field, holds in "SELECT '\(field)' AS field WHERE \(row).\(field) \(holds)" }
                    .joined(separator: " UNION ALL ")
            }
            let changedFields = tagFields.map { field, _ in
                "SELECT '\(field)' AS field WHERE OLD.\(field) IS NOT NEW.\(field)"
            }.joined(separator: " UNION ALL ")
            let anyChanged = tagFields.map { field, _ in "OLD.\(field) IS NOT NEW.\(field)" }
                .joined(separator: " OR ")
            /// Records that `fields`, a query of one column, `field`, of the
            /// tag named `name`, changed as the write happens, and leaves the
            /// tag waiting to be sent, in place of its change before, while
            /// sync is on.
            func stampAndWait(_ fields: String, named name: String) -> String {
                """
                INSERT INTO syncFieldTime (recordType, recordName, field, changedAt)
                SELECT 'tag', \(name), field, (SELECT at FROM syncWrite) FROM (\(fields)) WHERE true
                ON CONFLICT (recordType, recordName, field) DO UPDATE SET changedAt = excluded.changedAt;
                DELETE FROM syncPending WHERE recordType = 'tag' AND recordName = \(name);
                INSERT INTO syncPending (recordType, recordName, isDeletion)
                SELECT 'tag', \(name), 0 WHERE (SELECT isOn FROM syncDevice);
                """
            }
            let recording = "(SELECT recordsChanges FROM syncWrite)"
            try db.execute(
                sql: """
                    CREATE TRIGGER sync_tag_inserted AFTER INSERT ON tag WHEN \(recording) BEGIN
                    \(stampAndWait(fieldsHoldingSomething(of: "NEW"), named: "NEW.name"))
                    END;
                    CREATE TRIGGER sync_tag_updated AFTER UPDATE ON tag WHEN \(recording) AND (\(anyChanged)) BEGIN
                    \(stampAndWait(changedFields, named: "NEW.name"))
                    END;
                    CREATE TRIGGER sync_tag_deleted AFTER DELETE ON tag WHEN \(recording) BEGIN
                    \(stampAndWait(fieldsHoldingSomething(of: "OLD"), named: "OLD.name"))
                    END;
                    """)

            // Whether iCloud holds a record only as one that left: a card, an
            // entry of the review log or a capture that stopped syncing, whose
            // record keeps its ID and says it left, with nothing of its own
            // but, for a card, its tags, so that the other devices tell it
            // from one deleted. Adding a column keeps the table as it is.
            try db.alter(table: "syncRecord") { table in
                table.add(column: "hasLeft", .boolean).notNull().defaults(to: false)
            }

            // A deletion waits to be sent only when its row synced as it was
            // deleted: a card deleted while it doesn't sync is deleted on this
            // device alone. A card syncs when every card does, or one of its
            // tags is chosen; an entry of the review log with its card; and a
            // capture unless it expands or follows up a card that doesn't.
            // The triggers of "v24 how sync stands" that record a deletion,
            // made again. A card's deletion deletes its entries first, so
            // theirs still find it.
            /// Whether the card whose tags are the JSON array `tags` syncs.
            func cardSyncs(tags: String) -> String {
                """
                (NOT (SELECT onlyChosenTags FROM syncChoice) OR EXISTS (
                    SELECT 1 FROM json_each(\(tags)) AS cardTag JOIN tag ON tag.name = cardTag.value
                    WHERE tag.chosenToSync))
                """
            }
            let synced = [
                ("card", "card", cardSyncs(tags: "OLD.tags")),
                (
                    "reviewLog", "reviewLogEntry",
                    "EXISTS (SELECT 1 FROM card WHERE card.id = OLD.cardId AND \(cardSyncs(tags: "card.tags")))"
                ),
                (
                    "capture", "capture",
                    """
                    NOT EXISTS (
                        SELECT 1 FROM card WHERE card.id IN (OLD.expandsCardId, OLD.followsUpCardId)
                        AND NOT \(cardSyncs(tags: "card.tags")))
                    """
                ),
            ]
            for (table, type, rowSynced) in synced {
                let forgetsFieldTimes =
                    table == "reviewLog"
                    ? "" : "DELETE FROM syncFieldTime WHERE recordType = '\(type)' AND recordName = OLD.uuid;"
                try db.execute(
                    sql: """
                        DROP TRIGGER sync_\(table)_deleted;
                        CREATE TRIGGER sync_\(table)_deleted AFTER DELETE ON \(table) BEGIN
                        \(forgetsFieldTimes)
                        DELETE FROM syncPending WHERE recordType = '\(type)' AND recordName = OLD.uuid;
                        INSERT INTO syncPending (recordType, recordName, isDeletion)
                        SELECT '\(type)', OLD.uuid, 1 WHERE (SELECT recordsChanges FROM syncWrite) AND \(rowSynced);
                        END;
                        """)
            }

            // A device that holds cards and never synced starts with the
            // switch off, "firstSync" among the reasons why, so that the user
            // chooses what syncs before anything goes up, as Lucas does on
            // his Mac, whose database "v21 changes recorded to sync" left
            // with the switch on. Nothing waits to be sent then but the
            // deletions, as when the user turns it off. A database that
            // migrates with no cards, as a new install's, starts on, whatever
            // cards it gets after.
            try db.execute(
                sql: """
                    UPDATE syncDevice SET isOn = 0, offBecause = 'firstSync', timesTurnedOff = timesTurnedOff + 1
                    WHERE isOn AND engineState IS NULL AND lastSyncedAt IS NULL AND cardsZone IS NULL
                        AND EXISTS (SELECT 1 FROM card);
                    DELETE FROM syncPending WHERE NOT isDeletion AND NOT (SELECT isOn FROM syncDevice);
                    """)
        }
        migrator.registerMigration("v27 tags inside tags") { db in
            // A tag can sit inside another (ADR 0021): its name carries the
            // tags it sits inside, `economía::Argentina`, as cards carry it,
            // so the `tag` table keeps a row by that whole name. A tag can be
            // renamed now, which moves it and the tags inside it: the engine
            // deletes their rows and writes them again under their new names,
            // which sync as a tag's rows do, and changes every card that
            // carries them. Its name is still the key.
            //
            // A card syncs when every card does, or one of its tags, or a tag
            // one of them sits inside, is chosen. The deletion triggers of
            // "v26 selective sync", made again with that rule: a tag sits
            // inside a chosen one when its name starts with the chosen one's
            // and `::`, compared character by character, as selective sync's
            // own SQL in `SelectiveSync.swift` did until decks took the
            // choice ("v31 decks").
            /// Whether the card whose tags are the JSON array `tags` syncs.
            func cardSyncs(tags: String) -> String {
                """
                (NOT (SELECT onlyChosenTags FROM syncChoice) OR EXISTS (
                    SELECT 1 FROM json_each(\(tags)) AS cardTag JOIN tag ON tag.chosenToSync AND (
                        tag.name = cardTag.value OR substr(cardTag.value, 1, length(tag.name) + 2) = tag.name || '::')))
                """
            }
            let synced = [
                ("card", "card", cardSyncs(tags: "OLD.tags")),
                (
                    "reviewLog", "reviewLogEntry",
                    "EXISTS (SELECT 1 FROM card WHERE card.id = OLD.cardId AND \(cardSyncs(tags: "card.tags")))"
                ),
                (
                    "capture", "capture",
                    """
                    NOT EXISTS (
                        SELECT 1 FROM card WHERE card.id IN (OLD.expandsCardId, OLD.followsUpCardId)
                        AND NOT \(cardSyncs(tags: "card.tags")))
                    """
                ),
            ]
            for (table, type, rowSynced) in synced {
                let forgetsFieldTimes =
                    table == "reviewLog"
                    ? "" : "DELETE FROM syncFieldTime WHERE recordType = '\(type)' AND recordName = OLD.uuid;"
                try db.execute(
                    sql: """
                        DROP TRIGGER sync_\(table)_deleted;
                        CREATE TRIGGER sync_\(table)_deleted AFTER DELETE ON \(table) BEGIN
                        \(forgetsFieldTimes)
                        DELETE FROM syncPending WHERE recordType = '\(type)' AND recordName = OLD.uuid;
                        INSERT INTO syncPending (recordType, recordName, isDeletion)
                        SELECT '\(type)', OLD.uuid, 1 WHERE (SELECT recordsChanges FROM syncWrite) AND \(rowSynced);
                        END;
                        """)
            }
        }
        migrator.registerMigration("v28 card types of the user's own") { db in
            // The card types the user makes, beside the four Ficha comes
            // with (`UserType`): each with its ID unique across devices, as
            // Foundation writes a UUID, which the engine gives it as it makes
            // it, so that renaming it changes no card; its name, which the
            // engine keeps unique, ignoring case and accents, as a type made
            // offline on two devices may not be; and its emoji, or NULL for
            // none. A card's type column, "type", keeps a type Ficha comes
            // with by its raw value, as before, and a user type by its ID,
            // which no raw value is, so every card keeps its type, and the
            // card table, with its triggers, stays as it was. A card whose
            // column names a user type this device doesn't hold, one that
            // hasn't come from another device yet, or one deleted, has no
            // type.
            try db.create(table: "userType") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("uuid", .text).notNull().unique()
                table.column("name", .text).notNull().check(sql: "trim(name) <> ''")
                table.column("emoji", .text)
            }
            // A user type syncs as a record of its own, "userType", as
            // `SyncedRow` names it, whatever selective sync chooses, since it
            // isn't a card (ADR 0020), each of its fields, "name" and "emoji"
            // as `SyncedField` names them, keeping its latest change. Its
            // triggers are a capture's written out: those of "v21 changes
            // recorded to sync" as it comes in and changes, and that of "v24
            // how sync stands" as it's deleted, which waits to be sent whether
            // sync is on or not.
            let changed = """
                SELECT 'name' AS field WHERE OLD.name IS NOT NEW.name
                UNION ALL SELECT 'emoji' AS field WHERE OLD.emoji IS NOT NEW.emoji
                """
            let recording = "(SELECT recordsChanges FROM syncWrite)"
            let isOn = "(SELECT isOn FROM syncDevice)"
            try db.execute(
                sql: """
                    CREATE TRIGGER sync_userType_inserted AFTER INSERT ON userType WHEN \(recording) BEGIN
                    DELETE FROM syncPending WHERE recordType = 'userType' AND recordName = NEW.uuid;
                    INSERT INTO syncPending (recordType, recordName, isDeletion)
                    SELECT 'userType', NEW.uuid, 0 WHERE \(isOn);
                    END;
                    CREATE TRIGGER sync_userType_updated AFTER UPDATE ON userType
                    WHEN \(recording) AND (OLD.name IS NOT NEW.name OR OLD.emoji IS NOT NEW.emoji) BEGIN
                    INSERT INTO syncFieldTime (recordType, recordName, field, changedAt)
                    SELECT 'userType', NEW.uuid, field, (SELECT at FROM syncWrite) FROM (\(changed)) WHERE true
                    ON CONFLICT (recordType, recordName, field) DO UPDATE SET changedAt = excluded.changedAt;
                    DELETE FROM syncPending WHERE recordType = 'userType' AND recordName = NEW.uuid;
                    INSERT INTO syncPending (recordType, recordName, isDeletion)
                    SELECT 'userType', NEW.uuid, 0 WHERE \(isOn);
                    END;
                    CREATE TRIGGER sync_userType_deleted AFTER DELETE ON userType BEGIN
                    DELETE FROM syncFieldTime WHERE recordType = 'userType' AND recordName = OLD.uuid;
                    DELETE FROM syncPending WHERE recordType = 'userType' AND recordName = OLD.uuid;
                    INSERT INTO syncPending (recordType, recordName, isDeletion)
                    SELECT 'userType', OLD.uuid, 1 WHERE \(recording);
                    END;
                    """)
        }
        migrator.registerMigration("v29 pinned tags") { db in
            // A tag can be pinned to the Cards window's sidebar (ADR 0022):
            // its pin is its place among the pinned tags, as `PinPosition`
            // writes its key, digits of base 62 that never end in 0, which
            // the check below holds to, or NULL while it isn't pinned. Nothing
            // is pinned until the user pins it. A tag that's only pinned has a
            // row too, so the table is made again, as "v26 selective sync"
            // made it, with the check that a row holds something counting the
            // pin, and so are its triggers, which dropping the table drops,
            // with the new field, `pin` as `SyncedField` names it, which
            // syncs as the tag's other fields do. The triggers of "v27 tags
            // inside tags" that record a card's deletion read the table by
            // its name, so they read the new one.
            try db.create(table: "newTag") { table in
                table.primaryKey("name", .text)
                table.column("switchedOn", .text)
                    .check(sql: "switchedOn IN ('priority', 'setAside')")
                table.column("color", .text)
                    .check(sql: "color IN ('red', 'orange', 'yellow', 'green', 'blue', 'purple', 'gray')")
                table.column("emoji", .text)
                table.column("chosenToSync", .boolean).notNull().defaults(to: false)
                table.column("pin", .text)
                    .check(sql: "pin <> '' AND pin NOT GLOB '*[^0-9A-Za-z]*' AND pin NOT GLOB '*0'")
                table.check(
                    sql: """
                        switchedOn IS NOT NULL OR color IS NOT NULL OR emoji IS NOT NULL OR chosenToSync \
                        OR pin IS NOT NULL
                        """)
            }
            try db.execute(
                sql: """
                    INSERT INTO newTag (name, switchedOn, color, emoji, chosenToSync)
                    SELECT name, switchedOn, color, emoji, chosenToSync FROM tag;
                    DROP TABLE tag;
                    ALTER TABLE newTag RENAME TO tag;
                    """)
            // The triggers of "v26 selective sync", written out with the
            // pin: a field changed as a row comes in or goes when it held
            // something; as it changes, when it holds something else.
            let tagFields = [
                ("switchedOn", "IS NOT NULL"), ("color", "IS NOT NULL"), ("emoji", "IS NOT NULL"),
                ("chosenToSync", ""), ("pin", "IS NOT NULL"),
            ]
            /// The fields of the tag `row`, NEW or OLD, that hold something,
            /// as a query of one column, `field`.
            func fieldsHoldingSomething(of row: String) -> String {
                tagFields.map { field, holds in "SELECT '\(field)' AS field WHERE \(row).\(field) \(holds)" }
                    .joined(separator: " UNION ALL ")
            }
            let changedFields = tagFields.map { field, _ in
                "SELECT '\(field)' AS field WHERE OLD.\(field) IS NOT NEW.\(field)"
            }.joined(separator: " UNION ALL ")
            let anyChanged = tagFields.map { field, _ in "OLD.\(field) IS NOT NEW.\(field)" }
                .joined(separator: " OR ")
            /// Records that `fields`, a query of one column, `field`, of the
            /// tag named `name`, changed as the write happens, and leaves the
            /// tag waiting to be sent, in place of its change before, while
            /// sync is on.
            func stampAndWait(_ fields: String, named name: String) -> String {
                """
                INSERT INTO syncFieldTime (recordType, recordName, field, changedAt)
                SELECT 'tag', \(name), field, (SELECT at FROM syncWrite) FROM (\(fields)) WHERE true
                ON CONFLICT (recordType, recordName, field) DO UPDATE SET changedAt = excluded.changedAt;
                DELETE FROM syncPending WHERE recordType = 'tag' AND recordName = \(name);
                INSERT INTO syncPending (recordType, recordName, isDeletion)
                SELECT 'tag', \(name), 0 WHERE (SELECT isOn FROM syncDevice);
                """
            }
            let recording = "(SELECT recordsChanges FROM syncWrite)"
            try db.execute(
                sql: """
                    CREATE TRIGGER sync_tag_inserted AFTER INSERT ON tag WHEN \(recording) BEGIN
                    \(stampAndWait(fieldsHoldingSomething(of: "NEW"), named: "NEW.name"))
                    END;
                    CREATE TRIGGER sync_tag_updated AFTER UPDATE ON tag WHEN \(recording) AND (\(anyChanged)) BEGIN
                    \(stampAndWait(changedFields, named: "NEW.name"))
                    END;
                    CREATE TRIGGER sync_tag_deleted AFTER DELETE ON tag WHEN \(recording) BEGIN
                    \(stampAndWait(fieldsHoldingSomething(of: "OLD"), named: "OLD.name"))
                    END;
                    """)
        }
        migrator.registerMigration("v30 changes to tags") { db in
            // A rename or a deletion of a tag, recorded as a change to the
            // tag (ADR 0022), so that it reaches every card on every device,
            // those that don't sync included (`TagChanges.swift`): each with
            // its ID unique across devices, as Foundation writes a UUID; the
            // tag it changes, by its whole name; the name it's renamed to,
            // or NULL for a deletion; when it was made, by the engine's time
            // on the device that made it; and the change it follows, made
            // right before it in the same write, or NULL for the first or
            // only one, so that every device applies a write's changes in
            // their order, whatever order it hears of them in. A device
            // keeps a row for each change it made or heard of, which it has
            // applied, and never changes one, so a change whose row it holds
            // is never applied again. A device that takes a restore's cards
            // drops them, with every row that syncs, and keeps their IDs in
            // `tagChangeAppliedBeforeARestore`, so that it never applies again
            // one the restore's copy brings back. Every database starts with
            // none of either.
            try db.create(table: "tagChange") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("uuid", .text).notNull().unique()
                table.column("tag", .text).notNull().check(sql: "tag <> ''")
                table.column("newName", .text).check(sql: "newName <> ''")
                table.column("madeAt", .datetime).notNull()
                table.column("followsId", .integer).references("tagChange")
            }
            try db.create(table: "tagChangeAppliedBeforeARestore") { table in
                table.primaryKey("uuid", .text)
            }
            // A change syncs as a record of its own, "tagChange", as
            // `SyncedRow` names it, whatever selective sync chooses, as a
            // tag's row does (ADR 0020). It only ever comes in: its trigger
            // is an entry of the review log's, from "v21 changes recorded to
            // sync", written out.
            try db.execute(
                sql: """
                    CREATE TRIGGER sync_tagChange_inserted AFTER INSERT ON tagChange
                    WHEN (SELECT recordsChanges FROM syncWrite) BEGIN
                    DELETE FROM syncPending WHERE recordType = 'tagChange' AND recordName = NEW.uuid;
                    INSERT INTO syncPending (recordType, recordName, isDeletion)
                    SELECT 'tagChange', NEW.uuid, 0 WHERE (SELECT isOn FROM syncDevice);
                    END;
                    """)
        }
        migrator.registerMigration("v31 decks") { db in
            // Each card lives in exactly one deck (ADR 0024), which it names
            // by its whole name, its levels joined by `::`, as it names its
            // tags (ADR 0021), or by Default's, '', which no name the user
            // types is, since a blank one is refused. A parent exists through
            // the decks inside it. Every card from before this migration is
            // in Default, with its tags as they were, and nothing waits to be
            // sent for it: adding a column keeps the table, with its triggers.
            try db.alter(table: "card") { table in
                table.add(column: "deck", .text).notNull().defaults(to: "")
            }
            // A deck has a row of its own while it exists, by its whole name,
            // or Default's, compared character by character, as a tag's: the
            // switch it has on, "priority" or "setAside", or NULL for neither;
            // one of Finder's seven tag colors, or NULL for none; one emoji,
            // or NULL for none; whether the user chose it to sync, which it
            // isn't until they tick it; and whether the user made it on this
            // device, which never syncs: making a deck, or putting cards in
            // it, says so, on a row that was there too, and a row a switch,
            // a color, an emoji or a choice to sync gives a deck, or one
            // another device's record gives it, doesn't (`Decks.swift`), so
            // that under selective sync a device lists the decks made on it,
            // beside those that sync and those it holds cards of. A device
            // that takes a restore's cards drops every deck's row, with every
            // row that syncs, and keeps the names of those made on it in
            // `deckMadeHereBeforeARestore`, until the restore's copy brings
            // them again. Unlike a tag's, a deck's row needn't hold anything,
            // so a deck the user makes stays while it has no cards. The `tag`
            // table keeps its switches and its choice to sync as they were,
            // for Lucas's tags to carry over to decks.
            try db.create(table: "deck") { table in
                table.primaryKey("name", .text)
                table.column("switchedOn", .text)
                    .check(sql: "switchedOn IN ('priority', 'setAside')")
                table.column("color", .text)
                    .check(sql: "color IN ('red', 'orange', 'yellow', 'green', 'blue', 'purple', 'gray')")
                table.column("emoji", .text)
                table.column("chosenToSync", .boolean).notNull().defaults(to: false)
                table.column("madeHere", .boolean).notNull().defaults(to: false)
            }
            try db.create(table: "deckMadeHereBeforeARestore") { table in
                table.primaryKey("name", .text)
            }
            // A card's deck is one of its fields, `deck` as `SyncedField`
            // names it, of which the latest change wins: the trigger of "v21
            // changes recorded to sync" that records a change to a card, made
            // again with it.
            let cardFields = [
                ("front", ["front"]), ("back", ["back"]), ("frontImage", ["frontImage"]),
                ("backImage", ["backImage"]), ("frontSound", ["frontSound"]), ("backSound", ["backSound"]),
                ("tags", ["tags"]), ("type", ["type"]), ("source", ["source"]), ("bothWays", ["bothWays"]),
                ("flag", ["flagNote", "flaggedAt"]), ("burial", ["buriedAt"]), ("deck", ["deck"]),
            ]
            let changedCardFields = cardFields.map { field, columns in
                "SELECT '\(field)' AS field WHERE \(columns.map { "OLD.\($0) IS NOT NEW.\($0)" }.joined(separator: " OR "))"
            }.joined(separator: " UNION ALL ")
            let anyCardColumnChanged = cardFields.flatMap(\.1).map { "OLD.\($0) IS NOT NEW.\($0)" }
                .joined(separator: " OR ")
            let recording = "(SELECT recordsChanges FROM syncWrite)"
            let isOn = "(SELECT isOn FROM syncDevice)"
            try db.execute(
                sql: """
                    DROP TRIGGER sync_card_updated;
                    CREATE TRIGGER sync_card_updated AFTER UPDATE ON card
                    WHEN \(recording) AND (\(anyCardColumnChanged)) BEGIN
                    INSERT INTO syncFieldTime (recordType, recordName, field, changedAt)
                    SELECT 'card', NEW.uuid, field, (SELECT at FROM syncWrite) FROM (\(changedCardFields)) WHERE true
                    ON CONFLICT (recordType, recordName, field) DO UPDATE SET changedAt = excluded.changedAt;
                    DELETE FROM syncPending WHERE recordType = 'card' AND recordName = NEW.uuid;
                    INSERT INTO syncPending (recordType, recordName, isDeletion)
                    SELECT 'card', NEW.uuid, 0 WHERE \(isOn);
                    END;
                    """)
            // A deck syncs as a record of its own, "deck", as `SyncedRow`
            // names it, named by its name, whatever selective sync chooses, as
            // a tag's row does (ADR 0020), each of its fields, `switchedOn`,
            // `color`, `emoji` and `chosenToSync` as `SyncedField` names them,
            // keeping its latest change. Its triggers are a tag's, from "v29
            // pinned tags", as it comes in and changes, a field changed as the
            // row comes in when it holds something, and a user type's, from
            // "v28 card types of the user's own", as it's deleted: its record
            // goes, which waits to be sent whether sync is on or not.
            let deckFields = [
                ("switchedOn", "IS NOT NULL"), ("color", "IS NOT NULL"), ("emoji", "IS NOT NULL"), ("chosenToSync", ""),
            ]
            let deckFieldsHoldingSomething = deckFields.map { field, holds in
                "SELECT '\(field)' AS field WHERE NEW.\(field) \(holds)"
            }.joined(separator: " UNION ALL ")
            let changedDeckFields = deckFields.map { field, _ in
                "SELECT '\(field)' AS field WHERE OLD.\(field) IS NOT NEW.\(field)"
            }.joined(separator: " UNION ALL ")
            let anyDeckFieldChanged = deckFields.map { field, _ in "OLD.\(field) IS NOT NEW.\(field)" }
                .joined(separator: " OR ")
            /// Records that `fields`, a query of one column, `field`, of the
            /// deck `NEW`, changed as the write happens, and leaves the deck
            /// waiting to be sent, in place of its change before, while sync
            /// is on.
            func stampAndWait(_ fields: String) -> String {
                """
                INSERT INTO syncFieldTime (recordType, recordName, field, changedAt)
                SELECT 'deck', NEW.name, field, (SELECT at FROM syncWrite) FROM (\(fields)) WHERE true
                ON CONFLICT (recordType, recordName, field) DO UPDATE SET changedAt = excluded.changedAt;
                DELETE FROM syncPending WHERE recordType = 'deck' AND recordName = NEW.name;
                INSERT INTO syncPending (recordType, recordName, isDeletion)
                SELECT 'deck', NEW.name, 0 WHERE \(isOn);
                """
            }
            try db.execute(
                sql: """
                    CREATE TRIGGER sync_deck_inserted AFTER INSERT ON deck WHEN \(recording) BEGIN
                    \(stampAndWait(deckFieldsHoldingSomething))
                    END;
                    CREATE TRIGGER sync_deck_updated AFTER UPDATE ON deck WHEN \(recording) AND (\(anyDeckFieldChanged))
                    BEGIN
                    \(stampAndWait(changedDeckFields))
                    END;
                    CREATE TRIGGER sync_deck_deleted AFTER DELETE ON deck BEGIN
                    DELETE FROM syncFieldTime WHERE recordType = 'deck' AND recordName = OLD.name;
                    DELETE FROM syncPending WHERE recordType = 'deck' AND recordName = OLD.name;
                    INSERT INTO syncPending (recordType, recordName, isDeletion)
                    SELECT 'deck', OLD.name, 1 WHERE \(recording);
                    END;
                    """)
            // A rename or a deletion of a deck, recorded as a change to the
            // deck, as a tag's is in "v30 changes to tags", so that it
            // reaches every card on every device, those that don't sync
            // included (`DeckChanges.swift`): its ID unique across devices;
            // the deck it changes, by its whole name, never Default, which is
            // neither renamed nor deleted; the name it's renamed to, or NULL
            // for a deletion; when it was made; and, for a deletion, the IDs
            // of the cards the device that made it deleted, 16 bytes each,
            // which every device deletes, or NULL for none. A write makes one
            // change to decks at most, so none follows another in its write. A
            // device keeps a row for each change it made or heard of, which
            // it has applied, and keeps the IDs of those it dropped as it
            // took a restore's cards in `deckChangeAppliedBeforeARestore`.
            // Every database starts with none of either. A change syncs as a
            // record of its own, "deckChange", whatever selective sync
            // chooses, and only ever comes in, as a change to a tag does.
            try db.create(table: "deckChange") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("uuid", .text).notNull().unique()
                table.column("deck", .text).notNull().check(sql: "deck <> ''")
                table.column("newName", .text).check(sql: "newName <> ''")
                table.column("madeAt", .datetime).notNull()
                table.column("deletedCards", .blob).check(
                    sql: "deletedCards IS NULL OR (newName IS NULL AND length(deletedCards) % 16 = 0)")
            }
            try db.create(table: "deckChangeAppliedBeforeARestore") { table in
                table.primaryKey("uuid", .text)
            }
            try db.execute(
                sql: """
                    CREATE TRIGGER sync_deckChange_inserted AFTER INSERT ON deckChange WHEN \(recording) BEGIN
                    DELETE FROM syncPending WHERE recordType = 'deckChange' AND recordName = NEW.uuid;
                    INSERT INTO syncPending (recordType, recordName, isDeletion)
                    SELECT 'deckChange', NEW.uuid, 0 WHERE \(isOn);
                    END;
                    """)

            // Selective sync chooses decks (ADR 0024): a card syncs when every
            // card does, or its deck, or a deck its deck sits inside, is
            // chosen, Default included, which no deck sits inside. Whether
            // only chosen ones sync stays in `syncChoice.onlyChosenTags`, as
            // it was, and the tags' choices decide nothing. The deletion
            // triggers of "v27 tags inside tags", made again with that rule:
            // a deck sits inside a chosen one when its name starts with the
            // chosen one's and `::`, compared character by character, as
            // `cardSyncs(deck:)` in `SelectiveSync.swift` does.
            /// Whether the card whose deck is `deck` syncs.
            func cardSyncs(deck: String) -> String {
                """
                (NOT (SELECT onlyChosenTags FROM syncChoice) OR EXISTS (
                    SELECT 1 FROM deck AS chosen WHERE chosen.chosenToSync AND (chosen.name = \(deck)
                        OR (chosen.name <> '' AND substr(\(deck), 1, length(chosen.name) + 2) = chosen.name || '::'))))
                """
            }
            let synced = [
                ("card", "card", cardSyncs(deck: "OLD.deck")),
                (
                    "reviewLog", "reviewLogEntry",
                    "EXISTS (SELECT 1 FROM card WHERE card.id = OLD.cardId AND \(cardSyncs(deck: "card.deck")))"
                ),
                (
                    "capture", "capture",
                    """
                    NOT EXISTS (
                        SELECT 1 FROM card WHERE card.id IN (OLD.expandsCardId, OLD.followsUpCardId)
                        AND NOT \(cardSyncs(deck: "card.deck")))
                    """
                ),
            ]
            for (table, type, rowSynced) in synced {
                let forgetsFieldTimes =
                    table == "reviewLog"
                    ? "" : "DELETE FROM syncFieldTime WHERE recordType = '\(type)' AND recordName = OLD.uuid;"
                try db.execute(
                    sql: """
                        DROP TRIGGER sync_\(table)_deleted;
                        CREATE TRIGGER sync_\(table)_deleted AFTER DELETE ON \(table) BEGIN
                        \(forgetsFieldTimes)
                        DELETE FROM syncPending WHERE recordType = '\(type)' AND recordName = OLD.uuid;
                        INSERT INTO syncPending (recordType, recordName, isDeletion)
                        SELECT '\(type)', OLD.uuid, 1 WHERE \(recording) AND \(rowSynced);
                        END;
                        """)
            }
        }
        migrator.registerMigration("v32 the scheduler's settings and each review's interval") { db in
            // The settings FSRS spaces cards with, as Anki does (#404),
            // which decide a card's progress beside the ladder and sync as
            // the others do: the learning steps and the relearning steps,
            // each step's interval in whole seconds, from the first, as a
            // JSON array, as the ladder is, or an empty one for none; the
            // desired retention, a fraction from 0.70 to 0.99; the longest
            // interval, in days; and FSRS's parameters, a JSON array of the
            // 21 numbers in fsrs-rs's order, each the exact value of its
            // 32-bit float, or an empty one for FSRS-6's defaults. Each
            // column comes in with Ficha's default, which a row already
            // there takes too, as no change: adding columns keeps the table.
            try db.alter(table: "progressSettings") { table in
                table.add(column: "learningSteps", .text).notNull().defaults(to: "[3600,14400]")
                table.add(column: "relearningSteps", .text).notNull().defaults(to: "[3600]")
                table.add(column: "desiredRetention", .double).notNull().defaults(to: 0.9)
                table.add(column: "longestIntervalInDays", .integer).notNull().defaults(to: 36_500)
                table.add(column: "fsrsParameters", .text).notNull().defaults(to: "[]")
            }
            // Each is a field of the settings' record, as `SyncedField`
            // names it, of which the latest change wins: the trigger of "v23
            // the settings that decide progress", made again with them.
            let settingsFields = [
                "ladder", "newCardsPerDay", "forgottenOftenAfter", "learningSteps", "relearningSteps",
                "desiredRetention", "longestIntervalInDays", "fsrsParameters",
            ]
            let changedSettingsFields = settingsFields.map {
                "SELECT '\($0)' AS field WHERE OLD.\($0) IS NOT NEW.\($0)"
            }
            .joined(separator: " UNION ALL ")
            let anySettingChanged = settingsFields.map { "OLD.\($0) IS NOT NEW.\($0)" }.joined(separator: " OR ")
            try db.execute(
                sql: """
                    DROP TRIGGER sync_progressSettings_updated;
                    CREATE TRIGGER sync_progressSettings_updated AFTER UPDATE ON progressSettings
                    WHEN (SELECT recordsChanges FROM syncWrite) AND (\(anySettingChanged)) BEGIN
                    INSERT INTO syncFieldTime (recordType, recordName, field, changedAt)
                    SELECT 'progressSettings', 'progressSettings', field, (SELECT at FROM syncWrite)
                    FROM (\(changedSettingsFields)) WHERE true
                    ON CONFLICT (recordType, recordName, field) DO UPDATE SET changedAt = excluded.changedAt;
                    DELETE FROM syncPending WHERE recordType = 'progressSettings' AND recordName = 'progressSettings';
                    INSERT INTO syncPending (recordType, recordName, isDeletion)
                    SELECT 'progressSettings', 'progressSettings', 0 WHERE (SELECT isOn FROM syncDevice);
                    END;
                    """)

            // Each review keeps the interval it set (#404), in seconds, as
            // Anki's history keeps it, which syncs with it: the way waits it
            // from when the user answered. A first view and a placement keep
            // none, and neither does a review from before this migration. A
            // review's rating can be easy, Anki's fourth. A column can't join
            // the table's checks, so the table is made again, as "v20 IDs
            // unique across devices" made it, with every row as it was, and
            // its last id, which no entry gets again; and so are its index
            // and its triggers, which dropping it drops: that of "v21 changes
            // recorded to sync" as an entry comes in, and that of "v31 decks"
            // as one is deleted. Its rows' IDs keep their default, a random
            // UUID, as "v20 IDs unique across devices" writes it.
            let uuid = """
                (hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)), 2) || '-' \
                || substr('89AB', 1 + (random() & 3), 1) || substr(hex(randomblob(2)), 2) || '-' \
                || hex(randomblob(6)))
                """
            let lastID = try Int64.fetchOne(db, sql: "SELECT seq FROM sqlite_sequence WHERE name = 'reviewLog'")
            try db.create(table: "new_reviewLog") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("uuid", .text).notNull().unique().defaults(sql: uuid)
                // Its index comes once the table has its name.
                table.belongsTo("card", indexed: false).notNull()
                table.column("kind", .text).notNull()
                table.column("rating", .text)
                table.column("step", .integer)
                table.column("due", .datetime)
                table.column("answeredAt", .datetime).notNull()
                table.column("responseTime", .double)
                table.column("trigger", .text)
                table.column("isAhead", .boolean).notNull().defaults(to: false)
                    .check(sql: "isAhead = 0 OR kind = 'review'")
                table.column("way", .text).notNull().defaults(to: "frontFirst")
                    .check(sql: "way IN ('frontFirst', 'backFirst')")
                table.column("answeredEntryUuid", .text)
                    .check(sql: "answeredEntryUuid IS NULL OR kind = 'review'")
                table.column("isFromAnotherDevice", .boolean).notNull().defaults(to: false)
                table.column("interval", .double)
                    .check(sql: "interval IS NULL OR (kind = 'review' AND interval > 0)")
                table.check(
                    sql: """
                        (kind = 'firstView' AND rating IS NULL)
                        OR (kind = 'review' AND rating IN ('again', 'hard', 'good', 'easy'))
                        OR (kind = 'placement' AND rating IS NULL)
                        """
                )
                table.check(sql: "(kind = 'placement') = (step IS NOT NULL)")
                table.check(sql: "step IS NULL OR step >= 0")
                table.check(sql: "(kind = 'placement') = (due IS NOT NULL)")
                table.check(sql: "(kind = 'placement') = (trigger IS NULL)")
                table.check(sql: "kind <> 'placement' OR responseTime IS NULL")
            }
            let copied =
                "id, uuid, cardId, kind, rating, step, due, answeredAt, responseTime, trigger, isAhead, way, "
                + "answeredEntryUuid, isFromAnotherDevice"
            try db.execute(sql: "INSERT INTO new_reviewLog (\(copied)) SELECT \(copied) FROM reviewLog")
            try db.drop(table: "reviewLog")
            try db.rename(table: "new_reviewLog", to: "reviewLog")
            try db.create(index: "reviewLog_on_cardId", on: "reviewLog", columns: ["cardId"])
            if let lastID {
                try db.execute(
                    sql: """
                        DELETE FROM sqlite_sequence WHERE name = 'reviewLog';
                        INSERT INTO sqlite_sequence (name, seq) VALUES ('reviewLog', ?);
                        """,
                    arguments: [lastID])
            }
            /// Whether the card whose deck is `deck` syncs, as "v31 decks"
            /// says.
            func cardSyncs(deck: String) -> String {
                """
                (NOT (SELECT onlyChosenTags FROM syncChoice) OR EXISTS (
                    SELECT 1 FROM deck AS chosen WHERE chosen.chosenToSync AND (chosen.name = \(deck)
                        OR (chosen.name <> '' AND substr(\(deck), 1, length(chosen.name) + 2) = chosen.name || '::'))))
                """
            }
            let recording = "(SELECT recordsChanges FROM syncWrite)"
            try db.execute(
                sql: """
                    CREATE TRIGGER sync_reviewLog_inserted AFTER INSERT ON reviewLog WHEN \(recording) BEGIN
                    DELETE FROM syncPending WHERE recordType = 'reviewLogEntry' AND recordName = NEW.uuid;
                    INSERT INTO syncPending (recordType, recordName, isDeletion)
                    SELECT 'reviewLogEntry', NEW.uuid, 0 WHERE (SELECT isOn FROM syncDevice);
                    END;
                    CREATE TRIGGER sync_reviewLog_deleted AFTER DELETE ON reviewLog BEGIN
                    DELETE FROM syncPending WHERE recordType = 'reviewLogEntry' AND recordName = OLD.uuid;
                    INSERT INTO syncPending (recordType, recordName, isDeletion)
                    SELECT 'reviewLogEntry', OLD.uuid, 1 WHERE \(recording)
                        AND EXISTS (SELECT 1 FROM card WHERE card.id = OLD.cardId AND \(cardSyncs(deck: "card.deck")));
                    END;
                    """)
        }
        migrator.registerMigration("v33 the scheduler replaces the ladder") { db in
            // FSRS spaces every review (#404), and the ladder goes, with the
            // first view: a new way's first answer is a review. Each entry of
            // the review log is carried over to the scheduler's. A first view
            // becomes a review rated again, which puts the way on the first
            // learning step, as the first view put it on the ladder's first
            // step. A placement, which an import gave on a step of the
            // ladder, holds that step's wait as its interval, on the ladder
            // the settings held, or on the one Ficha shipped while they held
            // none, and, for a wait of a day or more, Anki's starting ease,
            // since the ladder kept none (`ladderPlacement(onStep:of:)`). And
            // every review holds the interval the scheduler gives it,
            // replaying its way's log with Ficha's settings, as #407 asks,
            // whatever the database's are (`carryOverScheduler`), answering
            // the entry replayed before it, or none as the way's first, so
            // that the scheduler keeps it: none keeps the interval it held,
            // which since "v32 the scheduler's settings and each review's
            // interval" was the ladder's wait, one the scheduler may not
            // set. The replay is the scheduler's as this version of Ficha has
            // it (`Scheduler.keepingIntervals(of:)`), so every device carries
            // over the log they share alike, as it carries over an older
            // device's entry on arrival.
            let ladderWaits =
                try String.fetchOne(db, sql: "SELECT ladder FROM progressSettings").map { text in
                    try JSONDecoder().decode([Int64].self, from: Data(text.utf8))
                } ?? shippedLadderWaits
            let scheduler = carryOverScheduler
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM reviewLog ORDER BY id")
            var entries: [ReviewLogEntry] = []
            for row in rows {
                let cardID: Int64 = try row.decode(forColumn: "cardId")
                let uuidName: String = try row.decode(forColumn: "uuid")
                guard let way = Way(rawValue: try row.decode(forColumn: "way")), let uuid = UUID(uuidString: uuidName)
                else {
                    throw unreadable("Card \(cardID) has a review log entry that went an unknown way, or isn't a UUID")
                }
                let answeredAt: Date = try row.decode(forColumn: "answeredAt")
                switch (try row.decode(forColumn: "kind") as String, try row.decode(forColumn: "rating") as String?) {
                case ("firstView", _):
                    entries.append(
                        ReviewLogEntry(
                            cardID: cardID, way: way, kind: .review(.again), answeredAt: answeredAt,
                            responseTime: nil, trigger: nil, uuid: uuid))
                case ("review", let ratingName?):
                    guard let rating = Rating(rawValue: ratingName) else {
                        throw unreadable("Card \(cardID) has a review in its review log of an unknown rating")
                    }
                    entries.append(
                        ReviewLogEntry(
                            cardID: cardID, way: way, kind: .review(rating), answeredAt: answeredAt,
                            responseTime: nil, trigger: nil, uuid: uuid))
                case ("placement", _):
                    let placed = ladderPlacement(onStep: try row.decode(forColumn: "step"), of: ladderWaits)
                    let placement = Placement(
                        interval: placed.interval, due: try row.decode(forColumn: "due"), ease: placed.ease)
                    entries.append(ReviewLogEntry(placing: cardID, way: way, on: placement, at: answeredAt, uuid: uuid))
                default:
                    throw unreadable("Card \(cardID) has a review log entry of an unknown kind")
                }
            }
            var carried: [UUID: ReviewLogEntry] = [:]
            for wayLog in Dictionary(grouping: entries, by: { CardWay(cardID: $0.cardID, way: $0.way) }).values {
                for entry in try scheduler.keepingIntervals(of: wayLog) {
                    if let uuid = entry.uuid {
                        carried[uuid] = entry
                    }
                }
            }

            // The table is made again, as "v32 the scheduler's settings and
            // each review's interval" made it, with every row carried over,
            // and its last id, which no entry gets again; and so are its
            // index and its triggers, which dropping it drops. The ladder's
            // step goes. Every entry holds its interval, in seconds: a
            // review's more than none, a placement's none or more; and a
            // placement its ease, when Anki gave one. A review an import
            // brings from Anki's history (#409) has no trigger, as a
            // placement has none.
            let uuid = """
                (hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)), 2) || '-' \
                || substr('89AB', 1 + (random() & 3), 1) || substr(hex(randomblob(2)), 2) || '-' \
                || hex(randomblob(6)))
                """
            let lastID = try Int64.fetchOne(db, sql: "SELECT seq FROM sqlite_sequence WHERE name = 'reviewLog'")
            try db.create(table: "new_reviewLog") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("uuid", .text).notNull().unique().defaults(sql: uuid)
                // Its index comes once the table has its name.
                table.belongsTo("card", indexed: false).notNull()
                table.column("kind", .text).notNull()
                table.column("rating", .text)
                table.column("due", .datetime)
                table.column("interval", .double).notNull()
                table.column("ease", .double)
                table.column("answeredAt", .datetime).notNull()
                table.column("responseTime", .double)
                table.column("trigger", .text)
                table.column("isAhead", .boolean).notNull().defaults(to: false)
                    .check(sql: "isAhead = 0 OR kind = 'review'")
                table.column("way", .text).notNull().defaults(to: "frontFirst")
                    .check(sql: "way IN ('frontFirst', 'backFirst')")
                table.column("answeredEntryUuid", .text)
                    .check(sql: "answeredEntryUuid IS NULL OR kind = 'review'")
                table.column("isFromAnotherDevice", .boolean).notNull().defaults(to: false)
                table.check(
                    sql: """
                        (kind = 'review' AND rating IN ('again', 'hard', 'good', 'easy') AND interval > 0)
                        OR (kind = 'placement' AND rating IS NULL AND interval >= 0)
                        """
                )
                table.check(sql: "(kind = 'placement') = (due IS NOT NULL)")
                table.check(sql: "ease IS NULL OR (kind = 'placement' AND ease > 0)")
                table.check(sql: "kind <> 'placement' OR (trigger IS NULL AND responseTime IS NULL)")
            }
            for row in rows {
                let uuidName: String = try row.decode(forColumn: "uuid")
                guard let entry = UUID(uuidString: uuidName).flatMap({ carried[$0] }) else {
                    throw unreadable("A review log entry, \(uuidName), wasn't carried over")
                }
                let kind: String
                let rating: String?
                let interval: Duration?
                let ease: Double?
                switch entry.kind {
                case .review(let answered):
                    (kind, rating, interval, ease) = ("review", answered.rawValue, entry.interval, nil)
                case .placement(let placement):
                    (kind, rating, interval, ease) = ("placement", nil, placement.interval, placement.ease)
                }
                guard let interval else {
                    throw unreadable("A review log entry, \(uuidName), wasn't given its interval")
                }
                try db.execute(
                    sql: """
                        INSERT INTO new_reviewLog (
                            id, uuid, cardId, kind, rating, due, interval, ease, answeredAt, responseTime, trigger,
                            isAhead, way, answeredEntryUuid, isFromAnotherDevice)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        row["id"] as DatabaseValue, uuidName, row["cardId"] as DatabaseValue, kind, rating,
                        row["due"] as DatabaseValue, interval.timeInterval, ease, row["answeredAt"] as DatabaseValue,
                        row["responseTime"] as DatabaseValue, row["trigger"] as DatabaseValue,
                        row["isAhead"] as DatabaseValue, row["way"] as DatabaseValue, entry.answeredEntry?.uuidString,
                        row["isFromAnotherDevice"] as DatabaseValue,
                    ])
            }
            try db.drop(table: "reviewLog")
            try db.rename(table: "new_reviewLog", to: "reviewLog")
            try db.create(index: "reviewLog_on_cardId", on: "reviewLog", columns: ["cardId"])
            if let lastID {
                try db.execute(
                    sql: """
                        DELETE FROM sqlite_sequence WHERE name = 'reviewLog';
                        INSERT INTO sqlite_sequence (name, seq) VALUES ('reviewLog', ?);
                        """,
                    arguments: [lastID])
            }
            /// Whether the card whose deck is `deck` syncs, as "v31 decks"
            /// says.
            func cardSyncs(deck: String) -> String {
                """
                (NOT (SELECT onlyChosenTags FROM syncChoice) OR EXISTS (
                    SELECT 1 FROM deck AS chosen WHERE chosen.chosenToSync AND (chosen.name = \(deck)
                        OR (chosen.name <> '' AND substr(\(deck), 1, length(chosen.name) + 2) = chosen.name || '::'))))
                """
            }
            let recording = "(SELECT recordsChanges FROM syncWrite)"
            try db.execute(
                sql: """
                    CREATE TRIGGER sync_reviewLog_inserted AFTER INSERT ON reviewLog WHEN \(recording) BEGIN
                    DELETE FROM syncPending WHERE recordType = 'reviewLogEntry' AND recordName = NEW.uuid;
                    INSERT INTO syncPending (recordType, recordName, isDeletion)
                    SELECT 'reviewLogEntry', NEW.uuid, 0 WHERE (SELECT isOn FROM syncDevice);
                    END;
                    CREATE TRIGGER sync_reviewLog_deleted AFTER DELETE ON reviewLog BEGIN
                    DELETE FROM syncPending WHERE recordType = 'reviewLogEntry' AND recordName = OLD.uuid;
                    INSERT INTO syncPending (recordType, recordName, isDeletion)
                    SELECT 'reviewLogEntry', OLD.uuid, 1 WHERE \(recording)
                        AND EXISTS (SELECT 1 FROM card WHERE card.id = OLD.cardId AND \(cardSyncs(deck: "card.deck")));
                    END;
                    """)

            // The settings lose the ladder, and so does their trigger, made
            // again as "v32 the scheduler's settings and each review's
            // interval" made it, without it. The time its field last
            // changed goes too: the record that a Ficha before FSRS sent
            // keeps the ladder in iCloud, unread.
            try db.execute(sql: "DROP TRIGGER sync_progressSettings_updated")
            try db.alter(table: "progressSettings") { table in
                table.drop(column: "ladder")
            }
            let settingsFields = [
                "newCardsPerDay", "forgottenOftenAfter", "learningSteps", "relearningSteps", "desiredRetention",
                "longestIntervalInDays", "fsrsParameters",
            ]
            let changedSettingsFields = settingsFields.map {
                "SELECT '\($0)' AS field WHERE OLD.\($0) IS NOT NEW.\($0)"
            }
            .joined(separator: " UNION ALL ")
            let anySettingChanged = settingsFields.map { "OLD.\($0) IS NOT NEW.\($0)" }.joined(separator: " OR ")
            try db.execute(
                sql: """
                    CREATE TRIGGER sync_progressSettings_updated AFTER UPDATE ON progressSettings
                    WHEN (SELECT recordsChanges FROM syncWrite) AND (\(anySettingChanged)) BEGIN
                    INSERT INTO syncFieldTime (recordType, recordName, field, changedAt)
                    SELECT 'progressSettings', 'progressSettings', field, (SELECT at FROM syncWrite)
                    FROM (\(changedSettingsFields)) WHERE true
                    ON CONFLICT (recordType, recordName, field) DO UPDATE SET changedAt = excluded.changedAt;
                    DELETE FROM syncPending WHERE recordType = 'progressSettings' AND recordName = 'progressSettings';
                    INSERT INTO syncPending (recordType, recordName, isDeletion)
                    SELECT 'progressSettings', 'progressSettings', 0 WHERE (SELECT isOn FROM syncDevice);
                    END;
                    DELETE FROM syncFieldTime WHERE recordType = 'progressSettings' AND field = 'ladder';
                    """)
        }
        return migrator
    }()
}
