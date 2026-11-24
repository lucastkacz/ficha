// Compares Ficha's settings over weeks of a made-up working life, with the
// mock's toy engine (checked by mockups/tools/check-engine.js), from the
// terminal, in the repo's folder:
//   node mockups/tools/simulate.js                 Ficha's defaults against a few changes
//   node mockups/tools/simulate.js scenarios.json  your own: { "name": { ...changes } }
// A scenario changes the Lab's DEFAULTS in kit/lab.js, e.g.
//   { "Every hour": { "separationMinutes": 60 }, "3 a time": { "cardsPerAppearance": 3 } }
const fs = require('fs');
const path = require('path');
const kit = path.join(__dirname, '..', 'kit');
for (const f of ['engine.js', 'decks.js', 'lab.js']) require(path.join(kit, f));
const { simulate, DEFAULTS } = globalThis.FichaLab;

function readScenarios(file) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (e) {
    console.error(`Couldn't read ${file} as JSON: ${e.message}. Pass a file like { "name": { ...changes to kit/lab.js's DEFAULTS } }.`);
    process.exit(1);
  }
}

const scenarios = process.argv[2]
  ? readScenarios(process.argv[2])
  : {
      'Ficha today': {},
      'Every hour': { separationMinutes: 60 },
      '3 a time': { cardsPerAppearance: 3 },
      '10 new a day': { decks: [{ id: 'palabras', perDay: 5 }, { id: 'nubes', perDay: 5 }] },
      '85%': { retention: 0.85 },
    };

const isObject = (x) => x !== null && typeof x === 'object' && !Array.isArray(x);
const reject = (what) => {
  console.error(`${what}. A scenarios file is { "name": { ...changes to kit/lab.js's DEFAULTS } }.`);
  process.exit(1);
};
if (!isObject(scenarios)) reject(`${process.argv[2]} doesn't hold an object of scenarios`);
for (const [name, over] of Object.entries(scenarios)) {
  if (!isObject(over)) reject(`The scenario "${name}" isn't an object`);
  const unknown = Object.keys(over).filter((k) => !(k in DEFAULTS));
  if (unknown.length) reject(`The scenario "${name}" changes ${unknown.join(', ')}, which DEFAULTS don't have; its keys are ${Object.keys(DEFAULTS).join(', ')}`);
  if ('life' in over && !isObject(over.life)) reject(`The scenario "${name}" gives life as something other than an object`);
  const unknownLife = Object.keys(over.life || {}).filter((k) => !(k in DEFAULTS.life));
  if (unknownLife.length) reject(`The scenario "${name}" changes life's ${unknownLife.join(', ')}, which DEFAULTS.life doesn't have; its keys are ${Object.keys(DEFAULTS.life).join(', ')}`);
  if ('decks' in over && !Array.isArray(over.decks)) reject(`The scenario "${name}" gives decks as something other than an array, such as [{ "id": "palabras", "perDay": 5 }]`);
}

const start = globalThis.FichaLab.nextMonday(Date.now());
const results = Object.entries(scenarios).map(([name, over]) => [name, simulate(over, { start }).totals]);
const rows = [
  ['Appearances a weekday', (t) => t.appearancesPerWeekday.toFixed(1)],
  ['… per hour at the Mac', (t) => t.appearancesPerMacHour.toFixed(2)],
  ['Cards per appearance', (t) => t.cardsPerAppearance.toFixed(1)],
  ['Minutes a weekday', (t) => t.minutesPerWeekday.toFixed(1)],
  ['Busiest day, minutes', (t) => t.busiestMinutes.toFixed(1)],
  ['Held back a weekday', (t) => t.heldBackPerWeekday.toFixed(1)],
  ['Remembered on reviews', (t) => (t.recall == null ? '–' : `${Math.round(t.recall * 100)}%`)],
  ['All met on day', (t) => (t.allMetDay == null ? `never (${Math.round(t.allMetShare * 100)}%)` : `${(t.allMetDay + 1).toFixed(1)}, latest ${t.allMetLatest + 1}`)],
  ['Graduated by the end', (t) => `${Math.round(t.graduated)} of ${t.cards}`],
  ['Due and waiting at the end', (t) => t.dueLeft.toFixed(1)],
];
const width = Math.max(...rows.map(([r]) => r.length)) + 2;
const col = Math.max(14, ...results.map(([n]) => n.length + 2));
console.log(''.padEnd(width) + results.map(([n]) => n.padStart(col)).join(''));
for (const [label, f] of rows) console.log(label.padEnd(width) + results.map(([, t]) => f(t).padStart(col)).join(''));
