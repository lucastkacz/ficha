# Tags sit inside tags by their names, as in Anki, and what's set on a tag holds for the tags inside it

A subject as broad as economía needs finer ones, such as economía › Argentina and economía › mundial (#346, grilled with #344 on 2026-10-29). Anki writes a tag inside another as `economía::Argentina`, shows its tags as a tree, and its search for a tag, like its study of a deck, takes in what sits inside. Ficha does the same: a tag's name carries the tags it sits inside, `economía::Argentina`, which the app shows as "economía › Argentina", and a parent exists through the tags inside it. Setting a tag aside, making it a priority tag or choosing it to sync holds for every tag inside it, also those made later, and so do its color and emoji for a tag that has none of its own. The user makes a tag inside another by writing its whole name on a card, by renaming it, or by dragging it onto the other in the Cards window's sidebar, which moves the tags inside it along. Renaming a tag to a name that exists merges the two, and the tag already there keeps what it has of its own.

## Considered options

- A parent kept apart from the name, as a link from each tag to another: a tag could move without changing its cards, but Export and Anki's imports would translate `::` both ways, and two devices moving tags at once could make one sit inside itself.
- Tags inside a parent with switches of their own, which the parent's don't reach: setting economía aside would leave economía › Argentina in the user's reviews, the opposite of what they meant, and Anki's parents take in their children.
- A tag that stays in the user's reviews inside a parent set aside: an exception to ADR 0011, where set aside wins over a card's other tags.

## Consequences

- ADR 0011 stands, counting the tags a card's tags sit inside: a card is set aside when one of its tags, or a tag one of them sits inside, is set aside, and the same goes for a priority tag. A tag inside another can be set aside, a priority tag or chosen to sync on its own; set aside still wins, so a priority tag inside a parent set aside brings nothing first.
- It changes ADR 0020 in one place: a new tag inside a tag chosen to sync syncs, where any other new tag waits until the user ticks it. The Sync tab lists the tags as a tree.
- A tag is renamed now, which v11's table ruled out. Renaming one, or moving it, changes every card that carries it or a tag inside it, and each card syncs that change as an edit to its tags, whose latest change wins (ADR 0017).
- An Anki deck comes in as one tag with all its levels, `Medicina::Anatomía`, in place of a tag for each level. An Anki note's tags with `::` came in whole already, and now show as a tree. Tags already imported a level at a time stay as they are, for the user to move.
- Export writes the whole name, `::` included, which Anki reads as its tree, and the `ficha` CLI shows and takes it the same way.
- The iPhone does the same, dragging included (ADR 0019).
- Standard practice: Anki's `::` names, its tree, a parent taking in what sits inside it, and renaming onto a name that exists. Our own: a tag taking its parent's color and emoji, and choosing a parent to sync taking in the tags inside it, also new ones.
