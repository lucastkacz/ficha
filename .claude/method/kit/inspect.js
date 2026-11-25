// The inspection: opens a page made with the kit as a phone and a laptop show it, light and dark, checks
// what .claude/method/artifacts.md asks of it, and leaves a picture of each card to look at.
// node .claude/method/kit/inspect.js <page.html> [outDir], from the repo's folder, on the machine the pliego's
// Where it runs gives the inspection of the method's pages (.claude/method/kit/README.md). outDir is
// <tmp>/inspect/<folder>-<page> when unset, and its last pictures go first. Prints the pictures' folder, then
// each failure with what to do about it; exits 1 when anything failed, 2 when it couldn't run, 0 when all passed.
const fs = require('fs');
const os = require('os');
const path = require('path');

const MAX_WORDS = 40; // per card, outside its drawings (artifacts.md)
const MAX_FIG_WORDS = 60; // per mock in a drawing, outside its SVG
const MAX_CAPTION_WORDS = 20; // per step of a movie
const MIN_STEPS = 4; // a movie, as the user approved it (artifacts.md)
const MAX_STEPS = 8;
const MAX_TABS = 5; // the tab bar at the bottom of a phone holds five
const MIN_TEXT_PX = 11;
const MIN_DRAWN_PX = 10; // a drawing's labels, as drawn on the screen: our own floor, a little under the text's
const MIN_TAP_PX = 28;
const SIZES = [
  { name: 'phone', width: 390, height: 700, mobile: true },
  { name: 'laptop', width: 1280, height: 760, mobile: false },
];
const README = '.claude/method/kit/README.md';

const [pageArg, outArg] = process.argv.slice(2);
if (!pageArg) {
  console.error(`Usage: node .claude/method/kit/inspect.js <page.html> [outDir]: pass the page's source, which loads kit/kit.css and kit/kit.js (${README}).`);
  process.exit(2);
}
const pageFile = path.resolve(pageArg);
if (!fs.existsSync(pageFile)) {
  console.error(`No ${pageFile}: pass the path of the page's source, the .html file you publish (${README}).`);
  process.exit(2);
}
let chromium;
try {
  ({ chromium } = require('playwright'));
} catch (e) {
  console.error("Couldn't load Playwright, which the inspection renders with: run it on the machine the pliego's Where it runs gives the inspection of the method's pages, which has Node and Playwright's Chromium.");
  process.exit(2);
}

const kitDir = __dirname;
const source = fs.readFileSync(pageFile, 'utf8');
const failures = [];
const fail = (msg) => { if (!failures.includes(msg)) failures.push(msg); };
if (!/href="kit\/kit\.css"/.test(source) || !/src="kit\/kit\.js"/.test(source)) {
  fail(`The page doesn't load the kit: put <link rel="stylesheet" href="kit/kit.css"> at its top and <script src="kit/kit.js"></script> at its end, as pieces.html does (${README}).`);
}
// The page as the Artifact tool publishes it: wrapped in its skeleton, with the kit's files beside it.
const page = source
  .replace(/<link[^>]*href="kit\/kit\.css"[^>]*>/, () => `<style>${fs.readFileSync(path.join(kitDir, 'kit.css'), 'utf8')}</style>`)
  .replace(/<script[^>]*src="kit\/kit\.js"[^>]*><\/script>/, () => `<script>${fs.readFileSync(path.join(kitDir, 'kit.js'), 'utf8')}</script>`);
const base = 'file://' + path.dirname(pageFile) + '/';
const html = `<!doctype html><html><head><meta charset=utf8><meta name=viewport content="width=device-width,initial-scale=1,viewport-fit=cover"><base href="${base}"><style>:root{color-scheme:light;padding-top:env(safe-area-inset-top,0px);padding-bottom:env(safe-area-inset-bottom,0px)}body{margin:0;font:14px system-ui}img{max-width:100%}[hidden]{display:none!important}</style></head><body>${page}</body></html>`;
const name = path.basename(pageFile, '.html');
const outDir = path.resolve(outArg || path.join(os.tmpdir(), 'inspect', `${path.basename(path.dirname(pageFile))}-${name}`));
if (outDir === path.dirname(pageFile)) {
  console.error(`The pictures' folder is the page's own, ${outDir}, which holds its sources: pass another folder, or none.`);
  process.exit(2);
}
fs.mkdirSync(outDir, { recursive: true });
// The last run's pictures go, and only those, so a card since removed leaves none behind.
const OWN = /^(phone|laptop)(-dark)?-.*\.png$/;
fs.readdirSync(outDir).filter((f) => OWN.test(f)).forEach((f) => fs.unlinkSync(path.join(outDir, f)));
const wrapped = path.join(outDir, '_page.html');
fs.writeFileSync(wrapped, html);

// The artifact's database, in memory, so the questions and Aprobar can be tried.
const fakeDb = () => {
  const docs = {}; const subs = [];
  const snap = () => ({ empty: !Object.keys(docs).length, docs: Object.entries(docs).map(([id, v]) => ({ id, data: () => v })) });
  window.__kitDocs = docs;
  window.claude = {
    use: async (n) => (n !== 'db' ? null : {
      collection: () => ({
        doc: (id) => ({ set: async (v) => { docs[id] = JSON.parse(JSON.stringify(v)); subs.forEach((f) => f(snap())); } }),
        onSnapshot: (cb) => { subs.push(cb); setTimeout(() => cb(snap()), 0); return () => {}; },
      }),
    }),
  };
};

// Runs in the page: what each tab, deck and card holds, and the checks that need no picture.
function survey(lim) {
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];
  const SKIP = 'svg,script,style,.k-fig,.k-pv,.k-ba,.k-movie,.k-terms,.k-qstate,.k-recb,.k-notebox,.k-ans,.k-apstate,.k-apbtn,.k-apnote,.k-head,[hidden]';
  const count = (s) => s.trim().split(/\s+/).filter((x) => /[\p{L}\p{N}]/u.test(x)).length;
  function words(root, skip) {
    let n = 0; const w = document.createTreeWalker(root, NodeFilter.SHOW_TEXT); let t;
    while ((t = w.nextNode())) {
      const p = t.parentElement; if (!p || (skip && p.closest(skip))) continue;
      const det = p.closest('details'); if (det && !det.open && !p.closest('summary')) continue;
      n += count(t.textContent);
    }
    return n;
  }
  const title = (c) => (c.querySelector('h2,h3') || {}).textContent?.trim() || '';
  const problems = [];
  if (!$$('.k-view').length) problems.push('The page has no .k-view: put each tab in a <section class="k-view" data-tab="…">, with a .k-deck of .k-card inside (README, A page).');
  const views = $$('.k-view').map((v) => ({
    id: v.id, tab: v.dataset.tab || v.id,
    decks: $$(':scope > .k-deck', v).map((dk) => ({ name: dk.dataset.name || '', cards: dk._cards ? dk._cards.length : 0 })),
    stray: $$('.k-card', v).filter((c) => !c.closest('.k-deck')).length,
  }));
  const where = (c) => { const v = c.closest('.k-view'); const dk = c.closest('.k-deck'); const cs = dk && dk._cards ? dk._cards : []; return `tab "${v ? v.dataset.tab || v.id : '?'}"${dk && dk.dataset.name ? `, deck "${dk.dataset.name}"` : ''}, card ${cs.indexOf(c) + 1}${title(c) ? ` "${title(c)}"` : ''}`; };
  $$('.k-card').forEach((c) => {
    const n = words(c, SKIP);
    if (n > lim.words) problems.push(`${where(c)}: ${n} words, over ${lim.words}. Cut it to a line per idea, and show the rest as a drawing, a before and after or a movie, or fold it (artifacts.md, The page).`);
    $$('.k-fig,.k-pv > [data-o],.k-ba [data-side],.k-sides > [data-side]', c).forEach((f) => {
      const m = words(f, 'svg,script,style');
      if (m > lim.fig) problems.push(`${where(c)}: a drawing, a preview or a side holds ${m} words outside its SVG, over ${lim.fig}. Put its labels inside the SVG, or say less (artifacts.md, The page).`);
    });
  });
  $$('.k-movie').forEach((m) => {
    const c = m.closest('.k-card'); const caps = $$(':scope > ol > li', m);
    if (caps.length < lim.minSteps || caps.length > lim.maxSteps) problems.push(`${where(c)}: a movie of ${caps.length} steps. Give it ${lim.minSteps} to ${lim.maxSteps}, one <li> each, or show it as steps or a drawing (artifacts.md, The page).`);
    caps.forEach((li, i) => { const n = count(li.textContent); if (n > lim.caption) problems.push(`${where(c)}: the movie's step ${i + 1} says ${n} words, over ${lim.caption}. Say one thing per step.`); });
    $$('[data-in],[data-out],[data-only],[data-skip],[data-on]', m).forEach((e) => {
      const nums = ['in', 'out', 'only', 'skip', 'on'].flatMap((k) => (e.dataset[k] || '').split(/\s+/).filter(Boolean).map(Number));
      const bad = nums.filter((x) => !(x >= 1 && x <= caps.length));
      if (bad.length) problems.push(`${where(c)}: a part of the movie names step ${bad[0]}, and it has ${caps.length}. Number its data-in, data-out, data-only, data-skip and data-on from 1 to ${caps.length}.`);
    });
  });
  const ids = {};
  $$('.k-q').forEach((q) => {
    const id = q.dataset.q; const opts = $$('.k-opts > li', q).map((li) => li.querySelector('[data-o]')?.dataset.o || li.dataset.o);
    if (!id) problems.push(`${where(q)}: a question with no data-q. Give it a short id; its answer is saved under it.`);
    else if (ids[id] || id === 'aprobacion') problems.push(`${where(q)}: the id "${id}" is taken${id === 'aprobacion' ? ' by the approval' : " by another question"}. Give each question its own data-q.`);
    ids[id] = true;
    if (opts.length < 2 || opts.length > 4) problems.push(`${where(q)}: ${opts.length} options. Give it 2 to 4 (artifacts.md, Questions).`);
    if (!opts.includes(q.dataset.rec)) problems.push(`${where(q)}: data-rec="${q.dataset.rec || ''}" names none of its options. Name the one you recommend.`);
    if (!q.querySelector('.k-why')) problems.push(`${where(q)}: no reason for the recommended option. Add <p class="k-why"> with it, in a line.`);
    const pv = $$('.k-pv > [data-o]', q).map((p) => p.dataset.o);
    opts.filter((o) => !pv.includes(o)).forEach((o) => problems.push(`${where(q)}: option ${o} has no preview. Add <div data-o="${o}"> to its .k-pv: its picture, its mock or its number (artifacts.md, Questions).`));
  });
  // Each note its own id, neither a question's nor the approval's, since each is saved under it.
  const noteIds = {};
  $$('.k-note').forEach((n) => {
    const id = n.dataset.id, c = n.closest('.k-card') || n;
    if (!id) problems.push(`${where(c)}: a note with no data-id. Give it a short id; the note is saved under it.`);
    else if (id === 'aprobacion' || ids[id] || noteIds[id]) problems.push(`${where(c)}: the note's id "${id}" is taken${id === 'aprobacion' ? ' by the approval' : ''}. Give each note its own data-id.`);
    noteIds[id] = true;
  });
  // A word shows its meaning, an issue what it does, and a link to a tab finds it.
  const termKey = (dt) => dt.dataset.term || dt.textContent.trim().normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
  const known = new Set($$('.k-terms dt').map(termKey));
  $$('.k-term').forEach((e) => { if (!known.has(e.dataset.term)) problems.push(`The word "${e.textContent.trim().slice(0, 30)}" has no meaning to show: give it the data-term of a <dt> in the page's dl.k-terms, or add one there with its <dd>.`); });
  $$('a.k-issue').forEach((a) => { if (!(a.dataset.tip || '').trim()) problems.push(`The issue "${a.textContent.trim().slice(0, 40)}" doesn't say what it does: put that, in a line, in its data-tip (artifacts.md, The page).`); });
  $$('a.k-go').forEach((a) => {
    const id = (a.getAttribute('href') || '').replace(/^#/, ''); let v = null;
    try { v = document.getElementById(decodeURIComponent(id)); } catch (e) { v = null; }
    if (!v || !v.classList.contains('k-view')) problems.push(`The link "${a.textContent.trim().slice(0, 30)}" goes to "#${id}", which no tab is: point its href at a view's id.`);
  });
  if (($$('.k-q,.k-note,.k-approve').length) && !document.querySelector('[data-db]')) problems.push('The page asks something but has no data-db: put data-db="<collection>" on its .k-top, one collection per artifact (artifacts.md, What the user answers).');
  // An issue shows its title, never its number alone (method.md, What the user sees).
  const w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT); let t;
  while ((t = w.nextNode())) {
    const p = t.parentElement; if (!p || p.closest('script,style,.k-fold')) continue;
    const m = t.textContent.match(/(^|[\s(\[,;:])#\d+\b/);
    if (m) problems.push(`The page shows "${m[0].trim()}" by its number: show the issue's title, linked, with what it does in data-tip (method.md, What the user sees).`);
  }
  $$('[data-tip]').forEach((e) => {
    const m = e.dataset.tip.match(/(^|[\s(\[,;:])#\d+\b/);
    if (m && !e.closest('.k-fold')) problems.push(`The tip of "${e.textContent.trim().slice(0, 30)}" shows "${m[0].trim()}" by its number: say what the issue does, in words (method.md, What the user sees).`);
  });
  $$('img').forEach((i) => { if (!i.complete || !i.naturalWidth) problems.push(`The picture ${i.getAttribute('src')} doesn't load: keep it beside the page, at the path the page names, and publish it in the Artifact tool's files.`); });
  if (!document.title.trim()) problems.push('The page has no <title>: name it in two to four words, as the Artifact tool asks.');
  return { views, problems, ready: document.body.classList.contains('k-ready') };
}

// Runs in the page, with one view and one deck showing: what's cut, too small or too wide.
function layout(lim) {
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];
  const out = [];
  const v = document.querySelector('.k-view.on');
  if (!v) return out;
  const title = (c) => (c.querySelector('h2,h3') || {}).textContent?.trim() || '';
  const dk = $$(':scope > .k-deck', v).find((x) => !x.hidden);
  if (dk) (dk._cards || []).forEach((c, i) => {
    const name = `card ${i + 1}${title(c) ? ` "${title(c)}"` : ''}`;
    if (c.scrollHeight - c.clientHeight > 4) out.push(`${name} is cut: it needs ${c.scrollHeight - c.clientHeight} px more than the screen gives it. Say less, make its drawing smaller, or split it into two cards (artifacts.md, The page).`);
    const cr = c.getBoundingClientRect();
    $$('svg', c).forEach((g) => { const r = g.getBoundingClientRect(); if (r.width && (r.bottom > cr.bottom + 2 || r.right > cr.right + 2)) out.push(`${name}: a drawing runs out of the card. Put it in a .k-fig, .k-movie or .k-pv, which size it to fit, or give it a viewBox and no fixed size.`); });
    if (c.scrollWidth - c.clientWidth > 1) out.push(`${name} is wider than the screen by ${c.scrollWidth - c.clientWidth} px. Give the wide part min-width:0, or let it wrap.`);
    // Each preview and each side shows in turn, so each must fit the box they share.
    $$('.k-pv', c).forEach((pv) => $$(':scope > [data-o]', pv).forEach((o) => {
      const over = Math.max(o.scrollHeight, o.getBoundingClientRect().height) - pv.clientHeight;
      if (over > 2) out.push(`${name}: option ${o.dataset.o}'s preview is cut by ${Math.round(over)} px. Draw it smaller, or say less in it.`);
    }));
    $$('.k-sides > [data-side]', c).forEach((s) => { if (s.scrollHeight - s.clientHeight > 2) out.push(`${name}: the side "${s.dataset.side}" is cut by ${s.scrollHeight - s.clientHeight} px. Draw it smaller, or say less in it.`); });
    // A drawing's labels, at the size the screen draws them.
    const tiny = new Set();
    $$('svg text', c).forEach((t) => {
      if (!t.textContent.trim() || t.closest('[hidden],.off')) return; // a part of a movie that's off is checked at its step
      const m = t.getScreenCTM(); if (!m) return;
      const px = parseFloat(getComputedStyle(t).fontSize) * Math.hypot(m.a, m.b);
      if (px < lim.drawn - 0.05) tiny.add(`${name}: the label "${t.textContent.trim().slice(0, 30)}" is drawn at ${px.toFixed(1)} px: make it at least ${lim.drawn}. Give the drawing a smaller viewBox, or its labels a bigger class (README, The pieces).`);
    });
    out.push(...tiny);
  });
  if (document.documentElement.scrollWidth > innerWidth + 1) out.push(`the page scrolls sideways by ${document.documentElement.scrollWidth - innerWidth} px. Find what's wider than the screen and let it wrap.`);
  // The page's own bars, which no card holds: the header, the tab bar, and the view's row of chips.
  const h1 = document.querySelector('.k-top h1');
  if (h1 && h1.scrollWidth - h1.clientWidth > 1) out.push(`@the page's name, "${h1.textContent.trim().slice(0, 30)}", doesn't fit its header: shorten it.`);
  // A tab's name, on a phone's bar, in at most two lines.
  const bar = document.querySelector('.k-tabs');
  if (bar && getComputedStyle(bar).position === 'fixed') $$('button', bar).forEach((b) => {
    const tx = [...b.childNodes].find((n) => n.nodeType === 3 && n.textContent.trim()); if (!tx) return;
    const rg = document.createRange(); rg.selectNodeContents(tx);
    const lines = new Set([...rg.getClientRects()].map((r) => Math.round(r.top))).size;
    if (lines > 2) out.push(`@the tab "${tx.textContent.trim().slice(0, 30)}" takes ${lines} lines on a phone's bar: name it in a word or two.`);
    if (b.scrollWidth - b.clientWidth > 1) out.push(`@the tab "${tx.textContent.trim().slice(0, 30)}" is wider than its place on a phone's bar: name it with shorter words.`);
  });
  [[document.querySelector('.k-top'), 'the header'], [document.querySelector('.k-tabs'), 'the tab bar'], [v.querySelector('.k-chaps'), 'the row of chips']].forEach(([e, what]) => {
    if (!e || !e.getClientRects().length) return;
    const at = what === 'the row of chips' ? '' : '@';
    if (e.scrollWidth - e.clientWidth > 1) out.push(`${at}${what} is wider than the screen by ${e.scrollWidth - e.clientWidth} px: shorten the names in it.`);
    $$('button', e).forEach((b) => { const r = b.getBoundingClientRect(); if (r.width && (r.right > innerWidth + 1 || r.left < -1)) out.push(`${at}${what}: "${b.textContent.trim().slice(0, 30)}" runs off the screen. Shorten the names in it.`); });
  });
  const small = new Set();
  for (const root of [v, document.querySelector('.k-top')].filter(Boolean)) {
  const tw = document.createTreeWalker(root, NodeFilter.SHOW_TEXT); let t;
  while ((t = tw.nextNode())) {
    const p = t.parentElement;
    if (!t.textContent.trim() || !p || p.closest('svg,script,style,.k-terms') || !p.getClientRects().length) continue;
    const cs = getComputedStyle(p), fs = parseFloat(cs.fontSize);
    if (fs < lim.text) small.add(`text "${t.textContent.trim().slice(0, 30)}" at ${fs} px: make it at least ${lim.text} px.`);
    if (cs.textOverflow === 'ellipsis' && p.scrollWidth > p.clientWidth + 1) small.add(`text "${t.textContent.trim().slice(0, 30)}" is cut with an ellipsis: let it wrap, or say it shorter.`);
  }
  }
  out.push(...small);
  const taps = $$('button,[role=button]:not(.k-term),summary,a.k-go,textarea,input', v).concat($$('.k-tabs button'));
  taps.forEach((b) => {
    if (b.closest('[hidden]')) return;
    const r = b.getBoundingClientRect();
    if (!r.width || !r.height) return;
    if (Math.min(r.width, r.height) < lim.tap) out.push(`"${(b.textContent || b.getAttribute('aria-label') || b.tagName).trim().slice(0, 30)}" is ${Math.round(r.width)}×${Math.round(r.height)} px: make what a finger taps at least ${lim.tap} px.`);
  });
  return out;
}

(async () => {
  let browser;
  try {
    browser = await chromium.launch();
  } catch (e) {
    console.error(`Couldn't start Chromium (${e.message.split('\n')[0]}): run the inspection on the machine the pliego's Where it runs gives the inspection of the method's pages, which has Playwright's Chromium.`);
    process.exit(2);
  }
  const lim = { words: MAX_WORDS, fig: MAX_FIG_WORDS, caption: MAX_CAPTION_WORDS, minSteps: MIN_STEPS, maxSteps: MAX_STEPS, text: MIN_TEXT_PX, drawn: MIN_DRAWN_PX, tap: MIN_TAP_PX };
  const shots = [];
  let tried = false;
  try {
    for (const dark of [false, true]) {
      for (const size of SIZES) {
        const label = `${size.name}${dark ? ', dark' : ''}`;
        const ctx = await browser.newContext({ viewport: { width: size.width, height: size.height }, isMobile: size.mobile, hasTouch: size.mobile, colorScheme: dark ? 'dark' : 'light', reducedMotion: 'reduce', deviceScaleFactor: 1 });
        await ctx.addInitScript(fakeDb);
        const pg = await ctx.newPage();
        const errors = [];
        // Only the fonts may fail, on a machine whose network doesn't reach them.
        pg.on('console', (m) => { if (m.type() === 'error' && !/fonts\.(googleapis|gstatic)\.com/.test(m.text() + ' ' + (m.location().url || ''))) errors.push(m.text()); });
        pg.on('pageerror', (e) => errors.push(e.message));
        await pg.goto('file://' + wrapped, { waitUntil: 'load', timeout: 30000 }).catch(() => {});
        await pg.evaluate(() => document.fonts && document.fonts.ready).catch(() => {});
        await pg.waitForTimeout(250);
        const s = await pg.evaluate(survey, lim);
        const tellErrors = () => errors.forEach((e) => fail(`${label}: the console says "${e.slice(0, 200)}". Fix it; a page reaches the user with no console errors.`));
        if (!s.ready) {
          fail(`${label}: the kit didn't start, so the rest wasn't checked at this size. The console errors say why.`);
          tellErrors(); await ctx.close(); continue;
        }
        if (!dark && size.mobile) {
          s.problems.forEach(fail);
          if (s.views.length > MAX_TABS) fail(`The page has ${s.views.length} tabs, over ${MAX_TABS}: a phone's tab bar holds ${MAX_TABS}. Join tabs, or put a round or a piece each in a deck of its own inside one tab (README, A page).`);
          s.views.forEach((v) => {
            if (v.stray) fail(`tab "${v.tab}": ${v.stray} card(s) outside a .k-deck. Put every card in a deck.`);
            if (!v.decks.length || v.decks.every((dk) => !dk.cards)) fail(`tab "${v.tab}" has no cards. Give it a .k-deck with at least one .k-card.`);
          });
        }
        for (const v of s.views) {
          for (let di = 0; di < Math.max(1, v.decks.length); di++) {
            await pg.evaluate(([id, i]) => { location.hash = id; window.Kit && window.Kit.show(id); const el = document.getElementById(id); if (el && el._pick) el._pick(i); }, [v.id, di]);
            await pg.waitForTimeout(200);
            const where = `${label}, tab "${v.tab}"${v.decks[di] && v.decks[di].name ? `, deck "${v.decks[di].name}"` : ''}`;
            (await pg.evaluate(layout, lim)).forEach((p) => fail(p[0] === '@' ? `${label}: ${p.slice(1)}` : `${where}: ${p}`));
            const stem = `${size.name}${dark ? '-dark' : ''}-${v.id}${v.decks.length > 1 ? '-' + (di + 1) : ''}`;
            const n = v.decks[di] ? v.decks[di].cards : 0;
            const perCard = size.mobile && !dark ? n : 1;
            for (let ci = 0; ci < perCard; ci++) {
              await pg.evaluate(([id, i, c]) => { const el = document.getElementById(id); const dk = [...el.querySelectorAll(':scope > .k-deck')][i]; if (dk && dk._go) dk._go(c); }, [v.id, di, ci]);
              await pg.waitForTimeout(150);
              const file = path.join(outDir, `${stem}${perCard > 1 ? '-' + (ci + 1) : ''}.png`);
              await pg.screenshot({ path: file });
              shots.push(file);
            }
          }
        }
        // Each movie at each of its steps, since a part can show at one step alone; a picture at the last.
        if (!dark) {
          const movies = await pg.evaluate(() => [...document.querySelectorAll('.k-movie')].map((m, i) => ({ i, view: m.closest('.k-view')?.id, n: m.querySelectorAll(':scope > ol > li').length })));
          for (const m of movies) {
            const seen = new Set();
            for (let k = 1; k <= m.n; k++) {
              await pg.evaluate(([id, i, k]) => { const mv = document.querySelectorAll('.k-movie')[i]; if (k === 1) { window.Kit.show(id); window.Kit.goTo(mv.closest('.k-card')); } mv._step && mv._step(k); }, [m.view, m.i, k]);
              await pg.waitForTimeout(k === 1 ? 250 : 120);
              (await pg.evaluate(layout, lim)).forEach((p) => { if (p[0] === '@') fail(`${label}: ${p.slice(1)}`); else if (!seen.has(p)) { seen.add(p); fail(`${label}, a movie at step ${k}: ${p}`); } });
            }
            const file = path.join(outDir, `${size.name}-movie-${m.i + 1}-last.png`);
            await pg.screenshot({ path: file });
            shots.push(file);
          }
        }
        // Answering a question and approving, once, saved in the database in memory.
        if (!dark && size.mobile && !tried) {
          tried = true;
          const r = await pg.evaluate(async () => {
            const q = document.querySelector('.k-q'); const ap = document.querySelector('.k-apbtn');
            const res = [];
            if (q) {
              window.Kit.goTo(q);
              const b = [...q.querySelectorAll('.k-opt')].find((x) => x.dataset.o !== q.dataset.rec);
              if (b) { b.click(); await new Promise((f) => setTimeout(f, 50)); const doc = window.__kitDocs[q.dataset.q]; if (!doc || doc.choice !== b.dataset.o) res.push(`choosing option ${b.dataset.o} of "${q.dataset.q}" didn't save it`); }
            }
            // A note typed just before another save comes back stays, and is saved: a question's, or else a piece's.
            const ta = (q && q.querySelector('.k-notebox textarea')) || document.querySelector('.k-note textarea');
            const nid = ta && (ta.closest('.k-q') ? ta.closest('.k-q').dataset.q : ta.closest('.k-note').dataset.id);
            if (ta) { ta.value = 'nota de prueba'; ta.dispatchEvent(new Event('input')); }
            if (ap) { ap.click(); await new Promise((f) => setTimeout(f, 50)); const doc = window.__kitDocs.aprobacion; if (!doc || !doc.approved) res.push("Aprobar didn't save the approval"); }
            if (ta) {
              if (ta.value !== 'nota de prueba') res.push('a note typed while another answer was saved was lost');
              ta.dispatchEvent(new Event('blur')); await new Promise((f) => setTimeout(f, 50));
              const doc = window.__kitDocs[nid]; if (!doc || doc.note !== 'nota de prueba') res.push(`the note "${nid}" wasn't saved when the user left it`);
            }
            return res;
          });
          r.forEach((p) => fail(`${label}: ${p}. Check the page's data-db, and the markup of its questions against pieces.html.`));
        }
        tellErrors();
        await ctx.close();
      }
    }
  } finally {
    await browser.close();
  }
  console.log(`Pictures: ${shots.length}, in ${outDir}. Look at each phone card, and at each tab in dark: the checks can't tell a drawing that reads wrong.`);
  if (failures.length) {
    console.log(`\n${failures.length} failed:`);
    failures.forEach((f) => console.log('- ' + f));
    process.exit(1);
  }
  console.log(`All passed: at most ${MAX_WORDS} words a card, nothing cut or too wide, text, labels and taps big enough, no console errors, on a phone and a laptop, light and dark.`);
})().catch((e) => {
  // What failed before it stopped is likely why: say it first.
  if (failures.length) { console.log(`${failures.length} failed before it stopped:`); failures.forEach((f) => console.log('- ' + f)); }
  console.error(`The inspection stopped: ${e.message.split('\n')[0]}. Fix what's listed, if anything, and run it again; if it stops at the same place, look at the page's script, and then at inspect.js.`);
  process.exit(failures.length ? 1 : 2);
});
