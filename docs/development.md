# Developing Ficha

How to build Ficha, try a change and work on it, one section for each task. The [README](../README.md) explains the app itself.

## Run it

Requires macOS 26 and the Xcode that [`.xcode-version`](../.xcode-version) names, the one CI runs, so a `make check` that passes on your Mac passes on CI too. `make check` stops first when your Mac's Xcode is another one, as when the App Store updates it on its own. To move to a newer Xcode, update your Mac's Xcode and the file together. The iPhone app also needs that Xcode's iOS platform (Xcode › Settings › Components).

```bash
make bootstrap   # installs XcodeGen, shellcheck and actionlint
make run         # builds and opens Ficha Dev, the development app
make install     # installs Ficha in /Applications
```

Ficha Dev is a separate app, with its own menu-bar icon, data and preferences, so it runs next to Ficha without touching your cards.

Ficha Dev's menu also has "Debug", to try a change in minutes: it loads sample cards, written by hand, moves Ficha Dev's time forward and checks for an appearance right away. Its time keeps running from there, stays ahead when Ficha Dev restarts, and Ficha Dev's `ficha` runs on it too. The real Ficha has no such menu and always runs on the system's time. To start Ficha Dev over, with no cards and on the system's time, quit it and move its folder, `~/Library/Application Support/Ficha Dev/`, to the Trash.

## On the iPhone

The iPhone app is on its way ([#97](https://github.com/lucastkacz/ficha/issues/97)). For now it's only Ficha Dev, which loads the sample cards the first time it opens and shows how many cards there are and how many are due. It needs iOS 26, on an iPhone: there's no iPad version. Its files are in `iPhone/`, and `make check` builds it for the simulator, as CI does.

Its appearances arrive as card notifications, which the app plans ahead ([ADR 0010](adr/0010-iphone-appearances-are-notifications-planned-ahead.md)): it asks whether it may send them the first time it opens, and plans again each time it opens or comes back to the foreground, when it also clears the ones iOS still shows. Each one brings a card, with buttons that show when you press and hold it: a new card whole, with "Got it", or a due card's front, with "Don't know", "Sort of" and "Know it". A button answers the card without opening the app or unlocking the iPhone, and the appearance's next card arrives right away, without sound. Tapping the notification only opens the app. To watch one arrive without waiting, press "Bring the next appearance now", under Debug, and lock the iPhone, or the simulator with ⌘L: the next planned appearance arrives 5 seconds later. While the app is in front, iOS doesn't show its notifications.

Debug also moves Ficha Dev's time forward, by the steps of the Mac's menu, so cards come due without waiting. Ficha Dev's time keeps running from there and stays ahead when the app opens again. Moving it counts the cards again and plans the appearances again, each notification at the real time that matches its appearance's time by Ficha Dev's: one whose time came already arrives a second later, while the app is in front, so to watch it, bring it with "Bring the next appearance now" and lock the iPhone. To start Ficha Dev over on the iPhone, with the sample cards and on the system's time, delete it and install it again.

It installs on your iPhone from the Mac, signed with your free Apple ID's Personal Team. The first time:

1. Xcode › Settings › Accounts: sign in with your Apple ID, which makes the Personal Team.
2. Write the team's ID in `iPhone/Local.xcconfig`, which git ignores, as a line like `DEVELOPMENT_TEAM = ABCDE12345`. The file is our own convention: `iPhone/Signing.xcconfig` includes it with Xcode's `#include?`, which skips a file that isn't there, as in CI. `defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier` shows the ID as the `teamID` next to `isFreeProvisioningTeam = 1`. That's an Xcode preference Apple doesn't document; if it's gone, Keychain Access shows the ID as the Organizational Unit of your "Apple Development" certificate.
3. Connect the iPhone with a cable, unlock it and trust the Mac. On the iPhone, turn on Settings › Privacy & Security › Developer Mode, which restarts it.

Then, each time, with the iPhone unlocked, on the cable or on the Mac's Wi-Fi, from the folder where you wrote `iPhone/Local.xcconfig`:

```bash
make install-iphone   # builds Ficha Dev for the iPhone paired with this Mac and installs it
```

After the first install, trust the developer on the iPhone, in Settings › General › VPN & Device Management, before opening it. With `iPhone/Local.xcconfig` written, Xcode's Run button signs it too, with the `iPhone` scheme.

A free Apple ID's apps run for 7 days. After that, iOS won't open Ficha Dev until you install it again, the same way, which keeps its cards. It also allows 3 such apps on the iPhone, and 10 App IDs a week: Ficha Dev takes one of each.

### In the simulator

After `make build-iphone`, these commands install Ficha Dev in the simulator that's running, open it, and show what it logged in the last 5 minutes:

```bash
xcrun simctl install booted ".build/DerivedData/Build/Products/Debug-iphonesimulator/Ficha Dev.app"
xcrun simctl launch booted com.lucastkacz.ficha.dev
xcrun simctl spawn booted log show --last 5m --info --predicate 'subsystem == "com.lucastkacz.ficha"'
```

- `booted` is the simulator that's running, which the Simulator app boots. With more than one running, simctl picks one of them, so name the one you want by its UDID instead, from `xcrun simctl list devices booted`.
- Without `--info`, the log leaves out the app's info lines, such as how many appearances it planned. Its first line, `getpwuid_r did not find a match for uid 501`, comes from the simulator and is harmless.
- The same command with `--predicate 'process == "usernotificationsd"'` shows iOS's side of the card notifications, among every app's. Each of Ficha Dev's requests that reached iOS is a `Forwarding addRequest: com.lucastkacz.ficha.dev` line, so `| grep -c 'Forwarding addRequest: com.lucastkacz.ficha.dev'` counts the notifications Ficha Dev handed iOS, which should add up to the app's "Planned … appearances" lines, plus one next card for each answer whose appearance goes on. That's iOS's own logging, which Apple doesn't document: a later iOS may word it otherwise.
- Locking the simulator, with ⌘L, makes the app active for a moment before it goes to the background, so what it does as it becomes active runs then too, such as planning again.
- To answer a card notification, swipe it left and press View, which shows its buttons. When Ficha Dev isn't running, iOS launches it in the background for the answer, so an answer logged from a new process ID while the app was running may mean it crashed: a bullet below says how to tell. Each answer logs `Recorded an answer from a card notification`, and whether the appearance goes on or is over. A rating for a card that isn't due within 20 minutes, how far an appearance looks ahead, is refused, and the log says why: "Bring the next appearance now" brings the next appearance early, with the cards it brings at its time. So to try the ratings, answer a new card with "Got it", which makes it due an hour later, press "Move forward 1 hour", under Debug, which takes the app's Due count above 0, and then bring the next appearance.
- To swipe a card notification away, swipe it left until it goes, or swipe it left and press Clear. iOS tells Ficha Dev, launching it in the background when it isn't running, and the app logs `Recorded a card notification swiped away`: its appearance is a snooze, and the next one comes after the separation, with the same cards. An appearance left alone is a snooze too, which the engine notes the next time the app plans. One that arrives while Ficha Dev is in front never shows, so it's one left alone: leave the app before it arrives.
- A crash writes nothing to the app's log, and iOS starts the app again for the next answer, so the log goes on from a new process ID as if nothing had happened. After each try, look for a crash report newer than the install: `ls -lt ~/Library/Logs/DiagnosticReports ~/Library/Logs/DiagnosticReports/Retired | grep 'Ficha Dev'` lists them newest first, as `Ficha Dev-<date>-<time>.ips` in the Mac's time, and each report's `pid` is the ID the crashed process has in the log. The file is a line of JSON, then the report as JSON, as Apple's [Interpreting the JSON format of a crash report](https://developer.apple.com/documentation/xcode/interpreting-the-json-format-of-a-crash-report) describes, and the thread with `"triggered": true` holds the frames where the app stopped. The command lists `Retired/` too because macOS moves the reports there later, as soon as a few hours after, which Apple doesn't document.
- To watch the app react to a change in its data, use one of its own debug tools: "Load the sample cards again", which [#107](https://github.com/lucastkacz/ficha/issues/107) will add, or, to watch it plan again meanwhile, "Bring the next appearance now" or one of the "Move forward" buttons. Claude's Bash commands can't reach the data otherwise, on purpose: the app's folder in the simulator has `Application Support/Ficha Dev/` in its path, and so has the name of the notification the engine posts when the database changes, which `notifyutil` would post. `.claude/settings.json` denies any Bash command with `Application Support/Ficha` in it, to keep Lucas's cards out of reach (CLAUDE.md), and that covers these too.

## The apps' texts

The texts each app shows live in its String Catalog, `App/Localizable.xcstrings` for the Mac's and `iPhone/Localizable.xcstrings` for the iPhone's, which the builds compile but never fill. After changing a text, run `make strings` and commit the catalog with the change. Xcode's export, which builds both apps, brings in the new texts with their comments, and drops the ones the code no longer has, or marks them stale when they have plural variations. `make check`, and so CI, fails while a catalog is out of date, and shows how it differs.

When a text with plural variations changes, the export brings the new text in plain, without them: move the variations over from the stale entry by hand, delete the stale entry, and run `make strings` again, which should change nothing.

## Refining

What you capture waits in the inbox, with the cards you flag and the follow-ups: what you ask about a card in the review panel. To turn it into cards, open Claude Code in this repository's folder and type `/refine`. Claude goes through it ten items at a time and, following [the content guide](content-guide.md), proposes cards for each capture, with Both ways on those whose back leads to their front, a fix or a burial for each flagged card, one you keep forgetting included, front first or back first, how to add each expansion to its card, and new cards with its card's tags for each follow-up. Point it to an image or a sound file on your Mac, and it proposes the card and the side it goes on. It writes only what you approve, through the installed Ficha's `ficha` command.

## The `ficha` command

Ficha ships with a command-line tool inside the app. Claude uses it to turn your captures into cards and to fix the cards you flag, and you can capture from a terminal with it:

```bash
/Applications/Ficha.app/Contents/Helpers/ficha capture "serendipia" --source "Un ensayo de Borges"
```

`ficha --help` lists its commands; each one prints JSON. `ficha unbury` brings back a card you buried. `ficha attach` puts an image or a sound file from your Mac on a side of a card, and `ficha detach` takes one off; `ficha approve`, `ficha approve-expansion` and `ficha fix` take them too. `ficha cards` says which cards go both ways, and `ficha approve` and `ficha fix` set it. `ficha restore` lists the copies in Ficha's Backups folder, newest first, and `ficha restore <copy>`, with a copy's name, restores it, as the Backups tab in Settings does: only while Ficha isn't running, since it would go on with the cards it has open. To type just `ficha`, add an alias to `~/.zshrc`:

```bash
alias ficha="/Applications/Ficha.app/Contents/Helpers/ficha"
```

The `ficha` inside Ficha Dev, which `make build` puts in `.build/DerivedData/Build/Products/Debug/Ficha Dev.app/Contents/Helpers/`, works on Ficha Dev's cards.

## A window's picture

`make render` draws one of the app's windows as a PNG, with Ficha Dev's sample cards, without showing anything on screen or taking the mouse or the keyboard, so it runs while you use your Mac:

```bash
make render ARGS="cards"
make render ARGS="cards --dark --click 520,66 --click 280,529 --out .build/render/by-due-dark.png"
make render ARGS="cards --key cmd+f --type serendip --out .build/render/search.png"
```

- The PNG goes to `.build/render/<window>-<light|dark>.png` unless `--out` says otherwise, at the display's scale.
- The cards are Ficha Dev's sample cards after twelve days of reviews, from 8 October 2026: some climbing at different paces, two sent back to the first step, one flagged with a note, one buried, and the rest new, with a capture waiting in the inbox, below the flagged card, for Convert to Card; and then three new cards made by hand, with no type and no capture, which the sidebar's No Type lists: the third row has Argentina's flag on its front and the Sun of May on its back, with a sound there too, a tone of 12 seconds.
- Each run opens the window as the app does the first time: at its first size, and the Cards window with Front, Media, Step and Due, newest first, whatever an earlier run clicked. macOS keeps the tool's preferences, where the app keeps a window's frame, columns and order, in your home's `Library/Preferences/Render.plist`, whatever `CFFIXED_USER_HOME` says, so the tool empties them as it starts and as it ends.
- Before the capture, the tool clicks, presses keys and types in the window, in the order its options give:
  - `--click <x>,<y>` clicks in points from the window's top-left corner: on a row of the table or the sidebar, to select it, or on a column's header, to sort by it. The modifier keys it holds down go before the point: in a table that selects several rows, `cmd+280,169` adds a row to the selection or takes it out, and `shift+280,217` selects the rows from the last one clicked to it. To find a point, render once and read it off the PNG.
  - `--key <keys>` presses a key, after the modifier keys it holds down: `cmd+f`, `cmd+a`, `escape`, `return`, `shift+tab`. The tool's usage lists the keys and modifiers it knows. As AppKit does, the key goes first to the window as a key equivalent, which a button's keyboard shortcut takes, then to the main menu, and then, when nothing took it, to what holds the focus. A key that nothing takes plays the system's alert sound, as in the app. The tool makes each press as the keyboard does, from the key's place on a US keyboard, and the Mac's keyboard layout says what it types: with a layout whose letters or digits are elsewhere, like AZERTY or Dvorak, it stops and says so.
  - `--type <text>` types into what holds the focus, like a text field after its shortcut or a click: `--type 'una palabra'` for text with spaces.
  - `--copy-image <flag|sun>` copies a picture the tool draws to its own pasteboard, for `--key cmd+v` to paste, since the tool can't drag a file: the flag, 1800 × 1125 pixels, comes in shrunk, and the sun has a transparent background. A card's side takes it once its image well has the focus, with `--key tab` from the side's text, as in `--key cmd+n --type '¿Qué país tiene esta bandera?' --key tab --copy-image flag --key cmd+v`.
  - `--copy-sound` copies a sound file the tool writes, a tone of 12 seconds, to its own pasteboard, as Finder copies a file, for `--key cmd+v` to paste. A card's side takes it once its sound well has the focus, the next `--key tab` after its image well.
  - A row of the sidebar below what the window shows, like No Type: click a row of the sidebar, then press the first letters of the one you want, each with `--key`, as in `--click 80,68 --key n --key o`. The sidebar selects that row and scrolls to it, as Finder's does. `--type` refuses it, since the focus isn't in a text field.
  - After each one, the tool prints what holds the focus, the first responder of the window or of its open sheet, so you can check that a shortcut went where it should: for a text field, its field editor, the field and its placeholder.
- The tool's main menu has only the Edit menu's shortcuts, copied from what SwiftUI gives the app, so ⌘Z, ⇧⌘Z, ⌘X, ⌘C, ⌘V and ⌘A undo, redo, cut, copy, paste and select all as they do there. The copy is our own, since the tool doesn't run the app's `App`: a command the app adds to the Edit menu with `.commands` needs adding to `editMenuItems` in `main.swift` too. It leaves out the app's other menus, whose shortcuts, like ⌘Q, ⌘H and ⌘M, quit the app, hide it or minimize its windows. Cut, Copy and Paste use a pasteboard of the tool's own, which it deletes when it's done, so it never pastes your clipboard into a picture nor changes it.
- A sheet, an alert or a confirmation the window opens, as SwiftUI's `.sheet`, `.alert` and `.confirmationDialog` do, goes below the desktop picture too, before macOS shows it, and the PNG shows it over the window, where macOS puts it. While it's open, the clicks, the keys and the typing go to it, as in the app, and the line the tool prints says when the focus is in it. A click outside it fails and says where it is: the window doesn't take clicks while its sheet is open.
- Buttons, SwiftUI's or an alert's, don't react to the tool's clicks: on macOS 26 a button takes its clicks through a gesture recognizer, which didn't fire for the tool's, whether sent to the button, to the window or to the recognizer. Press one through its keyboard shortcut instead, with `--key`: in a sheet, an alert or a confirmation, `return` presses the default button and `escape` Cancel, and hidden buttons answer theirs too. An alert's or a confirmation's button also takes the focus from a click, so `--click` on it and then `--key space` presses it.
- What the tool can't do yet, for a ticket that needs it to extend: right-click, as on a table's headers for their menu, or double-click; and keep a menu or a popover the window opens, like a picker's, below the desktop picture, as it does sheets.
- The window and its sheet act as the key window, with the title bar's buttons in color, but their selections and default buttons stay gray.
- The window is in English, the app's base language: the tool leaves the String Catalog out.
- The windows so far: `cards`, `cards-import`, the Cards window with its Import sheet on the preview of a file the tool writes, which `--key return` imports, `cards-import-anki`, the same on an Anki package the tool writes with SQLite and `zip`, `cards-anki-imported`, the Cards window once that package came in with its progress, on the card of the femur, which climbed since from the step the import put it on, `backups`, Settings on its Backups tab, `backups-failed`, the same once a backup failed, and `appearances`, `review-panel` and `ladder`, Settings on those tabs, with the settings that decide a card's progress, which the engine keeps, not Ficha's. The Import sheet before a file is chosen is `cards --key cmd+shift+i`, since the tool can't drive the open panel, and the Export sheet is `cards --key cmd+shift+e`, which stops before its save panel. The tool bundles no instructions for an AI, so the Import sheet's Copy Instructions for an AI says they're missing. For the Backups tab, the sample cards go in Ficha Dev's data folder in the tool's scratch home, with a backup each of the last eight days, of which it keeps seven, a copy before an update and a copy before a restore; the tool deletes the folder as it ends, so render these one at a time. Another window is one more case in `Window`, in `model(for:)` and in `window(_:model:)`, in `scripts/render/Sources/Render/main.swift`.
- The tool compiles the app's own files, through `scripts/render/Sources/Render/App`, a link to `App/`, so `make check` builds it: a change to the app that breaks it fails the check.

### The iPhone's screen

`make render-iphone` takes the iPhone app's opening screen as PNGs, light and dark. It builds Ficha Dev for the simulator, as `make build-iphone` does, makes a simulator of the newest iOS the Mac has and the first iPhone it offers, which simctl lists by generation, newest first, boots it without the Simulator app, takes the pictures in it, and deletes it, so the simulators you and other sessions use stay as they were. It takes about a minute, and shows nothing on screen:

```bash
make render-iphone
make render-iphone ARGS="--out .build/render/counts"
```

- The PNGs go to `.build/render/iphone-light.png` and `iphone-dark.png`, or `<path>-light.png` and `<path>-dark.png` with `--out <path>`, at the iPhone's scale: 1206 by 2622 pixels for an iPhone 17 Pro. The status bar shows 9:41 and a full battery, as Apple's pictures do.
- The tool opens Ficha Dev with `-FichaRendering`, which only Ficha Dev takes (`iPhone/Rendering.swift`). Then the app doesn't ask whether it may send notifications, since iOS's alert would cover its screen, and plans none, and once its screen is up it says so on its standard output. The tool waits for that, and then for the screen to stay the same for more than seven seconds, longer than a notification's banner stays: a new simulator shows one, "Ready for Apple Intelligence", in its first half minute.
- The simulator has `/tmp` and `/var/folders` of its own, so simctl writes the app's standard output to a scratch folder in `.build/render`, which the tool deletes with the simulator.
- When Ficha Dev doesn't open, doesn't say its screen is up within a minute, or its screen doesn't settle within another, the tool stops, says so, and keeps `<path>-<light|dark>-failed.png`, the screen then, and `-failed.log`, what the app logged. When another simctl command fails, it says what it couldn't do after simctl's own message. Either way, it deletes its simulator.
- Only the opening screen so far: the tool doesn't tap or type yet. `make check` doesn't run it, since a new simulator takes most of its minute.
- The commands are simctl's, which `xcrun simctl help` documents. A simulator for each run, the line the app says once its screen is up, and the wait for a still screen are our own: Apple's own way to drive an app and wait for its screen is a UI test target, with XCTest.

## The PR's pictures

A PR that changes what you see shows it in pictures, which `make render` draws for the Mac and `make render-iphone` for the iPhone, so you can decide from its body. They never reach `main`:

1. Copy the PNGs to `pr-images/<issue>/` and commit them on the PR's branch.
2. Remove the folder in the next commit.
3. Link each picture from the PR's body by the first commit's full SHA, with a width that fits the body, like 560 for the Cards window and 280 for the iPhone: `<img alt="Sorted by Due, a card selected" width="560" src="https://raw.githubusercontent.com/lucastkacz/ficha/<sha>/pr-images/<issue>/by-due-light.png">`. Say under them which commit they come from and that the next one removes it.

The squash merge leaves both commits off `main`, and GitHub keeps a PR's commits after its branch is deleted, so the links keep working.

## The README's pictures

The pictures in `docs/images/` show the app's own views with Ficha Dev's sample cards, captured without showing anything on screen. After a change to the review panel or the capture window, capture them again the same way, with a throwaway Swift package outside the repo:

1. The package depends on `Packages/FichaKit` by path, whose FichaData has the sample cards, and links in the `App/` files the views need, such as `ReviewPanelView.swift`, `ReviewPanelModel.swift` and, for the capture window, `CaptureView.swift` with `AppModel.swift` and what it uses. Its target defines `FICHA_DEV` and is isolated to the main actor, as the app's is.
2. It opens an engine on an in-memory database and a `ManualTimeSource`, loads `SampleCards`, meets five new cards through review now, one each time, and moves the time an hour and a second forward, so they're due.
3. Each picture is a borderless window with the review panel on a gradient, inside the same window so the Liquid Glass has something to show through. The card's front gets its back's height, the panel at the top, so the two pictures line up side by side. The capture window is a titled panel like `CaptureWindow`, captured with its shadow and drawn on the same gradient. So that it looks as it does with the keyboard, without taking it, the panel overrides `isKeyWindow` and AppKit's private `_hasActiveAppearance`: fine for a throwaway package, never for the app.
4. Each window goes below the desktop picture (`CGWindowLevelForKey(.desktopWindow) - 1`, ignoring the mouse), where macOS still draws it but nobody sees it, and `screencapture -x -l <window number>` captures it at the display's scale, with `-o` when the window's shadow should stay out. Run it with `CFFIXED_USER_HOME` set to a scratch folder, as `make render` does, so the app's files stay out of your home. Its preferences are the package's own, under its name, never Ficha Dev's.

The menu can't be captured this way: it only draws while it's open on screen, and then it takes the mouse and keyboard, so it needs Lucas's OK and a few seconds of his screen. The same package builds an `NSMenu` with the items `MenuContent` shows in the real Ficha, opens it with `popUp(positioning:at:in:)` over the gradient in a floating window, captures that window's rectangle with `screencapture -x -R` from a timer that runs while the menu is open, and closes the menu with `cancelTracking()`.
