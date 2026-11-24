# Pliego of Ficha

What the method's six commands read about Ficha (`.claude/method/method.md`), approved by Lucas on 2026-11-23. Each item is ✓ decided, ◐ provisional (it holds until a debate changes it) or ○ open. An item points at the file that already holds its details, and that file is where they change. A quoted name, such as "A window's picture", is a section of `docs/development.md`.

## What it is

- ✓ A macOS menu-bar app, for anyone, Lucas first, that shows its user a tiny flashcard every so often and spaces each card with FSRS, as Anki does. The cards stay on the user's devices and in their own iCloud (`README.md`, ADR 0017, ADR 0025).
- ✓ It sells once on the App Store, the Mac and the iPhone together, after seven free days (ADR 0029, #160). The iPhone app is Ficha Dev with the sample cards for now (#97).
- ✓ For a few small things the user wants to remember, which come to them while they work; for volume, Anki, which Ficha names once, honestly. Anki inside: its decks and tags, FSRS, the four ratings each review stores, its packages. Ficha outside: the card alone with two buttons, Forgot and Got it; a pace with its finish date, new cards coming from one deck at a time, at 85%; a few small decks of Ficha's own, picked at the Welcome page; English alone (ADR 0032 to ADR 0036, decided on 2026-11-24 in the artifact "Hacia dónde va Ficha").

## Areas

✓ Each node is a label, named with its path and colored as its top area, and each issue carries exactly one.

- `Mac` (blue): the Mac app.
  - `Mac › Review`: the review panel, appearances and what holds them back, Review now.
  - `Mac › Cards`: the Cards window: cards, decks, tags, types, the card form, the inbox.
    - `Mac › Cards › Import`: import and export: text files, zips, Anki's packages.
  - `Mac › Menu`: the menu bar item and its menu, Capture, the Welcome page, Diagnostics.
  - `Mac › Settings`: the Settings window's tabs.
  - `Mac › Widget`: the Next Card widget.
  - `Mac › CLI`: the `ficha` command.
- `iPhone` (amber): the iPhone app.
  - `iPhone › Review`: appearances as notifications, the Review tab.
  - `iPhone › Cards`: the Cards tab.
  - `iPhone › Capture`: capturing on the iPhone.
  - `iPhone › Settings`: Settings and the debug tools.
- `Core` (orange): what both apps share, in FichaKit (ADR 0019).
  - `Core › Scheduling`: FSRS, the learning steps, where a card stands, which cards show up and when.
  - `Core › Cards`: what a card holds: its sides, images, sounds, formatting, both ways.
  - `Core › Data`: the database and its migrations, the engine, backups.
  - `Core › Sync`: sync through the user's iCloud.
- `Launch` (green): selling Ficha.
  - `Launch › App Store`: its page, name, pictures, keywords and positioning.
  - `Launch › Price`: the free days and the payment (ADR 0029).
  - `Launch › Beta`: TestFlight's testers.
  - `Launch › Research`: the market research (`docs/research/`).
- `Environment` (pink): how agents build Ficha.
  - `Environment › Method`: the skills, this pliego, `CLAUDE.md`, the documents agents read, and `mockups/`, the web mocks and the Lab.
  - `Environment › Guards`: CI, the `Makefile`, the hooks, the permissions, the subagents' types.
  - `Environment › Hands-free`: the tools that drive, see and test Ficha, and the hand checks.
  - `Environment › Publishing`: `make upload`, TestFlight, the tags, iCloud's schema.

## How it's drawn

- ✓ A Mac window: `make render ARGS="<window>"`, offscreen, with Ficha Dev's sample cards ("A window's picture"), on the Mac Where it runs names.
- ✓ The iPhone: `make render-iphone`, its opening screen alone ("The iPhone's screen").
- ✓ The widget and the README's pictures: a throwaway package each ("The widget's pictures", "The README's pictures").
- ✓ A PR that changes what Lucas sees: each window or screen in English, German and Arabic ("The PR's pictures"), until #488 leaves English alone (ADR 0036).
- ✓ A proposal, before any Swift: the web mock kit, whose mock decides the look and FichaCore the logic, and the Ficha Lab, in `mockups/` (its README).
- ✓ An artifact's sources: the Claude project's shared folder, `/mnt/project-files/` in its sessions, a folder per artifact, such as `preparar/`.

## Hands-free

- **Drives it**
  - ✓ `ficha`, the CLI: cards, decks, tags, types, captures, approvals, fixes. Agents run Ficha Dev's through `scripts/ficha-dev.sh` on a scratch folder ("Agents' runs of Ficha Dev's `ficha`").
  - ✓ `make render`'s clicks, keys and typing in a window; `make preview-import` for an import; `xcrun simctl` for the simulator.
  - ○ Ficha Dev's Debug menu (the sample cards, its clock, an appearance now, the second device) takes clicks only: #474 brings it to the command line.
  - ○ Dragging, right-clicks, double-clicks, menus and popovers: `make render` can't; #293's driver would, on Lucas's screen.
  - ○ The iPhone takes no taps or typing (#136).
- **Sees it**
  - ✓ `make render` and `make render-iphone`'s pictures, in each of Ficha's languages, until #488 leaves English alone.
  - ✓ The log, subsystem `com.lucastkacz.ficha`, with `/usr/bin/log` or `simctl spawn … log`; `make last-crash`; the samples `make test` leaves in `.build/hangs`; `make preview-import`'s numbers.
  - ○ A window described as text, in place of its picture but for colors and the look: what each element says, where it is and its size, the focus, the selection, and what's cut off or overlaps (#139).
- **Tests it**
  - ✓ `make test` while building, and `make check` before the PR is ready, on Lucas's Mac: every step in the `Makefile`'s `CHECKS +=` lines, warnings as errors. From the cloud: Where it runs.
  - ✓ CI, `.github/workflows/check.yml`: on each PR, unless all its files are Markdown, as Where it runs says; and `make check` on each push to `main`, a run that stays, since it alone saves the cache the PRs' runs read.
  - ✓ They run on a Mac, GitHub's or Lucas's (Where it runs).

What stays by hand waits in the one open "Hand checks" issue, as "Hand checks" in `docs/agents/issue-tracker.md` says. ○ An agent runs the checks its tools already reach (#473); the rest wait for a tool, or need Lucas's Mac: meetings, Focus, logging in, the widget on the desktop, TestFlight.

## Where it runs

Cloud first (`.claude/method/method.md`), as ADR 0031 decides for Ficha.

- **The session in the cloud**: Linux, with no Swift or Xcode, so it builds, tests and draws none of Ficha: FichaKit imports Apple's frameworks, and FichaCore links fsrs-rs as an XCFramework. It has Node and Playwright's Chromium, which draw the web mocks (`mockups/`). It writes, reviews and pushes. Its network reaches GitHub, through the session's own tools, and npm's registry; it searches GitHub with `gh api`'s REST routes, such as `search/issues`, since GraphQL, and so `gh issue` and `gh search`, is refused. It comes with Lucas's Claude plan.
- **GitHub's Macs**: CI's `macos-26` runners, standard ones with 3 cores, free on a public repo ([GitHub's billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions)). A full `make check` takes about 24 minutes, `make test` alone about 8.
- **Lucas's Mac**: 10 cores, and his accounts, his signing and his screen. A cloud session runs work on it only through Remote Control, after his OK on its card, in the `ficha` folder, and it costs the Mac on and its cores while it runs. ✓ The `ficha` folder is in Remote Control: Lucas added it in the Claude app on 2026-11-23.

Each kind of work, as a cloud session does it by `CLAUDE.md`'s Shipping:

- ✓ Issues, debates, decisions and the reviews: the cloud.
- ✓ Building a node: the cloud, unless Lucas starts the session on his Mac.
  - ○ A change to `.github/workflows/`: GitHub refuses a cloud session's push there, since its token has no `workflow` scope, so it's pushed from Lucas's Mac through Remote Control ("A workflow change from the cloud").
  - ○ The other paths `.claude/hooks/merge-gate.sh` lists: no cloud session has tried a push to them yet; the next `/preparar` does.
- ✓ The tests while building, in two rounds per node (ADR 0031): from the cloud, GitHub's Macs; on Lucas's Mac, `make test`.
  - ◐ From the cloud, each push to the node's draft PR runs a round, CI's `tests` job, `make test` alone, which the session reads as `CLAUDE.md`'s Shipping says; marking the PR ready runs the full `check`.
- ✓ The three checks' tests and CI: from the cloud, the last round on the draft PR, then CI's `check` once it's ready; on Lucas's Mac, `make check`, then CI.
- ✓ The web mocks' pictures, with `mockups/tools/shoot.js`: the cloud.
- ○ The pictures of Ficha: GitHub's Macs, if the probe shows they draw Ficha's windows (#480); until then, Lucas's Mac, through Remote Control.
- ✓ The hand checks an agent can run (#473): Lucas's Mac, through Remote Control.
- ○ An agent's runs of Ficha, with `ficha`, `make render`'s clicks or the simulator: Lucas's Mac, through Remote Control, as the hand checks; GitHub's Macs, if the probe shows they can (#480).
- ✓ An acceptance criterion's proof: `test` runs where the tests do, `picture` where its picture is made, above, and `hand` on Lucas's Mac, from the Hand checks issue.
- ◐ In the cloud, a node's branch is the one the session is given.
- ○ The guards: no hook of the repo ran in a cloud session on 2026-11-23, and none matches the session's GitHub tools (#479). Until they do, a cloud session keeps them itself.

What stays on Lucas's Mac: `make upload` and `make install-iphone`, which sign with his team and reach App Store Connect and his iPhone; and the checks by hand, which need his hands, his meetings and his accounts.

## What waits for Lucas's OK

- ✓ A PR that changes a path `.claude/hooks/merge-gate.sh` lists carries `risk:high`, and Lucas merges it: `.claude/hooks/`, `.claude/settings.json`, `.claude/agents/`, `.github/workflows/`, `Makefile`, `*.entitlements`, `CLI/Info.plist`, `project.yml`, `scripts/data-changes.sh`. Where this list and the hook differ, the hook holds.
- ✓ Dependabot's update PRs carry it too (`.github/dependabot.yml`).
- ✓ GitHub's ruleset on `main`: a PR, a green `check`, a linear history, no bypass (ADR 0006).
- ✓ `make upload`, `make install-iphone` and `ficha restore` ask first (`.claude/settings.json`).

## When publishing

- ✓ `make upload`, from `main` in the main folder: the real Ficha to TestFlight's internal testers, tagged `v<version>-<build>`, listing the commits since the last tag that changed a path in `scripts/data-changes.sh`, the cards' database and the scheduler ("Upload to TestFlight").
- ✓ A new iCloud record type or field deploys to Production first ("A new record type or field in iCloud").
- ✓ `site/` publishes itself on GitHub Pages when it changes on `main` (`.github/workflows/pages.yml`).

## Plano

What `project.yml` builds, which generates the Xcode project with both apps:

```
Ficha.app (App/): the Mac app        iPhone (iPhone/): Ficha Dev, for now
├─ ficha (CLI/), in Contents/Helpers
├─ FichaWidget (Widget/), in Contents/PlugIns
└─ SVGDrawer (SVGDrawer/), in Contents/XPCServices
```

Who uses whom, with what each takes from outside:

```
Ficha ───────> FichaICloud, FichaData, FichaSVG, FichaCore
ficha ───────> FichaCLI, FichaData
FichaWidget ─> FichaData, FichaCore
SVGDrawer ───> FichaSVG
iPhone ──────> FichaData, FichaCore
FichaICloud ─> FichaData                     CloudKit
FichaCLI ────> FichaData, FichaCore          swift-argument-parser
FichaData ───> FichaSVG, FichaCore           GRDB, ZIPFoundation, zstd
FichaCore ───> FichaFSRS ─> CFichaFSRS       fsrs-rs, from Rust/
FichaSVG                                     WebKit
```

The executables:

- ✓ **Ficha** (`App/`): the Mac app, thin, built as the real Ficha or as Ficha Dev, which alone has the Debug menu. It bundles `docs/instructions-for-an-ai.md`, which the Import sheet copies.
- ✓ **ficha** (`CLI/`): runs FichaCLI's commands in a sandbox of its own, inside the app.
- ✓ **FichaWidget** (`Widget/`): the Next Card widget, inside the app.
- ✓ **SVGDrawer** (`SVGDrawer/`): an XPC service inside the app, the only part with the network entitlement WebKit needs in the sandbox (ADR 0018).
- ✓ **iPhone** (`iPhone/`): the iPhone app, for now only Ficha Dev (#97). Ficha Dev, on the Mac and the iPhone, and the real Ficha on the Mac sign with Lucas's paid team, whose ID is in `iPhone/Local.xcconfig`, which git ignores.
- ✓ What they share from `App/`: the CLI, the widget and the iPhone app compile `App/AppVariant.swift` too; the widget also `App/WidgetHandover.swift`; the iPhone app takes `App/AppIcon-Dev.icon`.

The libraries, in `Packages/FichaKit/`, a Swift package for macOS and iOS:

- ✓ **FichaCore**: the rules, as pure functions: scheduling, the planners, where a card stands, reading Anki.
- ✓ **FichaFSRS**: fsrs-rs's arithmetic for FichaCore, from our crate in `Rust/`, which `make fsrs` builds into an XCFramework (ADR 0026).
- ✓ **FichaData**: the engine: SQLite through GRDB, import and export, sync's logic behind `ICloudSyncEngine`, backups, the windows' states, Ficha Dev's sample cards.
- ✓ **FichaSVG**: draws an import's SVGs with WebKit: in the app, through the SVGDrawer service; in `swift test`, in the process.
- ✓ **FichaICloud**: the thin adapter that puts CloudKit's `CKSyncEngine` behind FichaData's `ICloudSyncEngine`; the only part that loads CloudKit, and the Mac app alone links it.
- ✓ **FichaCLI**: the `ficha` command's commands, with swift-argument-parser (ADR 0008).

The rest:

- ✓ Ficha's decks: a file each, in the app's resources, with each image's license, which come in through the same import as any file; #458 brings them (ADR 0035).
- ✓ `scripts/`: the render tools and the import-preview tool, which reach FichaKit by path (the render tool compiles `App/`'s files too); the hook tests; the watchdog for hung runs, with its tests; the build of fsrs-rs's XCFramework; the wrapper `make` runs `xcodebuild` through; what unregisters an app's other copies from LaunchServices; the reader of Ficha Dev's last crash, with its tests; the runner of its `ficha` on a scratch folder; the cleanup after a merge, with its tests; the list of what changed the cards' data since the last upload, with its tests; the translations check, with its tests; the check that the clock and the review log's IDs come from their sources; and Ficha's languages, `languages.txt`, which the render tools, the check and FichaKit's engine messages test read through `languages.sh` and `Languages.swift`.
- ✓ `docs/`: `development.md`, how to build, draw, test and publish; `agents/`, what agents read about the issues and the domain; `adr/`; `terms.md`, Ficha's words in each language; `content-guide.md`, how a refine session drafts Lucas's cards; `app-review-notes.md`, what App Review is told; `instructions-for-an-ai.md`; `research/`; `prototypes/`; and `images/`, the README's pictures.
- ✓ `.claude/`: the permissions, the hooks, the rules, the method's six skills and what they share (`method/`), the `/refine` skill and the subagents' types.
- ✓ `.github/`: CI, the workflow that publishes `site/` on GitHub Pages, Dependabot and the issue forms.
- ✓ `mockups/`: the web mock kit, the desktop mock and the Ficha Lab, with their tools in Node (its README).
- ✓ `site/`: the privacy policy, the one page GitHub Pages publishes, which Settings' About tab links to.
- ✓ `CODING_STANDARDS.md`: the standards `/construir`'s review checks every change against.
- ○ `.out-of-scope/`: ideas Lucas decided against, from before ADR 0030; no command reads it.

Rules that don't break:

1. ✓ Everything is driven and seen without hands: a new screen gets a `make render` window, a new behavior a `ficha` command, a Debug action an agent reaches or a test; what can't yet is a Task in `Environment › Hands-free`.
2. ✓ FichaCore is pure: Foundation, the standard library and FichaFSRS; the time from `TimeSource`, the review log's IDs from `IDSource` (ADR 0005, ADR 0026, `CODING_STANDARDS.md`, Layers and Time and IDs).
3. ✓ The apps are thin: what a window decides lives in FichaData, as a `Sendable` state (`CODING_STANDARDS.md`, Layers).
4. ✓ One way in: where a card stands, the cards that show up, flags and burials (`CODING_STANDARDS.md`, Where a card stands).
5. ✓ The OS enters through protocols, so the logic is tested without it (`CODING_STANDARDS.md`, Layers).
6. ✓ CloudKit lives in FichaICloud alone, which the Mac app alone links (ADR 0017, `Packages/FichaKit/Package.swift`).
7. ✓ No network of Ficha's own; only the SVG drawer may use it, drawing files already on the Mac (ADR 0001, ADR 0017).
8. ✓ Each executable runs in its sandbox (ADR 0018).
9. ✓ `project.yml` is the project; the Xcode project is generated, never edited (ADR 0005).
10. ✓ No crashes by design, and errors that say what to do; each dependency pinned, a new one with an ADR (`CODING_STANDARDS.md`, Errors and crashes, Dependencies).

## Words

- ✓ Ficha's: `GLOSSARY.md`. The method's: `.claude/method/method.md`.

## How we work

- ✓ Lucas reads Spanish; the repo and GitHub are in English, except the commands' descriptions and an issue's body above its folded part, which are in Spanish; the apps are in English alone (ADR 0036), once #488 takes out the eleven languages ADR 0027 brought (`CLAUDE.md`).
- ✓ Decisions: `docs/adr/`, one per decision, never rewritten: a later one says which it replaces, changes in part or makes obsolete, and, for records from ADR 0032 on, the older one gets a line under its title that says so, "Replaced by", "Changed in part by" or "Obsolete since", with the link.
- ✓ The default branch is `main`. On Lucas's Mac, a node's branch is named after its path, such as `mac-cards-import`, in a worktree of its own (`CLAUDE.md`, Shipping); in the cloud, Where it runs.
- ✓ The standards: `CODING_STANDARDS.md`.
- ✓ A PR merges itself after the three checks, with auto-merge; a `risk:high` PR waits for Lucas (`CLAUDE.md`, Shipping).
- ✓ After a merge: `/entregar`, then `make clean-merged` from the main folder ("Cleaning up after a merge").
- ✓ A mechanical chore goes to a `clerk`; building to `builder`s; the reviews to `reviewer`s (`.claude/agents/`).
- ✓ Where each kind of work runs, and on which machine: Where it runs (ADR 0031).

## Open

- ○ A web page where people share decks, which Lucas would like once Ficha's decks are built: an `/idea` when he brings it (ADR 0035).
- ○ Coming back after a break, without a wall of cards (#460): a `/debate` of its own (ADR 0034).
- ○ The pictures from GitHub's Macs (#480), and the guards in a cloud session (#479): Where it runs.
- ○ A change to `.github/workflows/` from a cloud session, pushed from Lucas's Mac while the session's token has no `workflow` scope: the `/debate` that takes it up; Where it runs.
- ○ Which of the guards' other paths a cloud session can push to: the next `/preparar`; Where it runs.
- ○ The hands-free gaps, for `/construir`: the checks an agent runs (#473), the Debug menu by command (#474) and the window as text (#139), which Lucas chose to build first; then the driver for dragging and right-clicks (#293) and taps on the iPhone (#136).
- ○ The Idea issue type: Lucas creates it in his account's settings; then a `clerk` gives the open issues their types and areas, and takes off the old triage labels (ADR 0030).
- ○ `.out-of-scope/`: whether it stays, moves into the issues or goes.
