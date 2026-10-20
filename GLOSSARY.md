# Ficha

A macOS menu-bar app that shows Lucas small cards to remember, every so often, and spaces each one out by how well he knows it. Terms are in English, as the code and the app name them.

## Language

### Cards

**Card**:
One small thing Lucas wants to remember, with a front and a back.
_Avoid_: flashcard, note, item

**Card type**:
What a card holds: a word, a concept, a quote or a question.
_Avoid_: kind, category

**Front**:
The side of a card the review panel shows first.

**Back**:
The side of a card Lucas turns to after trying to remember it.
_Avoid_: answer, solution

**Tag**:
A subject a card belongs to, like "historia" or "filosofía". A card can have several.
_Avoid_: topic, category, deck

**Source**:
Where Lucas came across what a capture or a card holds, like a book or a podcast.
_Avoid_: origin, reference, citation

### Capturing and refining

**Capture**:
Something Lucas jots down to turn into cards later: the raw text, with an optional note and source.
_Avoid_: draft, idea, raw card

**Inbox**:
What waits to be refined: captures, including expansions, and flagged cards.
_Avoid_: queue, backlog

**Duplicate**:
A capture whose text matches a card's front, the capture a card was approved from, or another capture in the inbox, ignoring case and accents. The ñ isn't an accent: "año" doesn't match "ano".

**Expand**:
Keeping a duplicate in the inbox anyway: attached to the card it repeats, as an expansion, so that refining adds it to that card; or next to the capture it repeats, to be refined with it.
_Avoid_: merge, append

**Expansion**:
A capture in the inbox attached to the card it repeats. Approving it gives that card new content, and the card keeps its step.

**Refine**:
Turning what waits in the inbox into finished cards, in a Claude session Lucas starts. Claude drafts each change following the content guide, and Lucas approves it.
_Avoid_: process, generate, import

**Approve**:
Turning a capture into the cards Lucas accepted for it, which takes it out of the inbox. Approving an expansion gives its card the content Lucas accepted instead.
_Avoid_: accept, save

**Discard**:
Taking a capture out of the inbox without turning it into cards.
_Avoid_: delete, reject

**Fix**:
Editing a flagged card, as its note asks, in the Cards window or a refine session, which brings it back from the inbox to Lucas's reviews, where it stood.
_Avoid_: correct

**Content guide**:
The written rules Claude follows to draft cards: what each type holds, how long it is and how it's worded.
_Avoid_: style guide, template, prompt

### Reviewing

**Review panel**:
The small floating window where cards show up and Lucas goes through them.
_Avoid_: popup, window, notification

**Review**:
One pass over one card: Lucas sees its front, flips it to check the back, and rates it.
_Avoid_: answer, attempt, study

**Rating**:
How well Lucas says he knew a card in a review: again, hard or good, which the app's buttons call "Don't know", "Sort of" and "Know it".
_Avoid_: grade, score, ease

**First view**:
The first time Lucas sees a card, whole, before it's on the ladder. It isn't a review.
_Avoid_: introduction, first review, learning step

**Review log**:
Every first view and review, with when Lucas answered, what opened the review panel, how long he took and his rating. A card's step and due time are worked out from it.
_Avoid_: history, review history

**Review now**:
Lucas opening the review panel himself, from the menu bar, outside an appearance.
_Avoid_: manual session, study mode

**See more**:
Lucas asking for more cards once an appearance or a review now is done.
_Avoid_: continue, extra session

**Review ahead**:
A review of a card that isn't due yet, which Lucas asks for.
_Avoid_: cram, study ahead, extra practice

**Flag**:
Sending a card back to the inbox with a note on what to fix. It stays out of reviews until it's fixed.
_Avoid_: mark, report

**Bury**:
Taking a card Lucas no longer wants out of reviews for good, and out of the inbox if it's flagged, without deleting it. Unburying it, in the Cards window or a refine session, puts it back where it was.
_Avoid_: archive, suspend

### Managing cards

**Cards window**:
The window where Lucas sees all his cards and everything in the inbox, and acts on them himself.
_Avoid_: browser, card list

**Edit**:
Changing the content of a card or a capture. A card keeps its step and its review log.
_Avoid_: modify, update

**Delete**:
Taking a card out of Ficha for good, with its review log, which burying keeps. An expansion attached to it stays in the inbox as a capture.
_Avoid_: remove, erase

### Spacing

**Ladder**:
The fixed sequence of waits a card climbs as Lucas remembers it.
_Avoid_: schedule, intervals, boxes

**Ladder step**:
A card's place on the ladder, which sets how long it waits before it's due again.
_Avoid_: box, level, interval

**Due**:
A card on the ladder whose wait is over.
_Avoid_: pending, ready

**New**:
A card that hasn't had its first view yet.
_Avoid_: unseen, fresh

**Learned**:
A card whose step waits 30 days or more.
_Avoid_: mastered, known, mature

### Appearances

**Appearance**:
A time the review panel shows up on its own, with the cards that are due or about to be.
_Avoid_: session, prompt, popup, presentation

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
Putting off an appearance, or what's left of a review now, without rating its cards, which stay due.
_Avoid_: dismiss, skip, postpone

**Auto-close**:
The review panel closing on its own: once it's been untouched for a while, or as the Mac or its screens go to sleep. It counts as a snooze, unless Lucas had gone through every card it brought.
_Avoid_: timeout, expiry

**Suppression**:
A situation in which Ficha holds back appearances so as not to interrupt: a meeting, a video or a full-screen app.
_Avoid_: exception, block, do not disturb

**Focus mode**:
Whether the review panel takes the keyboard when it shows up on its own: never, once Lucas is idle, or always. It has nothing to do with macOS's Focus.
_Avoid_: Focus, keyboard grab

**Appearance log**:
Every appearance, and every review now that brought cards, with what opened the review panel, when it showed and closed, and how it closed: finished, snoozed or auto-closed. An appearance a suppression held back goes in once too, with the suppression.
_Avoid_: history, session log
