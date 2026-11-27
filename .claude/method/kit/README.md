# The page kit

The pieces every page of the method is built from, drawn once and filled with each command's data, and the inspection that measures a page before the user gets its link ([`../artifacts.md`](../artifacts.md)). Plain CSS and JavaScript: no library and no build step. A page loads the kit from `kit/` beside it, as its Artifact serves it.

| File | What it holds |
|---|---|
| `kit.css` | The look, a plan's paper in light and dark; the tabs, decks and cards; each piece, and the classes drawings share. |
| `kit.js` | What the pieces do, and the user's answers, notes and approval, kept in the artifact's database. |
| `pieces.html` | Every piece once, as a page uses it, published where the pliego's How it's drawn says. |
| `inspect.js` | The inspection. |
| `test.js` | The kit's own test: its saving, and pages the inspection must fail. |

## A page

1. Copy `pieces.html`'s head (the title, the fonts and the kit's stylesheet) and its last line (the kit's script). Name the page in its `<title>`.
2. `header.k-top`, with a `p.k-kick` and the page's name in an `h1`. When the page asks anything, `data-db="<collection>"` on it, a collection per artifact.
3. A `section.k-view` per tab, as many as [`../artifacts.md`](../artifacts.md) allows, each with an `id`, its name in `data-tab`, and an icon in `data-icon`: `home`, `play`, `ask`, `list`, `check`, `tree`, `map`, `clock`, `layers`, `book` or `grid`. A page of one view has no tab bar.
4. In each view, a `div.k-deck` of `article.k-card`s, one idea per card. Several decks in one view, such as a debate's rounds or a decision's pieces, each name themselves in `data-name` and show one at a time, picked from a row of chips: the last, unless one has `data-open`.
5. In each card, a title and the pieces below, copied from `pieces.html` and filled with the page's data. A word the page uses with a meaning goes in its `dl.k-terms`.

Done when every card holds one idea, in pieces.

## The pieces

| Piece | Its markup, as `pieces.html` shows it | For |
|---|---|---|
| Movie | `figure.k-movie`: an `svg` whose parts appear and go with `data-in`, `data-out`, `data-only`, `data-skip`, or get marked with `data-on`, by step number; then an `ol`, a caption per step, each with a short `data-label` | A process: steps that happen in an order |
| Before and after | `figure.k-ba`, two `div[data-side]` | A change to something the user sees |
| A change | `ul.k-changes[data-from][data-to]`, two `span`s a row | A decision's home: today, and with the decision |
| Items | `ul.k-items`, each `li[data-s]`: `done` ✓, `prov` ◐, `open` ○, `built` ■ | What gets built; the pliego's items |
| Tree | `ul.k-tree`, nested, each top `li` colored with `--c` | Areas and nodes |
| Lanes | `div.k-lanes`, a `section` each, with `h3`, `ul` and `p` | Columns side by side: where it runs, hands-free |
| Steps | `ol.k-steps`, `li[data-s]`: `done`, `now` | The order of the work, and where it is |
| Bars | `ul.k-bars`, `li[data-n]` | Counts, such as open issues by area |
| Number | `p.k-num` with a `b` | The one number that matters |
| Drawing | `figure.k-fig`, an `svg` or an `img` | A diagram, the plano, a picture |
| Question | `article.k-card.k-q[data-q][data-rec]`: `h2`, `div.k-pv` with a `div[data-o]` per option, `ul.k-opts` with an `li[data-o]` per option, `p.k-why` | A question for the user |
| Note | `div.k-note[data-id][data-label]` | A note on a piece |
| Aprobar | `article.k-card.k-approve`, with its title and a line | The approval, with the answers chosen |
| Term | `span.k-term[data-term]`, and its meaning in `dl.k-terms` | A word of the method or the glossary |
| Issue | `a.k-issue` to the issue, its title as the text, what it does in `data-tip` | An issue, never by its number |
| Fold | `details.k-fold`, `lang="en"` for the agent's part | What only an agent reads |
| Small | `code.k-cmd`, `span.k-badge` (`ok`, `warn`, `bad`), `a.k-go[href="#<view>"]`, `p.k-kick`, `p.k-lead`, `p.k-row` | A command, a state, a way to another tab |

A drawing's `svg` has a `viewBox` and no size, and its labels inside, drawn no smaller than `inspect.js` allows: a viewBox about as wide as a phone's card in pixels keeps the `s` class above it. Its shapes and text take the classes `kit.css` gives drawings: `box`, `paper` and `ghost` for shapes; `blue`, `green`, `amber`, `red`, `orange` and `pink` for tints, with `solid` for the full color; `h`, `s` and `m` for a title, small and mono text, `c` and `e` to center or right-align it, `on` over a solid color; `ln`, `arr`, `arr flow` and `arr back` for lines; `pulse` and `float` to move; `hl` to mark. A drawing no class covers takes the page's own `<style>`, in the kit's tokens.

The kit's own words, such as Reproducir and Aprobar, are in Spanish. A page in another language sets `window.KIT_TEXT`, with the keys of `T` in `kit.js`, before the kit's script.

## The inspection

From the repo's folder, on the machine the pliego's Where it runs gives the inspection of the method's pages:

```
node .claude/method/kit/inspect.js <page.html> [outDir]
```

It opens the page as a phone and a laptop show it, light and dark, with the kit beside it and an artifact database in memory. It fails the page for what the constants at the top of `inspect.js` limit: the words of a card, a drawing and a movie's caption; a movie's steps; the tabs; and the size of text, of a drawing's labels as the screen draws them, and of what a finger taps. It fails it too for a card, a preview or a side that's cut; anything wider than the screen; text cut short; a question without its options, a preview for each, a recommendation and its reason; an issue shown by its number; a picture that doesn't load; or an error in the console. It answers a question, types a note, a question's or else a piece's, and approves, and fails if any of them wasn't saved; and it fails a note or a question whose id is taken, a word with no meaning, an issue that doesn't say what it does, and a link to a tab that isn't there. A word or an issue inside a line of text is a smaller tap, as WCAG 2.5.8's exception for inline targets allows, so it isn't measured. Each failure says what to do. It leaves, in a folder it empties of its last run's pictures, never the page's own, a picture of each card on a phone, of each tab on a laptop and in dark, and of each movie at its last step. Where the network doesn't reach Google Fonts, their failed loads don't count, and the pictures show the fallback fonts.

Done when it prints "All passed", and its pictures read right.

## Publishing

With the Artifact tool: the page as `file_path`, and in `files` the kit, `{"kit/kit.css": ".claude/method/kit/kit.css", "kit/kit.js": ".claude/method/kit/kit.js"}`, with the page's pictures at the paths it names. A page that asks anything declares `capabilities: {db: {}, user: {}}`. A page published again without `files` keeps the kit it had; pass the kit again to bring it up to date.

## Changing the kit

A change to a piece changes `pieces.html` with it. Its examples are about a neighborhood garden, a topic no project of ours has, so a project's decisions never make them old: a new piece's example is about the garden too. A saving rule or an inspection check the change adds gets a case in `test.js`, with generic examples, and a failure whose words the change rewrites changes its case's.

Before the change's reviews, it passes the inspection on `pieces.html` and on [`../map.html`](../map.html), and the kit's test, from the repo's folder, on the machine the pliego's Where it runs gives the inspection of the method's pages:

```
node .claude/method/kit/test.js
```

It tries the answers, notes and approval against `pieces.html`, with a database that's slow, absent or failing, and runs the inspection on copies of `pieces.html` with one defect each, which it must fail, naming the defect.

Before its PR is ready, both pages are published again at the links the pliego's How it's drawn gives, so the user sees the change while it waits to merge.

Done when the test prints "All … passed", both pages pass the inspection, and both are published.
