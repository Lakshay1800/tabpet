/**
 * Around route (tier 1): the scenic path for an end-to-end tab tap - off the
 * pill's near end, upside down along the underside, up the far end. One
 * continuous arc-length-parametrised path along the pill's real outline (a
 * half-ellipse wraps each rounded end cap) keeps the feet on the glass the
 * whole way, driven by one progress shared value so velocity never hits
 * zero mid-route.
 */
import { PERCH_SIZE } from './perch-geometry';

/** bars with fewer slots than this never route around (2 tabs = an adjacent hop) */
export const AROUND_MIN_SLOT_COUNT = 3;
/** one constant speed for the whole route - straight legs and arcs alike */
export const AROUND_SPEED_PT_S = 300;
/** arc-length samples per half-ellipse; phi/psi step by pi/K between them */
const ARC_SAMPLES = 32;

export interface PillFrame {
  x: number;
  y: number;
  width: number;
  height: number;
}

/** only a first-slot <-> last-slot tap takes the scenic route; a stop two or
 * three slots in stays on the pill */
export function isEndToEnd(fromSlot: number, toSlot: number, slotCount: number): boolean {
  return (
    slotCount >= AROUND_MIN_SLOT_COUNT &&
    Math.min(fromSlot, toSlot) === 0 &&
    Math.max(fromSlot, toSlot) === slotCount - 1
  );
}

export function shouldRouteAround(args: {
  fromSlot: number;
  toSlot: number;
  slotCount: number;
  aroundRoute: boolean;
  flightLift: number;
  pill: PillFrame | null | undefined;
  reduceMotion: boolean;
}): boolean {
  return (
    isEndToEnd(args.fromSlot, args.toSlot, args.slotCount) &&
    args.aroundRoute &&
    args.flightLift === 0 &&
    args.pill !== null &&
    args.pill !== undefined &&
    !args.reduceMotion
  );
}

/** plain data: lives in a shared value, captured by worklets */
export interface AroundPath {
  exitSide: -1 | 1; // -1 = the pill's left end
  enterSide: -1 | 1;
  /** the one facing for the whole route: toward the exit end */
  facing: -1 | 1;
  /** sign of the spin; rotation sweeps spin * 360 over the whole route */
  spin: -1 | 1;
  /** distance from the box center down to the drawn feet: the rotation pivot */
  pivot: number;
  /** window-space feet y while seated (seatY = 0) - both straight legs sit here */
  seatFeetY: number;
  /** feet y at the bottom of the hang, minus seatFeetY (seatY DOWNWARD) */
  underY: number;
  /** ellipse center x for the exit-end and enter-end arcs */
  cxExit: number;
  cxEnter: number;
  /** both arcs share this center y */
  cy: number;
  /** ellipse semi-axes: a horizontal (= pill end radius), b vertical */
  a: number;
  b: number;
  /** feet x at departure / destination (translateX + PERCH_SIZE / 2) */
  feetX0: number;
  targetFeetX: number;
  /** cumulative chord length at phi_k = k*pi/ARC_SAMPLES, shared by both arcs */
  arcCum: number[];
  arcLen: number;
  /** cumulative arc-length boundaries [s1, s2, s3, s4, s5] of the 5 legs */
  legs: number[];
  totalLen: number;
  totalMs: number;
}

/** distance from the perch box center down to the drawn feet; the around
 * route rotates about this point so the feet stay on the pill's outline */
export function routePivot(spriteScale: number, footPad: number): number {
  return (PERCH_SIZE / 2 - footPad) * spriteScale;
}

function signOrFallback(delta: number, fallback: -1 | 1): -1 | 1 {
  if (delta > 0) {
    return 1;
  }
  if (delta < 0) {
    return -1;
  }
  return fallback;
}

/** cumulative chord length of the canonical half-ellipse (a*sin t, b*cos t),
 * t = 0..pi in K steps; both arcs are reflections of this, so share it */
function computeArcCum(a: number, b: number, k: number): number[] {
  const cum: number[] = [0];
  let prevX = 0;
  let prevY = b;
  for (let i = 1; i <= k; i += 1) {
    const t = (i * Math.PI) / k;
    const x = a * Math.sin(t);
    const y = b * Math.cos(t);
    cum.push(cum[i - 1] + Math.hypot(x - prevX, y - prevY));
    prevX = x;
    prevY = y;
  }
  return cum;
}

export function planAroundPath(args: {
  fromX: number; // perch translateX at departure
  targetX: number; // perch translateX of the destination slot
  pill: PillFrame;
  windowWidth: number;
  spriteScale: number; // profile.scale
  footPad: number; // cell footPad (profile.footPad ?? 11)
  headPad: number; // profile.headPad
  seatOffset: number; // perch's bottom offset from the bar top: (profile.seatLift ?? 6) - footPad
}): AroundPath {
  const { fromX, targetX, pill, spriteScale, footPad, seatOffset } = args;

  const travel = signOrFallback(targetX - fromX, 1);
  const exitSide: -1 | 1 = travel === 1 ? -1 : 1;
  const enterSide = travel;
  const facing = exitSide;
  const spin = exitSide; // facing the left end = counter-clockwise

  const pivot = routePivot(spriteScale, footPad);
  const boxCenterY0 = pill.y - seatOffset - PERCH_SIZE / 2;
  const seatFeetY = boxCenterY0 + pivot;
  const d = pill.y - seatFeetY; // feet sit d above the pill top
  const R = pill.height / 2;
  const a = R;
  const b = R + d;
  const cy = pill.y + R;
  const cxExit = exitSide === -1 ? pill.x + R : pill.x + pill.width - R;
  const cxEnter = enterSide === -1 ? pill.x + R : pill.x + pill.width - R;
  const hangFeetY = cy + b; // == pillBottom + d
  const underY = hangFeetY - seatFeetY;
  const feetX0 = fromX + PERCH_SIZE / 2;
  const targetFeetX = targetX + PERCH_SIZE / 2;

  const arcCum = computeArcCum(a, b, ARC_SAMPLES);
  const arcLen = arcCum[ARC_SAMPLES];

  // no special case if feetX0 is already past cxExit (seat inside the cap):
  // exitRun is still the distance travelled toward cxExit
  const s1 = Math.abs(cxExit - feetX0);
  const s2 = s1 + arcLen;
  const s3 = s2 + Math.abs(cxEnter - cxExit);
  const s4 = s3 + arcLen;
  const s5 = s4 + Math.abs(targetFeetX - cxEnter);
  const legs = [s1, s2, s3, s4, s5];
  const totalLen = s5;
  const totalMs = (totalLen / AROUND_SPEED_PT_S) * 1000;

  return {
    exitSide,
    enterSide,
    facing,
    spin,
    pivot,
    seatFeetY,
    underY,
    cxExit,
    cxEnter,
    cy,
    a,
    b,
    feetX0,
    targetFeetX,
    arcCum,
    arcLen,
    legs,
    totalLen,
    totalMs,
  };
}

/** invert arc length -> phi by linear interpolation in arcCum */
function phiFromArcLength(arcCum: number[], u: number): number {
  'worklet';
  const k = arcCum.length - 1;
  const uc = Math.min(Math.max(u, 0), arcCum[k]);
  let i = 0;
  while (i < k - 1 && arcCum[i + 1] < uc) {
    i += 1;
  }
  const segLen = arcCum[i + 1] - arcCum[i];
  const frac = segLen > 0 ? (uc - arcCum[i]) / segLen : 0;
  return ((i + frac) * Math.PI) / k;
}

/** the ellipse's surface-normal angle at t, in degrees: 0 at t=0, 180 at t=pi */
function normalAngleDeg(t: number, a: number, b: number): number {
  'worklet';
  return (Math.atan2(Math.sin(t) / a, Math.cos(t) / b) * 180) / Math.PI;
}

/** pose along the path at arc length s (0 = departure, totalLen = arrival) */
export function aroundPose(
  path: AroundPath,
  s: number
): { x: number; seatY: number; rotation: number } {
  'worklet';
  const sc = Math.min(Math.max(s, 0), path.totalLen);
  const [s1, s2, s3, s4, s5] = path.legs;
  const hangFeetY = path.seatFeetY + path.underY;

  let feetX: number;
  let feetY: number;
  let rotation: number;

  if (sc <= s1) {
    const t = s1 > 0 ? sc / s1 : 1;
    feetX = path.feetX0 + (path.cxExit - path.feetX0) * t;
    feetY = path.seatFeetY;
    rotation = 0;
  } else if (sc <= s2) {
    const phi = phiFromArcLength(path.arcCum, sc - s1);
    feetX = path.cxExit + path.exitSide * path.a * Math.sin(phi);
    feetY = path.cy - path.b * Math.cos(phi);
    rotation = path.spin * normalAngleDeg(phi, path.a, path.b);
  } else if (sc <= s3) {
    const legLen = s3 - s2;
    const t = legLen > 0 ? (sc - s2) / legLen : 1;
    feetX = path.cxExit + (path.cxEnter - path.cxExit) * t;
    feetY = hangFeetY;
    rotation = path.spin * 180;
  } else if (sc <= s4) {
    const psi = phiFromArcLength(path.arcCum, sc - s3);
    feetX = path.cxEnter + path.enterSide * path.a * Math.sin(psi);
    feetY = path.cy + path.b * Math.cos(psi);
    rotation = path.spin * (180 + normalAngleDeg(psi, path.a, path.b));
  } else {
    const legLen = s5 - s4;
    const t = legLen > 0 ? (sc - s4) / legLen : 1;
    feetX = path.cxEnter + (path.targetFeetX - path.cxEnter) * t;
    feetY = path.seatFeetY;
    rotation = path.spin * 360;
  }

  return {
    x: feetX - PERCH_SIZE / 2,
    seatY: feetY - path.seatFeetY,
    rotation,
  };
}

/** plain data: a mid-route interrupt resumed from wherever the companion actually
 * is - the outline segment back to the base path's near cap, then a
 * straight run to the new target. Lives in a shared value, read by worklets. */
export interface ResumedRoute {
  base: AroundPath;
  /** arc length on base where the interrupt happened */
  startS: number;
  /** base.legs[3] going forward, base.legs[0] going backward */
  endS: number;
  /** +1 continues toward the far cap, -1 backs toward the near cap */
  dir: -1 | 1;
  curveLen: number;
  /** feet x where the curve hands off to the straight tail */
  tailFromFeetX: number;
  /** feet x of the new target */
  tailToFeetX: number;
  tailLen: number;
  totalLen: number;
  totalMs: number;
  facing: -1 | 1;
  /** rotation at the end of the curve segment, held through the tail */
  endRotation: number;
}

/** null when s is on a seat-line leg (1 or 5) - the caller falls back to the
 * plain run-chase there, since seatY/rotation are already at rest. */
export function resumeAroundRoute(
  base: AroundPath,
  s: number,
  targetX: number
): ResumedRoute | null {
  // oxlint-disable-next-line unicorn/no-unreadable-array-destructuring -- only s1/s4 matter here
  const [s1, , , s4] = base.legs;
  if (s <= s1 || s >= s4) {
    return null;
  }
  const targetFeetX = targetX + PERCH_SIZE / 2;
  const forwardLen = s4 - s + Math.abs(targetFeetX - base.cxEnter);
  const backwardLen = s - s1 + Math.abs(targetFeetX - base.cxExit);
  const dir: -1 | 1 = backwardLen < forwardLen ? -1 : 1;
  const endS = dir === 1 ? s4 : s1;
  const curveLen = Math.abs(endS - s);
  const tailFromFeetX = dir === 1 ? base.cxEnter : base.cxExit;
  const tailToFeetX = targetFeetX;
  const tailLen = Math.abs(tailToFeetX - tailFromFeetX);
  const totalLen = curveLen + tailLen;
  const flippedFacing: -1 | 1 = base.facing === 1 ? -1 : 1;
  const facing: -1 | 1 = dir === 1 ? base.facing : flippedFacing;
  const endRotation = dir === 1 ? base.spin * 360 : 0;

  return {
    base,
    startS: s,
    endS,
    dir,
    curveLen,
    tailFromFeetX,
    tailToFeetX,
    tailLen,
    totalLen,
    totalMs: (totalLen / AROUND_SPEED_PT_S) * 1000,
    facing,
    endRotation,
  };
}

/** pose along a resumed route at progress u (0 = interrupt point, totalLen =
 * new target); u <= curveLen retraces the base outline, past that is the
 * straight tail to the target at rest height/rotation */
export function resumedPose(
  route: ResumedRoute,
  u: number
): { x: number; seatY: number; rotation: number } {
  'worklet';
  const uc = Math.min(Math.max(u, 0), route.totalLen);
  if (uc <= route.curveLen) {
    return aroundPose(route.base, route.startS + route.dir * uc);
  }
  const t = route.tailLen > 0 ? (uc - route.curveLen) / route.tailLen : 1;
  const feetX = route.tailFromFeetX + (route.tailToFeetX - route.tailFromFeetX) * t;
  return {
    x: feetX - PERCH_SIZE / 2,
    seatY: 0,
    rotation: route.endRotation,
  };
}

/** maps resumed-route progress u back to the base path's s while still on
 * the curve; null once u is on the straight tail (a second interrupt there
 * is a plain run, not a second resume) */
export function resumedBaseS(route: ResumedRoute, u: number): number | null {
  if (u < route.curveLen) {
    return route.startS + route.dir * u;
  }
  return null;
}
