# The cards sync through the user's own iCloud, and nothing else leaves the device

Ficha sells on the App Store for the Mac and the iPhone together (#160), and someone with both wants the same cards on each. ADR 0001 kept everything on the Mac. Now the cards, their progress and the inbox sync through the user's private iCloud database, which macOS and iOS reach on Ficha's behalf, through Apple's `CKSyncEngine`, and which the developer can't see. Ficha still makes no network connections of its own and has no accounts or analytics: the only part of it allowed on the network is the one that draws SVG images, and it draws only files already on the Mac (ADR 0018). This supersedes the part of ADR 0001 that keeps everything on the Mac; the rest of it stands: no AI in the app, and Claude changes Lucas's cards only through the CLI.

## Considered options

- The live SQLite file in iCloud Drive: iCloud copies a file SQLite may be writing, which can corrupt it.
- Point-Free's SQLiteData, a library on GRDB that syncs through CloudKit: it needs every primary key to be a UUID, queries through its own layer, and doesn't say what it does when the user signs out or another process writes, as the CLI does. `CKSyncEngine`, used directly, fits Ficha's code with no new dependency.
- A server of our own: an account for each user, and a service to run and pay for.
- Anki's rule for a card reviewed on two devices while offline, where the latest review sets the card's state: it would erase an earlier "Don't know".
- Flagging a card edited on two devices, for the user to check: more to build and to answer, for a case that rarely happens.
- An iCloud container of its own for Ficha Dev: fully apart from Lucas's cards, but a second schema to keep in step forever, and a container can't be deleted once made.

## Consequences

- Each device's database stays the source of truth, and iCloud holds a copy: Ficha works without a connection and catches up later. Sync isn't a backup, since a deletion reaches every device, so each device keeps its own backups.
- What syncs: cards, captures, the review log, tags with their color, emoji, priority and set aside, flags, burials, images, sounds, and the three settings that decide progress: the ladder, the new cards a day, and the count for **Forgotten often**. Each device keeps its own appearance log and the settings for when Ficha shows up, since the Mac shows the review panel and the iPhone sends card notifications.
- A card reviewed on two devices keeps both reviews, and its step is worked out again from the joined log (ADR 0002): whether each review was ahead is decided again from the entries before it, so one wait never climbs two steps, and a second first view of the same card changes nothing.
- A card edited on two devices keeps the latest change of each field, such as its front, its back, each image and sound, its tags or its flag, and merges the rest. A deletion wins over an edit or a review on another device, and a capture discarded on one device and approved on another goes, while the cards approved from it stay.
- An image or a sound no card uses leaves iCloud only while the device is in sync, as Anki does with media; a device whose card uses a file iCloud lacks uploads it again.
- Ficha keeps what still has to go up in its own database, filled on every write, the CLI's included, since `CKSyncEngine` forgets its queue when the iCloud account changes, and the app doesn't see on its own what another process wrote. Only the app syncs: the CLI can't claim iCloud's entitlements.
- An iCloud account change never deletes cards, though Apple suggests it: signing out stops sync, another account merges with the cards, and deleting Ficha's data from iCloud's settings turns sync off.
- A restore turns sync off until the user turns it on again. Then the restored copy replaces iCloud's, and the other devices take it in place of theirs, losing what they hadn't sent yet, as Anki's one-way upload does. Images and sounds are kept apart, and a restore leaves them alone.
- Every build that syncs is signed with Lucas's paid Apple Developer team. His Ficha comes from TestFlight, in the Production environment of Ficha's iCloud container, which the App Store's builds use; Ficha Dev syncs in that container's Development environment, apart from his cards.
- Every row that syncs needs an identifier unique across devices, beside today's integer ones.
- It changes two more parts of ADR 0001: what Lucas captures on the iPhone reaches the Mac, and the cards move out of Application Support (ADR 0018).
- It changes ADR 0010's premises: Apple's servers now push CloudKit's changes to Ficha, with no server of ours, and another device's reviews change the cards while the iPhone app isn't running, so its card notifications are planned again whenever a sync brings changes.
- `CLAUDE.md`'s rule that the app is 100% local becomes this ADR's rule once sync lands.
- Standard practice: `CKSyncEngine` on the user's private database, and a schema built in Development and deployed to Production, as Apple documents them. Our own: tracking what has to go up in Ficha's own database; working the step out again from the joined log; the latest change winning field by field; deletions winning; keeping the cards when the account changes or Ficha's iCloud data is deleted, against Apple's advice; and a restore keeping sync off across launches, which Anki doesn't.
