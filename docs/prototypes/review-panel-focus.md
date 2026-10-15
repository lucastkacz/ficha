# The review panel's focus: prototype findings

What #10's prototype found about showing the review panel over whatever Lucas is doing without catching what he types, for the appearances ticket (#11). Measured on macOS 26 on 2026-10-15, by an agent and by Lucas (#34).

The prototype's code is on the branch [`10-focus-prototype`](https://github.com/lucastkacz/ficha/tree/10-focus-prototype), which is never merged.

## The prototype

On top of #9's review panel, Ficha Dev's debug menu gets "Prototipo: foco de la cajita". It shows the real panel 10 seconds later, over the app Lucas is typing in, in one of the three focus modes:

- **never** ("Nunca toma el teclado"): the panel never takes the keyboard on its own, and Lucas clicks it to use it;
- **once idle** ("Lo toma tras 5 s quieto"): it takes the keyboard once Lucas has been idle for 5 seconds;
- **always** ("Lo toma siempre"): it takes the keyboard as soon as it shows.

Under the card, the panel shows live who has the keyboard, the OS's idle time, the frontmost app and the menu bar's, and every key that reached it. Its cards come from an engine of its own in memory: four due cards and then a new one, so Space, 1, 2, 3 and Enter all do something. Launching Ficha Dev with `-FocusPrototype <mode>` runs one trial and quits, for agents.

## What works, and how

**Showing without the keyboard.** The panel is #9's `NSPanel` with `[.borderless, .nonactivatingPanel]`, at the `.floating` level, with `[.moveToActiveSpace, .fullScreenAuxiliary]` and `hidesOnDeactivate = false`. `orderFrontRegardless()` shows it over the frontmost app without making it key. The other app stays frontmost and keeps the menu bar, Ficha isn't activated, and no key reaches the panel.

**Taking the keyboard later.** `makeKey()`, called from a timer with no click or key press behind it, makes the panel key. The other app still stays frontmost and keeps the menu bar.

**Giving it back.** Once the panel closes, the keyboard goes back to the app in front with no code: that app's window becomes key again at once, and the next keys reach it. This held whether the panel took the keyboard on its own or from a click, and whether it closed on its own or with Esc, over a test app and over TextEdit. Clicking another app's window while the panel is open takes the keyboard away from the panel, and clicking the panel gives it back.

**Reading the idle time without permissions.** `CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType:)` with every input event, `CGEventType(rawValue: ~0)` (CoreGraphics' `kCGAnyInputEventType`, which Swift doesn't import), gives the seconds since the last key press, click, mouse move or scroll. Ficha Dev, launched with `open`, had neither Accessibility nor Input Monitoring (`AXIsProcessTrusted()` and `CGPreflightListenEventAccess()` were false, and neither asks), and the reading worked. `.combinedSessionState`, which also counts events that apps post, agreed to the microsecond. With `eventType: .keyDown`, the same call gives the seconds since the last key press only. The prototype read it every 250 milliseconds.

**Seeing who has the keyboard.** The panel's prominent button ("Dar vuelta", "Entendido") shows the accent color only while the panel is key, and is gray otherwise. That's macOS's own behavior, with no code.

## What Lucas saw

Lucas tried the three modes while typing in TextEdit (#34). The prototype's logs show:

- **once idle**: while he typed, the panel didn't take the keyboard. It took it 21 seconds after showing up, once he had stopped for 5 seconds.
- **always**: the panel took the keyboard at once, and in 12 seconds it caught 85 keys he was typing for TextEdit. That's what the focus mode is there to avoid.
- **never**: the panel took the keyboard only when he clicked it.

He also saw his keys not go back to TextEdit after closing the panel with Esc. The agent couldn't reproduce it with the same steps (see "Giving it back"), and Lucas thinks he may have slipped. Since then, the prototype logs any key that still reaches Ficha after the panel closes, so a new trial can tell.

Spaces and full-screen apps weren't checked in this trial. #33 checks them for the same panel.

## Gotchas

- **`NSApp.isActive` turns true while the panel is key**, although macOS doesn't activate Ficha: `NSRunningApplication.current.isActive` stays false, and `NSWorkspace`'s `frontmostApplication` and `menuBarOwningApplication` stay the other app. To tell whether Ficha took over, read `NSWorkspace`, not `NSApp.isActive` or its "did become active" notifications.
- **Once the panel has the keyboard, typing goes to it.** Letters do nothing, but a space flips the card and 1, 2 and 3 rate it. In the once-idle mode, that's what happens if Lucas starts typing again after a pause.
- **Mouse moves count as input** for the idle time with every input event: while Lucas reads and scrolls, he isn't idle, even if he hasn't typed in minutes.
- **Check permissions with the app launched through `open`.** A process started from a terminal or from Claude's shell takes that app's permissions. In this session, Claude's shell had Accessibility and Input Monitoring, so a check run from it would have reported both.

## Checking it without Lucas

The Accessibility API can't tell where keys go here: the system-wide focused app comes back as an error, and other apps' windows don't change their focus attributes when the panel takes the keyboard. What worked:

- a throwaway app with one window and a text field, which logs when its window becomes or stops being key, and every key it gets;
- a tool that clicks the panel and presses keys with `CGEvent`, from Claude's shell, which has Accessibility. Before each click or key, it checks that the panel is the topmost window under the point and that the test app is frontmost, so nothing lands in another app.

Both show up on Lucas's screen and take the keyboard for a few seconds, so they need him to keep off the Mac while they run. The prototype's info-level logs can be gone from `log show` within minutes, so read them right after a trial.

## For the appearances ticket (#11)

- Show an appearance with `orderFrontRegardless()`, and give it the keyboard with `makeKey()` as the focus mode says, by default once Lucas has been idle for 5 seconds. Never call `NSApp.activate()`.
- Read the idle time with `CGEventSource`, as above, while the panel is open. It needs no permission.
- The prototype takes the keyboard once per appearance: if Lucas then clicks his app, the panel doesn't take it again.
- Closing the panel needs nothing to give the keyboard back.
- The accent-colored button already shows whether the panel has the keyboard.
