# Content guide

How Claude drafts Lucas's cards in a refine session: what each card holds, how long it is and how it's worded. The terms are `CONTEXT.md`'s.

## The four rules

1. **Rioplatense Spanish, with "vos"**: "sabés", "mirá", "tenés".
2. **One idea per card.** A capture with two ideas makes two cards, and so does a back that needs "y además".
3. **A one-line front, and a back of at most 40 words.** The review panel shows both without scrolling. Count the back's words before proposing it.
4. **Words from other languages, explained in Spanish.** The front keeps the word, or the quote, as it's written in its language; the back starts with the language and says what it means in Spanish ("Palabra alemana: …").

## Captures

A capture becomes one card, several or none. Several when it holds more than one idea; none when it isn't worth a card, and then Claude proposes discarding it. Pick each card's type by what Lucas has to remember, not by the capture's form: "cuándo llegamos a la Luna" is a question.

## Each type

- **Word** (`word`): the front is the word alone, in lowercase unless its language capitalizes it ("Schadenfreude"). The back is its meaning in plain words, and its etymology only when that helps remember it.
- **Concept** (`concept`): the front is the concept's name, with its article when Spanish uses one ("La navaja de Ockham"). The back says what it is in a sentence or two, and then, if there's room, who came up with it or an example.
- **Quote** (`quote`): the front is the quote, word for word, with its final punctuation. The back says who said it and what it means: in a review, Lucas rates whether he had understood it, so the meaning is the core of the back. Where it's from goes in the source.
- **Question** (`question`): the front is a question with one answer. The back gives that answer first, and then why or how, in a sentence.

## Tags

A tag is a subject, in Spanish and in lowercase: "lenguaje", "filosofía", "historia". A card has one usually, and three at most. Claude reuses the tags Lucas's cards already have, and says so when it proposes a new one, so Lucas sees it. A card that fits no subject has no tags.

## Sources

A card takes its capture's source as Lucas wrote it, and the review panel shows it small under the back, so the back doesn't repeat it.

## Flagged cards and expansions

- **A flagged card**: Claude changes what Lucas's note asks for and keeps the rest as it was, so he recognizes the card. When the note says the card is no longer worth it, Claude proposes burying it.
- **An expansion**: when what it adds fits on its card, within the 40 words, Claude proposes the card's new content. When it's another idea, like a second meaning, it becomes a card of its own.

## Examples

Each example is a card: its front in bold, then its back, then its tags in italics and its source, if it has one, after a dot.

### Word

> **serendipia**
> Un hallazgo valioso que se da por casualidad, cuando estabas buscando otra cosa.
> _lenguaje_ · Un podcast de etimología

> **Schadenfreude**
> Palabra alemana: la alegría por la desgracia ajena. Viene de «Schaden», daño, y «Freude», alegría.
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

### Question

> **¿Por qué el cielo es azul?**
> Porque el aire dispersa mucho más la luz azul, de onda corta, que la roja, y esa luz dispersada te llega desde todo el cielo.
> _ciencia_ · Una charla de divulgación

> **¿En qué año llegó el ser humano a la Luna?**
> En 1969, con el Apolo 11: el 20 de julio, Neil Armstrong fue el primero en pisarla.
> _historia_
