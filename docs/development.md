# Developing Ficha

How to build and run Ficha, try a change with Ficha Dev, put Ficha Dev on the iPhone, refine cards with Claude, use the `ficha` command, and draw the app's windows as pictures. The [README](../README.md) explains the app itself.

## Run it

Requires macOS 26 and Xcode 26, with its iOS platform for the iPhone app (Xcode › Settings › Components).

```bash
make bootstrap   # installs XcodeGen
make run         # builds and opens Ficha Dev, the development app
make install     # installs Ficha in /Applications
```

Ficha Dev is a separate app, with its own menu-bar icon, data and preferences, so it runs next to Ficha without touching your cards.

Ficha Dev's menu also has "Debug", to try a change in minutes: it loads sample cards, written by hand, moves Ficha Dev's time forward and checks for an appearance right away. Its time keeps running from there, stays ahead when Ficha Dev restarts, and Ficha Dev's `ficha` runs on it too. The real Ficha has no such menu and always runs on the system's time. To start Ficha Dev over, with no cards and on the system's time, quit it and move its folder, `~/Library/Application Support/Ficha Dev/`, to the Trash.

## On the iPhone

The iPhone app is on its way ([#97](https://github.com/lucastkacz/ficha/issues/97)). For now it's only Ficha Dev, which loads the sample cards the first time it opens and shows how many cards there are and how many are due. It needs iOS 26, on an iPhone: there's no iPad version. Its files are in `iPhone/`, and `make check` builds it for the simulator, as CI does.

It installs on your iPhone from the Mac, signed with your free Apple ID's Personal Team. The first time:

1. Xcode › Settings › Accounts: sign in with your Apple ID, which makes the Personal Team.
2. Write the team's ID in `iPhone/Local.xcconfig`, which git ignores, as a line like `DEVELOPMENT_TEAM = ABCDE12345`. `defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier` shows it as the `teamID` next to `isFreeProvisioningTeam = 1`.
3. Connect the iPhone with a cable, unlock it and trust the Mac. On the iPhone, turn on Settings › Privacy & Security › Developer Mode, which restarts it.

Then, each time:

```bash
make install-iphone   # builds Ficha Dev for the connected iPhone and installs it
```

After the first install, trust the developer on the iPhone, in Settings › General › VPN & Device Management, before opening it. With `iPhone/Local.xcconfig` written, Xcode's Run button signs it too, with the `iPhone` scheme.

A free Apple ID's apps run for 7 days. After that, iOS won't open Ficha Dev until you install it again, the same way, which keeps its cards. It also allows 3 such apps on the iPhone, and 10 App IDs a week: Ficha Dev takes one of each.

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
make render ARGS="cards --dark --click 482,66 --click 280,529 --out .build/render/by-due-dark.png"
```

- The PNG goes to `.build/render/<window>-<light|dark>.png` unless `--out` says otherwise, at the display's scale.
- The cards are Ficha Dev's sample cards after twelve days of reviews, from 8 October 2026: some climbing at different paces, two sent back to the first step, one flagged with a note, one buried, and the rest new.
- `--click <x>,<y>` clicks before the capture, in points from the window's top-left corner: on a row, to select it, or on a column's header, to sort by it. SwiftUI's buttons don't react to these clicks. To find a point, render once and read it off the PNG.
- The window acts as the key window, with its title bar's buttons in color, but its selections stay gray.
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
