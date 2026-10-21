# Developing Ficha

How to build and run Ficha, try a change with Ficha Dev, put Ficha Dev on the iPhone and watch it in the simulator, keep each app's texts in its String Catalog, refine cards with Claude, use the `ficha` command, and draw the app's windows as pictures. The [README](../README.md) explains the app itself.

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
- To answer a card notification, swipe it left and press View, which shows its buttons. When Ficha Dev isn't running, iOS launches it in the background for the answer. Each answer logs `Recorded an answer from a card notification`, and whether the appearance goes on or is over. A rating for a card that isn't due yet is refused, and the log says why: "Bring the next appearance now" brings the next appearance early, with the cards it brings at its time, so to try the ratings, bring it once the app's Due count is above 0.
- To watch the app react to a change in its data, use one of its own debug tools: "Load the sample cards again", which [#107](https://github.com/lucastkacz/ficha/issues/107) will add, or, to watch it plan again meanwhile, "Bring the next appearance now". Claude's Bash commands can't reach the data otherwise, on purpose: the app's folder in the simulator has `Application Support/Ficha Dev/` in its path, and so has the name of the notification the engine posts when the database changes, which `notifyutil` would post. `.claude/settings.json` denies any Bash command with `Application Support/Ficha` in it, to keep Lucas's cards out of reach (CLAUDE.md), and that covers these too.

## The apps' texts

The texts each app shows live in its String Catalog, `App/Localizable.xcstrings` for the Mac's and `iPhone/Localizable.xcstrings` for the iPhone's, which the builds compile but never fill. After changing a text, run `make strings` and commit the catalog with the change. Xcode's export, which builds both apps, brings in the new texts with their comments, and drops the ones the code no longer has, or marks them stale when they have plural variations. `make check`, and so CI, fails while a catalog is out of date, and shows how it differs.

When a text with plural variations changes, the export brings the new text in plain, without them: move the variations over from the stale entry by hand, delete the stale entry, and run `make strings` again, which should change nothing.

## Refining

What you capture waits in the inbox, with the cards you flag. To turn it into cards, open Claude Code in this repository's folder and type `/refine`. Claude goes through it ten items at a time and, following [the content guide](content-guide.md), proposes cards for each capture, a fix or a burial for each flagged card, and how to add each expansion to its card. It writes only what you approve, through the installed Ficha's `ficha` command.

## The `ficha` command

Ficha ships with a command-line tool inside the app. Claude uses it to turn your captures into cards and to fix the cards you flag, and you can capture from a terminal with it:

```bash
/Applications/Ficha.app/Contents/Helpers/ficha capture "serendipia" --source "Un ensayo de Borges"
```

`ficha --help` lists its commands; each one prints JSON. `ficha unbury` brings back a card you buried. To type just `ficha`, add an alias to `~/.zshrc`:

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
- The cards are Ficha Dev's sample cards after twelve days of reviews, from 8 October 2026: some climbing at different paces, two sent back to the first step, one flagged with a note, one buried, and the rest new.
- Before the capture, the tool clicks, presses keys and types in the window, in the order its options give:
  - `--click <x>,<y>` clicks in points from the window's top-left corner: on a row of the table or the sidebar, to select it, or on a column's header, to sort by it. The modifier keys it holds down go before the point: in a table that selects several rows, `cmd+280,169` adds a row to the selection or takes it out, and `shift+280,217` selects the rows from the last one clicked to it. To find a point, render once and read it off the PNG.
  - `--key <keys>` presses a key, after the modifier keys it holds down: `cmd+f`, `cmd+a`, `escape`, `return`, `shift+tab`. The tool's usage lists the keys and modifiers it knows. As AppKit does, the key goes first to the window as a key equivalent, which a button's keyboard shortcut takes, then to the main menu, and then, when nothing took it, to what holds the focus. A key that nothing takes plays the system's alert sound, as in the app. The tool makes each press as the keyboard does, from the key's place on a US keyboard, and the Mac's keyboard layout says what it types: with a layout whose letters or digits are elsewhere, like AZERTY or Dvorak, it stops and says so.
  - `--type <text>` types into what holds the focus, like a text field after its shortcut or a click: `--type 'una palabra'` for text with spaces.
  - After each one, the tool prints what holds the focus, the first responder of the window or of its open sheet, so you can check that a shortcut went where it should: for a text field, its field editor, the field and its placeholder.
- The tool's main menu has only the Edit menu's shortcuts, copied from what SwiftUI gives the app, so ⌘Z, ⇧⌘Z, ⌘X, ⌘C, ⌘V and ⌘A undo, redo, cut, copy, paste and select all as they do there. The copy is our own, since the tool doesn't run the app's `App`: a command the app adds to the Edit menu with `.commands` needs adding to `editMenuItems` in `main.swift` too. It leaves out the app's other menus, whose shortcuts, like ⌘Q, ⌘H and ⌘M, quit the app, hide it or minimize its windows. Cut, Copy and Paste use a pasteboard of the tool's own, which it deletes when it's done, so it never pastes your clipboard into a picture nor changes it.
- A sheet, an alert or a confirmation the window opens, as SwiftUI's `.sheet`, `.alert` and `.confirmationDialog` do, goes below the desktop picture too, before macOS shows it, and the PNG shows it over the window, where macOS puts it. While it's open, the clicks, the keys and the typing go to it, as in the app, and the line the tool prints says when the focus is in it. A click outside it fails and says where it is: the window doesn't take clicks while its sheet is open.
- Buttons, SwiftUI's or an alert's, don't react to the tool's clicks: on macOS 26 a button takes its clicks through a gesture recognizer, which didn't fire for the tool's, whether sent to the button, to the window or to the recognizer. Press one through its keyboard shortcut instead, with `--key`: in a sheet, an alert or a confirmation, `return` presses the default button and `escape` Cancel, and hidden buttons answer theirs too. An alert's or a confirmation's button also takes the focus from a click, so `--click` on it and then `--key space` presses it.
- What the tool can't do yet, for a ticket that needs it to extend: right-click, as on a table's headers for their menu, or double-click; and keep a menu or a popover the window opens, like a picker's, below the desktop picture, as it does sheets.
- The window and its sheet act as the key window, with the title bar's buttons in color, but their selections and default buttons stay gray.
- The window is in English, the app's base language: the tool leaves the String Catalog out.
- Only the Cards window so far. Another window is one more case in `Window` and in `window(_:model:)`, in `scripts/render/Sources/Render/main.swift`.
- The tool compiles the app's own files, through `scripts/render/Sources/Render/App`, a link to `App/`, so `make check` builds it: a change to the app that breaks it fails the check.

## The PR's pictures

A PR that changes what you see shows it in pictures, which `make render` draws, so you can decide from its body. They never reach `main`:

1. Copy the PNGs to `pr-images/<issue>/` and commit them on the PR's branch.
2. Remove the folder in the next commit.
3. Link each picture from the PR's body by the first commit's full SHA, with a width that fits the body, like 560 for the Cards window: `<img alt="Sorted by Due, a card selected" width="560" src="https://raw.githubusercontent.com/lucastkacz/ficha/<sha>/pr-images/<issue>/by-due-light.png">`. Say under them which commit they come from and that the next one removes it.

The squash merge leaves both commits off `main`, and GitHub keeps a PR's commits after its branch is deleted, so the links keep working.

## The README's pictures

The pictures in `docs/images/` show the app's own views with Ficha Dev's sample cards, captured without showing anything on screen. After a change to the review panel or the capture window, capture them again the same way, with a throwaway Swift package outside the repo:

1. The package depends on `Packages/FichaKit` by path, whose FichaData has the sample cards, and links in the `App/` files the views need, such as `ReviewPanelView.swift`, `ReviewPanelModel.swift` and, for the capture window, `CaptureView.swift` with `AppModel.swift` and what it uses. Its target defines `FICHA_DEV` and is isolated to the main actor, as the app's is.
2. It opens an engine on an in-memory database and a `ManualTimeSource`, loads `SampleCards`, meets five new cards through review now, one each time, and moves the time an hour and a second forward, so they're due.
3. Each picture is a borderless window with the review panel on a gradient, inside the same window so the Liquid Glass has something to show through. The card's front gets its back's height, the panel at the top, so the two pictures line up side by side. The capture window is a titled panel like `CaptureWindow`, captured with its shadow and drawn on the same gradient. So that it looks as it does with the keyboard, without taking it, the panel overrides `isKeyWindow` and AppKit's private `_hasActiveAppearance`: fine for a throwaway package, never for the app.
4. Each window goes below the desktop picture (`CGWindowLevelForKey(.desktopWindow) - 1`, ignoring the mouse), where macOS still draws it but nobody sees it, and `screencapture -x -l <window number>` captures it at the display's scale, with `-o` when the window's shadow should stay out. Run it with `CFFIXED_USER_HOME` set to a scratch folder, so it doesn't touch Ficha Dev's preferences.

The menu can't be captured this way: it only draws while it's open on screen, and then it takes the mouse and keyboard, so it needs Lucas's OK and a few seconds of his screen. The same package builds an `NSMenu` with the items `MenuContent` shows in the real Ficha, opens it with `popUp(positioning:at:in:)` over the gradient in a floating window, captures that window's rectangle with `screencapture -x -R` from a timer that runs while the menu is open, and closes the menu with `cancelTracking()`.
