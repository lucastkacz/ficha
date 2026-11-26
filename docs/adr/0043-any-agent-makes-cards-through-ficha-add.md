# Any agent makes cards through `ficha add`

ADR 0042 took the refine sessions out, and `ficha add` with them, since it had been planned for those sessions. The same afternoon, on 2026-11-26, Lucas asked whether any agent, on any Mac where Ficha is installed, could still make him a small deck, such as one to learn the colors, since he understood that everything in Ficha could be driven outside its windows. Once Capture goes (#540), the CLI's capture and approve go with it, and without `ficha add` no agent could make a card. He chose to bring it back. It changes ADR 0042 in part, whose `ficha add` went.

- **`ficha add` comes back, for any agent.** It reads the cards as JSON on standard input, the same list `ficha approve` reads, and saves them as new, straight into their decks, with no capture (#534).
- **An agent makes a deck from a terminal.** On a Mac where Ficha is installed, an agent that runs commands there, such as Claude Code, makes the deck with `ficha deck`, its cards with `ficha add`, and puts a picture or a sound from the Downloads folder on a side (ADR 0018). With sync on, the deck reaches the user's other devices.
- **No skill.** What an agent needs is the CLI's own help, `ficha --help` and each command's; Lucas asks in his words, in a session he starts.
- **Agents' scratch runs make their cards the same way** once #540 takes capture and approve out.

## Considered options

- Cards only in the Cards window: no agent could make a deck.
- A connector, such as an MCP server inside Ficha: a second way in to keep beside the CLI, which already is one, and agents that run commands reach the CLI without it.

## Consequences

- #534 reopens. The code its draft PR wrote, closed when ADR 0042 took `ficha add` out, comes back on a new branch, since `main` moved under it.
- #540's replanteo no longer has to pick a way for agents' scratch runs to make cards: it's `ficha add`.
- `PLIEGO.md`'s Hands-free line on the CLI names `ficha add` as the way cards come in once captures and approvals go.
- Standard practice: a command-line tool that reads and prints JSON, which agents drive. Our own: the tool inside the app with a sandbox of its own (ADR 0018), and no connector.
