# FSRS spaces cards, as in Anki, instead of the fixed ladder

ADR 0002 spaced cards with a fixed ladder: every card on a step waited the same, so Lucas always knew why a card showed up. Since then Ficha has turned toward Anki, so that someone switching from it finds what they know (ADR 0024), and on 2026-10-31, grilling #396, Lucas decided the scheduler goes the same way: each card waits by how well the user knows it, as Anki does. So Ficha schedules with FSRS, Anki's modern scheduler, and Anki's four buttons. A new card goes through short learning steps, a forgotten one through relearning steps, and once it graduates FSRS gives it an interval in days, aiming at a desired retention of 90%. Why a card shows up is answered as in Anki: each button shows the interval it would set, and a card's detail shows its stability, difficulty and retrievability. This supersedes ADR 0002 and ADR 0023.

## Considered options

- SM-2, Anki's default: a card's ease drops with again and hard and rises only with easy, so with the three buttons Ficha had, every card would sink, what Anki's users call ease hell.
- The ladder, with its waits tuned by hand from step statistics (#168): simple, but every card on a step waits alike, and a card from Anki loses its interval.
- FSRS with three buttons: FSRS works with them, but Anki's users press four, and Anki's review history maps only onto four.
- Leaving the learning steps empty, so FSRS schedules the same day too: Anki calls it experimental, and the FSRS Anki ships counts time in whole days.
- Cards due by the day, as in Anki, where a day's cards fall due at 4 am: Anki's user opens it when they choose to study, but Ficha shows up on its own through the day (ADR 0003), and the day's first appearance would take the whole backlog.
- Anki's presets, settings for each deck: priority decks already serve an exam, and presets can come later as additions to the iCloud schema.
- Anki's Optimize, which fits FSRS's parameters to the user's reviews, now: there's no optimizer in Swift, only Anki's in Rust and one in Python, and nobody has reviews yet.
- A change to the settings re-timing every card at once, as the ladder did: Anki keeps that behind a checkbox, off by default, since it can make many cards due at once.

## Consequences

- The review log stays the source of truth (ADR 0002). Each review keeps the interval it set, and a card is due once the interval its last review set is over, at the time of day of that review: the user's cards spread themselves through the day. Its stability and difficulty are worked out by replaying its reviews. A change to the settings that decide progress applies from each card's next review, as in Anki.
- There's no first view: a new card's first showing is a review, front first, rated like any other. Easy graduates it at once.
- The ratings are Anki's four, with Anki's names in each language, keys 1 to 4, and Space for good. Hard counts as remembered, as in FSRS and Anki.
- The learning steps are 1 hour and 4 hours, and the relearning step 1 hour: longer than Anki's 1 and 10 minutes, since appearances come at least a separation apart, 30 minutes by default. Within the steps, again goes back to the first, hard repeats the step, good moves to the next and easy graduates, as in Anki.
- FSRS starts with its default parameters, fitted on Anki users' reviews. They sync as one of the settings that decide progress, so every device schedules alike, and Optimize, when it comes, only changes them.
- The desired retention is 90% and the longest interval 36,500 days, both settings, so a learned card no longer comes back every 75 days for good. Intervals get Anki's fuzz, which the device that recorded the review decides, since the review keeps its interval.
- A review ahead counts, as FSRS reckons it from the time since the card's last review: ADR 0002's rule that only its again counts goes.
- Learned means an interval of 21 days or more, Anki's mature. Forgotten often counts lapses, agains of graduated cards, as Anki counts leeches, so the agains of a card's learning steps don't count.
- One set of settings for every deck, as before.
- An Anki import brings each card's review history, with its four ratings and the intervals they set, so a card stays due when Anki had it due. A card that comes without its history keeps Anki's interval and due date. This changes ADR 0013, whose nearest step and history left behind go.
- A card that goes both ways starts its back-first way new once the card has had its first review (ADR 0016).
- A card reviewed on two devices keeps both reviews, and its progress is worked out again from the joined log, due after the interval its last review set (ADR 0017).
- Step statistics (#168) go, and with them ADR 0023's wait each review answered, which was never built. Spec #376 keeps the review count (#347), where a new card's first review now counts.
- Ficha has no limit on reviews a day, since appearances already spread a backlog (ADR 0003), and no load balancer, beyond the fuzz.
- The interval each review keeps, the fourth rating and the new settings sync, so they're in the iCloud schema before #318 deploys it to Production.
- The iPhone does the same (ADR 0019): its card notifications carry four ratings, and iOS shows up to ten actions in an expanded notification.
- Standard practice: FSRS as Anki ships it, with its default parameters; learning and relearning steps under a day; desired retention; Anki's ratings and names; the intervals above the buttons; Card Info's stability, difficulty and retrievability; leeches counted by lapses. Our own: steps of hours rather than minutes; a card due at the time of day of its last review; its due time worked out from the interval its last review kept; one set of settings for every deck; no review limit or load balancer.
