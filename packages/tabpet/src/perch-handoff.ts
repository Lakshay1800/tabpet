/**
 * Shared lastTab / lastX / lastSeat singleton the real tab perches hand off
 * through. Pure so node tests can replay focus/blur/drag without a renderer.
 * transientSlot never reads or writes this store - a pushed screen must not
 * skew the next genuine tab chase.
 */
import {
  CHASE_SLACK,
  CHASE_TRAIL,
  chaseTargetX,
  PERCH_SIZE,
  shouldSnapToSeat,
  tabCenterX,
  traverseDurationMs,
  TRAVERSE_SPEED_PT_S,
} from './perch-geometry';

export interface PerchHandoffState {
  lastTab: number;
  lastX: number | null;
  lastSeat: number;
}

type FocusKind =
  | 'transient-snap'
  | 'same-tab-snap'
  | 'snap-to-seat'
  | 'reduced-chase'
  | 'run-chase';

export interface FocusPlan {
  kind: FocusKind;
  fromX: number;
  targetX: number;
  /** seatY at the start of this focus (departing altitude → 0 on land) */
  fromSeatY: number;
  /** Altitude held during a run: going up to a raised seat holds the
   * departing height until catch; going down drops immediately so he never floats. */
  runSeatY: number;
  next: PerchHandoffState;
  /** false for transientSlot - the shared singleton stays untouched */
  commitsHandoff: boolean;
}

/** F1: rise onto a higher seat at catch, not mid-run. F2: drop immediately
 *  when the arriving seat is lower so a bounce-back cannot float. */
export function planRunSeatY(fromSeatY: number): number {
  return Math.max(fromSeatY, 0);
}

/** seatY to snap to at focus start, before any chase/catch. run-chase holds
 *  runSeatY (F1/F2); reduced-chase/snap-to-seat start at departing altitude
 *  so a reduce-motion glide to 0 isn't clamped away. */
export function planStartSeatY(plan: Pick<FocusPlan, 'kind' | 'runSeatY' | 'fromSeatY'>): number {
  if (plan.kind === 'run-chase') {
    return plan.runSeatY;
  }
  if (plan.kind === 'reduced-chase' || plan.kind === 'snap-to-seat') {
    return plan.fromSeatY;
  }
  return 0;
}

/** First committed frame, before useFocusEffect; equals planStartSeatY(planFocus(...)) -
 *  a raised seat initialized at 0 instead would flash one frame at bar height. */
export function planMountSeatY(
  handoff: PerchHandoffState,
  args: {
    tab: number;
    screenWidth: number;
    bottomExtra: number;
    transientSlot: boolean;
    reduceMotion: boolean;
    slotCount: number;
    /** measured item centers (window x, bar order); omit for the even-split fallback */
    slotCenters?: readonly number[];
  }
): number {
  return planStartSeatY(planFocus(handoff, args));
}

/** Live lastSeat from bottomExtra and current seatY. Blur must freeze this,
 *  not the destination lastSeat written at focus start, or a bounce-back
 *  thinks it already reached the raised seat. */
export function liveLastSeat(bottomExtra: number, seatY: number): number {
  return bottomExtra - seatY;
}

export function initialPerchHandoff(): PerchHandoffState {
  return { lastTab: 0, lastX: null, lastSeat: 0 };
}

let store: PerchHandoffState = initialPerchHandoff();

export function readPerchHandoff(): PerchHandoffState {
  return store;
}

export function writePerchHandoff(next: PerchHandoffState): void {
  store = next;
}

/** Test-only - module singleton must not leak across suites. */
export function resetPerchHandoffForTest(): void {
  store = initialPerchHandoff();
}

export function planFocus(
  handoff: PerchHandoffState,
  args: {
    tab: number;
    screenWidth: number;
    bottomExtra: number;
    transientSlot: boolean;
    reduceMotion: boolean;
    slotCount: number;
    /** measured item centers (window x, bar order); omit for the even-split fallback */
    slotCenters?: readonly number[];
    /** A route interrupt is being resumed: the caller owns fromX/seatY at
     *  close range, so skip snap-to-seat (would snap through the glass) and
     *  treat a same-tab re-tap as a run-chase from lastX, not a fresh snap. */
    holdRun?: boolean;
  }
): FocusPlan {
  const targetX = tabCenterX(args.tab, args.screenWidth, args.slotCount, args.slotCenters);
  if (args.transientSlot) {
    return {
      kind: 'transient-snap',
      fromX: targetX,
      targetX,
      fromSeatY: 0,
      runSeatY: 0,
      next: handoff,
      commitsHandoff: false,
    };
  }
  if (handoff.lastTab === args.tab && !args.holdRun) {
    return {
      kind: 'same-tab-snap',
      fromX: targetX,
      targetX,
      fromSeatY: 0,
      runSeatY: 0,
      next: { lastTab: args.tab, lastX: null, lastSeat: args.bottomExtra },
      commitsHandoff: true,
    };
  }
  const fromX =
    handoff.lastX ??
    tabCenterX(handoff.lastTab, args.screenWidth, args.slotCount, args.slotCenters);
  const fromSeatY = args.bottomExtra - handoff.lastSeat;
  const runSeatY = planRunSeatY(fromSeatY);
  const next: PerchHandoffState = {
    lastTab: args.tab,
    lastX: null,
    lastSeat: args.bottomExtra,
  };
  const distance = Math.abs(targetX - fromX);
  if (!args.holdRun && shouldSnapToSeat(distance)) {
    return {
      kind: 'snap-to-seat',
      fromX: targetX,
      targetX,
      fromSeatY,
      runSeatY,
      next,
      commitsHandoff: true,
    };
  }
  if (args.reduceMotion) {
    return {
      kind: 'reduced-chase',
      fromX,
      targetX,
      fromSeatY,
      runSeatY,
      next,
      commitsHandoff: true,
    };
  }
  return {
    kind: 'run-chase',
    fromX,
    targetX,
    fromSeatY,
    runSeatY,
    next,
    commitsHandoff: true,
  };
}

/** Blur freezes lastX at the pup's actual x, not the destination he may
 *  still be chasing, and lastSeat at the live altitude (F2). */
export function applyFocusBlur(
  handoff: PerchHandoffState,
  args: { currentX: number; transientSlot: boolean; currentSeat?: number }
): PerchHandoffState {
  if (args.transientSlot) {
    return handoff;
  }
  return {
    ...handoff,
    lastX: args.currentX,
    lastSeat: args.currentSeat ?? handoff.lastSeat,
  };
}

/** Live glass drag: preserve the glass (not the trailing companion) and bar
 *  level, so a release onto another tab starts from where the finger is. */
export function applyDragTrack(handoff: PerchHandoffState, glassTarget: number): PerchHandoffState {
  return { ...handoff, lastX: glassTarget, lastSeat: 0 };
}

/** Release only writes if this instance still owns lastTab - a competing
 *  focus may already have consumed the handoff. */
export function applyDragRelease(
  handoff: PerchHandoffState,
  args: { tab: number; releaseX: number; bottomExtra: number }
): PerchHandoffState {
  if (handoff.lastTab !== args.tab) {
    return handoff;
  }
  return { ...handoff, lastX: args.releaseX, lastSeat: args.bottomExtra };
}

/** How long a release over another slot waits for the host's selection
 *  before going home. Short loses to a busy JS thread - the timer and the
 *  navigation update become runnable together; long only costs a pause
 *  over the wrong tab when no selection ever comes. */
export const RELEASE_GRACE_MS = 800;

export type DragReleasePlan = { kind: 'home' } | { kind: 'await'; slot: number };

/** Whether anything will select the released-over slot. The bar decides, not
 *  the touch source: a wrapped native recognizer still rides a bar whose pill
 *  selects on release. A classic bar has no pill and does not select on
 *  touch-up; a pill the host passed for its own bar does not count. */
export function selectsOnRelease(args: {
  barScrub: 'native' | 'exclusive';
  hasOnDragRelease: boolean;
  nativePill: boolean;
}): boolean {
  return (
    (args.barScrub === 'exclusive' && args.hasOnDragRelease) ||
    (args.barScrub === 'native' && args.nativePill)
  );
}

/** A cancelled drag, and a release on its own slot or over a slot nothing
 *  will select, are a chase only - the companion walks back to its seat.
 *  Only an ended release over a different slot that selectsOnRelease is
 *  worth waiting on. */
export function planDragRelease(args: {
  phase: 'ended' | 'cancelled';
  releaseSlot: number;
  currentSlot: number;
  selectsOnRelease: boolean;
}): DragReleasePlan {
  if (args.phase === 'ended' && args.releaseSlot !== args.currentSlot && args.selectsOnRelease) {
    return { kind: 'await', slot: args.releaseSlot };
  }
  return { kind: 'home' };
}

export type ApproachPlan = { kind: 'spring' } | { kind: 'run'; durationMs: number };

/** Under one glass width a catch reads fine as a spring; farther, a
 *  constant-speed run so a long release-driven approach doesn't teleport. */
export function planApproach(distancePt: number, speedPtS?: number): ApproachPlan {
  const distance = Math.abs(distancePt);
  if (shouldSnapToSeat(distance)) {
    return { kind: 'spring' };
  }
  return { kind: 'run', durationMs: traverseDurationMs(distance, speedPtS) };
}

/** Gap between the glass target and the companion, at engage, above which a
 *  live drag is a far grab rather than a normal spring chase. */
export const FAR_GRAB_PT = PERCH_SIZE;

/** Whether an engaging drag starts far enough from the companion's seat to
 *  need a run instead of the spring follower. */
export function isFarGrab(gapPt: number): boolean {
  return Math.abs(gapPt) > FAR_GRAB_PT;
}

/** dt above this is clamped in stepToward - a stale or idle frame callback
 *  cannot cover more travel than this in one step. */
export const FAR_STEP_MAX_DT_MS = 34;

export type FarSamplePlan = { kind: 'end' } | { kind: 'track'; target: number; facing: 1 | -1 };

/** A far approach ends once the glass is inside the leash's not-chasing edge,
 *  or on a non-finite input. That edge, not a deadband, is what keeps a small
 *  gap from flipping him: beyond it the facing is the sign of the gap. */
export function planFarSample(args: {
  glassX: number;
  currentX: number;
  screenWidth: number;
}): FarSamplePlan {
  if (!Number.isFinite(args.glassX) || !Number.isFinite(args.currentX)) {
    return { kind: 'end' };
  }
  const gap = args.glassX - args.currentX;
  if (Math.abs(gap) <= CHASE_TRAIL + CHASE_SLACK) {
    return { kind: 'end' };
  }
  const facing: 1 | -1 = gap >= 0 ? 1 : -1;
  return { kind: 'track', target: chaseTargetX(args.glassX, facing, args.screenWidth), facing };
}

/** One frame's step toward a target that may move. Stepped per frame rather
 *  than animated: re-issuing an animation per finger sample restarts its
 *  clock and he gains a frame of travel each time. Never returns NaN. */
export function stepToward(
  current: number,
  target: number,
  speedPtS: number,
  dtMs: number
): { x: number; arrived: boolean } {
  'worklet';
  if (
    !Number.isFinite(current) ||
    !Number.isFinite(target) ||
    !Number.isFinite(speedPtS) ||
    !Number.isFinite(dtMs) ||
    speedPtS <= 0
  ) {
    return { x: current, arrived: false };
  }
  const clampedDt = Math.min(Math.max(dtMs, 0), FAR_STEP_MAX_DT_MS);
  const distance = target - current;
  const step = (speedPtS * clampedDt) / 1000;
  if (Math.abs(distance) <= step) {
    return { x: target, arrived: true };
  }
  const direction = distance >= 0 ? 1 : -1;
  return { x: current + direction * step, arrived: false };
}

/** speed when it is a real, positive number, else the shared default - a
 *  host profile's runSpeed is an unvalidated number (a zero or negative
 *  override must not freeze or reverse a run). */
export function sanitizeRunSpeed(speed: number | undefined): number {
  return speed !== undefined && Number.isFinite(speed) && speed > 0 ? speed : TRAVERSE_SPEED_PT_S;
}

/** A drag that arrives by drag must not be mistaken for an end-to-end tap
 *  and sent round the pill - the focused slot wins as the route's origin
 *  whenever the reducer says this focus is arriving by drag, whatever slot
 *  the bar's own hit test actually picked. */
export function focusFromSlot(
  handoffLastTab: number,
  arrivedByDrag: boolean,
  focusedSlot: number
): number {
  return arrivedByDrag ? focusedSlot : handoffLastTab;
}

/** A release that is waiting for its selection. The perch keeps this in a
 *  ref and acts on the effect reduceRelease returns; it decides nothing itself. */
export interface ReleaseState {
  pending: { fromSlot: number; slot: number; generation: number } | null;
  arrival: boolean;
}

export function initialReleaseState(): ReleaseState {
  return { pending: null, arrival: false };
}

export type ReleaseEvent =
  | { type: 'release'; plan: DragReleasePlan; fromSlot: number; generation: number }
  | { type: 'began' }
  | { type: 'engage' }
  | { type: 'focus-cleanup' }
  | { type: 'focus-body'; transientSlot: boolean }
  | { type: 'timer'; mounted: boolean; generation: number; renderedSlot: number }
  | { type: 'abort' }
  | { type: 'unmount' };

export type ReleaseEffect =
  | 'none'
  | 'go-home'
  | 'await'
  | 'clear-timer'
  | 'hold-generation'
  | 'arrived';

/** Unmounted or a newer motion: drop the wait. Slot already changed: keep
 *  pending, the focus cleanup about to run turns it into an arrival. */
function reduceTimer(
  state: ReleaseState,
  event: { mounted: boolean; generation: number; renderedSlot: number }
): { state: ReleaseState; effect: ReleaseEffect } {
  if (state.pending === null) {
    return { state, effect: 'none' };
  }
  const { pending } = state;
  if (!event.mounted || event.generation !== pending.generation) {
    return { state: { ...state, pending: null }, effect: 'none' };
  }
  if (event.renderedSlot !== pending.fromSlot) {
    return { state, effect: 'none' };
  }
  return { state: { ...state, pending: null }, effect: 'go-home' };
}

/** began keeps state: the touch may be a tap, and ending the wait on it
 *  strands him over the wrong tab with no fallback. focus-cleanup ends any
 *  wait, since the focus body re-plans x. */
export function reduceRelease(
  state: ReleaseState,
  event: ReleaseEvent
): { state: ReleaseState; effect: ReleaseEffect } {
  switch (event.type) {
    case 'release': {
      if (event.plan.kind === 'home') {
        return { state: { ...state, pending: null }, effect: 'go-home' };
      }
      return {
        state: {
          ...state,
          pending: {
            fromSlot: event.fromSlot,
            slot: event.plan.slot,
            generation: event.generation,
          },
        },
        effect: 'await',
      };
    }
    case 'began': {
      return { state, effect: state.pending === null ? 'none' : 'hold-generation' };
    }
    case 'engage': {
      const hadPending = state.pending !== null;
      return { state: { ...state, pending: null }, effect: hadPending ? 'clear-timer' : 'none' };
    }
    case 'focus-cleanup': {
      const hadPending = state.pending !== null;
      return {
        state: { pending: null, arrival: hadPending },
        effect: hadPending ? 'clear-timer' : 'none',
      };
    }
    case 'focus-body': {
      const arrived = state.arrival && !event.transientSlot;
      return { state: { ...state, arrival: false }, effect: arrived ? 'arrived' : 'none' };
    }
    case 'timer': {
      return reduceTimer(state, event);
    }
    case 'abort': {
      const hadPending = state.pending !== null;
      return { state: { ...state, pending: null }, effect: hadPending ? 'clear-timer' : 'none' };
    }
    case 'unmount': {
      const hadPending = state.pending !== null;
      return {
        state: { pending: null, arrival: false },
        effect: hadPending ? 'clear-timer' : 'none',
      };
    }
    default: {
      return { state, effect: 'none' };
    }
  }
}
