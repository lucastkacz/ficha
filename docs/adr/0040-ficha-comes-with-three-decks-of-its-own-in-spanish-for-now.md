# Ficha comes with three decks of its own, in Spanish for now

ADR 0035 has Ficha come with four to six small decks of its own, in English, which ones still provisional: the types of clouds, the fourteen eight-thousanders, famous paintings and beautiful words were examples. On 2026-11-26 Lucas asked for three: forty pretty words, fifty paintings, and the flowers of Buenos Aires, those a florist there sells. In the proposal "Los mazos de Ficha" he chose those three alone, every painting Argentine, the picture on a card's front, and the decks in Spanish for now, since they're the ones he'll share with his friends for the beta; their English versions come later, and he brings them himself. He approved it as a decision the same day, in the artifact "Los mazos de Ficha: decisión". It changes ADR 0035 in part, how many decks, which ones and their language, and ADR 0032 in part, whose "in English alone" now holds for the app and not, for now, for Ficha's decks.

- **Three decks.** Palabras lindas, forty Spanish words, each with what it means and where it comes from (provisional); Arte argentino, fifty Argentine paintings; Flores de Buenos Aires, thirty flowers and greens a Buenos Aires florist sells. Their names are provisional, and Lucas approves each card before it ships, as ADR 0035 asks.
- **In Spanish for now.** The cards are in Spanish, for the friends' beta (#359). Their English versions come later, and Lucas brings them himself. The app stays in English alone (ADR 0036).
- **The picture on the front.** A painting or a flower shows on the front, and behind it its name and what goes with it: a painting's title, painter, year and museum; a flower's name and a line about it (provisional); last, the image's credit and license. A word card shows the word, and behind it what it means and where it comes from.
- **Only paintings in the public domain.** The painter died before 1956 and the painting is from before 1931, so it's free both in Argentina, where a painter's rights last seventy years after their death (Law 11.723), and in the US, as Wikimedia Commons asks of an image. Cándido López, Pueyrredón, Sívori, Della Valle, De la Cárcova, Malharro, Fader and Collivadino fit; Quinquela Martín, Berni, Xul Solar, Pettoruti and Spilimbergo don't. The list of fifty is drawn up while building, several paintings by each painter, and Lucas approves it.
- **The photos come from Wikimedia Commons.** The paintings in the public domain; the flowers under CC0, CC BY or CC BY-SA, CC0 first, with the author and the license on the card's back. A cloud session fetches them in Lucas's cloud environment «ficha», which allows `commons.wikimedia.org` and `upload.wikimedia.org`; the built-in one refuses both. The app grows by about 8 MB (an estimate: some 80 images of about 100 KB).

## Considered options

- Five decks, adding the types of clouds and the eight-thousanders, already written in the web mock: Lucas wanted his three alone.
- The decks in English now, as ADR 0035 has them: his friends test the beta in Spanish.
- Forty-two of the world's classics and eight Argentine paintings: Lucas chose all fifty Argentine.
- Modern Argentine painters, such as Quinquela Martín or Berni, without their picture: a deck of paintings that doesn't show them.
- The name on the front and the picture behind, or both ways: both ways doubles the reviews, and recognizing is what one does in a museum or at a flower stall.
- Lucas's own photos of a flower stall: left out for now.

## Consequences

- ADR 0035's four to six decks, and their English, go. The rest stays: the decks come inside the app, the Welcome page offers them (#467), each is a file in the app's resources that comes in through the same import as any file, and an update of the app leaves a deck the user added as it was. The friends' beta picks one of the three.
- `GLOSSARY.md`'s Ficha's decks, `PLIEGO.md`'s What it is and `CLAUDE.md` say three, in Spanish for now.
- #458 builds them, and the web mock changes first, as `PLIEGO.md`'s How it's drawn says of a proposal: its decks (`mockups/kit/decks.js`), the rule that has them in English (`mockups/README.md`, rule 4), and the Desktop mock's line that says so.
- No issue tracks the English versions: Lucas asked for none.
- Standard practice: Wikimedia Commons' rule that an image be free in its country and in the US, and Creative Commons attribution. Our own: the three decks, Argentine paintings alone, and Spanish before English.
