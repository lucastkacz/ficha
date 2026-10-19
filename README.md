# Ficha

A macOS menu-bar app that shows you a tiny flashcard every so often (a word, a concept, a quote or a question) and spaces each card by how well you know it. Answering takes seconds, and everything stays on your Mac.

Ficha follows your Mac's language. For now it's in English; Spanish comes later.

Status: early development.

## Run it

Requires macOS 26 and Xcode 26.

```bash
make bootstrap   # installs XcodeGen
make run         # builds and opens Ficha Dev, the development app
make install     # installs Ficha in /Applications
```

Ficha Dev is a separate app, with its own menu-bar icon, data and preferences, so it runs next to Ficha without touching your cards.

Ficha Dev's menu also has "Debug", to try a change in minutes: it loads sample cards, written by hand, moves Ficha Dev's time forward and checks for an appearance right away. Its time keeps running from there, stays ahead when Ficha Dev restarts, and Ficha Dev's `ficha` runs on it too. The real Ficha has no such menu and always runs on the system's time. To start Ficha Dev over, with no cards and on the system's time, quit it and move its folder, `~/Library/Application Support/Ficha Dev/`, to the Trash.

## Reviewing

"Review now", in the menu, shows how many cards are due and opens the review panel with up to five cards: the due ones, lowest step first, and a new card when there's room, up to five new cards a day. A new card shows whole, marked "New": press Enter. Any other card shows its front: Space flips it, and 1, 2 or 3 rate it ("Don't know", "Sort of", "Know it"). Esc closes the panel, and every action can also be clicked. The menu also says how many cards you've learned and how much waits in the inbox.

M flags a card with a note on what to fix: it leaves your reviews and waits in the inbox until a refine session fixes it, and then it goes back to its step. E buries a card: it never shows up again, and keeps its review log, and `ficha unbury` brings it back. ⌘Z undoes what you did with the last card, one card at a time, while the panel is open: a rating, a flag or a bury.

The review panel also shows up on its own when cards are due, between 9:00 and 22:00, with the same cards plus those due within the next 20 minutes. With nothing due, one new card is enough. It comes at least 30 minutes after the last panel with cards closed, never while your Mac or its screens sleep, and 2 minutes after they wake. It shows up without the keyboard, so it doesn't catch what you're typing, and takes it once you've been idle for 5 seconds. Esc snoozes it, and left untouched for 10 minutes it closes on its own: either way, its cards stay due.

## Refining

What you capture waits in the inbox, with the cards you flag. To turn it into cards, open Claude Code in this repository's folder and type `/refine`. Claude goes through it ten items at a time and, following [the content guide](docs/content-guide.md), proposes cards for each capture, a fix or a burial for each flagged card, and how to add each expansion to its card. It writes only what you approve, through the installed Ficha's `ficha` command.

## The `ficha` command

Ficha ships with a command-line tool inside the app. Claude uses it to turn your captures into cards and to fix the cards you flag, and you can capture from a terminal with it:

```bash
/Applications/Ficha.app/Contents/Helpers/ficha capture "serendipia" --source "Un ensayo de Borges"
```

`ficha --help` lists its commands; each one prints JSON. To type just `ficha`, add an alias to `~/.zshrc`:

```bash
alias ficha="/Applications/Ficha.app/Contents/Helpers/ficha"
```

The `ficha` inside Ficha Dev, which `make build` puts in `.build/DerivedData/Build/Products/Debug/Ficha Dev.app/Contents/Helpers/`, works on Ficha Dev's cards.

## How it's built

Ficha is built by AI agents (Claude Code) with [Matt Pocock's skills](https://github.com/mattpocock/skills). Lucas brings the ideas and the decisions; the agents turn them into specs, tickets, code and pull requests. [`CLAUDE.md`](CLAUDE.md) holds the rules they follow, and [`CODING_STANDARDS.md`](CODING_STANDARDS.md) how the code is written.
