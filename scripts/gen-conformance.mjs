#!/usr/bin/env node
/**
 * Generates the conformance fixtures at the repository root from the
 * TypeScript pure functions in packages/tabpet/src/{perch-geometry,
 * perch-around,perch-handoff,pose-dissolve}.ts. Run under tsx (`bun run
 * conformance`) since it imports those .ts sources directly, the same way
 * scripts/run-tests.mjs runs the *.test.ts suites.
 *
 * `bun run conformance --check` regenerates every file in memory and exits 1
 * with a diff summary if any committed file differs, without writing.
 *
 * `bun run conformance --self-test` proves the around.json tolerance rule
 * below actually does something: bumps an argument float and an expectation
 * float by one ULP in memory and asserts the structural diff still reports
 * none, then does the same to a geometry.json expectation and asserts a diff
 * IS reported. Wired into the conformance check step of `bun run check`.
 *
 * Write ordering: every module's payload is built - which runs every one of
 * its assertions - before any file is written. A failing assertion on module
 * 4 must not leave modules 1-3 freshly overwritten and module 4 stale; it
 * must leave the whole committed set untouched.
 *
 * Determinism: every case is built by explicit, fixed-order enumeration over
 * curated value lists (edges + a deterministic evenly-spaced sample of the
 * remaining cartesian product via combosCapped). No Math.random, no Date, no
 * environment reads - two runs always produce byte-identical output.
 *
 * Coverage: every function below prepends a hand-written MUST-HIT list
 * (both sides of every comparison, every early return, every discriminant
 * value) before any sampled cases, then asserts the OUTPUT CLASSES those
 * combined cases must produce (assertOutputClasses/buildCases) - a miss
 * throws before any file is written, so a coverage regression fails
 * `bun run conformance` itself, not just a later replay. combosCapped's
 * sampling stride is chosen coprime with the cartesian total (hence with
 * every radix - each radix divides the total) so it cannot lock a dimension
 * to a subset of its values the way a stride sharing a factor with a radix
 * did previously (isEndToEnd/shouldRouteAround sampled 0 true cases).
 *
 * Skipped (module-state, not pure): perch-handoff's readPerchHandoff,
 * writePerchHandoff, resetPerchHandoffForTest.
 *
 * Constants: each output file also carries a top-level "constants" object -
 * every numeric constant its source module exports, wrapped in the same
 * {bits, value} format as any case argument/expectation. Both readers
 * (conformance.test.ts and the Swift *ConformanceTests.swift files) check
 * every one of them against their own module's copy, so a constant drifting
 * out of sync between the TypeScript and the Swift port fails loudly instead
 * of only showing up as an unrelated case mismatch downstream.
 *
 * Compare-rule table (why): a function is "tolerance" only if a JS engine
 * could legitimately round its last bit differently from another - i.e. its
 * result passes through Math.sin/cos/atan2/hypot. Everything else is
 * "exact" (bit-identical), including functions that merely consume an
 * already-computed tolerance-derived value (e.g. resumeAroundRoute reads
 * base.legs/cxExit but only does its own arithmetic on them).
 *
 * | module          | function          | compare   | why |
 * |-----------------|--------------------|-----------|-----|
 * | perch-geometry  | tabCenterX         | exact     | arithmetic only |
 * | perch-geometry  | nearestSlot        | exact     | arithmetic only |
 * | perch-geometry  | glassTargetX       | exact     | Math.min/max only |
 * | perch-geometry  | chaseTargetX       | exact     | arithmetic + min/max |
 * | perch-geometry  | chaseStep          | exact     | arithmetic + comparisons |
 * | perch-geometry  | travelFacing       | exact     | arithmetic only |
 * | perch-geometry  | shouldSnapToSeat   | exact     | comparison only |
 * | perch-geometry  | traverseDurationMs | exact     | arithmetic + min/max |
 * | perch-geometry  | seatedFootPad      | exact     | arithmetic only |
 * | perch-around    | isEndToEnd         | exact     | comparisons only |
 * | perch-around    | shouldRouteAround  | exact     | boolean logic only |
 * | perch-around    | routePivot         | exact     | arithmetic only |
 * | perch-around    | planAroundPath     | tolerance | computeArcCum uses sin/cos/hypot |
 * | perch-around    | aroundPose         | tolerance | normalAngleDeg uses atan2 |
 * | perch-around    | resumeAroundRoute  | exact     | arithmetic on given fields, no trig call |
 * | perch-around    | resumedPose        | tolerance | delegates to aroundPose on the curve |
 * | perch-around    | resumedBaseS       | exact     | arithmetic only |
 * | perch-handoff   | planRunSeatY       | exact     | Math.max only |
 * | perch-handoff   | planStartSeatY     | exact     | branch only |
 * | perch-handoff   | planMountSeatY     | exact     | delegates to planFocus/planStartSeatY |
 * | perch-handoff   | liveLastSeat       | exact     | arithmetic only |
 * | perch-handoff   | initialPerchHandoff| exact     | constant |
 * | perch-handoff   | planFocus          | exact     | branch + arithmetic |
 * | perch-handoff   | applyFocusBlur     | exact     | object spread only |
 * | perch-handoff   | applyDragTrack     | exact     | object spread only |
 * | perch-handoff   | applyDragRelease   | exact     | object spread only |
 * | perch-handoff   | selectsOnRelease   | exact     | boolean logic only |
 * | perch-handoff   | planDragRelease    | exact     | comparisons only |
 * | perch-handoff   | planApproach       | exact     | delegates to shouldSnapToSeat/traverseDurationMs |
 * | perch-handoff   | isFarGrab          | exact     | comparison only |
 * | perch-handoff   | planFarSample      | exact     | arithmetic + comparisons, delegates to chaseTargetX |
 * | perch-handoff   | stepToward         | exact     | arithmetic + comparisons only |
 * | perch-handoff   | sanitizeRunSpeed   | exact     | comparisons only |
 * | perch-handoff   | focusFromSlot      | exact     | branch only |
 * | perch-handoff   | initialReleaseState| exact     | constant |
 * | perch-handoff   | reduceRelease      | exact     | branch only |
 * | pose-dissolve   | planPoseDissolve   | exact     | branch only |
 * | pose-dissolve   | poseDissolveApplyOrder | exact | branch only |
 * | pose-dissolve   | shouldResetIncomingFrame | exact | branch only |
 * | pose-dissolve   | shouldSnapBusyIdleFrameToRest | exact | branch only |
 * | animals         | animalProfile      | exact     | data, no computation |
 *
 * animals.json is not a function-conformance file like the four above: each
 * case is one of the six built-in profiles as the TS registry resolves it
 * (registerBuiltinCompanions, then getCompanion(id)), not a call over swept
 * arguments. Its constants block carries the flattened idle/run/sit sheet
 * grids from sheet-geometry.ts. The animal modules import PNGs, which Node
 * cannot load as ESM on its own; scripts/png-stub-loader.mjs stubs that one
 * specifier shape so the real TypeScript profiles load unmodified - the
 * numbers below come from resolveProfile, never hand-typed.
 *
 * File-size note: perch-around's planAroundPath/aroundPose/resumeAroundRoute/
 * resumedPose/resumedBaseS return or consume an AroundPath (a 33-entry
 * arcCum array plus ~15 more doubles); at ~45 bytes per wrapped float that is
 * ~2-5 KB per case. Their case counts are capped well under the 150-400
 * guideline to keep conformance/around.json under ~400 KB - see
 * deviationsFromSpec in the PR/task notes.
 */
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import path from 'node:path';

import {
  AROUND_MIN_SLOT_COUNT,
  AROUND_SPEED_PT_S,
  isEndToEnd,
  shouldRouteAround,
  routePivot,
  planAroundPath,
  aroundPose,
  resumeAroundRoute,
  resumedPose,
  resumedBaseS,
} from '../packages/tabpet/src/perch-around';
import {
  PERCH_SIZE,
  BAR_MARGIN_H,
  CHASE_TRAIL,
  FACING_DEADBAND,
  CHASE_SLACK,
  TRAVERSE_SPEED_PT_S,
  MIN_TRAVERSE_MS,
  MAX_TRAVERSE_MS,
  tabCenterX,
  nearestSlot,
  glassTargetX,
  chaseTargetX,
  chaseStep,
  travelFacing,
  shouldSnapToSeat,
  traverseDurationMs,
  seatedFootPad,
} from '../packages/tabpet/src/perch-geometry';
import {
  RELEASE_GRACE_MS,
  FAR_GRAB_PT,
  FAR_STEP_MAX_DT_MS,
  planRunSeatY,
  planStartSeatY,
  planMountSeatY,
  liveLastSeat,
  initialPerchHandoff,
  planFocus,
  applyFocusBlur,
  applyDragTrack,
  applyDragRelease,
  planDragRelease,
  selectsOnRelease,
  planApproach,
  isFarGrab,
  planFarSample,
  stepToward,
  sanitizeRunSpeed,
  focusFromSlot,
  initialReleaseState,
  reduceRelease,
} from '../packages/tabpet/src/perch-handoff';
import {
  PUP_POSES,
  POSE_FADE_MS,
  planPoseDissolve,
  poseDissolveApplyOrder,
  shouldResetIncomingFrame,
  shouldSnapBusyIdleFrameToRest,
} from '../packages/tabpet/src/pose-dissolve';
// registers scripts/png-stub-loader.mjs before any animal module (which
// imports PNGs) is loaded below - must run before the dynamic imports, not
// just before they're used.
import './png-stub-loader.mjs';
import {
  DEFAULT_SIT_SHEET,
  IDLE_SHEET_GRID,
  RUN_SHEET_GRID,
} from '../packages/tabpet/src/sheet-geometry';

const root = path.resolve(import.meta.dirname, '..');
const outDir = path.join(root, 'conformance');

// dynamic: these modules import PNGs, which only resolve once the loader
// hook above has registered - a static import would race it.
const { registerBuiltinCompanions } = await import('../packages/tabpet/src/animals/all');
const { getCompanion, companionIds } = await import('../packages/tabpet/src/registry');
registerBuiltinCompanions();

// ---------------------------------------------------------------------------
// wire-format encoding
// ---------------------------------------------------------------------------

/** every float, in args and expect, is {bits, value} - bits is authoritative */
function encodeNumber(x) {
  const buf = Buffer.alloc(8);
  buf.writeDoubleBE(x, 0);
  const bits = buf.toString('hex');
  let value;
  if (Number.isNaN(x)) {
    value = 'NaN';
  } else if (x === Infinity) {
    value = 'Infinity';
  } else if (x === -Infinity) {
    value = '-Infinity';
  } else if (Object.is(x, -0)) {
    value = '-0';
  } else {
    value = x;
  }
  return { bits, value };
}

const isNullish = (x) => x === null || x === undefined;
const encArr = (arr) => (isNullish(arr) ? null : arr.map(encodeNumber));
const encOrNull = (x) => (isNullish(x) ? null : encodeNumber(x));

function encPill(p) {
  if (isNullish(p)) {
    return null;
  }
  return {
    x: encodeNumber(p.x),
    y: encodeNumber(p.y),
    width: encodeNumber(p.width),
    height: encodeNumber(p.height),
  };
}

function encAroundPath(p) {
  return {
    exitSide: p.exitSide,
    enterSide: p.enterSide,
    facing: p.facing,
    spin: p.spin,
    pivot: encodeNumber(p.pivot),
    seatFeetY: encodeNumber(p.seatFeetY),
    underY: encodeNumber(p.underY),
    cxExit: encodeNumber(p.cxExit),
    cxEnter: encodeNumber(p.cxEnter),
    cy: encodeNumber(p.cy),
    a: encodeNumber(p.a),
    b: encodeNumber(p.b),
    feetX0: encodeNumber(p.feetX0),
    targetFeetX: encodeNumber(p.targetFeetX),
    arcCum: p.arcCum.map(encodeNumber),
    arcLen: encodeNumber(p.arcLen),
    legs: p.legs.map(encodeNumber),
    totalLen: encodeNumber(p.totalLen),
    totalMs: encodeNumber(p.totalMs),
  };
}

function encResumedRoute(r) {
  return {
    base: encAroundPath(r.base),
    startS: encodeNumber(r.startS),
    endS: encodeNumber(r.endS),
    dir: r.dir,
    curveLen: encodeNumber(r.curveLen),
    tailFromFeetX: encodeNumber(r.tailFromFeetX),
    tailToFeetX: encodeNumber(r.tailToFeetX),
    tailLen: encodeNumber(r.tailLen),
    totalLen: encodeNumber(r.totalLen),
    totalMs: encodeNumber(r.totalMs),
    facing: r.facing,
    endRotation: encodeNumber(r.endRotation),
  };
}

const encPose = (pose) => ({
  x: encodeNumber(pose.x),
  seatY: encodeNumber(pose.seatY),
  rotation: encodeNumber(pose.rotation),
});

function encChaseStep(r) {
  return { target: encOrNull(r.target), facing: r.facing };
}

function encHandoff(h) {
  return { lastTab: h.lastTab, lastX: encOrNull(h.lastX), lastSeat: encodeNumber(h.lastSeat) };
}

function encFocusPlan(plan) {
  return {
    kind: plan.kind,
    fromX: encodeNumber(plan.fromX),
    targetX: encodeNumber(plan.targetX),
    fromSeatY: encodeNumber(plan.fromSeatY),
    runSeatY: encodeNumber(plan.runSeatY),
    next: encHandoff(plan.next),
    commitsHandoff: plan.commitsHandoff,
  };
}

// plain objects with a "kind"/"type" string - no wrapped floats live in any
// of these three unions, so no encodeNumber is needed here
const encDragReleasePlan = (r) =>
  r.kind === 'home' ? { kind: 'home' } : { kind: 'await', slot: r.slot };

const encApproachPlan = (r) =>
  r.kind === 'spring'
    ? { kind: 'spring' }
    : { kind: 'run', durationMs: encodeNumber(r.durationMs) };

const encFarSamplePlan = (r) =>
  r.kind === 'end'
    ? { kind: 'end' }
    : { kind: 'track', target: encodeNumber(r.target), facing: r.facing };

const encReleasePending = (p) =>
  p === null ? null : { fromSlot: p.fromSlot, slot: p.slot, generation: p.generation };

const encReleaseState = (s) => ({ pending: encReleasePending(s.pending), arrival: s.arrival });

const encReduceReleaseResult = (r) => ({ state: encReleaseState(r.state), effect: r.effect });

function encPoseDissolvePlan(plan) {
  const out = {};
  for (const pose of PUP_POSES) {
    const layer = plan[pose];
    const opacity =
      layer.opacity.kind === 'fade-out'
        ? { kind: 'fade-out', durationMs: encodeNumber(layer.opacity.durationMs) }
        : { kind: layer.opacity.kind };
    out[pose] = { opacity, z: layer.z };
  }
  return out;
}

// ---------------------------------------------------------------------------
// deterministic combination sampling (no randomness - fixed index stepping)
// ---------------------------------------------------------------------------

function cartesianCount(arrays) {
  return arrays.reduce((acc, a) => acc * a.length, 1);
}

function tupleAt(arrays, index) {
  const tuple = Array.from({ length: arrays.length });
  let idx = index;
  for (let i = arrays.length - 1; i >= 0; i -= 1) {
    const len = arrays[i].length;
    tuple[i] = arrays[i][idx % len];
    idx = Math.floor(idx / len);
  }
  return tuple;
}

function gcd(a, b) {
  let x = a;
  let y = b;
  while (y !== 0) {
    [x, y] = [y, x % y];
  }
  return x;
}

/** full cartesian product if it fits under cap, else `cap` samples at a
 *  fixed stride coprime with the total (deterministic, no RNG). A stride
 *  that shares a factor with a radix (an array's length) revisits only a
 *  subset of that dimension's values across the whole sample - coprime with
 *  the total guarantees coprime with every radix too, since each radix
 *  divides the total. */
function combosCapped(arrays, cap) {
  const total = cartesianCount(arrays);
  if (total === 0) {
    return [];
  }
  if (total <= cap) {
    return Array.from({ length: total }, (_, i) => tupleAt(arrays, i));
  }
  let stride = Math.max(1, Math.floor(total / cap));
  while (gcd(stride, total) !== 1) {
    stride += 1;
  }
  const out = [];
  let idx = 0;
  for (let i = 0; i < cap; i += 1) {
    out.push(tupleAt(arrays, idx));
    idx = (idx + stride) % total;
  }
  return out;
}

/** throws (before any file is written) if `items` - {a, r} pairs of the raw
 *  call args and raw (pre-encoding) result - miss a required output class.
 *  Checked against the raw result, not the wire-encoded one, since bits/NaN
 *  wrapping would defeat a simple boolean/null predicate. */
function assertOutputClasses(label, items, classifiers) {
  const missing = Object.entries(classifiers)
    .filter(([, pred]) => !items.some(pred))
    .map(([name]) => name);
  if (missing.length > 0) {
    throw new Error(`${label}: generated cases miss output class(es): ${missing.join(', ')}`);
  }
}

/** combines a hand-written MUST-HIT list with a sampled list, computes the
 *  real result for every case before any wire encoding, asserts required
 *  output classes against the raw results, then encodes to fixture shape */
function buildCases(fn, compare, mustHit, sampled, call, encodeArgs, encodeExpect, classifiers) {
  const items = [...mustHit, ...sampled].map((a) => ({ a, r: call(a) }));
  if (classifiers) {
    assertOutputClasses(fn, items, classifiers);
  }
  return items.map(({ a, r }) => ({ fn, args: encodeArgs(a), expect: encodeExpect(r), compare }));
}

// ---------------------------------------------------------------------------
// shared value grids
// ---------------------------------------------------------------------------

const SLOT_COUNTS = [0, 1, 2, 3, 5, 12];
const SCREEN_WIDTHS = [0, -0, 1, 30, 320, 375, 402, 402.5, 430, 744, 1024, 1e6, -1e6];
const BASE_X = [0, 100, -50, 12_345.5];

/** non-finite screen width / position - a port that swaps JS Math.min/max
 *  for a comparison-based min/max must diverge on at least one of these */
const NON_FINITE = [Number.NaN, Infinity, -Infinity];

function slotIndexesFor(n) {
  const s = new Set([-1, 0, n]);
  if (n > 0) {
    s.add(n - 1);
  }
  if (n > 2) {
    s.add(Math.floor(n / 2));
  }
  s.add(n + 4);
  return [...s];
}

function slotCentersVariants(n) {
  const variants = [null];
  if (n === 0) {
    return variants;
  }
  variants.push([]);
  const measured = Array.from({ length: n }, (_, i) => 40 + i * 80 + (i % 2 === 0 ? 0 : 0.5));
  variants.push(measured);
  if (n > 1) {
    variants.push(measured.slice(0, n - 1));
  }
  variants.push(Array.from({ length: n }, () => 0));
  return variants;
}

// ---------------------------------------------------------------------------
// perch-geometry
// ---------------------------------------------------------------------------

// MUST-HIT: the `measured` branch (slotCenters[tab] defined) vs the
// even-split fallback, including the two ways the fallback is reached
// (no array, or tab out of the array's range) - plus F3 non-finite width
// n fixed at 5 (only attached to the n===5 loop iteration below)
const TAB_CENTER_MUST_HIT = [
  [1, 402, [40, 120, 200]], // measured branch
  [1, 402, undefined], // fallback: no slotCenters array
  [-1, 402, [40, 120, 200]], // fallback: negative tab out of range
  [5, 402, [40, 120, 200]], // fallback: tab >= slotCenters.length
  ...NON_FINITE.map((w) => [1, w, undefined]),
];

function genTabCenterX() {
  const cases = [];
  for (const n of SLOT_COUNTS) {
    const tabs = slotIndexesFor(n);
    const centersVariants = slotCentersVariants(n);
    const sampled = combosCapped([tabs, SCREEN_WIDTHS, centersVariants], 30);
    const mustHit = n === 5 ? TAB_CENTER_MUST_HIT : [];
    cases.push(
      ...buildCases(
        'tabCenterX',
        'exact',
        mustHit,
        sampled,
        ([tab, width, centers]) => tabCenterX(tab, width, n, centers ?? undefined),
        ([tab, width, centers]) => ({
          tab,
          screenWidth: encodeNumber(width),
          slotCount: n,
          slotCenters: encArr(centers),
        }),
        encodeNumber,
        // a class is only satisfied by a case that executes the branch it
        // names - checked against the same condition tabCenterX itself branches on
        n === 5
          ? {
              'measured center used': ({ a }) => a[2]?.[a[0]] !== undefined,
              'even split used': ({ a }) => a[2]?.[a[0]] === undefined,
            }
          : undefined
      )
    );
  }
  return cases;
}

// n fixed at 5 (only attached to the n===5 loop iteration below) - x set to
// the exact even-split center of slot 0/2/4 (first/middle/last of 5) so the
// MUST-HIT list itself, not luck of sampling, produces each class
function nearestSlotMustHit() {
  const width = 402;
  const n = 5;
  const centerOf = (slot) => tabCenterX(slot, width, n) + PERCH_SIZE / 2;
  return [
    [centerOf(0), width, undefined], // first slot
    [centerOf(2), width, undefined], // middle slot
    [centerOf(4), width, undefined], // last slot
    ...NON_FINITE.map((x) => [x, width, undefined]),
    ...NON_FINITE.map((w) => [200, w, undefined]),
    // a measured slotCenters array with a non-finite first entry (rest
    // finite) and one whose entries are all non-finite - every per-slot
    // distance in the loop becomes NaN, so the comparison-based `best` never
    // updates and the result stays its initial value (slot 0)
    [200, width, [Number.NaN, 120, 200, 280, 360]],
    [200, width, [Number.NaN, Number.NaN, Number.NaN, Number.NaN, Number.NaN]],
  ];
}

function genNearestSlot() {
  const cases = [];
  for (const n of SLOT_COUNTS) {
    const centersVariants = slotCentersVariants(n);
    const sampled = combosCapped([SCREEN_WIDTHS, SCREEN_WIDTHS, centersVariants], 25);
    const mustHit = n === 5 ? nearestSlotMustHit() : [];
    cases.push(
      ...buildCases(
        'nearestSlot',
        'exact',
        mustHit,
        sampled,
        ([x, width, centers]) => nearestSlot(x, width, n, centers ?? undefined),
        ([x, width, centers]) => ({
          x: encodeNumber(x),
          screenWidth: encodeNumber(width),
          slotCount: n,
          slotCenters: encArr(centers),
        }),
        (r) => r,
        n === 5
          ? {
              'first-slot-selected': ({ r }) => r === 0,
              'middle-slot-selected': ({ r }) => r === 2,
              'last-slot-selected': ({ r }) => r === 4,
              'non-finite input': ({ a }) =>
                !Number.isFinite(a[0]) ||
                !Number.isFinite(a[1]) ||
                (a[2] ?? []).some((c) => !Number.isFinite(c)),
            }
          : undefined
      )
    );
  }
  return cases;
}

// NaN and the infinities as finger x and as screen width - these are what
// catch a comparison-based min/max (Math.min/max propagate NaN, a
// comparison-based swap-in does not). The tie below lands both clamp bounds
// on plus zero, so it cannot tell any min/max implementation apart; signed
// zero itself is covered by the Swift JSMathTests only, not here.
const GLASS_TARGET_MUST_HIT = [
  ...NON_FINITE.map((x) => [x, 402]),
  ...NON_FINITE.map((w) => [27, w]),
  [27, 54], // clamp tie, both bounds +0
];

function genGlassTargetX() {
  return buildCases(
    'glassTargetX',
    'exact',
    GLASS_TARGET_MUST_HIT,
    combosCapped([SCREEN_WIDTHS, SCREEN_WIDTHS], 200),
    ([fingerX, screenWidth]) => glassTargetX(fingerX, screenWidth),
    ([fingerX, screenWidth]) => ({
      fingerX: encodeNumber(fingerX),
      screenWidth: encodeNumber(screenWidth),
    }),
    encodeNumber
  );
}

// NaN and the infinities as glass x and as screen width - what actually
// catches a comparison-based min/max. The two ties below (direction *
// CHASE_TRAIL cancels glassX exactly, landing the clamp target at 0 while
// screenWidth - PERCH_SIZE is also 0) put both clamp bounds on plus zero
// either way, so they cannot distinguish a min/max implementation; signed
// zero itself is covered by the Swift JSMathTests only, not here.
const CHASE_TARGET_MUST_HIT = [
  ...NON_FINITE.map((x) => [x, 1, 402]),
  ...NON_FINITE.map((w) => [100, 1, w]),
  [18, 1, 54], // clamp tie, both bounds +0
  [-18, -1, 54], // clamp tie, both bounds +0
];

function genChaseTargetX() {
  return buildCases(
    'chaseTargetX',
    'exact',
    CHASE_TARGET_MUST_HIT,
    combosCapped([SCREEN_WIDTHS, [1, -1], SCREEN_WIDTHS], 350),
    ([glassX, direction, screenWidth]) => chaseTargetX(glassX, direction, screenWidth),
    ([glassX, direction, screenWidth]) => ({
      glassX: encodeNumber(glassX),
      direction,
      screenWidth: encodeNumber(screenWidth),
    }),
    encodeNumber
  );
}

// CHASE_TRAIL=18, CHASE_SLACK=4: TRAIL-SLACK=14, TRAIL=18, TRAIL+SLACK=22
const CHASE_GAPS = [
  0, -0, 1, -1, 4, -4, 14, -14, 18, -18, 22, -22, 23, -23, 0.5, -0.5, 100, -100, 1e6, -1e6,
];

// MUST-HIT: a null target with each currentFacing (gap inside the
// hysteresis threshold), and a non-null target for each returned facing
// (gap beyond threshold, both signs)
const CHASE_STEP_MUST_HIT = [
  [0, 0, 1, false], // null target, currentFacing 1
  [0, 0, -1, false], // null target, currentFacing -1
  [100, 0, 1, true], // gap >= 0 -> facing 1, non-null target
  [-100, 0, -1, true], // gap < 0 -> facing -1, non-null target
  // NaN/Infinity as glassX (via a non-finite gap, currentX stays finite)
  ...NON_FINITE.map((gap) => [gap, 0, 1, true]),
  // NaN/Infinity as currentX (glassX becomes non-finite too, since it is
  // currentX + gap - there is no way to hold glassX finite while currentX is not)
  ...NON_FINITE.map((currentX) => [0, currentX, 1, true]),
];

function genChaseStep() {
  return buildCases(
    'chaseStep',
    'exact',
    CHASE_STEP_MUST_HIT,
    combosCapped([CHASE_GAPS, BASE_X, [1, -1], [true, false]], 280),
    ([gap, currentX, currentFacing, chasing]) =>
      chaseStep(currentX + gap, currentX, currentFacing, chasing),
    ([gap, currentX, currentFacing, chasing]) => ({
      glassX: encodeNumber(currentX + gap),
      currentX: encodeNumber(currentX),
      currentFacing,
      chasing,
    }),
    encChaseStep,
    {
      'target-null': ({ r }) => r.target === null,
      'target-nonnull-facing-right': ({ r }) => r.target !== null && r.facing === 1,
      'target-nonnull-facing-left': ({ r }) => r.target !== null && r.facing === -1,
      'non-finite input': ({ a }) => !Number.isFinite(a[0] + a[1]) || !Number.isFinite(a[1]),
    }
  );
}

// FACING_DEADBAND=3
const FACING_DELTAS = [0, -0, 1, -1, 2, -2, 3, -3, 4, -4, 0.5, -0.5, 100, -100, 1e6, -1e6];
const FACING_BASE_X = [0, 100, -50, 12_345.5, -999.25];

// MUST-HIT: both returned facings, and holding inside the deadband with
// each current facing
const TRAVEL_FACING_MUST_HIT = [
  [0, 0, 1], // held, currentFacing 1
  [0, 0, -1], // held, currentFacing -1
  [10, 0, 1], // beyond deadband, positive -> facing 1
  [-10, 0, -1], // beyond deadband, negative -> facing -1
  // held against the sign: inside the deadband, but currentFacing disagrees
  // with the sign of delta - held wins, the disagreement is not resolved
  [2, 0, -1], // delta positive, currentFacing -1
  [-2, 0, 1], // delta negative, currentFacing 1
  // NaN/Infinity as targetX (via a non-finite delta, currentX finite)
  ...NON_FINITE.map((delta) => [delta, 0, 1]),
  // NaN/Infinity as currentX (targetX becomes non-finite too, same as chaseStep)
  ...NON_FINITE.map((currentX) => [0, currentX, 1]),
];

function genTravelFacing() {
  return buildCases(
    'travelFacing',
    'exact',
    TRAVEL_FACING_MUST_HIT,
    combosCapped([FACING_DELTAS, FACING_BASE_X, [1, -1]], 200),
    ([delta, currentX, currentFacing]) => travelFacing(currentX + delta, currentX, currentFacing),
    ([delta, currentX, currentFacing]) => ({
      targetX: encodeNumber(currentX + delta),
      currentX: encodeNumber(currentX),
      currentFacing,
    }),
    (r) => r,
    {
      'facing-right': ({ r }) => r === 1,
      'facing-left': ({ r }) => r === -1,
      'held-currentFacing-right': ({ a, r }) => r === 1 && a[2] === 1 && Math.abs(a[0]) <= 3,
      'held-currentFacing-left': ({ a, r }) => r === -1 && a[2] === -1 && Math.abs(a[0]) <= 3,
      // held inside the deadband while currentFacing disagrees with the
      // sign of delta, for both facings - proves held wins over the sign
      'held against the sign (facing right)': ({ a, r }) =>
        r === 1 && a[2] === 1 && a[0] < 0 && Math.abs(a[0]) <= 3,
      'held against the sign (facing left)': ({ a, r }) =>
        r === -1 && a[2] === -1 && a[0] > 0 && Math.abs(a[0]) <= 3,
      'non-finite input': ({ a }) => !Number.isFinite(a[0] + a[1]) || !Number.isFinite(a[1]),
    }
  );
}

// PERCH_SIZE=54: the threshold itself and its immediate neighbors, explicit
// (not left to the sweep below to happen to land on)
const SHOULD_SNAP_MUST_HIT = [53, 53.99, 54, 54.01, 55];

// PERCH_SIZE=54: sweep tightly around the threshold plus generic edges
function genShouldSnapToSeat() {
  const near = [];
  for (let d = 53; d <= 55; d += 0.05) {
    near.push(Math.round(d * 100) / 100);
  }
  const values = [...new Set([...near, 0, -0, 1, -1, 0.5, -0.5, 2, 100, -100, 1e6, -1e6])];
  return buildCases(
    'shouldSnapToSeat',
    'exact',
    // NaN and the infinities as distancePt
    [...SHOULD_SNAP_MUST_HIT, ...NON_FINITE],
    values,
    (distancePt) => shouldSnapToSeat(distancePt),
    (distancePt) => ({ distancePt: encodeNumber(distancePt) }),
    (r) => r,
    {
      true: ({ r }) => r === true,
      false: ({ r }) => r === false,
      'non-finite input': ({ a }) => !Number.isFinite(a),
    }
  );
}

// TRAVERSE_SPEED_PT_S=340, MIN_TRAVERSE_MS=400, MAX_TRAVERSE_MS=2200:
// 136 = floor boundary distance at default speed, 748 = ceiling boundary
const TRAVERSE_DISTANCES = [
  0, -0, 1, -1, 80, -80, 100_000, -100_000, 296, -296, 600, -600, 133.5, -133.5, 136, -136, 748,
  -748,
];
const TRAVERSE_SPEEDS = [null, 340, 170, 680, 0, -170, 1e6];

// NaN and the infinities as distance and as speed
const TRAVERSE_DURATION_MUST_HIT = [
  ...NON_FINITE.map((d) => [d, null]),
  ...NON_FINITE.map((s) => [100, s]),
];

function genTraverseDurationMs() {
  return buildCases(
    'traverseDurationMs',
    'exact',
    TRAVERSE_DURATION_MUST_HIT,
    combosCapped([TRAVERSE_DISTANCES, TRAVERSE_SPEEDS], 160),
    ([distancePt, speedPtS]) =>
      speedPtS === null ? traverseDurationMs(distancePt) : traverseDurationMs(distancePt, speedPtS),
    ([distancePt, speedPtS]) => ({
      distancePt: encodeNumber(distancePt),
      speedPtS: encOrNull(speedPtS),
    }),
    encodeNumber
  );
}

const FOOT_PADS = [0, -0, 1, -1, 11, 11.025, 27, -5, 100, -100, 0.5, -0.5, 1e6, -1e6];
const SCALES = [0, -0, 1, -1, 0.72, 1.25, 2, -1, 0.001, 100, -100, 1e6, -1e6, 0.5];

// NaN and the infinities as footPad (a distance) and as scale - what
// catches a comparison-based min/max the way a bare arithmetic port would not
const SEATED_FOOT_PAD_MUST_HIT = [
  ...NON_FINITE.map((footPad) => [footPad, 1]),
  ...NON_FINITE.map((scale) => [11, scale]),
];

function genSeatedFootPad() {
  return buildCases(
    'seatedFootPad',
    'exact',
    SEATED_FOOT_PAD_MUST_HIT,
    combosCapped([FOOT_PADS, SCALES], 196),
    ([footPad, scale]) => seatedFootPad(footPad, scale),
    ([footPad, scale]) => ({ footPad: encodeNumber(footPad), scale: encodeNumber(scale) }),
    encodeNumber,
    { 'non-finite input': ({ a }) => !Number.isFinite(a[0]) || !Number.isFinite(a[1]) }
  );
}

function genPerchGeometry() {
  return [
    ...genTabCenterX(),
    ...genNearestSlot(),
    ...genGlassTargetX(),
    ...genChaseTargetX(),
    ...genChaseStep(),
    ...genTravelFacing(),
    ...genShouldSnapToSeat(),
    ...genTraverseDurationMs(),
    ...genSeatedFootPad(),
  ];
}

// ---------------------------------------------------------------------------
// perch-around
// ---------------------------------------------------------------------------

const AROUND_SLOT_IDX = [-1, 0, 1, 2, 3, 4, 5, 11, 12, 16];

// MUST-HIT: both directions of the true case, plus one false case per broken
// condition (slotCount < AROUND_MIN_SLOT_COUNT, min !== 0, max !== slotCount-1)
const IS_END_TO_END_MUST_HIT = [
  [0, 4, 5], // true
  [4, 0, 5], // true, reversed
  [0, 1, 2], // false: slotCount below the minimum
  [1, 4, 5], // false: min !== 0
  [0, 2, 5], // false: max !== slotCount - 1 (a mid stop)
  [0, 0, 5], // false: same slot
  [-1, 4, 5], // false: negative index
];

function genIsEndToEnd() {
  return buildCases(
    'isEndToEnd',
    'exact',
    IS_END_TO_END_MUST_HIT,
    combosCapped([AROUND_SLOT_IDX, AROUND_SLOT_IDX, SLOT_COUNTS], 150),
    ([fromSlot, toSlot, slotCount]) => isEndToEnd(fromSlot, toSlot, slotCount),
    ([fromSlot, toSlot, slotCount]) => ({ fromSlot, toSlot, slotCount }),
    (r) => r,
    { true: ({ r }) => r === true, false: ({ r }) => r === false }
  );
}

const PILL_A = { x: 24, y: 800, width: 354, height: 64 };
const SLOT_TRIPLES = [
  [0, 4, 5],
  [4, 0, 5],
  [0, 3, 5],
  [1, 4, 5],
  [0, 2, 3],
  [0, 1, 2],
  [0, 0, 5],
  [2, 2, 5],
  [0, 11, 12],
  [11, 0, 12],
  [-1, 4, 5],
  [0, 12, 5],
];
const FLIGHT_LIFTS = [0, -0, 1, -1, 14, 100, -50];
const PILL_VARIANTS = [PILL_A, null];

// MUST-HIT: the true case, plus one false case per condition shouldRouteAround
// ANDs together (isEndToEnd, aroundRoute, flightLift === 0, pill defined, !reduceMotion)
const SHOULD_ROUTE_AROUND_MUST_HIT = [
  [[0, 4, 5], true, 0, PILL_A, false], // true
  [[0, 2, 5], true, 0, PILL_A, false], // false: not end-to-end
  [[0, 4, 5], false, 0, PILL_A, false], // false: aroundRoute off
  [[0, 4, 5], true, 14, PILL_A, false], // false: flightLift !== 0
  [[0, 4, 5], true, 0, null, false], // false: pill null
  [[0, 4, 5], true, 0, undefined, false], // false: pill undefined
  [[0, 4, 5], true, 0, PILL_A, true], // false: reduceMotion on
  // flightLift NaN and 0.5 - neither is === 0, so both must read false;
  // NaN is what catches a comparison-based (rather than ===) check
  [[0, 4, 5], true, Number.NaN, PILL_A, false], // false: flightLift NaN
  [[0, 4, 5], true, 0.5, PILL_A, false], // false: flightLift 0.5, non-zero
];

function genShouldRouteAround() {
  return buildCases(
    'shouldRouteAround',
    'exact',
    SHOULD_ROUTE_AROUND_MUST_HIT,
    combosCapped([SLOT_TRIPLES, [true, false], FLIGHT_LIFTS, PILL_VARIANTS, [true, false]], 180),
    ([triple, aroundRoute, flightLift, pill, reduceMotion]) => {
      const [fromSlot, toSlot, slotCount] = triple;
      return shouldRouteAround({
        fromSlot,
        toSlot,
        slotCount,
        aroundRoute,
        flightLift,
        pill,
        reduceMotion,
      });
    },
    ([triple, aroundRoute, flightLift, pill, reduceMotion]) => {
      const [fromSlot, toSlot, slotCount] = triple;
      return {
        fromSlot,
        toSlot,
        slotCount,
        aroundRoute,
        flightLift: encodeNumber(flightLift),
        pill: encPill(pill),
        reduceMotion,
      };
    },
    (r) => r,
    {
      true: ({ r }) => r === true,
      false: ({ r }) => r === false,
      'non-finite input': ({ a }) => !Number.isFinite(a[2]),
    }
  );
}

function genRoutePivot() {
  const cases = [];
  for (const [spriteScale, footPad] of combosCapped([SCALES, FOOT_PADS], 196)) {
    const result = routePivot(spriteScale, footPad);
    cases.push({
      fn: 'routePivot',
      args: { spriteScale: encodeNumber(spriteScale), footPad: encodeNumber(footPad) },
      expect: encodeNumber(result),
      compare: 'exact', // arithmetic only, no trig
    });
  }
  return cases;
}

// PERCH_SIZE, duplicated locally so this module has no import-order coupling
// to perch-geometry beyond what planAroundPath itself already needs
const PERCH_SIZE_CONST = 54;

// explicit paths (never sampled) - both travel directions, >=2 sprite
// scales/foot pads/seat offsets/pill frames, and one start === target path.
// Case counts below stay modest because every AroundPath case embeds the
// whole object (a 33-entry arcCum array plus ~15 more doubles), but the
// budget here is ~1 MB (see file-size note in the header), far above the
// ~400 KB geometry/handoff/pose-dissolve budget.
const AROUND_PILL_1 = { x: 24, y: 800, width: 354, height: 64 };
const AROUND_PILL_2 = { x: 0, y: 500, width: 300, height: 40 };

const AROUND_PATH_ARGS = [
  {
    fromX: 40,
    targetX: 320,
    pill: AROUND_PILL_1,
    windowWidth: 402,
    spriteScale: 0.72,
    footPad: 11,
    headPad: 0,
    seatOffset: -5,
  },
  {
    fromX: 320,
    targetX: 40,
    pill: AROUND_PILL_2,
    windowWidth: 402,
    spriteScale: 1.25,
    footPad: 20,
    headPad: 10,
    seatOffset: 6,
  },
  {
    fromX: 0,
    targetX: 100,
    pill: AROUND_PILL_1,
    windowWidth: 402,
    spriteScale: 1,
    footPad: 11,
    headPad: 0,
    seatOffset: 0,
  },
  {
    fromX: 100,
    targetX: 0,
    pill: AROUND_PILL_2,
    windowWidth: 402,
    spriteScale: 0.72,
    footPad: 20,
    headPad: 10,
    seatOffset: 6,
  },
  {
    // start === target: fromX and targetX coincide
    fromX: 100,
    targetX: 100,
    pill: AROUND_PILL_1,
    windowWidth: 402,
    spriteScale: 1,
    footPad: 11,
    headPad: 0,
    seatOffset: 0,
  },
];

// degenerate around geometry, kept as a separate small list rather than
// merged into AROUND_PATH_ARGS/AROUND_SAMPLE_PATHS - it only feeds
// genPlanAroundPath and genAroundPose, not resumeAroundRoute/resumedPose/
// resumedBaseS, to stay inside the ~1.2MB around.json budget. Numbers below
// are worked out from planAroundPath's own formulas (R = height/2, cxExit/
// cxEnter = pill.x + R or pill.x + width - R, leg lengths from |cx - feetX|),
// not guessed - see degenerateResults in the PR/task notes for what
// aroundPose actually returns at s=0 and totalLen on each.
const DEGENERATE_PILL = { x: 24, y: 800, width: 354, height: 64 }; // R=32: cxExit=56, cxEnter=346
const DEGENERATE_ARGS_BASE = {
  windowWidth: 402,
  spriteScale: 1,
  footPad: 11,
  headPad: 0,
  seatOffset: 0,
};

const DEGENERATE_PATH_ARGS = [
  // leg 1 zero length: feetX0 (fromX + PERCH_SIZE/2 = 29+27=56) === cxExit (56)
  { ...DEGENERATE_ARGS_BASE, fromX: 29, targetX: 300, pill: DEGENERATE_PILL },
  // leg 5 zero length: targetFeetX (targetX + PERCH_SIZE/2 = 319+27=346) === cxEnter (346)
  { ...DEGENERATE_ARGS_BASE, fromX: 50, targetX: 319, pill: DEGENERATE_PILL },
  // leg 3 zero length: pill width === height (64 === 64), so cxExit === cxEnter (both 32)
  {
    ...DEGENERATE_ARGS_BASE,
    fromX: 0,
    targetX: 200,
    pill: { x: 0, y: 800, width: 64, height: 64 },
  },
  // pill height 0: R=0, the ellipse's horizontal semi-axis a=R collapses to 0
  {
    ...DEGENERATE_ARGS_BASE,
    fromX: 0,
    targetX: 200,
    pill: { x: 0, y: 800, width: 300, height: 0 },
  },
  // pill width 0: cxExit/cxEnter land outside the pill's own (zero) span
  {
    ...DEGENERATE_ARGS_BASE,
    fromX: 0,
    targetX: 200,
    pill: { x: 100, y: 800, width: 0, height: 64 },
  },
  // pill narrower than it is tall: R (32) exceeds width/2 (10), same cap crossing as width 0
  {
    ...DEGENERATE_ARGS_BASE,
    fromX: 0,
    targetX: 200,
    pill: { x: 100, y: 800, width: 20, height: 64 },
  },
];
const DEGENERATE_SAMPLE_PATHS = DEGENERATE_PATH_ARGS.map(planAroundPath);

// kept small (cap 6, trimmed from 15 to make room for P4's degenerate must-hit
// paths under the around.json size budget) as extra numeric variety around
// the explicit list above
function planAroundPathArgsList() {
  const AROUND_SCALES = [0.72, 1, 1.25];
  const AROUND_FOOT_PADS = [11, 0, 20];
  const AROUND_SEAT_OFFSETS = [-5, 0, 6];
  const AROUND_HEAD_PADS = [0, 10];
  const AROUND_FROM_TARGET = [
    [40, 320],
    [320, 40],
    [0, 100],
    [100, 0],
  ];
  return combosCapped(
    [
      [AROUND_PILL_1, AROUND_PILL_2],
      AROUND_SCALES,
      AROUND_FOOT_PADS,
      AROUND_SEAT_OFFSETS,
      AROUND_HEAD_PADS,
      AROUND_FROM_TARGET,
    ],
    6
  ).map(([pill, spriteScale, footPad, seatOffset, headPad, fromTarget]) => ({
    fromX: fromTarget[0],
    targetX: fromTarget[1],
    pill,
    windowWidth: 402,
    spriteScale,
    footPad,
    headPad,
    seatOffset,
  }));
}

function encodePlanAroundPathArgs(args) {
  return {
    fromX: encodeNumber(args.fromX),
    targetX: encodeNumber(args.targetX),
    pill: encPill(args.pill),
    windowWidth: encodeNumber(args.windowWidth),
    spriteScale: encodeNumber(args.spriteScale),
    footPad: encodeNumber(args.footPad),
    headPad: encodeNumber(args.headPad),
    seatOffset: encodeNumber(args.seatOffset),
  };
}

function genPlanAroundPath() {
  return buildCases(
    'planAroundPath',
    'tolerance',
    [...AROUND_PATH_ARGS, ...DEGENERATE_PATH_ARGS],
    planAroundPathArgsList(),
    (args) => planAroundPath(args),
    encodePlanAroundPathArgs,
    (r) => encAroundPath(r),
    {
      'exitSide--1': ({ r }) => r.exitSide === -1,
      'exitSide-+1': ({ r }) => r.exitSide === 1,
      'spin--1': ({ r }) => r.spin === -1,
      'spin-+1': ({ r }) => r.spin === 1,
      'facing--1': ({ r }) => r.facing === -1,
      'facing-+1': ({ r }) => r.facing === 1,
      'direction-forward': ({ a }) => a.targetX > a.fromX,
      'direction-backward': ({ a }) => a.targetX < a.fromX,
      'start-equals-target': ({ a }) => a.fromX === a.targetX,
      // degenerate around geometry, checked against the real geometry
      // (leg lengths / cap centers), not the specific numbers chosen above
      'leg1-zero-departure-at-exit-cap': ({ r }) => r.legs[0] === 0 && r.feetX0 === r.cxExit,
      'leg5-zero-target-at-entry-cap': ({ r }) =>
        r.legs[4] === r.legs[3] && r.targetFeetX === r.cxEnter,
      'leg3-zero-width-eq-height': ({ a, r }) =>
        r.legs[2] === r.legs[1] && a.pill.width === a.pill.height,
      'pill-height-zero': ({ a }) => a.pill.height === 0,
      'pill-width-zero': ({ a }) => a.pill.width === 0,
      'pill-narrower-than-tall': ({ a }) => a.pill.width < a.pill.height,
    }
  );
}

/** the AroundPath fixtures shared by aroundPose, resumeAroundRoute,
 *  resumedPose and resumedBaseS below - one per AROUND_PATH_ARGS entry, so
 *  exitSide/spin/facing and both travel directions carry through to every
 *  consumer without relying on sampling to hit them */
const AROUND_SAMPLE_PATHS = AROUND_PATH_ARGS.map(planAroundPath);

/** every leg's interior midpoint plus every boundary (0, the 4 seams,
 *  totalLen) - the minimum s coverage P4 requires on every degenerate path */
function sDegenerateValuesFor(arcPath) {
  const [s1, s2, s3, s4, total] = arcPath.legs;
  return [
    0,
    s1 / 2,
    s1,
    s1 + (s2 - s1) / 2,
    s2,
    s2 + (s3 - s2) / 2,
    s3,
    s3 + (s4 - s3) / 2,
    s4,
    s4 + (total - s4) / 2,
    total,
  ];
}

/** sDegenerateValuesFor plus the clamp cases below 0 and above totalLen -
 *  used for the (small, fixed) set of non-degenerate sample paths */
function sValuesFor(arcPath) {
  return [...sDegenerateValuesFor(arcPath), -10, arcPath.totalLen + 10];
}

function genAroundPose() {
  const items = [];
  for (const arcPath of AROUND_SAMPLE_PATHS) {
    for (const s of sValuesFor(arcPath)) {
      items.push([arcPath, s]);
    }
  }
  // NaN and the infinities as s (a position along the path) - one
  // representative path only (every AroundPath case embeds the whole path,
  // so repeating this on all 5 would cost more than the extra coverage is
  // worth); Math.min/Math.max(s, 0/totalLen) propagate NaN, which a
  // comparison-based clamp would not
  for (const s of [Number.NaN, Number.POSITIVE_INFINITY, Number.NEGATIVE_INFINITY]) {
    items.push([AROUND_SAMPLE_PATHS[0], s]);
  }
  // every degenerate path, at s=0, inside each leg, at each boundary and
  // at totalLen (sDegenerateValuesFor - no clamp/non-finite s extras here,
  // to stay inside the around.json size budget)
  for (const arcPath of DEGENERATE_SAMPLE_PATHS) {
    for (const s of sDegenerateValuesFor(arcPath)) {
      items.push([arcPath, s]);
    }
  }
  return buildCases(
    'aroundPose',
    'tolerance',
    items,
    [],
    ([arcPath, s]) => aroundPose(arcPath, s),
    ([arcPath, s]) => ({ path: encAroundPath(arcPath), s: encodeNumber(s) }),
    (r) => encPose(r),
    {
      'exitSide--1': ({ a }) => a[0].exitSide === -1,
      'exitSide-+1': ({ a }) => a[0].exitSide === 1,
      'spin--1': ({ a }) => a[0].spin === -1,
      'spin-+1': ({ a }) => a[0].spin === 1,
      'facing--1': ({ a }) => a[0].facing === -1,
      'facing-+1': ({ a }) => a[0].facing === 1,
      'leg1-interior': ({ a }) => a[1] > 0 && a[1] < a[0].legs[0],
      'leg2-interior': ({ a }) => a[1] > a[0].legs[0] && a[1] < a[0].legs[1],
      'leg3-interior': ({ a }) => a[1] > a[0].legs[1] && a[1] < a[0].legs[2],
      'leg4-interior': ({ a }) => a[1] > a[0].legs[2] && a[1] < a[0].legs[3],
      'leg5-interior': ({ a }) => a[1] > a[0].legs[3] && a[1] < a[0].legs[4],
      'boundary-0': ({ a }) => a[1] === 0,
      'boundary-s1': ({ a }) => a[1] === a[0].legs[0],
      'boundary-s2': ({ a }) => a[1] === a[0].legs[1],
      'boundary-s3': ({ a }) => a[1] === a[0].legs[2],
      'boundary-s4': ({ a }) => a[1] === a[0].legs[3],
      'boundary-total': ({ a }) => a[1] === a[0].legs[4],
      'non-finite input': ({ a }) => !Number.isFinite(a[1]),
    }
  );
}

/** null (on a seat leg), a forward resume, and a backward resume, per
 *  sample path - the forward/backward split comes from the real geometry
 *  (forwardLen vs backwardLen), not a guess, so both attempts are made on
 *  every path and whichever direction wins is whichever it is */
function resumeAroundRouteMustHit() {
  const items = [];
  for (const arcPath of AROUND_SAMPLE_PATHS) {
    const [s1, s2, s3, s4, total] = arcPath.legs;
    const farTarget = arcPath.targetFeetX - PERCH_SIZE_CONST;
    const nearTarget = arcPath.feetX0 + PERCH_SIZE_CONST;
    items.push(
      [arcPath, 0, farTarget], // leg1 (seat) -> null
      [arcPath, s1, farTarget], // seam -> null
      [arcPath, s4, farTarget], // seam -> null
      [arcPath, total, farTarget], // leg5 (seat) -> null
      [arcPath, s4 - 1, nearTarget], // near the far seam, target near departure
      [arcPath, s1 + 1, farTarget], // near the near seam, target near arrival
      [arcPath, s2 + (s3 - s2) / 2, farTarget] // mid-hang interrupt
    );
  }
  // NaN/Infinity as s - one representative path only (every case embeds
  // the whole AroundPath, so repeating this on all 5 costs more than the
  // extra coverage is worth). Infinity/-Infinity both fall outside (s1, s4)
  // so resumeAroundRoute returns null; NaN fails both bounds comparisons and
  // falls through to a concrete (if partly NaN) forward resume, since
  // `backwardLen < forwardLen` on NaN operands is false either way
  const [repPath] = AROUND_SAMPLE_PATHS;
  const repFarTarget = repPath.targetFeetX - PERCH_SIZE_CONST;
  items.push(
    [repPath, Number.NaN, repFarTarget],
    [repPath, Number.POSITIVE_INFINITY, repFarTarget],
    [repPath, Number.NEGATIVE_INFINITY, repFarTarget]
  );
  return items;
}

/** resumeAroundRoute's dir tie - backwardLen === forwardLen exactly.
 *  At mid-hang (s = midpoint of leg 3, the flat hang between cxExit and
 *  cxEnter), s - s1 === s4 - s by construction (leg2 and leg4 are the same
 *  arcLen). Targeting the pill's own center makes
 *  |targetFeetX - cxExit| === |targetFeetX - cxEnter| too (cxExit/cxEnter
 *  are symmetric about the pill center), so backwardLen === forwardLen
 *  exactly - and resumeAroundRoute's `backwardLen < forwardLen ? -1 : 1`
 *  must resume forward on the tie. */
function resumeAroundRouteTieMustHit() {
  return AROUND_PATH_ARGS.map((args, i) => {
    const arcPath = AROUND_SAMPLE_PATHS[i];
    const [, s2, s3] = arcPath.legs;
    const midHangS = s2 + (s3 - s2) / 2;
    const pillCenterTargetX = args.pill.x + args.pill.width / 2 - PERCH_SIZE_CONST / 2;
    return [arcPath, midHangS, pillCenterTargetX];
  });
}

function genResumeAroundRoute() {
  return buildCases(
    'resumeAroundRoute',
    'exact',
    [...resumeAroundRouteMustHit(), ...resumeAroundRouteTieMustHit()],
    [],
    ([base, s, targetX]) => resumeAroundRoute(base, s, targetX),
    ([base, s, targetX]) => ({
      base: encAroundPath(base),
      s: encodeNumber(s),
      targetX: encodeNumber(targetX),
    }),
    (r) => (r === null ? null : encResumedRoute(r)),
    {
      'dir-forward-on-tie': ({ a, r }) => {
        const [base, s, targetX] = a;
        // oxlint-disable-next-line unicorn/no-unreadable-array-destructuring -- only s1/s4 matter here
        const [s1c, , , s4c] = base.legs;
        const targetFeetX = targetX + PERCH_SIZE_CONST / 2;
        const forwardLen = s4c - s + Math.abs(targetFeetX - base.cxEnter);
        const backwardLen = s - s1c + Math.abs(targetFeetX - base.cxExit);
        return r !== null && r.dir === 1 && forwardLen === backwardLen;
      },
      'non-finite input': ({ a }) => !Number.isFinite(a[1]),
      null: ({ r }) => r === null,
      'dir-forward': ({ r }) => r !== null && r.dir === 1,
      'dir-backward': ({ r }) => r !== null && r.dir === -1,
    }
  );
}

/** the non-null resumed routes from resumeAroundRouteMustHit's forward/
 *  backward attempts, shared by resumedPose and resumedBaseS below */
function resumedRouteFixtures() {
  const routes = [];
  for (const arcPath of AROUND_SAMPLE_PATHS) {
    // oxlint-disable-next-line unicorn/no-unreadable-array-destructuring -- only s1/s4 matter here
    const [s1, , , s4] = arcPath.legs;
    const forward = resumeAroundRoute(arcPath, s4 - 1, arcPath.feetX0 + PERCH_SIZE_CONST);
    const backward = resumeAroundRoute(arcPath, s1 + 1, arcPath.targetFeetX - PERCH_SIZE_CONST);
    if (forward) {
      routes.push(forward);
    }
    if (backward) {
      routes.push(backward);
    }
  }
  return routes;
}

function genResumedPose() {
  const items = [];
  for (const route of resumedRouteFixtures()) {
    const uValues = [-5, 0, route.curveLen / 2, route.curveLen, route.curveLen + 1, route.totalLen];
    for (const u of uValues) {
      items.push([route, u]);
    }
  }
  // u above totalLen (upper clamp) - one route per direction, not every
  // route, to keep the AroundPath-embedding case count inside the budget
  const routesByDir = resumedRouteFixtures();
  const forwardRoute = routesByDir.find((route) => route.dir === 1);
  const backwardRoute = routesByDir.find((route) => route.dir === -1);
  for (const route of [forwardRoute, backwardRoute]) {
    if (route) {
      items.push([route, route.totalLen + 5]);
    }
  }
  return buildCases(
    'resumedPose',
    'tolerance',
    items,
    [],
    ([route, u]) => resumedPose(route, u),
    ([route, u]) => ({ route: encResumedRoute(route), u: encodeNumber(u) }),
    (r) => encPose(r),
    {
      'dir-forward': ({ a }) => a[0].dir === 1,
      'dir-backward': ({ a }) => a[0].dir === -1,
      // both directions must each include a case that actually executes
      // resumedPose's tail branch (uc > curveLen), not just any case tagged
      // with that direction
      'dir-forward-tail': ({ a }) => a[0].dir === 1 && a[1] > a[0].curveLen,
      'dir-backward-tail': ({ a }) => a[0].dir === -1 && a[1] > a[0].curveLen,
      'u-below-0-clamped': ({ a }) => a[1] < 0,
      'u-above-totalLen-clamped': ({ a }) => a[1] > a[0].totalLen,
    }
  );
}

function genResumedBaseS() {
  const items = [];
  for (const route of resumedRouteFixtures()) {
    const uValues = [0, route.curveLen / 2, route.curveLen, route.curveLen + 1, route.totalLen];
    for (const u of uValues) {
      items.push([route, u]);
    }
  }
  // u below 0 and above totalLen - one route per direction, same
  // reasoning as genResumedPose above
  const routesByDir = resumedRouteFixtures();
  const forwardRoute = routesByDir.find((route) => route.dir === 1);
  const backwardRoute = routesByDir.find((route) => route.dir === -1);
  for (const route of [forwardRoute, backwardRoute]) {
    if (route) {
      items.push([route, -5], [route, route.totalLen + 5]);
    }
  }
  return buildCases(
    'resumedBaseS',
    'exact',
    items,
    [],
    ([route, u]) => resumedBaseS(route, u),
    ([route, u]) => ({ route: encResumedRoute(route), u: encodeNumber(u) }),
    (r) => (r === null ? null : encodeNumber(r)),
    {
      'u-below-0': ({ a }) => a[1] < 0,
      'u-above-totalLen': ({ a }) => a[1] > a[0].totalLen,
      'dir-forward': ({ a }) => a[0].dir === 1,
      'dir-backward': ({ a }) => a[0].dir === -1,
      'null-result': ({ r }) => r === null,
    }
  );
}

function genPerchAround() {
  return [
    ...genIsEndToEnd(),
    ...genShouldRouteAround(),
    ...genRoutePivot(),
    ...genPlanAroundPath(),
    ...genAroundPose(),
    ...genResumeAroundRoute(),
    ...genResumedPose(),
    ...genResumedBaseS(),
  ];
}

// ---------------------------------------------------------------------------
// perch-handoff (readPerchHandoff / writePerchHandoff / resetPerchHandoffForTest
// are module-state mutators, not pure functions - intentionally not fixtured)
// ---------------------------------------------------------------------------

const SEAT_Y_VALUES = [
  0, -0, 1, -1, 24, -24, 0.5, -0.5, 100, -100, 1e6, -1e6, 12.75, -12.75, -5, -10, -50, -1000, 5, 10,
  50, 1000, 0.001, -0.001,
];

function genPlanRunSeatY() {
  return buildCases(
    'planRunSeatY',
    'exact',
    NON_FINITE, // NaN and the infinities as fromSeatY (a distance)
    SEAT_Y_VALUES,
    (fromSeatY) => planRunSeatY(fromSeatY),
    (fromSeatY) => ({ fromSeatY: encodeNumber(fromSeatY) }),
    encodeNumber,
    { 'non-finite input': ({ a }) => !Number.isFinite(a) }
  );
}

const HANDOFF_KINDS = [
  'run-chase',
  'reduced-chase',
  'snap-to-seat',
  'same-tab-snap',
  'transient-snap',
];

// MUST-HIT: every discriminant value of `kind`, the three branch groups it
// collapses to (run-chase / reduced-chase-or-snap-to-seat / everything else)
const PLAN_START_SEAT_Y_MUST_HIT = HANDOFF_KINDS.map((kind) => [kind, 24, 10]);

function genPlanStartSeatY() {
  return buildCases(
    'planStartSeatY',
    'exact',
    PLAN_START_SEAT_Y_MUST_HIT,
    combosCapped([HANDOFF_KINDS, SEAT_Y_VALUES, SEAT_Y_VALUES], 175),
    ([kind, runSeatY, fromSeatY]) => planStartSeatY({ kind, runSeatY, fromSeatY }),
    ([kind, runSeatY, fromSeatY]) => ({
      kind,
      runSeatY: encodeNumber(runSeatY),
      fromSeatY: encodeNumber(fromSeatY),
    }),
    encodeNumber,
    Object.fromEntries(HANDOFF_KINDS.map((kind) => [`kind-${kind}`, ({ a }) => a[0] === kind]))
  );
}

const WIDTH = 402;
const HANDOFF_STATES = [
  { lastTab: 0, lastX: null, lastSeat: 0 },
  { lastTab: 0, lastX: 40, lastSeat: 0 },
  { lastTab: 1, lastX: 180, lastSeat: 0 },
  { lastTab: 2, lastX: null, lastSeat: 24 },
  { lastTab: 4, lastX: 320, lastSeat: 24 },
  { lastTab: 4, lastX: -0, lastSeat: -24 },
  { lastTab: 11, lastX: 1e6, lastSeat: 1e6 },
  { lastTab: -1, lastX: -100.5, lastSeat: -100.5 },
];

const FOCUS_ARGS_LIST = [
  {
    tab: 0,
    screenWidth: WIDTH,
    bottomExtra: 0,
    transientSlot: false,
    reduceMotion: false,
    slotCount: 5,
  },
  {
    tab: 4,
    screenWidth: WIDTH,
    bottomExtra: 24,
    transientSlot: false,
    reduceMotion: false,
    slotCount: 5,
  },
  {
    tab: 4,
    screenWidth: WIDTH,
    bottomExtra: 24,
    transientSlot: false,
    reduceMotion: true,
    slotCount: 5,
  },
  {
    tab: 2,
    screenWidth: WIDTH,
    bottomExtra: 0,
    transientSlot: true,
    reduceMotion: false,
    slotCount: 5,
  },
  {
    tab: 1,
    screenWidth: WIDTH,
    bottomExtra: 0,
    transientSlot: false,
    reduceMotion: false,
    slotCount: 5,
    holdRun: true,
  },
  {
    tab: 0,
    screenWidth: WIDTH,
    bottomExtra: -50,
    transientSlot: false,
    reduceMotion: true,
    slotCount: 3,
  },
  {
    tab: 11,
    screenWidth: WIDTH,
    bottomExtra: 0,
    transientSlot: false,
    reduceMotion: false,
    slotCount: 12,
  },
  {
    tab: -1,
    screenWidth: WIDTH,
    bottomExtra: 0,
    transientSlot: false,
    reduceMotion: false,
    slotCount: 5,
  },
  {
    tab: 3,
    screenWidth: WIDTH,
    bottomExtra: 10,
    transientSlot: false,
    reduceMotion: false,
    slotCount: 5,
    slotCenters: [40, 120, 200, 280, 360],
  },
  {
    tab: 2,
    screenWidth: WIDTH,
    bottomExtra: 0,
    transientSlot: false,
    reduceMotion: false,
    slotCount: 0,
  },
];

function encFocusArgs(a) {
  return {
    tab: a.tab,
    screenWidth: encodeNumber(a.screenWidth),
    bottomExtra: encodeNumber(a.bottomExtra),
    transientSlot: a.transientSlot,
    reduceMotion: a.reduceMotion,
    slotCount: a.slotCount,
    slotCenters: a.slotCenters === undefined ? null : encArr(a.slotCenters),
    holdRun: a.holdRun === undefined ? null : a.holdRun,
  };
}

/** planMountSeatY's TypeScript type has no holdRun field - unlike
 *  encFocusArgs above, this omits the key entirely rather than emitting it
 *  as null, so the fixture only ever carries the fields the function's own
 *  type declares. The MUST-HIT rows below still pass the full args object
 *  (holdRun included) to the real planMountSeatY call, since it forwards to
 *  planFocus internally and holdRun does affect that result - only the
 *  wire-format args, not the computed expectation, drop the field. */
function encFocusArgsForMountSeatY(a) {
  return {
    tab: a.tab,
    screenWidth: encodeNumber(a.screenWidth),
    bottomExtra: encodeNumber(a.bottomExtra),
    transientSlot: a.transientSlot,
    reduceMotion: a.reduceMotion,
    slotCount: a.slotCount,
    slotCenters: a.slotCenters === undefined ? null : encArr(a.slotCenters),
  };
}

// planFocus's holdRun branch and the strict-less-than snap threshold,
// worked out from tabCenterX/shouldSnapToSeat rather than guessed. Target is
// tab 1 of 5 on a 402pt screen: tabCenterX(1, 402, 5) === 100. A handoff at
// lastX=120 (lastTab 0, so tab 1 is a real cross-tab focus) puts the run
// distance at |100-120| = 20 - under PERCH_SIZE (54) and non-zero, per spec.
const PLAN_FOCUS_BASE_HANDOFF = { lastTab: 0, lastX: 120, lastSeat: 0 };
const PLAN_FOCUS_TARGET_ARGS = {
  tab: 1,
  screenWidth: 402,
  bottomExtra: 0,
  transientSlot: false,
  reduceMotion: false,
  slotCount: 5,
};
// measured centers for the same 5-slot/402pt bar, so a slotCenters variant
// of every row below still lands in the same distance regime
const PLAN_FOCUS_SLOT_CENTERS = [40, 120, 200, 280, 360];
// fromX=46 makes |tabCenterX(1,402,5) - 46| === 100 - 46 === 54 exactly
const PLAN_FOCUS_TIE_HANDOFF = { lastTab: 0, lastX: 46, lastSeat: 0 };

// holdRun / distance-threshold rows - mirrored verbatim into planMountSeatY
const PLAN_FOCUS_HOLD_RUN_MUST_HIT = [
  // holdRun true, reduceMotion false: the snap is suppressed, kind run-chase
  [PLAN_FOCUS_BASE_HANDOFF, { ...PLAN_FOCUS_TARGET_ARGS, holdRun: true }],
  // holdRun true, reduceMotion true: kind reduced-chase
  [PLAN_FOCUS_BASE_HANDOFF, { ...PLAN_FOCUS_TARGET_ARGS, reduceMotion: true, holdRun: true }],
  // holdRun false (explicit): kind snap-to-seat
  [PLAN_FOCUS_BASE_HANDOFF, { ...PLAN_FOCUS_TARGET_ARGS, holdRun: false }],
  // holdRun absent: same as explicit false, kind snap-to-seat
  [PLAN_FOCUS_BASE_HANDOFF, { ...PLAN_FOCUS_TARGET_ARGS }],
  // holdRun true on the SAME tab as lastTab: not a same-tab-snap
  [PLAN_FOCUS_BASE_HANDOFF, { ...PLAN_FOCUS_TARGET_ARGS, tab: 0, holdRun: true }],
  // distance of exactly 54: not a snap (strict less-than), through planFocus itself
  [PLAN_FOCUS_TIE_HANDOFF, { ...PLAN_FOCUS_TARGET_ARGS }],
];

// each of the five FocusKind discriminants, with and without measured
// slotCenters - snap-to-seat/reduced-chase/run-chase reuse the rows above for
// the "without" half and add only the "with slotCenters" half here
const PLAN_FOCUS_KIND_SLOT_CENTERS_MUST_HIT = [
  // transient-snap
  [PLAN_FOCUS_BASE_HANDOFF, { ...PLAN_FOCUS_TARGET_ARGS, transientSlot: true }],
  [
    PLAN_FOCUS_BASE_HANDOFF,
    { ...PLAN_FOCUS_TARGET_ARGS, transientSlot: true, slotCenters: PLAN_FOCUS_SLOT_CENTERS },
  ],
  // same-tab-snap
  [{ lastTab: 1, lastX: 120, lastSeat: 0 }, { ...PLAN_FOCUS_TARGET_ARGS }],
  [
    { lastTab: 1, lastX: 120, lastSeat: 0 },
    { ...PLAN_FOCUS_TARGET_ARGS, slotCenters: PLAN_FOCUS_SLOT_CENTERS },
  ],
  // snap-to-seat + slotCenters (the plain snap-to-seat row is in the holdRun list above)
  [PLAN_FOCUS_BASE_HANDOFF, { ...PLAN_FOCUS_TARGET_ARGS, slotCenters: PLAN_FOCUS_SLOT_CENTERS }],
  // reduced-chase + slotCenters
  [
    PLAN_FOCUS_BASE_HANDOFF,
    {
      ...PLAN_FOCUS_TARGET_ARGS,
      reduceMotion: true,
      holdRun: true,
      slotCenters: PLAN_FOCUS_SLOT_CENTERS,
    },
  ],
  // run-chase + slotCenters
  [
    PLAN_FOCUS_BASE_HANDOFF,
    { ...PLAN_FOCUS_TARGET_ARGS, holdRun: true, slotCenters: PLAN_FOCUS_SLOT_CENTERS },
  ],
];

const PLAN_FOCUS_MUST_HIT = [
  ...PLAN_FOCUS_HOLD_RUN_MUST_HIT,
  ...PLAN_FOCUS_KIND_SLOT_CENTERS_MUST_HIT,
];

function genPlanMountSeatY() {
  const cases = [];
  for (const [handoff, args] of [
    ...PLAN_FOCUS_MUST_HIT,
    ...combosCapped([HANDOFF_STATES, FOCUS_ARGS_LIST], 150),
  ]) {
    const result = planMountSeatY(handoff, args);
    cases.push({
      fn: 'planMountSeatY',
      args: { handoff: encHandoff(handoff), args: encFocusArgsForMountSeatY(args) },
      expect: encodeNumber(result),
      compare: 'exact',
    });
  }
  return cases;
}

const BOTTOM_EXTRAS = [0, -0, 1, -1, 24, -24, 100, -100];

// NaN and the infinities as bottomExtra and as seatY (both distances)
const LIVE_LAST_SEAT_MUST_HIT = [
  ...NON_FINITE.map((bottomExtra) => [bottomExtra, 24]),
  ...NON_FINITE.map((seatY) => [24, seatY]),
];

function genLiveLastSeat() {
  return buildCases(
    'liveLastSeat',
    'exact',
    LIVE_LAST_SEAT_MUST_HIT,
    combosCapped([BOTTOM_EXTRAS, SEAT_Y_VALUES], 64),
    ([bottomExtra, seatY]) => liveLastSeat(bottomExtra, seatY),
    ([bottomExtra, seatY]) => ({
      bottomExtra: encodeNumber(bottomExtra),
      seatY: encodeNumber(seatY),
    }),
    encodeNumber,
    { 'non-finite input': ({ a }) => !Number.isFinite(a[0]) || !Number.isFinite(a[1]) }
  );
}

// zero-arg function: exactly one case (there is no parameter space to sweep)
function genInitialPerchHandoff() {
  return [
    {
      fn: 'initialPerchHandoff',
      args: {},
      expect: encHandoff(initialPerchHandoff()),
      compare: 'exact',
    },
  ];
}

const FOCUS_PLAN_KINDS = [
  'transient-snap',
  'same-tab-snap',
  'snap-to-seat',
  'reduced-chase',
  'run-chase',
];

function genPlanFocus() {
  return buildCases(
    'planFocus',
    'exact',
    PLAN_FOCUS_MUST_HIT,
    combosCapped([HANDOFF_STATES, FOCUS_ARGS_LIST], 150),
    ([handoff, args]) => planFocus(handoff, args),
    ([handoff, args]) => ({ handoff: encHandoff(handoff), args: encFocusArgs(args) }),
    encFocusPlan,
    {
      ...Object.fromEntries(
        FOCUS_PLAN_KINDS.map((kind) => [`kind-${kind}`, ({ r }) => r.kind === kind])
      ),
      'holdRun suppresses the snap': ({ a, r }) => {
        const distance = Math.abs(r.targetX - r.fromX);
        return (
          a[1].holdRun === true &&
          r.kind !== 'snap-to-seat' &&
          distance > 0 &&
          distance < PERCH_SIZE_CONST
        );
      },
      'holdRun overrides same-tab': ({ a, r }) =>
        a[0].lastTab === a[1].tab && a[1].holdRun === true && r.kind !== 'same-tab-snap',
      'distance exactly 54 runs': ({ r }) =>
        r.kind === 'run-chase' && Math.abs(r.targetX - r.fromX) === PERCH_SIZE_CONST,
    }
  );
}

const BLUR_ARGS_LIST = [
  { currentX: 0, transientSlot: false },
  { currentX: -0, transientSlot: false },
  { currentX: 402, transientSlot: false },
  { currentX: 200.5, transientSlot: true },
  { currentX: -50, transientSlot: false, currentSeat: 24 },
  { currentX: 100, transientSlot: false, currentSeat: 0 },
  { currentX: 100, transientSlot: false, currentSeat: -24 },
  { currentX: 1e6, transientSlot: false, currentSeat: 1e6 },
  { currentX: -1e6, transientSlot: true, currentSeat: -1e6 },
  { currentX: 12.5, transientSlot: false },
];

function encBlurArgs(a) {
  return {
    currentX: encodeNumber(a.currentX),
    transientSlot: a.transientSlot,
    currentSeat: a.currentSeat === undefined ? null : encodeNumber(a.currentSeat),
  };
}

// applyFocusBlur's 'currentSeat fallback' class must actually exercise
// the `args.currentSeat ?? handoff.lastSeat` branch: transientSlot false AND
// currentSeat absent, checked against the real output (lastSeat carried
// through from the incoming handoff), not just the input shape
const APPLY_FOCUS_BLUR_MUST_HIT = [
  [
    { lastTab: 2, lastX: null, lastSeat: 24 },
    { currentX: 40, transientSlot: false },
  ],
];

function genApplyFocusBlur() {
  return buildCases(
    'applyFocusBlur',
    'exact',
    APPLY_FOCUS_BLUR_MUST_HIT,
    combosCapped([HANDOFF_STATES, BLUR_ARGS_LIST], 120),
    ([handoff, args]) => applyFocusBlur(handoff, args),
    ([handoff, args]) => ({ handoff: encHandoff(handoff), args: encBlurArgs(args) }),
    encHandoff,
    {
      'transientSlot-true': ({ a }) => a[1].transientSlot === true,
      'transientSlot-false': ({ a }) => a[1].transientSlot === false,
      'currentSeat-missing': ({ a }) => a[1].currentSeat === undefined,
      'currentSeat fallback': ({ a, r }) =>
        a[1].transientSlot === false &&
        a[1].currentSeat === undefined &&
        r.lastSeat === a[0].lastSeat,
    }
  );
}

const GLASS_TARGETS = [0, -0, 1, -1, 100, -100, 200.5, 402, 1e6, -1e6, 24, -24, 750, 0.5, -0.5];

function genApplyDragTrack() {
  const cases = [];
  for (const [handoff, glassTarget] of combosCapped([HANDOFF_STATES, GLASS_TARGETS], 120)) {
    const result = applyDragTrack(handoff, glassTarget);
    cases.push({
      fn: 'applyDragTrack',
      args: { handoff: encHandoff(handoff), glassTarget: encodeNumber(glassTarget) },
      expect: encHandoff(result),
      compare: 'exact',
    });
  }
  return cases;
}

const DRAG_RELEASE_ARGS_LIST = [
  { tab: 0, releaseX: 0, bottomExtra: 0 },
  { tab: 4, releaseX: 320, bottomExtra: 24 },
  { tab: 2, releaseX: -50, bottomExtra: -24 },
  { tab: 1, releaseX: 1e6, bottomExtra: 1e6 },
  { tab: -1, releaseX: -1e6, bottomExtra: -1e6 },
  { tab: 11, releaseX: 200.5, bottomExtra: 0 },
  { tab: 0, releaseX: -0, bottomExtra: -0 },
];

function encDragReleaseArgs(args) {
  return {
    tab: args.tab,
    releaseX: encodeNumber(args.releaseX),
    bottomExtra: encodeNumber(args.bottomExtra),
  };
}

// explicit written/unchanged rows, not left to sampling alone
const APPLY_DRAG_RELEASE_MUST_HIT = [
  // written: this instance still owns lastTab
  [
    { lastTab: 4, lastX: 320, lastSeat: 24 },
    { tab: 4, releaseX: 40, bottomExtra: 10 },
  ],
  // unchanged: a competing focus already consumed the handoff
  [
    { lastTab: 2, lastX: null, lastSeat: 24 },
    { tab: 4, releaseX: 40, bottomExtra: 10 },
  ],
];

function genApplyDragRelease() {
  return buildCases(
    'applyDragRelease',
    'exact',
    APPLY_DRAG_RELEASE_MUST_HIT,
    combosCapped([HANDOFF_STATES, DRAG_RELEASE_ARGS_LIST], 120),
    ([handoff, args]) => applyDragRelease(handoff, args),
    ([handoff, args]) => ({ handoff: encHandoff(handoff), args: encDragReleaseArgs(args) }),
    encHandoff,
    {
      written: ({ a, r }) => a[0].lastTab === a[1].tab && r.lastX === a[1].releaseX,
      unchanged: ({ a, r }) => a[0].lastTab !== a[1].tab && r === a[0],
    }
  );
}

// full truth table (phase x releaseSlot!==currentSlot x selectsOnRelease) -
// mirrors perch-handoff.test.ts's testPlanDragReleaseTable
const PLAN_DRAG_RELEASE_MUST_HIT = [
  ['ended', 3, 2, true],
  ['ended', 3, 2, false],
  ['ended', 2, 2, true],
  ['ended', 2, 2, false],
  ['ended', 1, 2, true], // release slot BELOW the current slot also awaits it
  ['cancelled', 3, 2, true],
  ['cancelled', 3, 2, false],
  ['cancelled', 2, 2, true],
  ['cancelled', 2, 2, false],
];

function genPlanDragRelease() {
  return buildCases(
    'planDragRelease',
    'exact',
    PLAN_DRAG_RELEASE_MUST_HIT,
    [],
    ([phase, releaseSlot, currentSlot, selectsOnReleaseArg]) =>
      planDragRelease({ phase, releaseSlot, currentSlot, selectsOnRelease: selectsOnReleaseArg }),
    ([phase, releaseSlot, currentSlot, selectsOnReleaseArg]) => ({
      phase,
      releaseSlot,
      currentSlot,
      selectsOnRelease: selectsOnReleaseArg,
    }),
    encDragReleasePlan,
    {
      home: ({ r }) => r.kind === 'home',
      await: ({ r }) => r.kind === 'await',
      'await-release-below-current': ({ a, r }) => a[1] < a[2] && r.kind === 'await',
    }
  );
}

// full truth table (barScrub x hasOnDragRelease x nativePill) - mirrors
// perch-handoff.test.ts's testSelectsOnReleaseAllCombinations
const SELECTS_ON_RELEASE_MUST_HIT = [
  ['native', false, false],
  ['native', false, true],
  ['native', true, false],
  ['native', true, true],
  ['exclusive', false, false],
  ['exclusive', false, true],
  ['exclusive', true, false],
  ['exclusive', true, true],
];

function genSelectsOnRelease() {
  return buildCases(
    'selectsOnRelease',
    'exact',
    SELECTS_ON_RELEASE_MUST_HIT,
    [],
    ([barScrub, hasOnDragRelease, nativePill]) =>
      selectsOnRelease({ barScrub, hasOnDragRelease, nativePill }),
    ([barScrub, hasOnDragRelease, nativePill]) => ({ barScrub, hasOnDragRelease, nativePill }),
    (r) => r,
    { true: ({ r }) => r === true, false: ({ r }) => r === false }
  );
}

// both kinds, the 54pt edge (both signs), the floor, the raw-rate middle, the
// ceiling, a speed override, and non-finite distance - worked out from
// perch-handoff.test.ts's testPlanApproach, not sampled
const PLAN_APPROACH_MUST_HIT = [
  [53.9, undefined], // spring: just under one glass width
  [54, undefined], // run: exactly one glass width (shouldSnapToSeat is strict less-than)
  [-54, undefined], // run: same edge, negative sign
  [600, undefined], // run: mid-distance, unclamped raw rate
  [100_000, undefined], // run: clamped to the 2200ms ceiling
  [200, 100], // run: a speed override stretches the floor/ceiling
  [200, 0], // speed override 0
  [200, -100], // speed override negative
  [200, Number.NaN], // speed override NaN
  [200, Infinity], // speed override Infinity
  // distance/speed worked out so the STRETCHED floor is what clamps: stretch
  // 340/170 = 2, raw = 102/170*1000 = 600, between the unstretched floor
  // (400) and the stretched one (800) - only the stretched floor catches it
  [102, 170],
  // distance/speed worked out so the STRETCHED ceiling is what clamps: stretch
  // 340/680 = 0.5, raw = 1020/680*1000 = 1500, between the stretched ceiling
  // (1100) and the unstretched one (2200) - only the stretched ceiling catches it
  [1020, 680],
  ...NON_FINITE.map((d) => [d, undefined]),
];

function encPlanApproachArgs([distancePt, speedPtS]) {
  return { distancePt: encodeNumber(distancePt), speedPtS: encOrNull(speedPtS) };
}

function genPlanApproach() {
  return buildCases(
    'planApproach',
    'exact',
    PLAN_APPROACH_MUST_HIT,
    [],
    ([distancePt, speedPtS]) =>
      speedPtS === undefined ? planApproach(distancePt) : planApproach(distancePt, speedPtS),
    encPlanApproachArgs,
    encApproachPlan,
    {
      spring: ({ r }) => r.kind === 'spring',
      run: ({ r }) => r.kind === 'run',
      'edge-54-runs': ({ a, r }) => Math.abs(a[0]) === 54 && r.kind === 'run',
      'floor-clamped': ({ r }) => r.kind === 'run' && r.durationMs === 400,
      'ceiling-clamped': ({ r }) => r.kind === 'run' && r.durationMs === 2200,
      // outcome, not input: a speed override only counts as this class if it
      // actually changed the duration from what the default speed would give
      'speed-override': ({ a, r }) => {
        const [distancePt, speedPtS] = a;
        if (speedPtS === undefined || r.kind !== 'run') {
          return false;
        }
        const atDefault = planApproach(distancePt);
        return atDefault.kind === 'run' && r.durationMs !== atDefault.durationMs;
      },
      // the stretched floor/ceiling, not the constant MIN/MAX_TRAVERSE_MS,
      // is what clamped this result
      'stretched-floor-clamps': ({ a, r }) => {
        const [, speedPtS] = a;
        if (
          speedPtS === undefined ||
          !Number.isFinite(speedPtS) ||
          speedPtS === 0 ||
          r.kind !== 'run'
        ) {
          return false;
        }
        const stretch = TRAVERSE_SPEED_PT_S / speedPtS;
        const stretchedFloor = MIN_TRAVERSE_MS * stretch;
        return stretchedFloor !== MIN_TRAVERSE_MS && r.durationMs === stretchedFloor;
      },
      'stretched-ceiling-clamps': ({ a, r }) => {
        const [, speedPtS] = a;
        if (
          speedPtS === undefined ||
          !Number.isFinite(speedPtS) ||
          speedPtS === 0 ||
          r.kind !== 'run'
        ) {
          return false;
        }
        const stretch = TRAVERSE_SPEED_PT_S / speedPtS;
        const stretchedCeiling = MAX_TRAVERSE_MS * stretch;
        return stretchedCeiling !== MAX_TRAVERSE_MS && r.durationMs === stretchedCeiling;
      },
      'non-finite input': ({ a }) => !Number.isFinite(a[0]),
    }
  );
}

// PERCH_SIZE=54: the edge and both signs
const IS_FAR_GRAB_MUST_HIT = [54, -54, 54.1, -54.1, 0, ...NON_FINITE];

function genIsFarGrab() {
  return buildCases(
    'isFarGrab',
    'exact',
    IS_FAR_GRAB_MUST_HIT,
    [],
    (gapPt) => isFarGrab(gapPt),
    (gapPt) => ({ gapPt: encodeNumber(gapPt) }),
    (r) => r,
    {
      true: ({ r }) => r === true,
      false: ({ r }) => r === false,
      'non-finite input': ({ a }) => !Number.isFinite(a),
    }
  );
}

// CHASE_TRAIL=18, CHASE_SLACK=4: TRAIL+SLACK=22 - the not-chasing edge, both
// signs, both screen-edge clamps and non-finite input, worked out from
// perch-handoff.test.ts's testPlanFarSample
const PLAN_FAR_SAMPLE_SCREEN_WIDTH = 402;
const PLAN_FAR_SAMPLE_MUST_HIT = [
  [122, 100, PLAN_FAR_SAMPLE_SCREEN_WIDTH], // end: gap exactly +22 (inside the not-chasing edge)
  [122.1, 100, PLAN_FAR_SAMPLE_SCREEN_WIDTH], // track: just past +22, facing right
  [78, 100, PLAN_FAR_SAMPLE_SCREEN_WIDTH], // end: gap exactly -22
  [77.9, 100, PLAN_FAR_SAMPLE_SCREEN_WIDTH], // track: just past -22, facing left
  [300, 0, PLAN_FAR_SAMPLE_SCREEN_WIDTH], // track: a big positive gap
  [10, -20, PLAN_FAR_SAMPLE_SCREEN_WIDTH], // track: clamped to the left screen edge
  [345, 400, PLAN_FAR_SAMPLE_SCREEN_WIDTH], // track: clamped to the right screen edge
  ...NON_FINITE.map((glassX) => [glassX, 100, PLAN_FAR_SAMPLE_SCREEN_WIDTH]),
  ...NON_FINITE.map((currentX) => [122.1, currentX, PLAN_FAR_SAMPLE_SCREEN_WIDTH]),
  // a second screen width entirely, not the one every other row above shares
  [500, 0, 800],
  // a narrow screen where both clamps meet: screenWidth === PERCH_SIZE, so
  // min(max(x, 0), screenWidth - PERCH_SIZE) collapses to min(max(x,0), 0) - 0 either way
  [200, 0, PERCH_SIZE],
];

function genPlanFarSample() {
  return buildCases(
    'planFarSample',
    'exact',
    PLAN_FAR_SAMPLE_MUST_HIT,
    [],
    ([glassX, currentX, screenWidth]) => planFarSample({ glassX, currentX, screenWidth }),
    ([glassX, currentX, screenWidth]) => ({
      glassX: encodeNumber(glassX),
      currentX: encodeNumber(currentX),
      screenWidth: encodeNumber(screenWidth),
    }),
    encFarSamplePlan,
    {
      end: ({ r }) => r.kind === 'end',
      'track-facing-right': ({ r }) => r.kind === 'track' && r.facing === 1,
      'track-facing-left': ({ r }) => r.kind === 'track' && r.facing === -1,
      'clamped-left-edge': ({ r }) => r.kind === 'track' && r.target === 0,
      'clamped-right-edge': ({ a, r }) => r.kind === 'track' && r.target === a[2] - PERCH_SIZE,
      'second-screen-width': ({ a }) => a[2] !== PLAN_FAR_SAMPLE_SCREEN_WIDTH,
      'both-clamps-meet': ({ a, r }) => a[2] === PERCH_SIZE && r.kind === 'track' && r.target === 0,
      'non-finite input': ({ a }) => !Number.isFinite(a[0]) || !Number.isFinite(a[1]),
    }
  );
}

// FAR_STEP_MAX_DT_MS=34: a normal step each direction, arrival exactly on the
// target, dt below 0, dt above the cap, speed 0 and negative, and every
// argument non-finite in turn - worked out from perch-handoff.test.ts's
// testStepToward/testStepTowardTotalOnNonFiniteAndBadSpeed, not sampled
const STEP_TOWARD_MUST_HIT = [
  [0, 300, 340, 16], // normal step, rightward
  [100, 50, 340, 16], // normal step, leftward
  [298, 300, 340, 16], // a step past the target lands exactly on it
  [0, 5.44, 340, 16], // step exactly equal to the remaining distance also arrives (340*16/1000 === 5.44)
  [50, 50, 340, 16], // already at the target
  [50, 300, 340, -5], // dt below 0 clamps to 0, no step
  [0, 300, 340, 1000], // dt above the cap clamps to FAR_STEP_MAX_DT_MS (34)
  [50, 50, 0, 16], // speed 0 at the target: the guard, not zero distance, decides
  [10, 300, 0, 16], // speed 0 short of the target
  [10, 300, -5, 16], // negative speed
  [Number.NaN, 300, 340, 16],
  [10, Number.NaN, 340, 16],
  [10, Number.POSITIVE_INFINITY, 340, 16],
  [10, 300, Number.NaN, 16],
  [10, 300, Number.POSITIVE_INFINITY, 16],
  [10, 300, 340, Number.NaN],
  [10, 300, 340, Number.POSITIVE_INFINITY],
  [Number.POSITIVE_INFINITY, 300, 340, 16], // current as Infinity
  [Number.NEGATIVE_INFINITY, 300, 340, 16], // current as -Infinity
  [10, Number.NEGATIVE_INFINITY, 340, 16], // target as -Infinity
  [10, 300, Number.NEGATIVE_INFINITY, 16], // speed as -Infinity
  [10, 300, 340, Number.NEGATIVE_INFINITY], // dt as -Infinity
  [-0, 300, 340, 0], // current -0 with dt 0
  [-0, 300, 340, -0], // current -0 with dt -0
];

function genStepToward() {
  return buildCases(
    'stepToward',
    'exact',
    STEP_TOWARD_MUST_HIT,
    [],
    ([current, target, speedPtS, dtMs]) => stepToward(current, target, speedPtS, dtMs),
    ([current, target, speedPtS, dtMs]) => ({
      current: encodeNumber(current),
      target: encodeNumber(target),
      speedPtS: encodeNumber(speedPtS),
      dtMs: encodeNumber(dtMs),
    }),
    (r) => ({ x: encodeNumber(r.x), arrived: r.arrived }),
    {
      'arrived-true': ({ r }) => r.arrived === true,
      'arrived-false': ({ r }) => r.arrived === false,
      'step-rightward': ({ a, r }) => a[1] > a[0] && !r.arrived,
      'step-leftward': ({ a, r }) => a[1] < a[0] && !r.arrived,
      'negative-dt-no-move': ({ a, r }) => a[3] < 0 && r.x === a[0],
      // outcome, not input: a finite dt above the cap must produce a step of
      // exactly speed * 34 / 1000, not the raw dt's step
      'dt-above-cap-clamped': ({ a, r }) => {
        const [current, , speedPtS, dtMs] = a;
        if (!Number.isFinite(dtMs) || dtMs <= 34 || r.arrived) {
          return false;
        }
        const clampedStep = (speedPtS * 34) / 1000;
        return Math.abs(r.x - current) === clampedStep;
      },
      'speed-zero-or-negative': ({ a }) => a[2] <= 0,
      'non-finite input': ({ a }) => a.some((v) => !Number.isFinite(v)),
    }
  );
}

// a valid speed, 0, negative, NaN, both infinities, undefined - mirrors
// perch-handoff.test.ts's testSanitizeRunSpeed
const SANITIZE_RUN_SPEED_MUST_HIT = [
  340,
  200,
  5000,
  0,
  -0,
  -5,
  Number.NaN,
  Infinity,
  -Infinity,
  undefined,
];

function genSanitizeRunSpeed() {
  return buildCases(
    'sanitizeRunSpeed',
    'exact',
    SANITIZE_RUN_SPEED_MUST_HIT,
    [],
    (speed) => sanitizeRunSpeed(speed),
    (speed) => ({ speed: encOrNull(speed) }),
    encodeNumber,
    {
      'valid speed passthrough': ({ a, r }) =>
        a !== undefined && Number.isFinite(a) && a > 0 && r === a,
      'falls back to the default': ({ r }) => r === 340, // TRAVERSE_SPEED_PT_S
    }
  );
}

// both branches
const FOCUS_FROM_SLOT_MUST_HIT = [
  [0, true, 3],
  [0, false, 3],
  [4, true, 2],
  [4, false, 2],
];

function genFocusFromSlot() {
  return buildCases(
    'focusFromSlot',
    'exact',
    FOCUS_FROM_SLOT_MUST_HIT,
    [],
    ([handoffLastTab, arrivedByDrag, focusedSlot]) =>
      focusFromSlot(handoffLastTab, arrivedByDrag, focusedSlot),
    ([handoffLastTab, arrivedByDrag, focusedSlot]) => ({
      handoffLastTab,
      arrivedByDrag,
      focusedSlot,
    }),
    (r) => r,
    {
      // outcome, not input: arriving by drag must actually return the
      // focused slot, and that slot must differ from the handoff tab -
      // else this class could be satisfied by a no-op case
      'arrived-by-drag': ({ a, r }) => a[1] === true && r === a[2] && a[2] !== a[0],
      'not-arrived-by-drag': ({ a }) => a[1] === false,
    }
  );
}

// zero-arg function: exactly one case (there is no parameter space to sweep)
function genInitialReleaseState() {
  return [
    {
      fn: 'initialReleaseState',
      args: {},
      expect: encReleaseState(initialReleaseState()),
      compare: 'exact',
    },
  ];
}

// [state, event] pairs, run as the full cross product of 4 states x every
// event below - so every event type is exercised from a state with nothing
// pending, one with a release pending, one mid-arrival, and one with both -
// rather than a hand-picked subset that could hide an outcome only visible
// from a state nobody tried.
//
// pending's three fields are each given their own value (fromSlot 1, slot 3,
// generation 7) so a reducer that compares the wrong two fields (event
// generation vs pending.fromSlot, or renderedSlot vs pending.generation)
// cannot pass by accident; timerSwappedGenerationForFromSlot and
// timerSwappedRenderedSlotForGeneration below are built to trip exactly that
// confusion.
const RR_PENDING_FIELDS = { fromSlot: 1, slot: 3, generation: 7 };
const RR_EMPTY_STATE = { pending: null, arrival: false };
const RR_PENDING_STATE = { pending: RR_PENDING_FIELDS, arrival: false };
const RR_ARRIVAL_STATE = { pending: null, arrival: true };
const RR_PENDING_ARRIVAL_STATE = { pending: RR_PENDING_FIELDS, arrival: true };

const RR_EVENTS = {
  releaseHome: { type: 'release', plan: { kind: 'home' }, fromSlot: 1, generation: 1 },
  releaseAwait: { type: 'release', plan: { kind: 'await', slot: 3 }, fromSlot: 1, generation: 1 },
  releaseAwaitOverwrite: {
    type: 'release',
    plan: { kind: 'await', slot: 4 },
    fromSlot: 5,
    generation: 2,
  },
  began: { type: 'began' },
  engage: { type: 'engage' },
  focusCleanup: { type: 'focus-cleanup' },
  focusBodyFalse: { type: 'focus-body', transientSlot: false },
  focusBodyTrue: { type: 'focus-body', transientSlot: true },
  // not mounted: drops the wait regardless of generation/renderedSlot
  timerMountedFail: { type: 'timer', mounted: false, generation: 7, renderedSlot: 1 },
  // generation mismatches pending.generation (7): drops the wait
  timerGenerationFail: { type: 'timer', mounted: true, generation: 8, renderedSlot: 1 },
  // generation matches, but renderedSlot (4) isn't pending.fromSlot (1): keeps the wait
  timerRenderedSlotFail: { type: 'timer', mounted: true, generation: 7, renderedSlot: 4 },
  // generation and renderedSlot both match: the only combination that goes home
  timerAllPass: { type: 'timer', mounted: true, generation: 7, renderedSlot: 1 },
  // generation (1) matches pending.fromSlot, not pending.generation (7) - a
  // reducer comparing generation against fromSlot would wrongly pass this
  timerSwappedGenerationForFromSlot: {
    type: 'timer',
    mounted: true,
    generation: 1,
    renderedSlot: 1,
  },
  // renderedSlot (7) matches pending.generation, not pending.fromSlot (1) - a
  // reducer comparing renderedSlot against generation would wrongly pass this
  timerSwappedRenderedSlotForGeneration: {
    type: 'timer',
    mounted: true,
    generation: 7,
    renderedSlot: 7,
  },
  abort: { type: 'abort' },
  unmount: { type: 'unmount' },
};

const REDUCE_RELEASE_MUST_HIT = [];
for (const state of [
  RR_EMPTY_STATE,
  RR_PENDING_STATE,
  RR_ARRIVAL_STATE,
  RR_PENDING_ARRIVAL_STATE,
]) {
  for (const event of Object.values(RR_EVENTS)) {
    REDUCE_RELEASE_MUST_HIT.push([state, event]);
  }
}

function genReduceRelease() {
  return buildCases(
    'reduceRelease',
    'exact',
    REDUCE_RELEASE_MUST_HIT,
    [],
    ([state, event]) => reduceRelease(state, event),
    ([state, event]) => ({ state: encReleaseState(state), event }),
    encReduceReleaseResult,
    {
      'effect-none': ({ r }) => r.effect === 'none',
      'effect-go-home': ({ r }) => r.effect === 'go-home',
      'effect-await': ({ r }) => r.effect === 'await',
      'effect-clear-timer': ({ r }) => r.effect === 'clear-timer',
      'effect-hold-generation': ({ r }) => r.effect === 'hold-generation',
      'effect-arrived': ({ r }) => r.effect === 'arrived',
      'pending-set-to-null': ({ a, r }) => a[0].pending !== null && r.state.pending === null,
      'pending-null-to-set': ({ a, r }) => a[0].pending === null && r.state.pending !== null,
      'arrival-false-to-true': ({ a, r }) => a[0].arrival === false && r.state.arrival === true,
      'arrival-true-to-false': ({ a, r }) => a[0].arrival === true && r.state.arrival === false,
      // Y1: each reduceTimer outcome, checked against the actual transition
      // (not just the input shape), including the two swapped-field traps
      'timer-not-mounted-drops-pending': ({ a, r }) =>
        a[1].type === 'timer' &&
        a[0].pending !== null &&
        !a[1].mounted &&
        r.state.pending === null &&
        r.effect === 'none',
      'timer-generation-mismatch-drops-pending': ({ a, r }) =>
        a[1].type === 'timer' &&
        a[0].pending !== null &&
        a[1].mounted &&
        a[1].generation !== RR_PENDING_FIELDS.generation &&
        r.state.pending === null &&
        r.effect === 'none',
      'timer-renderedSlot-mismatch-keeps-pending': ({ a, r }) =>
        a[1].type === 'timer' &&
        a[0].pending !== null &&
        a[1].mounted &&
        a[1].generation === RR_PENDING_FIELDS.generation &&
        a[1].renderedSlot !== RR_PENDING_FIELDS.fromSlot &&
        r.state.pending !== null &&
        r.effect === 'none',
      'timer-all-pass-goes-home': ({ a, r }) =>
        a[1].type === 'timer' && a[0].pending !== null && r.effect === 'go-home',
      'timer-swapped-generation-for-fromSlot-still-drops': ({ a, r }) =>
        a[1].type === 'timer' &&
        a[0].pending !== null &&
        a[1].generation === RR_PENDING_FIELDS.fromSlot &&
        a[1].generation !== RR_PENDING_FIELDS.generation &&
        r.state.pending === null &&
        r.effect === 'none',
      'timer-swapped-renderedSlot-for-generation-still-keeps': ({ a, r }) =>
        a[1].type === 'timer' &&
        a[0].pending !== null &&
        a[1].renderedSlot === RR_PENDING_FIELDS.generation &&
        a[1].renderedSlot !== RR_PENDING_FIELDS.fromSlot &&
        r.state.pending !== null &&
        r.effect === 'none',
      // Y2: arrival flows through every event by the rule the reducer
      // actually implements, checked against the real transition
      'arrival-preserved-by-release': ({ a, r }) =>
        a[1].type === 'release' && a[0].arrival === true && r.state.arrival === true,
      'arrival-preserved-by-began': ({ a, r }) =>
        a[1].type === 'began' && a[0].arrival === true && r.state.arrival === true,
      'arrival-preserved-by-engage': ({ a, r }) =>
        a[1].type === 'engage' && a[0].arrival === true && r.state.arrival === true,
      'arrival-preserved-by-abort': ({ a, r }) =>
        a[1].type === 'abort' && a[0].arrival === true && r.state.arrival === true,
      'arrival-preserved-by-timer': ({ a, r }) =>
        a[1].type === 'timer' && a[0].arrival === true && r.state.arrival === true,
      'focus-cleanup-clears-arrival-when-nothing-pending': ({ a, r }) =>
        a[1].type === 'focus-cleanup' &&
        a[0].pending === null &&
        a[0].arrival === true &&
        r.state.arrival === false,
      'focus-cleanup-sets-arrival-when-pending': ({ a, r }) =>
        a[1].type === 'focus-cleanup' && a[0].pending !== null && r.state.arrival === true,
      'focus-body-clears-arrival': ({ a, r }) =>
        a[1].type === 'focus-body' && a[0].arrival === true && r.state.arrival === false,
      'unmount-clears-arrival': ({ a, r }) =>
        a[1].type === 'unmount' && a[0].arrival === true && r.state.arrival === false,
    }
  );
}

function genPerchHandoff() {
  return [
    ...genPlanRunSeatY(),
    ...genPlanStartSeatY(),
    ...genPlanMountSeatY(),
    ...genLiveLastSeat(),
    ...genInitialPerchHandoff(),
    ...genPlanFocus(),
    ...genApplyFocusBlur(),
    ...genApplyDragTrack(),
    ...genApplyDragRelease(),
    ...genPlanDragRelease(),
    ...genSelectsOnRelease(),
    ...genPlanApproach(),
    ...genIsFarGrab(),
    ...genPlanFarSample(),
    ...genStepToward(),
    ...genSanitizeRunSpeed(),
    ...genFocusFromSlot(),
    ...genInitialReleaseState(),
    ...genReduceRelease(),
  ];
}

// ---------------------------------------------------------------------------
// pose-dissolve - a small closed enum product; every semantically distinct
// input is already covered, so counts here are exhaustive rather than 150+
// ---------------------------------------------------------------------------

// null represents an omitted opts argument (default {} applies); the
// planPoseDissolve reader must convert this null back to undefined, since
// `opts = {}` is a real default parameter and null would bypass it
const OPTS_VARIANTS = [
  null,
  {},
  { reduceMotion: true },
  { reduceMotion: false },
  { reduceMotion: null },
];

function encOpts(opts) {
  if (opts === null) {
    return null;
  }
  const out = {};
  if ('reduceMotion' in opts) {
    out.reduceMotion = opts.reduceMotion === null ? null : opts.reduceMotion;
  }
  return out;
}

// every ordered (previous, next) pair - required for both planPoseDissolve
// and poseDissolveApplyOrder below
const POSE_PAIRS = PUP_POSES.flatMap((previous) => PUP_POSES.map((next) => [previous, next]));
// items in both consumers below are [previous, next, ...] tuples
const posePairClassifiers = Object.fromEntries(
  POSE_PAIRS.map(([previous, next]) => [
    `pair-${previous}-${next}`,
    ({ a }) => a[0] === previous && a[1] === next,
  ])
);

function genPlanPoseDissolve() {
  const items = [];
  for (const [previous, next] of POSE_PAIRS) {
    for (const opts of OPTS_VARIANTS) {
      items.push([previous, next, opts]);
    }
  }
  return buildCases(
    'planPoseDissolve',
    'exact',
    items,
    [],
    ([previous, next, opts]) => {
      const callOpts =
        opts === null
          ? undefined
          : { reduceMotion: opts.reduceMotion === null ? undefined : opts.reduceMotion };
      return callOpts === undefined
        ? planPoseDissolve(previous, next)
        : planPoseDissolve(previous, next, callOpts);
    },
    ([previous, next, opts]) => ({ previous, next, opts: encOpts(opts) }),
    encPoseDissolvePlan,
    posePairClassifiers
  );
}

function genPoseDissolveApplyOrder() {
  const items = [];
  for (const [previous, next] of POSE_PAIRS) {
    for (const reduceMotion of [false, true]) {
      items.push([previous, next, reduceMotion]);
    }
  }
  return buildCases(
    'poseDissolveApplyOrder',
    'exact',
    items,
    [],
    ([previous, next, reduceMotion]) =>
      poseDissolveApplyOrder(planPoseDissolve(previous, next, { reduceMotion })),
    ([previous, next, reduceMotion]) => ({
      plan: encPoseDissolvePlan(planPoseDissolve(previous, next, { reduceMotion })),
    }),
    (r) => r,
    posePairClassifiers
  );
}

function genShouldResetIncomingFrame() {
  return buildCases(
    'shouldResetIncomingFrame',
    'exact',
    POSE_PAIRS,
    [],
    ([previous, next]) => shouldResetIncomingFrame(previous, next),
    ([previous, next]) => ({ previous, next }),
    (r) => r,
    { true: ({ r }) => r === true, false: ({ r }) => r === false }
  );
}

function genShouldSnapBusyIdleFrameToRest() {
  return buildCases(
    'shouldSnapBusyIdleFrameToRest',
    'exact',
    PUP_POSES,
    [],
    (currentPose) => shouldSnapBusyIdleFrameToRest(currentPose),
    (currentPose) => ({ currentPose }),
    (r) => r,
    { true: ({ r }) => r === true, false: ({ r }) => r === false }
  );
}

function genPoseDissolve() {
  return [
    ...genPlanPoseDissolve(),
    ...genPoseDissolveApplyOrder(),
    ...genShouldResetIncomingFrame(),
    ...genShouldSnapBusyIdleFrameToRest(),
  ];
}

// ---------------------------------------------------------------------------
// animals
// ---------------------------------------------------------------------------

function encSpring(s) {
  return { duration: encodeNumber(s.duration), dampingRatio: encodeNumber(s.dampingRatio) };
}

function encSheetGeometry(g) {
  return isNullish(g)
    ? null
    : { cols: g.cols, rows: g.rows, frames: g.frames, fps: encodeNumber(g.fps) };
}

// every numeric field of CompanionProfile - optional ones stay present with
// their nil-ness recorded (null), never omitted, so a Swift decode can't
// mistake "not in the fixture" for "the TS side had none"
function encAnimalProfile(p) {
  return {
    id: p.id,
    label: p.label,
    runFps: encodeNumber(p.runFps),
    commitSpring: encSpring(p.commitSpring),
    trackSpring: encSpring(p.trackSpring),
    catchSpring: encSpring(p.catchSpring),
    hopHeight: encodeNumber(p.hopHeight),
    flightLift: encodeNumber(p.flightLift),
    scale: encodeNumber(p.scale),
    aroundRoute: p.aroundRoute,
    headPad: encOrNull(p.headPad),
    footPad: encOrNull(p.footPad),
    seatLift: encOrNull(p.seatLift),
    runSpeed: encOrNull(p.runSpeed),
    sitSheet: encSheetGeometry(p.sitSheet),
  };
}

// the order registerBuiltinCompanions registers them in (animals/all.ts,
// preserved by companionIds()'s Object.keys) - the Swift umbrella's
// registerAll must match this order too. Read from the registry itself
// not a literal list, so a seventh animal registered the documented
// way shows up here without anyone editing this file.
function genAnimals() {
  return companionIds().map((id) => {
    const profile = getCompanion(id);
    if (!profile) {
      throw new Error(
        `animals conformance: "${id}" is not registered by registerBuiltinCompanions`
      );
    }
    return {
      fn: 'animalProfile',
      args: { id },
      expect: encAnimalProfile(profile),
      compare: 'exact',
    };
  });
}

/** SHA-256 hex digest of a file's raw bytes - what enforces `.copy`
 *  over `.process` on the Swift side: a test hashes the bundled sheet and
 *  compares against this, so any recompression the build applies fails it. */
function sha256Hex(filePath) {
  return createHash('sha256').update(readFileSync(filePath)).digest('hex');
}

/** Extra top-level payload for the "animals" module only: SHA-256 of every
 *  bundled sheet and of the shared LICENSE-ART.md, keyed by animal id in
 *  registry order. Not part of `cases` - it isn't a function-call fixture,
 *  it's a asset-integrity fixture the Swift hash test cross-checks against
 *  its own pinned literals (see AssetHashes.swift). */
function genAssetHashes() {
  const assetsDir = path.join(root, 'packages/tabpet/assets');
  const license = sha256Hex(path.join(assetsDir, 'LICENSE-ART.md'));
  const sheets = {};
  for (const id of companionIds()) {
    sheets[id] = {
      idle: sha256Hex(path.join(assetsDir, `${id}-idle-sprite.png`)),
      run: sha256Hex(path.join(assetsDir, `${id}-run-sprite.png`)),
      sit: sha256Hex(path.join(assetsDir, `${id}-sit-sprite.png`)),
    };
  }
  return { assetHashes: { license, sheets } };
}

/** Renders swift/Tests/TabPetAnimalsTests/AssetHashes.swift from a built
 *  "animals" payload - the pinned digests a contributor adding an animal
 *  would otherwise have to copy by hand from animals.json. `ids` is the
 *  registry order (matches the payload's own case order), so the emitted
 *  dictionary lists animals in the same order every other animals.json
 *  consumer does. */
function renderAssetHashesSwift(payload, ids) {
  const entries = ids
    .map((id) => {
      const h = payload.assetHashes.sheets[id];
      return `    "${id}": PinnedSheetHashes(\n        idle: "${h.idle}",\n        run: "${h.run}",\n        sit: "${h.sit}"\n    ),`;
    })
    .join('\n');
  return `// GENERATED by \`bun run conformance\` - do not hand-edit. Pinned SHA-256
// digests of every built-in animal's bundled sheets and the shared
// LICENSE-ART.md, read straight from packages/tabpet/assets/ so a
// contributor adding an animal never copies a digest by hand; \`bun run
// conformance --check\` fails if this file drifts from animals.json's own copy.
let pinnedLicenseSHA256 = "${payload.assetHashes.license}"

struct PinnedSheetHashes {
    let idle: String
    let run: String
    let sit: String
}

let pinnedSheetSHA256: [String: PinnedSheetHashes] = [
${entries}
]
`;
}

// ---------------------------------------------------------------------------
// write / check
// ---------------------------------------------------------------------------

const MODULES = [
  {
    name: 'perch-geometry',
    source: 'packages/tabpet/src/perch-geometry.ts',
    file: 'geometry.json',
    gen: genPerchGeometry,
    // every numeric constant perch-geometry.ts exports
    constants: {
      PERCH_SIZE,
      BAR_MARGIN_H,
      CHASE_TRAIL,
      FACING_DEADBAND,
      CHASE_SLACK,
      TRAVERSE_SPEED_PT_S,
      MIN_TRAVERSE_MS,
      MAX_TRAVERSE_MS,
    },
  },
  {
    name: 'perch-around',
    source: 'packages/tabpet/src/perch-around.ts',
    file: 'around.json',
    gen: genPerchAround,
    // every numeric constant perch-around.ts exports (ARC_SAMPLES is internal, not exported)
    constants: { AROUND_MIN_SLOT_COUNT, AROUND_SPEED_PT_S },
  },
  {
    name: 'perch-handoff',
    source: 'packages/tabpet/src/perch-handoff.ts',
    file: 'handoff.json',
    gen: genPerchHandoff,
    // every numeric constant perch-handoff.ts exports
    constants: { RELEASE_GRACE_MS, FAR_GRAB_PT, FAR_STEP_MAX_DT_MS },
  },
  {
    name: 'pose-dissolve',
    source: 'packages/tabpet/src/pose-dissolve.ts',
    file: 'pose-dissolve.json',
    gen: genPoseDissolve,
    // every numeric constant pose-dissolve.ts exports (PUP_POSES is a string array, not numeric)
    constants: { POSE_FADE_MS },
  },
  {
    name: 'animals',
    source: 'packages/tabpet/src/animals/all.ts',
    file: 'animals.json',
    gen: genAnimals,
    extra: genAssetHashes,
    // this module also writes a companion Swift literal file (a contributor
    // adding an animal must not hand-copy digests) - see renderAssetHashesSwift.
    swiftFile: 'swift/Tests/TabPetAnimalsTests/AssetHashes.swift',
    renderSwiftFile: renderAssetHashesSwift,
    // sheet-geometry.ts's grids, flattened - each is a {cols,rows,frames,fps?}
    // object, but the constants block (like every module's) is a flat
    // name->number map
    constants: {
      idleCols: IDLE_SHEET_GRID.cols,
      idleRows: IDLE_SHEET_GRID.rows,
      idleFrames: IDLE_SHEET_GRID.frames,
      idleFps: IDLE_SHEET_GRID.fps,
      runCols: RUN_SHEET_GRID.cols,
      runRows: RUN_SHEET_GRID.rows,
      runFrames: RUN_SHEET_GRID.frames,
      sitCols: DEFAULT_SIT_SHEET.cols,
      sitRows: DEFAULT_SIT_SHEET.rows,
      sitFrames: DEFAULT_SIT_SHEET.frames,
      sitFps: DEFAULT_SIT_SHEET.fps,
    },
  },
];

/** encodes a module's pinned constants the same way as any other wrapped
 *  float - bits authoritative, so both readers check the exact value their
 *  own module exports, not a hand-copied literal that can drift. */
function encodeConstants(constants) {
  const out = {};
  for (const [name, value] of Object.entries(constants)) {
    out[name] = encodeNumber(value);
  }
  return out;
}

function buildPayload(mod) {
  const payload = {
    module: mod.name,
    source: mod.source,
    constants: encodeConstants(mod.constants),
    cases: mod.gen(),
  };
  // only the "animals" module sets this (the SHA-256 asset-integrity block)
  if (mod.extra) {
    Object.assign(payload, mod.extra());
  }
  return payload;
}

function renderPayload(payload) {
  // compact: these files are generated and never hand-edited; pretty-printing
  // would blow well past the per-file size budget for no benefit
  return `${JSON.stringify(payload)}\n`;
}

// ---------------------------------------------------------------------------
// --check compares structurally, not by rendered bytes. The committed
// files were generated on one Node/V8 build; CI regenerates on another -
// a value that passed through Math.sin/cos/atan2/hypot can round its last
// bit differently between them, and a byte-exact diff would fail --check on
// every CI run for that reason alone. For geometry.json, handoff.json and
// pose-dissolve.json, `args` are checked exact and `expect` is checked with
// each case's own declared compare rule, mirroring
// packages/tabpet/src/conformance.test.ts.
//
// around.json is the one file whose arguments themselves embed a whole
// AroundPath built from Math.sin/cos/hypot (arcCum, legs, totalLen, cxExit,
// cxEnter, ...) - the around cases' arguments, not just their expectations,
// can round differently on a different engine. So in --check ONLY, every
// float leaf of around.json - in args and in expect, for every function in
// the file, exact-pinned ones included (resumeAroundRoute, resumedBaseS) -
// compares with the tolerance rule instead of each case's own pinned mode.
// See wideTolerance in firstStructuralDiff. The two readers (this script's
// own --self-test aside) are untouched: they keep comparing args exactly and
// expect per the case's pinned compare rule, same as before.
// ---------------------------------------------------------------------------

function decodeWireNumber(node) {
  return Buffer.from(node.bits, 'hex').readDoubleBE(0);
}

function isWireNumber(node) {
  return (
    node !== null &&
    typeof node === 'object' &&
    !Array.isArray(node) &&
    typeof node.bits === 'string' &&
    'value' in node &&
    Object.keys(node).length === 2
  );
}

function wireNumbersEqual(a, b, mode) {
  if (Number.isNaN(a) || Number.isNaN(b)) {
    return Number.isNaN(a) && Number.isNaN(b);
  }
  if (mode === 'exact') {
    return Object.is(a, b);
  }
  if (!Number.isFinite(a) || !Number.isFinite(b)) {
    return a === b;
  }
  const scale = Math.max(1, Math.abs(a), Math.abs(b));
  return Math.abs(a - b) <= 1e-9 * scale;
}

/** structural equality over the wire-format JSON tree; `mode` governs how a
 *  wrapped-float leaf compares */
function structuralEqual(a, b, mode) {
  if (isWireNumber(a) && isWireNumber(b)) {
    return wireNumbersEqual(decodeWireNumber(a), decodeWireNumber(b), mode);
  }
  if (a === null || b === null) {
    return a === b;
  }
  if (Array.isArray(a) && Array.isArray(b)) {
    return a.length === b.length && a.every((v, i) => structuralEqual(v, b[i], mode));
  }
  if (typeof a === 'object' && typeof b === 'object') {
    const keys = new Set([...Object.keys(a), ...Object.keys(b)]);
    for (const k of keys) {
      if (!structuralEqual(a[k], b[k], mode)) {
        return false;
      }
    }
    return true;
  }
  return a === b;
}

/** null if the two payloads are structurally equivalent, else a one-line
 *  description naming the first differing case (file, function, index).
 *  `wideTolerance` is around.json's --check-only rule: every float leaf, in
 *  args and in expect alike, compares with the tolerance rule regardless of
 *  the case's own pinned compare mode - a path built from Math.sin/cos/hypot
 *  embeds those same rounding-sensitive floats in its arguments too (an
 *  AroundPath's arcCum, legs, totalLen), and even the "exact" functions in
 *  this file (resumeAroundRoute, resumedBaseS) take or return one. The two
 *  readers are unaffected - they keep comparing args exactly and expect per
 *  the case's own compare mode, same as before. */
function firstStructuralDiff(fileLabel, fresh, committed, wideTolerance = false) {
  if (fresh.module !== committed.module) {
    return `${fileLabel}: module ${committed.module} -> ${fresh.module}`;
  }
  if (fresh.source !== committed.source) {
    return `${fileLabel}: source ${committed.source} -> ${fresh.source}`;
  }
  const argsMode = wideTolerance ? 'tolerance' : 'exact';
  if (!structuralEqual(fresh.constants, committed.constants, argsMode)) {
    return `${fileLabel}: constants differ`;
  }
  // only "animals" carries this (plain hex strings, no wrapped floats, so a
  // straight JSON comparison is exact either way - no tolerance concern)
  if (JSON.stringify(fresh.assetHashes) !== JSON.stringify(committed.assetHashes)) {
    return `${fileLabel}: assetHashes differ`;
  }
  if (fresh.cases.length !== committed.cases.length) {
    return `${fileLabel}: case count ${committed.cases.length} -> ${fresh.cases.length}`;
  }
  for (let i = 0; i < fresh.cases.length; i += 1) {
    const f = fresh.cases[i];
    const c = committed.cases[i];
    if (f.fn !== c.fn) {
      return `${fileLabel} case ${i}: fn ${c.fn} -> ${f.fn}`;
    }
    if (f.compare !== c.compare) {
      return `${fileLabel} case ${i} (${f.fn}): compare ${c.compare} -> ${f.compare}`;
    }
    const expectMode = wideTolerance ? 'tolerance' : f.compare;
    if (!structuralEqual(f.args, c.args, argsMode)) {
      return `${fileLabel} case ${i} (${f.fn}): args differ`;
    }
    if (!structuralEqual(f.expect, c.expect, expectMode)) {
      return `${fileLabel} case ${i} (${f.fn}): expect differs`;
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// P2 self-test: proves the tolerance rule above actually absorbs a rounding
// difference for around.json and actually still catches one for an exact
// file, so deleting/weakening wideTolerance fails `bun run check` itself.
// ---------------------------------------------------------------------------

/** flips the last bit of a wire-format float leaf's bit pattern (its `bits`
 *  hex string is authoritative - see encodeNumber) - a real "one ULP" bump,
 *  not an approximation via arithmetic on the decoded value */
function bumpWireNumberUlp(node) {
  const bits = BigInt(`0x${node.bits}`) + 1n;
  return { ...node, bits: bits.toString(16).padStart(16, '0') };
}

function deepCloneJSON(x) {
  return JSON.parse(JSON.stringify(x));
}

/** self-test-only: bumps the first arcCum leaf of an aroundPose case's
 *  `args.path` by one ULP - a rounding difference inside an *argument*,
 *  which is exactly what the file-wide around.json tolerance in --check
 *  exists to absorb */
function bumpAnAroundArgLeaf(payload) {
  const clone = deepCloneJSON(payload);
  const c = clone.cases.find((item) => item.fn === 'aroundPose');
  if (!c) {
    throw new Error('self-test: no aroundPose case in the around payload to bump');
  }
  c.args.path.arcCum[0] = bumpWireNumberUlp(c.args.path.arcCum[0]);
  return clone;
}

/** self-test-only: bumps a resumeAroundRoute expectation's curveLen by one
 *  ULP - resumeAroundRoute is pinned "exact" (arithmetic only, no trig call
 *  of its own), so this proves the file-wide override in --check applies
 *  even to a function whose own compare rule is exact */
function bumpAResumeExpectationLeaf(payload) {
  const clone = deepCloneJSON(payload);
  const c = clone.cases.find((item) => item.fn === 'resumeAroundRoute' && item.expect !== null);
  if (!c) {
    throw new Error('self-test: no non-null resumeAroundRoute case in the around payload to bump');
  }
  c.expect.curveLen = bumpWireNumberUlp(c.expect.curveLen);
  return clone;
}

/** self-test-only: bumps the first wrapped-float leaf found in a geometry
 *  case's expectation by one ULP - geometry.json stays exact in --check, so
 *  this must be reported as a difference */
function bumpAGeometryExpectationLeaf(payload) {
  const clone = deepCloneJSON(payload);
  const c = clone.cases.find((item) => isWireNumber(item.expect));
  if (!c) {
    throw new Error(
      'self-test: no case with a plain wrapped-float expectation in geometry payload'
    );
  }
  c.expect = bumpWireNumberUlp(c.expect);
  return clone;
}

function runSelfTest() {
  const aroundMod = MODULES.find((mod) => mod.file === 'around.json');
  const geometryMod = MODULES.find((mod) => mod.file === 'geometry.json');
  const aroundPayload = buildPayload(aroundMod);
  const geometryPayload = buildPayload(geometryMod);

  const argBumped = bumpAnAroundArgLeaf(aroundPayload);
  const noDiffOnArg = firstStructuralDiff('around.json', argBumped, aroundPayload, true);
  if (noDiffOnArg !== null) {
    throw new Error(
      `self-test failed: a 1-ULP arcCum argument bump should be absorbed by around.json's --check tolerance, but got: ${noDiffOnArg}`
    );
  }

  const expectBumped = bumpAResumeExpectationLeaf(aroundPayload);
  const noDiffOnExpect = firstStructuralDiff('around.json', expectBumped, aroundPayload, true);
  if (noDiffOnExpect !== null) {
    throw new Error(
      `self-test failed: a 1-ULP resumeAroundRoute expectation bump should be absorbed by around.json's --check tolerance, but got: ${noDiffOnExpect}`
    );
  }

  const geometryBumped = bumpAGeometryExpectationLeaf(geometryPayload);
  const diffOnGeometry = firstStructuralDiff(
    'geometry.json',
    geometryBumped,
    geometryPayload,
    false
  );
  if (diffOnGeometry === null) {
    throw new Error(
      'self-test failed: a 1-ULP geometry.json expectation bump should still be reported as a difference (geometry.json stays exact), but none was reported'
    );
  }

  console.log(
    'conformance --self-test: passed (tolerance absorbs around.json, still catches geometry.json)'
  );
}

function main() {
  const check = process.argv.includes('--check');
  const selfTest = process.argv.includes('--self-test');
  if (selfTest) {
    runSelfTest();
    return;
  }
  // Build every module's payload (which runs every one of its assertions)
  // before writing or checking anything. The generator writes one module's
  // file per iteration; if module N throws, building it happens before any
  // write for module N or later, but writing module 1's file already
  // happened on an earlier iteration in the old single-pass loop, leaving a
  // half-regenerated set on disk. Building the whole array up front means a
  // throw here happens before the write loop below ever starts.
  const built = MODULES.map((mod) => ({ mod, payload: buildPayload(mod) }));

  let stale = false;
  if (check) {
    for (const { mod, payload } of built) {
      const outPath = path.join(outDir, mod.file);
      const label = path.relative(root, outPath);
      if (!existsSync(outPath)) {
        console.error(
          `conformance --check: ${label} is missing - run \`bun run conformance\` and commit the result`
        );
        stale = true;
        continue;
      }
      let committed;
      try {
        committed = JSON.parse(readFileSync(outPath, 'utf-8'));
      } catch (error) {
        console.error(`conformance --check: ${label} is not valid JSON: ${error.message}`);
        stale = true;
        continue;
      }
      // around.json compares every float leaf (args and expect alike)
      // with the tolerance rule in --check, regardless of each case's own
      // pinned compare mode - see the header note above main().
      const wideTolerance = mod.file === 'around.json';
      const diff = firstStructuralDiff(label, payload, committed, wideTolerance);
      if (diff === null) {
        console.log(`conformance --check: ${label} up to date (${payload.cases.length} cases)`);
      } else {
        console.error(
          `conformance --check: ${diff} - run \`bun run conformance\` and commit the result`
        );
        stale = true;
      }
      // the generated Swift literal file, checked the same way: these are
      // plain hex strings and identifiers, deterministic across Node/V8
      // builds, so a byte-exact comparison is exact here (unlike the JSON
      // payload's trig-derived floats above).
      if (mod.swiftFile) {
        const swiftPath = path.join(root, mod.swiftFile);
        const swiftLabel = mod.swiftFile;
        const freshSwift = mod.renderSwiftFile(payload, companionIds());
        if (existsSync(swiftPath) && readFileSync(swiftPath, 'utf-8') === freshSwift) {
          console.log(`conformance --check: ${swiftLabel} up to date`);
        } else if (existsSync(swiftPath)) {
          console.error(
            `conformance --check: ${swiftLabel} is stale - run \`bun run conformance\` and commit the result`
          );
          stale = true;
        } else {
          console.error(
            `conformance --check: ${swiftLabel} is missing - run \`bun run conformance\` and commit the result`
          );
          stale = true;
        }
      }
    }
    if (stale) {
      process.exit(1);
    }
    return;
  }

  if (!existsSync(outDir)) {
    mkdirSync(outDir, { recursive: true });
  }
  for (const { mod, payload } of built) {
    const outPath = path.join(outDir, mod.file);
    const label = path.relative(root, outPath);
    const rendered = renderPayload(payload);
    writeFileSync(outPath, rendered);
    console.log(`conformance: wrote ${label} (${rendered.length} bytes)`);

    if (mod.swiftFile) {
      const swiftPath = path.join(root, mod.swiftFile);
      const renderedSwift = mod.renderSwiftFile(payload, companionIds());
      writeFileSync(swiftPath, renderedSwift);
      console.log(`conformance: wrote ${mod.swiftFile} (${renderedSwift.length} bytes)`);
    }
  }
}

main();
