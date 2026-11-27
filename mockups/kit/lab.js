/*
 * Ficha mock kit: the lab. Runs weeks of Ficha in a made-up person's life,
 * with the toy engine (checked against FichaKit by tools/check-engine.js),
 * and counts what a setting costs and gives: how often Ficha interrupts,
 * how many minutes a day it takes, how many cards graduate.
 *
 * Plain JavaScript: the Lab page and tools/simulate.js run the same code.
 * Needs engine.js, and decks.js for the sample decks.
 */
(function (root) {
  'use strict';

  const E = root.FichaEngine;
  const { MINUTE, HOUR, DAY } = E;

  /**
   * A setting to try, as the Lab's defaults: Ficha as ADR 0034 decided it,
   * and a working week.
   */
  const DEFAULTS = {
    days: 28,
    runs: 8,
    // Ficha's settings (ReviewSettings.defaults, Scheduler.standard), with
    // ADR 0034's pace, queue and retention.
    cardsPerAppearance: 5,
    separationMinutes: 30,
    activeHours: [9, 22],
    lookAheadMinutes: 20,
    newPerAppearance: 1,
    // New cards a day, for all decks together: Steady.
    newPerDay: 2,
    // New cards from one deck at a time, the queue's first; false splits
    // them between every deck in turn, ADR 0034's "one pace split between them".
    queue: true,
    retention: 0.85,
    // The decks in use, in the queue's order: a sample deck's id, or a
    // made-up deck with a number of cards.
    decks: [{ id: 'flores-de-buenos-aires' }, { id: 'palabras-lindas' }],
    // The person: when the Mac is on, meetings, and how they answer.
    life: {
      weekday: [9, 18.5],
      eveningChance: 0.3,
      evening: [20, 22],
      weekendChance: 0.4,
      weekend: [10, 13],
      meetingsPerDay: 2,
      meetingMinutes: [30, 60],
      snoozeChance: 0.1,
      secondsPerCard: 8,
    },
  };

  const merge = (base, over) => ({ ...base, ...over, life: { ...base.life, ...(over && over.life) } });

  /** The Mac's hours and the meetings of one day, made up but repeatable. */
  function planDay(dayStart, life, random) {
    const weekday = new Date(dayStart).getDay();
    const isWeekend = weekday === 0 || weekday === 6;
    const at = (h) => dayStart + h * HOUR;
    const on = [];
    if (isWeekend) {
      if (random() < life.weekendChance) on.push([at(life.weekend[0]), at(life.weekend[1])]);
    } else {
      on.push([at(life.weekday[0]), at(life.weekday[1])]);
      if (random() < life.eveningChance) on.push([at(life.evening[0]), at(life.evening[1])]);
    }
    const meetings = [];
    if (!isWeekend && on.length) {
      const [from, to] = on[0];
      const slots = Math.floor((to - from) / (30 * MINUTE)) - 1;
      // Around meetingsPerDay meetings, some days more and some fewer.
      const count = Math.max(0, Math.round(life.meetingsPerDay + (random() - 0.5) * 2));
      for (let i = 0; i < count && slots > 0; i++) {
        const start = from + Math.floor(random() * slots) * 30 * MINUTE;
        const [lo, hi] = life.meetingMinutes;
        const length = (lo + Math.round((random() * (hi - lo)) / 15) * 15) * MINUTE;
        if (!meetings.some(([a, b]) => start < b && start + length > a)) meetings.push([start, start + length]);
      }
      meetings.sort((a, b) => a[0] - b[0]);
    }
    return { isWeekend, on, meetings };
  }
  const inside = (spans, t) => spans.some(([a, b]) => t >= a && t < b);

  function decksFor(config) {
    const samples = root.FichaDecks || [];
    return config.decks.map((d, i) => {
      const sample = samples.find((s) => s.id === d.id);
      if (sample) return { ...sample };
      const n = d.cards || 20;
      return {
        id: d.id || `deck${i}`,
        name: d.name || `Deck of ${n}`,
        emoji: '🗂️',
        cards: Array.from({ length: n }, (_, k) => ({ front: `Card ${k + 1}`, back: '' })),
      };
    });
  }

  /** One run: every day of `config.days`, from Monday `start`. */
  function runOnce(config, start, seed) {
    // Two streams of chance: the days (the Mac's hours, the meetings) and the
    // person's answers. A setting changes how many answers there are, so the
    // days get their own stream, planned up front: every setting meets the
    // same days, and A and B differ only by what the setting does.
    const life = config.life;
    const dayRandom = E.seeded(seed);
    const random = E.seeded(seed + 104729);
    const plans = Array.from({ length: config.days }, (_, day) => planDay(start + day * DAY, life, dayRandom));
    const settings = {
      ...E.SETTINGS,
      cardsPerAppearance: config.cardsPerAppearance,
      separation: config.separationMinutes * MINUTE,
      activeHours: config.activeHours,
      lookAhead: config.lookAheadMinutes * MINUTE,
      newPerAppearance: config.newPerAppearance,
      newCardsFrom: config.queue ? 'queue' : 'together',
    };
    const scheduler = { ...E.SCHEDULER, retention: config.retention };
    const decks = decksFor(config);
    const app = new E.ToyFicha({ decks, now: start, speed: 0, settings, scheduler, pace: config.newPerDay });
    decks.forEach((d) => app.addDeck(d.id));
    const total = app.state.cards.length;
    const s = app.state;
    const days = [];
    let allMetDay = null;
    // The day each deck's last new card was met, in the decks' order.
    const deckMetDay = decks.map(() => null);

    for (let day = 0; day < config.days; day++) {
      const dayStart = start + day * DAY;
      const dayEnd = dayStart + DAY;
      const plan = plans[day];
      const stats = {
        day: dayStart,
        weekend: plan.isWeekend,
        macHours: plan.on.reduce((h, [a, b]) => h + (b - a) / HOUR, 0),
        meetings: plan.meetings.length,
        appearances: 0,
        heldBack: 0,
        snoozed: 0,
        reviews: 0,
        recalls: 0,
        graduatedReviews: 0,
        newMet: 0,
        seconds: 0,
        cardsPerAppearance: [],
      };
      const bounds = [...plan.on.flat(), ...plan.meetings.flat(), dayEnd].filter((b) => b > dayStart).sort((a, b) => a - b);
      let t = dayStart;
      let heldThisEpisode = false;
      let wasOn = false;
      let wasMeeting = false;
      for (let guard = 0; guard < 5000 && t < dayEnd; guard++) {
        const on = inside(plan.on, t);
        const meeting = on && inside(plan.meetings, t);
        // Waking the Mac and the end of a meeting each make Ficha wait 2 minutes.
        if ((on && !wasOn) || (wasMeeting && !meeting)) s.suppressionEndedAt = t;
        if (meeting !== wasMeeting) heldThisEpisode = false;
        wasOn = on;
        wasMeeting = meeting;
        s.now = t;
        s.suppression = meeting ? 'meeting' : null;
        if (s.introduced.day !== E.startOfDay(t, settings)) s.introduced = { day: E.startOfDay(t, settings), count: 0 };
        const next = on ? app.nextAppearance() : null;
        const boundary = bounds.find((b) => b > t) ?? dayEnd;
        if (next && next.at <= t) {
          if (meeting) {
            if (!heldThisEpisode) stats.heldBack++;
            heldThisEpisode = true;
            t = boundary;
            continue;
          }
          const queue = app.pickCards(t);
          stats.appearances++;
          stats.cardsPerAppearance.push(queue.length);
          if (random() < life.snoozeChance) {
            stats.snoozed++;
            t += MINUTE;
          } else {
            for (const id of queue) {
              const card = app.card(id);
              const g = E.pretendRating(card, t, random);
              if (card.state === 'new') {
                stats.newMet++;
                s.introduced.count++;
              }
              if (card.state === 'review') {
                stats.graduatedReviews++;
                if (g > 1) stats.recalls++;
              }
              Object.assign(card, E.rate(card, g, t, scheduler));
              stats.reviews++;
              stats.seconds += life.secondsPerCard;
              t += life.secondsPerCard * 1000;
            }
            t += 5000;
          }
          s.lastClosedAt = t;
          continue;
        }
        t = Math.min(next ? next.at : Infinity, boundary);
      }
      stats.graduated = s.cards.filter((c) => c.state === 'review').length;
      stats.met = s.cards.filter((c) => c.state !== 'new').length;
      stats.dueLeft = s.cards.filter((c) => c.state !== 'new' && c.due < dayEnd).length;
      if (allMetDay == null && stats.met === total) allMetDay = day;
      decks.forEach((d, i) => {
        if (deckMetDay[i] == null && app.newLeft(d.id) === 0) deckMetDay[i] = day;
      });
      days.push(stats);
    }
    return { days, total, allMetDay, deckMetDay };
  }

  const mean = (xs) => (xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : 0);

  /**
   * Runs `config` (the Lab's defaults with what it changes) `runs` times and
   * averages each day, then sums it up.
   */
  function simulate(over = {}, { start } = {}) {
    const config = merge(DEFAULTS, over);
    const monday = start ?? nextMonday(Date.now());
    const runs = Array.from({ length: config.runs }, (_, r) => runOnce(config, monday, 1000 + r * 7919));
    const n = config.days;
    const keys = ['appearances', 'heldBack', 'snoozed', 'reviews', 'newMet', 'seconds', 'graduated', 'met', 'dueLeft', 'macHours', 'meetings', 'recalls', 'graduatedReviews'];
    const days = Array.from({ length: n }, (_, d) => {
      const out = { day: runs[0].days[d].day, weekend: runs[0].days[d].weekend };
      for (const k of keys) out[k] = mean(runs.map((r) => r.days[d][k]));
      out.minutes = out.seconds / 60;
      return out;
    });
    const weekdays = days.filter((d) => !d.weekend);
    const all = runs.flatMap((r) => r.days);
    const perAppearance = all.flatMap((d) => d.cardsPerAppearance);
    const recalls = all.reduce((a, d) => a + d.recalls, 0);
    const graduated = all.reduce((a, d) => a + d.graduatedReviews, 0);
    const metDays = runs.map((r) => r.allMetDay);
    const total = runs[0].total;
    const deckNames = decksFor(config).map((d) => d.name);
    const last = days[n - 1];
    return {
      config,
      days,
      totals: {
        cards: total,
        appearancesPerWeekday: mean(weekdays.map((d) => d.appearances)),
        appearancesPerMacHour: mean(weekdays.map((d) => (d.macHours ? d.appearances / d.macHours : 0))),
        minutesPerWeekday: mean(weekdays.map((d) => d.minutes)),
        busiestMinutes: Math.max(...days.map((d) => d.minutes)),
        cardsPerAppearance: mean(perAppearance),
        heldBackPerWeekday: mean(weekdays.map((d) => d.heldBack)),
        snoozedShare: mean(all.map((d) => d.snoozed)) / Math.max(1e-9, mean(all.map((d) => d.appearances))),
        recall: graduated ? recalls / graduated : null,
        met: last.met,
        graduated: last.graduated,
        dueLeft: last.dueLeft,
        // The day the last new card was met, in every run; null where some never were.
        allMetDay: metDays.every((d) => d != null) ? mean(metDays) : null,
        allMetLatest: metDays.every((d) => d != null) ? Math.max(...metDays) : null,
        allMetShare: metDays.filter((d) => d != null).length / metDays.length,
        // Each deck, in the queue's order: the day its cards were all met, or null where some run never did.
        decks: deckNames.map((name, i) => {
          const each = runs.map((r) => r.deckMetDay[i]);
          return { name, metDay: each.every((d) => d != null) ? mean(each) : null };
        }),
      },
    };
  }

  function nextMonday(t) {
    const d = new Date(t);
    d.setHours(0, 0, 0, 0);
    const add = (8 - d.getDay()) % 7 || 7;
    d.setDate(d.getDate() + add);
    return d.getTime();
  }

  root.FichaLab = { DEFAULTS, simulate, planDay, merge, nextMonday };
})(typeof window !== 'undefined' ? window : globalThis);
