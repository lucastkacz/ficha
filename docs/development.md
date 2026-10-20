# Developing Ficha

How to build and run Ficha, try a change with Ficha Dev, refine cards with Claude, and use the `ficha` command. The [README](../README.md) explains the app itself.

## Run it

Requires macOS 26 and Xcode 26.

```bash
make bootstrap   # installs XcodeGen
make run         # builds and opens Ficha Dev, the development app
make install     # installs Ficha in /Applications
```

`make check` runs everything CI runs, and must pass before every pull request.

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

The pictures in `docs/images/` show the app's own views with Ficha Dev's sample cards. They were captured without showing anything on screen: a throwaway Swift package compiled the app's view files against FichaKit, with an in-memory database, and placed each window below the desktop picture, where macOS still draws it, Liquid Glass included, for `screencapture -l <window number>` to capture it. After a change to the review panel or the capture window, capture them again the same way.
