# Coding standards

How Swift is written in Ficha, what the scripts, the hooks, the `Makefile` and CI say when they fail, how the docs keep up with the files they describe, and how the documents agents read are written. The `code-review` skill checks every change against this file, so a rule that isn't here doesn't bind. Formatting is `swift format`'s job (`.swift-format`), and shellcheck and actionlint lint the shell scripts and the workflows; this file covers what those tools can't.

## Language and concurrency

- Swift 6 language mode with complete concurrency checking. Warnings are errors.
- The app target is isolated to the main actor by default (Xcode 26's default). Work that must leave the main actor says so explicitly (`nonisolated`, `@concurrent`).
- A delegate method that iOS or macOS calls with a completion handler runs on the main actor (`extension Type: @MainActor Delegate`), even when the framework calls it on a queue of its own, unless the framework's documentation says the handler may run on any thread. Swift also imports it as an `async` method, and calls the handler where that method returns; UIKit's handlers can need the main thread.
- Package targets aren't main-actor isolated: their types are `Sendable` values (structs and enums) wherever possible.

## Layers

- `FichaCore` holds the logic as pure functions and value types. It imports only Foundation and the standard library's modules (such as `Synchronization`): no AppKit, SwiftUI, GRDB or OS services.
- Storage, the CLI and the app stay thin at the edges and call into `FichaCore`.
- What a window decides lives in FichaData, in a `Sendable` state shaped like `ReviewPanelState`: the engine opens it, the window's view holds it, its operations call the engine and change it, and `swift test` tests it through that interface against an engine in memory. What a window decides is what it lists, what is selected, what it shows, what it offers, what it asks before acting, and what happens when Lucas acts: narrowing a table to a search, offering Bury only when none of the selected cards is buried, or recording which action failed. The view draws the state and turns it into translated text: it keeps the drawing, the keyboard, the focus and the text. A decision worked out in the app instead, in a view or in a model of the app's around it, breaks this rule, however small. A window that only shows what the engine returns, such as Capture and Diagnostics, has nothing of its own to decide.
- What the OS tells us (camera or microphone in use, idle time, power assertions, full-screen apps) enters through protocols the app implements, so the logic that reacts to it is tested without the OS.
- The Xcode project is generated from `project.yml`. Never edit `Ficha.xcodeproj`.

## Which cards show up

- Whether a card is in Lucas's reviews is read from `Card.isInReviews`, or from `cardsInReviews(in:)` and `cardInReviews(_:in:)`, in `FichaData/CardsInReviews.swift`, never worked out again from the card's flag and burial. The merge gate watches that file, so a change to which cards show up makes a pull request risk:high; the same rule written elsewhere would slip past it.

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

- Every text the app shows is in English, its base language, and can be translated (ADR 0009): SwiftUI's text literals, and `String(localized:)` for text built in code, with a comment when the text alone is ambiguous. A sentence is one localized string with its values interpolated, never pieces put together in code. A word that changes with a count gets a plural variation in the app's String Catalog: `App/Localizable.xcstrings`, or `iPhone/Localizable.xcstrings` for the iPhone app.
- `EngineError`'s messages use `String(localized:)` in the main bundle too. Xcode doesn't add them to the app's String Catalog, so a translation adds them by hand. The `ficha` CLI's main bundle is its own folder in the app, with no catalog, which keeps them in English there.
- Two exceptions are in English only and never translated. Ficha Dev's debug tools and their messages, such as the Mac's debug menu and the sample cards' errors, are verbatim (`Text(verbatim:)`, plain `String`s), so they stay out of the String Catalog. The `ficha` CLI is in English whatever the Mac's language: its commands, options, JSON fields, help and messages, like swift-argument-parser's own words (ADR 0008).
- Every action has a keyboard path. Icon-only buttons have an accessibility label.
- Icons are SF Symbols. The app icon is the exception: Apple's terms don't allow SF Symbols, or images confusingly similar to them, in app icons, so it's our own drawing, vector layers in Icon Composer documents (`App/*.icon`).

## Tests

- Swift Testing: `import Testing`, `@Test`, `#expect`, and `try #require` to unwrap.
- Few and meaningful: test what can break in a way that matters, like scheduling, which cards show and when, storage and migrations, and import and export. No tests for trivial code, and no mocks that only check which calls were made.
- Test names are sentences that state the behavior: `@Test("a wrong answer sends the card back to the first step")`.
- Fixtures are made by hand, never taken from Lucas's cards.

## No suppressions

- No `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`, `// swift-format-ignore` or disabled tests to make a check pass. If one is truly needed, the PR says why.

## Dependencies

- Each dependency is pinned to an exact version in `Package.swift`, and `Package.resolved` is committed. The render tool (`scripts/render`) takes its dependencies through FichaKit's pins, so its own `Package.resolved` stays out.
- A new dependency needs an ADR in `docs/adr/` and makes the PR `risk:high`.

## Scripts, hooks, the Makefile and CI

- A failure message says what happened and what to do about it, as an error's message does in Swift: "App/Localizable.xcstrings is out of date with the code's UI texts: run make strings and commit the catalog."

## Docs

- A change that renames a file, or changes what it covers or does, updates in the same PR every line elsewhere in the repo that describes it, such as those in `CLAUDE.md`, `README.md`, `docs/`, `.claude/rules/`, `.claude/skills/` and comments. `git grep` finds them by the file's name and by words for what it covers or does. `docs/adr/` and `docs/prototypes/` stay as they are: they record what was decided or tried at the time.
- No linter can tell that a file's scope changed, so the reviewer looks beyond the diff for these lines. A line the change left stale is a violation.
- A document agents read, such as `CLAUDE.md` and those in `.claude/rules/`, `.claude/skills/` and `docs/agents/`, follows the mattpocock-skills plugin's `writing-for-agents` skill.
