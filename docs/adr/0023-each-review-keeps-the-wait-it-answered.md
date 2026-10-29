# Each review keeps the wait it answered, so step statistics count only a step's current wait

The ladder is fixed so the user always knows why a card shows up (ADR 0002), and they change its waits by hand in Settings' Ladder tab. Step statistics (#168) give them their own data to change it with: how they rated the reviews on each step. A card's step is worked out by replaying its review log with today's ladder, so a change to the ladder re-times every card, and the log doesn't say which wait a review answered. Counted by the step each review replays to, a step's statistics would mix every wait it ever had: after Lucas shortens step 5 from 12 to 10 days, months of 12-day reviews would hide the new ones, and he couldn't tell whether the change worked. So each review now keeps the wait it answered, and a step's statistics count only the reviews that answered the wait it has now: they start over when the wait changes, and the old reviews count again if it changes back.

## Considered options

- Every review by the step it replays to: nothing new to keep, but a change shows only after months, and adding or removing a step moves a step's reviews to another.
- The dates the ladder changed, with each step counting its reviews since: one record for every card, but a wait that comes back loses its old reviews, and the settings that decide progress, which sync as one value, would need a history.
- The time each card actually waited, from the entry before its review: nothing new to keep, but a review comes late whenever the Mac sleeps or active hours end, so the time doesn't tell which wait the review answered.

## Consequences

- The review log stays the source of truth for a card's step, worked out with today's ladder (ADR 0002). The wait a review answered feeds step statistics alone, never a step or a due time, and it syncs with its review (ADR 0017).
- Step statistics group reviews by the wait they answered, so adding or removing a step keeps the reviews of every wait that stays, under the step that has it now. The ladder's waits all differ, so no review counts under two steps.
- Reviews from before this change get the wait of the step they replay to, with the ladder in force when a device first runs the new version, and so do those of an older backup once it's restored.
- They count the reviews of both ways of every card the device holds, buried, flagged and set-aside ones too, and reviews that came late. They leave out first views, an import's placements, and reviews ahead, as the ladder judges them once two devices' logs join (ADR 0017). Under selective sync, a device counts only the cards it holds (ADR 0020).
- The first review after an import's placement answered the wait of the step the import put the card on, though the card waited the interval Anki gave it: ADR 0013 already counts an imported card's reviews from its import on.
- They show in Settings' Ladder tab, under each step's wait: a bar of "Know it", "Sort of" and "Don't know", the share of "Know it", and how many reviews, or that the wait has none yet. They show however few the reviews are, since their count says how far to trust them.
- Ficha shows them and suggests no wait: a suggestion needs a rule of its own that picks a wait from the numbers, and the ladder's waits stay the user's choice (ADR 0002).
- Ficha shows no other statistics: no calendar of the days the user reviewed, which would be a streak, against the menu bar's choice of no pressure (#4); no curve of learned cards, since the menu already counts them; and no forecast of due cards, since Ficha, not the user, decides when cards show up.
- The iPhone shows them in its Settings too (ADR 0019).
- Standard practice: measuring how often the user remembers what they review, as Anki's statistics do with their true retention. Our own: counting it for each ladder step, and only for the wait it has now, which each review keeps; and showing "Know it" apart from "Sort of", where Anki counts Hard as remembered.
