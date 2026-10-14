# Fixed ladder steps instead of a per-card formula

Cards are spaced with a Leitner ladder: a fixed list of waits (1 h, 4 h, 2 d, 5 d, 12 d, 30 d and 75 d by default), where good moves a card up one step, hard keeps it on its step and again sends it back to the first. Formula-based schedulers such as SM-2 (Anki's classic) or FSRS work out a different wait for each card from its history and need somewhat fewer reviews, but Lucas couldn't tell why a card shows up today, and their parameters are hard to tune. We picked the ladder because it's simple and predictable.

## Consequences

- Every first view and review is saved, and that log is the source of truth: a card's step is worked out from it, so a formula could replace the ladder later without losing history.
- A first view isn't a review: the card always starts on the first step.
- A review ahead only counts when it's an again. Otherwise a bored afternoon would climb cards without the waits in between.
- The last step repeats for good: a learned card keeps coming back every 75 days, and Lucas buries the ones he no longer wants.
