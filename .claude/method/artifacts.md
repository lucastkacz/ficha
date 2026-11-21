# The user's artifacts

What `/preparar`, `/debate`, `/decision` and a change order show the user is an artifact: a web page they look at and touch, not text to read. Before writing one, load the `artifact-design` skill, and `artifact-capabilities` for its database. Publish it with the Artifact tool, and update the same artifact, by its URL, round after round. Keep its sources where the pliego says, so a later session can rebuild it.

## The page

- **One screen.** On a laptop the page doesn't scroll: a bar of numbered tabs on top (Inicio, a tab per round or piece, then the action), and panels that scroll inside. Below 900 px wide it becomes one scrolling column. It works on a phone, light and dark.
- **Shown, not told.** Each idea is a picture with a line or two beside it: a before and after, a diagram with its labels inside, a mock of the screen. A process is a short movie: the diagram builds step by step, a caption under it says what each step does, and Anterior, Reproducir and Siguiente drive it. It respects `prefers-reduced-motion`.
- **Linked.** A word of the method or the glossary is a button that shows its meaning on hover or tap. An issue shows its title and what it does, never its number alone. Each claim of fact links its source.
- **Light.** Add a simulator, a voice or a theme switch only when the topic needs it.

## Questions

A debate's round is up to five questions, one card each: the question in a line, then 2 to 4 options. Each option previews on the right as the user points at it: its picture, its mock, or its number from a simulation. One option is recommended, with the reason in a line. A free note follows, for what no option says.

## A decision

A home with the change in a table (today, and with the decision), and what stays open. A tab per piece: its before and after, what gets built as items marked ✓ decided, ◐ provisional or ○ open, the why in a line, and the agent's part folded, in English. A last tab, Aprobar: one button, and a note per piece.

## What the user answers

Answers, notes and the approval are kept in the artifact's database (capabilities `db` and `user`): a collection per artifact, one document per question, per piece's note, and `aprobacion` for the approval, `{approved, at, note}`. Claude reads them with the `ArtifactData` tool once the user says they answered, and takes each as the user's own word.

## Before sending it

Render it at a laptop's width and a phone's, light and dark, and look: nothing cut, nothing overlapping, every tab and control working, with no errors in the console. Then a line to the user with the link, and end the turn.
