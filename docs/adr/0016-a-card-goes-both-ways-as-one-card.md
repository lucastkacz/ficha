# A card goes both ways as one card, each way with its own progress

Someone learning words wants the same card the other way round too: the meaning shown, and the word once they flip it (#251). Anki makes that reverse a card of its own, which its note creates, with a schedule of its own. Ficha has no notes, since the card is what the user writes and edits, so a card that goes both ways stays one card, with one front and one back to edit. Each way has its own progress: its own first view, ladder step, due time and reviews, because knowing what a word means and finding the word for a meaning are learned apart. Which cards go both ways is a switch on each card, off by default, as Anki's "Basic (optional reversed card)" decides it note by note: not every card of a subject works back first.

## Considered options

- Two cards, as Ficha brought in Anki's reversed notes until now: nothing new in the model, but every edit is made twice, and nothing ties the two cards.
- One card with one progress, shown either way: simpler, but a good rating one way would climb the other way unearned.
- An option of each tag, beside priority and set aside (ADR 0011): the grilling's first answer, dropped because one subject mixes cards that work back first with cards that don't.

## Consequences

- The review log says which way each first view and review went, and a card's step, due time and count for **Forgotten often** are worked out for each way apart.
- A card's back-first way starts new once the card has had its first view, counts toward the new cards a day, and takes turns with new cards. Nothing keeps a card's two ways apart in time: Anki's burying of siblings is off by default, and Lucas didn't want the rule.
- Flagging, burying, setting aside and priority tags act on the whole card, both ways. Switching a card's both ways off takes its back-first way out of reviews and keeps its progress.
- A reversed note from Anki comes in as one card that goes both ways, which changes ADR 0013's "each Anki card becomes one Ficha card".
- The app never hides the front where the back names it, such as a word's example: whoever writes the card decides whether it goes both ways, and the content guide tells Claude how to write it.
