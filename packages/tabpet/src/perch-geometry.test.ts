import { deepStrictEqual, ok, strictEqual } from 'node:assert';

import {
  BAR_MARGIN_H,
  CHASE_SLACK,
  CHASE_TRAIL,
  chaseStep,
  chaseTargetX,
  FACING_DEADBAND,
  glassTargetX,
  MAX_TRAVERSE_MS,
  nearestSlot,
  MIN_TRAVERSE_MS,
  PERCH_SIZE,
  seatedFootPad,
  shouldSnapToSeat,
  tabCenterX,
  travelFacing,
  TRAVERSE_SPEED_PT_S,
  traverseDurationMs,
} from './perch-geometry';

// number of tab slots in the reference host app's bar - kept as a plain
// fixture so this module has no opinion on any particular app's tab layout
const SLOT_COUNT = 5;

function testPerchCenteredOverEachTabSlot() {
  const width = 402; // iPhone 16 Pro pt
  const barWidth = width - 2 * BAR_MARGIN_H;
  const slotWidth = barWidth / SLOT_COUNT;
  for (let tab = 0; tab < SLOT_COUNT; tab += 1) {
    const slotCenter = BAR_MARGIN_H + slotWidth * (tab + 0.5);
    const perchCenter = tabCenterX(tab, width, SLOT_COUNT) + PERCH_SIZE / 2;
    strictEqual(perchCenter, slotCenter, `tab ${tab} perch center`);
  }
}

function testPerchStaysOnScreenAtAllWidths() {
  for (const width of [320, 375, 402, 430, 744, 1024]) {
    const first = tabCenterX(0, width, SLOT_COUNT);
    const last = tabCenterX(SLOT_COUNT - 1, width, SLOT_COUNT);
    ok(first >= 0, `width ${width}: first tab on-screen`);
    ok(last + PERCH_SIZE <= width, `width ${width}: last tab on-screen`);
    ok(last > first, `width ${width}: tabs ordered left-to-right`);
  }
}

function testGlassTargetXCentersOnFinger() {
  const width = 402;
  const fingerX = 200;
  strictEqual(glassTargetX(fingerX, width), fingerX - PERCH_SIZE / 2, 'centers under the finger');
}

function testGlassTargetXClampsLeftEdge() {
  const width = 402;
  strictEqual(glassTargetX(0, width), 0, 'clamps to the left screen edge');
  strictEqual(glassTargetX(-50, width), 0, 'clamps a negative finger x to the left edge');
}

function testGlassTargetXClampsRightEdge() {
  const width = 402;
  strictEqual(glassTargetX(width, width), width - PERCH_SIZE, 'clamps to the right screen edge');
  strictEqual(
    glassTargetX(width + 100, width),
    width - PERCH_SIZE,
    'clamps a finger x past the edge to the right edge'
  );
}

function testChaseTargetTrailsTravelDirection() {
  const width = 402;
  const glassX = 180;
  strictEqual(chaseTargetX(glassX, 1, width), glassX - CHASE_TRAIL, 'trails a right-moving glass');
  strictEqual(chaseTargetX(glassX, -1, width), glassX + CHASE_TRAIL, 'trails a left-moving glass');
}

function testChaseTargetClampsAtEdges() {
  const width = 402;
  strictEqual(chaseTargetX(0, 1, width), 0, 'rightward chase stays on the left edge');
  strictEqual(
    chaseTargetX(width - PERCH_SIZE, -1, width),
    width - PERCH_SIZE,
    'leftward chase stays on the right edge'
  );
}

function testTravelFacingFollowsActualTravel() {
  // pup far left, target far right: he travels right regardless of finger wiggle
  strictEqual(travelFacing(300, 50, -1), 1, 'faces right toward a far-right target');
  strictEqual(travelFacing(50, 300, 1), -1, 'faces left toward a far-left target');
}

function testTravelFacingHoldsInsideDeadband() {
  strictEqual(travelFacing(100, 100, -1), -1, 'zero delta holds current facing');
  strictEqual(
    travelFacing(100 + FACING_DEADBAND, 100, -1),
    -1,
    'delta at the deadband boundary still holds'
  );
  strictEqual(travelFacing(100 + FACING_DEADBAND + 1, 100, -1), 1, 'delta past the deadband flips');
}

function testTravelFacingDeadbandStaysUnderChaseTrail() {
  // steady tracking parks the pup CHASE_TRAIL behind the glass; the deadband
  // must not swallow that offset or the mirror would oscillate mid-drag
  ok(FACING_DEADBAND < CHASE_TRAIL, 'deadband must stay below the chase trail');
}

function testChaseStepHoldsInsideLeash() {
  deepStrictEqual(
    chaseStep(100, 100, 1, false),
    { target: null, facing: 1 },
    'glass directly over the pup: stand'
  );
  deepStrictEqual(
    chaseStep(100 + CHASE_TRAIL, 100, -1, false),
    { target: null, facing: -1 },
    'gap at the leash still holds, facing untouched'
  );
  deepStrictEqual(
    chaseStep(100 - CHASE_TRAIL, 100, 1, false),
    { target: null, facing: 1 },
    'glass slightly behind: he does NOT walk backward'
  );
}

function testChaseStepChasesBeyondLeash() {
  const start = CHASE_TRAIL + CHASE_SLACK + 1;
  deepStrictEqual(
    chaseStep(100 + start, 100, -1, false),
    { target: 100 + start - CHASE_TRAIL, facing: 1 },
    'leash taut to the right: chase to trailing distance, face right'
  );
  deepStrictEqual(
    chaseStep(100 - start, 100, 1, false),
    { target: 100 - start + CHASE_TRAIL, facing: -1 },
    'leash taut to the left: chase to trailing distance, face left'
  );
}

function testChaseStepHysteresis() {
  const hover = CHASE_TRAIL + 1; // inside the band either way
  deepStrictEqual(
    chaseStep(100 + hover, 100, 1, false),
    { target: null, facing: 1 },
    'standing: a gap just past the bare leash does not start a chase'
  );
  deepStrictEqual(
    chaseStep(100 + hover, 100, 1, true),
    { target: 100 + hover - CHASE_TRAIL, facing: 1 },
    'chasing: the same gap keeps the chase alive'
  );
  deepStrictEqual(
    chaseStep(100 + CHASE_TRAIL - CHASE_SLACK, 100, 1, true),
    { target: null, facing: 1 },
    'chasing: he stands down only once well inside the leash'
  );
}

testPerchCenteredOverEachTabSlot();
testPerchStaysOnScreenAtAllWidths();
testGlassTargetXCentersOnFinger();
testGlassTargetXClampsLeftEdge();
testGlassTargetXClampsRightEdge();
testChaseTargetTrailsTravelDirection();
testChaseTargetClampsAtEdges();
testTravelFacingFollowsActualTravel();
testTravelFacingHoldsInsideDeadband();
testTravelFacingDeadbandStaysUnderChaseTrail();
function testTraverseDurationMsClampsToFloor() {
  strictEqual(traverseDurationMs(0), MIN_TRAVERSE_MS, 'zero distance clamps to the floor');
  strictEqual(
    traverseDurationMs(80),
    MIN_TRAVERSE_MS,
    'one-tab-ish distance clamps to the floor, keeping short hops feeling unchanged'
  );
}

function testTraverseDurationMsClampsToCeiling() {
  strictEqual(
    traverseDurationMs(100_000),
    MAX_TRAVERSE_MS,
    'a pathologically long distance clamps to the ceiling'
  );
}

function testTraverseDurationMsFollowsConstantSpeedUnclamped() {
  // pick a distance whose raw duration lands strictly between the clamps
  const distance = 600;
  const expected = (distance / TRAVERSE_SPEED_PT_S) * 1000;
  ok(expected > MIN_TRAVERSE_MS && expected < MAX_TRAVERSE_MS, 'fixture sits between the clamps');
  strictEqual(
    traverseDurationMs(distance),
    expected,
    'unclamped distance follows the constant speed'
  );
}

function testTraverseDurationMsLongerTraverseTakesLonger() {
  // a leftmost-to-rightmost tap on a reference-width screen should read
  // clearly longer than a single adjacent-tab hop
  const oneTabHop = traverseDurationMs(80);
  const fullWidthTraverse = traverseDurationMs(296);
  ok(fullWidthTraverse > oneTabHop, 'a longer distance takes visibly longer to traverse');
}

function testTraverseDurationMsIgnoresSign() {
  strictEqual(
    traverseDurationMs(-296),
    traverseDurationMs(296),
    'direction does not change how long the traverse takes'
  );
}

function testTraverseDurationMsSpeedOverride() {
  const speed = TRAVERSE_SPEED_PT_S / 2;
  strictEqual(
    traverseDurationMs(600, speed),
    traverseDurationMs(600) * 2,
    'half speed doubles an unclamped traverse'
  );
  strictEqual(
    traverseDurationMs(80, speed),
    MIN_TRAVERSE_MS * 2,
    'the floor stretches with the override - a slow animal stays slow on a short hop'
  );
  strictEqual(
    traverseDurationMs(100_000, speed),
    MAX_TRAVERSE_MS * 2,
    'the ceiling stretches with the override'
  );
  strictEqual(
    traverseDurationMs(600, TRAVERSE_SPEED_PT_S),
    traverseDurationMs(600),
    'passing the default speed matches the no-arg call'
  );
}

testChaseStepHoldsInsideLeash();
testChaseStepChasesBeyondLeash();
testChaseStepHysteresis();
function testShouldSnapToSeatPinsThreshold() {
  strictEqual(PERCH_SIZE, 54, 'fixture assumes the current glass-width value');
  strictEqual(shouldSnapToSeat(53.9), true, 'just under one glass width still snaps');
  strictEqual(shouldSnapToSeat(54), false, 'exactly one glass width no longer snaps (strict <)');
}

function testShouldSnapToSeatTrivialNearZero() {
  strictEqual(shouldSnapToSeat(0), true, 'zero distance snaps');
  strictEqual(shouldSnapToSeat(2), true, 'the old <2 threshold is well inside the new one');
}

testTraverseDurationMsClampsToFloor();
testTraverseDurationMsClampsToCeiling();
testTraverseDurationMsFollowsConstantSpeedUnclamped();
testTraverseDurationMsSpeedOverride();
testTraverseDurationMsLongerTraverseTakesLonger();
testTraverseDurationMsIgnoresSign();
testShouldSnapToSeatPinsThreshold();
testShouldSnapToSeatTrivialNearZero();

function testSeatedFootPadFollowsScale() {
  strictEqual(seatedFootPad(11, 1), 11, 'identity at reference size');
  // a 1.25x figure's feet land lower in the box, so the seat pads less
  ok(Math.abs(seatedFootPad(11.025, 1.25) - 7.03125) < 1e-9, 'scaled up pads less');
  // a 0.72x figure's feet float higher, so the seat pads more
  ok(Math.abs(seatedFootPad(11, 0.72) - 15.48) < 1e-9, 'scaled down pads more');
}
testSeatedFootPadFollowsScale();

function testNearestSlotPicksClosestCenter() {
  const width = 402;
  // even split, 4 slots: centers at 62.25, 154.75, 247.25, 339.75
  strictEqual(nearestSlot(0, width, 4), 0);
  strictEqual(nearestSlot(108, width, 4), 0);
  strictEqual(nearestSlot(109, width, 4), 1);
  strictEqual(nearestSlot(300, width, 4), 3);
  strictEqual(nearestSlot(402, width, 4), 3);
  // measured centers win over the even split
  const centers = [40, 120, 300];
  strictEqual(nearestSlot(200, width, 3, centers), 1);
  strictEqual(nearestSlot(215, width, 3, centers), 2);
}
testNearestSlotPicksClosestCenter();
console.log('perch-geometry: 22 tests passed');

// measured centers win over the even split, and a missing entry falls back
{
  const centers = [40, 120, 200];
  strictEqual(tabCenterX(1, 390, 3, centers), 120 - PERCH_SIZE / 2, 'measured center used');
  strictEqual(tabCenterX(2, 390, 5, [40, 120]), tabCenterX(2, 390, 5), 'missing entry falls back');
}
