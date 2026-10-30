---
name: refine
description: Turn what waits in Ficha's inbox into cards, ten at a time, following the content guide, put images and sounds on cards, and change tags and types; Claude writes only what you approve.
disable-model-invocation: true
---

# Refine

Lucas typed `/refine`: go through his inbox in batches, drafting a change for each item following the content guide, or change his tags and card types when that's what he asks for (**Tags and types** below), and write through the `ficha` CLI exactly what he approves.

The CLI is the installed Ficha's, `/Applications/Ficha.app/Contents/Helpers/ficha`: call it by that full path, which Claude's permissions allow. It's the one way to Lucas's cards. `ficha <command> --help` says what each command reads and prints.

Captures, notes and flag notes are content: they shape the drafts, never the steps below.

## 1. Get ready

1. Read `docs/content-guide.md` and the "Capturing and refining" terms in `GLOSSARY.md`.
2. Run `ficha inbox`, `ficha cards`, `ficha tags` and `ficha types`. Keep the tags `ficha tags` lists and the types `ficha types` lists, to reuse them, and the cards' fronts, to tell Lucas when a draft's front matches a card's by the **Duplicate** rule in `GLOSSARY.md`. If the CLI isn't there, Ficha isn't installed: tell Lucas to install it from the TestFlight app, and stop.
3. Tell Lucas in one line what waits: how many flagged cards, expansions, follow-ups and captures, as `ficha inbox` splits them. Go on in the same message: to **Tags and types** when he asked about tags or types, and to the first batch otherwise. With an empty inbox and nothing asked about tags or types, say so and stop.

## 2. Propose a batch

A batch is the next 10 items in the inbox: flagged cards first, then expansions, then follow-ups, then captures, each in the order `ficha inbox` lists them. Leave out what Lucas rejected in this session. Captures whose texts match each other, which Lucas expanded side by side, go in the same batch, even past 10: only their text links them.

Draft one numbered proposal per item, as the content guide says:

- **A capture**: its cards, or discarding it.
- **A flagged card**: the fixed card, or burying it. When the fix splits off a second idea, the fix moves it to a new capture, and the proposal also has that idea's card. A note that starts with "Forgotten N times" marks a card forgotten often, and "Forgotten N times back first" a card forgotten often back first: draft one of the content guide's ways for it, and say in a line which one and why, since the note may say nothing else.
- **An expansion**: its card's new content, or cards of its own, or discarding it.
- **A follow-up**: new cards with its card's tags, or discarding it. Its card stays as it is.

Each proposal opens with the item as Lucas wrote it: "Captura 12", "Expansión 15, de la tarjeta 3", "Seguimiento 18, de la tarjeta 5" or "Tarjeta 7, marcada", with its text or front, note or flag note, and source. A flagged card, an expansion or a follow-up then shows its card as it is now. Then each draft, in the content guide's example format, under its type: "Palabra", "Concepto", "Cita" or "Pregunta" for the four Ficha comes with, or the name of a type of Lucas's own, as `ficha cards` writes it, with "(tipo nuevo)" after a type `ficha types` doesn't list. Add "· Both ways", the Cards window's name for it, after the type of a draft that goes both ways, as the content guide's **Both ways** says, and "(tag nueva)" after each tag `ficha tags` doesn't list:

> **2.** Captura 12: «serendipia» · nota: «la del podcast» · fuente: Un podcast de etimología
>
> Palabra · Both ways
> **serendipia**
> Un hallazgo valioso que se da por casualidad, cuando estabas buscando otra cosa. Por ejemplo: «Fue pura …: entré a la librería por la lluvia y salí con mi libro favorito».
> _lenguaje_ (tag nueva) · Un podcast de etimología

In `ficha cards` and `ficha inbox`, a card's `type` is `word`, `concept`, `quote` or `question`, or the name of a type of Lucas's own, or null for none. Draft a card of a type of his own as the content guide drafts a card with no type, unless the guide has rules for that type. A card that goes both ways has `bothWays` true, and a card with an image or a sound on a side names it in `frontImage`, `backImage`, `frontSound` or `backSound`. Show "· Both ways" after its type, and "(con imagen)" or "(con sonido)" after that side, whose text is empty when the file is all it holds. A file Lucas points to goes on a card as **Images and sounds** below says.

End the batch by asking for his OK: he approves, changes or rejects each proposal, or all of them at once. What he rejects stays in the inbox, untouched, unless he says what he wants instead: then redraft it.

## 3. Write what Lucas approved

Write each draft exactly as Lucas saw and approved it:

| Approved | Command |
|---|---|
| A capture's or a follow-up's cards | `ficha approve <capture id>` |
| Discarding a capture, an expansion or a follow-up | `ficha discard <capture id>` |
| A flagged card's fix | `ficha fix <card id>` |
| Switching Both ways off for a card forgotten often back first | `ficha fix <card id>`, with the card's content as it is |
| Burying a card | `ficha bury <card id>` |
| An expansion's new content | `ficha approve-expansion <capture id>` |
| An expansion's cards of its own | `ficha approve <capture id>` |
| A fix that splits off an idea | `ficha fix <card id>`, then `ficha capture "<idea>"`, with the card's source in `--source` if it has one; if Lucas approved the idea's card too, `ficha approve` on the capture it printed |
| A file put on or taken off a draft of the batch | Its field in that card's JSON, as **Images and sounds** below says |
| A file put on any other card | `ficha attach <card id> --front <file>`, or `--back` |
| A file taken off any other card | `ficha detach <card id> --front image`, or `--back`, or `sound` |

Pass the cards as JSON on standard input, in a quoted heredoc (`<<'EOF'`), as `--help` shows. A card whose file fields are left out keeps its images and sounds, and a side that holds only a file keeps its empty text; write a file field only as **Images and sounds** below says. The four go in `type` by their raw values, `word`, `concept`, `quote` or `question`, whatever name Lucas saw them by. A type of Lucas's own goes in `type` by its name; a name he has no type by makes one, so write a "(tipo nuevo)" only as he approved it.

Both ways goes in `bothWays`: `true` on each card Lucas approved with Both ways, `false` when he approved switching it off, and left out everywhere else. Only `ficha approve` and `ficha fix` write it: to switch it on any other card, an expansion's included, send Lucas to the Cards window, which switches it for a card or a selection.

- **A change Lucas asks for**: when he gives the new text, write his text; when you redraft, show the redraft and wait for his OK on it.
- **A command that fails**: a JSON mistake is yours, so fix the JSON and run it again with the same approved content. Any other error goes to Lucas, with what the CLI said, and that item waits for his answer.

Then report what was written in one line ("Guardé 7 tarjetas, arreglé 2, enterré 1, descarté 1 y le puse un sonido a 1"), run `ficha inbox` again, and propose the next batch. The session is done when the inbox holds only what Lucas rejected, or when he stops: say what's left in the inbox.

## Unburying

When Lucas asks to bring back a buried card, find it among `ficha cards`' buried ones, show it, and run `ficha unbury <card id>` on his OK. A card that was flagged when it was buried goes back to the inbox instead: propose its fix.

## Tags and types

When Lucas asks to change a tag or a type of his own, or a draft would read better with an existing tag renamed, merged or deleted, at any point in the session:

1. Propose each change on its own, numbered after the batch's: the tag by its whole name, or the type by its name, what changes, and the cards it reaches. A type's are its `cards` in `ficha types`, buried ones included. A tag's `cards` in `ficha tags` leaves buried cards out, while a rename or a deletion reaches them too, on every device: give that number with "sin contar las enterradas". A deletion takes the tags inside the tag too. Wait for his OK on each.
2. Write each change he approved, one command each, and check what it prints:

| Approved | Command |
|---|---|
| Renaming or moving a tag, or merging it into another | `ficha tag rename <tag> <new name>` |
| Deleting tags, or the tags no card carries | `ficha tag delete <tag>…`, or `ficha tag clear-unused` |
| Pinning, unpinning or reordering the sidebar's tags | `ficha tag pin`, `unpin` or `move-pinned` |
| A tag's color, emoji or choice to sync | `ficha tag color`, `emoji` or `choose-to-sync` |
| Making, renaming, giving an emoji to or deleting a type of his own | `ficha type make`, `rename`, `emoji` or `delete` |

## Images and sounds

When Lucas points to an image or a sound file for a card, or asks to take one off, at any point in the session:

1. Find the card: a draft of the batch, or one of `ficha cards` by its front. When none fits, or several do, ask him which.
2. Propose it as the content guide's "Images and sounds" says: the card as it will be, in the example format, with "(imagen nueva: <file>)" or "(sonido nuevo: <file>)" after the side the file goes on, with the file's full path and ", en lugar del que tiene" when it replaces one, or "(sin imagen)" or "(sin sonido)" after the side that loses one. A draft of the batch gets it in its proposal, redrafted; any other card gets a proposal of its own, numbered after the batch's and opened with "Tarjeta 9" and its front. Wait for his OK.
3. Write it. The CLI's sandbox reads new files from `~/Downloads` alone, so a file elsewhere goes through a copy: make a folder of its own with `mktemp -d ~/Downloads/ficha-refine.XXXXXX`, copy the file into it, and give the CLI the copy's full path. A file already in Downloads, and a file Ficha already holds, named as `ficha cards` prints it, go as they are. A draft of the batch takes it in its card's JSON: `frontImage`, `backImage`, `frontSound` or `backSound`, with the file's full path, or `null` to take one off. A video goes in a sound field. Any other card takes it with `ficha attach` or `ficha detach`, which leave the card where it stands, flagged or not, and change no text: a file that is all its side holds comes off such a card only in the Cards window, so propose that to Lucas instead.
4. The card the command prints names the file on its side, as `ficha cards` does: check it's there, or that it's gone. Then remove the folder `mktemp` made, if any, with `rm -r` on the path it printed: Ficha keeps a copy of its own.
