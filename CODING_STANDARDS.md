# Coding standards

How Swift is written in Ficha. The `code-review` skill checks every change against this file, so a rule that isn't here doesn't bind. Formatting is `swift format`'s job (`.swift-format`); this file covers what a formatter can't.

## Language and concurrency

- Swift 6 language mode with complete concurrency checking. Warnings are errors.
- The app target is isolated to the main actor by default (Xcode 26's default). Work that must leave the main actor says so explicitly (`nonisolated`, `@concurrent`).
- Package targets aren't main-actor isolated: their types are `Sendable` values (structs and enums) wherever possible.

## Layers

- `FichaCore` holds the logic as pure functions and value types. It imports only Foundation and the standard library's modules (such as `Synchronization`): no AppKit, SwiftUI, GRDB or OS services.
- Storage, the CLI and the app stay thin at the edges and call into `FichaCore`.
- What the OS tells us (camera or microphone in use, idle time, power assertions, full-screen apps) enters through protocols the app implements, so the logic that reacts to it is tested without the OS.
- The Xcode project is generated from `project.yml`. Never edit `Ficha.xcodeproj`.

## Time

- Logic gets the current time from a `TimeSource` (`now`), never from `Date()` or `Date.now`, so tests control time.

## Errors and crashes

- No crashes by design: no `!`, `try!` or `fatalError` outside tests. Handle the error or throw it.
- Errors are typed, and their message says what happened and what to do about it.
- Unexpected data fails loudly. Never guess a default for what isn't known.

## Logging

- `os.Logger` with subsystem `com.lucastkacz.ficha` and one category per area.
- Card content is logged with the default private privacy, never `.public`.

## UI

- Every user-facing text is in Spanish.
- The `ficha` CLI is the exception: its commands, options and JSON fields are in English, as the code names them, and so are swift-argument-parser's own words (ADR 0008). Its help and its messages are in Spanish.
- Every action has a keyboard path. Icon-only buttons have an accessibility label.
- Icons are SF Symbols.

## Tests

- Swift Testing: `import Testing`, `@Test`, `#expect`, and `try #require` to unwrap.
- Few and meaningful: test what can break in a way that matters, like scheduling, which cards show and when, storage and migrations, and import and export. No tests for trivial code, and no mocks that only check which calls were made.
- Test names are sentences that state the behavior: `@Test("a wrong answer sends the card back to the first step")`.
- Fixtures are made by hand, never taken from Lucas's cards.

## No suppressions

- No `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`, `// swift-format-ignore` or disabled tests to make a check pass. If one is truly needed, the PR says why.

## Dependencies

- Each dependency is pinned to an exact version in `Package.swift`, and `Package.resolved` is committed.
- A new dependency needs an ADR in `docs/adr/` and makes the PR `risk:high`.
