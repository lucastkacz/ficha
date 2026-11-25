# The user's artifacts

What `/preparar`, `/debate`, `/decision`, `/recorrida` and a change order show the user is an artifact: a web page they look at and touch, on their phone first, built from the page kit, [`kit/`](kit/README.md). Before writing one, load the `artifact-design` skill for the Artifact tool's rules; the kit holds the look and the database's code. Publish it with the Artifact tool, and update the same artifact, by its URL, round after round. Keep its sources where the pliego says, so a later session can rebuild it.

## The page

- **Cards you swipe.** The page never scrolls. At most five tabs, each a deck of cards, one idea per card, in at most 40 words outside its drawings.
- **Shown, not told.** What doesn't fit in a line is a picture: a before and after, a diagram with its labels inside, a mock of the screen, a count.
- **A movie for a process, and only there**: steps that happen in an order, such as how a change reaches the user, build up in a diagram, 3 to 8 of them, each with its caption.
- **Linked.** A word of the method or the glossary shows its meaning on tap or hover; an issue, its title, linked, and what it does. Each claim of fact links its source.
- **Light.** A simulator, a voice or a theme switch only when the topic needs it.

## Questions

A debate's round is up to five questions, a card each: the question in a line, then 2 to 4 options of a line each, each with its preview: its picture, its mock, or its number from a simulation. One option is recommended, with the reason in a line, and a free note follows, for what no option says.

## A decision

A home with the change, today and with the decision, and what stays open. A deck per piece, in one tab: its before and after, what gets built as items marked ✓ decided, ◐ provisional or ○ open, the why in a line, and the agent's part folded, in English. A last tab, Aprobar: one button, and a note per piece.

## A change order

One tab: the plano before and after, with what changes marked in both; why, in a line; the node's issues it touches, each with what changes for it; and Aprobar, with a note.

## A recorrida

One tab, made to be skimmed, asking nothing, so with no database. First the answer: since when, what changed in two lines, and the next step with its command and why. Then a card for each of the command's steps 2 to 4, in its order: what was done, a PR each, newest first; where it stands, the order of the work as a line of steps with the one it's on marked, and the open issues counted by area; and what comes after the next step.

## What the user answers

Answers, notes and the approval are kept in the artifact's database (capabilities `db` and `user`): a collection per artifact, one document per question, per piece's note, and `aprobacion` for the approval, `{approved, at, note}`. Claude reads them with the `ArtifactData` tool once the user says they answered, and takes each as the user's own word.

## Before sending it

1. Run the inspection on the page ([`kit/README.md`](kit/README.md), The inspection), and fix what it lists until it passes.
2. Look at its pictures: each card on a phone, and each tab in dark. A drawing that reads wrong fails too.
3. Publish it with the kit beside it ([`kit/README.md`](kit/README.md), Publishing), tell the user in a line with the link, and end the turn.

Done when the inspection passes, its pictures read right, and the user has the link.
