# The user's artifacts

What `/preparar`, `/debate`, `/decision`, `/recorrida` and a change order show the user is a page built from the page kit, [`kit/`](kit/README.md), for their phone first. Load the `artifact-design` skill before writing one, publish it with the Artifact tool, and update the same artifact, by its URL, each time. Its sources go where the pliego says, so a later session can rebuild it.

## The page

- **Cards you swipe.** At most five tabs, each with a deck of cards, or several picked from a row of chips; one idea per card, in at most 40 words outside its drawings. The page never scrolls.
- **Shown, not told.** What doesn't fit in a line is drawn: a before and after, a diagram with its labels inside, a mock of the screen, a count.
- **A movie only for a process**: steps that happen in an order, 4 to 8, each with its caption.
- **Linked.** A word of the method or the glossary shows its meaning on a tap; an issue, its title, linked, and what it does. Each claim of fact links its source.
- **Light.** A simulator or a voice only when the topic needs it. A screen mock or a simulator is an artifact of its own, made as the pliego's How it's drawn says, which a preview links; the inspection measures the kit's pages.

## Each page's pieces

| Page | Tabs | Pieces |
|---|---|---|
| `/preparar` | Five | As its skill lists them |
| A debate | Home, rounds, close | The idea's issue; a deck of questions per round; the close as items |
| A decision | Home, pieces, Aprobar | A change; a deck per piece: its before and after, items, the why, a fold for the agent; Aprobar, with a note per piece |
| A change order | One | The plano's before and after; the node's issues it touches, as a change; Aprobar, with a note |
| A recorrida | One, with no database: a deck for the answer, open first, and one for each of its steps 2 to 4 | The answer: since when, what changed, the next step and its command; and the days since, as a drawing, each PR by a short name on its day. Step 2: a card per PR merged, with what the step gathers for it: what it built, drawn, as a before and after when it changed what the user sees; how it went, as badges; what it left the user, counted, which step 4's card lists; and a card for the issues without a PR. Step 3: steps, bars by area and trees by node. Step 4: the next step, a card of what the PRs left the user, and the rest |

## Questions

Up to five a round, a card each: the question in a line; 2 to 4 options of a line each, each with its preview, its picture, its mock or its number; the one recommended, with why in a line; and a free note.

## What the user answers

Answers, notes and the approval go in the artifact's database (capabilities `db` and `user`): a collection per artifact, a document per question and per piece's note, and `aprobacion` for the approval, `{approved, at, note}`. Claude reads them with the `ArtifactData` tool once the user says they answered, each as the user's own word.

## Before sending it

Each time a command publishes a page, the first time or again:

1. Run the inspection on it ([`kit/README.md`](kit/README.md), The inspection), and fix what it lists until it passes.
2. Look at its pictures: each card on a phone, and each tab in dark. A drawing that reads wrong fails too.
3. Publish it with the kit beside it ([`kit/README.md`](kit/README.md), Publishing), tell the user in a line with the link, and end the turn.

A page made before the kit takes it the next time its command publishes it.

Done when the inspection passes, its pictures read right, and the user has the link.
