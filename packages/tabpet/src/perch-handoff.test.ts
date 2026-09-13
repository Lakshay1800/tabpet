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
  initialPerchHandoff,
  liveLastSeat,
  planFocus,
  planMountSeatY,
  planRunSeatY,
  planStartSeatY,
  readPerchHandoff,
  resetPerchHandoffForTest,
  writePerchHandoff,
} from './perch-handoff';

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

function testSingletonReset(): void {
  resetPerchHandoffForTest();
  deepStrictEqual(readPerchHandoff(), initialPerchHandoff());
  writePerchHandoff({ lastTab: 3, lastX: 99, lastSeat: 8 });
  deepStrictEqual(readPerchHandoff(), { lastTab: 3, lastX: 99, lastSeat: 8 });
  resetPerchHandoffForTest();
  deepStrictEqual(readPerchHandoff(), initialPerchHandoff());
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
  testSingletonReset();
  // oxlint-disable-next-line no-console -- test runner reporting
  console.log('19 passed (perch-handoff)');
}

main();
