// Checks the mock's toy engine against FichaKit's own tests, so what the
// mock and the lab show is what the app would do.
//   node mockups/tools/check-engine.js    (from the repo's folder)
// Each case cites the Swift test it copies, in Packages/FichaKit/Tests.
const path = require('path');
require(path.join(__dirname, '..', 'kit', 'engine.js'));
const E = globalThis.FichaEngine;
const { FSRS, rate, preview, SCHEDULER, DAY, HOUR, PACES, ToyFicha, finishDays } = E;

let failed = 0;
const check = (name, ok, got) => {
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${name}${ok ? '' : `: got ${JSON.stringify(got)}`}`);
  if (!ok) failed++;
};
const near = (a, b, tol = 1e-3) => Math.abs(a - b) < tol;
const start = new Date(2026, 0, 5, 10, 0).getTime();
const fresh = (id = 'c1') => ({ id, state: 'new', step: 0, mem: null, last: null, reps: 0 });
const days = (p) => [1, 2, 3, 4].map((g) => Math.round(p[g].wait / DAY));
const noSteps = { ...SCHEDULER, learningSteps: [] };

// FSRSTests.newCardsNextStates: a new card's next states at 90%.
{
  const mems = [1, 2, 3, 4].map((g) => FSRS.nextMemory(null, g, 0));
  check('a new card\'s stabilities are 0.212, 1.2931, 2.3065, 8.2956',
    mems.every((m, i) => near(m.S, [0.212, 1.2931, 2.3065, 8.2956][i], 1e-6)), mems.map((m) => m.S));
  check('a new card\'s difficulties are 6.4133, 5.1121707, 2.118104, 1.0',
    mems.every((m, i) => near(m.D, [6.4133, 5.1121707, 2.118104, 1.0][i], 1e-5)), mems.map((m) => m.D));
}
// SchedulerIntervalsTests.retrievability: 90% once the stability's days have passed.
{
  check('retrievability is 90% once the stability\'s days have passed', near(FSRS.retrievability(7, 7), 0.9, 1e-6), FSRS.retrievability(7, 7));
}
// SchedulerIntervalsTests.memoryAfterKnownRatings: fsrs-rs's test_memory_state.
{
  let card = fresh();
  let t = start;
  card = rate(card, 1, t);
  t += HOUR;
  card = rate(card, 3, t);
  for (const d of [1, 3, 8, 21]) {
    t += d * DAY;
    card = rate(card, 3, t);
  }
  check('again, good the same day, then good 1, 3, 8 and 21 days apart: S 53.62691, D 6.3574867',
    near(card.mem.S, 53.62691, 1e-2) && near(card.mem.D, 6.3574867, 1e-3), card.mem);
}
// SchedulerIntervalsTests.newWaysIntervalsWithoutSteps.
{
  const p = preview(fresh(), start, noSteps);
  const d = days(p);
  check('with no learning steps, a new card\'s days are 1, 1, 2 and 6 to 10', d[0] === 1 && d[1] === 1 && d[2] === 2 && d[3] >= 6 && d[3] <= 10, d);
}
// SchedulerIntervalsTests.fuzzWithinAnkisRange.
{
  const easy = new Set();
  for (let i = 1; i <= 300; i++) easy.add(days(preview(fresh(`c${i}`), start, noSteps))[3]);
  check('a new card\'s easy falls anywhere from 6 to 10 days across 300 cards', [6, 7, 8, 9, 10].every((x) => easy.has(x)) && easy.size === 5, [...easy].sort());
  const a = days(preview(fresh('c7'), start, noSteps))[3];
  const b = days(preview(fresh('c7'), start + DAY, noSteps))[3];
  check('the same card always lands on the same day', a === b, [a, b]);
}
// SchedulerIntervalsTests.hardGoodAndEasyADayApart.
{
  const s99 = { ...noSteps, retention: 0.99 };
  const card = rate(fresh(), 2, start, s99);
  const d = days(preview(card, start + DAY, s99));
  check('at 99%, a graduated card\'s hard, good and easy are 1, 2 and 3 days', d[1] === 1 && d[2] === 2 && d[3] === 3, d);
}
// SchedulerIntervalsTests.theLongestIntervalCaps.
{
  const s10 = { ...SCHEDULER, longestIntervalDays: 10 };
  const card = { ...fresh(), state: 'review', mem: { S: 30, D: 5 }, last: start - 30 * DAY, reps: 3 };
  const d = days(preview(card, start, s10));
  check('the longest interval caps hard, good and easy', d[1] <= 10 && d[2] === 10 && d[3] === 10, d);
}
// SchedulerStepsTests: Ficha's standard steps.
{
  // againAndHardOnANewWay, goodAndEasyOnANewWay
  const p = preview(fresh(), start);
  const waits = [1, 2, 3].map((g) => p[g].wait / HOUR);
  check('a new card: again waits 1 h, hard 2.5 h, good 4 h (the second step)', waits.join() === '1,2.5,4', waits);
  check('a new card: easy graduates it', p[4].card.state === 'review', p[4].card.state);
  // eachRatingOnTheLastLearningStep
  const onLast = rate(fresh(), 3, start);
  const q = preview(onLast, start + 4 * HOUR);
  check('on the last step, again goes back to the first, hard repeats it, good and easy graduate',
    q[1].wait === HOUR && q[2].wait === 4 * HOUR && q[3].card.state === 'review' && q[4].card.state === 'review',
    [q[1].wait / HOUR, q[2].wait / HOUR, q[3].card.state, q[4].card.state]);
  // eachRatingOfAGraduatedWay
  const graduated = { ...fresh(), state: 'review', mem: { S: 10, D: 5 }, last: start - 10 * DAY, reps: 4 };
  const r = preview(graduated, start);
  check('again on a graduated card is a lapse, to the relearning step of 1 h', r[1].card.state === 'relearning' && r[1].wait === HOUR, [r[1].card.state, r[1].wait / HOUR]);
  // eachRatingOnTheOneRelearningStep
  const relearning = r[1].card;
  const s = preview(relearning, start + HOUR);
  check('on the one relearning step, hard waits 1.5 times as long, good and easy graduate',
    s[2].wait === 1.5 * HOUR && s[3].card.state === 'review' && s[4].card.state === 'review', [s[2].wait / HOUR, s[3].card.state]);
}
// SchedulerIntervalsTests.elapsedDaysAreRounded: 11 h counts as the same day, 13 h as the next.
{
  const after = (h) => rate({ ...fresh(), state: 'review', mem: { S: 5, D: 5 }, last: start, reps: 2 }, 3, start + h * HOUR).mem.S;
  check('days since the last review round to the nearest whole day', after(11) === after(0.1) && after(13) === after(24), [after(11), after(13)]);
}

// PaceAndQueueTests.aNewInstallStartsAtSteady: Chill, Steady and Faster,
// Steady to start, and 85% on a new install.
{
  check('the paces are 1, 2 and 4 new cards a day', PACES.map((p) => p.perDay).join() === '1,2,4', PACES.map((p) => p.perDay));
  const app = new ToyFicha({ decks: [], now: start, speed: 0 });
  check('a new install starts at Steady and 85%', app.perDay() === 2 && app.scheduler.retention === 0.85, [app.perDay(), app.scheduler.retention]);
}
// PaceAndQueueTests.newCardsComeFromTheFirstDeckAlone: at Steady, new cards
// come from the first deck in the queue alone, 2 a day, and then from the next.
{
  const deckOf = (id, fronts) => ({ id, name: id, cards: fronts.map((front) => ({ front, back: '' })) });
  const app = new ToyFicha({ decks: [deckOf('arte', ['a', 'b', 'c']), deckOf('historia', ['d'])], now: start, speed: 0 });
  app.addDeck('arte');
  app.addDeck('historia');
  const meetEachNewCard = (t) => {
    app.state.now = t;
    if (app.state.introduced.day !== E.startOfDay(t)) app.state.introduced = { day: E.startOfDay(t), count: 0 };
    const met = [];
    for (let id; (id = app.pickCards(t, 0).find((x) => app.card(x).state === 'new')) && met.length < 10; ) {
      Object.assign(app.card(id), rate(app.card(id), 1, t));
      app.state.introduced.count++;
      met.push(id);
    }
    return met;
  };
  const firstDay = meetEachNewCard(start);
  const secondDay = meetEachNewCard(start + DAY);
  check('2 new cards a day from the first deck, then from the next', firstDay.join() === 'arte-0,arte-1' && secondDay.join() === 'arte-2,historia-0', [firstDay, secondDay]);
}
// PaceAndQueueTests.aDeckThatComesInGoesLast and aSetAsideDeckLeavesTheQueue:
// a deck goes last, or first when asked; a deck set aside leaves the queue
// and comes back to its place.
{
  const deckOf = (id) => ({ id, name: id, cards: [{ front: id, back: '' }] });
  const app = new ToyFicha({ decks: ['arte', 'historia', 'musica', 'lenguaje'].map(deckOf), now: start, speed: 0 });
  ['arte', 'historia', 'musica'].forEach((id) => app.addDeck(id));
  app.addDeck('lenguaje', { first: true });
  const queue = () => app.queueDecks().map((d) => d.id).join();
  check('a deck goes last, or first when asked', queue() === 'lenguaje,arte,historia,musica', queue());
  app.setAside('arte');
  const setAside = queue();
  app.setAside('arte', false);
  check('a deck set aside leaves the queue and comes back to its place', setAside === 'lenguaje,historia,musica' && queue() === 'lenguaje,arte,historia,musica', [setAside, queue()]);
}
// PaceAndQueueTests.aDecksFinishDateCountsWhatTodayStillBrings: Arte's 2
// new ways left once La Gioconda is met today, with 1 still to come today at
// Steady, 3 at Faster, and none once active hours are over.
{
  const days = (f) => f.map((d) => `${d.soonest}-${d.latest}`).join();
  const steady = finishDays({ left: [2], perDay: 2, today: 1 });
  const faster = finishDays({ left: [2], perDay: 4, today: 3 });
  const late = finishDays({ left: [2], perDay: 4, today: 0 });
  check('the new cards met today count, and a late hour brings none', days(steady) === '1-2' && days(faster) === '0-0' && days(late) === '1-2', [days(steady), days(faster), days(late)]);
}
// PaceAndQueueTests.aDecksFinishDate: Arte's 3 new cards and then
// Historia's 4, with today's 2 still to come at Steady, or 4 at Faster.
{
  const steady = finishDays({ left: [3, 4], perDay: 2, today: 2 });
  const faster = finishDays({ left: [3, 4], perDay: 4, today: 4 });
  const days = (f) => f.map((d) => `${d.soonest}-${d.latest}`).join();
  check('at Steady, the finish dates are 1 to 2 days away and 3 to 5', days(steady) === '1-2,3-5', days(steady));
  check('at Faster, they are today and 1 to 2 days away', days(faster) === '0-0,1-2', days(faster));
}

console.log(failed
  ? `\n${failed} failed: mockups/kit/engine.js no longer matches FichaKit's tests. Change engine.js until they pass, or the case above if the Swift test it copies changed (mockups/README.md).`
  : '\nAll match FichaKit.');
process.exit(failed ? 1 : 0);
