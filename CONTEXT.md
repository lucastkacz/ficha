# Ficha

A macOS menu-bar app that shows Lucas small cards to remember, every so often, and spaces each one out by how well he knows it. Terms are in English, with the word the app's Spanish UI uses in italics.

## Language

### Cards

**Card** (_ficha_):
One small thing Lucas wants to remember, with a front and a back. The ladder spaces each card out by how well he knows it.
_Avoid_: flashcard, note, item

**Card type** (_tipo_):
What a card holds: a word (_palabra_), a concept (_concepto_), a quote (_frase_) or a question (_pregunta_).
_Avoid_: kind, category

**Front** (_frente_):
The side of a card the review panel shows first: the word, the concept's name, the quote or the question.

**Back** (_dorso_):
The side Lucas turns to after trying to remember: a word's definition and an example, a concept's explanation, what a quote means and who said it, or a question's answer.
_Avoid_: answer, solution

**Tag** (_tema_):
A topic a card belongs to, like "historia" or "filosofía". A card can have several.
_Avoid_: topic, category, deck

**Source** (_fuente_):
Where Lucas came across what a card holds, like a book or a podcast. It's optional.
_Avoid_: origin, reference, citation

### Capturing and refining

**Capture** (_captura_):
Something Lucas jots down to turn into cards later: the raw text and an optional note.
_Avoid_: draft, idea, raw card

**Inbox** (_bandeja_):
The captures waiting to be refined.
_Avoid_: queue, backlog

**Duplicate** (_duplicado_):
A capture whose text matches another capture or a card's front, ignoring case and accents.

**Expand** (_expandir_):
Keeping a duplicate in the inbox attached to the card it repeats, so that refining adds it to that card. The other choice is to drop it.
_Avoid_: merge, append

**Refine** (_refinar_):
Turning captures into cards, in a Claude session Lucas starts. Claude drafts each card following the content guide, and Lucas approves it before it's saved.
_Avoid_: process, generate, import

**Content guide** (_guía de contenido_):
The written rules Claude follows to draft cards: what each type holds, how long it is and how it's worded.
_Avoid_: style guide, template, prompt

### Reviewing

**Review panel** (_cajita_):
The small floating window where cards show up and Lucas answers them.
_Avoid_: popup, window, notification

**Review** (_repaso_):
One pass over one card: Lucas sees its front, flips it to check the back, and rates it.
_Avoid_: answer, attempt, study

**Rating** (_calificación_):
Lucas's answer in a review: again (_No lo sé_), hard (_Más o menos_) or good (_Lo sé_). Again sends the card back to the first step, hard keeps it on its step, and good moves it up one.
_Avoid_: grade, score, ease

**First view** (_primera vista_):
The first time a card shows up: the review panel shows it whole, and Lucas just acknowledges it. It isn't a review: nothing is rated, and the card starts on the first step.
_Avoid_: introduction, first review, learning step

**Review now** (_Repasar ahora_):
Lucas opening the review panel himself, from the menu bar, outside an appearance.
_Avoid_: manual session, study mode

**Review ahead** (_adelantar_):
Reviewing cards before they're due, once Lucas asks for more and no due cards are left. Only again counts, sending the card back to the first step; hard and good leave it where it was.
_Avoid_: cram, study ahead, extra practice

**Flag** (_marcar_):
Pulling a card out of reviews and back into the inbox, with a note, so that the next refine fixes it.
_Avoid_: mark, report

**Bury** (_enterrar_):
Taking a card Lucas no longer wants out of reviews for good. It stays saved with its history: he can undo it right away, or unbury it while refining.
_Avoid_: delete, archive, suspend

### Spacing

**Ladder** (_escalera_):
The sequence of waits a card climbs as Lucas remembers it: 1 h, 4 h, 2 d, 5 d, 12 d, 30 d and 75 d, unless he changes them.
_Avoid_: schedule, intervals, boxes

**Ladder step** (_escalón_):
A card's place on the ladder, which sets how long it waits before it's due again.
_Avoid_: box, level, interval

**Due** (_vencida_):
A card on the ladder whose wait is over, so it's ready to be shown again.
_Avoid_: pending, ready

**New** (_nueva_):
A card that hasn't had its first view yet.
_Avoid_: unseen, fresh

**Learned** (_aprendida_):
A card whose step waits 30 days or more.
_Avoid_: mastered, known, mature

### Appearances

**Appearance** (_aparición_):
A time the review panel shows up on its own, with the cards that are due or about to be.
_Avoid_: session, prompt, popup, presentation

**Active hours** (_horario activo_):
The part of the day in which appearances may happen.
_Avoid_: schedule, work hours

**Snooze** (_posponer_):
Closing an appearance without answering, with Esc or by leaving it until it closes on its own. Its cards stay due until the next appearance.
_Avoid_: dismiss, skip, postpone

**Suppression** (_excepción_):
A situation in which Ficha holds back appearances so as not to interrupt: a meeting, a video or a full-screen app.
_Avoid_: exception, block, do not disturb

**Focus mode** (_foco_):
Whether the review panel takes the keyboard when it shows up: never, once Lucas has been idle for 5 seconds, or always.
