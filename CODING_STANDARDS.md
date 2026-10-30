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
- The app stays thin in its windows too: what a window decides lives in `FichaData`, in a `Sendable` state shaped like `ReviewPanelState`. The engine opens it, its operations call the engine and change it, and `swift test` tests it through that interface against an engine in memory.
  - What a window decides is what it lists, what is selected, what it shows, what it offers, what it asks before acting, and what happens when the user acts, such as narrowing a table to a search, offering Bury only when none of the selected cards is buried, or recording which action failed.
  - The window's view draws the state and turns it into translated text, an engine error's message included. It keeps the drawing, the keyboard shortcuts, which control has the focus, and the text. It also keeps the fields the user types into, and a table's columns and the order its rows sort in, since a column can sort by translated names.
  - A decision worked out in the app instead, in a view or in an app-side model that holds the state, breaks this rule, however small: the app may hold the state, but never decides for it.
  - Showing what the engine returned is drawing, not deciding. Capture asks about the duplicate the engine found, and Diagnostics lists what the engine and the Mac's detectors report, so neither needs a state of its own.
- What the OS tells us (camera or microphone in use, idle time, power assertions, full-screen apps) enters through protocols the app implements, so the logic that reacts to it is tested without the OS.
- The Xcode project is generated from `project.yml`. Never edit `Ficha.xcodeproj`.

## Where a card stands

- Where a card stands, in Lucas's reviews, waiting in the inbox, buried or set aside with its deck or a deck it sits inside (ADR 0024), is read from `CardStanding` (`Card.standing`), in `FichaCore/Scheduler/CardStanding.swift`, or from `cardInReviews(_:in:)`, in `FichaData/CardsInReviews.swift`, never worked out again from a card's flag, burial date and deck. A card read from the database knows which decks set it aside: `setAsideDecks(in:)`, in the same file, reads the decks that are set aside, and `CardStanding.setAsideDecks(of:among:)` picks the card's deck and the decks it sits inside, which `TagPath`, in `FichaCore/TagsInsideTags.swift`, says. A tag's switch, which the tag table keeps until Lucas's tags become decks (#387), decides nothing.
- The cards that show up are read from one way in, never gathered again: `cardsThatShowUp(in:)`, in `FichaData/CardsInReviews.swift`, reads every card, the priority decks and the review log into `CardsInReviews`, in `FichaCore/Scheduler/CardsInReviews.swift`, which keeps the ways of the cards whose standing is in Lucas's reviews and knows which of those cards are in a priority deck or a deck inside one. The planners take that value, never ids, and pick ways, each a card and the way it shows (`CardWay`), which `CardsThatShowUp.panelCards` maps back to cards.
- The merge gate watches these four files, so a change to where a card stands, and so to which cards show up, makes a pull request risk:high; the same rule written elsewhere would slip past it.
- A card's flag and burial are set and cleared only by the functions in `FichaData/FlaggingAndBurying.swift`. Fixing and editing a card, the review panel's ⌘Z, an import that buries a card suspended in the app it comes from, and sync, which takes the flag and the burial another device left, call them too, never SQL of their own, so a change to how a card is flagged or buried can't miss a path.

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

- Every text the app shows is in English, its base language, and can be translated (ADR 0009): SwiftUI's text literals, and `String(localized:)` for text built in code, with a comment when the text alone is ambiguous. A sentence is one localized string with its values interpolated, never pieces put together in code. A word that changes with a count gets a plural variation in the app's String Catalog: `App/Localizable.xcstrings`, `Widget/Localizable.xcstrings` for the Mac's widget, or `iPhone/Localizable.xcstrings` for the iPhone app.
- `EngineError`'s messages use `String(localized:)` in the main bundle too. Xcode doesn't add them to the String Catalogs, so a translation adds them by hand: to the app's, and to the widget's, `Widget/Localizable.xcstrings`, since the widget's extension, which shows them too, is a main bundle of its own. The `ficha` CLI's main bundle is its own folder in the app, with no catalog, which keeps them in English there.
- Two exceptions are in English only and never translated. Ficha Dev's debug tools and their messages, such as the Mac's debug menu and the sample cards' errors, are verbatim (`Text(verbatim:)`, plain `String`s), so they stay out of the String Catalog. The `ficha` CLI is in English whatever the Mac's language: its commands, options, JSON fields, help and messages, like swift-argument-parser's own words (ADR 0008).
- Every action has a keyboard path. A tag's own actions have theirs in the Cards window's All Tags: the arrow keys select a tag, and Shift several; the detail's Actions menu holds what the tag's context menu does, Pin to Sidebar or Unpin from Sidebar, Rename…, Color, Emoji… and Delete…; Rename… with a tag's whole name moves it inside another, or out of one, as a drop in All Tags does; Return lists the tag's cards and ⌘⌫ deletes the tags; and the detail's Clear Unused Tags… button, which has no shortcut, clears the tags no card carries. A deck's own actions have theirs above the card list: the arrow keys choose the deck in the sidebar's Decks section, and the Actions menu in the bar above the card list holds what the deck's context menu in the sidebar does, Set Aside, Prioritize, Color and Emoji… (`App/Cards/DeckMenu.swift`); a deck's new action goes in both, through `DeckMenuItems`. The deck's tags, in the same bar, are buttons, and the tags that don't fit a "+N more" menu (`App/Cards/DeckTagsRow.swift`). The Actions menus and the detail's buttons take the focus with Tab while macOS's Keyboard navigation setting is on, which is what makes them a keyboard path, as for every button. All Tags' Pinned checkbox, a pinned tag's context menu in the sidebar, a deck's context menu in the sidebar, and dragging tags into the sidebar, onto a tag or between two rows of All Tags, are other ways to do the same. Some actions live in the sidebar alone, in its rows and context menus, as tags do in Finder's sidebar (#206): reordering the pinned tags, by dragging one to another place among them, and the Rename…, Emoji… and Delete… of a card type the user made. Icon-only buttons have an accessibility label.
- Icons are SF Symbols. The app icon is the exception: Apple's terms don't allow SF Symbols, or images confusingly similar to them, in app icons, so it's our own drawing, vector layers in Icon Composer documents (`App/*.icon`).

## Tests

- Swift Testing: `import Testing`, `@Test`, `#expect`, and `try #require` to unwrap.
- Few and meaningful: test what can break in a way that matters, like scheduling, which cards show and when, storage and migrations, and import and export. No tests for trivial code, and no mocks that only check which calls were made.
- A fake of a system service, such as `FakeICloud` for CloudKit and `CKSyncEngine`, does what the service's documentation says, and where the documentation says nothing, the less forgiving thing: a fake kinder than the service passes tests the app then fails. Its doc comment names each place it differs from the real service. The reviewer reads a change to a fake, or to code a fake stands in for, against the service's documentation.
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
