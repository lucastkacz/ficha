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
                // When Lucas answered, or when the import placed the card.
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
        return migrator
    }()
}
