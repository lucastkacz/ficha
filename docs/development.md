# Developing Ficha

How to build and run Ficha, try a change with Ficha Dev, refine cards with Claude, and use the `ficha` command. The [README](../README.md) explains the app itself.

## Run it

Requires macOS 26 and Xcode 26.

```bash
make bootstrap   # installs XcodeGen
make run         # builds and opens Ficha Dev, the development app
make install     # installs Ficha in /Applications
```

Ficha Dev is a separate app, with its own menu-bar icon, data and preferences, so it runs next to Ficha without touching your cards.

Ficha Dev's menu also has "Debug", to try a change in minutes: it loads sample cards, written by hand, moves Ficha Dev's time forward and checks for an appearance right away. Its time keeps running from there, stays ahead when Ficha Dev restarts, and Ficha Dev's `ficha` runs on it too. The real Ficha has no such menu and always runs on the system's time. To start Ficha Dev over, with no cards and on the system's time, quit it and move its folder, `~/Library/Application Support/Ficha Dev/`, to the Trash.

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

## The README's pictures

The pictures in `docs/images/` show the app's own views with Ficha Dev's sample cards, captured without showing anything on screen. After a change to the review panel or the capture window, capture them again the same way, with a throwaway Swift package outside the repo:

1. The package depends on `Packages/FichaKit` by path and links in the `App/` files the views need, such as `ReviewPanelView.swift`, `ReviewPanelModel.swift`, `SampleCards.swift` and, for the capture window, `CaptureView.swift` with `AppModel.swift` and what it uses. Its target defines `FICHA_DEV` and is isolated to the main actor, as the app's is.
2. It opens an engine on an in-memory database and a `ManualTimeSource`, loads `SampleCards`, meets five new cards through review now, one each time, and moves the time an hour and a second forward, so they're due.
3. Each picture is a borderless window with the review panel on a gradient, inside the same window so the Liquid Glass has something to show through. The capture window is a titled panel like `CaptureWindow`, captured with its shadow and drawn on the same gradient. So that it looks as it does with the keyboard, without taking it, the panel overrides `isKeyWindow` and AppKit's private `_hasActiveAppearance`: fine for a throwaway package, never for the app.
4. Each window goes below the desktop picture (`CGWindowLevelForKey(.desktopWindow) - 1`, ignoring the mouse), where macOS still draws it but nobody sees it, and `screencapture -x -l <window number>` captures it at the display's scale, with `-o` when the window's shadow should stay out. Run it with `CFFIXED_USER_HOME` set to a scratch folder, so it doesn't touch Ficha Dev's preferences.

The menu can't be captured this way: it only draws while it's open on screen and taking the mouse and keyboard.
