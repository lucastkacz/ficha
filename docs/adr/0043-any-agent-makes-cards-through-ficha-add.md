# Any agent makes cards through ficha add

ADR 0042 took the refine sessions out, and `ficha add` with them, since it had been planned for those sessions. The same afternoon, on 2026-11-26, Lucas asked whether any agent, on any Mac where Ficha is installed, could still make him a small deck, such as one to learn the colors, since he understood that everything in Ficha could be driven outside its windows. Once Capture goes (#540), the CLI's capture and approve go with it, and without `ficha add` no agent could make a card. He chose to bring it back, finishing the draft PR that had built it. It changes ADR 0042 in part, whose `ficha add` went; ADR 0041 in part, whose `ficha add` served refine sessions alone; and ADR 0012 in part, whose cards came in by hand or from a file.

- **`ficha add` comes back, for any agent.** It reads the cards as JSON on standard input, the same list `ficha approve` reads, and saves them as new, straight into their decks, with no capture (#534).
- **An agent makes a deck from a terminal.** On a Mac where Ficha is installed, an agent that runs commands there, such as Claude Code, makes the deck with `ficha deck make`, or through the deck each card names, its cards with `ficha add`, and puts a picture or a sound from the Downloads folder on a side with `ficha add` or `ficha attach` (ADR 0018). The tool is inside the app, at `Ficha.app/Contents/Helpers/ficha`, since App Review's guideline 2.4.5(ii) bars installing it in a shared place (`docs/research/platform.md`): the user gives the agent that path, or an alias (`docs/development.md`). With sync on, the deck's cards reach the user's other devices, once it, or a deck it sits inside, is chosen when only chosen decks sync (`ficha deck choose-to-sync`).
- **No skill.** What an agent needs is the tool's path and its own help, `ficha --help` and each command's; the user asks in their words, in a session they start.
- **Agents' scratch runs make their cards the same way** once #540 takes capture and approve out (provisional).

## Considered options

- Cards only in the Cards window: no agent could make a deck.
- A connector, such as an MCP server inside Ficha: a second way in to keep beside the CLI, which already is one for an agent that runs commands on the Mac. An agent with no terminal there, such as one in a chat app or on a phone, reaches neither, since Ficha makes no network connections of its own (ADR 0001, ADR 0017).

## Consequences

- #534 reopens. Its code comes back from draft PR #543, at 1034a42 on its branch, with `main` merged in, as #534 says.
- #540 waits for #534 again, and its replanteo no longer picks a way for agents' scratch runs to make cards: it's `ficha add` (provisional).
- `PLIEGO.md`'s Hands-free line on the CLI names `ficha add` as the way cards come in once captures and approvals go.
- The nodes that build #534 and #540 change what `docs/app-review-notes.md` tells App Review the command-line tool does.
- Standard practice: a command-line tool that reads and prints JSON, which agents drive. Our own: the tool inside the app with a sandbox of its own (ADR 0018), and no connector.
