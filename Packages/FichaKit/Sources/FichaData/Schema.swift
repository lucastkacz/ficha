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
        return migrator
    }()
}
