# The sidebar lists the tags the user pins, and All Tags holds every tag

Spec #363 listed every tag in the Cards window's sidebar as a tree, with a Set Aside section below it, and left a page of their own for tags out (#346). Lucas's first use of it, in the real Ficha's build 141 on 2026-10-29, found three things (#368): with many tags inside others, most from Anki decks, the tree became an endless list; a tag dropped between two others did nothing, where he expected it to land there; and nothing let him put his tags in an order of his own. So the sidebar now lists only the tags the user pins, in the order they choose, and ends with All Tags, a place in the Cards window that lists every tag as a tree, where the user pins, sets aside, prioritizes, renames, moves and deletes them. Finder's sidebar treats tags the same way: its Tags section lists the ones the user chose, in their order, with All Tags… at its end.

## Considered options

Lucas chose from four mockups, the three below and this one, in the grilling that followed on 2026-10-29.

- The sidebar as it was, alphabetical, where a tag dropped between two others moves to their level, with a field that filters the tree: the list stays long, and the order still isn't the user's.
- The sidebar as it was, in an order of the user's own across the whole tree: every tag keeps a place that syncs, and the list stays long.
- All Tags alone, with no tags in the sidebar: listing a subject's cards would always take a trip through All Tags.

## Consequences

- Which tags are pinned, and in what order, is one choice for all the user's devices, and syncs as a tag's switches do (ADR 0020). Nothing is pinned at first, after the update or for a new user, so the sidebar's Tags section shows All Tags… alone. A pinned tag stays pinned while no card carries it, as a set-aside tag stays listed, and when it's renamed or moved.
- It changes ADR 0021 in two places. A tag moves inside another, or out of it, in All Tags alone, where the user dragged it onto another in the sidebar, and the drop on the Tags section's title goes. And when two tags join, the tag is pinned if either was: the one thing a join takes from the tag that moves, so a tag never leaves the sidebar because the user moved it.
- The sidebar's pinned tags are a flat list, each tag inside another named by its whole path. Choosing a parent lists its cards and those of the tags inside it, as before. Dragging there only reorders them, or pins a tag dragged in from All Tags.
- The Set Aside section leaves the sidebar. All Tags keeps a set-aside tag in its place in the tree, grayed, with the tags inside it.
- All Tags' tree is alphabetical: the pinned tags' order is the only one of the user's own. Each tag shows how many cards it holds and how many are due, counting the tags inside it, and whether it's pinned, a priority tag or set aside. Which tags sync stays in the Sync tab alone (ADR 0020).
- The user can delete a tag now: it comes off every card that carries it or a tag inside it, and no card is deleted. Since Ficha has no undo, it asks first, saying how many cards carry them, and that a set-aside tag's cards come back to the user's reviews. Under selective sync, a card whose only chosen tag goes stops syncing, as when the user unticks it (ADR 0020). Clear Unused Tags deletes at once the tags no card carries, which stay listed only for something of their own.
- The menu bar's Prioritize submenu lists the pinned tags and the priority tags, then All Tags…, in place of every tag.
- The `ficha` CLI does all of it: it lists every tag with what it holds, and renames, moves, deletes, pins, orders, sets aside, prioritizes, colors and chooses tags to sync, and makes, renames and deletes the user's card types. It asks nothing first, since `/refine` shows Lucas each change before making it.
- The iPhone does the same (ADR 0019).
- Standard practice: Finder's Tags section in its sidebar with All Tags… at its end, and Anki's deleting a tag and clearing unused ones. Our own: the pinned tags' order syncing, a join keeping a pin, and each tag's count of due cards.
