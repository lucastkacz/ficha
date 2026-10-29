# Selective sync: the user can sync only the cards with the tags they choose, and choosing never deletes

ADR 0017 syncs every card. Lucas has many tags, most from Anki decks he imported, some heavy with images and sounds, and wants only the ones he's using in his iCloud and on his iPhone, where he might review only the world maps (the grilling of selective sync before #318, 2026-10-28). So sync can now carry only the cards with the tags the user chooses: every card syncs by default, as before, and in the Sync tab the user can switch to selective sync, so only the cards with the tags they tick go up to iCloud and reach their other devices. The choice is by tags, since subjects are tags (ADR 0011) and an Anki deck comes in as a tag for each level of its name.

It changes three parts of ADR 0017, which now hold for the cards that sync alone: what syncs, a deletion reaching every device, and the other devices taking a restored copy in place of theirs. It also reverses #317's decision not to build cards or files that stay on one device.

## Considered options

- Anki's way: it syncs the whole collection, with a switch on each device that leaves out images and sounds. It would spare iCloud the gigabytes, but cards like the world maps are images, and would reach the iPhone blank.
- Tags set aside on one device alone: the iPhone would show only the world maps, but every card would still go up to iCloud, and set aside would stop being one choice for every device (ADR 0011).
- A sync switch on each tag, on by default: every deck imported would go up on its own.
- A choice of its own on each device: a card one device sends could come to another where its tag isn't chosen, which would never send its edits back.
- When a tag stops syncing, its cards leave every device but the one where the user changed it: unticking it on the iPhone would delete them from the Mac. Or they leave the iPhone and stay on the Mac: it treats the two apart (ADR 0019), and someone with an iPhone and an iPad would lose them.

## Consequences

- Whether sync takes every card or only the chosen tags, and which tags, is one choice for all the user's devices: it syncs, as set aside and priority do, and any device changes it. Whether a tag syncs is a switch of its own, beside ADR 0011's priority and set aside, so a priority tag or a tag set aside can sync or not.
- ADR 0011 stands: a device reviews every card it holds, and nothing reviews one tag alone. A device that syncs only the world maps holds only those, besides the cards made on it.
- Under selective sync, a card syncs when one of its tags is chosen, a card with no tag doesn't, and a new tag, such as an import brings, isn't chosen until the user ticks it.
- Everything that isn't a card syncs whatever the choice: captures, tags and the settings that decide progress. An expansion or a follow-up of a card that doesn't sync stays with its card. A card's review log, flag and burial go with it, and an image or a sound goes up when a card that syncs uses it.
- Choosing never deletes. A card that stops syncing leaves iCloud, and each device keeps its copy, which syncs no more; if it syncs again, the copies join as after a long time offline (ADR 0017). So a record that leaves iCloud because its card stopped syncing isn't a deletion to the other devices, and a card deleted while it doesn't sync is deleted on that device alone. As built in #355, the record stays in iCloud as one that left, holding the card's tags alone, which tell the other devices why it left, in whichever order they hear it and the change to the choice. Its content and files leave, and each entry of its review log stays as a record that left, holding nothing. Since no device can tell whether another still holds the card, these records stay until the card syncs again or the user deletes Ficha's data in iCloud, even once every device deleted it.
- A restore that replaces iCloud's copy (ADR 0017) sends only the cards that sync, and a device that takes it in place of its own keeps the cards that don't.
- Under selective sync, the Sync tab lists every tag with a checkbox and what its cards' images and sounds weigh, with no alert. #317's lines count only what syncs: the Import sheet's, the files of the cards that would sync; the line while sync is off, the files of the cards that sync.
- A device that already holds cards and has never synced starts with sync off, and Settings says why and what turning it on sends, so the user chooses the tags before anything goes up, as Lucas does on his Mac in #318. A new install, with no cards, starts with sync on, as before.
- The iPhone gets the same when it comes (ADR 0019).
- Standard practice: none. Anki syncs whole collections, and its manual advises against profiles for splitting one's own content. Our own: all of it.
