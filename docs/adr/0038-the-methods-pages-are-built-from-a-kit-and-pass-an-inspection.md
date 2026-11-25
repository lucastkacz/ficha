# The method's pages are built from a kit, and pass an inspection before they reach Lucas

On 2026-11-25 Lucas found the method's pages "conceptually good" but too dense: "muchísimo texto, muy cluttered", hard to take in, and he reviews them from his phone. Measured that day at a phone's size, the seven pages the commands had left him ran from 696 to 5,296 words, and from 5 to 26 screens each, about 550 words a tab, with two diagrams among them; on a phone, the decision "Hacia dónde va Ficha" cut its eight tabs. Each page was written by hand from scratch, laptop first, and nothing counted its text. He approved, in the artifact "Planos tipo del método", a kit of pieces the commands fill, an inspection that measures each page, and a map of the method made with it. It adds to ADR 0030, whose commands show Lucas what he decides in an artifact, how that artifact is built.

- **A kit of pieces**, in `.claude/method/kit/`: the look, a plan's paper in light and dark, and the pieces a command fills with its data: the movie, the before and after, a change, items, a tree, lanes, steps, bars, a drawing, a question with its previews, a note, Aprobar, terms and issues that explain themselves on a tap, and a fold. Plain CSS and JavaScript, loaded from beside the page, as the web mock kit is.
- **For a phone first**: at most five tabs, at the bottom of a phone and on top of a laptop, each a deck of cards the user swipes; several decks in one tab, such as a debate's rounds or a decision's pieces, picked from a row of chips.
- **One idea per card, in at most 40 words** outside its drawings; what doesn't fit is drawn.
- **A movie only for a process**, steps that happen in an order, as Lucas chose over a movie on every page.
- **An inspection**, `inspect.js`: it opens the page as a phone and a laptop show it, light and dark, fails it for what the rules above forbid, and leaves a picture of each card. A page reaches Lucas only once it passes.
- **A map of the method**, `.claude/method/map.html`: the seven commands in a movie, what each leaves, and the method's words, made with the kit.

## Considered options

- Pages left as they were, with a word limit added to `artifacts.md`: nothing would hold a page to it, and each page would still be drawn from scratch.
- A column of folded sections on a phone, or the page as it shows on a laptop: either keeps the scrolling Lucas found hard.
- A paragraph a card, 80 words, or no limit: the cards that need a paragraph are the ones a drawing explains better.
- A movie on every page, or behind a button: chosen against by Lucas, for a movie only where there's a process.
- The look of the AWS lessons, or Ficha's own: the method already speaks of building works, pliego and plano.
- Shorter skills too: the skills are read by agents, who aren't the ones who found them dense.

## Consequences

- `.claude/method/artifacts.md` points at the kit and its inspection; `/preparar`, `/debate` and a decision's page lay out in at most five tabs; the recorrida's columns are cards.
- `PLIEGO.md`'s How it's drawn and Where it runs name the kit and place its inspection in the cloud, and the pliego's template asks each project where the inspection runs.
- The pages published before the kit stay as they are; a page published again takes the kit then.
- A change to a piece changes `pieces.html` with it, and is inspected on it and on the map; a change to a command or a word changes the map.
- Standard practice: a component kit and an automated layout check. Our own: the pieces the method's pages need, the 40-word card, the inspection's rules, and its floor of 10 px for a drawing's labels as drawn. A word or an issue inside a line is a smaller tap, as WCAG 2.5.8's exception for inline targets allows.
