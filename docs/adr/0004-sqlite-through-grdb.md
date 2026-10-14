# SQLite through GRDB instead of SwiftData

The app and the `ficha` CLI read and write the same database, so storage has to work from a command-line tool as well as from an app, with migrations both share. SwiftData, Apple's default, is built around a single app's model container and hides its schema and migrations. GRDB, a widely used open-source SQLite library, gives explicit SQL and explicit, versioned migrations, and two processes can share the file through SQLite's own locking.

## Consequences

- GRDB is Ficha's first dependency, pinned to an exact version; this is the ADR that `CODING_STANDARDS.md` asks for.
- Storage, and the engine the app and the CLI go through, live in their own target, `FichaData`; `FichaCore` stays free of GRDB.
