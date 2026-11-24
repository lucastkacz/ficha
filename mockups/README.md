# Ficha's mockups

Web mocks of Ficha's UI, to settle how a screen looks and feels before anyone builds it in SwiftUI, and the Ficha Lab, which shows what a setting does over weeks. A `/debate` or a `/decision` shows a proposal with them, Lucas tries it in the browser, and once it's settled, what it decided goes into the decision's issues and `/construir` builds it in Swift (`.claude/method/method.md`). The pliego's "How it's drawn" points here (`PLIEGO.md`).

No step of `make check` builds or reads this folder: the pages run in a browser, and the tools in Node.

## The rules

1. **A mock decides the look and the feel; FichaCore decides the logic.** The mock's engine is a toy. A rule that comes out of a mock (a number, an order, a condition) goes into the decision's issue as an acceptance criterion, and is built in Swift with its tests.
2. **A mock is cheap and disposable.** Variants are a switch in the mock's bar, not a new build. Nothing in a mock is kept because it took work.
3. **Emulate as much as the web allows; what it can't show stays native.** The mock imitates screen sizes, the notch, the Dock, full-screen apps, meetings and videos, and the card size. It can't show whether the review panel takes the keyboard from the app you're typing in (the focus mode), Spaces, how macOS really detects meetings, videos and full screen, or exact pixels. Those still need a prototype on the Mac, as `docs/prototypes/` did.
4. **Names come from the app.** A screen is named as its SwiftUI view is or will be, and its words come from `GLOSSARY.md`. A mock's UI is in English, Ficha's base language (ADR 0009); its cards are in Spanish, as Lucas's are, and made up, never his.

## The mocks

| Mock | Artifact | What it explores |
|---|---|---|
| `desktop/` | [Ficha Desktop Mock](https://claude.ai/artifact/D9dTXwJWK5gNsFp36y2XrU) | The review panel over a working day on a fast clock; a meeting, a video or a full-screen app that holds an appearance back; the menu, Capture, the card size, two rating buttons as a variant, and a proposed Add a Deck window with "How fast?". On a Mac's real screen sizes, in the browser's full screen. |
| `lab/` | [Ficha Lab](https://claude.ai/artifact/9frTfAJnYsNJukGgK8E1jd) | Not a screen: four weeks of Ficha in a made-up working life, A against B. What a setting costs (appearances and minutes a weekday, meetings it waits out) and what it gives (cards met and graduated, how often a review is remembered), day by day. |

## How it's built

No build step: React 18.3.1 from cdnjs and htm 3.1.1 from jsDelivr, pinned, so components are written as tagged templates instead of JSX. Every mock loads the same kit, from `kit/` beside its page, as its Artifact serves it: open a mock through `tools/shoot.js` or publish it, not straight from its folder.

| File | What it holds |
|---|---|
| `kit/tokens.css` | Colors, type and shapes, named as macOS names them, in light and dark. |
| `kit/ui.css` | The look of macOS 26 controls, Liquid Glass, the review panel, and the mock's own bar. |
| `kit/ui.js` | React components named after their SwiftUI counterparts, the fake Mac, and `MockControls`. |
| `kit/engine.js` | The toy engine: FSRS-6, the learning steps, the appearance rules, the clock, and the pace estimate. Plain JavaScript, so it also runs in Node. |
| `kit/decks.js` | Sample decks, made up. |
| `kit/lab.js` | The Lab's simulator: weeks of the toy engine in a made-up life (the Mac's hours, meetings, snoozed appearances, ratings as FSRS predicts), run several times and averaged. Plain JavaScript; the Lab page and `tools/simulate.js` share it. |

### From the mock to SwiftUI

| In the mock | In the app |
|---|---|
| `--label`, `--secondary-label`, `--tertiary-label` | `.primary`, `.secondary`, `.tertiary` |
| `--separator` | `Divider()` |
| `--accent` | `.tint` |
| `.glass` with `--radius-panel` (24) | `.glassEffect(.regular, in: .rect(cornerRadius: 24, style: .continuous))` |
| `--text-title2` semibold, `--text-body`, `--text-caption` | `.title2.weight(.semibold)`, `.body`, `.caption` (`CardTextStyle`) |
| `Button` / `Button prominent` | `.buttonStyle(.bordered)` / `.borderedProminent` |
| `IconButton` | `.labelStyle(.iconOnly)`, `.buttonStyle(.borderless)` |
| `KeyLabel`, `Capsule` | `KeyLabel`, `CardTopLine`'s capsules |
| `Segmented` | `Picker` with `.pickerStyle(.segmented)` |
| `MenuContent` | `App/MenuContent.swift` |
| `ReviewPanelView` | `App/ReviewPanelView.swift`, placed as `ReviewPanelWindow` places it: centered, 40 points under the menu bar |
| `CaptureView` | `App/CaptureView.swift` |

### What the toy engine copies

- FSRS-6 with fsrs-rs's default parameters and desired retention (`FichaFSRS`), and the learning and relearning steps of `Scheduler.standard` (`Scheduler.swift`, `StepRules.swift`); Anki's order for a review's ratings (Hard ≤ Good < Easy).
- `ReviewSettings.defaults`: the active hours, the separation, the cards an appearance, the look-ahead, the auto-close, and the wait after a meeting ends or the Mac wakes.
- FichaCore's `AppearancePlanner.swift` and `ReviewNow.swift`: Ficha appears when a card is due now, and the look-ahead only brings along the cards due within it; each appearance brings one new card at most; a deck's new cards a day count by the calendar day.
- `tools/check-engine.js` runs cases copied from FichaFSRS's and FichaCore's tests (`FSRSTests`, `SchedulerIntervalsTests`, `SchedulerStepsTests`, in `Packages/FichaKit/Tests`) against the toy engine. Run it, from the repo's folder, after any change to `kit/engine.js`, and after a change to those tests or to the scheduling they test: `node mockups/tools/check-engine.js`.
- The review panel's keys, as `App/ReviewPanelView.swift` handles them, and how an interval reads, as `App/IntervalText.swift` writes it (`formatInterval`).
- The card size (`CardSize`): ⌘+, ⌘− and ⌘0, in `CardSize`'s steps. The card's text grows, the review panel widens with it and its buttons keep their size, as `CardSize` sets them; the review panel grows up to `ReviewPanelWindow.maximumShareOfScreen` of the screen's free height, and a taller card scrolls between its top line and its buttons.
- The suppressions a mock can act out, as `AppearancePlanner.swift` names them: a meeting, a video, an app in full screen.

### Sizes

- **Screen** in the mock's bar picks a Mac at macOS's default "looks like" size, with the notch and the menu bar its model has (`SCREENS` in `kit/ui.js`). A page smaller than that Mac shows it scaled down, and the bar says by how much. "Fit the window" fills the page instead, at 1:1 once the page is as large as `Stage` in `kit/ui.js` needs.
- **Full screen** gives the mock the whole display and hides the bar (the Mock tab brings it back). On Lucas's own Mac, full screen with "Fit the window" is the closest to the real thing.
- Windows resize from their lower right corner; the green button takes Writer to full screen, which holds Ficha back as a full-screen app does.

What it makes up: the learner who rates the cards in a fast-forward and in the pace estimate (they remember as FSRS predicts), and the seconds a card takes.

## Deciding with numbers

The mocks show how Ficha feels in a minute; the Lab and the terminal tool show what a setting does over weeks, so a decision about a number (how many cards, how far apart, how fast a deck) starts from a measure instead of a guess.

- **The Lab** (`lab/`), for Lucas: the person (their cards, when the Mac is on, meetings) is shared; Ficha's settings are A and B. Its results average several runs over the same weeks from a Monday, as `DEFAULTS` in `kit/lab.js` sets them. The days have their own stream of chance, planned up front, so A and B meet the same days and meetings and differ only by the setting.
- **`node mockups/tools/simulate.js`**, for Claude: the same simulator from the terminal, Ficha's defaults against a few changes, or `node mockups/tools/simulate.js scenarios.json` with `{ "name": { ...changes to kit/lab.js's DEFAULTS } }`.
- **`node mockups/tools/check-engine.js`**: what makes the two worth trusting ("What the toy engine copies").

A number from the Lab is a lead, not a fact: like a rule from a mock, it goes into the decision's issue and is checked by FichaCore's tests. The made-up life is in "How the Lab works" on the page and in `DEFAULTS` in `kit/lab.js`.

Known gap: the desktop mock's "How fast?" estimate (`simulatePace` and `metBy` in `kit/engine.js`) meets each day's new cards all at once, while Ficha brings one new card an appearance. With small decks they agree; with a large deck and many new cards a day, "How fast?" says much sooner than the Lab; `node mockups/tools/simulate.js` shows by how much.

## A debate's mock

A `/debate` or a `/decision` that shows a screen builds its mock with this kit, as `.claude/method/artifacts.md` asks of its artifacts:

1. Start from `desktop/index.html` and keep its head: the title, the pinned scripts and the kit's links.
2. Build the new screen in the page. Once a second mock needs a piece, it moves into `kit/ui.js`, through a PR.
3. Put each variant in the mock's bar: a `HudGroup` with a `HudChoice`, passed to `MockControls` as `variants`.
4. Try it with `tools/shoot.js`, which renders it in Chromium through Playwright, with React and htm from npm, and reports console errors, where a mock that loads Google Fonts shows one failed load, the stylesheet it blocks: `node mockups/tools/shoot.js <mock> mockups/kit <out> [dev]`, with the sizes and steps its header describes, on the machine `PLIEGO.md`'s Where it runs gives the web mocks' pictures. The npm packages go in `mockups/npmtest/`, which git ignores, or where the header's `NPMTEST` says; from the repo's folder: `mkdir -p mockups/npmtest && cd mockups/npmtest && npm pack react@18.3.1 react-dom@18.3.1 htm@3.1.1 && for f in *.tgz; do mkdir -p "${f%.tgz}" && tar -xzf "$f" -C "${f%.tgz}"; done`.
5. Publish it with the Artifact tool: the page as `file_path`, and each kit file in `files`, from this folder (`"kit/ui.js": "mockups/kit/ui.js"`) or from a published mock's files (`{ "artifact": "<url>", "path": "kit/ui.js" }`).
6. Keep the page's own source where `PLIEGO.md` keeps an artifact's sources (How it's drawn). A mock that stays useful past its debate, as `desktop/` and the Lab do, comes here, with its row in the table above, through a PR.

Done when `tools/shoot.js` renders each variant with no console error but the Google Fonts one, and the debate's artifact links the published mock.
