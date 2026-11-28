# Ficha's mockups

Web mocks of Ficha's UI, to settle how a screen looks and feels before anyone builds it in SwiftUI, and the Ficha Lab, which shows what a setting does over weeks. A `/debate` or a `/decision` shows a proposal with them, Lucas tries it in the browser, and once it's settled, what it decided goes into the decision's issues and `/construir` builds it in Swift (`.claude/method/method.md`). The pliego's "How it's drawn" points here (`PLIEGO.md`).

No step of `make check` builds or reads this folder: the pages run in a browser, and the tools in Node.

## The rules

1. **A mock decides the look and the feel; FichaCore decides the logic.** The mock's engine is a toy. A rule that comes out of a mock (a number, an order, a condition) goes into the decision's issue as an acceptance criterion, and is built in Swift with its tests.
2. **A mock is cheap and disposable.** Variants are a switch in the mock's bar, not a new build. Nothing in a mock is kept because it took work.
3. **Emulate as much as the web allows; what it can't show stays native.** The mock imitates screen sizes, the notch, the Dock, full-screen apps, meetings and videos, and the card size. It can't show whether the review panel takes the keyboard from the app you're typing in (the focus mode), Spaces, how macOS really detects meetings, videos and full screen, or exact pixels. Those still need a prototype on the Mac, as `docs/prototypes/` did.
4. **Names come from the app.** A screen is named as its SwiftUI view is or will be, and its words come from `GLOSSARY.md`. A mock's UI is in English, Ficha's only language (ADR 0036). Its decks are in `kit/decks.js`: Ficha's decks, `ficha: true`, with the cards the app ships, in Spanish for now (ADR 0040), and one that stands for a deck of the user's own, made up, never Lucas's, in Spanish too, as Lucas's cards are.

## The mocks

| Mock | Artifact | What it explores |
|---|---|---|
| `desktop/` | [Ficha Desktop Mock](https://claude.ai/artifact/D9dTXwJWK5gNsFp36y2XrU) | Ficha as ADRs 0033 to 0035 and 0039 decided it: the review panel's card alone with Forgot, a yellow Kind of and Got it (#489, #517), and its four buttons before as a variant; the Welcome page with Ficha's decks (#467, #458); the Cards window's decks in their queue, each deck's cards as a grid, its front's picture or its text, with the selected card's detail beside it (#536), which says in words when the card is back and how many times it was seen, its numbers under Details (#537), a flagged card in its deck with its flag and its note (#540), and How fast? as a deck comes in (#491); Settings in five tabs, each row where Lucas approved it on 2026-11-25 and marked with the tab it was in (#492). As before: the panel over a working day on a fast clock, a meeting, a video or a full-screen app that holds an appearance back, the menu and the card size, on a Mac's real screen sizes. It starts at the first launch, or 25 days in. |
| `lab/` | [Ficha Lab](https://claude.ai/artifact/9frTfAJnYsNJukGgK8E1jd) | Not a screen: four or twelve weeks of Ficha in a made-up working life, A against B, Ficha as decided against Ficha before the decision to start with. What a setting costs (appearances and minutes a weekday, meetings it waits out) and what it gives (cards met, each deck's day all met, graduated, how often a review is remembered), day by day. |

## How it's built

No build step: React 18.3.1 from cdnjs and htm 3.1.1 from jsDelivr, pinned, so components are written as tagged templates instead of JSX. Every mock loads the same kit, from `kit/` beside its page, as its Artifact serves it: open a mock through `tools/shoot.js` or publish it, not straight from its folder. The decks carry no pictures, so `CardPicture` draws a stand-in; a copy published with the decks' pictures, small, sets `FichaPictures` in a script of its own, and `CardPicture` draws those.

| File | What it holds |
|---|---|
| `kit/tokens.css` | Colors, type and shapes, named as macOS names them, in light and dark. |
| `kit/ui.css` | The look of macOS 26 controls, Liquid Glass, the review panel, and the mock's own bar. |
| `kit/ui.js` | React components named after their SwiftUI counterparts, the fake Mac, and `MockControls`. |
| `kit/engine.js` | The toy engine: FSRS-6, the learning steps, the appearance rules, the clock, the pace, the queue and the finish date, and each card's review log. Plain JavaScript, so it also runs in Node. |
| `kit/decks.js` | Ficha's three decks, `ficha: true`, with the cards the app ships in `App/FichaDecks/`, which the Claude project's `build_decks.py` writes between its `// <ficha-decks>` lines, from `/mnt/project-files/mazos-ficha/build/` in its sessions (`PLIEGO.md`, An artifact's sources), and a made-up deck someone sent the user, as its `.ficha` (#554). |
| `kit/lab.js` | The Lab's simulator: weeks of the toy engine in a made-up life (the Mac's hours, meetings, snoozed appearances, ratings as FSRS predicts), run several times and averaged. Plain JavaScript; the Lab page and `tools/simulate.js` share it. |

### From the mock to SwiftUI

| In the mock | In the app |
|---|---|
| `--label`, `--secondary-label`, `--tertiary-label` | `.primary`, `.secondary`, `.tertiary` |
| `--separator` | `Divider()` |
| `--accent` | `.tint` |
| `--selection` | `.tint.opacity(0.16)`, and `0.3` in dark mode, as How fast?'s chosen pace is |
| `.glass` with `--radius-panel` (24) | `.glassEffect(.regular, in: .rect(cornerRadius: 24, style: .continuous))` |
| `--text-title2` semibold, `--text-title3` semibold, `--text-body`, `--text-caption` | `.title2.weight(.semibold)`, `.title3.weight(.semibold)`, `.body`, `.caption` (`CardTextStyle`) |
| `Button` / `Button prominent` / `Button yellow` | `.buttonStyle(.bordered)` / `.borderedProminent` / `.borderedProminent` with `.tint(.yellow)` and a black title while the panel has the keyboard |
| `IconButton` | `.labelStyle(.iconOnly)`, `.buttonStyle(.borderless)` |
| `KeyLabel`, `Capsule` | `KeyLabel`, a badge's `.background(.secondary.opacity(0.15), in: .capsule)`, as `AheadBadge`'s (`App/ReviewPanelView.swift`) |
| `Segmented` | `Picker` with `.pickerStyle(.segmented)` |
| `DisclosureGroup` | `DisclosureGroup(isExpanded:)` |
| `Window`'s `toolbar`, as the Cards window's New Card and Search, in `desktop/` | `.toolbar` and `.searchable(text:placement: .toolbar)`, at the window's unified toolbar's trailing end (`App/Cards/CardsView.swift`) |
| `MenuContent` | `App/MenuContent.swift` |
| `ReviewPanelView` | `App/ReviewPanelView.swift`, placed as `ReviewPanelWindow` places it: centered, 40 points under the menu bar; its `face` 'new' is the app's since #489, with #517's three buttons, and 'today' the app's before #489 |
| `WelcomePage`, in `desktop/` | `App/WelcomePage.swift`, with #467's steps |
| `CardsWindow` and `HowFast`, in `desktop/` | `App/Cards/CardsView.swift`'s deck rows and `App/Cards/HowFastSheet.swift`, since #491 |
| `CardsWindow`'s grid of tiles, its legend and `dotOf`, in `desktop/` | `App/Cards/CardGrid.swift`, with FichaData's `CardsWindowState.Tile` deciding each tile's face and dot, since #536, and a flagged card's flag in its dot's place, since #540 |
| `CardsWindow`'s card pane, its flag's note, `backWords`, `seenWords` and `CardNumbers`, in `desktop/` | `App/Cards/CardsDetail.swift`'s `CardDetail`, with `FlagAndSetAside` for the note, with FichaData's `CardsWindowState.wording(of:)` deciding its words, and Details' numbers and review log, `App/ReviewLogView.swift`, since #537 |
| `formatFinish` and `metBy`, a finish date's words | FichaData's `FinishDate.wording(now:dayStartsAtHour:calendar:)`, as `App/Cards/HowFastSheet.swift` writes it, since #491 |
| `SettingsWindow`, in `desktop/` | `App/SettingsTabViewController.swift`, `App/SettingsTabViews.swift`, `App/BackupsSettings.swift` and `App/SyncSettings.swift`, in #492's five tabs, each row where FichaData's `SettingsTabs.swift` places it; the Pace tab's paces and queue, FichaData's `PaceTab.swift` |

### What the toy engine copies

- FSRS-6 with fsrs-rs's default parameters and desired retention (`FichaFSRS`), and the learning and relearning steps of `Scheduler.standard` (`Scheduler.swift`, `StepRules.swift`); Anki's order for a review's ratings (Hard ≤ Good < Easy).
- `ReviewSettings.defaults`: the active hours, which may cross midnight, as `ActiveHours` says (ADR 0045), the separation, the cards an appearance, the look-ahead, the auto-close, and the wait after a meeting ends or the Mac wakes.
- FichaCore's `AppearancePlanner.swift` and `ReviewNow.swift`: Ficha appears when a card is due now, and the look-ahead only brings along the cards due within it; each appearance brings one new card at most; new cards a day count by Ficha's day, from 4:00 (`FichasDay.swift`, ADR 0045), as `ReviewNow`'s `metToday` does.
- The pace, one for all decks, as FichaCore's `Pace`: `PACES` in `kit/engine.js`, Chill, Steady and Faster at 1, 2 and 4 new cards a day, Steady to start (#490).
- The queue, as `CardsInReviews` and `ReviewNow` pick from it: new cards come from the first deck with cards not met, then from the next; a deck goes last, or first when asked, into the first place held by a deck with cards not met, as `places(putting:at:now:)` puts it, where the decks it passes move down one and a deck met in full or set aside keeps its own; a deck set aside leaves it and comes back to its place (`ToyFicha`'s `pickCards`, `addDeck`, `putFirst`, `moveFirst`, `setAside`). FichaCore also brings a priority deck's new cards first, which no mock acts out. `newCardsFrom: 'together'` splits them between every deck in turn instead, ADR 0034's "one pace split between them", which the Lab's "Ficha before" uses; the app never does.
- The finish date, as a range, as FichaCore's `DeckQueue.swift` works it out: `finishDays` gives each deck's days, the soonest if every day has appearances and the latest if five days in seven do, and `ToyFicha`'s `finishDates` places them on the calendar.
- 85% desired retention on a new install, `Scheduler.newInstall`: `NEW_INSTALL_RETENTION`; `SCHEDULER` keeps `Scheduler.standard`'s 90%, which `tools/check-engine.js`'s scheduling cases use.
- `tools/check-engine.js` runs cases copied from FichaFSRS's and FichaCore's tests (`FSRSTests`, `SchedulerIntervalsTests`, `SchedulerStepsTests`, and FichaData's `PaceAndQueueTests`, `DeckRowsTests`, `FichasDayTests` and `NightHoursTests`, in `Packages/FichaKit/Tests`) against the toy engine. Run it, from the repo's folder, after any change to `kit/engine.js`, and after a change to those tests or to the scheduling they test: `node mockups/tools/check-engine.js`.
- The review panel's three buttons, its ⋯ menu and its keys, as `App/ReviewPanelView.swift` has them since #517: `FACES`' 'new' and `MoreMenu` in `kit/ui.js`, where keys 1, 2 and 3 record Again, Hard and Good, and 4 nothing, as `AnswerButton` maps them; 'today', the panel before #489, keeps Anki's four buttons on keys 1 to 4. And how an interval reads, as `App/IntervalText.swift` writes it (`formatInterval`).
- The card size (`CardSize`): ⌘+, ⌘− and ⌘0, in `CardSize`'s steps. The card's text grows, the review panel widens with it and its buttons keep their size, as `CardSize` sets them; the review panel grows up to `ReviewPanelWindow.maximumShareOfScreen` of the screen's free height, and a taller card scrolls between its top line and its buttons.
- The suppressions a mock can act out, as `AppearancePlanner.swift` names them: a meeting, a video, an app in full screen.

### What it acts out ahead of the app

What `desktop/` shows that the app doesn't yet, or not where the mock has it, so a picture of the app differs from the mock there. `tools/check-engine.js` checks only the toy engine against FichaKit's tests, so it can't check these.

- The Welcome page's steps, `WelcomePage` (#467).
- In the Cards window, a deck's bar, with Put it first and Set aside: the app has Set Aside in the deck's menu, and Put it first in How fast? and in Settings' Pace tab.
- The Cards window's "Your Own" section, with New Deck… and Open Deck…, which the app keeps elsewhere: both in a deck's menu and the Your Decks title's, Open Deck… on ⌘O too, and beside New Card while the user has no cards. The mock's Open Deck… shows the deck a made-up `.ficha` holds, as the app's open panel would choose it, with Add Deck…, which asks How fast? for it, where the app goes from its open panel, or from Finder, straight to How fast?, whose line names the file (#554).

### Sizes

- **Screen** in the mock's bar picks a Mac at macOS's default "looks like" size, with the notch and the menu bar its model has (`SCREENS` in `kit/ui.js`). A page smaller than that Mac shows it scaled down, and the bar says by how much. "Fit the window" fills the page instead, at 1:1 once the page is as large as `Stage` in `kit/ui.js` needs.
- **Full screen** gives the mock the whole display and hides the bar (the Mock tab brings it back). On Lucas's own Mac, full screen with "Fit the window" is the closest to the real thing.
- Windows resize from their lower right corner; the green button takes Writer to full screen, which holds Ficha back as a full-screen app does.

What it makes up: the learner who rates the cards in a fast-forward and in the Lab (they remember as FSRS predicts), and the seconds a card takes.

## Deciding with numbers

The mocks show how Ficha feels in a minute; the Lab and the terminal tool show what a setting does over weeks, so a decision about a number (how many cards, how far apart, how fast a deck) starts from a measure instead of a guess.

- **The Lab** (`lab/`), for Lucas: the person (their cards, when the Mac is on, meetings) is shared; Ficha's settings are A and B. Its results average several runs over the same weeks from a Monday, as `DEFAULTS` in `kit/lab.js` sets them. The days have their own stream of chance, planned up front, so A and B meet the same days and meetings and differ only by the setting.
- **`node mockups/tools/simulate.js`**, for Claude: the same simulator from the terminal, Ficha as decided against Chill, Faster, every deck in turn and Ficha before, or `node mockups/tools/simulate.js scenarios.json` with `{ "name": { ...changes to kit/lab.js's DEFAULTS } }`.
- **`node mockups/tools/check-engine.js`**: what makes the two worth trusting ("What the toy engine copies").

A number from the Lab is a lead, not a fact: like a rule from a mock, it goes into the decision's issue and is checked by FichaCore's tests. The made-up life is in "How the Lab works" on the page and in `DEFAULTS` in `kit/lab.js`.

How fast?'s range holds in the Lab's made-up life: Ficha's three decks, 120 cards, are all met on day 72 at Steady, against a promise of day 60 to 84, and on day 36 at Faster, against 30 to 42. The Lab's "All cards met" shows both for any setting but "Ficha before", which promised no date.

## A debate's mock

A `/debate` or a `/decision` that shows a screen builds its mock with this kit, as an artifact of its own that a preview on its page links, as `.claude/method/artifacts.md` says:

1. Start from `desktop/index.html` and keep its head: the title, the pinned scripts and the kit's links.
2. Build the new screen in the page. Once a second mock needs a piece, it moves into `kit/ui.js`, through a PR.
3. Put each variant in the mock's bar: a `HudGroup` with a `HudChoice`, passed to `MockControls` as `variants`.
4. Try it with `tools/shoot.js`, which renders it in Chromium through Playwright, with React and htm from npm, and reports console errors, where a mock that loads Google Fonts shows one failed load, the stylesheet it blocks: `node mockups/tools/shoot.js <mock> mockups/kit <out> [dev]`, with the sizes and steps its header describes, on the machine `PLIEGO.md`'s Where it runs gives the web mocks' pictures. The npm packages go in `mockups/npmtest/`, which git ignores, or where the header's `NPMTEST` says; from the repo's folder: `mkdir -p mockups/npmtest && cd mockups/npmtest && npm pack react@18.3.1 react-dom@18.3.1 htm@3.1.1 && for f in *.tgz; do mkdir -p "${f%.tgz}" && tar -xzf "$f" -C "${f%.tgz}"; done`.
5. Publish it with the Artifact tool: the page as `file_path`, and each kit file in `files`, from this folder (`"kit/ui.js": "mockups/kit/ui.js"`) or from a published mock's files (`{ "artifact": "<url>", "path": "kit/ui.js" }`).
6. Keep the page's own source where `PLIEGO.md` keeps an artifact's sources (How it's drawn). A mock that stays useful past its debate, as `desktop/` and the Lab do, comes here, with its row in the table above, through a PR.

Done when `tools/shoot.js` renders each variant with no console error but the Google Fonts one, and the debate's artifact links the published mock.
