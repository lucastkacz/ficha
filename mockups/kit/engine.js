/*
 * Ficha mock kit: the toy engine.
 *
 * Plain JavaScript, no React, so it runs in a page and in Node alike.
 * It imitates FichaCore closely enough for a mock to feel right, in what
 * mockups/README.md's "What the toy engine copies" lists: since #490, the
 * pace, the queue of decks, the finish date and 85% on a new install too.
 * It is a toy:
 * FichaCore, with its tests, decides the real logic. A rule that comes out
 * of a mock goes into the decision's issue and is built in Swift with its
 * tests (mockups/README.md).
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
  /** ADR 0034: the desired retention a new install starts at, as FichaCore's `Scheduler.newInstall`. */
  const NEW_INSTALL_RETENTION = 0.85;

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
    waitAfterWaking: 2 * MINUTE,
    // What holds an appearance back, each a key of SUPPRESSIONS.
    suppressionsThatApply: ['meeting', 'video', 'fullScreen'],
    // At most this many new cards an appearance brings (ReviewNow.bringsNewCard: one).
    newPerAppearance: 1,
    // Where new cards come from: 'queue', one deck at a time (ADR 0034), or
    // 'together', every deck in turn: the day's new cards split between the
    // decks, ADR 0034's "one pace split between them". The app itself takes
    // them as 'queue' does (ReviewNow.pickCards).
    newCardsFrom: 'queue',
    // New cards a day count by Ficha's day, from 4:00 to 4:00, as
    // ReviewNow's metToday does, and so do the finish date and the days the
    // mock names (ADR 0045).
    dayStartsAtHour: 4,
  };

  /**
   * ADR 0034: one pace for all decks, the new cards a day the user meets.
   * Steady to start. The numbers are provisional: the Lab measured each
   * pace's appearances and minutes a weekday (#490).
   */
  const PACES = [
    { id: 'chill', name: 'Chill', perDay: 1 },
    { id: 'steady', name: 'Steady', perDay: 2 },
    { id: 'faster', name: 'Faster', perDay: 4 },
  ];
  /** A pace by its id; a number is any count a day, as the Lab tries. */
  const paceOf = (id) =>
    typeof id === 'number' ? { id, name: `${id} a day`, perDay: id } : PACES.find((p) => p.id === id) || PACES[1];

  /**
   * ADR 0034's finish date, in days from today, for each deck of a queue:
   * `left` is each deck's new cards still to meet, in the queue's order, and
   * `today` the new cards today may still bring. `soonest` is if every day
   * has appearances, `latest` if five days in seven do.
   */
  function finishDays({ left, perDay, today = 0 }) {
    let total = 0;
    return left.map((n) => {
      total += n;
      const days = Math.ceil(Math.max(0, total - today) / perDay);
      return { soonest: days, latest: Math.ceil((days * 7) / 5) };
    });
  }

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
  /**
   * The first moment at or after t inside active hours, which cross
   * midnight when they end before they start, as from 20 to 3 they do
   * (ADR 0045).
   */
  function intoActiveHours(t, s = SETTINGS) {
    const h = new Date(t).getHours();
    const [from, to] = s.activeHours;
    const inside = from < to ? h >= from && h < to : h >= from || h < to;
    if (inside) return t;
    return h < from ? atHour(t, from) : atHour(t + DAY, from);
  }
  const inActiveHours = (t, s = SETTINGS) => intoActiveHours(t, s) === t;

  // A small seeded random, so a fast-forward and a Lab run come out the
  // same every time.
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
    constructor({
      decks,
      now,
      speed = 60,
      settings = SETTINGS,
      scheduler = { ...SCHEDULER, retention: NEW_INSTALL_RETENTION },
      pace = 'steady',
    }) {
      this.settings = { ...settings };
      this.scheduler = { ...scheduler };
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
            picture: Boolean(c.picture),
            source: c.source || null,
            tags: c.tags || [],
            state: 'new',
            step: 0,
            mem: null,
            due: null,
            last: null,
            // When it came in, with its deck, and when its front or back
            // last changed, as the Cards window's Details say them: null
            // until its deck is added, and always, since no mock edits a
            // card.
            createdAt: null,
            editedAt: null,
            // Its review log, oldest first: when it was rated, how, and how
            // long it waits after, as the Cards window's Details lists it.
            reviewLog: [],
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
        // No appearance before this time, as after the Welcome page.
        notBefore: null,
        cardSize: 100,
        // ADR 0034: one pace for all decks, and the queue new cards come from.
        pace,
        queue: [],
        decks: decks.map(({ cards: _, ...d }) => ({ ...d, added: false, addedAt: null, metAllAt: null, setAside: false })),
        cards,
        panel: null,
        lastClosedAt: null,
        introduced: { day: dayKey(now, settings), count: 0 },
        // The cards set aside on their own, by id, with when: out of the
        // reviews until they're put back (GLOSSARY.md, Set aside).
        cardsSetAside: {},
        // A flagged card's note and when it was flagged, by its id, until
        // it's fixed: out of the reviews, in its deck with its flag (#540).
        flagged: {},
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
      // A deck set aside takes all its cards out of the reviews, a card set
      // aside on its own leaves them too (GLOSSARY.md), and so does a flag,
      // until the card is fixed.
      const added = new Set(this.state.decks.filter((d) => d.added && !d.setAside).map((d) => d.id));
      return this.state.cards.filter((c) => added.has(c.deckId) && !this.isSetAside(c.id) && !this.isFlagged(c.id));
    }
    deckCards(id) {
      return this.state.cards.filter((c) => c.deckId === id);
    }
    /** Whether the card is set aside on its own, until it's put back. */
    isSetAside(id) {
      return this.state.cardsSetAside[id] != null;
    }
    /** Whether the card is flagged, waiting in its deck until it's fixed (#540). */
    isFlagged(id) {
      return this.state.flagged[id] != null;
    }
    /** A deck's cards not met yet. */
    newLeft(id) {
      return this.deckCards(id).filter((c) => c.state === 'new').length;
    }
    perDay(pace = this.state.pace) {
      return paceOf(pace).perDay;
    }
    /** The decks in the queue, first to last; a deck set aside leaves it. */
    queueDecks() {
      return this.state.queue.map((id) => this.deck(id)).filter((d) => d && !d.setAside);
    }
    /** The deck new cards come from now: the first in the queue with cards not met. */
    currentDeck() {
      return this.queueDecks().find((d) => this.newLeft(d.id) > 0) || null;
    }
    /** New cards today may still bring, for all decks together. */
    newLeftToday(at = this.state.now) {
      const today = dayKey(at, this.settings);
      const used = today === this.state.introduced.day ? this.state.introduced.count : 0;
      return Math.max(0, this.perDay() - used);
    }
    dueCount(at = this.state.now) {
      return this.activeCards().filter((c) => c.state !== 'new' && c.due <= at).length;
    }
    // Learned, as WayStanding.isLearned counts it (GLOSSARY.md).
    learnedCount() {
      return this.state.cards.filter((c) => c.state === 'review' && c.ivlDays >= 21).length;
    }
    /** Whether a suppression holds appearances back now, as Settings lets it. */
    holding() {
      const s = this.state.suppression;
      return !!s && this.settings.suppressionsThatApply.includes(s);
    }

    /**
     * The cards an appearance at `at` would bring, as ReviewNow.pickCards
     * picks them: the cards due within the look-ahead, soonest first, up to
     * the cards an appearance brings, and then one new card if there's room
     * and today's pace allows one. The new card comes from the first deck in
     * the queue with cards not met (ADR 0034), or, with `newCardsFrom`
     * 'together', from each deck in turn.
     */
    pickCards(at = this.state.now, lookAhead = this.settings.lookAhead) {
      const max = this.settings.cardsPerAppearance;
      const active = this.activeCards();
      const picked = active
        .filter((c) => c.state !== 'new' && c.due <= at + lookAhead)
        .sort((a, b) => a.due - b.due)
        .slice(0, max)
        .map((c) => c.id);
      const byDeck = this.queueDecks().map((d) =>
        active.filter((c) => c.deckId === d.id && c.state === 'new').sort((a, b) => a.order - b.order),
      );
      const together = this.settings.newCardsFrom === 'together';
      // Together, the decks take turns: each one's first card, then each one's second.
      const fresh = together
        ? byDeck.flatMap((cards, k) => cards.map((c) => ({ c, rank: c.order * byDeck.length + k }))).sort((a, b) => a.rank - b.rank).map((x) => x.c)
        : byDeck.flat();
      const room = Math.min(this.settings.newPerAppearance, this.newLeftToday(at), max - picked.length);
      for (const c of fresh.slice(0, Math.max(0, room))) picked.push(c.id);
      return picked;
    }

    /** When the next appearance would come, and whether a suppression holds it back. */
    nextAppearance() {
      const s = this.state;
      if (s.panel) return null;
      if (!s.decks.some((d) => d.added)) return null;
      let t = s.now;
      if (s.notBefore != null) t = Math.max(t, s.notBefore);
      if (s.lastClosedAt != null) t = Math.max(t, s.lastClosedAt + this.settings.separation);
      if (s.suppressionEndedAt != null) t = Math.max(t, s.suppressionEndedAt + this.settings.waitAfterSuppression);
      const hasNew = !!this.currentDeck();
      for (let i = 0; i < 30; i++) {
        t = intoActiveHours(t, this.settings);
        if (hasNew && this.newLeftToday(t) > 0) break;
        // An appearance comes once a card is due; the look-ahead only brings others along.
        const dues = this.activeCards()
          .filter((c) => c.state !== 'new')
          .map((c) => c.due);
        const nextDue = dues.length ? Math.min(...dues) : null;
        const nextDay = startOfDay(t, this.settings) + DAY;
        if (nextDue != null && nextDue <= t) break;
        const candidates = [nextDue, hasNew ? nextDay : null].filter((x) => x != null);
        if (!candidates.length) return null;
        t = Math.min(...candidates);
      }
      return { at: t, heldBack: this.holding(), cards: this.pickCards(t).length };
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
      if (today !== s.introduced.day) s.introduced = { day: today, count: 0 };
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
      if (this.holding()) {
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
        const wait = Math.round(this.settings.waitAfterSuppression / MINUTE);
        if (s.heldBack) this.log(`Over: the appearance waits ${wait} minute${wait === 1 ? '' : 's'}`, 'held');
        s.heldBack = false;
      }
      if (kind) this.log(SUPPRESSIONS[kind][0].toUpperCase() + SUPPRESSIONS[kind].slice(1), 'held');
      this.emit();
    }
    setMeeting(on) {
      this.setSuppression(on ? 'meeting' : null);
    }

    /** ⌘+, ⌘− and ⌘0, or a percent from Settings: the card's size, from 80% to 200% by tens (CardSize). */
    setCardSize(key) {
      const p = this.state.cardSize;
      const step = key === '0' ? 100 : key === '-' ? Math.max(80, p - 10) : Math.min(200, p + 10);
      const next = typeof key === 'number' ? key : step;
      this.state.cardSize = next;
      this.emit();
    }

    // Settings.
    /** Changes one of ReviewSettings' values, by its name in SETTINGS. */
    setSetting(key, value) {
      this.settings = { ...this.settings, [key]: value };
      this.changed();
      this.emit();
    }
    setRetention(retention) {
      this.scheduler = { ...this.scheduler, retention };
      this.log(`Desired retention ${Math.round(retention * 100)}%`, 'deck');
      this.changed();
      this.emit();
    }

    // The pace and the queue (ADR 0034).
    setPace(pace) {
      if (this.state.pace === pace) return;
      this.state.pace = pace;
      const p = paceOf(pace);
      this.log(`Pace: ${p.name}, ${p.perDay} new a day`, 'deck');
      this.changed();
      this.emit();
    }
    /** Adds a deck at the end of the queue, or first when asked, as `putFirst` puts it. */
    addDeck(id, { first = false } = {}) {
      const d = this.deck(id);
      const s = this.state;
      d.added = true;
      d.setAside = false;
      d.addedAt = d.addedAt ?? s.now;
      for (const c of this.deckCards(id)) c.createdAt = c.createdAt ?? s.now;
      s.queue = [...s.queue.filter((x) => x !== id), id];
      if (first) this.moveFirst(id);
      this.log(`Added ${d.name}, ${first ? 'first' : 'last'} in the queue`, 'deck');
      this.changed();
      this.emit();
    }
    /** A deck of the user's own, with no cards yet, as New Deck… makes it; returns its id. */
    newDeck(name = 'New Deck') {
      const s = this.state;
      const id = `own-${s.decks.length}`;
      s.decks.push({ id, name, emoji: '🗂️', ficha: false, added: false, addedAt: null, metAllAt: null, setAside: false });
      return id;
    }
    /**
     * A card the user adds in the card form, new, last in its deck, as the
     * app's Add puts it (#538): with no tags, which the form no longer has.
     */
    addCard(deckId, { front, back, source = null, bothWays = false }) {
      const s = this.state;
      const order = this.deckCards(deckId).length;
      s.cards = [
        ...s.cards,
        { id: `${deckId}-${order}`, deckId, order, front, back, picture: false, source, bothWays, tags: [], state: 'new',
          step: 0, mem: null, due: null, last: null, createdAt: s.now, editedAt: null, reviewLog: [] },
      ];
      this.log(`Added “${front}” to ${this.deck(deckId).name}`, 'deck');
      this.changed();
      this.emit();
    }
    /** Puts a deck first in the queue, as `moveFirst` moves it. */
    putFirst(id) {
      this.moveFirst(id);
      this.log(`${this.deck(id).name} goes first`, 'deck');
      this.changed();
      this.emit();
    }
    /**
     * Moves a deck to the first place in the queue held by a deck with
     * cards not met, not set aside, as FichaCore's
     * `places(putting:at:now:)` does: the decks it passes move down into
     * each other's places, and a deck met in full or set aside keeps its
     * own, so one ahead of them stays ahead of it. A deck not in the queue
     * yet comes in last before it moves, as `addDeck` puts it.
     */
    moveFirst(id) {
      const s = this.state;
      const queue = s.queue.includes(id) ? [...s.queue] : [...s.queue, id];
      const moves = (x) => x === id || (!this.deck(x).setAside && this.newLeft(x) > 0);
      const places = queue.flatMap((x, i) => (moves(x) ? [i] : []));
      const order = [id, ...places.map((i) => queue[i]).filter((x) => x !== id)];
      places.forEach((place, k) => {
        queue[place] = order[k];
      });
      s.queue = queue;
    }
    /**
     * Sets a deck aside, out of the queue, or brings it back to its place,
     * as FichaCore's queue does (provisional in ADR 0034).
     */
    setAside(id, aside = true) {
      const d = this.deck(id);
      d.setAside = aside;
      this.log(aside ? `${d.name} set aside` : `${d.name} back in the queue, at its place`, 'deck');
      this.changed();
      this.emit();
    }
    /**
     * Whether a new card can still come today: while active hours inside
     * today's Ficha day aren't over, as DeckQueue's newCardsLeftToday says.
     */
    canMeetToday(at = this.state.now) {
      return intoActiveHours(at, this.settings) < startOfDay(at, this.settings) + DAY;
    }
    /**
     * Each queued deck's finish date (ADR 0034): when the user will have met
     * all its cards, as a range of days, from the pace and the decks ahead
     * of it. `add` places a deck not yet added, last or `first`, to answer
     * How fast?; `pace` tries another pace. Days without appearances move
     * the dates later, since they count from today's cards not met.
     */
    finishDates({ pace = this.state.pace, add = null, first = false } = {}) {
      let ids = this.queueDecks().map((d) => d.id);
      if (add) {
        ids = ids.filter((x) => x !== add);
        if (first) ids.unshift(add);
        else ids.push(add);
      }
      const decks = ids.filter((id) => this.newLeft(id) > 0);
      const s = this.state;
      const used = s.introduced.day === dayKey(s.now, this.settings) ? s.introduced.count : 0;
      const today = this.canMeetToday() ? Math.max(0, this.perDay(pace) - used) : 0;
      const days = finishDays({ left: decks.map((id) => this.newLeft(id)), perDay: this.perDay(pace), today });
      const start = startOfDay(s.now, this.settings);
      const out = {};
      decks.forEach((id, i) => {
        out[id] = {
          ...days[i],
          left: this.newLeft(id),
          soonestAt: start + days[i].soonest * DAY,
          latestAt: start + days[i].latest * DAY,
          place: i,
        };
      });
      return out;
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
        // The decks whose last new card this panel met: "You've met them all".
        metAll: [],
      };
      s.heldBack = false;
      this.log(kind === 'appearance' ? `Appearance, ${queue.length} card${queue.length > 1 ? 's' : ''}` : `Review now, ${queue.length} cards`, 'appear');
    }
    reviewNow() {
      if (this.state.panel) return;
      const queue = this.pickCards(this.state.now, 0);
      if (queue.length) this.open('reviewNow', queue);
      else this.state.panel = { kind: 'empty', queue: [], index: 0, touchedAt: this.state.now, undo: [], openedAt: this.state.now, metAll: [] };
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
    /** Records Anki's rating g, 1 to 4, whichever button or key gave it. */
    rate(g) {
      const p = this.state.panel;
      const card = this.currentCard();
      if (!card || !p.flipped) return;
      const now = this.state.now;
      const wasNew = card.state === 'new';
      p.undo.push({ index: p.index, card: { ...card } });
      if (wasNew) {
        const intro = this.state.introduced;
        intro.count++;
      }
      Object.assign(card, rate(card, g, now, this.scheduler));
      // A new array, so that undo's copy keeps the log as it was.
      card.reviewLog = [...(card.reviewLog || []), { t: now, g, wait: card.due - now }];
      const deck = this.deck(card.deckId);
      if (wasNew && this.newLeft(deck.id) === 0) {
        deck.metAllAt = now;
        p.metAll.push(deck.id);
        this.log(`You've met them all: ${deck.name}`, 'done');
      }
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
        this.state.introduced.count--;
        this.deck(card.deckId).metAllAt = null;
        p.metAll = p.metAll.filter((id) => id !== card.deckId);
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
    /** Sets the card the panel shows aside, out of the reviews until it's put back, and moves on. */
    setCurrentCardAside() {
      const card = this.currentCard();
      if (!card) return;
      this.state.cardsSetAside = { ...this.state.cardsSetAside, [card.id]: this.state.now };
      this.toast('Set aside');
      this.changed();
      this.advance();
      this.touch();
      this.emit();
    }
    /**
     * Sets a card aside, as the Cards window's Set Aside does, or with
     * `aside` false puts it back, where it stood: its progress never moved.
     */
    setCardAside(id, aside = true) {
      const card = this.card(id);
      const { [id]: _, ...others } = this.state.cardsSetAside;
      this.state.cardsSetAside = aside ? { ...others, [id]: this.state.now } : others;
      this.log(aside ? `${card.front} set aside` : `${card.front} put back`, 'deck');
      this.changed();
      this.emit();
    }
    setMode(mode) {
      const p = this.state.panel;
      if (!p || p.done) return;
      p.mode = mode;
      this.touch();
      this.emit();
    }
    /**
     * Flags the panel's card with the user's note on what to fix: it leaves
     * the reviews and waits in its deck, with its flag and its note, until
     * it's fixed, and the panel goes on to the next card (#540).
     */
    flag(note) {
      const card = this.currentCard();
      if (!card) return;
      this.state.flagged[card.id] = { note, at: this.state.now };
      this.state.panel.mode = null;
      this.toast("Flagged. It waits in its deck until it's fixed.");
      this.changed();
      this.advance();
      this.touch();
      this.emit();
    }
    /**
     * Flags a card from outside the panel, as a mock that opens with one
     * flagged does.
     */
    flagCard(id, note) {
      this.state.flagged[id] = { note, at: this.state.now };
      this.changed();
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

  root.FichaEngine = {
    MINUTE,
    HOUR,
    DAY,
    FSRS,
    SCHEDULER,
    NEW_INSTALL_RETENTION,
    SETTINGS,
    SUPPRESSIONS,
    PACES,
    finishDays,
    rate,
    preview,
    fuzz,
    formatInterval,
    intoActiveHours,
    inActiveHours,
    startOfDay,
    seeded,
    pretendRating,
    ToyFicha,
  };
})(typeof window !== 'undefined' ? window : globalThis);
