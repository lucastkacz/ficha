internal import GRDB

/// The database's schema, built by versioned migrations in order. A migration
/// that has shipped never changes: every change to the schema is a new
/// migration at the end. Changing this file makes a pull request risk:high.
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
        return migrator
    }()
}
