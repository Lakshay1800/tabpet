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
  FAR_GRAB_PT,
  focusFromSlot,
  initialPerchHandoff,
  initialReleaseState,
  isFarGrab,
  liveLastSeat,
  planApproach,
  planDragRelease,
  planFarSample,
  planFocus,
  planMountSeatY,
  planRunSeatY,
  planStartSeatY,
  readPerchHandoff,
  reduceRelease,
  resetPerchHandoffForTest,
  sanitizeRunSpeed,
  selectsOnRelease,
  stepToward,
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

// literal expected values - never derived from isFarGrab's own expression
function testIsFarGrab(): void {
  strictEqual(FAR_GRAB_PT, 54, 'fixture assumes FAR_GRAB_PT === PERCH_SIZE');
  strictEqual(isFarGrab(54), false, 'exactly the threshold is not far (strict greater-than)');
  strictEqual(isFarGrab(54.1), true);
  strictEqual(isFarGrab(-54.1), true);
  strictEqual(isFarGrab(0), false);
}

// literal expected values - never derived from sanitizeRunSpeed's own expression
function testSanitizeRunSpeed(): void {
  strictEqual(sanitizeRunSpeed(340), 340);
  strictEqual(sanitizeRunSpeed(200), 200);
  strictEqual(sanitizeRunSpeed(5000), 5000);
  for (const bad of [
    0,
    -5,
    Number.NaN,
    Number.POSITIVE_INFINITY,
    Number.NEGATIVE_INFINITY,
    undefined,
  ]) {
    strictEqual(sanitizeRunSpeed(bad), 340, `${bad} must fall back to TRAVERSE_SPEED_PT_S`);
  }
}

// literal expected values - never derived from stepToward's own expression
function testStepToward(): void {
  const speed = 340;
  const stepPt = 5.44; // 340 * 16 / 1000
  const base = stepToward(0, 300, speed, 16);
  ok(Math.abs(base.x - stepPt) < 1e-9, `dt 16 must step ${stepPt}, got ${base.x}`);
  strictEqual(base.arrived, false);

  const dtZero = stepToward(0, 300, speed, 0);
  strictEqual(dtZero.x, 0, 'dt 0 makes no step');
  strictEqual(dtZero.arrived, false);

  const dtOverLong = stepToward(0, 300, speed, 1000);
  ok(
    Math.abs(dtOverLong.x - 11.56) < 1e-9,
    'dt above FAR_STEP_MAX_DT_MS clamps to 34ms (11.56pt), not the raw 1000ms'
  );
  strictEqual(dtOverLong.arrived, false);

  const leftward = stepToward(100, 50, speed, 16);
  ok(
    Math.abs(leftward.x - (100 - stepPt)) < 1e-9,
    'a target on the left moves him left by the same step'
  );
  strictEqual(leftward.arrived, false);

  const closeIn = stepToward(298, 300, speed, 16);
  strictEqual(closeIn.x, 300, 'a step past the target lands exactly on it');
  strictEqual(closeIn.arrived, true);

  const already = stepToward(50, 50, speed, 16);
  strictEqual(already.x, 50, 'current equal to target: x unchanged');
  strictEqual(already.arrived, true);

  // speed 0 at current === target: the speedPtS <= 0 guard returns not-arrived
  // before the arithmetic ever sees the zero distance - a mutation to < 0
  // would let speed 0 fall through and report arrived true instead
  const zeroSpeedAtTarget = stepToward(50, 50, 0, 16);
  strictEqual(zeroSpeedAtTarget.x, 50);
  strictEqual(zeroSpeedAtTarget.arrived, false, 'the guard, not the arithmetic, decides');

  const nanTarget = stepToward(10, Number.NaN, speed, 16);
  strictEqual(nanTarget.x, 10);
  strictEqual(nanTarget.arrived, false);
  const nanSpeed = stepToward(10, 300, Number.NaN, 16);
  strictEqual(nanSpeed.x, 10);
  strictEqual(nanSpeed.arrived, false);
  const nanDt = stepToward(10, 300, speed, Number.NaN);
  strictEqual(nanDt.x, 10);
  strictEqual(nanDt.arrived, false);
}

// A FIXED 300pt target at 340pt/s in 16ms steps: every step but the last
// moves the raw 5.44pt/step; the last step clamps to the target exactly,
// never past it. Steps counted by hand: 300 / 5.44 = 55.14..., so 55 full
// steps (299.2pt) plus one clamped step to 300.
function testStepTowardFixedTargetStepCount(): void {
  const speed = 340;
  let x = 0;
  let steps = 0;
  let arrived = false;
  while (!arrived && steps < 200) {
    const { x: nextX, arrived: isArrived } = stepToward(x, 300, speed, 16);
    if (steps < 55) {
      ok(
        Math.abs(nextX - (x + 5.44)) < 1e-9,
        `step ${steps} must move the raw 5.44pt, got ${nextX - x}`
      );
    }
    x = nextX;
    arrived = isArrived;
    steps += 1;
  }
  strictEqual(steps, 56, 'closing 300pt at 5.44pt/step arrives on the 56th step');
  strictEqual(x, 300, 'the last step lands exactly on the target, never past it');
}

// A MOVING target that recedes at 100pt/s: stepToward only sees the live
// gap each call, so x still steps the raw 5.44pt/step (50 steps = 272pt);
// the gap itself only closes by 5.44 - 1.6 = 3.84pt per step, so he has not
// caught the ever-receding target.
function testStepTowardRecedingTarget(): void {
  const speed = 340;
  let x = 0;
  let target = 300;
  let arrived = false;
  for (let i = 0; i < 50; i += 1) {
    target += 1.6; // recedes at 100pt/s over this 16ms step
    const { x: nextX, arrived: isArrived } = stepToward(x, target, speed, 16);
    x = nextX;
    arrived = isArrived;
  }
  ok(Math.abs(x - 272) < 1e-9, `x after 50 receding steps must be 272, got ${x}`);
  ok(!arrived, 'a target receding faster than he closes on it is never reached');
}

// A MOVING target that approaches him still steps the raw 5.44pt/step -
// stepToward only knows the live gap, not the target's own velocity.
function testStepTowardApproachingTarget(): void {
  const speed = 340;
  let x = 0;
  let target = 300;
  for (let i = 0; i < 3; i += 1) {
    target -= 1.6; // approaches at 100pt/s over this 16ms step
    const { x: nextX } = stepToward(x, target, speed, 16);
    ok(
      Math.abs(nextX - (x + 5.44)) < 1e-9,
      `step ${i} toward an approaching target must still move 5.44pt`
    );
    x = nextX;
  }
}

// A target that jumps to the other side of him mid-approach reverses -
// same 5.44pt/step magnitude, opposite direction.
function testStepTowardTargetJumpsSides(): void {
  const speed = 340;
  let x = 0;
  ({ x } = stepToward(x, 300, speed, 16));
  ({ x } = stepToward(x, 300, speed, 16));
  ok(Math.abs(x - 10.88) < 1e-9, 'two steps toward 300 land at 10.88');
  const jumpedTarget = x - 300; // now well to the left of x
  const reversed = stepToward(x, jumpedTarget, speed, 16);
  ok(
    Math.abs(reversed.x - (x - 5.44)) < 1e-9,
    'a target jumping to the other side reverses, still 5.44pt/step'
  );
}

// Frame times that vary (8, 16, 33, 16, 8ms), none above FAR_STEP_MAX_DT_MS:
// the distance covered equals speed * sum(dt) / 1000 exactly.
function testStepTowardVariableFrameTimesSumExactly(): void {
  const speed = 340;
  const dts = [8, 16, 33, 16, 8];
  let x = 0;
  const target = 10_000; // far enough that no arrival interrupts the sum
  for (const dt of dts) {
    ({ x } = stepToward(x, target, speed, dt));
  }
  const totalDtS = dts.reduce((sum, dt) => sum + dt, 0) / 1000;
  ok(
    Math.abs(x - speed * totalDtS) < 1e-9,
    `distance covered must equal speed * total dt exactly, got ${x}`
  );
}

// literal expected values - a mutation that drops the lower dt clamp must fail
function testStepTowardNegativeDtDoesNotMove(): void {
  const result = stepToward(50, 300, 340, -5);
  strictEqual(result.x, 50, 'a negative dt clamps to 0 - it must not step backward in time');
  strictEqual(result.arrived, false);
}

// literal expected values - non-finite inputs and a non-positive speed are total, not NaN-producing
function testStepTowardTotalOnNonFiniteAndBadSpeed(): void {
  const infTarget = stepToward(10, Number.POSITIVE_INFINITY, 340, 16);
  strictEqual(infTarget.x, 10);
  strictEqual(infTarget.arrived, false);
  const infSpeed = stepToward(10, 300, Number.POSITIVE_INFINITY, 16);
  strictEqual(infSpeed.x, 10);
  strictEqual(infSpeed.arrived, false);
  const infDt = stepToward(10, 300, 340, Number.POSITIVE_INFINITY);
  strictEqual(infDt.x, 10);
  strictEqual(infDt.arrived, false);
  const zeroSpeed = stepToward(10, 300, 0, 16);
  strictEqual(zeroSpeed.x, 10, 'speed 0 must not freeze at a wrong x nor throw');
  strictEqual(zeroSpeed.arrived, false);
  const negSpeed = stepToward(10, 300, -5, 16);
  strictEqual(negSpeed.x, 10, 'a negative speed must not reverse him');
  strictEqual(negSpeed.arrived, false);
  const nanCurrent = stepToward(Number.NaN, 300, 340, 16);
  ok(Number.isNaN(nanCurrent.x), 'current itself not finite: x is returned as it is');
  strictEqual(nanCurrent.arrived, false);
}

// literal expected values - never derived from planFarSample's own expression;
// worked out from CHASE_TRAIL (18) + CHASE_SLACK (4) = 22 and chaseTargetX
function testPlanFarSample(): void {
  const screenWidth = WIDTH;
  const endAtThreshold = planFarSample({ glassX: 122, currentX: 100, screenWidth });
  strictEqual(endAtThreshold.kind, 'end', 'gap of exactly 22 is inside the not-chasing edge');
  const tracksJustPast = planFarSample({ glassX: 122.1, currentX: 100, screenWidth });
  strictEqual(tracksJustPast.kind, 'track');
  if (tracksJustPast.kind === 'track') {
    strictEqual(tracksJustPast.facing, 1);
    ok(
      Math.abs(tracksJustPast.target - 104.1) < 1e-9,
      `expected 104.1, got ${tracksJustPast.target}`
    );
  }
  const endAtNegThreshold = planFarSample({ glassX: 78, currentX: 100, screenWidth });
  strictEqual(
    endAtNegThreshold.kind,
    'end',
    'gap of exactly -22 is inside the not-chasing edge too'
  );
  const tracksJustPastNeg = planFarSample({ glassX: 77.9, currentX: 100, screenWidth });
  strictEqual(tracksJustPastNeg.kind, 'track');
  if (tracksJustPastNeg.kind === 'track') {
    strictEqual(tracksJustPastNeg.facing, -1, 'a gap of -22.1 flips facing to -1');
    ok(
      Math.abs(tracksJustPastNeg.target - 95.9) < 1e-9,
      `expected 95.9, got ${tracksJustPastNeg.target}`
    );
  }
  const bigGapFlips = planFarSample({ glassX: 300, currentX: 0, screenWidth });
  strictEqual(bigGapFlips.kind, 'track');
  if (bigGapFlips.kind === 'track') {
    strictEqual(bigGapFlips.facing, 1, 'a gap of 300 is a positive gap, facing 1');
    strictEqual(bigGapFlips.target, 300 - 18, 'target is glass - 18 once facing is 1');
  }
  const clampedLeft = planFarSample({ glassX: 10, currentX: -20, screenWidth });
  strictEqual(clampedLeft.kind, 'track');
  if (clampedLeft.kind === 'track') {
    strictEqual(clampedLeft.target, 0, 'chaseTargetX(10, 1, ...) = -8, clamped to the left edge');
  }
  const clampedRight = planFarSample({ glassX: 345, currentX: 400, screenWidth });
  strictEqual(clampedRight.kind, 'track');
  if (clampedRight.kind === 'track') {
    strictEqual(
      clampedRight.target,
      348,
      'chaseTargetX(345, -1, ...) = 363, clamped to the right edge (402 - 54)'
    );
  }
  const nanGlassEnds = planFarSample({ glassX: Number.NaN, currentX: 100, screenWidth });
  strictEqual(nanGlassEnds.kind, 'end', 'NaN glassX is total, not a track toward NaN');
  const nanCurrentEnds = planFarSample({ glassX: 122.1, currentX: Number.NaN, screenWidth });
  strictEqual(nanCurrentEnds.kind, 'end', 'NaN currentX is total, not a track toward NaN');
  const infGlassEnds = planFarSample({
    glassX: Number.POSITIVE_INFINITY,
    currentX: 100,
    screenWidth,
  });
  strictEqual(infGlassEnds.kind, 'end', 'Infinity glassX is total, not a track toward Infinity');
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
  testIsFarGrab();
  testSanitizeRunSpeed();
  testStepToward();
  testStepTowardFixedTargetStepCount();
  testStepTowardRecedingTarget();
  testStepTowardApproachingTarget();
  testStepTowardTargetJumpsSides();
  testStepTowardVariableFrameTimesSumExactly();
  testStepTowardNegativeDtDoesNotMove();
  testStepTowardTotalOnNonFiniteAndBadSpeed();
  testPlanFarSample();
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
  console.log('53 passed (perch-handoff)');
}

main();
