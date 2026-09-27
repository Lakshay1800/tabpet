import { ok, strictEqual } from 'node:assert';
/**
 * Replays conformance/*.json against the real exports of the four modules
 * the fixtures were generated from. Every wrapped float is decoded from its
 * `bits` (authoritative, not `value`) before comparison. Fails if a fixture
 * names a function its module does not export, and fails if a module
 * exports a pure function that no fixture covers.
 */
import { readFileSync } from 'node:fs';
import path from 'node:path';

import * as Around from './perch-around';
import * as Geometry from './perch-geometry';
import * as Handoff from './perch-handoff';
import * as PoseDissolve from './pose-dissolve';

const conformanceDir = path.resolve(import.meta.dirname, '../../../conformance');

// module-state mutators, not pure functions - the generator never fixtures these
const STATEFUL_SKIP = new Set([
  'readPerchHandoff',
  'writePerchHandoff',
  'resetPerchHandoffForTest',
]);

type Compare = 'exact' | 'tolerance';
interface FixtureCase {
  fn: string;
  args: unknown;
  expect: unknown;
  compare: Compare;
}
interface FixtureFile {
  module: string;
  source: string;
  constants: Record<string, unknown>;
  cases: FixtureCase[];
}

function loadFixture(file: string): FixtureFile {
  const raw = readFileSync(path.join(conformanceDir, file), 'utf-8');
  return JSON.parse(raw) as FixtureFile;
}

// exactly 16 lowercase hex digits - Buffer.from silently truncates/
// ignores invalid hex instead of throwing, which would decode a corrupt
// fixture into a wrong-but-plausible double rather than failing the test
const BITS_PATTERN = /^[0-9a-f]{16}$/u;

/** decodes a wrapped {bits, value} leaf from its bits (authoritative);
 *  everything else (plain ints/bools/strings, arrays, objects, null)
 *  recurses or passes through unchanged */
function decodeValue(v: unknown): unknown {
  if (v === null) {
    return null;
  }
  if (Array.isArray(v)) {
    return v.map(decodeValue);
  }
  if (typeof v === 'object') {
    const obj = v as Record<string, unknown>;
    const keys = Object.keys(obj);
    if (keys.length === 2 && typeof obj.bits === 'string' && 'value' in obj) {
      ok(BITS_PATTERN.test(obj.bits), `malformed bits string: ${JSON.stringify(obj.bits)}`);
      return Buffer.from(obj.bits, 'hex').readDoubleBE(0);
    }
    const out: Record<string, unknown> = {};
    for (const k of keys) {
      out[k] = decodeValue(obj[k]);
    }
    return out;
  }
  return v;
}

/** NaN matches only NaN, regardless of compare mode. "exact" is otherwise
 *  bit-identical (Object.is, so it also tells Infinity from -Infinity and
 *  +0 from -0 for free). "tolerance" treats an infinite value as an exact
 *  match only against the same infinity - the old rule's
 *  `|a - b| <= 1e-9 * max(1, |a|, |b|)` made Infinity != Infinity (NaN on
 *  both sides of <=) and Infinity == 5 (Infinity <= Infinity is true). */
function numbersEqual(a: number, b: number, compare: Compare): boolean {
  if (Number.isNaN(a) || Number.isNaN(b)) {
    return Number.isNaN(a) && Number.isNaN(b);
  }
  if (compare === 'exact') {
    return Object.is(a, b);
  }
  if (!Number.isFinite(a) || !Number.isFinite(b)) {
    return a === b;
  }
  const scale = Math.max(1, Math.abs(a), Math.abs(b));
  return Math.abs(a - b) <= 1e-9 * scale;
}

// direct unit checks of the tolerance rule, independent of any fixture
function checkToleranceRule(): void {
  const checks: [number, number, boolean][] = [
    [Infinity, Infinity, true],
    [Infinity, 5, false],
    [-Infinity, Infinity, false],
    [Number.NaN, Number.NaN, true],
    [Number.NaN, 1, false],
    [1, 1 + 1e-12, true],
    [1, 1.001, false],
  ];
  for (const [a, b, expected] of checks) {
    strictEqual(
      numbersEqual(a, b, 'tolerance'),
      expected,
      `tolerance rule: numbersEqual(${a}, ${b}) should be ${expected}`
    );
  }
}

/** structural comparison of two already-decoded values; every numeric leaf
 *  (plain int or decoded double alike) goes through the same compare rule -
 *  exact trivially holds for plain ints, so no per-field type table is needed */
function deepCompare(actual: unknown, expected: unknown, compare: Compare): boolean {
  if (typeof actual === 'number' && typeof expected === 'number') {
    return numbersEqual(actual, expected, compare);
  }
  if (actual === null || expected === null) {
    return actual === expected;
  }
  if (Array.isArray(actual) && Array.isArray(expected)) {
    return (
      actual.length === expected.length &&
      actual.every((v, i) => deepCompare(v, expected[i], compare))
    );
  }
  if (typeof actual === 'object' && typeof expected === 'object') {
    const a = actual as Record<string, unknown>;
    const b = expected as Record<string, unknown>;
    const keys = new Set([...Object.keys(a), ...Object.keys(b)]);
    for (const k of keys) {
      if (!deepCompare(a[k], b[k], compare)) {
        return false;
      }
    }
    return true;
  }
  return actual === expected;
}

// per-function invoke: converts a fully-decoded args object into the actual
// positional call. Two functions have a real default-value parameter where
// JSON null (representing "omitted") must become JS undefined, not null -
// `null` would bypass the default (traverseDurationMs's speedPtS,
// planPoseDissolve's opts); every other optional/nullable field is passed
// through as-is since the source treats null and undefined identically there
// (optional chaining or `??`).
// oxlint-disable-next-line typescript/no-explicit-any -- decoded fixture args are dynamically shaped; each invoker destructures only the fields its function needs
const invokers: Record<string, Record<string, (a: any) => unknown>> = {
  'perch-geometry': {
    tabCenterX: (a) =>
      Geometry.tabCenterX(a.tab, a.screenWidth, a.slotCount, a.slotCenters ?? undefined),
    nearestSlot: (a) =>
      Geometry.nearestSlot(a.x, a.screenWidth, a.slotCount, a.slotCenters ?? undefined),
    glassTargetX: (a) => Geometry.glassTargetX(a.fingerX, a.screenWidth),
    chaseTargetX: (a) => Geometry.chaseTargetX(a.glassX, a.direction, a.screenWidth),
    chaseStep: (a) => Geometry.chaseStep(a.glassX, a.currentX, a.currentFacing, a.chasing),
    travelFacing: (a) => Geometry.travelFacing(a.targetX, a.currentX, a.currentFacing),
    shouldSnapToSeat: (a) => Geometry.shouldSnapToSeat(a.distancePt),
    traverseDurationMs: (a) =>
      a.speedPtS === null
        ? Geometry.traverseDurationMs(a.distancePt)
        : Geometry.traverseDurationMs(a.distancePt, a.speedPtS),
    seatedFootPad: (a) => Geometry.seatedFootPad(a.footPad, a.scale),
  },
  'perch-around': {
    isEndToEnd: (a) => Around.isEndToEnd(a.fromSlot, a.toSlot, a.slotCount),
    shouldRouteAround: (a) => Around.shouldRouteAround(a),
    routePivot: (a) => Around.routePivot(a.spriteScale, a.footPad),
    planAroundPath: (a) => Around.planAroundPath(a),
    aroundPose: (a) => Around.aroundPose(a.path, a.s),
    resumeAroundRoute: (a) => Around.resumeAroundRoute(a.base, a.s, a.targetX),
    resumedPose: (a) => Around.resumedPose(a.route, a.u),
    resumedBaseS: (a) => Around.resumedBaseS(a.route, a.u),
  },
  'perch-handoff': {
    planRunSeatY: (a) => Handoff.planRunSeatY(a.fromSeatY),
    planStartSeatY: (a) => Handoff.planStartSeatY(a),
    planMountSeatY: (a) => Handoff.planMountSeatY(a.handoff, a.args),
    liveLastSeat: (a) => Handoff.liveLastSeat(a.bottomExtra, a.seatY),
    initialPerchHandoff: () => Handoff.initialPerchHandoff(),
    planFocus: (a) => Handoff.planFocus(a.handoff, a.args),
    applyFocusBlur: (a) => Handoff.applyFocusBlur(a.handoff, a.args),
    applyDragTrack: (a) => Handoff.applyDragTrack(a.handoff, a.glassTarget),
    applyDragRelease: (a) => Handoff.applyDragRelease(a.handoff, a.args),
    planDragRelease: (a) => Handoff.planDragRelease(a),
    selectsOnRelease: (a) => Handoff.selectsOnRelease(a),
    planApproach: (a) =>
      a.speedPtS === null
        ? Handoff.planApproach(a.distancePt)
        : Handoff.planApproach(a.distancePt, a.speedPtS),
    isFarGrab: (a) => Handoff.isFarGrab(a.gapPt),
    planFarSample: (a) => Handoff.planFarSample(a),
    stepToward: (a) => Handoff.stepToward(a.current, a.target, a.speedPtS, a.dtMs),
    sanitizeRunSpeed: (a) => Handoff.sanitizeRunSpeed(a.speed === null ? undefined : a.speed),
    focusFromSlot: (a) => Handoff.focusFromSlot(a.handoffLastTab, a.arrivedByDrag, a.focusedSlot),
    initialReleaseState: () => Handoff.initialReleaseState(),
    reduceRelease: (a) => Handoff.reduceRelease(a.state, a.event),
  },
  'pose-dissolve': {
    planPoseDissolve: (a) =>
      a.opts === null
        ? PoseDissolve.planPoseDissolve(a.previous, a.next)
        : PoseDissolve.planPoseDissolve(a.previous, a.next, {
            reduceMotion: a.opts.reduceMotion === null ? undefined : a.opts.reduceMotion,
          }),
    poseDissolveApplyOrder: (a) => PoseDissolve.poseDissolveApplyOrder(a.plan),
    shouldResetIncomingFrame: (a) => PoseDissolve.shouldResetIncomingFrame(a.previous, a.next),
    shouldSnapBusyIdleFrameToRest: (a) => PoseDissolve.shouldSnapBusyIdleFrameToRest(a.currentPose),
  },
};

// the compare mode per function is pinned here, mirroring the table in
// scripts/gen-conformance.mjs's header - a fixture disagreeing with this
// table (e.g. a function that gained a trig call without updating either
// side) fails loudly instead of silently comparing with the wrong rule
const EXPECTED_COMPARE: Record<string, Compare> = {
  tabCenterX: 'exact',
  nearestSlot: 'exact',
  glassTargetX: 'exact',
  chaseTargetX: 'exact',
  chaseStep: 'exact',
  travelFacing: 'exact',
  shouldSnapToSeat: 'exact',
  traverseDurationMs: 'exact',
  seatedFootPad: 'exact',
  isEndToEnd: 'exact',
  shouldRouteAround: 'exact',
  routePivot: 'exact',
  planAroundPath: 'tolerance',
  aroundPose: 'tolerance',
  resumeAroundRoute: 'exact',
  resumedPose: 'tolerance',
  resumedBaseS: 'exact',
  planRunSeatY: 'exact',
  planStartSeatY: 'exact',
  planMountSeatY: 'exact',
  liveLastSeat: 'exact',
  initialPerchHandoff: 'exact',
  planFocus: 'exact',
  applyFocusBlur: 'exact',
  applyDragTrack: 'exact',
  applyDragRelease: 'exact',
  planDragRelease: 'exact',
  selectsOnRelease: 'exact',
  planApproach: 'exact',
  isFarGrab: 'exact',
  planFarSample: 'exact',
  stepToward: 'exact',
  sanitizeRunSpeed: 'exact',
  focusFromSlot: 'exact',
  initialReleaseState: 'exact',
  reduceRelease: 'exact',
  planPoseDissolve: 'exact',
  poseDissolveApplyOrder: 'exact',
  shouldResetIncomingFrame: 'exact',
  shouldSnapBusyIdleFrameToRest: 'exact',
};

const namespaces: Record<string, Record<string, unknown>> = {
  'perch-geometry': Geometry as unknown as Record<string, unknown>,
  'perch-around': Around as unknown as Record<string, unknown>,
  'perch-handoff': Handoff as unknown as Record<string, unknown>,
  'pose-dissolve': PoseDissolve as unknown as Record<string, unknown>,
};

const FILES = ['geometry.json', 'around.json', 'handoff.json', 'pose-dissolve.json'];

function exportedPureFunctionNames(ns: Record<string, unknown>): Set<string> {
  const names = new Set<string>();
  for (const [name, value] of Object.entries(ns)) {
    if (typeof value === 'function' && !STATEFUL_SKIP.has(name)) {
      names.add(name);
    }
  }
  return names;
}

function main(): void {
  checkToleranceRule();
  let total = 0;
  for (const file of FILES) {
    const fixture = loadFixture(file);
    const moduleInvokers = invokers[fixture.module];
    ok(moduleInvokers, `no invoker table registered for module ${fixture.module}`);
    const ns = namespaces[fixture.module];
    ok(ns, `no export namespace registered for module ${fixture.module}`);

    // every pinned constant must match this module's own export exactly -
    // bit-identical, since these are literal numbers, never a trig result
    const constantNames = Object.keys(fixture.constants);
    ok(constantNames.length > 0, `${fixture.module}: fixture carries no pinned constants`);
    for (const name of constantNames) {
      const expected = decodeValue(fixture.constants[name]) as number;
      const actual = ns[name];
      ok(
        typeof actual === 'number',
        `${fixture.module}: constant ${name} is not exported as a number by the module`
      );
      ok(
        numbersEqual(actual as number, expected, 'exact'),
        `${fixture.module}: constant ${name} mismatch: module=${actual} fixture=${expected}`
      );
    }

    const exported = exportedPureFunctionNames(ns);
    const covered = new Set(fixture.cases.map((c) => c.fn));

    for (const fn of covered) {
      ok(
        exported.has(fn),
        `${fixture.module}: fixture names ${fn}, which the module does not export`
      );
    }
    for (const fn of exported) {
      ok(
        covered.has(fn),
        `${fixture.module}: exported pure function ${fn} has no fixture coverage`
      );
    }

    for (const c of fixture.cases) {
      const invoke = moduleInvokers[c.fn];
      ok(invoke, `${fixture.module}: no invoker registered for ${c.fn}`);
      // reject any compare string other than exact/tolerance, and pin
      // the mode per function so a fixture can't silently disagree with it
      ok(
        c.compare === 'exact' || c.compare === 'tolerance',
        `${fixture.module}.${c.fn}: unknown compare mode ${JSON.stringify(c.compare)}`
      );
      ok(
        EXPECTED_COMPARE[c.fn] === c.compare,
        `${fixture.module}.${c.fn}: fixture says compare=${c.compare}, expected ${EXPECTED_COMPARE[c.fn]}`
      );
      const args = decodeValue(c.args);
      const expected = decodeValue(c.expect);
      const actual = invoke(args);
      ok(
        deepCompare(actual, expected, c.compare),
        `${fixture.module}.${c.fn}: mismatch\n  args: ${JSON.stringify(args)}\n  expected: ${JSON.stringify(expected)}\n  actual: ${JSON.stringify(actual)}`
      );
      total += 1;
    }
  }
  strictEqual(total > 0, true, 'conformance: no cases were replayed');
  // oxlint-disable-next-line no-console -- test runner reporting
  console.log(`conformance: ${total} cases passed across ${FILES.length} fixtures`);
}

main();
