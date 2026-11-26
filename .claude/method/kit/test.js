// The kit's own test: the user's answers, notes and approval kept through a database that's slow, absent or
// failing, against pieces.html; and pages built from pieces.html with one defect each, which the inspection
// must fail, naming the defect. A change to the kit passes it before its reviews (README.md, Changing the kit).
// node .claude/method/kit/test.js, from the repo's folder, on the machine the pliego's Where it runs gives the
// inspection of the method's pages. Prints a line per case; exits 1 when any failed, 2 when it couldn't run.
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFile } = require('child_process');

const kitDir = __dirname;
const README = '.claude/method/kit/README.md';
let chromium;
try {
  ({ chromium } = require('playwright'));
} catch (e) {
  console.error("Couldn't load Playwright, which the test renders with: run it on the machine the pliego's Where it runs gives the inspection of the method's pages, which has Node and Playwright's Chromium.");
  process.exit(2);
}
const read = (f) => fs.readFileSync(path.join(kitDir, f), 'utf8');
const pieces = read('pieces.html');

let failed = 0, passed = 0;
const check = (name, problem) => {
  if (problem) { failed++; console.log(`FAIL ${name}: ${problem}`); } else { passed++; console.log(`ok   ${name}`); }
};

/* ---------- Saving: pieces.html, with an artifact database in memory the case controls ---------- */

// Runs in the page before the kit. mode.absent: 'none', no window.claude; 'null', no db; 'refused', use('db')
// throws. mode.slow: the first snapshot waits for __db.answer(). mode.docs: what the database holds at first.
// __db.hold holds each write until __db.release(); __db.fail(n, code) makes the next n writes throw.
function fakeDb(mode) {
  if (mode.absent === 'none') return;
  const copy = (v) => JSON.parse(JSON.stringify(v));
  const docs = copy(mode.docs || {}), subs = [], held = [];
  const db = window.__db = { docs, writes: [], hold: false, failing: 0, code: null, answered: false };
  const snap = () => ({ empty: !Object.keys(docs).length, docs: Object.entries(docs).map(([id, v]) => ({ id, data: () => copy(v) })) });
  const emit = () => { if (db.answered) subs.forEach(([ok]) => ok(snap())); };
  db.answer = () => { db.answered = true; emit(); };
  db.release = () => { while (held.length) held.shift()(); };
  db.fail = (n, code) => { db.failing = n; db.code = code || null; };
  db.lose = () => subs.forEach(([, err]) => err && err(new Error('the database went away')));
  async function set(id, v) {
    db.writes.push({ id, v: copy(v) });
    if (db.hold) await new Promise((f) => held.push(f));
    if (db.failing > 0) { db.failing--; throw Object.assign(new Error('the write failed'), db.code ? { code: db.code } : {}); }
    docs[id] = copy(v);
    emit();
  }
  window.claude = {
    use: async (n) => {
      if (mode.absent === 'refused') throw Object.assign(new Error('not granted'), { code: 'not_granted' });
      if (mode.absent === 'null' || n !== 'db') return null;
      return {
        collection: () => ({
          doc: (id) => ({ set: (v) => set(id, v) }),
          onSnapshot: (ok, err) => { subs.push([ok, err]); if (!mode.slow) setTimeout(db.answer, 0); return () => {}; },
        }),
      };
    },
  };
}

// The page as the Artifact tool serves it: wrapped in its skeleton, with kit/ beside it.
const ORIGIN = 'https://kit.test/';
const wrap = (src) => `<!doctype html><html><head><meta charset=utf-8><meta name=viewport content="width=device-width,initial-scale=1"></head><body>${src}</body></html>`;
async function openPieces(browser, mode = {}) {
  const ctx = await browser.newContext({ viewport: { width: 390, height: 700 }, isMobile: true, hasTouch: true, reducedMotion: 'reduce' });
  await ctx.route(/fonts\.(googleapis|gstatic)\.com/, (r) => r.abort());
  await ctx.route(ORIGIN + '**', (r) => {
    const p = new URL(r.request().url()).pathname;
    if (p === '/pieces.html') return r.fulfill({ contentType: 'text/html', body: wrap(pieces) });
    if (p === '/kit/kit.css') return r.fulfill({ contentType: 'text/css', body: read('kit.css') });
    if (p === '/kit/kit.js') return r.fulfill({ contentType: 'text/javascript', body: read('kit.js') });
    return r.fulfill({ status: 404, body: '' });
  });
  await ctx.addInitScript(fakeDb, mode);
  const pg = await ctx.newPage();
  const errors = [];
  pg.on('console', (m) => { if (m.type() === 'error' && !/fonts\.(googleapis|gstatic)\.com/.test(m.text() + ' ' + (m.location().url || ''))) errors.push(m.text()); });
  pg.on('pageerror', (e) => errors.push(e.message));
  await pg.clock.install();
  await pg.goto(ORIGIN + 'pieces.html');
  await pg.waitForFunction(() => document.body.classList.contains('k-ready'));
  // What a case does and reads, in the page, as a user's taps and what the screen says.
  await pg.evaluate(() => {
    const q = (id) => document.querySelector(`.k-q[data-q="${id}"]`);
    const box = (id) => (id === 'aprobacion' ? document.querySelector('.k-apnote') : (q(id) || document.querySelector(`.k-note[data-id="${id}"]`)).querySelector('.k-notebox textarea'));
    window.__t = {
      choose: (id, o) => q(id).querySelector(`.k-opt[data-o="${o}"]`).click(),
      type: (id, text) => { const ta = box(id); ta.value = text; ta.dispatchEvent(new Event('input')); },
      leave: (id) => box(id).dispatchEvent(new Event('blur')),
      approve: () => document.querySelector('.k-apbtn').click(),
      screen: () => {
        const ap = document.querySelector('.k-apbtn'), save = document.querySelector('.k-save');
        const pressed = {};
        document.querySelectorAll('.k-q').forEach((x) => { pressed[x.dataset.q] = (x.querySelector('.k-opt[aria-pressed="true"]') || {}).dataset?.o || null; });
        const notes = {};
        ['ritmo', 'mazos', 'nota-ritmo', 'aprobacion'].forEach((id) => { notes[id] = box(id).value; });
        return { status: save ? save.textContent : null, statusErr: !!save && save.classList.contains('err'), button: ap.textContent, buttonOff: ap.disabled, apState: document.querySelector('.k-apstate').textContent, pressed, notes };
      },
    };
  });
  // The kit's own words, which the screen shows.
  return { ctx, pg, errors, T: await pg.evaluate(() => window.Kit.text) };
}

const KIT = 'look at the saving part of kit.js, from "Questions, notes and the approval" on';
// Each case returns what broke, with where to look, or nothing.
const SAVING = [
  ['a choice, a note and Aprobar made before the database answers wait, and are saved once it does', { slow: true, docs: { ritmo: { choice: 'a', note: '', at: '2026-01-01T00:00:00Z' } } }, async (pg, run, T) => {
    await run((t) => { t.choose('ritmo', 'c'); t.type('nota-ritmo', 'antes'); t.leave('nota-ritmo'); t.approve(); });
    await pg.clock.runFor(10000);
    let s = await run((t) => t.screen());
    const early = await pg.evaluate(() => window.__db.writes.length);
    if (early) return `${early} write(s) went out before the database's first snapshot: what the user does waits for it, in queued. Then ${KIT}.`;
    if (s.button !== T.saving) return `Aprobar says "${s.button}" before the database answered: it says "${T.saving}" until the database holds the approval. Then ${KIT}.`;
    if (s.status !== T.slow) return `after 10 s with no answer, the status says "${s.status}": it says "${T.slow}". Then ${KIT}.`;
    await pg.evaluate(() => window.__db.answer());
    await pg.clock.runFor(100);
    const docs = await pg.evaluate(() => window.__db.docs);
    s = await run((t) => t.screen());
    if (docs.ritmo?.choice !== 'c') return `the choice made before the answer is "${docs.ritmo?.choice}" in the database, which held "a": the user's choice wins over the first snapshot. Then ${KIT}.`;
    if (docs['nota-ritmo']?.note !== 'antes') return `the note typed before the answer was saved as "${docs['nota-ritmo']?.note}". Then ${KIT}.`;
    if (!docs.aprobacion?.approved || s.button !== T.approved) return `the approval made before the answer wasn't saved, or Aprobar says "${s.button}". Then ${KIT}.`;
    if (s.status !== T.saved) return `once everything saved, the status says "${s.status}". Then ${KIT}.`;
  }],
  ['a note typed while another answer saves stays, and is saved', { docs: { ritmo: { choice: 'b', note: 'vieja', at: '2026-01-01T00:00:00Z' } } }, async (pg, run, T) => {
    await run((t) => { t.type('ritmo', 'nueva'); t.choose('mazos', 'b'); });
    await pg.clock.runFor(100);
    let s = await run((t) => t.screen());
    if (s.notes.ritmo !== 'nueva') return `the snapshot of another answer's save put back "${s.notes.ritmo}" over the note being typed: a snapshot leaves alone what touched holds. Then ${KIT}.`;
    await run((t) => t.leave('ritmo'));
    await pg.clock.runFor(100);
    const docs = await pg.evaluate(() => window.__db.docs);
    if (docs.ritmo?.note !== 'nueva' || docs.ritmo?.choice !== 'b') return `the note was saved as ${JSON.stringify(docs.ritmo)}: it's "nueva", with the choice the database held, "b". Then ${KIT}.`;
  }],
  ['a note typed while its own last save is on its way is saved after it', {}, async (pg, run, T) => {
    await pg.evaluate(() => { window.__db.hold = true; });
    await run((t) => { t.type('nota-ritmo', 'uno'); t.leave('nota-ritmo'); t.type('nota-ritmo', 'uno dos'); t.leave('nota-ritmo'); });
    await pg.evaluate(() => { window.__db.hold = false; window.__db.release(); });
    await pg.clock.runFor(100);
    const docs = await pg.evaluate(() => window.__db.docs), s = await run((t) => t.screen());
    if (docs['nota-ritmo']?.note !== 'uno dos') return `the database holds "${docs['nota-ritmo']?.note}": the save that came back first put back an older note, or the second save never went. Then ${KIT}.`;
    if (s.notes['nota-ritmo'] !== 'uno dos' || s.status !== T.saved) return `the screen shows "${s.notes['nota-ritmo']}" and the status "${s.status}". Then ${KIT}.`;
  }],
  ...[['none', 'no window.claude'], ['null', 'no database'], ['refused', 'a database it may not use'], ['lost', 'a database that stops answering']].map(([absent, what]) => [
    `a view with ${what} says it doesn't save, and leaves Aprobar off`, absent === 'lost' ? {} : { absent }, async (pg, run, T) => {
      if (absent === 'lost') await pg.evaluate(() => window.__db.lose());
      await run((t) => { t.choose('mazos', 'b'); t.type('nota-ritmo', 'x'); t.leave('nota-ritmo'); t.approve(); });
      await pg.clock.runFor(3000);
      const s = await run((t) => t.screen()), writes = await pg.evaluate(() => (window.__db ? window.__db.writes.length : 0));
      if (s.apState !== T.noSave || !s.buttonOff) return `Aprobar is ${s.buttonOff ? 'off' : 'on'} and says "${s.apState}": a view that can't save keeps it off, and says "${T.noSave}". Then ${KIT}.`;
      if (s.pressed.mazos !== 'a' || writes) return `a tap in a view that can't save chose "${s.pressed.mazos}", or wrote ${writes} time(s): it changes nothing. Then ${KIT}.`;
    }]),
  ['a view that loses the right to save goes read-only, and takes back the approval it hadn\'t saved', {}, async (pg, run, T) => {
    await pg.evaluate(() => { window.__db.hold = true; window.__db.fail(1, 'revoked'); });
    await run((t) => t.approve());
    await pg.evaluate(() => window.__db.release());
    await pg.clock.runFor(100);
    const s = await run((t) => t.screen()), docs = await pg.evaluate(() => window.__db.docs);
    if (s.status !== T.readOnly) return `the status says "${s.status}": a revoked database says "${T.readOnly}". Then ${KIT}.`;
    if (s.button !== T.approve || !s.buttonOff || docs.aprobacion) return `Aprobar says "${s.button}" and is ${s.buttonOff ? 'off' : 'on'}: an approval the database never held is taken back, and a read-only view keeps Aprobar off. Then ${KIT}.`;
  }],
  ['a choice that doesn\'t save says so, holds Aprobar back, and is tried again by itself', {}, async (pg, run, T) => {
    await pg.evaluate(() => window.__db.fail(1));
    await run((t) => t.choose('mazos', 'b'));
    await pg.clock.runFor(100);
    let s = await run((t) => t.screen());
    if (s.status !== T.notSaved || !s.statusErr) return `after a failed save the status says "${s.status}": it says "${T.notSaved}", in red. Then ${KIT}.`;
    if (!s.buttonOff || s.apState !== T.unsaved) return `while an answer isn't saved, Aprobar is ${s.buttonOff ? 'off' : 'on'} and says "${s.apState}": it waits, and says "${T.unsaved}". Then ${KIT}.`;
    await pg.clock.runFor(2100);
    const docs = await pg.evaluate(() => window.__db.docs);
    s = await run((t) => t.screen());
    if (docs.mazos?.choice !== 'b') return `2 s later the choice still isn't in the database: a failed save is tried again by itself. Then ${KIT}.`;
    if (s.status !== T.saved || s.buttonOff || s.apState !== T.withChoices) return `once the retry saved, the status says "${s.status}" and Aprobar is ${s.buttonOff ? 'off' : 'on'}. Then ${KIT}.`;
  }],
  ['a save that keeps failing stops after three more tries, and the next tap saves it', {}, async (pg, run, T) => {
    await pg.evaluate(() => window.__db.fail(99));
    await run((t) => t.choose('mazos', 'b'));
    await pg.clock.runFor(30000);
    const writes = await pg.evaluate(() => window.__db.writes.length);
    let s = await run((t) => t.screen());
    if (writes !== 4) return `a save that always fails was sent ${writes} time(s) in 30 s: once, and three more tries, 2, 4 and 6 s apart. Then ${KIT}.`;
    if (s.status !== T.notSaved || !s.buttonOff) return `after the last try the status says "${s.status}" and Aprobar is ${s.buttonOff ? 'off' : 'on'}. Then ${KIT}.`;
    await pg.evaluate(() => window.__db.fail(0));
    await run((t) => t.choose('mazos', 'b'));
    await pg.clock.runFor(100);
    s = await run((t) => t.screen());
    if ((await pg.evaluate(() => window.__db.docs.mazos?.choice)) !== 'b' || s.status !== T.saved || s.buttonOff) return `the user's tap after the tries didn't save, or the status says "${s.status}". Then ${KIT}.`;
  }],
  ['an approval that doesn\'t save is taken back, and pressing Aprobar again saves it', {}, async (pg, run, T) => {
    await pg.evaluate(() => window.__db.fail(1));
    await run((t) => t.approve());
    await pg.clock.runFor(10000);
    let s = await run((t) => t.screen());
    if (s.button !== T.approve || s.buttonOff) return `after a failed approval Aprobar says "${s.button}" and is ${s.buttonOff ? 'off' : 'on'}: it's taken back, so the user can press it again. Then ${KIT}.`;
    if (await pg.evaluate(() => window.__db.docs.aprobacion)) return `the approval reached the database by itself after it failed: it waits for the user's press. Then ${KIT}.`;
    if (s.status !== T.notSaved) return `after a failed approval the status says "${s.status}". Then ${KIT}.`;
    await run((t) => t.approve());
    await pg.clock.runFor(100);
    s = await run((t) => t.screen());
    if (!(await pg.evaluate(() => window.__db.docs.aprobacion?.approved)) || s.button !== T.approved || s.status !== T.saved) return `the second press didn't save the approval: Aprobar says "${s.button}", the status "${s.status}". Then ${KIT}.`;
  }],
  ['an approval that saved is never taken back, by a note that fails or a database that goes away', {}, async (pg, run, T) => {
    await pg.evaluate(() => { window.__db.hold = true; });
    await run((t) => { t.type('aprobacion', 'uno'); t.approve(); t.type('aprobacion', 'uno dos'); });
    await pg.evaluate(() => { window.__db.hold = false; window.__db.release(); });
    await pg.clock.runFor(100);
    if (!(await pg.evaluate(() => window.__db.docs.aprobacion?.approved))) return `the approval, sent while its note was typed, didn't reach the database. Then ${KIT}.`;
    await pg.evaluate(() => window.__db.fail(99));
    await run((t) => t.leave('aprobacion'));
    await pg.clock.runFor(100);
    let s = await run((t) => t.screen());
    if (s.button !== T.approved) return `the approval saved, then the note's save failed, and Aprobar says "${s.button}": a field the database holds leaves the pending set. Then ${KIT}.`;
    await pg.evaluate(() => window.__db.lose());
    s = await run((t) => t.screen());
    if (s.button !== T.approved) return `the approval saved, then the database went away, and Aprobar says "${s.button}". Then ${KIT}.`;
  }],
];

async function saving(browser) {
  for (const [name, mode, body] of SAVING) {
    let ctx, problem;
    try {
      const o = await openPieces(browser, mode);
      ctx = o.ctx;
      const run = (fn) => o.pg.evaluate(`(${fn})(window.__t)`);
      problem = await body(o.pg, run, o.T);
      if (!problem && o.errors.length) problem = `the console says "${o.errors[0].slice(0, 200)}". Fix it in kit.js; a page reaches the user with no console errors.`;
    } catch (e) {
      problem = `it stopped: ${e.message.split('\n')[0]}. Look at the case's steps against kit.js and pieces.html.`;
    }
    if (ctx) await ctx.close();
    check(name, problem);
  }
}

/* ---------- The inspection: pages with one defect each, which it must fail, naming the defect ---------- */

// Each defect: its name, what it changes in pieces.html, and what the inspection's failures must say.
// A failure that matches none of them is a wrong failure, unless every page shows it, the plain one too.
const tooSmall = '<text class="s" x="20" y="200" data-only="3" style="font-size:5px">diminuta</text>';
const DEFECTS = [
  ['a tab whose name runs off a phone\'s bar', ['data-tab="Preguntas"', 'data-tab="Las preguntas de la ronda"'], [/the tab "Las preguntas de la ronda" (takes \d+ lines|is wider than its place)/]],
  ['a page whose name doesn\'t fit its header', ['<h1>Piezas tipo</h1>', '<h1>Piezastipoparatodaslaspaginasdelmetodo</h1>'], [/the page's name, "Piezastipo[^"]*", doesn't fit its header/, /the header is wider than the screen/, /the page scrolls sideways/]],
  ['a drawing\'s label too small at a movie\'s middle step', ['</svg>\n        <ol>', `  ${tooSmall}\n        </svg>\n        <ol>`], [/a movie at step 3: .*the label "diminuta" is drawn at/]],
  ['words in a legend, over a card\'s limit', ['<span>○ abierto</span></p>', '<span>○ abierto</span><span>y una leyenda tan larga que pasa sola el límite de palabras de una tarjeta aunque nadie la mire como texto, porque una leyenda también se lee</span></p>'], [/card \d+ "El ritmo": \d+ words, over 40/]],
  ['a note whose id is the approval\'s', ['data-id="nota-ritmo"', 'data-id="aprobacion"'], [/the note's id "aprobacion" is taken by the approval/]],
  ['a note whose id is a question\'s', ['data-id="nota-ritmo"', 'data-id="ritmo"'], [/the note's id "ritmo" is taken/]],
  ['two notes with one id', ['</ul>\n    </article>\n    <article class="k-card">\n      <p class="k-kick">Carriles', '</ul>\n      <div class="k-note" data-id="nota-ritmo"></div>\n    </article>\n    <article class="k-card">\n      <p class="k-kick">Carriles'], [/the note's id "nota-ritmo" is taken/]],
  ['a word with no meaning', ['data-term="pliego">pliego', 'data-term="plano">pliego'], [/The word "pliego" has no meaning to show/]],
  ['an issue that doesn\'t say what it does', [' data-tip="Lo que hace el issue, en una línea."', ''], [/The issue "El título del issue" doesn't say what it does/]],
  ['a link to a tab that isn\'t there', ['href="#pelicula"', 'href="#peli"'], [/The link "Ver la película ›" goes to "#peli", which no tab is/]],
];

function inspect(file, out) {
  return new Promise((resolve) => {
    execFile(process.execPath, [path.join(kitDir, 'inspect.js'), file, out], { maxBuffer: 1 << 24 }, (err, stdout, stderr) => {
      const code = err ? (typeof err.code === 'number' ? err.code : 2) : 0;
      resolve({ code, failures: stdout.split('\n').filter((l) => l.startsWith('- ')).map((l) => l.slice(2)), stderr: stderr.trim() });
    });
  });
}

async function inspection() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'kit-test-'));
  const pages = [['the plain pieces page', pieces]];
  for (const [name, [from, to]] of DEFECTS) {
    if (!pieces.includes(from)) { check(name, `pieces.html no longer holds ${JSON.stringify(from.slice(0, 60))}, which this defect changes: change the defect in test.js to what pieces.html holds now.`); continue; }
    pages.push([name, pieces.replace(from, to)]);
  }
  // Each page in a folder of its own, its pictures in another; a few inspections at a time.
  const runs = pages.map(([name, src], i) => {
    const dir = path.join(tmp, `page-${i}`);
    fs.mkdirSync(dir);
    fs.writeFileSync(path.join(dir, 'pieces.html'), src);
    return { name, file: path.join(dir, 'pieces.html'), out: path.join(tmp, `out-${i}`) };
  });
  let next = 0;
  const worker = async () => { while (next < runs.length) { const r = runs[next++]; r.result = await inspect(r.file, r.out); } };
  await Promise.all(Array.from({ length: Math.max(1, Math.min(4, os.cpus().length)) }, worker));
  fs.rmSync(tmp, { recursive: true, force: true });

  const [plain, ...broken] = runs;
  const shared = new Set(plain.result.failures);
  if (plain.result.code === 2) { check(plain.name, `the inspection couldn't run: ${plain.result.stderr.slice(0, 300)}`); return; }
  check(`the inspection passes ${plain.name}`, plain.result.code === 0 ? null : `it failed it:\n  - ${plain.result.failures.join('\n  - ')}\nFix pieces.html, or the check that's wrong in inspect.js, until the inspection passes it (${README}, Changing the kit).`);
  for (const r of broken) {
    const [, , want] = DEFECTS.find(([n]) => n === r.name);
    const { code, failures, stderr } = r.result;
    let problem = null;
    if (code === 2) problem = `the inspection couldn't run: ${stderr.slice(0, 300)}`;
    else if (code === 0) problem = 'the inspection passed it. Bring back, in inspect.js, the check that finds it.';
    else if (!failures.some((f) => want[0].test(f))) problem = `the inspection didn't name it; it said:\n  - ${failures.join('\n  - ')}\nBring back, in inspect.js, the check that finds it, or change its failure's words here with it.`;
    else {
      const wrong = failures.filter((f) => !shared.has(f) && !want.some((w) => w.test(f)));
      if (wrong.length) problem = `the inspection also named what the defect doesn't break:\n  - ${wrong.join('\n  - ')}\nFind why in inspect.js.`;
    }
    check(`the inspection fails ${r.name}`, problem);
  }
}

/* ---------- The kit's README and its words ---------- */

function docs() {
  const readme = read('README.md');
  const part = (readme.split(/^## Changing the kit$/m)[1] || '').split(/^## /m)[0];
  check('the README\'s Changing the kit runs this test before a change\'s reviews', /test\.js/.test(part) && /review/.test(part) ? null : `${README}, Changing the kit, doesn't say that a change to the kit passes test.js before its reviews: say it there.`);
  // The kit serves any project: none of its files names the one it lives in, as its pliego's title does.
  const pliego = path.resolve(kitDir, '..', '..', '..', 'PLIEGO.md');
  const project = fs.existsSync(pliego) && (fs.readFileSync(pliego, 'utf8').match(/^# Pliego of (.+)$/m) || [])[1];
  if (!project) { check('the kit names no fact of the project it lives in', null); return; }
  const named = fs.readdirSync(kitDir).filter((f) => new RegExp(`\\b${project.trim()}\\b`).test(read(f)));
  check('the kit names no fact of the project it lives in', named.length ? `${named.join(', ')} name(s) "${project.trim()}", the project's name in its pliego: the kit and its examples serve any project, so give them a generic example (.claude/method/method.md).` : null);
}

(async () => {
  let browser;
  try {
    browser = await chromium.launch();
  } catch (e) {
    console.error(`Couldn't start Chromium (${e.message.split('\n')[0]}): run the test on the machine the pliego's Where it runs gives the inspection of the method's pages, which has Playwright's Chromium.`);
    process.exit(2);
  }
  try {
    await saving(browser);
  } finally {
    await browser.close();
  }
  await inspection();
  docs();
  console.log(failed
    ? `\n${failed} of ${failed + passed} failed: fix kit.js, inspect.js, pieces.html or the README as each line says, and run it again before the change's reviews (${README}, Changing the kit).`
    : `\nAll ${passed} passed.`);
  process.exit(failed ? 1 : 0);
})().catch((e) => {
  console.error(`The test stopped: ${e.message.split('\n')[0]}. Run it again; if it stops at the same place, look at test.js.`);
  process.exit(2);
});
