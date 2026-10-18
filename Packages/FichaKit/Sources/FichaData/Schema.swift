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
            // `Suppression` names it; its shownAt and closedAt are when it was
            // held back. It never showed, so the next appearance doesn't wait
            // from it.
            try db.alter(table: "appearanceLog") { table in
                table.add(column: "heldBackBy", .text)
                    .check(sql: "(outcome = 'heldBack') = (heldBackBy IS NOT NULL)")
            }
        }
        return migrator
    }()
}
