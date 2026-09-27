/**
 * Pins increment 4 (perch handoff): lastTab / lastX / lastSeat sequences
 * for focus, blur, drag, and transientSlot - without a renderer.
 */
import { deepStrictEqual, ok, strictEqual } from 'node:assert';

import { PERCH_SIZE, tabCenterX } from './perch-geometry';
import {
  applyDragRelease,
  applyDragTrack,
  applyFocusBlur,
  focusFromSlot,
  initialPerchHandoff,
  initialReleaseState,
  liveLastSeat,
  planApproach,
  planDragRelease,
  planFocus,
  planMountSeatY,
  planRunSeatY,
  planStartSeatY,
  readPerchHandoff,
  reduceRelease,
  resetPerchHandoffForTest,
  selectsOnRelease,
  writePerchHandoff,
} from './perch-handoff';
import type { DragReleasePlan } from './perch-handoff';

const WIDTH = 402;
const SLOT_COUNT = 5;
// stand-in for a raised seat (e.g. above a composer bar) above the tab bar
const RAISED_SEAT = 24;

function tabX(tab: number): number {
  return tabCenterX(tab, WIDTH, SLOT_COUNT);
}

function testInitialHandoff(): void {
  deepStrictEqual(initialPerchHandoff(), { lastTab: 0, lastX: null, lastSeat: 0 });
}

function testTransientNeverWritesHandoff(): void {
  const start = { lastTab: 1, lastX: 120, lastSeat: RAISED_SEAT };
  const plan = planFocus(start, {
    tab: 4,
    screenWidth: WIDTH,
    bottomExtra: RAISED_SEAT,
    transientSlot: true,
    reduceMotion: false,
    slotCount: SLOT_COUNT,
  });
  strictEqual(plan.kind, 'transient-snap');
  strictEqual(plan.commitsHandoff, false);
  deepStrictEqual(plan.next, start, 'transientSlot must not touch lastTab/lastX/lastSeat');
  const afterBlur = applyFocusBlur(start, { currentX: 200, transientSlot: true });
  deepStrictEqual(afterBlur, start, 'transient blur must not write lastX');
}

function testSameTabSnapClearsLastX(): void {
  const start = { lastTab: 2, lastX: 180, lastSeat: 0 };
  const plan = planFocus(start, {
    tab: 2,
    screenWidth: WIDTH,
    bottomExtra: 0,
    transientSlot: false,
    reduceMotion: false,
    slotCount: SLOT_COUNT,
  });
  strictEqual(plan.kind, 'same-tab-snap');
  strictEqual(plan.fromX, tabX(2));
  strictEqual(plan.fromSeatY, 0);
  deepStrictEqual(plan.next, { lastTab: 2, lastX: null, lastSeat: 0 });
}

function testCrossTabChaseUsesLastXThenClears(): void {
  const from = tabX(0) + 40;
  const start = { lastTab: 0, lastX: from, lastSeat: 0 };
  const plan = planFocus(start, {
    tab: 4,
    screenWidth: WIDTH,
    bottomExtra: 0,
    transientSlot: false,
    reduceMotion: false,
    slotCount: SLOT_COUNT,
  });
  strictEqual(plan.kind, 'run-chase');
  strictEqual(plan.fromX, from, 'chase starts from the frozen mid-traverse x');
  strictEqual(plan.targetX, tabX(4));
  ok(Math.abs(plan.targetX - plan.fromX) >= PERCH_SIZE, 'fixture is a real run');
  deepStrictEqual(plan.next, { lastTab: 4, lastX: null, lastSeat: 0 });
}

function testCrossTabFallsBackToLastTabCenter(): void {
  const start = { lastTab: 0, lastX: null, lastSeat: 0 };
  const plan = planFocus(start, {
    tab: 3,
    screenWidth: WIDTH,
    bottomExtra: 0,
    transientSlot: false,
    reduceMotion: false,
    slotCount: SLOT_COUNT,
  });
  strictEqual(plan.kind, 'run-chase');
  strictEqual(plan.fromX, tabX(0), 'without lastX, origin is lastTab center');
}

function testAltitudeGlideUsesLastSeat(): void {
  const start = { lastTab: 4, lastX: tabX(4), lastSeat: RAISED_SEAT };
  const plan = planFocus(start, {
    tab: 0,
    screenWidth: WIDTH,
    bottomExtra: 0,
    transientSlot: false,
    reduceMotion: false,
    slotCount: SLOT_COUNT,
  });
  strictEqual(plan.fromSeatY, 0 - RAISED_SEAT, 'land at bar level from the raised seat');
  strictEqual(plan.runSeatY, 0, 'drop immediately when leaving the raised seat, do not float');
  deepStrictEqual(plan.next.lastSeat, 0);
}

function testArriveAtRaisedSeatHoldsBarUntilCatch(): void {
  const start = { lastTab: 0, lastX: tabX(0), lastSeat: 0 };
  const plan = planFocus(start, {
    tab: 4,
    screenWidth: WIDTH,
    bottomExtra: RAISED_SEAT,
    transientSlot: false,
    reduceMotion: false,
    slotCount: SLOT_COUNT,
  });
  strictEqual(plan.kind, 'run-chase');
  strictEqual(
    plan.fromSeatY,
    RAISED_SEAT,
    'raised-seat instance starts at bar (24pt down from the seat)'
  );
  strictEqual(plan.runSeatY, RAISED_SEAT, 'hold bar altitude during the run');
  deepStrictEqual(plan.next, { lastTab: 4, lastX: null, lastSeat: RAISED_SEAT });
}

function testPlanRunSeatYDirectional(): void {
  strictEqual(planRunSeatY(RAISED_SEAT), RAISED_SEAT, 'climb: hold the lower seat');
  strictEqual(planRunSeatY(-RAISED_SEAT), 0, 'descend: drop immediately');
  strictEqual(planRunSeatY(0), 0);
}

function testPlanStartSeatY(): void {
  const climb = planFocus(
    { lastTab: 0, lastX: tabX(0), lastSeat: 0 },
    {
      tab: 4,
      screenWidth: WIDTH,
      bottomExtra: RAISED_SEAT,
      transientSlot: false,
      reduceMotion: false,
      slotCount: SLOT_COUNT,
    }
  );
  strictEqual(planStartSeatY(climb), RAISED_SEAT);
  const leave = planFocus(
    { lastTab: 4, lastX: tabX(4), lastSeat: RAISED_SEAT },
    {
      tab: 0,
      screenWidth: WIDTH,
      bottomExtra: 0,
      transientSlot: false,
      reduceMotion: false,
      slotCount: SLOT_COUNT,
    }
  );
  strictEqual(planStartSeatY(leave), 0);
  // reduced-chase glides seatY to 0 over the transition, so the descent must not be clamped away
  const reducedLeave = planFocus(
    { lastTab: 4, lastX: tabX(4), lastSeat: RAISED_SEAT },
    {
      tab: 0,
      screenWidth: WIDTH,
      bottomExtra: 0,
      transientSlot: false,
      reduceMotion: true,
      slotCount: SLOT_COUNT,
    }
  );
  strictEqual(reducedLeave.kind, 'reduced-chase');
  strictEqual(reducedLeave.fromSeatY, -RAISED_SEAT);
  strictEqual(
    planStartSeatY(reducedLeave),
    -RAISED_SEAT,
    'RM descent glide starts at raised-seat height'
  );
  const reducedClimb = planFocus(
    { lastTab: 0, lastX: tabX(0), lastSeat: 0 },
    {
      tab: 4,
      screenWidth: WIDTH,
      bottomExtra: RAISED_SEAT,
      transientSlot: false,
      reduceMotion: true,
      slotCount: SLOT_COUNT,
    }
  );
  strictEqual(planStartSeatY(reducedClimb), RAISED_SEAT, 'RM climb glide starts at bar height');
}

function testPlanMountSeatYSeedsFirstFrame(): void {
  const fromHome = { lastTab: 0, lastX: tabX(0), lastSeat: 0 };
  const raisedSeatArgs = {
    tab: 4,
    screenWidth: WIDTH,
    bottomExtra: RAISED_SEAT,
    transientSlot: false,
    reduceMotion: false,
    slotCount: SLOT_COUNT,
  };
  const climb = planFocus(fromHome, raisedSeatArgs);
  strictEqual(climb.kind, 'run-chase');
  strictEqual(
    planMountSeatY(fromHome, raisedSeatArgs),
    RAISED_SEAT,
    'raised-seat mount first frame is bar height, not the seat itself (0)'
  );
  strictEqual(
    planMountSeatY(fromHome, raisedSeatArgs),
    planStartSeatY(climb),
    'mount seed equals the focus snap - not a second altitude rule'
  );
  strictEqual(
    planMountSeatY(fromHome, { ...raisedSeatArgs, reduceMotion: true }),
    RAISED_SEAT,
    'RM climb mount still starts at bar (fromSeatY), not 0'
  );
  const fromRaisedSeat = { lastTab: 4, lastX: tabX(4), lastSeat: RAISED_SEAT };
  const homeArgs = {
    tab: 0,
    screenWidth: WIDTH,
    bottomExtra: 0,
    transientSlot: false,
    reduceMotion: false,
    slotCount: SLOT_COUNT,
  };
  strictEqual(
    planMountSeatY(fromRaisedSeat, homeArgs),
    0,
    'leave-raised-seat run-chase mount is already at bar'
  );
  strictEqual(
    planMountSeatY(fromRaisedSeat, { ...homeArgs, reduceMotion: true }),
    -RAISED_SEAT,
    'RM descent mount keeps fromSeatY so the glide is not a no-op'
  );
  strictEqual(
    planMountSeatY(fromHome, { ...raisedSeatArgs, transientSlot: true }),
    0,
    'transient mount stays at its own seat (no cross-tab first frame)'
  );
}

function testBlurFreezesLiveSeatNotDestination(): void {
  const start = { lastTab: 4, lastX: null, lastSeat: RAISED_SEAT };
  const midRise = liveLastSeat(RAISED_SEAT, 12);
  strictEqual(midRise, 12, 'seatY 12pt down from the raised seat is lastSeat 12');
  const stillAtBar = liveLastSeat(RAISED_SEAT, RAISED_SEAT);
  strictEqual(stillAtBar, 0, 'still at bar during a run toward the raised seat');
  const next = applyFocusBlur(start, {
    currentX: tabX(0) + 90,
    currentSeat: stillAtBar,
    transientSlot: false,
  });
  strictEqual(next.lastSeat, 0, 'bounce-back must not keep the destination raised seat');
  strictEqual(next.lastX, tabX(0) + 90);
}

function testSnapToSeatWhenHandoffIsUnderOneGlass(): void {
  const start = { lastTab: 1, lastX: tabX(2) - 10, lastSeat: 0 };
  const plan = planFocus(start, {
    tab: 2,
    screenWidth: WIDTH,
    bottomExtra: 0,
    transientSlot: false,
    reduceMotion: false,
    slotCount: SLOT_COUNT,
  });
  strictEqual(plan.kind, 'snap-to-seat');
  strictEqual(plan.fromX, plan.targetX);
}

function testHoldRunSkipsSnapToSeat(): void {
  const start = { lastTab: 1, lastX: tabX(2) - 30, lastSeat: 0 };
  const args = {
    tab: 2,
    screenWidth: WIDTH,
    bottomExtra: 0,
    transientSlot: false,
    reduceMotion: false,
    slotCount: SLOT_COUNT,
  };
  const defaultPlan = planFocus(start, args);
  strictEqual(defaultPlan.kind, 'snap-to-seat', 'default: under one glass still snaps');
  const heldPlan = planFocus(start, { ...args, holdRun: true });
  strictEqual(heldPlan.kind, 'run-chase', 'holdRun: a route interrupt gets a real run instead');
  strictEqual(heldPlan.fromX, start.lastX, 'holdRun keeps the live fromX, not targetX');
  strictEqual(heldPlan.runSeatY, 0, 'holdRun run starts at bar level');
}

function testHoldRunTreatsSameTabAsRunChase(): void {
  const start = { lastTab: 4, lastX: tabX(4) - 30, lastSeat: 0 };
  const args = {
    tab: 4,
    screenWidth: WIDTH,
    bottomExtra: 0,
    transientSlot: false,
    reduceMotion: false,
    slotCount: SLOT_COUNT,
  };
  const defaultPlan = planFocus(start, args);
  strictEqual(defaultPlan.kind, 'same-tab-snap', 'default: a re-tap of the current tab snaps');
  const heldPlan = planFocus(start, { ...args, holdRun: true });
  strictEqual(
    heldPlan.kind,
    'run-chase',
    'holdRun: a same-tab re-tap mid-route gets a run back to it too'
  );
  strictEqual(heldPlan.fromX, start.lastX, 'holdRun keeps the live fromX for the same-tab case');
  strictEqual(heldPlan.targetX, tabX(4));
  strictEqual(heldPlan.runSeatY, 0);
}

function testReduceMotionIsReducedChase(): void {
  const start = { lastTab: 0, lastX: null, lastSeat: 0 };
  const plan = planFocus(start, {
    tab: 4,
    screenWidth: WIDTH,
    bottomExtra: 0,
    transientSlot: false,
    reduceMotion: true,
    slotCount: SLOT_COUNT,
  });
  strictEqual(plan.kind, 'reduced-chase');
}

function testBlurWritesActualXNotDestination(): void {
  const start = { lastTab: 4, lastX: null, lastSeat: 0 };
  const mid = tabX(0) + 90;
  const next = applyFocusBlur(start, { currentX: mid, transientSlot: false });
  strictEqual(next.lastX, mid, 'mid-traverse blur hands off where the pup is');
  strictEqual(next.lastTab, 4, 'blur does not rewrite lastTab - focus already did');
}

function testDragTrackWritesGlassAndBarLevel(): void {
  const start = { lastTab: 2, lastX: tabX(2), lastSeat: RAISED_SEAT };
  const next = applyDragTrack(start, 200);
  deepStrictEqual(next, { lastTab: 2, lastX: 200, lastSeat: 0 });
}

function testDragReleaseWritesOnlyWhenThisTabOwnsHandoff(): void {
  const owned = { lastTab: 2, lastX: 200, lastSeat: 0 };
  deepStrictEqual(applyDragRelease(owned, { tab: 2, releaseX: 210, bottomExtra: RAISED_SEAT }), {
    lastTab: 2,
    lastX: 210,
    lastSeat: RAISED_SEAT,
  });
  const stolen = { lastTab: 4, lastX: tabX(4), lastSeat: 0 };
  deepStrictEqual(
    applyDragRelease(stolen, { tab: 2, releaseX: 210, bottomExtra: RAISED_SEAT }),
    stolen,
    'ended after another tab consumed lastTab must not stomp'
  );
}

// literal expected values - never derived from planDragRelease's own condition
function testPlanDragReleaseTable(): void {
  const currentSlot = 2;
  const table: {
    phase: 'ended' | 'cancelled';
    releaseSlot: number;
    selectsOnRelease: boolean;
    expected: DragReleasePlan;
  }[] = [
    {
      phase: 'ended',
      releaseSlot: 3,
      selectsOnRelease: true,
      expected: { kind: 'await', slot: 3 },
    },
    { phase: 'ended', releaseSlot: 3, selectsOnRelease: false, expected: { kind: 'home' } },
    { phase: 'ended', releaseSlot: 2, selectsOnRelease: true, expected: { kind: 'home' } },
    { phase: 'ended', releaseSlot: 2, selectsOnRelease: false, expected: { kind: 'home' } },
    { phase: 'cancelled', releaseSlot: 3, selectsOnRelease: true, expected: { kind: 'home' } },
    { phase: 'cancelled', releaseSlot: 3, selectsOnRelease: false, expected: { kind: 'home' } },
    { phase: 'cancelled', releaseSlot: 2, selectsOnRelease: true, expected: { kind: 'home' } },
    { phase: 'cancelled', releaseSlot: 2, selectsOnRelease: false, expected: { kind: 'home' } },
  ];
  for (const row of table) {
    const label = `phase=${row.phase} releaseSlot=${row.releaseSlot} selectsOnRelease=${row.selectsOnRelease}`;
    deepStrictEqual(
      planDragRelease({
        phase: row.phase,
        releaseSlot: row.releaseSlot,
        currentSlot,
        selectsOnRelease: row.selectsOnRelease,
      }),
      row.expected,
      label
    );
  }
}

// literal expected values - never derived from selectsOnRelease's own expression
function testSelectsOnReleaseAllCombinations(): void {
  const table: {
    barScrub: 'native' | 'exclusive';
    hasOnDragRelease: boolean;
    nativePill: boolean;
    expected: boolean;
  }[] = [
    { barScrub: 'native', hasOnDragRelease: false, nativePill: false, expected: false },
    { barScrub: 'native', hasOnDragRelease: false, nativePill: true, expected: true },
    { barScrub: 'native', hasOnDragRelease: true, nativePill: false, expected: false },
    { barScrub: 'native', hasOnDragRelease: true, nativePill: true, expected: true },
    { barScrub: 'exclusive', hasOnDragRelease: false, nativePill: false, expected: false },
    { barScrub: 'exclusive', hasOnDragRelease: false, nativePill: true, expected: false },
    { barScrub: 'exclusive', hasOnDragRelease: true, nativePill: false, expected: true },
    { barScrub: 'exclusive', hasOnDragRelease: true, nativePill: true, expected: true },
  ];
  for (const row of table) {
    const label = `barScrub=${row.barScrub} hasOnDragRelease=${row.hasOnDragRelease} nativePill=${row.nativePill}`;
    strictEqual(
      selectsOnRelease({
        barScrub: row.barScrub,
        hasOnDragRelease: row.hasOnDragRelease,
        nativePill: row.nativePill,
      }),
      row.expected,
      label
    );
  }
}

function testPlanApproach(): void {
  strictEqual(planApproach(53.9).kind, 'spring', 'under one glass width is a spring');
  const at54 = planApproach(54);
  const atNeg54 = planApproach(-54);
  strictEqual(at54.kind, 'run', 'exactly one glass width is a run');
  strictEqual(atNeg54.kind, 'run', 'negative distance is not under the threshold either');
  if (at54.kind !== 'run' || atNeg54.kind !== 'run') {
    throw new Error('expected run plans');
  }
  strictEqual(
    atNeg54.durationMs,
    at54.durationMs,
    'a negative distance behaves like its magnitude'
  );
  // 54 / 340 * 1000 = 158.82ms raw, below the 400ms floor at the default speed
  strictEqual(at54.durationMs, 400, 'a short run is clamped to the floor');
  const midRun = planApproach(600);
  if (midRun.kind !== 'run') {
    throw new Error('expected a run plan');
  }
  // 600 / 340 * 1000, between the floor and ceiling so the raw linear rate applies
  strictEqual(midRun.durationMs, 1764.7058823529412, 'a mid-distance run uses the raw rate');
  const capped = planApproach(100_000);
  if (capped.kind !== 'run') {
    throw new Error('expected a run plan');
  }
  // 100_000 / 340 * 1000 = 294117.6ms raw, above the 2200ms ceiling at the default speed
  strictEqual(capped.durationMs, 2200, 'an extreme distance is clamped to the ceiling');
  const stretched = planApproach(200, 100);
  if (stretched.kind !== 'run') {
    throw new Error('expected a run plan');
  }
  // speed 100 stretches floor/ceiling by 340/100 = 3.4x (1360ms/7480ms); the
  // raw rate 200 / 100 * 1000 = 2000ms falls between them, so it applies unclamped
  strictEqual(stretched.durationMs, 2000, 'a speed override stretches the floor and ceiling');
}

function testFocusFromSlot(): void {
  strictEqual(focusFromSlot(0, true, 3), 3, 'arrived by drag: the focused slot wins as fromSlot');
  strictEqual(focusFromSlot(0, false, 3), 0, 'not arrived: falls back to handoffLastTab');
}

function testReplayFromPlanDragReleaseAwaitSnapsWhenCloseAtBlur(): void {
  const plan = planDragRelease({
    phase: 'ended',
    releaseSlot: 3,
    currentSlot: 1,
    selectsOnRelease: true,
  });
  strictEqual(plan.kind, 'await');
  if (plan.kind !== 'await') {
    throw new Error('expected an await plan');
  }
  const afterRelease = applyDragRelease(
    { lastTab: 1, lastX: tabX(1), lastSeat: 0 },
    { tab: 1, releaseX: tabX(plan.slot) - 5, bottomExtra: 0 }
  );
  const liveXNearB = tabX(plan.slot) - 10; // within one glass width of the awaited slot's seat
  const afterBlur = applyFocusBlur(afterRelease, { currentX: liveXNearB, transientSlot: false });
  const focusPlan = planFocus(afterBlur, {
    tab: plan.slot,
    screenWidth: WIDTH,
    bottomExtra: 0,
    transientSlot: false,
    reduceMotion: false,
    slotCount: SLOT_COUNT,
  });
  strictEqual(
    focusPlan.kind,
    'snap-to-seat',
    'a live x within one glass width of the awaited slot snaps to seat'
  );
}

function testReplayFromPlanDragReleaseGoesHomeWhenNothingSelects(): void {
  const plan = planDragRelease({
    phase: 'ended',
    releaseSlot: 3,
    currentSlot: 1,
    selectsOnRelease: false,
  });
  strictEqual(plan.kind, 'home', 'nothing will select the slot - a chase home, not a wait');
}

function testReplayReleaseAwaitRunsWhenFarAtBlur(): void {
  const releaseX = tabX(3) - 120;
  const afterRelease = applyDragRelease(
    { lastTab: 1, lastX: tabX(1), lastSeat: 0 },
    { tab: 1, releaseX, bottomExtra: 0 }
  );
  const liveXFar = tabX(3) - 60; // approach closed some distance, still over one glass width out
  ok(
    Math.abs(liveXFar - tabX(3)) < Math.abs(releaseX - tabX(3)),
    "live x is on B's side of the release point"
  );
  const afterBlur = applyFocusBlur(afterRelease, { currentX: liveXFar, transientSlot: false });
  const plan = planFocus(afterBlur, {
    tab: 3,
    screenWidth: WIDTH,
    bottomExtra: 0,
    transientSlot: false,
    reduceMotion: false,
    slotCount: SLOT_COUNT,
  });
  strictEqual(plan.kind, 'run-chase');
  strictEqual(
    plan.fromX,
    liveXFar,
    'run-chase starts from the live x at blur, not the release point'
  );
}

function testReplayDragReleaseWriteIsOverwrittenByBlur(): void {
  const afterRelease = applyDragRelease(
    { lastTab: 1, lastX: tabX(1), lastSeat: 0 },
    { tab: 1, releaseX: tabX(3) - 5, bottomExtra: 0 }
  );
  strictEqual(afterRelease.lastX, tabX(3) - 5);
  const liveX = tabX(1) + 30; // wherever he actually is by the time the blur runs
  const afterBlur = applyFocusBlur(afterRelease, { currentX: liveX, transientSlot: false });
  strictEqual(
    afterBlur.lastX,
    liveX,
    'applyFocusBlur always overwrites the release write - nothing may rely on it surviving'
  );
}

function testSingletonReset(): void {
  resetPerchHandoffForTest();
  deepStrictEqual(readPerchHandoff(), initialPerchHandoff());
  writePerchHandoff({ lastTab: 3, lastX: 99, lastSeat: 8 });
  deepStrictEqual(readPerchHandoff(), { lastTab: 3, lastX: 99, lastSeat: 8 });
  resetPerchHandoffForTest();
  deepStrictEqual(readPerchHandoff(), initialPerchHandoff());
}

// a: release(await) -> focus-cleanup -> focus-body: await, clear-timer, arrived
function testReduceReleaseSequenceA(): void {
  let state = initialReleaseState();
  let step = reduceRelease(state, {
    type: 'release',
    plan: { kind: 'await', slot: 3 },
    fromSlot: 1,
    generation: 1,
  });
  ({ state } = step);
  strictEqual(step.effect, 'await');
  deepStrictEqual(state, { pending: { fromSlot: 1, slot: 3, generation: 1 }, arrival: false });
  step = reduceRelease(state, { type: 'focus-cleanup' });
  ({ state } = step);
  strictEqual(step.effect, 'clear-timer');
  deepStrictEqual(state, { pending: null, arrival: true });
  step = reduceRelease(state, { type: 'focus-body', transientSlot: false });
  ({ state } = step);
  strictEqual(step.effect, 'arrived');
  deepStrictEqual(state, { pending: null, arrival: false });
}

// b: release(await) -> timer, slot unchanged: go-home; a second timer is none
function testReduceReleaseSequenceB(): void {
  let state = initialReleaseState();
  let step = reduceRelease(state, {
    type: 'release',
    plan: { kind: 'await', slot: 3 },
    fromSlot: 1,
    generation: 1,
  });
  ({ state } = step);
  strictEqual(step.effect, 'await');
  deepStrictEqual(state, { pending: { fromSlot: 1, slot: 3, generation: 1 }, arrival: false });
  step = reduceRelease(state, { type: 'timer', mounted: true, generation: 1, renderedSlot: 1 });
  ({ state } = step);
  strictEqual(step.effect, 'go-home');
  deepStrictEqual(state, { pending: null, arrival: false });
  step = reduceRelease(state, { type: 'timer', mounted: true, generation: 1, renderedSlot: 1 });
  strictEqual(step.effect, 'none', 'a second timer event has nothing left pending');
  deepStrictEqual(step.state, { pending: null, arrival: false });
}

// c: release(await) -> timer with renderedSlot different: none, pending KEPT for the
// focus-cleanup that is about to run -> focus-cleanup: clear-timer, arrival true, pending null
// -> focus-body: arrived
function testReduceReleaseSequenceC(): void {
  let state = initialReleaseState();
  let step = reduceRelease(state, {
    type: 'release',
    plan: { kind: 'await', slot: 3 },
    fromSlot: 1,
    generation: 1,
  });
  ({ state } = step);
  strictEqual(step.effect, 'await');
  deepStrictEqual(state, { pending: { fromSlot: 1, slot: 3, generation: 1 }, arrival: false });
  step = reduceRelease(state, {
    type: 'timer',
    mounted: true,
    generation: 1,
    renderedSlot: 4,
  });
  ({ state } = step);
  strictEqual(step.effect, 'none');
  deepStrictEqual(
    state,
    { pending: { fromSlot: 1, slot: 3, generation: 1 }, arrival: false },
    'the selection committed but focus has not run yet - pending survives for focus-cleanup'
  );
  step = reduceRelease(state, { type: 'focus-cleanup' });
  ({ state } = step);
  strictEqual(step.effect, 'clear-timer');
  deepStrictEqual(state, { pending: null, arrival: true });
  step = reduceRelease(state, { type: 'focus-body', transientSlot: false });
  strictEqual(step.effect, 'arrived');
  deepStrictEqual(step.state, { pending: null, arrival: false });
}

// d: release(await) -> timer with a generation that differs from pending.generation: none,
// pending cleared
function testReduceReleaseSequenceD(): void {
  let state = initialReleaseState();
  let step = reduceRelease(state, {
    type: 'release',
    plan: { kind: 'await', slot: 3 },
    fromSlot: 1,
    generation: 1,
  });
  ({ state } = step);
  strictEqual(step.effect, 'await');
  deepStrictEqual(state, { pending: { fromSlot: 1, slot: 3, generation: 1 }, arrival: false });
  step = reduceRelease(state, {
    type: 'timer',
    mounted: true,
    generation: 2,
    renderedSlot: 1,
  });
  strictEqual(step.effect, 'none');
  deepStrictEqual(step.state, { pending: null, arrival: false });
}

// e: release(await) -> timer while unmounted: none, pending cleared
function testReduceReleaseSequenceE(): void {
  let state = initialReleaseState();
  let step = reduceRelease(state, {
    type: 'release',
    plan: { kind: 'await', slot: 3 },
    fromSlot: 1,
    generation: 1,
  });
  ({ state } = step);
  strictEqual(step.effect, 'await');
  deepStrictEqual(state, { pending: { fromSlot: 1, slot: 3, generation: 1 }, arrival: false });
  step = reduceRelease(state, {
    type: 'timer',
    mounted: false,
    generation: 1,
    renderedSlot: 1,
  });
  strictEqual(step.effect, 'none');
  deepStrictEqual(step.state, { pending: null, arrival: false });
}

// f: release(await) -> began -> (a tap, no engage) -> timer: hold-generation, then go-home
function testReduceReleaseSequenceF(): void {
  let state = initialReleaseState();
  let step = reduceRelease(state, {
    type: 'release',
    plan: { kind: 'await', slot: 3 },
    fromSlot: 1,
    generation: 1,
  });
  ({ state } = step);
  strictEqual(step.effect, 'await');
  deepStrictEqual(state, { pending: { fromSlot: 1, slot: 3, generation: 1 }, arrival: false });
  step = reduceRelease(state, { type: 'began' });
  ({ state } = step);
  strictEqual(step.effect, 'hold-generation');
  deepStrictEqual(
    state,
    { pending: { fromSlot: 1, slot: 3, generation: 1 }, arrival: false },
    'a tap must not touch the pending release'
  );
  // no 'engage' event - the touch never travelled past DRAG_ENGAGE_PT
  step = reduceRelease(state, { type: 'timer', mounted: true, generation: 1, renderedSlot: 1 });
  strictEqual(step.effect, 'go-home', 'the timer still fires after a tap that never engaged');
  deepStrictEqual(step.state, { pending: null, arrival: false });
}

// g: release(await) -> began -> engage: hold-generation, then clear-timer; a later timer is none
function testReduceReleaseSequenceG(): void {
  let state = initialReleaseState();
  let step = reduceRelease(state, {
    type: 'release',
    plan: { kind: 'await', slot: 3 },
    fromSlot: 1,
    generation: 1,
  });
  ({ state } = step);
  strictEqual(step.effect, 'await');
  deepStrictEqual(state, { pending: { fromSlot: 1, slot: 3, generation: 1 }, arrival: false });
  step = reduceRelease(state, { type: 'began' });
  ({ state } = step);
  strictEqual(step.effect, 'hold-generation');
  deepStrictEqual(state, { pending: { fromSlot: 1, slot: 3, generation: 1 }, arrival: false });
  step = reduceRelease(state, { type: 'engage' });
  ({ state } = step);
  strictEqual(step.effect, 'clear-timer');
  deepStrictEqual(state, { pending: null, arrival: false });
  step = reduceRelease(state, { type: 'timer', mounted: true, generation: 1, renderedSlot: 1 });
  strictEqual(step.effect, 'none');
  deepStrictEqual(step.state, { pending: null, arrival: false });
}

// h: release(await) -> focus-cleanup -> focus-body(transientSlot): not arrived, arrival cleared
function testReduceReleaseSequenceH(): void {
  let state = initialReleaseState();
  let step = reduceRelease(state, {
    type: 'release',
    plan: { kind: 'await', slot: 3 },
    fromSlot: 1,
    generation: 1,
  });
  ({ state } = step);
  strictEqual(step.effect, 'await');
  deepStrictEqual(state, { pending: { fromSlot: 1, slot: 3, generation: 1 }, arrival: false });
  step = reduceRelease(state, { type: 'focus-cleanup' });
  ({ state } = step);
  strictEqual(step.effect, 'clear-timer');
  deepStrictEqual(state, { pending: null, arrival: true });
  step = reduceRelease(state, { type: 'focus-body', transientSlot: true });
  strictEqual(step.effect, 'none');
  deepStrictEqual(step.state, { pending: null, arrival: false });
}

// i: release(home): go-home, nothing pending; a later focus-body is not an arrival
function testReduceReleaseSequenceI(): void {
  let state = initialReleaseState();
  let step = reduceRelease(state, {
    type: 'release',
    plan: { kind: 'home' },
    fromSlot: 1,
    generation: 1,
  });
  ({ state } = step);
  strictEqual(step.effect, 'go-home');
  deepStrictEqual(state, { pending: null, arrival: false });
  step = reduceRelease(state, { type: 'focus-body', transientSlot: false });
  strictEqual(step.effect, 'none');
  deepStrictEqual(step.state, { pending: null, arrival: false });
}

// j: focus-cleanup with nothing pending -> focus-body: not an arrival
function testReduceReleaseSequenceJ(): void {
  let state = initialReleaseState();
  let step = reduceRelease(state, { type: 'focus-cleanup' });
  ({ state } = step);
  strictEqual(step.effect, 'none');
  deepStrictEqual(state, { pending: null, arrival: false });
  step = reduceRelease(state, { type: 'focus-body', transientSlot: false });
  strictEqual(step.effect, 'none');
  deepStrictEqual(step.state, { pending: null, arrival: false });
}

// k: release(await) -> focus-cleanup -> focus-body -> focus-body: arrived exactly once
function testReduceReleaseSequenceK(): void {
  let state = initialReleaseState();
  let step = reduceRelease(state, {
    type: 'release',
    plan: { kind: 'await', slot: 3 },
    fromSlot: 1,
    generation: 1,
  });
  ({ state } = step);
  strictEqual(step.effect, 'await');
  deepStrictEqual(state, { pending: { fromSlot: 1, slot: 3, generation: 1 }, arrival: false });
  step = reduceRelease(state, { type: 'focus-cleanup' });
  ({ state } = step);
  strictEqual(step.effect, 'clear-timer');
  deepStrictEqual(state, { pending: null, arrival: true });
  step = reduceRelease(state, { type: 'focus-body', transientSlot: false });
  ({ state } = step);
  strictEqual(step.effect, 'arrived');
  deepStrictEqual(state, { pending: null, arrival: false });
  step = reduceRelease(state, { type: 'focus-body', transientSlot: false });
  strictEqual(step.effect, 'none', 'arrived only once');
  deepStrictEqual(step.state, { pending: null, arrival: false });
}

// l: release(await) -> unmount -> timer: clear-timer, then none
function testReduceReleaseSequenceL(): void {
  let state = initialReleaseState();
  let step = reduceRelease(state, {
    type: 'release',
    plan: { kind: 'await', slot: 3 },
    fromSlot: 1,
    generation: 1,
  });
  ({ state } = step);
  strictEqual(step.effect, 'await');
  deepStrictEqual(state, { pending: { fromSlot: 1, slot: 3, generation: 1 }, arrival: false });
  step = reduceRelease(state, { type: 'unmount' });
  ({ state } = step);
  strictEqual(step.effect, 'clear-timer');
  deepStrictEqual(state, { pending: null, arrival: false });
  step = reduceRelease(state, { type: 'timer', mounted: true, generation: 1, renderedSlot: 1 });
  strictEqual(step.effect, 'none');
  deepStrictEqual(step.state, { pending: null, arrival: false });
}

// m: release(await) -> abort: clear-timer, pending null; a later timer is none; a later
// focus-cleanup then focus-body is not an arrival
function testReduceReleaseSequenceM(): void {
  let state = initialReleaseState();
  let step = reduceRelease(state, {
    type: 'release',
    plan: { kind: 'await', slot: 3 },
    fromSlot: 1,
    generation: 1,
  });
  ({ state } = step);
  strictEqual(step.effect, 'await');
  deepStrictEqual(state, { pending: { fromSlot: 1, slot: 3, generation: 1 }, arrival: false });
  step = reduceRelease(state, { type: 'abort' });
  ({ state } = step);
  strictEqual(step.effect, 'clear-timer');
  deepStrictEqual(state, { pending: null, arrival: false });
  step = reduceRelease(state, { type: 'timer', mounted: true, generation: 1, renderedSlot: 1 });
  ({ state } = step);
  strictEqual(step.effect, 'none');
  deepStrictEqual(state, { pending: null, arrival: false });
  step = reduceRelease(state, { type: 'focus-cleanup' });
  ({ state } = step);
  strictEqual(step.effect, 'none');
  deepStrictEqual(state, { pending: null, arrival: false });
  step = reduceRelease(state, { type: 'focus-body', transientSlot: false });
  strictEqual(step.effect, 'none', 'not an arrival - abort cleared pending before it could');
  deepStrictEqual(step.state, { pending: null, arrival: false });
}

// n: abort with nothing pending: none
function testReduceReleaseSequenceN(): void {
  const state = initialReleaseState();
  const step = reduceRelease(state, { type: 'abort' });
  strictEqual(step.effect, 'none');
  deepStrictEqual(step.state, { pending: null, arrival: false });
}

// o: release(await) -> focus-cleanup sets arrival -> unmount: arrival cleared alongside
// pending, effect none - unmount must not leave arrival set for the next mount to see
function testReduceReleaseSequenceO(): void {
  let state = initialReleaseState();
  let step = reduceRelease(state, {
    type: 'release',
    plan: { kind: 'await', slot: 3 },
    fromSlot: 1,
    generation: 1,
  });
  ({ state } = step);
  strictEqual(step.effect, 'await');
  step = reduceRelease(state, { type: 'focus-cleanup' });
  ({ state } = step);
  strictEqual(step.effect, 'clear-timer');
  deepStrictEqual(state, { pending: null, arrival: true });
  step = reduceRelease(state, { type: 'unmount' });
  strictEqual(step.effect, 'none', 'nothing pending left to clear a timer for');
  deepStrictEqual(step.state, { pending: null, arrival: false }, 'unmount clears arrival too');
}

function main(): void {
  testInitialHandoff();
  testTransientNeverWritesHandoff();
  testSameTabSnapClearsLastX();
  testCrossTabChaseUsesLastXThenClears();
  testCrossTabFallsBackToLastTabCenter();
  testAltitudeGlideUsesLastSeat();
  testArriveAtRaisedSeatHoldsBarUntilCatch();
  testPlanRunSeatYDirectional();
  testPlanStartSeatY();
  testPlanMountSeatYSeedsFirstFrame();
  testBlurFreezesLiveSeatNotDestination();
  testSnapToSeatWhenHandoffIsUnderOneGlass();
  testHoldRunSkipsSnapToSeat();
  testHoldRunTreatsSameTabAsRunChase();
  testReduceMotionIsReducedChase();
  testBlurWritesActualXNotDestination();
  testDragTrackWritesGlassAndBarLevel();
  testDragReleaseWritesOnlyWhenThisTabOwnsHandoff();
  testPlanDragReleaseTable();
  testSelectsOnReleaseAllCombinations();
  testPlanApproach();
  testFocusFromSlot();
  testReplayFromPlanDragReleaseAwaitSnapsWhenCloseAtBlur();
  testReplayFromPlanDragReleaseGoesHomeWhenNothingSelects();
  testReplayReleaseAwaitRunsWhenFarAtBlur();
  testReplayDragReleaseWriteIsOverwrittenByBlur();
  testSingletonReset();
  testReduceReleaseSequenceA();
  testReduceReleaseSequenceB();
  testReduceReleaseSequenceC();
  testReduceReleaseSequenceD();
  testReduceReleaseSequenceE();
  testReduceReleaseSequenceF();
  testReduceReleaseSequenceG();
  testReduceReleaseSequenceH();
  testReduceReleaseSequenceI();
  testReduceReleaseSequenceJ();
  testReduceReleaseSequenceK();
  testReduceReleaseSequenceL();
  testReduceReleaseSequenceM();
  testReduceReleaseSequenceN();
  testReduceReleaseSequenceO();
  // oxlint-disable-next-line no-console -- test runner reporting
  console.log('42 passed (perch-handoff)');
}

main();
