# Ficha

A macOS menu-bar app that shows Lucas small cards to remember, every so often, and spaces each one out by how well he knows it. Terms are in English, as they're named in code, with the word the app's Spanish UI uses in italics.

## Language

### Cards

**Card** (_ficha_):
One small thing Lucas wants to remember, with a front and a back.
_Avoid_: flashcard, note, item

**Card type** (_tipo_):
What a card holds: a word (_palabra_), a concept (_concepto_), a quote (_frase_) or a question (_pregunta_).
_Avoid_: kind, category

**Front** (_frente_):
The side of a card the review panel shows first.

**Back** (_dorso_):
The side of a card Lucas turns to after trying to remember it.
_Avoid_: answer, solution

**Tag** (_tema_):
A subject a card belongs to, like "historia" or "filosofía". A card can have several.
_Avoid_: topic, category, deck

**Source** (_fuente_):
Where Lucas came across what a capture or a card holds, like a book or a podcast.
_Avoid_: origin, reference, citation

### Capturing and refining

**Capture** (_captura_):
Something Lucas jots down to turn into cards later: the raw text, with an optional note and source.
_Avoid_: draft, idea, raw card

**Inbox** (_bandeja_):
What waits to be refined: captures, including expansions, and flagged cards.
_Avoid_: queue, backlog

**Duplicate** (_duplicado_):
A capture whose text matches another capture or a card's front, ignoring case and accents.

**Expand** (_expandir_):
Keeping a duplicate in the inbox, attached to the card it repeats, so that refining adds it to that card.
_Avoid_: merge, append

**Refine** (_refinar_):
Turning what waits in the inbox into finished cards, in a Claude session Lucas starts. Claude drafts each change following the content guide, and Lucas approves it.
_Avoid_: process, generate, import

**Approve** (_aprobar_):
Turning a capture into the cards Lucas accepted for it, which takes it out of the inbox.
_Avoid_: accept, save

**Discard** (_descartar_):
Taking a capture out of the inbox without turning it into cards.
_Avoid_: delete, reject

**Content guide** (_guía de contenido_):
The written rules Claude follows to draft cards: what each type holds, how long it is and how it's worded.
_Avoid_: style guide, template, prompt

### Reviewing

**Review panel** (_cajita_):
The small floating window where cards show up and Lucas goes through them.
_Avoid_: popup, window, notification

**Review** (_repaso_):
One pass over one card: Lucas sees its front, flips it to check the back, and rates it.
_Avoid_: answer, attempt, study

**Rating** (_calificación_):
How well Lucas says he knew a card in a review: again (_No lo sé_), hard (_Más o menos_) or good (_Lo sé_).
_Avoid_: grade, score, ease

**First view** (_primera vista_):
The first time Lucas sees a card, whole, before it's on the ladder. It isn't a review.
_Avoid_: introduction, first review, learning step

**Review now** (_Repasar ahora_):
Lucas opening the review panel himself, from the menu bar, outside an appearance.
_Avoid_: manual session, study mode

**See more** (_ver más_):
Lucas asking for more cards once an appearance or a review now is done.
_Avoid_: continue, extra session

**Review ahead** (_adelantar_):
A review of a card that isn't due yet, which Lucas asks for.
_Avoid_: cram, study ahead, extra practice

**Flag** (_marcar_):
Sending a card back to the inbox with a note on what to fix. It stays out of reviews until it's fixed.
_Avoid_: mark, report

**Bury** (_enterrar_):
Taking a card Lucas no longer wants out of reviews for good, without deleting it.
_Avoid_: delete, archive, suspend

### Spacing

**Ladder** (_escalera_):
The fixed sequence of waits a card climbs as Lucas remembers it.
_Avoid_: schedule, intervals, boxes

**Ladder step** (_escalón_):
A card's place on the ladder, which sets how long it waits before it's due again.
_Avoid_: box, level, interval

**Due** (_vencida_):
A card on the ladder whose wait is over.
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
Putting off an appearance without rating its cards, which stay due.
_Avoid_: dismiss, skip, postpone

**Suppression** (_excepción_):
A situation in which Ficha holds back appearances so as not to interrupt: a meeting, a video or a full-screen app.
_Avoid_: exception, block, do not disturb

**Focus mode** (_foco_):
Whether the review panel takes the keyboard when it shows up on its own: never, once Lucas is idle, or always. It has nothing to do with macOS's Focus.
_Avoid_: Focus, keyboard grab
