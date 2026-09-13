/**
 * Shared lastTab / lastX / lastSeat singleton the real tab perches hand off
 * through. Pure so node tests can replay focus/blur/drag without a renderer.
 * transientSlot never reads or writes this store - a pushed screen must not
 * skew the next genuine tab chase.
 */
import { tabCenterX, shouldSnapToSeat } from './perch-geometry';

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
