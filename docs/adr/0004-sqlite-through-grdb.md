# SQLite through GRDB instead of SwiftData

The app and the `ficha` CLI read and write the same database, so storage has to work from a command-line tool as well as from an app, with migrations both share. SwiftData, Apple's default, is built around a single app's model container and hides its schema and migrations. GRDB, a widely used open-source SQLite library, gives explicit SQL and explicit, versioned migrations, and two processes can share the file through SQLite's own locking. GRDB is Ficha's first dependency, pinned to an exact version; `CODING_STANDARDS.md` asks for an ADR for each one.

## Consequences

- Storage lives in its own target, `FichaData`, which the app and the CLI both use; `FichaCore` stays free of GRDB.
- The schema and its migrations are `risk:high`: the pull request that creates them adds their paths to the merge gate.
