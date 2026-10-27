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
            // tags in their own JSON column, and a tag is never renamed, so
            // its name is the key.
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
            // capture" did.
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
            // write, the time is SQLite's, when the database was migrated.
            // One row.
            try db.create(table: "syncWrite") { table in
                table.column("id", .integer).primaryKey().check(sql: "id = 1")
                table.column("at", .datetime).notNull()
                table.column("recordsChanges", .boolean).notNull()
            }
            try db.execute(
                sql: """
                    INSERT INTO syncWrite (id, at, recordsChanges)
                    VALUES (1, strftime('%Y-%m-%d %H:%M:%f', 'now'), 1)
                    """)
            // What waits to be sent to iCloud, one change per row that
            // syncs: it was saved, as when it came in or changed, or deleted.
            // Each change replaces the one before it, and gets the next id,
            // so a change sent is forgotten by its id, and one made while it
            // was being sent stays. It survives an iCloud account change,
            // which empties CKSyncEngine's own queue. While sync is off,
            // nothing waits: turning it on sends everything.
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
            func fieldsWhere(_ fields: [(String, [String])], _ changed: (String) -> String) -> String {
                fields.map { field, columns in
                    "SELECT '\(field)' AS field WHERE \(columns.map(changed).joined(separator: " OR "))"
                }
                .joined(separator: " UNION ALL ")
            }
            /// Whether `changed` holds of any column of `fields`.
            func anyColumn(of fields: [(String, [String])], _ changed: (String) -> String) -> String {
                fields.flatMap(\.1).map(changed).joined(separator: " OR ")
            }
            /// Records that the fields `fields` names, a query of one column,
            /// `field`, of the row of `type` named `name` changed now.
            func stamp(_ type: String, _ name: String, _ fields: String) -> String {
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
            func wait(_ type: String, _ name: String, deleted: Bool, onlyWhileRecording: Bool = false) -> String {
                """
                DELETE FROM syncPending WHERE recordType = '\(type)' AND recordName = \(name);
                INSERT INTO syncPending (recordType, recordName, isDeletion)
                SELECT '\(type)', \(name), \(deleted ? 1 : 0) WHERE \(isOn)\(onlyWhileRecording ? " AND \(recording)" : "");
                """
            }
            let changed = { (column: String) in "OLD.\(column) IS NOT NEW.\(column)" }
            // A card's type is its table's name, and so is a capture's.
            for (table, fields) in [("card", cardFields), ("capture", captureFields)] {
                try db.execute(
                    sql: """
                        CREATE TRIGGER sync_\(table)_inserted AFTER INSERT ON \(table) WHEN \(recording) BEGIN
                        \(wait(table, "NEW.uuid", deleted: false))
                        END;
                        CREATE TRIGGER sync_\(table)_updated AFTER UPDATE ON \(table)
                        WHEN \(recording) AND (\(anyColumn(of: fields, changed))) BEGIN
                        \(stamp(table, "NEW.uuid", fieldsWhere(fields, changed)))
                        \(wait(table, "NEW.uuid", deleted: false))
                        END;
                        CREATE TRIGGER sync_\(table)_deleted AFTER DELETE ON \(table) BEGIN
                        DELETE FROM syncFieldTime WHERE recordType = '\(table)' AND recordName = OLD.uuid;
                        \(wait(table, "OLD.uuid", deleted: true, onlyWhileRecording: true))
                        END;
                        """)
            }
            try db.execute(
                sql: """
                    CREATE TRIGGER sync_reviewLog_inserted AFTER INSERT ON reviewLog WHEN \(recording) BEGIN
                    \(wait("reviewLogEntry", "NEW.uuid", deleted: false))
                    END;
                    CREATE TRIGGER sync_reviewLog_deleted AFTER DELETE ON reviewLog BEGIN
                    \(wait("reviewLogEntry", "OLD.uuid", deleted: true, onlyWhileRecording: true))
                    END;
                    CREATE TRIGGER sync_tag_inserted AFTER INSERT ON tag WHEN \(recording) BEGIN
                    \(stamp("tag", "NEW.name", fieldsWhere(tagFields) { "NEW.\($0) IS NOT NULL" }))
                    \(wait("tag", "NEW.name", deleted: false))
                    END;
                    CREATE TRIGGER sync_tag_updated AFTER UPDATE ON tag
                    WHEN \(recording) AND (\(anyColumn(of: tagFields, changed))) BEGIN
                    \(stamp("tag", "NEW.name", fieldsWhere(tagFields, changed)))
                    \(wait("tag", "NEW.name", deleted: false))
                    END;
                    CREATE TRIGGER sync_tag_deleted AFTER DELETE ON tag WHEN \(recording) BEGIN
                    \(stamp("tag", "OLD.name", fieldsWhere(tagFields) { "OLD.\($0) IS NOT NULL" }))
                    \(wait("tag", "OLD.name", deleted: false))
                    END;
                    """)
        }
        return migrator
    }()
}
