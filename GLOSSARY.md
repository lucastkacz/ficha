# Ficha

An app that shows its user small cards to remember, every so often, on the Mac, from the menu bar, and on the iPhone, and spaces each one out by how well they know it. Anyone can use it; Lucas builds it, and his own way of making cards, refining them with Claude, isn't part of the app. Terms are in English, as the code and the app name them.

## Language

### Cards

**Card**:
One small thing the user wants to remember, with a front and a back. Each side holds text, an image, a sound, or any of them together, with one image and one sound at most.
_Avoid_: flashcard, note, item

**Card type**:
What a card holds, if it has one: a word, a concept, a quote or a question.
_Avoid_: kind, category

**Front**:
The side of a card the user sees first, except back first.

**Back**:
The side of a card the user turns to after trying to remember it, except back first.
_Avoid_: answer, solution

**Both ways**:
A card the user also reviews back first, which each card can be set to. Each way has its own progress, as a card of its own would: its own first view, ladder step, due time and reviews.
_Avoid_: reverse, reversed card, sibling

**Back first**:
The other way of reviewing a card that goes both ways: the user sees its back first, and its front when they flip it.
_Avoid_: reverse

**Sound**:
What the user hears on one side of a card, from a file they added or imported, such as an excerpt of an aria or a word's pronunciation. It plays only when they ask for it.
_Avoid_: audio, clip, recording

**Tag**:
A subject a card belongs to, like "historia" or "filosofía". A card can have several.
_Avoid_: topic, category, deck

**Priority tag**:
A tag the user chose so that its cards come first when cards show up, as while preparing for an exam. It changes which cards come first, never when a card is due.
_Avoid_: focus, exam mode, filter

**Set aside**:
Taking every card with a tag out of the user's reviews for now, also those that get the tag later, as when they're done with a subject, without burying them. Once the tag is no longer set aside, its cards stand where they would without it.
_Avoid_: pause, suspend, archive, hide

**Source**:
Where the user came across what a capture or a card holds, like a book or a podcast.
_Avoid_: origin, reference, citation

### Capturing and refining

**Capture**:
Something the user jots down to turn into cards later: the raw text, with an optional note and source.
_Avoid_: draft, idea, raw card

**Inbox**:
What waits to be turned into cards or fixed: captures, including expansions and follow-ups, and flagged cards.
_Avoid_: queue, backlog

**Duplicate**:
A capture whose text matches a card's front, the capture a card was approved from, or another capture in the inbox, or a card created or imported whose front matches another card's, ignoring case, accents, superscripts and subscripts: "H₂O" matches "H2O", and a minus sign, "−", matches "-". The ñ isn't an accent: "año" doesn't match "ano". An imported card's front counts its image too: two fronts that each have an image match only when it's the same image, so a front with only an image matches one with only that image. Otherwise a front without text, with only an image or a sound, matches none.

**Expand**:
Keeping a duplicate in the inbox anyway: attached to the card it repeats, as an expansion, so that approving it adds to that card; or next to the capture it repeats, to be turned into cards with it.
_Avoid_: merge, append

**Expansion**:
A capture in the inbox attached to the card it repeats. Approving it gives that card new content, and the card keeps its step.

**Follow-up**:
A capture the user jots down in the review panel about the card in front of them, tied to that card, such as a question it raised. Approving it creates new cards, as any capture does, and leaves that card as it is.
_Avoid_: question, expansion

**Refine**:
Turning what waits in the inbox into finished cards, in a Claude session Lucas starts. Claude drafts each change following the content guide, and Lucas approves it.
_Avoid_: process, generate, import

**Approve**:
Turning a capture into the cards the user accepted for it, in the Cards window or a refine session, which takes it out of the inbox. Approving an expansion gives its card the content the user accepted instead.
_Avoid_: accept, save

**Discard**:
Taking a capture out of the inbox without turning it into cards.
_Avoid_: delete, reject

**Fix**:
Editing a flagged card, as its note asks, in the Cards window or a refine session, which takes it out of the inbox, back to the user's reviews unless one of its tags is set aside.
_Avoid_: correct

**Content guide**:
The written rules Claude follows to draft Lucas's cards: what each type holds, which cards go both ways, how long a card is and how it's worded.
_Avoid_: style guide, template, prompt

### Reviewing

**Review panel**:
The small floating window on the Mac where cards show up and the user goes through them.
_Avoid_: popup, window, notification

**Widget**:
A small view of Ficha on the Mac's desktop or in Notification Center, with the next card to review, on the side the review panel shows first, or when the next one comes, which opens the review panel on that card.
_Avoid_: tile, complication

**Review**:
One pass over one card: the user sees its front, or back first its back, flips it to check the other side, and rates it.
_Avoid_: answer, attempt, study

**Rating**:
How well the user says they knew a card in a review: again, hard or good, which the app's buttons call "Don't know", "Sort of" and "Know it".
_Avoid_: grade, score, ease

**First view**:
The first time the user sees a card, before it's on the ladder: whole, or back first its back, and its front once they flip it. It isn't a review.
_Avoid_: introduction, first review, learning step

**Review log**:
Every first view and review, with when the user answered, whether an appearance or a review now brought the card, which way it went, their rating, and how long they took, except from a card notification; and the step an import placed a card on, when it came with its progress. A card's step and due time are worked out from it.
_Avoid_: history, review history

**Review now**:
The user reviewing on their own, outside an appearance: from the menu bar, the Shortcuts app or a widget on the Mac, or the Review tab on the iPhone.
_Avoid_: manual session, study mode

**See more**:
The user asking for more cards once an appearance or a review now is done.
_Avoid_: continue, extra session

**Review ahead**:
A review of a card that isn't due yet, which the user asks for.
_Avoid_: cram, study ahead, extra practice

**Flag**:
Sending a card back to the inbox with a note on what to fix. It stays out of reviews until it's fixed.
_Avoid_: mark, report

**Forgotten often**:
A card the user rated again, "Don't know", in eight reviews in all, or as many as they set, since its front or back last changed, counting each way apart. The review panel offers to flag it, so it gets fixed, unless the user turned that off.
_Avoid_: leech, hard card

**Bury**:
Taking a card the user no longer wants out of reviews for good, and out of the inbox if it's flagged, without deleting it. Unburying it, in the Cards window or a refine session, puts it back where it would be without the burial.
_Avoid_: archive, suspend

**Standing**:
Where a card stands, the first of these that holds: buried; waiting in the inbox to be fixed; set aside with one of its tags; or in the user's reviews, new or on a ladder step until it's due. Out of their reviews, a card keeps its step, or stays new, and returns to them that way.
_Avoid_: status, state

### Managing cards

**Cards window**:
The window where the user sees all their cards and everything in the inbox, creates cards, and acts on them.
_Avoid_: browser, card list

**Edit**:
Changing the content of a card or a capture. A card keeps its step and its review log.
_Avoid_: modify, update

**Delete**:
Taking a card out of Ficha for good, with its review log, which burying keeps. An expansion attached to it, or a follow-up tied to it, stays in the inbox as a capture.
_Avoid_: remove, erase

**Import**:
Bringing cards into Ficha from a file: a text file with one card per line, zipped with its images and sounds if it has any, which another Ficha exported or someone wrote, maybe with an AI; or a deck exported from Anki, with its progress unless the user leaves it out.
_Avoid_: load, refine

**Export**:
Saving cards to a text file with one card per line, zipped with their images and sounds if they have any, which another Ficha can import, and Anki too when it's text alone. It holds what the cards say, and which go both ways, never the user's progress.
_Avoid_: backup, share

### Spacing

**Ladder**:
The fixed sequence of waits a card climbs as the user remembers it.
_Avoid_: schedule, intervals, boxes

**Ladder step**:
A card's place on the ladder, which sets how long it waits before it's due again.
_Avoid_: box, level, interval

**Settings that decide progress**:
The ladder, how many new cards a day the user meets, and after how many "Don't know" a card is forgotten often. They sync, so a card's progress means the same on each device; the user's other settings stay each device's own.
_Avoid_: synced settings, review settings

**Due**:
A card on the ladder whose wait is over.
_Avoid_: pending, ready

**New**:
A card that isn't on the ladder yet: it hasn't had its first view, nor come in on a step with an import.
_Avoid_: unseen, fresh

**Learned**:
A card whose step waits 30 days or more.
_Avoid_: mastered, known, mature

### Appearances

**Appearance**:
A time Ficha shows up on its own, with the cards that are due or about to be: the review panel on the Mac, a card notification for each card on the iPhone.
_Avoid_: session, prompt, popup, presentation

**Card notification**:
A notification on the iPhone with one card of an appearance, and the buttons to go through it: a new card whole, for its first view, or a due card's front, or back first its back, and the other side when the user presses and holds it, to rate it.
_Avoid_: alert, push, banner

**Look-ahead**:
How far ahead an appearance looks: it brings along the cards due within it, whose reviews count as on time.
_Avoid_: buffer, window

**Active hours**:
The part of the day in which appearances may happen.
_Avoid_: schedule, work hours

**Separation**:
The least time between appearances, counted from when the last appearance or review now closed.
_Avoid_: cooldown, gap, interval

**Snooze**:
Putting off an appearance, or what's left of a review now, without rating its cards, which stay due. On the iPhone, it's also leaving a card notification without rating it, or swiping it away.
_Avoid_: dismiss, skip, postpone

**Auto-close**:
The Mac's review panel closing on its own: once it's been untouched for a while, or as the Mac or its screens go to sleep. It counts as a snooze, unless the user had gone through every card it brought.
_Avoid_: timeout, expiry

**Suppression**:
A situation in which Ficha holds back appearances on the Mac so as not to interrupt: a meeting, a video, a full-screen app, or a Focus of macOS in which the user turned on Ficha's filter. The user turns the first three off in Settings, and the Focus's in System Settings.
_Avoid_: exception, block, do not disturb

**Focus mode**:
Whether the Mac's review panel takes the keyboard when it shows up on its own: never, once the user is idle, or always. It has nothing to do with the Focus of macOS or iOS.
_Avoid_: Focus, keyboard grab

**Appearance log**:
Every appearance, and every review now that brought cards, with when it showed and closed and how: finished, snoozed or auto-closed; on the iPhone, from its first card notification to the last card the user went through or the one they swiped away, snoozed until none is left, and closed as it showed when they never touched them. An appearance a suppression held back goes in once too, with the suppression.
_Avoid_: history, session log

### Backups

**Backup**:
A copy of everything Ficha keeps, images and sounds included, as it was at one moment, which Ficha saves on its own every day, or as often as the user sets, or when they ask. Ficha keeps the last 7, or as many as they set, and each device keeps its own.
_Avoid_: snapshot, export

**Copy before an update**:
A copy Ficha saves before a new version changes the database. Ficha never deletes it on its own.

**Copy before a restore**:
A copy of everything as it was just before a restore, so restoring it undoes the restore. Ficha never deletes it on its own.

**Copy before an import**:
A copy of everything as it was just before an import, so restoring it undoes the import. Ficha never deletes it on its own.

**Copy before taking iCloud's copy**:
A copy of everything as it was just before a device took the cards another device restored, in place of its own, as sync does, so the cards the restore removed can still be found. Ficha never deletes it on its own.

**Restore**:
Bringing back a backup, or another copy Ficha saved, in place of everything as it is now. On a device that syncs, it turns sync off, and once the user turns it on again, the restored copy replaces what their other devices hold.
_Avoid_: revert, roll back

### Sync

**Sync**:
Keeping the user's cards, or those with the tags they choose, their progress, the inbox and the settings that decide progress the same on each of their devices, through their own iCloud. Each device keeps working without a connection and catches up later; it isn't a backup, since a deletion reaches every device.
_Avoid_: cloud, mirror, upload

**Selective sync**:
Syncing only the cards with a tag the user chose, instead of all of them, so the rest stay off iCloud and off their other devices. Which tags sync is one choice for all their devices, and changing it never deletes a card from any of them.
_Avoid_: partial sync, local cards, offline tags
