/* The method's page kit: what the pieces do (.claude/method/kit/README.md). Plain JavaScript, no library.
   It turns the page's markup into tabs, decks you swipe, movies, before-and-afters and questions,
   and keeps the user's answers, notes and approval in the artifact's database. */
(() => {
  'use strict';
  const d = document;
  const $$ = (s, r = d) => [...r.querySelectorAll(s)];
  const el = (tag, cls, html) => { const e = d.createElement(tag); if (cls) e.className = cls; if (html != null) e.innerHTML = html; return e; };
  const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const phone = () => innerWidth < 640;

  // The kit's own words, in the user's language. A page in another language sets window.KIT_TEXT first.
  const T = Object.assign({
    card: 'Tarjeta', of: 'de', play: '▶ Reproducir', pause: '❚❚ Pausa', again: '↺ De nuevo',
    prev: 'Anterior', next: 'Siguiente', today: 'Hoy', after: 'Con esto', rec: 'Recomendada', yours: 'tuya',
    unanswered: 'Sin responder: va la recomendada', chosen: 'Elegiste', addNote: '+ Agregar una nota', note: 'Nota',
    notePh: 'Lo que ninguna opción dice…', approve: 'Aprobar', approved: 'Aprobado ✓',
    approvedAt: (t) => `Aprobado el ${t}. Ya lo leo.`, withChoices: 'Con lo que elegiste.', noSave: 'En esta vista no se guarda.',
    saving: 'Guardando…', saved: 'Guardado ✓', upToDate: 'Al día ✓', ready: 'Listo para tus respuestas', readOnly: 'Solo lectura',
    notSaved: 'No se guardó: probá de nuevo', slow: 'Todavía no llego a tus respuestas', open: 'Abrir ›', locale: 'es-AR',
  }, window.KIT_TEXT || {});

  /* ---------- Arrowheads the drawings share ---------- */
  d.body.insertAdjacentHTML('afterbegin', '<svg class="k-defs" aria-hidden="true"><defs>' +
    ['', '-blue', '-red'].map((c) => `<marker id="k-ah${c}" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path class="mk${c}" d="M0 0L10 5L0 10z"/></marker>`).join('') +
    '</defs></svg>');

  /* ---------- Top bar, views and tabs ---------- */
  const top = d.querySelector('.k-top');
  const views = $$('.k-view');
  const ICONS = {
    home: '<path d="M4 11l8-7 8 7v9H4z"/><path d="M10 20v-5h4v5"/>',
    play: '<rect x="3" y="5" width="18" height="14" rx="2"/><path d="M10 9l5 3-5 3z"/>',
    ask: '<circle cx="12" cy="12" r="9"/><path d="M9.5 9.5a2.5 2.5 0 1 1 3.5 2.3c-.7.3-1 .8-1 1.5v.7"/><path d="M12 17h.01"/>',
    list: '<path d="M9 6h11M9 12h11M9 18h11"/><path d="M4 6h.01M4 12h.01M4 18h.01"/>',
    check: '<circle cx="12" cy="12" r="9"/><path d="M8 12l3 3 5-6"/>',
    tree: '<rect x="9" y="3" width="6" height="5" rx="1"/><rect x="3" y="16" width="6" height="5" rx="1"/><rect x="15" y="16" width="6" height="5" rx="1"/><path d="M12 8v4M6 16v-4h12v4"/>',
    map: '<path d="M9 4L3 6v14l6-2 6 2 6-2V4l-6 2z"/><path d="M9 4v14M15 6v14"/>',
    clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
    layers: '<path d="M12 3l9 5-9 5-9-5z"/><path d="M3 13l9 5 9-5"/>',
    book: '<path d="M4 5a2 2 0 0 1 2-2h13v16H6a2 2 0 0 0-2 2z"/><path d="M4 19V5"/>',
    grid: '<rect x="4" y="4" width="7" height="7" rx="1"/><rect x="13" y="4" width="7" height="7" rx="1"/><rect x="4" y="13" width="7" height="7" rx="1"/><rect x="13" y="13" width="7" height="7" rx="1"/>',
  };
  const ORDER = ['home', 'play', 'ask', 'list', 'check'];
  const slug = (s) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '') || 'vista';
  views.forEach((v, i) => { if (!v.id) v.id = slug(v.dataset.tab || 'vista-' + (i + 1)); });

  let save = null;
  if (top) {
    const brand = el('div', 'k-brand');
    [...top.children].forEach((c) => brand.appendChild(c));
    top.appendChild(brand);
  }
  let tabs = null;
  if (views.length > 1) {
    tabs = el('nav', 'k-tabs');
    tabs.setAttribute('role', 'tablist');
    views.forEach((v, i) => {
      const b = el('button', null, `<svg viewBox="0 0 24 24" aria-hidden="true">${ICONS[v.dataset.icon] || ICONS[ORDER[i % ORDER.length]]}</svg><b>${i + 1}</b>${esc(v.dataset.tab || v.id)}<i></i>`);
      b.setAttribute('role', 'tab');
      b.dataset.v = v.id;
      b.addEventListener('click', () => open(v.id));
      tabs.appendChild(b);
    });
    (top || d.body).appendChild(tabs);
    d.body.classList.add('k-tabbed');
    // On a phone the bar is fixed at the bottom; the views leave room for it, as tall as its names make it.
    const bar = () => { if (getComputedStyle(tabs).position === 'fixed') d.documentElement.style.setProperty('--bar', tabs.offsetHeight + 'px'); };
    if ('ResizeObserver' in window) new ResizeObserver(bar).observe(tabs); else bar();
  }

  /* ---------- Decks: cards you swipe ---------- */
  function initDeck(deck) {
    const cards = $$(':scope > .k-card', deck);
    const track = el('div', 'k-track');
    cards.forEach((c) => track.appendChild(c));
    const pager = el('div', 'k-pager', `<button class="k-pg" aria-label="${T.prev}">‹</button><div class="k-dots"></div><button class="k-pg" aria-label="${T.next}">›</button>`);
    deck.append(track, pager);
    const [prev, next] = $$('.k-pg', pager);
    const dots = pager.querySelector('.k-dots');
    const left = (c) => c.offsetLeft - track.children[0].offsetLeft;
    const idx = () => { let best = 0, dist = Infinity; cards.forEach((c, i) => { const x = Math.abs(left(c) - track.scrollLeft); if (x < dist) { dist = x; best = i; } }); return best; };
    function size() {
      const w = track.clientWidth, n = cards.length, gap = parseFloat(getComputedStyle(track).columnGap) || 14;
      if (!w || !n) return;
      let per;
      if (phone()) per = n > 1 ? w - 18 : w;
      else {
        const min = +deck.dataset.min || 340, fit = Math.max(1, Math.floor((w + gap) / (min + gap)));
        const cols = +deck.dataset.cols || Math.min(n, fit, 4);
        per = (w - (cols - 1) * gap) / cols;
      }
      track.style.setProperty('--w', per + 'px');
    }
    function paint() {
      if (!cards.length) return;
      if (dots.children.length !== cards.length) dots.innerHTML = cards.map((_, k) => `<button aria-label="${T.card} ${k + 1} ${T.of} ${cards.length}"></button>`).join('');
      pager.hidden = track.scrollWidth <= track.clientWidth + 2;
      const a = track.scrollLeft, b = a + track.clientWidth;
      [...dots.children].forEach((dot, k) => { const l = left(cards[k]), r = l + cards[k].offsetWidth; dot.classList.toggle('cur', l >= a - 4 && r <= b + 4); });
      prev.disabled = a <= 2; next.disabled = b >= track.scrollWidth - 2;
    }
    function go(i) { i = Math.max(0, Math.min(cards.length - 1, i)); track.scrollTo({ left: left(cards[i]), behavior: reduce ? 'auto' : 'smooth' }); }
    dots.addEventListener('click', (e) => { const b = e.target.closest('button'); if (b) go([...dots.children].indexOf(b)); });
    prev.addEventListener('click', () => go(idx() - 1));
    next.addEventListener('click', () => go(idx() + 1));
    let raf = 0;
    track.addEventListener('scroll', () => { cancelAnimationFrame(raf); raf = requestAnimationFrame(paint); }, { passive: true });
    if ('ResizeObserver' in window) new ResizeObserver(() => { size(); paint(); }).observe(track);
    deck._go = go; deck._idx = idx; deck._paint = () => { size(); paint(); };
    deck._cards = cards;
    size(); paint();
  }

  // A view with several decks shows one at a time, picked from a row of chips: a debate's rounds, a decision's pieces.
  views.forEach((v) => {
    const decks = $$(':scope > .k-deck', v);
    decks.forEach(initDeck);
    if (decks.length < 2) return;
    const chaps = el('div', 'k-chaps');
    decks.forEach((dk, i) => {
      const b = el('button', null, esc(dk.dataset.name || String(i + 1)));
      b.addEventListener('click', () => pick(i));
      chaps.appendChild(b);
    });
    v.insertBefore(chaps, decks[0]);
    function pick(i) {
      decks.forEach((dk, k) => { dk.hidden = k !== i; });
      [...chaps.children].forEach((b, k) => b.setAttribute('aria-pressed', k === i));
      requestAnimationFrame(decks[i]._paint);
    }
    const start = decks.findIndex((dk) => dk.hasAttribute('data-open'));
    pick(start < 0 ? decks.length - 1 : start);
    v._pick = pick;
  });

  let current = null;
  function show(id) {
    const v = views.find((x) => x.id === id) || views[0];
    if (!v) return;
    current = v;
    views.forEach((x) => x.classList.toggle('on', x === v));
    if (tabs) $$('[role=tab]', tabs).forEach((t) => { const on = t.dataset.v === v.id; t.setAttribute('aria-selected', on); t.tabIndex = on ? 0 : -1; });
    $$('.k-deck', v).forEach((dk) => dk._paint && requestAnimationFrame(dk._paint));
    d.dispatchEvent(new CustomEvent('k-view', { detail: v.id }));
  }
  // The view the address names; an id with accents arrives encoded.
  const hashId = () => { const h = location.hash.slice(1); try { return decodeURIComponent(h); } catch (e) { return h; } };
  // Opens a view through the address, so the browser's back button returns to the last one.
  function open(id) { if (hashId() !== id) location.hash = encodeURIComponent(id); else show(id); }
  addEventListener('hashchange', () => show(hashId()));
  // Takes the user to a card: its view, its deck and the card itself.
  function goTo(card) {
    const v = card.closest('.k-view'), deck = card.closest('.k-deck');
    if (!v || !deck) return;
    open(v.id);
    const decks = $$(':scope > .k-deck', v);
    if (v._pick) v._pick(decks.indexOf(deck));
    setTimeout(() => deck._go(deck._cards.indexOf(card)), 80);
  }
  addEventListener('keydown', (e) => {
    if (e.target.closest('textarea,input,[contenteditable]') || e.metaKey || e.ctrlKey || e.altKey) return;
    if (/^[1-9]$/.test(e.key) && views[+e.key - 1]) { open(views[+e.key - 1].id); return; }
    // On the tab bar, the arrows move between tabs, as a tab list does.
    const tab = e.target.closest('[role=tab]');
    if (tab && tabs && ['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(e.key)) {
      const all = $$('[role=tab]', tabs), i = all.indexOf(tab);
      const j = e.key === 'Home' ? 0 : e.key === 'End' ? all.length - 1 : (i + (e.key === 'ArrowRight' ? 1 : -1) + all.length) % all.length;
      e.preventDefault(); open(all[j].dataset.v); all[j].focus();
      return;
    }
    if (e.key !== 'ArrowLeft' && e.key !== 'ArrowRight' || !current) return;
    const deck = $$('.k-deck', current).find((dk) => !dk.hidden);
    if (deck && deck._go) { e.preventDefault(); deck._go(deck._idx() + (e.key === 'ArrowRight' ? 1 : -1)); }
  });

  // Runs fn the first time el is on screen, and stop() when it leaves.
  function watch(node, fn, stop) {
    if (!('IntersectionObserver' in window)) { fn(); return; }
    let first = true;
    new IntersectionObserver((es) => es.forEach((e) => {
      if (e.isIntersecting) { if (first) { first = false; fn(); } }
      else if (stop) stop();
    }), { threshold: 0.55 }).observe(node);
  }

  /* ---------- The movie: a drawing that builds step by step, with its caption under it ---------- */
  $$('.k-movie').forEach((fig) => {
    const svg = fig.querySelector('svg'), caps = $$(':scope > ol > li', fig);
    const N = caps.length, ms = +fig.dataset.ms || 3600;
    if (!svg || !N) return;
    const stage = el('div', 'k-stage'); stage.appendChild(svg);
    const cap = el('div', 'k-cap');
    const player = el('div', 'k-player', `<button aria-label="${T.prev}">‹</button><button class="k-play"></button><button aria-label="${T.next}">›</button><div class="k-mdots" aria-hidden="true">${caps.map(() => '<i></i>').join('')}</div>`);
    const list = el('div', 'k-steplist', caps.map((c, i) => `<button><i>${i + 1}</i><span>${esc(c.dataset.label || c.textContent.trim())}</span></button>`).join(''));
    fig.prepend(stage); fig.append(cap, player, list);
    const [bPrev, bPlay, bNext] = $$(':scope > button', player);
    const mdots = $$('.k-mdots i', player), items = $$('button', list);
    const parts = $$('[data-in],[data-out],[data-only],[data-skip],[data-on]', svg);
    let s = 1, timer = null;
    function step(n) {
      s = n;
      parts.forEach((p) => {
        const a = p.dataset; let on = true;
        if (a.in && s < +a.in) on = false;
        if (a.out && s >= +a.out) on = false;
        if (a.only && !a.only.split(/\s+/).map(Number).includes(s)) on = false;
        if (a.skip && a.skip.split(/\s+/).map(Number).includes(s)) on = false;
        p.classList.toggle('off', !on);
        if (a.on) p.classList.toggle('hl', a.on.split(/\s+/).map(Number).includes(s));
      });
      cap.innerHTML = `<span>${s}/${N}</span><span>${caps[s - 1].innerHTML}</span>`;
      mdots.forEach((b, i) => { b.className = i + 1 < s ? 'done' : i + 1 === s ? 'cur' : ''; });
      items.forEach((b, i) => b.classList.toggle('cur', i + 1 === s));
      bPrev.disabled = s <= 1; bNext.disabled = s >= N;
      if (!timer) bPlay.textContent = s >= N ? T.again : T.play;
    }
    function stop() { if (timer) { clearInterval(timer); timer = null; } bPlay.textContent = s >= N ? T.again : T.play; }
    function play() {
      if (timer) { stop(); return; }
      if (s >= N) step(1);
      timer = setInterval(() => { if (s < N) step(s + 1); if (s >= N) stop(); }, ms);
      bPlay.textContent = T.pause;
    }
    bPlay.addEventListener('click', play);
    bPrev.addEventListener('click', () => { stop(); step(Math.max(1, s - 1)); });
    bNext.addEventListener('click', () => { stop(); step(Math.min(N, s + 1)); });
    items.forEach((b, i) => b.addEventListener('click', () => { stop(); step(i + 1); }));
    step(1);
    watch(fig, () => { if (!reduce) play(); }, stop);
    fig._step = step;
  });

  /* ---------- Before and after: two sides and a switch; it turns once by itself ---------- */
  $$('.k-ba').forEach((fig) => {
    const sides = $$(':scope > [data-side]', fig);
    if (sides.length < 2) return;
    const seg = el('div', 'k-seg', sides.map((x) => `<button>${esc(x.dataset.side)}</button>`).join(''));
    const box = el('div', 'k-sides'); sides.forEach((x) => box.appendChild(x));
    fig.append(seg, box);
    const bs = $$('button', seg);
    let touched = false;
    const pick = (i) => { sides.forEach((x, k) => x.classList.toggle('k-hide', k !== i)); bs.forEach((b, k) => b.setAttribute('aria-pressed', k === i)); };
    bs.forEach((b, i) => b.addEventListener('click', () => { touched = true; pick(i); }));
    pick(0);
    watch(fig, () => { if (reduce) pick(sides.length - 1); else setTimeout(() => { if (!touched) pick(sides.length - 1); }, 1400); });
  });

  /* ---------- A change, today and after: its header row ---------- */
  $$('.k-changes').forEach((ul) => {
    const head = el('li', 'k-head', `<span>${esc(ul.dataset.from || T.today)}</span><span>${esc(ul.dataset.to || T.after)}</span>`);
    head.setAttribute('aria-hidden', 'true');
    ul.prepend(head);
  });

  /* ---------- Counted bars ---------- */
  $$('.k-bars').forEach((ul) => {
    const lis = $$(':scope > li', ul), max = Math.max(1, ...lis.map((li) => +li.dataset.n || 0));
    lis.forEach((li) => {
      const label = li.innerHTML;
      li.innerHTML = `<span>${label}</span><i></i><b>${(+li.dataset.n || 0).toLocaleString(T.locale)}</b>`;
    });
    const grow = () => lis.forEach((li) => li.style.setProperty('--p', ((+li.dataset.n || 0) / max * 100) + '%'));
    if (reduce) grow(); else watch(ul, grow);
  });

  /* ---------- Words and issues: a popover on tap, or on hover where there's a mouse ---------- */
  const pop = el('div', 'k-pop'); pop.hidden = true; pop.setAttribute('role', 'tooltip'); d.body.appendChild(pop);
  const terms = {};
  $$('.k-terms dt').forEach((dt) => { const dd = dt.nextElementSibling; terms[dt.dataset.term || slug(dt.textContent)] = [dt.innerHTML, dd ? dd.innerHTML : '']; });
  let popFor = null;
  function openPop(t) {
    let head, body, link = '';
    if (t.dataset.term) [head, body] = terms[t.dataset.term] || [esc(t.textContent), ''];
    else { head = esc(t.textContent.trim()); body = esc(t.dataset.tip || ''); }
    if (t.matches('a[href^="https://"]') && mouseOn !== t) link =`<a href="${esc(t.href)}" target="_blank" rel="noopener">${T.open}</a>`;
    pop.innerHTML = `<b>${head}</b>${body ? `<p>${body}</p>` : ''}${link}`;
    pop.hidden = false; popFor = t;
    const r = t.getBoundingClientRect(), w = pop.offsetWidth, h = pop.offsetHeight;
    const x = Math.min(Math.max(12, r.left), innerWidth - w - 12);
    let y = r.bottom + 8; if (y + h > innerHeight - 12) y = Math.max(12, r.top - h - 8);
    pop.style.left = x + 'px'; pop.style.top = y + 'px';
  }
  const closePop = () => { pop.hidden = true; popFor = null; };
  const tipSel = '.k-term,[data-tip]';
  let mouseOn = null; // the tip a mouse is over, which a click keeps open
  $$(tipSel).forEach((t) => {
    if (!t.matches('a,button')) { t.tabIndex = 0; t.setAttribute('role', 'button'); }
    t.addEventListener('pointerenter', (e) => { if (e.pointerType === 'mouse') { mouseOn = t; openPop(t); } });
    t.addEventListener('pointerleave', (e) => { if (e.pointerType === 'mouse') { mouseOn = null; if (popFor === t) closePop(); } });
  });
  d.addEventListener('click', (e) => {
    const t = e.target.closest(tipSel);
    if (t) {
      if (t.matches('a[href]') && mouseOn === t) return; // a mouse already saw the tip; the click opens the link
      e.preventDefault();
      if (mouseOn === t) openPop(t); else if (popFor === t) closePop(); else openPop(t);
      return;
    }
    if (!e.target.closest('.k-pop')) closePop();
  });
  d.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') closePop();
    const t = e.target.closest && e.target.closest(tipSel);
    if (t && !t.matches('a,button') && (e.key === 'Enter' || e.key === ' ')) { e.preventDefault(); openPop(t); }
  });
  $$('.k-track,.k-card').forEach((x) => x.addEventListener('scroll', closePop, { passive: true }));

  /* ---------- Questions, notes and the approval, kept in the artifact's database ---------- */
  const S = { ans: {}, notes: {}, approval: null, apNote: '' };
  const qs = $$('.k-q[data-q]').filter((q) => {
    if (q.querySelector('.k-opts > li[data-o]')) return true;
    console.error(`The question "${q.dataset.q}" has no .k-opts with its <li data-o> options: give it 2 to 4, as pieces.html does (.claude/method/kit/README.md).`);
    return false;
  });
  const noteBoxes = $$('.k-note[data-id]');
  const approve = d.querySelector('.k-approve');
  const dbName = (d.querySelector('[data-db]') || {}).dataset?.db;
  const optOf = (q, o) => $$('.k-opt', q).find((b) => b.dataset.o === o);
  const chosen = (q) => S.ans[q.dataset.q] || q.dataset.rec;
  let col = null, readOnly = false, synced = false;
  const status = (t, cls) => { if (!save) return; save.textContent = t; save.className = 'k-save' + (cls ? ' ' + cls : ''); };
  // What the user changed here that the database doesn't hold yet, by document and field: a snapshot
  // leaves those alone, so a note typed while another save comes back isn't lost.
  const touched = {}, ver = {}, queued = new Set();
  const touch = (id, field) => { (touched[id] = touched[id] || new Set()).add(field); ver[id] = (ver[id] || 0) + 1; };

  function noteBox(id, label) {
    const box = el('details', 'k-notebox', `<summary>${esc(label)}</summary><textarea id="n-${esc(id)}" placeholder="${esc(T.notePh)}"></textarea>`);
    const ta = box.querySelector('textarea');
    ta.addEventListener('input', () => { S.notes[id] = ta.value; touch(id, 'note'); later(id); });
    ta.addEventListener('blur', () => flush(id));
    return box;
  }
  qs.forEach((q, qi) => {
    const id = q.dataset.q, h = q.querySelector('h2');
    const head = el('div', 'k-qhead');
    if (h) { q.insertBefore(head, h); head.appendChild(h); } else q.prepend(head);
    head.prepend(el('span', 'k-qstate'));
    const pv = q.querySelector('.k-pv'), pvs = pv ? $$(':scope > [data-o]', pv) : [];
    const ul = q.querySelector('.k-opts');
    $$(':scope > li[data-o]', ul).forEach((li) => {
      const b = el('button', 'k-opt', `<span class="k-rad"></span><span class="k-ol">${li.innerHTML}</span>${li.dataset.o === q.dataset.rec ? `<span class="k-recb">${T.rec}</span>` : ''}`);
      b.dataset.o = li.dataset.o;
      li.innerHTML = ''; li.appendChild(b);
      b.addEventListener('click', () => { if (readOnly) return; S.ans[id] = li.dataset.o; touch(id, 'choice'); paintQ(q); paintApprove(); saveDoc(id); });
      b.addEventListener('pointerenter', (e) => { if (e.pointerType === 'mouse') { q._look = li.dataset.o; paintQ(q); } });
      b.addEventListener('pointerleave', () => { if (q._look === li.dataset.o) { q._look = null; paintQ(q); } });
      b.addEventListener('focus', () => { q._look = li.dataset.o; paintQ(q); });
      b.addEventListener('blur', () => { q._look = null; paintQ(q); });
    });
    const why = q.querySelector('.k-why');
    if (why) why.prepend(el('span', 'k-recb', T.rec));
    q.appendChild(noteBox(id, T.addNote));
    // An inner box, so a wide card can lay the question out beside its preview (a container can't style itself).
    const inner = el('div', 'k-qin');
    [...q.childNodes].forEach((n) => inner.appendChild(n));
    q.appendChild(inner);
    q._pvs = pvs; q._n = qi + 1;
  });
  function paintQ(q) {
    const id = q.dataset.q, show = q._look || chosen(q);
    $$('.k-opt', q).forEach((b) => { b.setAttribute('aria-pressed', b.dataset.o === chosen(q)); b.classList.toggle('look', b.dataset.o === q._look); });
    q._pvs.forEach((p) => p.classList.toggle('k-hide', p.dataset.o !== show));
    const st = q.querySelector('.k-qstate');
    st.textContent = S.ans[id] ? T.chosen : T.unanswered;
    st.className = 'k-qstate' + (S.ans[id] ? ' ok' : '');
    const ta = q.querySelector('.k-notebox textarea');
    if (d.activeElement !== ta) { ta.value = S.notes[id] || ''; if (S.notes[id]) ta.closest('details').open = true; }
  }
  noteBoxes.forEach((n) => n.appendChild(noteBox(n.dataset.id, n.dataset.label || T.note)));
  function paintNotes() {
    noteBoxes.forEach((n) => {
      const ta = n.querySelector('textarea');
      if (d.activeElement !== ta) { ta.value = S.notes[n.dataset.id] || ''; if (S.notes[n.dataset.id]) ta.closest('details').open = true; }
    });
  }
  let apList, apNote, apBtn, apState;
  if (approve) {
    apList = el('div', 'k-ans');
    apNote = el('textarea', 'k-apnote'); apNote.id = 'k-apnote'; apNote.placeholder = T.notePh;
    apBtn = el('button', 'k-apbtn', T.approve);
    apState = el('p', 'k-apstate');
    approve.append(apList, apNote, apBtn, apState);
    apList.addEventListener('click', (e) => { const b = e.target.closest('button[data-i]'); if (b) goTo(qs[+b.dataset.i]); });
    apNote.addEventListener('input', () => { S.apNote = apNote.value; touch('aprobacion', 'note'); later('aprobacion'); });
    apNote.addEventListener('blur', () => flush('aprobacion'));
    apBtn.addEventListener('click', () => { if (readOnly) return; S.approval = { approved: true, at: new Date().toISOString() }; touch('aprobacion', 'approved'); saveDoc('aprobacion'); paintApprove(); });
  }
  function paintApprove() {
    if (tabs) {
      const open = qs.some((q) => !S.ans[q.dataset.q]);
      $$('[role=tab]', tabs).forEach((t) => { const v = d.getElementById(t.dataset.v); t.querySelector('i').classList.toggle('on', !!v && open && !!v.querySelector('.k-q')); });
    }
    if (!approve) return;
    apList.innerHTML = qs.map((q, i) => {
      const b = optOf(q, chosen(q)), o = b && b.querySelector('.k-ol');
      const label = o ? (o.querySelector('b') || o).textContent.trim() : '';
      return `<button data-i="${i}"><span class="k-qn">${i + 1}</span><b>${esc(label)}</b><span class="k-tag${S.ans[q.dataset.q] ? ' mine' : ''}">${S.ans[q.dataset.q] ? T.yours : T.rec}</span></button>`;
    }).join('');
    apList.hidden = !qs.length;
    // Approved shows only once the database holds it; until then the button says it's saving.
    const ap = S.approval, done = !!(ap && ap.approved), sending = done && !!(touched.aprobacion && touched.aprobacion.has('approved'));
    apBtn.disabled = done || readOnly;
    apBtn.textContent = sending ? T.saving : done ? T.approved : T.approve;
    apState.textContent = done && !sending
      ? T.approvedAt(new Date(ap.at).toLocaleString(T.locale, { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }))
      : readOnly ? T.noSave : T.withChoices;
    if (d.activeElement !== apNote) apNote.value = S.apNote || '';
  }

  const writing = {}, again = {}, timers = {}, tries = {}, failed = new Set();
  // The status says saved, or up to date, only when nothing the user did is waiting or failed.
  function settle(okText) {
    if (failed.size) status(T.notSaved, 'err');
    else if (Object.keys(touched).length) status(T.saving);
    else status(okText, okText === T.ready ? '' : 'ok');
  }
  function docFor(id) {
    if (id === 'aprobacion') return { approved: !!(S.approval && S.approval.approved), at: (S.approval && S.approval.at) || new Date().toISOString(), note: S.apNote || '' };
    if (qs.some((q) => q.dataset.q === id)) return { choice: S.ans[id] || null, note: S.notes[id] || '', at: new Date().toISOString() };
    return { note: S.notes[id] || '', at: new Date().toISOString() };
  }
  // Saves a document once the database answered its first snapshot; until then, what the user did waits in queued.
  async function saveDoc(id) {
    if (readOnly) return;
    if (!col || !synced) { queued.add(id); return; }
    if (writing[id]) { again[id] = true; return; }
    writing[id] = true; status(T.saving);
    const v = ver[id];
    try {
      await col.doc(id).set(docFor(id));
      if (ver[id] === v) delete touched[id];
      failed.delete(id); tries[id] = 0;
    } catch (e) {
      const code = e && e.code;
      writing[id] = false;
      if (code === 'not_granted' || code === 'revoked' || code === 'capability_disabled' || code === 'capability_removed') { goReadOnly(T.readOnly, 'err'); return; }
      failed.add(id);
      const t = touched[id];
      if (id === 'aprobacion' && t && t.has('approved')) {
        // An approval that didn't reach the database is taken back, so the user can press it again.
        S.approval = null; t.delete('approved'); if (!t.size) delete touched[id];
      } else if ((tries[id] = (tries[id] || 0) + 1) <= 3) {
        // The rest tries again by itself, a little later each time.
        clearTimeout(timers[id]); timers[id] = setTimeout(() => { timers[id] = null; saveDoc(id); }, 2000 * tries[id]);
      }
    }
    writing[id] = false;
    paintApprove(); settle(T.saved);
    if (again[id]) { again[id] = false; saveDoc(id); }
  }
  function later(id) { clearTimeout(timers[id]); timers[id] = setTimeout(() => { timers[id] = null; saveDoc(id); }, 800); }
  function flush(id) { if (timers[id]) { clearTimeout(timers[id]); timers[id] = null; saveDoc(id); } }
  const flushAll = () => Object.keys(timers).forEach(flush);
  addEventListener('pagehide', flushAll);
  d.addEventListener('visibilitychange', () => { if (d.visibilityState === 'hidden') flushAll(); });
  // A view that can't save: what was chosen stays on screen, but an approval that never reached the database isn't one.
  function goReadOnly(msg, cls) {
    readOnly = true;
    if (touched.aprobacion && touched.aprobacion.has('approved')) S.approval = null;
    status(msg, cls); paintAll();
  }
  function paintAll() { qs.forEach(paintQ); paintNotes(); paintApprove(); }

  async function initDb() {
    if (!qs.length && !noteBoxes.length && !approve) return;
    if (top) { save = el('span', 'k-save'); top.insertBefore(save, tabs && tabs.parentNode === top ? tabs.nextSibling : null); }
    if (!dbName) { console.error('The page has questions, notes or Aprobar but no data-db: put data-db="<collection>" on its .k-top (.claude/method/kit/README.md).'); goReadOnly(T.noSave); return; }
    let db = null;
    try { db = window.claude && window.claude.use ? await window.claude.use('db') : null; } catch (e) { db = null; }
    if (!db) { goReadOnly(T.noSave); return; }
    col = db.collection(dbName);
    const slow = setTimeout(() => status(T.slow), 10000);
    col.onSnapshot((snap) => {
      clearTimeout(slow);
      snap.docs.forEach((doc) => {
        const v = doc.data() || {}, t = touched[doc.id] || new Set();
        if (doc.id === 'aprobacion') {
          if (!t.has('approved')) S.approval = v.approved ? { approved: true, at: v.at } : null;
          if (!t.has('note')) S.apNote = typeof v.note === 'string' ? v.note : '';
          return;
        }
        const q = qs.find((x) => x.dataset.q === doc.id);
        if (q && !t.has('choice')) { if (optOf(q, v.choice)) S.ans[doc.id] = v.choice; else delete S.ans[doc.id]; }
        if (!t.has('note')) S.notes[doc.id] = typeof v.note === 'string' ? v.note : '';
      });
      settle(snap.empty ? T.ready : T.upToDate);
      if (!synced) { synced = true; const ids = [...queued]; queued.clear(); ids.forEach(saveDoc); }
      paintAll();
    }, () => { clearTimeout(slow); goReadOnly(T.noSave, 'err'); });
  }

  /* ---------- Start ---------- */
  paintAll();
  show(hashId());
  d.body.classList.add('k-ready');
  initDb();
  window.Kit = { show, goTo, text: T };
})();
