# The review panel's focus: prototype findings

What #10's prototype found about showing the review panel over whatever Lucas is doing without catching what he types, for the appearances ticket (#11). Measured on macOS 26 on 2026-10-15, by an agent and by Lucas (#34).

The prototype's code is on the branch [`10-focus-prototype`](https://github.com/lucastkacz/ficha/tree/10-focus-prototype), which is never merged, with the tools that checked it in `prototypes/focus/`.

## The prototype

On top of #9's review panel, Ficha Dev's debug menu gets "Prototipo: foco de la cajita". It shows the real panel 10 seconds later, over the app Lucas is typing in, in one of the three focus modes:

- **never** ("Nunca toma el teclado"): the panel never takes the keyboard on its own, and Lucas clicks it to use it;
- **once idle** ("Lo toma tras 5 s quieto"): it takes the keyboard once Lucas has been idle for 5 seconds;
- **always** ("Lo toma siempre"): it takes the keyboard as soon as it shows.

Under the card, the panel shows live who has the keyboard, the OS's idle time, the frontmost app and the menu bar's, and the last keys that reached it. Its cards come from an engine of its own in memory: four due cards and then a new one, so Space, 1, 2, 3 and Enter all do something.

For agents, launching Ficha Dev with `-FocusPrototype <mode>` runs one trial, closes the panel 3 seconds after it shows, and quits. `-FocusPrototypeReturn` picks how the panel gives the keyboard back.

## What works, and how

**Showing without the keyboard.** The panel is #9's `NSPanel` with `[.borderless, .nonactivatingPanel]`. It overrides `canBecomeKey` to return true, since a borderless window can't become key otherwise. It sits at the `.floating` level, with `[.moveToActiveSpace, .fullScreenAuxiliary]` and `hidesOnDeactivate = false`. `orderFrontRegardless()` shows it over the frontmost app without making it key. The other app stays frontmost and keeps the menu bar, Ficha isn't activated, and no key reaches the panel.

**Taking the keyboard later.** `makeKey()`, called from the prototype's polling loop with no click or key press behind it, makes the panel key. The other app still stays frontmost and keeps the menu bar.

**Giving it back.** In every agent test, the keyboard went back to the app in front once the panel closed, with no code: that app's window became key again at once, and the next keys reached it. The tests covered the panel taking the keyboard on its own or from a click, and closing on its own or with Esc, over a test app and over TextEdit. Clicking another app's window while the panel is open takes the keyboard away from the panel, and clicking the panel gives it back. Lucas once saw it fail (see "What Lucas saw").

The prototype has two fallbacks, picked with `-FocusPrototypeReturn`:

- yielding activation to the app in front and activating it, as macOS 14's cooperative activation asks: `NSApp.yieldActivation(to:)`, then `activate(from:options:)`, before closing;
- hiding Ficha with `NSApp.hide(nil)` after closing.

Both gave the keyboard back too, in tests where the panel closed on its own. Neither was tried with Esc or by Lucas.

**Reading the idle time without permissions.** `CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType:)` gives the seconds since the last key press, click, mouse move or scroll, with every input event as the type. That's CoreGraphics' `kCGAnyInputEventType`, which Swift doesn't import: build it with `CGEventType(rawValue: ~0)`, which returns an optional to unwrap without `!`. With `eventType: .keyDown`, the same call gives the seconds since the last key press only. Ficha Dev, launched with `open`, had neither Accessibility nor Input Monitoring (`AXIsProcessTrusted()` and `CGPreflightListenEventAccess()` were false, and neither asks), and the reading worked. `.combinedSessionState`, which also counts events that apps post, agreed with `.hidSystemState` to the microsecond. The once-idle mode read `.hidSystemState` with every input event, every 250 milliseconds.

**Seeing who has the keyboard.** The panel's prominent button ("Dar vuelta", "Entendido") shows the accent color only while the panel is key, and is gray otherwise. That's macOS's own behavior, with no code.

## What Lucas saw

Lucas tried the three modes while typing in TextEdit (#34). The prototype's logs show:

- **once idle**: while he typed, the panel didn't take the keyboard. It took it 21 seconds after showing up, once he had stopped for 5 seconds.
- **always**: the panel took the keyboard at once, and in 12 seconds it caught 85 keys he was typing for TextEdit. That's what the focus mode is there to avoid.
- **never**: the panel took the keyboard only when he clicked it.

He also saw his keys not go back to TextEdit after he closed the panel with Esc. The agent couldn't reproduce it with the same steps, and Lucas thinks he may have slipped, so it stays open. Since then, the prototype logs any key that still reaches Ficha in the 4 seconds after the panel closes.

Still open, in #34 and for #11's trial:

- which mode felt right, and whether 5 seconds is a good wait;
- whether he noticed when the panel took the keyboard;
- whether the first click on "Dar vuelta" flips the card or only gives the panel the keyboard, which matters in the never and once-idle modes;
- Spaces and full-screen apps. #33 checks them for review now, whose panel takes the keyboard as it opens. An appearance shows the panel from a timer with `orderFrontRegardless()`, and nobody has checked that path yet.

## Gotchas

- **`NSApp.isActive` turns true while the panel is key**, although macOS doesn't activate Ficha: `NSRunningApplication.current.isActive` stays false, and `NSWorkspace`'s `frontmostApplication` and `menuBarOwningApplication` stay the other app. To tell whether Ficha took over, read `NSWorkspace`, not `NSApp.isActive`.
- **Once the panel has the keyboard, typing goes to it.** Letters do nothing, but a space flips the card, 1, 2 and 3 rate it, and Return ends a new card's first view ("Entendido"), which records it. In the once-idle mode, that's what happens if Lucas starts typing again after a pause.
- **Mouse moves count as input** for the idle time with every input event: while Lucas reads and scrolls, he isn't idle, even if he hasn't typed in minutes.
- **Check permissions with the app launched through `open`.** A process started from a terminal or from Claude's shell takes that app's permissions. On 2026-10-15, Claude's shell had Accessibility and Input Monitoring, so a check run from it would have reported both.

## Checking it without Lucas

The Accessibility API can't tell where keys go here: the system-wide focused app comes back as an error, and other apps' windows don't change their focus attributes when the panel takes the keyboard. What worked is in `prototypes/focus/`, on the prototype's branch:

- a Probe app with one window and a text field, which logs when its window becomes or stops being key, and every key it gets;
- `drive`, which clicks the panel and presses keys with `CGEvent`, so it needs Accessibility, as Claude's shell has. Before each click or key, it checks that the panel is the topmost window under the point and that the test app is frontmost, so nothing lands in another app.

Both show up on Lucas's screen and take the keyboard for a few seconds, so they need him to keep off the Mac while they run. `log show` lists the prototype's info-level logs only with `--info`, and they can be gone within minutes, so read them right after a trial.

## For the appearances ticket (#11)

- In an appearance, show the panel with `orderFrontRegardless()`, and give it the keyboard with `makeKey()` as the focus mode says: by default, once Lucas has been idle for 5 seconds. Never call `NSApp.activate()`.
- Read the idle time as the once-idle mode did: `.hidSystemState` with every input event, while the panel is open. It needs no permission. It enters through a protocol the app implements (`CODING_STANDARDS.md`, "Layers"), so the rules that react to it are tested without the OS.
- Decide what happens when Lucas types after the panel took the keyboard: in the once-idle mode, a space, a digit or Return would answer a card (see "Gotchas").
- Our own choice, which the prototype made and we suggest keeping: the panel takes the keyboard once per appearance, so if Lucas clicks his app, it doesn't take it again.
- Closing the panel gave the keyboard back with no code in every agent test. #11's trial should watch for Lucas's case, and if it shows up, fall back on yielding to the app in front and activating it.
- The accent-colored button already shows whether the panel has the keyboard.
