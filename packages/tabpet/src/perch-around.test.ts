import { ok, strictEqual } from 'node:assert';

import type { AroundPath, PillFrame, ResumedRoute } from './perch-around';
import {
  AROUND_MIN_SLOT_COUNT,
  AROUND_SPEED_PT_S,
  aroundPose,
  isEndToEnd,
  planAroundPath,
  resumeAroundRoute,
  resumedBaseS,
  resumedPose,
  routePivot,
  shouldRouteAround,
} from './perch-around';
import { PERCH_SIZE } from './perch-geometry';

const FIT_TOLERANCE = 0.5;
const ARC_EPSILON = 1e-6;

// pill, footPad, and seatOffset shared by every planAroundPath fixture below
const PILL: PillFrame = { x: 24, y: 800, width: 354, height: 64 };
const FOOT_PAD = 11;
const SEAT_OFFSET = -5;
const SPRITE_SCALE = 0.72;

const PLAN = {
  pill: PILL,
  windowWidth: 402,
  spriteScale: SPRITE_SCALE,
  footPad: FOOT_PAD,
  headPad: 0,
  seatOffset: SEAT_OFFSET,
};

// slot 0 -> 4 of 5 on the PLAN fixture
const FROM_X = 40;
const TARGET_X = 320;

/** window-space y of the drawn feet for a given seatY (the pivot keeps the
 *  feet there through every rotation) */
function feetY(seatY: number): number {
  const boxCenterY0 = PILL.y - SEAT_OFFSET - PERCH_SIZE / 2;
  return boxCenterY0 + seatY + routePivot(SPRITE_SCALE, FOOT_PAD);
}

function testShouldRouteAroundTruthTable() {
  const base = {
    fromSlot: 0,
    toSlot: 4,
    slotCount: 5,
    aroundRoute: true,
    flightLift: 0,
    pill: PILL,
    reduceMotion: false,
  };
  strictEqual(shouldRouteAround(base), true, 'first -> last routes around');
  strictEqual(
    shouldRouteAround({ ...base, fromSlot: 4, toSlot: 0 }),
    true,
    'last -> first routes around'
  );
  strictEqual(
    shouldRouteAround({ ...base, toSlot: 3 }),
    false,
    'a stop one short of the end (0 -> 3 of 5) stays on the pill'
  );
  strictEqual(
    shouldRouteAround({ ...base, fromSlot: 1, toSlot: 4 }),
    false,
    'from the second slot (1 -> 4 of 5) stays on the pill'
  );
  strictEqual(
    shouldRouteAround({ ...base, toSlot: 2, slotCount: 3 }),
    true,
    'a three-tab bar still routes end to end'
  );
  strictEqual(
    shouldRouteAround({ ...base, toSlot: 1, slotCount: 2 }),
    false,
    'a two-tab bar never routes around (adjacent hop)'
  );
  strictEqual(isEndToEnd(0, 0, 5), false, 'same slot is not end to end');
  strictEqual(
    shouldRouteAround({ ...base, aroundRoute: false }),
    false,
    'opted-out profile never routes around'
  );
  strictEqual(
    shouldRouteAround({ ...base, flightLift: 14 }),
    false,
    'a flying companion never routes around'
  );
  strictEqual(
    shouldRouteAround({ ...base, pill: null }),
    false,
    'no pill (classic bar) never routes around'
  );
  strictEqual(
    shouldRouteAround({ ...base, reduceMotion: true }),
    false,
    'reduce motion never routes around'
  );
  strictEqual(AROUND_MIN_SLOT_COUNT, 3, 'fixture assumes the current AROUND_MIN_SLOT_COUNT');
}

function testPlanAroundPathHomeToSettings() {
  const path = planAroundPath({ ...PLAN, fromX: FROM_X, targetX: TARGET_X });
  strictEqual(path.exitSide, -1, "departs off the pill's left end");
  strictEqual(path.enterSide, 1, "climbs the pill's right end");
  strictEqual(path.facing, -1, 'faces the exit end for the whole route');
  strictEqual(path.spin, -1, 'rolls head-first over the left end: counter-clockwise');
  strictEqual(path.pivot, routePivot(SPRITE_SCALE, FOOT_PAD), 'pivot is the feet offset');
  const start = aroundPose(path, 0);
  strictEqual(start.x, FROM_X, 'pose at s=0 sits at the departure x');
  strictEqual(start.seatY, 0, 'pose at s=0 sits on the seat');
  strictEqual(start.rotation, 0, 'pose at s=0 is unrotated');
  const end = aroundPose(path, path.totalLen);
  strictEqual(end.x, TARGET_X, 'pose at totalLen sits at the destination x');
  strictEqual(end.seatY, 0, 'pose at totalLen sits back on the seat');
  strictEqual(end.rotation, path.spin * 360, 'pose at totalLen completes the roll');
  // the hang mirrors the seat: as far below the bottom edge as above the top
  const aboveTop = PILL.y - feetY(0);
  ok(
    Math.abs(feetY(path.underY) - (PILL.y + PILL.height) - aboveTop) <= FIT_TOLERANCE,
    "the feet hang as far below the pill's bottom edge as they stand above its top"
  );
}

function testPlanAroundPathMirrorTripSwapsSidesAndSpin() {
  const there = planAroundPath({ ...PLAN, fromX: FROM_X, targetX: TARGET_X });
  const back = planAroundPath({ ...PLAN, fromX: TARGET_X, targetX: FROM_X });
  strictEqual(back.exitSide, there.enterSide, 'the return trip exits where the outbound entered');
  strictEqual(back.enterSide, there.exitSide, 'the return trip enters where the outbound exited');
  strictEqual(back.facing, 1, 'the return trip faces the right end');
  strictEqual(back.spin, 1, 'the return trip rolls clockwise');
  strictEqual(back.underY, there.underY, 'the hang height does not depend on direction');
}

function testPlanAroundPathHangIgnoresTheGap() {
  // the hang is fixed by the pill alone - a taller body clips at the window
  // bottom instead of lifting the feet into the pill
  const path = planAroundPath({ ...PLAN, fromX: FROM_X, targetX: TARGET_X });
  const shortHead = planAroundPath({ ...PLAN, headPad: 10, fromX: FROM_X, targetX: TARGET_X });
  strictEqual(shortHead.underY, path.underY, 'headPad never moves the hang');
  ok(feetY(path.underY) > PILL.y + PILL.height, 'the feet hang below the pill bottom');
}

/** which of the 5 legs s falls in, matching aroundPose's own boundaries */
function legOf(path: AroundPath, s: number): 1 | 2 | 3 | 4 | 5 {
  const [s1, s2, s3, s4] = path.legs;
  if (s <= s1) {
    return 1;
  }
  if (s <= s2) {
    return 2;
  }
  if (s <= s3) {
    return 3;
  }
  if (s <= s4) {
    return 4;
  }
  return 5;
}

interface PathSample {
  s: number;
  pose: { x: number; seatY: number; rotation: number };
}

function samplePath(path: AroundPath): PathSample[] {
  const samples: PathSample[] = [];
  for (let s = 0; s <= path.totalLen; s += 1) {
    samples.push({ s, pose: aroundPose(path, s) });
  }
  const last = samples.at(-1);
  if (last && last.s !== path.totalLen) {
    samples.push({ s: path.totalLen, pose: aroundPose(path, path.totalLen) });
  }
  return samples;
}

function testOnOutline() {
  const path = planAroundPath({ ...PLAN, fromX: FROM_X, targetX: TARGET_X });
  const { seatFeetY } = path;
  const hangFeetY = path.seatFeetY + path.underY;
  for (const { s, pose } of samplePath(path)) {
    const fx = pose.x + PERCH_SIZE / 2;
    const fy = seatFeetY + pose.seatY;
    const leg = legOf(path, s);
    if (leg === 1 || leg === 5) {
      strictEqual(fy, seatFeetY, `leg ${leg} at s=${s} sits at seat height`);
    } else if (leg === 3) {
      strictEqual(fy, hangFeetY, `leg 3 at s=${s} hangs at the mirrored height`);
    } else {
      const cx = leg === 2 ? path.cxExit : path.cxEnter;
      const norm = ((fx - cx) / path.a) ** 2 + ((fy - path.cy) / path.b) ** 2;
      ok(
        Math.abs(norm - 1) <= ARC_EPSILON,
        `leg ${leg} at s=${s} sits on the ellipse (norm=${norm})`
      );
    }
  }
}

function testContinuity() {
  const path = planAroundPath({ ...PLAN, fromX: FROM_X, targetX: TARGET_X });
  const samples = samplePath(path);
  for (let i = 1; i < samples.length; i += 1) {
    const prev = samples[i - 1].pose;
    const cur = samples[i].pose;
    const dx = Math.abs(cur.x - prev.x);
    const dy = Math.abs(cur.seatY - prev.seatY);
    const dRot = Math.abs(cur.rotation - prev.rotation);
    ok(
      dx <= 1.5,
      `x moves <= 1.5pt between s=${samples[i - 1].s} and s=${samples[i].s} (was ${dx})`
    );
    ok(
      dy <= 1.5,
      `y moves <= 1.5pt between s=${samples[i - 1].s} and s=${samples[i].s} (was ${dy})`
    );
    ok(
      dRot <= 6,
      `rotation moves <= 6deg between s=${samples[i - 1].s} and s=${samples[i].s} (was ${dRot})`
    );
  }
}

function testConstantSpeedOnArcs() {
  const path = planAroundPath({ ...PLAN, fromX: FROM_X, targetX: TARGET_X });
  const samples = samplePath(path);
  for (let i = 1; i < samples.length; i += 1) {
    const a = samples[i - 1];
    const b = samples[i];
    if (b.s - a.s !== 1) {
      continue; // skip the appended exact-totalLen sample if it lands off-grid
    }
    const legA = legOf(path, a.s);
    const legB = legOf(path, b.s);
    if (legA !== legB || (legA !== 2 && legA !== 4)) {
      continue; // only both-in-the-same-arc pairs are checked here
    }
    const chord = Math.hypot(b.pose.x - a.pose.x, b.pose.seatY - a.pose.seatY);
    ok(
      Math.abs(chord - 1) <= 0.05,
      `arc chord at s=${a.s}->${b.s} stays within 5% of 1pt (was ${chord})`
    );
  }
}

function testEndpointsMonotoneAndTiming() {
  const path = planAroundPath({ ...PLAN, fromX: FROM_X, targetX: TARGET_X });
  const start = aroundPose(path, 0);
  strictEqual(start.x, FROM_X, 'endpoint: x starts at fromX');
  strictEqual(start.seatY, 0, 'endpoint: seatY starts at 0');
  strictEqual(start.rotation, 0, 'endpoint: rotation starts at 0');
  const end = aroundPose(path, path.totalLen);
  strictEqual(end.x, TARGET_X, 'endpoint: x ends at targetX');
  strictEqual(end.seatY, 0, 'endpoint: seatY ends at 0');
  strictEqual(end.rotation, path.spin * 360, 'endpoint: rotation ends at spin * 360');
  strictEqual(
    path.totalMs,
    (path.totalLen / AROUND_SPEED_PT_S) * 1000,
    'totalMs matches totalLen at the one route speed'
  );
  let prevRotation = 0;
  for (const { pose } of samplePath(path)) {
    if (path.spin > 0) {
      ok(pose.rotation >= prevRotation - ARC_EPSILON, 'rotation is monotone non-decreasing');
    } else {
      ok(pose.rotation <= prevRotation + ARC_EPSILON, 'rotation is monotone non-increasing');
    }
    prevRotation = pose.rotation;
  }
}

function testMirrorTripFlipsRotationSign() {
  const there = planAroundPath({ ...PLAN, fromX: FROM_X, targetX: TARGET_X });
  const back = planAroundPath({ ...PLAN, fromX: TARGET_X, targetX: FROM_X });
  strictEqual(back.exitSide, there.enterSide, 'the return trip exits where the outbound entered');
  strictEqual(back.enterSide, there.exitSide, 'the return trip enters where the outbound exited');
  strictEqual(back.spin, -there.spin, 'the return trip spins the opposite way');
  const thereEnd = aroundPose(there, there.totalLen).rotation;
  const backEnd = aroundPose(back, back.totalLen).rotation;
  strictEqual(thereEnd, there.spin * 360, 'the 0 -> 4 trip ends its roll at spin * 360');
  strictEqual(backEnd, back.spin * 360, 'the 4 -> 0 trip ends its roll at spin * 360');
  strictEqual(backEnd, -thereEnd, 'the return trip ends the roll at the opposite sign');
}

// a target left/right of the pill center (201), used by the resume tests -
// arbitrary window x's, not tied to any particular slot layout
const LEFT_TARGET_X = 120;
const RIGHT_TARGET_X = 280;
const RESUME_EPSILON = 1e-9;

/** which of the 5 legs s falls in on the RESUME path's own boundaries */
function resumeLegOf(route: ResumedRoute, u: number): 1 | 2 | 3 | 4 | 5 {
  if (u >= route.curveLen) {
    return 5; // the straight tail - never a seat-line leg of `base`
  }
  return legOf(route.base, route.startS + route.dir * u);
}

function testResumeContinuityAtInterrupt() {
  const path = planAroundPath({ ...PLAN, fromX: FROM_X, targetX: TARGET_X });
  const [s1, s2, s3, s4] = path.legs;
  const midS = [s1 + (s2 - s1) / 2, s2 + (s3 - s2) / 2, s3 + (s4 - s3) / 2];
  for (const targetX of [LEFT_TARGET_X, RIGHT_TARGET_X]) {
    for (const s of midS) {
      const route = resumeAroundRoute(path, s, targetX);
      ok(route !== null, `s=${s} inside legs 2-4 always resumes`);
      if (!route) {
        continue;
      }
      const expected = aroundPose(path, s);
      const actual = resumedPose(route, 0);
      ok(Math.abs(actual.x - expected.x) <= RESUME_EPSILON, `resume x continuous at s=${s}`);
      ok(
        Math.abs(actual.seatY - expected.seatY) <= RESUME_EPSILON,
        `resume seatY continuous at s=${s}`
      );
      ok(
        Math.abs(actual.rotation - expected.rotation) <= RESUME_EPSILON,
        `resume rotation continuous at s=${s}`
      );
    }
  }
}

function testResumeOnOutline() {
  const path = planAroundPath({ ...PLAN, fromX: FROM_X, targetX: TARGET_X });
  const midLeg3 = path.legs[1] + (path.legs[2] - path.legs[1]) / 2;
  const route = resumeAroundRoute(path, midLeg3, RIGHT_TARGET_X);
  ok(route !== null, 'midpoint of leg 3 resumes');
  if (!route) {
    return;
  }
  const { seatFeetY } = path;
  const hangFeetY = path.seatFeetY + path.underY;
  let prevRotation: number | null = null;
  for (let u = 0; u <= route.curveLen; u += 1) {
    const pose = resumedPose(route, u);
    const fx = pose.x + PERCH_SIZE / 2;
    const fy = seatFeetY + pose.seatY;
    const leg = resumeLegOf(route, u);
    if (leg === 3) {
      strictEqual(fy, hangFeetY, `curve u=${u} hangs at the mirrored height`);
    } else {
      const cx = leg === 2 ? path.cxExit : path.cxEnter;
      const norm = ((fx - cx) / path.a) ** 2 + ((fy - path.cy) / path.b) ** 2;
      ok(Math.abs(norm - 1) <= ARC_EPSILON, `curve u=${u} sits on the ellipse (norm=${norm})`);
    }
    if (prevRotation !== null) {
      ok(
        Math.abs(pose.rotation - prevRotation) <= 6,
        `rotation continuous at u=${u} (was ${pose.rotation} vs ${prevRotation})`
      );
    }
    prevRotation = pose.rotation;
  }
}

function testResumeDirectionChoice() {
  const path = planAroundPath({ ...PLAN, fromX: FROM_X, targetX: TARGET_X });
  // oxlint-disable-next-line unicorn/no-unreadable-array-destructuring -- only s1/s4 matter here
  const [s1, , , s4] = path.legs;

  // just past the exit cap, target right at the exit end: backing off is short
  const nearExitS = s1 + 1;
  const exitEndTargetX = path.cxExit - PERCH_SIZE / 2;
  const backRoute = resumeAroundRoute(path, nearExitS, exitEndTargetX);
  ok(backRoute !== null, 'near-exit interrupt resumes');
  if (backRoute) {
    strictEqual(backRoute.dir, -1, 'backing toward the exit end is shorter');
    strictEqual(backRoute.facing, -path.facing, 'a backward resume flips facing');
    const forwardLen = s4 - nearExitS + Math.abs(exitEndTargetX + PERCH_SIZE / 2 - path.cxEnter);
    ok(backRoute.totalLen <= forwardLen, 'the chosen (backward) length is the shorter one');
  }

  // just before the enter cap, target right at the enter end: continuing on is short
  const nearEnterS = s4 - 1;
  const enterEndTargetX = path.cxEnter - PERCH_SIZE / 2;
  const fwdRoute = resumeAroundRoute(path, nearEnterS, enterEndTargetX);
  ok(fwdRoute !== null, 'near-enter interrupt resumes');
  if (fwdRoute) {
    strictEqual(fwdRoute.dir, 1, 'continuing toward the enter end is shorter');
    const backwardLen = nearEnterS - s1 + Math.abs(enterEndTargetX + PERCH_SIZE / 2 - path.cxExit);
    ok(fwdRoute.totalLen <= backwardLen, 'the chosen (forward) length is the shorter one');
  }
}

function testResumeEndpoint() {
  const path = planAroundPath({ ...PLAN, fromX: FROM_X, targetX: TARGET_X });
  const midLeg2 = path.legs[0] + (path.legs[1] - path.legs[0]) / 2;
  const route = resumeAroundRoute(path, midLeg2, RIGHT_TARGET_X);
  ok(route !== null, 'midpoint of leg 2 resumes');
  if (!route) {
    return;
  }
  const end = resumedPose(route, route.totalLen);
  ok(Math.abs(end.x - RIGHT_TARGET_X) <= RESUME_EPSILON, 'resume ends at the new target x');
  strictEqual(end.seatY, 0, 'resume ends seated');
  strictEqual(end.rotation, route.endRotation, 'resume ends at endRotation');
}

function testResumeSeatLineReturnsNull() {
  const path = planAroundPath({ ...PLAN, fromX: FROM_X, targetX: TARGET_X });
  // oxlint-disable-next-line unicorn/no-unreadable-array-destructuring -- only s1/s4/s5 matter here
  const [s1, , , s4, s5] = path.legs;
  strictEqual(resumeAroundRoute(path, 0, RIGHT_TARGET_X), null, 's=0 is on leg 1');
  strictEqual(resumeAroundRoute(path, s1, RIGHT_TARGET_X), null, 's=legs[0] is the leg 1/2 seam');
  strictEqual(resumeAroundRoute(path, s4, RIGHT_TARGET_X), null, 's=legs[3] is the leg 4/5 seam');
  strictEqual(resumeAroundRoute(path, s5, RIGHT_TARGET_X), null, 's=totalLen is on leg 5');
}

function testResumedBaseSRoundTrips() {
  const path = planAroundPath({ ...PLAN, fromX: FROM_X, targetX: TARGET_X });
  const midLeg4 = path.legs[2] + (path.legs[3] - path.legs[2]) / 2;
  const route = resumeAroundRoute(path, midLeg4, LEFT_TARGET_X);
  ok(route !== null, 'midpoint of leg 4 resumes');
  if (!route) {
    return;
  }
  for (let u = 0; u < route.curveLen; u += 1) {
    const s = resumedBaseS(route, u);
    ok(s !== null, `u=${u} is still on the curve`);
    if (s === null) {
      continue;
    }
    const fromBase = aroundPose(route.base, s);
    const fromResumed = resumedPose(route, u);
    strictEqual(fromBase.x, fromResumed.x, `x round-trips at u=${u}`);
    strictEqual(fromBase.seatY, fromResumed.seatY, `seatY round-trips at u=${u}`);
    strictEqual(fromBase.rotation, fromResumed.rotation, `rotation round-trips at u=${u}`);
  }
  strictEqual(
    resumedBaseS(route, route.curveLen + 1),
    null,
    'a point on the straight tail has no base s'
  );
}

function testResumeConstantSpeedTiming() {
  const path = planAroundPath({ ...PLAN, fromX: FROM_X, targetX: TARGET_X });
  const midLeg3 = path.legs[1] + (path.legs[2] - path.legs[1]) / 2;
  const route = resumeAroundRoute(path, midLeg3, LEFT_TARGET_X);
  ok(route !== null, 'midpoint of leg 3 resumes');
  if (!route) {
    return;
  }
  strictEqual(
    route.totalMs,
    (route.totalLen / AROUND_SPEED_PT_S) * 1000,
    'totalMs matches totalLen at the one route speed'
  );
}

testShouldRouteAroundTruthTable();
testPlanAroundPathHomeToSettings();
testPlanAroundPathMirrorTripSwapsSidesAndSpin();
testPlanAroundPathHangIgnoresTheGap();
testOnOutline();
testContinuity();
testConstantSpeedOnArcs();
testEndpointsMonotoneAndTiming();
testMirrorTripFlipsRotationSign();
testResumeContinuityAtInterrupt();
testResumeOnOutline();
testResumeDirectionChoice();
testResumeEndpoint();
testResumeSeatLineReturnsNull();
testResumedBaseSRoundTrips();
testResumeConstantSpeedTiming();
console.log('perch-around: 16 tests passed');
