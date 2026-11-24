/*
 * Ficha mock kit: the toy engine.
 *
 * Plain JavaScript, no React, so it runs in a page and in Node alike.
 * It imitates FichaCore closely enough for a mock to feel right: FSRS-6
 * with its default parameters, the standard scheduler's steps, and the
 * appearance rules of ReviewSettings.defaults. It is a toy: FichaCore,
 * with its tests, decides the real logic. A rule that comes out of a mock
 * goes into a spec and is built in Swift.
 *
 * Mirrors, in the repo:
 *   FSRS                 -> Packages/FichaKit/Sources/FichaFSRS (fsrs-rs)
 *   Scheduler            -> FichaCore/Scheduler/Scheduler.swift, StepRules.swift
 *   SETTINGS             -> FichaCore/ReviewSettings.swift (defaults)
 *   ToyFicha.next...     -> FichaCore/AppearancePlanner.swift
 *   formatInterval       -> App/IntervalText.swift
 */
(function (root) {
  'use strict';

  const MINUTE = 60 * 1000;
  const HOUR = 60 * MINUTE;
  const DAY = 24 * HOUR;

  // ---------------------------------------------------------------------
  // FSRS-6, default parameters (fsrs-rs DEFAULT_PARAMETERS).
  // ---------------------------------------------------------------------
  const W = [
    0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001, 1.8722, 0.1666, 0.796, 1.4835, 0.0614,
    0.2629, 1.6483, 0.6014, 1.8729, 0.5425, 0.0912, 0.0658, 0.1542,
  ];
  const DECAY = -W[20];
  const FACTOR = Math.pow(0.9, 1 / DECAY) - 1;
  const clamp = (x, lo, hi) => Math.min(hi, Math.max(lo, x));

  const FSRS = {
    W,
    retrievability(days, S) {
      return Math.pow(1 + (FACTOR * days) / S, DECAY);
    },
    intervalDays(S, retention) {
      return (S / FACTOR) * (Math.pow(retention, 1 / DECAY) - 1);
    },
    initStability: (g) => W[g - 1],
    initDifficulty: (g) => clamp(W[4] - Math.exp(W[5] * (g - 1)) + 1, 1, 10),
    nextDifficulty(D, g) {
      const delta = -W[6] * (g - 3);
      const damped = D + (delta * (10 - D)) / 9;
      // Mean reversion toward easy's initial difficulty before clamping, as fsrs-rs does.
      const target = W[4] - Math.exp(W[5] * 3) + 1;
      return clamp(W[7] * target + (1 - W[7]) * damped, 1, 10);
    },
    recallStability(D, S, R, g) {
      const hard = g === 2 ? W[15] : 1;
      const easy = g === 4 ? W[16] : 1;
      return S * (1 + Math.exp(W[8]) * (11 - D) * Math.pow(S, -W[9]) * (Math.exp(W[10] * (1 - R)) - 1) * hard * easy);
    },
    forgetStability(D, S, R) {
      const next = W[11] * Math.pow(D, -W[12]) * (Math.pow(S + 1, W[13]) - 1) * Math.exp(W[14] * (1 - R));
      return Math.min(next, S / Math.exp(W[17] * W[18]));
    },
    shortTermStability(S, g) {
      let inc = Math.exp(W[17] * (g - 3 + W[18])) * Math.pow(S, -W[19]);
      if (g >= 3) inc = Math.max(inc, 1);
      return S * inc;
    },
    /** The memory state after rating g, `days` after the last review. */
    nextMemory(mem, g, days) {
      if (!mem) return { S: FSRS.initStability(g), D: FSRS.initDifficulty(g) };
      const D = FSRS.nextDifficulty(mem.D, g);
      if (days < 1) return { S: FSRS.shortTermStability(mem.S, g), D };
      const R = FSRS.retrievability(days, mem.S);
      const S = g === 1 ? FSRS.forgetStability(mem.D, mem.S, R) : FSRS.recallStability(mem.D, mem.S, R, g);
      return { S, D };
    },
  };

  // ---------------------------------------------------------------------
  // The scheduler: Anki's steps on top of FSRS, as FichaCore's standard.
  // ---------------------------------------------------------------------
  const SCHEDULER = {
    learningSteps: [1 * HOUR, 4 * HOUR],
    relearningSteps: [1 * HOUR],
    retention: 0.9,
    longestIntervalDays: 36500,
  };

  /**
   * Anki's fuzz: a graduated interval of 3 days or more moves a little,
   * from about 15% on short intervals to 5% on long ones, so cards added
   * together don't stay together. The same card, at the same review, always
   * lands on the same day.
   */
  function fuzz(days, card, longest) {
    if (days < 2.5) return days;
    const ranges = [
      [2.5, 7, 0.15],
      [7, 20, 0.1],
      [20, Infinity, 0.05],
    ];
    const delta = ranges.reduce((d, [from, to, f]) => d + f * Math.max(0, Math.min(days, to) - from), 1);
    const lower = Math.max(2, Math.round(days - delta));
    const upper = Math.min(longest, Math.round(days + delta));
    const random = seeded(hash(`${card.id}:${card.reps || 0}`))();
    return Math.min(upper, lower + Math.floor(random * (upper - lower + 1)));
  }
  function hash(text) {
    let h = 2166136261;
    for (let i = 0; i < text.length; i++) h = Math.imul(h ^ text.charCodeAt(i), 16777619);
    return h >>> 0;
  }

  /**
   * A card's next state for rating g (1 Again, 2 Hard, 3 Good, 4 Easy) at
   * `now`, as FichaCore's scheduler gives it: FSRS's memory, counting the
   * days since the last review rounded to the nearest whole day (0 days is
   * a same-day review), and Anki's learning and relearning steps.
   */
  function rate(card, g, now, settings = SCHEDULER) {
    const days = card.last == null ? 0 : Math.round((now - card.last) / DAY);
    const mem = FSRS.nextMemory(card.mem, g, days);
    const next = { ...card, mem, last: now, reps: (card.reps || 0) + 1 };
    const longest = settings.longestIntervalDays;
    const fsrsDays = (m) => clamp(Math.round(FSRS.intervalDays(m.S, settings.retention)), 1, longest);
    const graduateIn = (ivl) => {
      next.state = 'review';
      next.step = 0;
      next.ivlDays = ivl;
      next.due = now + ivl * DAY;
      return next;
    };
    const graduate = () => graduateIn(fuzz(fsrsDays(mem), card, longest));
    const stepTo = (steps, i, delay) => {
      next.step = i;
      next.due = now + (delay ?? steps[i]);
      return next;
    };
    const inSteps = (steps) => {
      if (!steps.length) return graduate();
      const i = card.state === 'new' ? 0 : Math.min(card.step || 0, steps.length - 1);
      if (g === 1) return stepTo(steps, 0);
      if (g === 2) {
        const delay = i === 0 ? (steps.length > 1 ? (steps[0] + steps[1]) / 2 : steps[0] * 1.5) : steps[i];
        return stepTo(steps, i, delay);
      }
      if (g === 3 && i + 1 < steps.length) return stepTo(steps, i + 1);
      return graduate();
    };

    if (card.state === 'new' || card.state === 'learning') {
      next.state = 'learning';
      if (card.state === 'new') next.firstSeen = now;
      return inSteps(settings.learningSteps);
    }
    if (card.state === 'relearning') return inSteps(settings.relearningSteps);
    // A review.
    if (g === 1) {
      next.lapses = (card.lapses || 0) + 1;
      // With no relearning steps, a lapse goes straight to FSRS's interval, without the fuzz.
      if (!settings.relearningSteps.length) return graduateIn(fsrsDays(mem));
      next.state = 'relearning';
      return stepTo(settings.relearningSteps, 0);
    }
    // Anki keeps a review's buttons in order, Hard < Good < Easy, a day
    // apart, within the longest interval.
    const raw = (h) => fuzz(fsrsDays(FSRS.nextMemory(card.mem, h, days)), card, longest);
    const hard = Math.min(raw(2), raw(3));
    const good = Math.min(longest, Math.max(raw(3), hard + 1));
    const easy = Math.min(longest, Math.max(raw(4), good + 1));
    return graduateIn({ 2: hard, 3: good, 4: easy }[g]);
  }

  /** What each rating would do, as the panel shows above its buttons. */
  function preview(card, now, settings = SCHEDULER) {
    const out = {};
    for (const g of [1, 2, 3, 4]) {
      const n = rate(card, g, now, settings);
      out[g] = { card: n, wait: n.due - now };
    }
    return out;
  }

  // ---------------------------------------------------------------------
  // How an interval reads on the buttons: 10m, 2h 30m, 4h, 3d, 1.5mo, 2.1y.
  // ---------------------------------------------------------------------
  function formatInterval(ms) {
    const minutes = Math.round(ms / MINUTE);
    if (minutes < 60) return `${Math.max(1, minutes)}m`;
    if (minutes < 24 * 60) {
      const h = Math.floor(minutes / 60);
      const m = minutes % 60;
      return m ? `${h}h ${m}m` : `${h}h`;
    }
    const days = ms / DAY;
    const tenths = (x) => (Math.round(x * 10) / 10).toString();
    if (days < 365 / 12) return `${Math.round(days)}d`;
    if (days < 365) return `${tenths(days / (365 / 12))}mo`;
    return `${tenths(days / 365)}y`;
  }

  // ---------------------------------------------------------------------
  // When Ficha shows up: ReviewSettings.defaults.
  // ---------------------------------------------------------------------
  const SETTINGS = {
    cardsPerAppearance: 5,
    lookAhead: 20 * MINUTE,
    activeHours: [9, 22],
    separation: 30 * MINUTE,
    waitAfterSuppression: 2 * MINUTE,
    autoClose: 10 * MINUTE,
    // At most this many new cards an appearance brings (ReviewNow.bringsNewCard: one).
    newPerAppearance: 1,
    // New cards a day count by the calendar day, as ReviewNow's metToday does.
    dayStartsAtHour: 0,
  };

  /** The suppressions of AppearancePlanner, as the log says them. */
  const SUPPRESSIONS = {
    meeting: 'in a meeting',
    video: 'watching a video',
    fullScreen: 'an app in full screen',
  };

  const startOfDay = (t, s = SETTINGS) => {
    const d = new Date(t - s.dayStartsAtHour * HOUR);
    d.setHours(0, 0, 0, 0);
    return d.getTime() + s.dayStartsAtHour * HOUR;
  };
  const dayKey = (t, s = SETTINGS) => startOfDay(t, s);
  const atHour = (t, hour) => {
    const d = new Date(t);
    d.setHours(hour, 0, 0, 0);
    return d.getTime();
  };
  /** The first moment at or after t inside active hours. */
  function intoActiveHours(t, s = SETTINGS) {
    const h = new Date(t).getHours();
    const [from, to] = s.activeHours;
    if (h < from) return atHour(t, from);
    if (h >= to) return atHour(t + DAY, from);
    return t;
  }
  const inActiveHours = (t, s = SETTINGS) => intoActiveHours(t, s) === t;

  // A small seeded random, so a fast-forward and a pace estimate come out
  // the same every time.
  function seeded(seed) {
    let a = seed >>> 0;
    return () => {
      a = (a + 0x6d2b79f5) >>> 0;
      let t = a;
      t = Math.imul(t ^ (t >>> 15), t | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  /** A made-up learner: how a person might rate a card. */
  function pretendRating(card, now, random) {
    const x = random();
    if (card.state === 'review') {
      const R = FSRS.retrievability((now - card.last) / DAY, card.mem.S);
      if (x > R) return 1;
      return x < R * 0.1 ? 2 : x > R * 0.95 ? 4 : 3;
    }
    if (card.state === 'new') return x < 0.15 ? 1 : x < 0.2 ? 2 : x > 0.95 ? 4 : 3;
    return x < 0.12 ? 1 : x < 0.16 ? 2 : 3;
  }

  // ---------------------------------------------------------------------
  // ToyFicha: the app's state, the clock and the appearances.
  // A tiny store: read `state`, call actions, `subscribe` to changes.
  // ---------------------------------------------------------------------
  class ToyFicha {
    constructor({ decks, now, speed = 60, settings = SETTINGS, scheduler = SCHEDULER }) {
      this.settings = settings;
      this.scheduler = scheduler;
      this.listeners = new Set();
      const cards = [];
      for (const deck of decks) {
        deck.cards.forEach((c, i) =>
          cards.push({
            id: `${deck.id}-${i}`,
            deckId: deck.id,
            order: i,
            front: c.front,
            back: c.back,
            source: c.source || null,
            tags: c.tags || [],
            state: 'new',
            step: 0,
            mem: null,
            due: null,
            last: null,
          }),
        );
      }
      this.state = {
        now,
        speed,
        paused: false,
        // What holds appearances back: null, or one of SUPPRESSIONS' keys.
        suppression: null,
        suppressionEndedAt: null,
        heldBack: false,
        cardSize: 100,
        decks: decks.map(({ cards: _, ...d }) => ({ ...d, added: false, perDay: 5, addedAt: null })),
        cards,
        panel: null,
        lastClosedAt: null,
        introduced: { day: dayKey(now, settings), byDeck: {} },
        buried: {},
        inbox: 0,
        log: [],
        toast: null,
      };
    }

    // The store.
    subscribe(fn) {
      this.listeners.add(fn);
      return () => this.listeners.delete(fn);
    }
    getState = () => this.state;
    emit() {
      this.state = { ...this.state };
      this.listeners.forEach((fn) => fn());
    }
    /** Marks that cards or decks changed, for views that cache what they compute from them. */
    changed() {
      this.state.revision = (this.state.revision || 0) + 1;
    }
    log(text, kind = 'info') {
      this.state.log = [{ t: this.state.now, text, kind }, ...this.state.log].slice(0, 60);
    }

    // Lookups.
    deck(id) {
      return this.state.decks.find((d) => d.id === id);
    }
    card(id) {
      return this.state.cards.find((c) => c.id === id);
    }
    activeCards() {
      const added = new Set(this.state.decks.filter((d) => d.added).map((d) => d.id));
      const buriedUntil = this.state.buried;
      return this.state.cards.filter((c) => added.has(c.deckId) && !(buriedUntil[c.id] > this.state.now));
    }
    newLeftToday(deck, at = this.state.now) {
      const today = dayKey(at, this.settings);
      const used = today === this.state.introduced.day ? this.state.introduced.byDeck[deck.id] || 0 : 0;
      const remaining = this.state.cards.filter((c) => c.deckId === deck.id && c.state === 'new').length;
      return Math.min(Math.max(0, deck.perDay - used), remaining);
    }
    dueCount(at = this.state.now) {
      return this.activeCards().filter((c) => c.state !== 'new' && c.due <= at).length;
    }
    learnedCount() {
      return this.state.cards.filter((c) => c.state === 'review').length;
    }

    /**
     * The cards an appearance at `at` would bring, as ReviewNow.pickCards
     * picks them: the cards due within the look-ahead, soonest first, up to
     * the cards an appearance brings, and then one new card if there's room
     * and a deck may still meet one today. With several decks, the new card
     * comes from the deck with the most left to meet today (new here: the
     * app has one count of new cards a day for all decks).
     */
    pickCards(at = this.state.now, lookAhead = this.settings.lookAhead) {
      const max = this.settings.cardsPerAppearance;
      const picked = this.activeCards()
        .filter((c) => c.state !== 'new' && c.due <= at + lookAhead)
        .sort((a, b) => a.due - b.due)
        .slice(0, max)
        .map((c) => c.id);
      for (let n = 0; n < this.settings.newPerAppearance && picked.length < max; n++) {
        const decks = this.state.decks
          .filter((d) => d.added)
          .map((d) => ({ d, left: this.newLeftToday(d, at) - picked.filter((id) => this.card(id).state === 'new' && this.card(id).deckId === d.id).length }))
          .filter((x) => x.left > 0)
          .sort((a, b) => b.left - a.left);
        if (!decks.length) break;
        const fresh = this.activeCards()
          .filter((c) => c.deckId === decks[0].d.id && c.state === 'new' && !picked.includes(c.id))
          .sort((a, b) => a.order - b.order)[0];
        if (!fresh) break;
        picked.push(fresh.id);
      }
      return picked;
    }

    /** When the next appearance would come, and whether a suppression holds it back. */
    nextAppearance() {
      const s = this.state;
      if (s.panel) return null;
      let t = s.now;
      if (s.lastClosedAt != null) t = Math.max(t, s.lastClosedAt + this.settings.separation);
      if (s.suppressionEndedAt != null) t = Math.max(t, s.suppressionEndedAt + this.settings.waitAfterSuppression);
      const added = s.decks.filter((d) => d.added);
      if (!added.length) return null;
      for (let i = 0; i < 30; i++) {
        t = intoActiveHours(t, this.settings);
        if (added.some((d) => this.newLeftToday(d, t) > 0)) break;
        // An appearance comes once a card is due; the look-ahead only brings others along.
        const dues = this.activeCards()
          .filter((c) => c.state !== 'new')
          .map((c) => c.due);
        const nextDue = dues.length ? Math.min(...dues) : null;
        const nextDay = startOfDay(t, this.settings) + DAY;
        const hasNew = added.some((d) => this.state.cards.some((c) => c.deckId === d.id && c.state === 'new'));
        if (nextDue != null && nextDue <= t) break;
        const candidates = [nextDue, hasNew ? nextDay : null].filter((x) => x != null);
        if (!candidates.length) return null;
        t = Math.min(...candidates);
      }
      return { at: t, heldBack: !!s.suppression, cards: this.pickCards(t).length };
    }

    // The clock.
    tick(realMs) {
      const s = this.state;
      if (!s.paused) this.advanceTo(s.now + realMs * s.speed);
      if (s.toast && performance.now() > s.toast.until) s.toast = null;
      this.emit();
    }
    advanceTo(t) {
      const s = this.state;
      s.now = t;
      const today = dayKey(t, this.settings);
      if (today !== s.introduced.day) s.introduced = { day: today, byDeck: {} };
      if (s.panel) {
        if (t - s.panel.touchedAt > this.settings.autoClose) this.close('auto');
        return;
      }
      this.maybeAppear();
    }
    maybeAppear() {
      const s = this.state;
      const next = this.nextAppearance();
      if (!next || next.at > s.now) return;
      if (s.suppression) {
        if (!s.heldBack) this.log(`Appearance held back: ${SUPPRESSIONS[s.suppression]}`, 'held');
        s.heldBack = true;
        return;
      }
      const queue = this.pickCards(s.now);
      if (queue.length) this.open('appearance', queue);
    }
    setSpeed(speed) {
      this.state.speed = speed;
      this.state.paused = false;
      this.emit();
    }
    togglePause() {
      this.state.paused = !this.state.paused;
      this.emit();
    }
    skipToNextAppearance() {
      const next = this.nextAppearance();
      if (!next) return;
      if (next.heldBack) {
        this.toast(`Held back: ${SUPPRESSIONS[this.state.suppression]}`);
        return;
      }
      this.advanceTo(Math.max(this.state.now, next.at));
      this.emit();
    }
    /** Starts or ends what holds Ficha back: 'meeting', 'video', 'fullScreen', or null. */
    setSuppression(kind) {
      const s = this.state;
      if (s.suppression === kind) return;
      const was = s.suppression;
      s.suppression = kind;
      if (was && !kind) {
        s.suppressionEndedAt = s.now;
        if (s.heldBack) this.log('Over: the appearance waits 2 minutes', 'held');
        s.heldBack = false;
      }
      if (kind) this.log(SUPPRESSIONS[kind][0].toUpperCase() + SUPPRESSIONS[kind].slice(1), 'held');
      this.emit();
    }
    setMeeting(on) {
      this.setSuppression(on ? 'meeting' : null);
    }

    /** ⌘+, ⌘− and ⌘0: the card's size, from 80% to 200% by tens (CardSize). */
    setCardSize(key) {
      const p = this.state.cardSize;
      const next = key === '0' ? 100 : key === '-' ? Math.max(80, p - 10) : Math.min(200, p + 10);
      this.state.cardSize = next;
      this.emit();
    }

    // Decks.
    addDeck(id, perDay) {
      const d = this.deck(id);
      const was = d.added;
      d.added = true;
      d.perDay = perDay;
      d.addedAt = d.addedAt ?? this.state.now;
      this.log(was ? `${d.name}: ${perDay} new a day` : `Added ${d.name}, ${perDay} new a day`, 'deck');
      this.changed();
      this.emit();
    }

    // The review panel.
    open(kind, queue) {
      const s = this.state;
      s.panel = {
        kind,
        queue,
        index: 0,
        flipped: false,
        mode: null,
        done: false,
        openedAt: s.now,
        touchedAt: s.now,
        undo: [],
        rated: 0,
      };
      s.heldBack = false;
      this.log(kind === 'appearance' ? `Appearance, ${queue.length} card${queue.length > 1 ? 's' : ''}` : `Review now, ${queue.length} cards`, 'appear');
    }
    reviewNow() {
      if (this.state.panel) return;
      const queue = this.pickCards(this.state.now, 0);
      if (queue.length) this.open('reviewNow', queue);
      else this.state.panel = { kind: 'empty', queue: [], index: 0, touchedAt: this.state.now, undo: [], openedAt: this.state.now };
      this.emit();
    }
    touch() {
      if (this.state.panel) this.state.panel.touchedAt = this.state.now;
    }
    currentCard() {
      const p = this.state.panel;
      return p && !p.done && p.queue[p.index] ? this.card(p.queue[p.index]) : null;
    }
    flip() {
      const p = this.state.panel;
      if (!p || p.done || p.flipped) return;
      p.flipped = true;
      this.touch();
      this.emit();
    }
    advance() {
      const p = this.state.panel;
      p.index++;
      p.flipped = false;
      p.mode = null;
      if (p.index >= p.queue.length) p.done = true;
    }
    rate(g) {
      const p = this.state.panel;
      const card = this.currentCard();
      if (!card || !p.flipped) return;
      const now = this.state.now;
      p.undo.push({ index: p.index, card: { ...card } });
      if (card.state === 'new') {
        const intro = this.state.introduced.byDeck;
        intro[card.deckId] = (intro[card.deckId] || 0) + 1;
      }
      Object.assign(card, rate(card, g, now, this.scheduler));
      p.rated++;
      this.changed();
      this.advance();
      this.touch();
      this.emit();
    }
    undo() {
      const p = this.state.panel;
      const last = p && p.undo.pop();
      if (!last) return;
      const card = this.card(last.card.id);
      if (card.state !== 'new' && last.card.state === 'new') {
        this.state.introduced.byDeck[card.deckId]--;
      }
      Object.assign(card, last.card);
      p.index = last.index;
      p.done = false;
      p.flipped = false;
      p.mode = null;
      p.rated--;
      this.changed();
      this.touch();
      this.emit();
    }
    bury() {
      const card = this.currentCard();
      if (!card) return;
      this.state.buried[card.id] = startOfDay(this.state.now, this.settings) + DAY;
      this.toast('Buried until tomorrow');
      this.changed();
      this.advance();
      this.touch();
      this.emit();
    }
    setMode(mode) {
      const p = this.state.panel;
      if (!p || p.done) return;
      p.mode = mode;
      this.touch();
      this.emit();
    }
    saveToInbox(what) {
      this.state.inbox++;
      this.state.panel.mode = null;
      this.toast(what === 'flag' ? 'Flagged. It waits in the inbox.' : 'Your question waits in the inbox.');
      this.touch();
      this.emit();
    }
    capture() {
      this.state.inbox++;
      this.log('Captured to the inbox', 'deck');
      this.toast('Captured. It waits in the inbox.');
      this.emit();
    }
    close(how = 'byHand') {
      const s = this.state;
      const p = s.panel;
      if (!p) return;
      const left = p.done ? 0 : p.queue.length - p.index;
      if (p.kind !== 'empty') {
        const verb = p.done ? 'Finished' : how === 'auto' ? 'Auto-closed' : 'Snoozed';
        this.log(left ? `${verb}, ${left} card${left > 1 ? 's' : ''} still due` : `${verb}`, p.done ? 'done' : 'snooze');
        s.lastClosedAt = s.now;
      }
      s.panel = null;
      this.emit();
    }
    toast(text) {
      this.state.toast = { text, until: performance.now() + 2600 };
    }

    /**
     * Runs the made-up learner through every appearance until `end`, as a
     * fast-forward: for a mock that opens on decks already in use.
     */
    fastForward(end, seed = 7) {
      const random = seeded(seed);
      for (let i = 0; i < 2000; i++) {
        const next = this.nextAppearance();
        if (!next || next.at > end) break;
        this.advanceTo(next.at);
        const p = this.state.panel;
        if (!p) continue;
        while (!p.done) {
          const card = this.currentCard();
          p.flipped = true;
          this.rate(pretendRating(card, this.state.now, random));
        }
        this.state.now += 2 * MINUTE;
        this.close();
      }
      this.state.now = end;
      this.state.log = [];
      this.state.toast = null;
    }
  }

  // ---------------------------------------------------------------------
  // The pace a deck would take: the "How fast?" screen's numbers.
  // ---------------------------------------------------------------------
  /**
   * Simulates the coming `days` with the made-up learner, reviewing each card
   * when it's due inside active hours, and returns the cards each day would
   * bring, the new deck's apart from the rest, averaged over a few runs.
   */
  function simulatePace({ cards, deckId, perDay, now, days = 28, runs = 12, settings = SETTINGS, scheduler = SCHEDULER }) {
    const start = startOfDay(now, settings);
    const totals = Array.from({ length: days }, () => ({ deck: 0, others: 0, fresh: 0 }));
    for (let run = 0; run < runs; run++) {
      const random = seeded(101 + run);
      const pool = cards.map((c) => ({ ...c }));
      const fresh = pool.filter((c) => c.deckId === deckId && c.state === 'new').sort((a, b) => a.order - b.order);
      for (let day = 0; day < days; day++) {
        const dayStart = start + day * DAY;
        const dayEnd = dayStart + DAY;
        const firstHour = intoActiveHours(Math.max(dayStart, day === 0 ? now : dayStart), settings);
        // New cards meet at the day's first appearance.
        if (firstHour < dayEnd) {
          for (const c of fresh.splice(0, perDay)) {
            Object.assign(c, rate(c, pretendRating(c, firstHour, random), firstHour, scheduler));
            totals[day].deck++;
            totals[day].fresh++;
          }
        }
        // Then every card due today, once each time it's due.
        for (let guard = 0; guard < 400; guard++) {
          const due = pool
            .filter((c) => c.state !== 'new' && c.due < dayEnd)
            .sort((a, b) => a.due - b.due)[0];
          if (!due) break;
          const at = intoActiveHours(Math.max(due.due, firstHour), settings);
          if (at >= dayEnd) {
            due.due = at;
            continue;
          }
          Object.assign(due, rate(due, pretendRating(due, at, random), at, scheduler));
          if (due.deckId === deckId) totals[day].deck++;
          else totals[day].others++;
        }
      }
    }
    return totals.map((d, i) => ({
      day: start + i * DAY,
      deck: d.deck / runs,
      others: d.others / runs,
      fresh: d.fresh / runs,
    }));
  }

  /** When the last new card would be met: every day, or five days a week. */
  function metBy({ newCards, perDay, now, settings = SETTINGS }) {
    const firstDay = startOfDay(now, settings) + (new Date(now).getHours() >= settings.activeHours[1] ? DAY : 0);
    const daysNeeded = Math.max(1, Math.ceil(newCards / perDay));
    return {
      daysNeeded,
      soonest: firstDay + (daysNeeded - 1) * DAY,
      latest: firstDay + (Math.ceil((daysNeeded * 7) / 5) - 1) * DAY,
    };
  }

  root.FichaEngine = {
    MINUTE,
    HOUR,
    DAY,
    FSRS,
    SCHEDULER,
    SETTINGS,
    SUPPRESSIONS,
    rate,
    preview,
    fuzz,
    formatInterval,
    intoActiveHours,
    inActiveHours,
    startOfDay,
    seeded,
    pretendRating,
    simulatePace,
    metBy,
    ToyFicha,
  };
})(typeof window !== 'undefined' ? window : globalThis);
