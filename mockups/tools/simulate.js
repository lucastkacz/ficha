// Compares Ficha's settings over weeks of a made-up working life, with the
// mock's toy engine (checked by tools/check-engine.js), from the terminal.
//   node tools/simulate.js                 Ficha's defaults against a few changes
//   node tools/simulate.js scenarios.json  your own: { "name": { ...changes } }
// A scenario changes the Lab's DEFAULTS in kit/lab.js, e.g.
//   { "Every hour": { "separationMinutes": 60 }, "3 a time": { "cardsPerAppearance": 3 } }
const fs = require('fs');
const path = require('path');
const kit = path.join(__dirname, '..', 'kit');
for (const f of ['engine.js', 'decks.js', 'lab.js']) require(path.join(kit, f));
const { simulate } = globalThis.FichaLab;

const scenarios = process.argv[2]
  ? JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
  : {
      'Ficha today': {},
      'Every hour': { separationMinutes: 60 },
      '3 a time': { cardsPerAppearance: 3 },
      '10 new a day': { decks: [{ id: 'palabras', perDay: 5 }, { id: 'nubes', perDay: 5 }] },
      '85%': { retention: 0.85 },
    };

const start = globalThis.FichaLab.nextMonday(Date.now());
const results = Object.entries(scenarios).map(([name, over]) => [name, simulate(over, { start }).totals]);
const rows = [
  ['Appearances a weekday', (t) => t.appearancesPerWeekday.toFixed(1)],
  ['… per hour at the Mac', (t) => t.appearancesPerMacHour.toFixed(2)],
  ['Cards per appearance', (t) => t.cardsPerAppearance.toFixed(1)],
  ['Minutes a weekday', (t) => t.minutesPerWeekday.toFixed(1)],
  ['Busiest day, minutes', (t) => t.busiestMinutes.toFixed(1)],
  ['Held back a weekday', (t) => t.heldBackPerWeekday.toFixed(1)],
  ['Recall on reviews', (t) => (t.recall == null ? '–' : `${Math.round(t.recall * 100)}%`)],
  ['All met on day', (t) => (t.allMetDay == null ? `never (${Math.round(t.allMetShare * 100)}%)` : `${(t.allMetDay + 1).toFixed(1)}, latest ${t.allMetLatest + 1}`)],
  ['Learned by the end', (t) => `${Math.round(t.learned)} of ${t.cards}`],
  ['Due and waiting at the end', (t) => t.dueLeft.toFixed(1)],
];
const width = Math.max(...rows.map(([r]) => r.length)) + 2;
const col = Math.max(14, ...results.map(([n]) => n.length + 2));
console.log(''.padEnd(width) + results.map(([n]) => n.padStart(col)).join(''));
for (const [label, f] of rows) console.log(label.padEnd(width) + results.map(([, t]) => f(t).padStart(col)).join(''));
