# Coding standards

How Swift is written in Ficha, what the scripts, the hooks, the `Makefile` and CI say when they fail, how the docs keep up with the files they describe, and how the documents agents read are written. The `code-review` skill checks every change against this file, so a rule that isn't here doesn't bind. Formatting is `swift format`'s job (`.swift-format`), rustfmt and clippy check our Rust crate, with warnings as errors, and shellcheck and actionlint lint the shell scripts and the workflows; this file covers what those tools can't.

## Language and concurrency

- Swift 6 language mode with complete concurrency checking. Warnings are errors.
- The app target is isolated to the main actor by default (Xcode 26's default). Work that must leave the main actor says so explicitly (`nonisolated`, `@concurrent`).
- A delegate method that iOS or macOS calls with a completion handler runs on the main actor (`extension Type: @MainActor Delegate`), even when the framework calls it on a queue of its own, unless the framework's documentation says the handler may run on any thread. Swift also imports it as an `async` method, and calls the handler where that method returns; UIKit's handlers can need the main thread.
- Package targets aren't main-actor isolated: their types are `Sendable` values (structs and enums) wherever possible.
- Code that blocks a thread until other work ends, with a semaphore or a `wait`, waits only for work that needs no thread of Swift's concurrency pool: work on the main actor, reached through completion handlers, on a serial dispatch queue of its own, or answered on the thread that waits, as XPC's synchronous proxy answers. An `await` on its way resumes on that pool, an Objective-C method imported as `async` and a task's `value` included, and `DispatchQueue.global()` and XPC's asynchronous replies get no thread either while the pool's all wait: it has one per core, three on GitHub's Macs. Its test makes every other thread of the pool wait while it waits, as `SVGDrawerTests` does, in a serialized suite: two such tests side by side hold the threads each other waits for, and stall every other test.

## Layers

- `FichaCore` holds the logic as pure functions and value types. It imports Foundation, the standard library's modules (such as `Synchronization`) and `FichaFSRS`, which wraps fsrs-rs's arithmetic for it (ADR 0026), and nothing else: no AppKit, SwiftUI, GRDB or OS services.
- Storage, the CLI and the app stay thin at the edges and call into `FichaCore`.
- The app stays thin in its windows too: what a window decides lives in `FichaData`, in a `Sendable` state shaped like `ReviewPanelState`. The engine opens it, its operations call the engine and change it, and `swift test` tests it through that interface against an engine in memory.
  - What a window decides is what it lists, what is selected, what it shows, what it offers, what it asks before acting, and what happens when the user acts, such as narrowing a table to a search, offering Bury only when none of the selected cards is buried, or recording which action failed.
  - The window's view draws the state and turns it into translated text, an engine error's message included. It keeps the drawing, the keyboard shortcuts, which control has the focus, and the text. It also keeps the fields the user types into, and a table's columns and the order its rows sort in, since a column can sort by translated names.
  - A decision worked out in the app instead, in a view or in an app-side model that holds the state, breaks this rule, however small: the app may hold the state, but never decides for it.
  - Showing what the engine returned is drawing, not deciding. Capture asks about the duplicate the engine found, and Diagnostics lists what the engine and the Mac's detectors report, so neither needs a state of its own.
- What the OS tells us (camera or microphone in use, idle time, power assertions, full-screen apps) enters through protocols the app implements, so the logic that reacts to it is tested without the OS.
- The Xcode project is generated from `project.yml`. Never edit `Ficha.xcodeproj`.

## Where a card stands

- Where a card stands, in Lucas's reviews, waiting in the inbox, buried or set aside with its deck or a deck it sits inside (ADR 0024), is read from `CardStanding` (`Card.standing`), in `FichaCore/Scheduler/CardStanding.swift`, or from `cardInReviews(_:in:)`, in `FichaData/CardsInReviews.swift`, never worked out again from a card's flag, burial date and deck. A card read from the database knows which decks set it aside: `setAsideDecks(in:)`, in the same file, reads the decks that are set aside, and `CardStanding.setAsideDecks(of:among:)` picks the card's deck and the decks it sits inside, which `TagPath`, in `FichaCore/TagsInsideTags.swift`, says. A tag's switch, which the tag table keeps for `ficha tag convert-to-decks` to carry to the deck the tag becomes (`FichaData/TagsIntoDecks.swift`), decides nothing.
- The cards that show up are read from one way in, never gathered again: `cardsThatShowUp(in:)`, in `FichaData/CardsInReviews.swift`, reads every card, the priority decks and the review log into `CardsInReviews`, in `FichaCore/Scheduler/CardsInReviews.swift`, which keeps the ways of the cards whose standing is in Lucas's reviews and knows which of those cards are in a priority deck or a deck inside one. The planners take that value, never ids, and pick ways, each a card and the way it shows (`CardWay`), which `CardsThatShowUp.panelCards` maps back to cards.
- The merge gate watches these four files, so a change to where a card stands, and so to which cards show up, makes a pull request risk:high; the same rule written elsewhere would slip past it.
- A card's flag and burial are set and cleared only by the functions in `FichaData/FlaggingAndBurying.swift`. Fixing and editing a card, the review panel's ⌘Z, an import that buries a card suspended in the app it comes from, and sync, which takes the flag and the burial another device left, call them too, never SQL of their own, so a change to how a card is flagged or buried can't miss a path.

## Time and IDs

- Logic gets the current time from a `TimeSource` (`now`), and the review log's IDs, which seed FSRS's fuzz, from the engine's `IDSource` (`newID`), never from `Date()`, `Date.now` or `UUID()`, so tests control both. An ID that seeds nothing, such as a temporary file's name or a card type's, may still take a `UUID()`, as `FichaData` does. `make time-and-ids-check`, a step of `make check`, fails on `Date()` and `Date.now` outside the tests, `scripts/` and `FichaCore/TimeSource.swift`, and on `UUID()` in `FichaCore` outside `IDSource.swift`. The reviewer judges the rest.

## Errors and crashes

- No crashes by design: no `!`, `try!` or `fatalError` outside tests. Handle the error or throw it.
- Errors are typed, and their message says what happened and what to do about it.
- Unexpected data fails loudly. Never guess a default for what isn't known.

## Logging

- `os.Logger` with subsystem `com.lucastkacz.ficha` and one category per area.
- Card content is logged with the default private privacy, never `.public`.

## UI

- Every text the app shows is in English, its base language, and is translated into each of Ficha's languages in `scripts/languages.txt`, in the change that adds or changes it, with the words in `docs/terms.md` (ADR 0027): SwiftUI's text literals, and `String(localized:)` for text built in code, with a comment when the text alone is ambiguous, since the comment is what a translation reads. One English word with two meanings a language says apart, such as the sidebar's Due and a card's, gets a key of its own for one of them, `String(localized: "sidebar.due", defaultValue: "Due", comment: …)`. A sentence is one localized string with its values interpolated, never pieces put together in code. A word that changes with a count gets plural variations, in every language, with the categories `scripts/languages.txt` gives it. The String Catalogs are `App/Localizable.xcstrings`, `Widget/Localizable.xcstrings` for the Mac's widget, `iPhone/Localizable.xcstrings` for the iPhone app and `App/AppShortcuts.xcstrings` for the App Shortcut's phrases alone: Xcode reads every text in it as a phrase, so a short title goes in the app's. Each translation is marked translated, and a text that must not change, such as one of symbols alone, is marked Don't translate. `make check` fails while a text lacks a translation into one of the languages in `scripts/languages.txt`, so a new language comes in one change that adds its line there and translates every catalog into it.
- `EngineError`'s messages use `String(localized:)` in the main bundle too, each message one `LocalizedStringResource`, whose key is the whole English text with its format specifiers. Xcode doesn't add them to the String Catalogs, so each message is added by hand, translated, as a manual key, to the catalog of each main bundle that shows them: the app's, the widget's, since the widget's extension is a main bundle of its own, and the iPhone app's. A new or changed message changes the three catalogs in the same change: FichaKit's `EngineMessagesTests` fails while a message lacks its key, or a language, in any of them. The `ficha` CLI's main bundle is its own folder in the app, with no catalog, which keeps them in English there.
- Two exceptions are in English only and never translated. Ficha Dev's debug tools and their messages, such as the Mac's debug menu and the sample cards' errors, are verbatim (`Text(verbatim:)`, plain `String`s), so they stay out of the String Catalog. The `ficha` CLI is in English whatever the Mac's language: its commands, options, JSON fields, help and messages, like swift-argument-parser's own words (ADR 0008).
- A text that can't wrap, such as a button's or a tab's title, a column header or a label beside a control, fits whole in every language: its view grows to fit it, and never cuts it with an ellipsis or a fixed width. German runs about 30% longer than English.
- Layout says leading and trailing, never left and right, so that a right-to-left language mirrors it: SwiftUI's `.leading` and `.trailing`, AppKit's leading and trailing anchors, and `.natural` text alignment, or, for AppKit's trailing side, which has no alignment of its own, `.right` or `.left` as the app's layout direction says. SF Symbols that point say backward and forward, such as `chevron.backward`. A drawing or a name that keeps a physical side says why in a comment.
- The user's own text, a card's sides and source and a capture's text, note and source, follows its own direction, whatever the app's language, in the review panel, the Cards window's tables and detail, the card form and the editor: SwiftUI gives a `Text` and a text field their text's direction within their lines, macOS 26's default, but aligns a `Text` at the layout's leading side, its default `Text.AlignmentStrategy`, `.layoutBased`. So `TextAsItReads` shows such a text, and `alignedAsItReads(_:)` aligns a text field or a row that holds one, at the side the text starts from. Both set `.layoutBased`, the strategy Apple names for an alignment chosen explicitly, since Apple documents text fields and editors as `.writingDirectionBased`, under which `.trailing` means against the text's direction; and a frame on that side, since a `Text` wraps its content tightly, so its alignment alone only places its lines against one another. AppKit's text views get the natural direction. The app's layout never gives the user's text its direction or its alignment.
- Every action has a keyboard path. A tag's own actions have theirs in the Cards window's All Tags: the arrow keys select a tag, and Shift several; the detail's Actions menu holds what the tag's context menu does, Pin to Sidebar or Unpin from Sidebar, Rename…, Color, Emoji… and Delete…; Rename… with a tag's whole name moves it inside another, or out of one, as a drop in All Tags does; Return lists the tag's cards and ⌘⌫ deletes the tags; and the detail's Clear Unused Tags… button, which has no shortcut, clears the tags no card carries. A deck's own actions have theirs above the card list: the arrow keys choose the deck in the sidebar's Decks section, and the Actions menu in the bar above the card list holds what the deck's context menu in the sidebar does, Set Aside, Prioritize, Rename…, Color, Emoji… and Delete…, Default's without Rename… and Delete… (`App/Cards/DeckMenu.swift`); a deck's new action goes in both, through `DeckMenuItems`. Rename… with a deck's whole name moves it inside another, or to the top, as a drop in the sidebar does, and Change Deck… (⌘D) moves the selected cards, as dropping them on a deck does. The deck's tags, in the same bar, are buttons, and the tags that don't fit a "+N more" menu (`App/Cards/DeckTagsRow.swift`). The Actions menus and the detail's buttons take the focus with Tab while macOS's Keyboard navigation setting is on, which is what makes them a keyboard path, as for every button. All Tags' Pinned checkbox, a pinned tag's context menu in the sidebar, a deck's context menu in the sidebar, dragging tags into the sidebar, onto a tag or between two rows of All Tags, and dragging cards onto a deck in the sidebar, or a deck onto another or onto the Decks section's title, are other ways to do the same. Some actions live in the sidebar alone, in its rows and context menus, as tags do in Finder's sidebar (#206): reordering the pinned tags, by dragging one to another place among them, and the Rename…, Emoji… and Delete… of a card type the user made. Icon-only buttons have an accessibility label.
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
- Our Rust crate's (`Packages/FichaKit/Rust`) are pinned the same way: each direct dependency to an exact version (`=6.6.2`) in `Cargo.toml`, with `Cargo.lock` committed, and every Cargo command that builds or lints it runs with `--locked`.
- A new dependency needs an ADR in `docs/adr/` and makes the PR `risk:high`.

## Scripts, hooks, the Makefile and CI

- A failure message says what happened and what to do about it, as an error's message does in Swift: "App/Localizable.xcstrings is out of date with the code's UI texts: run make strings and commit the catalog."

## Docs

- A change that renames a file, or changes what it covers or does, updates in the same PR every line elsewhere in the repo that describes it, such as those in `CLAUDE.md`, `README.md`, `docs/`, `.claude/rules/`, `.claude/skills/`, `.claude/agents/` and comments. `git grep` finds them by the file's name and by words for what it covers or does. `docs/adr/` and `docs/prototypes/` stay as they are: they record what was decided or tried at the time.
- No linter can tell that a file's scope changed, so the reviewer looks beyond the diff for these lines. A line the change left stale is a violation.
- A document agents read, such as `CLAUDE.md` and those in `.claude/rules/`, `.claude/skills/`, `.claude/agents/` and `docs/agents/`, follows the mattpocock-skills plugin's `writing-for-agents` skill.
