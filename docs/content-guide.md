# Content guide

How Claude drafts Lucas's cards in a refine session: what each card holds, how long it is and how it's worded. The terms are `GLOSSARY.md`'s.

Everything Claude drafts is a proposal: a card, a fix, a file on a card, a discarded capture or a burial. Lucas approves, changes or rejects each one, and nothing is written without his OK.

## The five rules

1. **Rioplatense Spanish, with "vos"**: "sabés", "mirá", "tenés".
2. **One idea per card.** A capture with two ideas makes two cards, and so does a back that needs "y además".
3. **A one-line front, and a back of at most 40 words.** The review panel shows both without scrolling. Count the back's words before proposing it.
4. **Plain, concrete backs.** A short story or a contrast, rather than a list or an abstract summary: Lucas reviews these cards for years, and a back he has to read twice doesn't stick.
5. **Words from other languages, explained in Spanish.** The front keeps the word as it's written in its language; the back starts with the language and says what it means in Spanish ("Palabra alemana: …"). A quote from another language is the exception, on both sides: see Quote below.

## Captures

A capture becomes one card, several or none. Several when it holds more than one idea; none when it isn't worth a card, and then Claude proposes discarding it. Pick each card's type by what Lucas has to remember, not by the capture's form: "cuándo llegamos a la Luna" is a question.

## Each type

- **Word** (`word`): the front is the word alone, in lowercase unless its language capitalizes it ("Schadenfreude"). The back is its meaning in plain words and then, always, an example of its use, written as `Por ejemplo: «…»`. Its etymology goes on the back only when it fits within the 40 words and helps remember the word ("Schadenfreude"); one that's a story of its own becomes a question card of its own ("¿De dónde viene la palabra «serendipia»?").
- **Concept** (`concept`): the front is the concept's name, with its article when Spanish uses one ("La navaja de Ockham"). The back says what it is in a sentence or two, and then, if there's room, who came up with it or an example.
- **Quote** (`quote`): the front is the quote, word for word, with its final punctuation. A quote from another language goes on the front in Spanish, word for word as people say it ("La suerte está echada."), and the back ends with the original when that's famous too (in Latin, «alea iacta est»). A quote too long for one line is cut to its most memorable part, still word for word, with "…" where it's cut. The back says who said it and what it means: in a review, Lucas rates whether he had understood it, so the meaning is the core of the back. Where it's from goes in the source.
- **Question** (`question`): the front is a question with one answer. The back gives that answer first, and then why or how, in a sentence.

## Tags

A tag is a subject, in Spanish and in lowercase: "lenguaje", "filosofía", "historia". A card has one usually, and three at most. Claude reuses the tags Lucas's cards already have, and says so when it proposes a new one, so Lucas sees it. A card that fits no subject has no tags.

## Sources

A card takes its capture's source as Lucas wrote it, and the review panel shows it small under the back, so the back doesn't repeat it.

## Flagged cards, expansions and follow-ups

- **A flagged card**: Claude changes what Lucas's note asks for and keeps the rest as it was, so he recognizes the card. When the note says the card is no longer worth it, Claude proposes burying it. When the card holds two ideas, Claude fixes it to one, and captures the other to propose it as a new card in the same session.
- **A card forgotten often**: a flagged card whose note starts with "Forgotten N times", which the review panel writes when Lucas rated the card "Don't know" that many times since its front or back last changed. Whatever he added after it says what to fix, as in any note. A card forgotten again and again is usually badly written rather than hard, so Claude rewrites it even when the note says nothing more, in the one of these ways that fits it best, which Anki's manual advises for the cards it calls leeches (docs.ankiweb.net/leeches.html):
  - **Clearer wording**: a back that gives what the front asks for first, in fewer words, or a front that tells the card apart from another one Lucas mixes it up with.
  - **A trick to remember it**: a mnemonic, a vivid image, or a link to something Lucas already knows, on the back and within its 40 words.
  - **Two cards instead of one**: when the back asks for more than one thing, the fix keeps one, and the other becomes a capture, as for a card with two ideas.
  - **Burying it**: when the card isn't worth the reviews it costs.
- **An expansion**: when what it adds fits on its card, within the 40 words, Claude proposes the card's new content. When it's another idea, like a second meaning, it becomes a card of its own.
- **A follow-up**: it becomes cards as a capture does, and they sit beside its card: they take its card's tags, and the card stays as it is. Its text often leans on the card ("¿Y cómo se eligen?" on a card about the branches of government), so each new front says on its own what it asks.

## Images and sounds

A side of a card can hold an image and a sound, with its text or alone, as the glossary's **Card** says. A file goes on a card only where Lucas asks: he points to a file on his Mac, such as "ponele este fragmento a coloratura", and Claude proposes the card and the side, then puts it there after his OK, through the CLI, as `/refine` says. Captures stay text: their cards hold a file only when Lucas points to one.

- **Putting one on**: the back takes a file that shows or plays the answer, as an aria's excerpt on the back of "coloratura"; the front takes one the card asks about, as a word to recognize by ear, and may then hold only the file. The text around it keeps the five rules. A side holds one image and one sound at most, so a file on a side that has one of its kind replaces it, and the proposal says so.
- **Taking one off**: when Lucas asks, Claude proposes the card without it. A side left without text, an image or a sound can't be saved, so the proposal gives that side text, or, when the CLI can't change the card's text, sends Lucas to the Cards window.
- **Keeping them**: a fix, or an expansion's new content, keeps the card's images and sounds unless Lucas asks to change them, and its proposal shows them, so he sees they stay.
- **What Claude knows of a file**: it can look at an image, to word the card, but not listen to a sound, so it goes by what Lucas says of a sound and by the file's name. When they leave the card or the side unclear, Claude asks.

## Examples

Each example is a card: its front in bold, then its back, then its tags in italics and its source, if it has one, after a dot. Most come from Ficha Dev's sample cards, some trimmed or with an example added. After Lucas's first refine session, cards of his own replace them.

### Word

> **serendipia**
> Un hallazgo valioso que se da por casualidad, cuando estabas buscando otra cosa. Por ejemplo: «Fue pura serendipia: entré a la librería por la lluvia y salí con mi libro favorito».
> _lenguaje_ · Un podcast de etimología

> **Schadenfreude**
> Palabra alemana: la alegría por la desgracia ajena. Viene de «Schaden», daño, y «Freude», alegría. Por ejemplo: «Sentí un poco de Schadenfreude cuando al que se coló en la fila lo mandaron al final».
> _lenguaje_

### Concept

> **ubuntu**
> Palabra de las lenguas bantúes del sur de África: una persona es persona a través de las demás. Se suele resumir como «soy porque somos».
> _filosofía_

> **La falacia del costo hundido**
> Seguir con algo solo por lo que ya invertiste, aunque no te convenga. Lo gastado no vuelve: para decidir, mirá lo que viene.
> _psicología_ · Pensar rápido, pensar despacio

### Quote

> **Caminante, no hay camino, se hace camino al andar.**
> Antonio Machado: el camino no está trazado de antemano; lo vas haciendo vos, con cada paso.
> _literatura_ · Campos de Castilla

> **Solo sé que no sé nada.**
> Se le atribuye a Sócrates, a partir de la «Apología» de Platón: reconocer lo que no sabés es el primer paso para aprender.
> _filosofía_

> **La suerte está echada.**
> Julio César, al cruzar el Rubicón con su ejército y desatar una guerra civil: la decisión está tomada y ya no hay vuelta atrás. En latín, «alea iacta est».
> _historia_ · Suetonio, Vidas de los doce césares

### Question

> **¿Por qué el cielo es azul?**
> Porque el aire dispersa mucho más la luz azul, de onda corta, que la roja, y esa luz dispersada te llega desde todo el cielo.
> _ciencia_ · Una charla de divulgación

> **¿En qué año llegó el ser humano a la Luna?**
> En 1969, con el Apolo 11: el 20 de julio, Neil Armstrong fue el primero en pisarla.
> _historia_
