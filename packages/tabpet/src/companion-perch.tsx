/**
 * Companion perch: a JS overlay riding the host's tab bar. Committed tab
 * changes chase after a short reaction delay; live drags trail the glass.
 * Sit is the rest pose. An opted-in profile can take the "around" route
 * (off one pill end, under it, up the other) instead of a straight chase.
 */
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { StyleSheet, useWindowDimensions } from 'react-native';
import Animated, {
  cancelAnimation,
  Easing,
  runOnJS,
  useAnimatedReaction,
  useAnimatedStyle,
  useFrameCallback,
  useReducedMotion,
  useSharedValue,
  withDelay,
  withSequence,
  withSpring,
  withTiming,
} from 'react-native-reanimated';
import type { FrameInfo } from 'react-native-reanimated';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { useCompanionConfig, useCompanionId } from './companion-provider';
import { CompanionSprite, resolveProfile } from './companion-sprite';
import { isCompanionBusy, subscribeCompanionBusy } from './companion-state';
import { nativeTabBarFingerSource } from './finger-source';
import type { FingerSource } from './finger-source';
import { nativeTabBarLayout, setGlassPanScrub } from './native/glass-pan';
import type { BarScrub } from './native/glass-pan';
import type { AroundPath, PillFrame, ResumedRoute } from './perch-around';
import {
  aroundPose,
  planAroundPath,
  resumeAroundRoute,
  resumedBaseS,
  resumedPose,
  routePivot,
  shouldRouteAround,
} from './perch-around';
import {
  chaseStep,
  chaseTargetX,
  nearestSlot,
  FACING_DEADBAND,
  glassTargetX,
  PERCH_SIZE,
  seatedFootPad,
  tabCenterX,
  travelFacing,
  traverseDurationMs,
} from './perch-geometry';
import {
  applyDragRelease,
  applyDragTrack,
  applyFocusBlur,
  focusFromSlot,
  initialReleaseState,
  isFarGrab,
  liveLastSeat,
  planApproach,
  planDragRelease,
  planFarSample,
  planFocus,
  planMountSeatY,
  planStartSeatY,
  readPerchHandoff,
  reduceRelease,
  RELEASE_GRACE_MS,
  sanitizeRunSpeed,
  selectsOnRelease,
  stepToward,
  writePerchHandoff,
} from './perch-handoff';
import type { DragReleasePlan, ReleaseState } from './perch-handoff';
import { shouldApplyArrive } from './perch-reentry';
import { retryMeasure } from './perch-remeasure';
import type { PupPose } from './pose-dissolve';

/** empty pt under the drawn feet in a cell; profile.footPad overrides */
const SPRITE_FOOT_PAD = 11;
const BAR_TOP_ABOVE_INSET = 6;
/** finger travel before a bar gesture counts as a drag instead of a tap */
const DRAG_ENGAGE_PT = 6;

// Reanimated 4 physical springs fire `finished` seconds after the visual
// settle, so arrive() below is generation-gated rather than driven off it.
// Spring/hop/flight values live on the active profile (registry.ts).
const CHASE_REACTION_MS = 65;
const REDUCED_DURATION_MS = 200;
const HOP_STEP_MS = 120;

export interface CompanionAnchor {
  slotCount: number;
  slotIndex: number;
  /** Window-space x centers of the slots (custom bars). Omitted: measured
   *  from the native tab bar, else an even split of the screen width. */
  slotCenters?: readonly number[];
  /** Window-space y of the bar's top edge. Omitted: measured from the
   *  native tab bar, else the bottom safe-area inset is assumed to be it. */
  barTop?: number;
  /** Window-space frame of the floating pill. Omitted: measured from the
   *  native tab bar. Null: no pill (classic UITabBar) - never route around. */
  pill?: PillFrame | null;
}

export interface CompanionPerchProps {
  anchor: CompanionAnchor;
  onAction?: () => void;
  actionLabel?: string;
  bottomExtra?: number;
  /** A pushed screen's own slot, not a real tab - `anchor.slotIndex` is only
   *  its X-coordinate. Snaps instantly (no chase) and never reads/writes
   *  the shared perch-handoff singleton the real tab screens use. */
  transientSlot?: boolean;
  /** Host's own focus signal. Chase/drag effects are inert while false,
   *  matching a focus-effect's mount/unmount semantics. */
  focused?: boolean;
  /** undefined = the native tab-bar recognizer (once, memoised); null =
   *  disables the drag-chase entirely (no bar to drag from). */
  fingerSource?: FingerSource | null;
  onHaptic?: (kind: 'selection' | 'impact') => void;
  /** A bar drag released over another slot, `barScrub: 'exclusive'` only:
   *  the host selects that tab (the bar's own scrub is cancelled for the
   *  drag, so nothing else will). Omitted: the drag is a chase only and he
   *  walks back to his seat. Never called in `'native'` mode, where the
   *  bar's scrub selects on release itself. */
  onDragRelease?: (slotIndex: number) => void;
  /** How a drag along the native bar shares the touch. `'native'` (default):
   *  the bar's own scrub runs, the iOS 26 pill follows the finger and the
   *  bar selects on release, the companion chases alongside. `'exclusive'`:
   *  the scrub is cancelled once the drag recognises, the bar holds still,
   *  and the host selects via onDragRelease. Native recognizer only; a
   *  custom-bar FingerSource is whatever gesture the host built. */
  barScrub?: BarScrub;
}

type RunChaseRoute =
  | { kind: 'resumed'; route: ResumedRoute }
  | { kind: 'around'; path: AroundPath };

/** A route interrupted mid curve/underside by a tab change: staged by the
 *  blurring perch, taken (and cleared) by whichever real tab perch focuses
 *  next. Module level, not an instance ref, because a per-screen host mounts
 *  one perch per tab, so the instance that stages the interrupt is never the
 *  one that resumes it; a single mount is simply its own next focus.
 *  transientSlot perches neither stage nor take, matching the handoff store. */
interface InterruptedRoute {
  path: AroundPath;
  s: number;
}
let stagedInterruptedRoute: InterruptedRoute | null = null;
function stageInterruptedRoute(route: InterruptedRoute | null): void {
  stagedInterruptedRoute = route;
}
function takeInterruptedRoute(): InterruptedRoute | null {
  const route = stagedInterruptedRoute;
  stagedInterruptedRoute = null;
  return route;
}

/** Clears the release grace timer, if one is armed. Kept as a plain
 *  function (not a hook) so its own `if` doesn't count against the caller's
 *  complexity budget - called from several separate sites. */
function clearReleaseTimer(ref: { current: ReturnType<typeof setTimeout> | null }): void {
  if (ref.current) {
    clearTimeout(ref.current);
    ref.current = null;
  }
}

/** Pure: picks the run-chase's route, if any, so the focus effect's own
 * branching stays shallow. A tab-change interrupt of the curve/underside
 * resumes first; only lacking that does a fresh end-to-end tap route around. */
function resolveRunChaseRoute(args: {
  interrupted: { path: AroundPath; s: number } | null;
  pillNow: PillFrame | null;
  runSeatY: number;
  fromX: number;
  targetX: number;
  fromSlot: number;
  toSlot: number;
  slotCount: number;
  aroundRoute: boolean;
  flightLift: number;
  reduceMotionOn: boolean;
  spriteScale: number;
  footPad: number;
  headPad: number;
  seatOffset: number;
  windowWidth: number;
}): RunChaseRoute | null {
  if (args.interrupted && args.pillNow && args.runSeatY === 0 && !args.reduceMotionOn) {
    const route = resumeAroundRoute(args.interrupted.path, args.interrupted.s, args.targetX);
    if (route) {
      return { kind: 'resumed', route };
    }
  }
  const canRouteAround =
    args.pillNow !== null &&
    args.runSeatY === 0 &&
    shouldRouteAround({
      fromSlot: args.fromSlot,
      toSlot: args.toSlot,
      slotCount: args.slotCount,
      aroundRoute: args.aroundRoute,
      flightLift: args.flightLift,
      pill: args.pillNow,
      reduceMotion: args.reduceMotionOn,
    });
  if (!canRouteAround || !args.pillNow) {
    return null;
  }
  const path = planAroundPath({
    fromX: args.fromX,
    targetX: args.targetX,
    pill: args.pillNow,
    windowWidth: args.windowWidth,
    spriteScale: args.spriteScale,
    footPad: args.footPad,
    headPad: args.headPad,
    seatOffset: args.seatOffset,
  });
  return { kind: 'around', path };
}

export function CompanionPerch({
  anchor,
  onAction,
  actionLabel,
  bottomExtra = 0,
  transientSlot = false,
  focused = true,
  fingerSource: fingerSourceProp,
  onHaptic,
  onDragRelease,
  barScrub = 'native',
}: CompanionPerchProps) {
  const insets = useSafeAreaInsets();
  const { width: screenWidth, height: windowHeight } = useWindowDimensions();
  const reduceMotion = useReducedMotion();
  const id = useCompanionId();
  const profile = resolveProfile(id);
  // sanitized once, shared by the tab-tap run leg, the release approach, and
  // the drag's far approach - an unvalidated profile.runSpeed (0, negative,
  // NaN) never freezes or reverses any of them
  const runSpeed = useMemo(() => sanitizeRunSpeed(profile.runSpeed), [profile.runSpeed]);
  // profile.footPad is measured on the cell at reference size; pose layers
  // scale about the cell center, so the seat pads by the scaled figure
  const cellFootPad = profile.footPad ?? SPRITE_FOOT_PAD;
  const footPad = seatedFootPad(cellFootPad, profile.scale);
  const perchBottomOffset = (profile.seatLift ?? BAR_TOP_ABOVE_INSET) - footPad;
  const { onError } = useCompanionConfig();
  const fingerSource = useMemo(
    () => (fingerSourceProp === undefined ? nativeTabBarFingerSource() : fingerSourceProp),
    [fingerSourceProp]
  );
  // The mode lives on the native recognizer, so it is pushed whenever the
  // native source is in use; a host-built FingerSource owns its own gesture.
  useEffect(() => {
    if (fingerSourceProp === undefined) {
      setGlassPanScrub(barScrub);
    }
  }, [barScrub, fingerSourceProp]);

  // a short list (fewer than slots) is ignored in favour of the host's
  // own centers or the even-split fallback
  const measureCenters = useCallback((): readonly number[] | undefined => {
    if (anchor.slotCenters) {
      return anchor.slotCenters;
    }
    const centers = nativeTabBarLayout()?.centers;
    return centers && centers.length >= anchor.slotCount ? centers : undefined;
  }, [anchor.slotCenters, anchor.slotCount]);
  const measureBarTop = useCallback((): number | undefined => {
    if (anchor.barTop !== undefined) {
      return anchor.barTop;
    }
    return nativeTabBarLayout()?.top ?? undefined;
  }, [anchor.barTop]);
  const measurePill = useCallback((): PillFrame | null => {
    if (anchor.pill !== undefined) {
      return anchor.pill;
    }
    return nativeTabBarLayout()?.pill ?? null;
  }, [anchor.pill]);
  // re-measured every focus (bar can resize); state, not a ref, since it feeds render
  const [barTop, setBarTop] = useState<number | undefined>(measureBarTop);
  // focus effect below reads a fresh local, not this (state updates aren't synchronous)
  const [, setPill] = useState<PillFrame | null>(measurePill);
  const lastPillRef = useRef<PillFrame | null>(null);
  // mount seed only (useSharedValue reads it once); later focuses refresh the ref
  const initialCenters = useMemo(() => measureCenters(), [measureCenters]);
  const slotCentersRef = useRef<readonly number[] | undefined>(initialCenters);
  const x = useSharedValue(
    tabCenterX(readPerchHandoff().lastTab, screenWidth, anchor.slotCount, initialCenters)
  );
  const hop = useSharedValue(0);
  // far-approach frame callback: steps x toward farTargetX at farApproachSpeed
  // pt/s while farApproachActive is true, entirely on the UI thread - a fresh
  // 'moved' sample only ever writes farTargetX, never restarts a clock (see
  // the finger-source effect below and useFrameCallback further down)
  const farTargetX = useSharedValue(0);
  // mirror of farApproachRef below, written by JS for the worklet to read -
  // JS itself never reads this back (writing then reading in the same tick
  // returns the stale pre-write value; farApproachRef is the JS source of truth)
  const farApproachActive = useSharedValue(false);
  // the motion generation the running far approach belongs to, read only by
  // the frame callback so its one runOnJS report is generation-gated like
  // every other completion; farApproachGenerationRef below is JS's own copy
  const farApproachGeneration = useSharedValue(0);
  const farApproachSpeed = useSharedValue(runSpeed);
  // JS-thread source of truth for "an approach owns x" - never the shared
  // value above, which a same-tick JS read would see stale
  const farApproachRef = useRef(false);
  const farApproachGenerationRef = useRef(0);
  // latest arrival handler, refreshed every render below (after arrive/rest
  // exist) - same indirection as goHomeRef further down, so the frame
  // callback's declaration order here doesn't have to wait on theirs
  const farApproachArrivalRef = useRef<(generation: number) => void>(() => {
    // replaced by the layout effect below before the frame callback can report
  });
  // stable bridge from the worklet's runOnJS into whatever the ref currently holds
  const reportFarApproachArrival = useCallback((generation: number) => {
    farApproachArrivalRef.current(generation);
  }, []);
  const farApproachTick = useCallback(
    (frameInfo: FrameInfo) => {
      'worklet';
      if (!farApproachActive.get()) {
        return;
      }
      // first frame after (re)activation reports null - treat as 0, not a huge step
      const dtMs = frameInfo.timeSincePreviousFrame ?? 0;
      const result = stepToward(x.get(), farTargetX.get(), farApproachSpeed.get(), dtMs);
      x.set(result.x);
      if (result.arrived) {
        farApproachActive.set(false);
        runOnJS(reportFarApproachArrival)(farApproachGeneration.get());
      }
    },
    [
      x,
      farTargetX,
      farApproachActive,
      farApproachSpeed,
      farApproachGeneration,
      reportFarApproachArrival,
    ]
  );
  // OFF by default: an idle screen must not wake the UI thread every frame.
  // Turned on only while an approach is running (beginFarApproachIfNeeded)
  // and off at every site that ends one (stopFarApproach).
  const farApproachFrameCallback = useFrameCallback(farApproachTick, false);
  // Clears the JS/shared approach state and stops the frame callback - called
  // from every site that ends an approach, whether by arrival or by interrupt.
  const stopFarApproach = useCallback(() => {
    farApproachRef.current = false;
    farApproachActive.set(false);
    farApproachFrameCallback.setActive(false);
  }, [farApproachActive, farApproachFrameCallback]);
  // vertical offset from this seat, in pt DOWNWARD (0 = seated). Seeded from
  // the same planner the focus effect uses, not useSharedValue(0) - otherwise
  // the mount frame flashes at this instance's own seat before focus snaps it.
  const seatY = useSharedValue(
    planMountSeatY(readPerchHandoff(), {
      tab: anchor.slotIndex,
      slotCenters: initialCenters,
      screenWidth,
      bottomExtra,
      transientSlot,
      reduceMotion: reduceMotion === true,
      slotCount: anchor.slotCount,
    })
  );
  // Tab screens stay mounted, so a revisited screen flashes its own stale x
  // for a few frames before the focus effect stages the handoff - hidden at
  // blur, revealed only once staged.
  const visible = useSharedValue(1);
  // pt UPWARD (negative) lift while pose is 'run', for profile.flightLift > 0.
  // Animated on whichever spring drove the motion that triggered it
  // (motionSpringRef), so lift-off/landing stay in sync with x/hop/seatY.
  const flightLift = useSharedValue(0);
  // deg, rotation while running the around route; 0 on the pill
  const routeRotation = useSharedValue(0);
  // pt travelled along the current around route; drives x/seatY/routeRotation
  // together via the reaction below, one clock for the whole path
  const routeProgress = useSharedValue(0);
  // 'around': a fresh end-to-end route, driven by aroundPose. 'resumed': a
  // tab-change interrupt mid-route, driven by resumedPose from wherever the
  // companion actually was - see the focus effect body.
  const routePath = useSharedValue<
    { kind: 'around'; path: AroundPath } | { kind: 'resumed'; route: ResumedRoute } | null
  >(null);
  // the one place x/seatY/routeRotation get their around-route values: keeps
  // the three in lockstep, since they all come from the same pose call
  useAnimatedReaction(
    () => routeProgress.get(),
    (s) => {
      const active = routePath.get();
      if (!active) {
        return;
      }
      const pose =
        active.kind === 'around' ? aroundPose(active.path, s) : resumedPose(active.route, s);
      x.set(pose.x);
      seatY.set(pose.seatY);
      routeRotation.set(pose.rotation);
    }
  );
  // spring of the motion path currently driving x: commitSpring for a
  // committed tab chase, trackSpring for a live glass drag. Landing reads
  // whatever was last set here, so the fall matches the rise.
  const motionSpringRef = useRef(profile.trackSpring);
  const [pose, setPose] = useState<PupPose>('sit');
  // relays the busy claim edge (companion-state.ts) as a prop only;
  // presentation stays in CompanionSprite
  const [busy, setBusy] = useState(isCompanionBusy);
  const busyRef = useRef(busy);
  // idle sheet is the busy presentation: never interrupts a run or a drag
  useEffect(
    () =>
      subscribeCompanionBusy((next) => {
        busyRef.current = next;
        setBusy(next);
        if (dragEngagedRef.current || chasingRef.current) {
          return;
        }
        setPose((current) => {
          if (next && current === 'sit') {
            return 'idle';
          }
          if (!next && current === 'idle') {
            return 'sit';
          }
          return current;
        });
      }),
    []
  );
  const [facing, setFacing] = useState<1 | -1>(1);
  const facingRef = useRef<1 | -1>(1);
  const prevDragTargetRef = useRef<number | null>(null);
  // a TAP also fires the glass-pan recognizer (began+ended at the target
  // slot); treating it as a drag wrote lastX = destination and skipped the
  // arriving chase (a known regression) - a drag needs DRAG_ENGAGE_PT travel.
  const dragStartXRef = useRef<number | null>(null);
  const dragEngagedRef = useRef(false);
  // which hysteresis edge chaseStep uses (see CHASE_SLACK)
  const chasingRef = useRef(false);
  // the pending-release / arrival bookkeeping - reduceRelease (perch-handoff.ts)
  // is the only place these decisions are made; this ref just holds its state
  const releaseStateRef = useRef<ReleaseState>(initialReleaseState());
  // the grace timer awaiting the host's selection of another slot - cleared by
  // engage, focus-cleanup, unmount, or the timer itself firing
  const releaseTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  // latest go-home closure, read by the grace timer above - written every
  // render (no deps) so a stale render's props/state never leak into a timer
  // armed long before it fires
  const goHomeRef = useRef<() => void>(() => {
    // replaced by the layout effect below before any timer can read it
  });

  const face = useCallback((direction: 1 | -1) => {
    facingRef.current = direction;
    setFacing(direction);
  }, []);
  // guards late runOnJS completions from touching state post-unmount
  const mountedRef = useRef(true);
  useEffect(
    () => () => {
      mountedRef.current = false;
      stopFarApproach();
      const { state, effect } = reduceRelease(releaseStateRef.current, { type: 'unmount' });
      releaseStateRef.current = state;
      if (effect === 'clear-timer') {
        clearReleaseTimer(releaseTimerRef);
      }
    },
    [stopFarApproach]
  );
  // generation-gates late spring `finished` (up to ~5s) - mountedRef alone
  // would sit the companion mid-air on a newer chase.
  const motionGenerationRef = useRef(0);
  const bumpMotion = useCallback(() => {
    motionGenerationRef.current += 1;
    return motionGenerationRef.current;
  }, []);
  // stops a mid-flight around route dead: drops the shared path so the
  // reaction stops writing x/seatY/routeRotation, and kills the progress
  // clock driving it
  const cancelRoute = useCallback(() => {
    routePath.set(null);
    cancelAnimation(routeProgress);
  }, [routePath, routeProgress]);
  const snapVerticalToSeat = useCallback(
    (seatYStart: number) => {
      cancelAnimation(hop);
      cancelAnimation(flightLift);
      cancelAnimation(seatY);
      cancelAnimation(routeRotation);
      cancelRoute();
      hop.set(0);
      flightLift.set(0);
      seatY.set(seatYStart);
      routeRotation.set(0);
    },
    [hop, flightLift, seatY, routeRotation, cancelRoute]
  );
  // Rest pose: the sit sheet's last frame, or the idle loop while a busy
  // claim is held. idle[0] is a different drawing from sit's last frame on
  // panda/cat, so resting on idle mid-drag swapped in a second seated companion.
  const rest = useCallback(() => {
    setPose(busyRef.current ? 'idle' : 'sit');
  }, []);
  const arrive = useCallback(
    (generation: number) => {
      if (
        !shouldApplyArrive({
          callbackGeneration: generation,
          currentGeneration: motionGenerationRef.current,
          mounted: mountedRef.current,
        })
      ) {
        return;
      }
      rest();
    },
    [rest]
  );
  // cross-dissolving to idle here would swap drawings when sit/idle came from different clips
  const settle = useCallback(() => {
    // intentionally no pose change
  }, []);

  // The worklet's one arrival report: acts only when an approach is still
  // ours (farApproachRef) and belongs to this motion (generation match); a
  // report failing either test is ignored, so a still finger after a far
  // grab ends in the rest pose, never running in place.
  useLayoutEffect(() => {
    farApproachArrivalRef.current = (generation: number) => {
      if (!farApproachRef.current || generation !== motionGenerationRef.current) {
        return;
      }
      stopFarApproach();
      arrive(generation);
    };
  });

  // Distance-aware approach to targetX, used by every release/await/timeout
  // path: a spring under one glass width, a constant-speed run otherwise.
  // No reaction delay, no hop - he is already moving, not starting cold.
  const approach = useCallback(
    (targetX: number, generation: number) => {
      const liveX = x.get();
      const direction = travelFacing(targetX, liveX, facingRef.current);
      if (direction !== facingRef.current) {
        face(direction);
      }
      const plan = planApproach(targetX - liveX, runSpeed);
      if (plan.kind === 'spring') {
        x.set(
          withSpring(targetX, profile.catchSpring, (finished) => {
            if (finished) {
              runOnJS(arrive)(generation);
            }
          })
        );
        return;
      }
      setPose('run');
      x.set(
        withSequence(
          withTiming(targetX, { duration: plan.durationMs, easing: Easing.linear }),
          withSpring(targetX, profile.catchSpring, (finished) => {
            if (finished) {
              runOnJS(arrive)(generation);
            }
          })
        )
      );
    },
    [x, face, profile, arrive, runSpeed]
  );

  // Plain (no around/resumed route) run-chase leg: a constant-speed run
  // timed by distance, then a catch spring. Split out of the focus effect
  // below to keep that function's own branching within the lint's
  // complexity budget. An arrived-by-drag catch is already moving - no
  // reaction delay, no hop.
  const runPlainChase = useCallback(
    (
      fromX: number,
      targetX: number,
      runSeatY: number,
      generation: number,
      arrivedByDrag: boolean
    ) => {
      face(targetX >= fromX ? 1 : -1);
      const distance = Math.abs(targetX - fromX);
      const runMs = traverseDurationMs(distance, runSpeed);
      motionSpringRef.current = profile.commitSpring;
      setPose('run');
      // constant-speed run leg, not distance-keyed spring physics, so a
      // full-width tap visibly takes longer than a one-slot hop
      const runLeg = withSequence(
        withTiming(targetX, { duration: runMs, easing: Easing.linear }),
        withSpring(targetX, profile.catchSpring, (finished) => {
          if (finished) {
            runOnJS(arrive)(generation);
          }
        })
      );
      x.set(arrivedByDrag ? runLeg : withDelay(CHASE_REACTION_MS, runLeg));
      if (!arrivedByDrag) {
        hop.set(
          withDelay(
            CHASE_REACTION_MS,
            withSequence(
              withTiming(profile.hopHeight, { duration: HOP_STEP_MS }),
              withTiming(0, { duration: HOP_STEP_MS })
            )
          )
        );
      }
      // Rise onto the raised seat with the catch, not the fixed commit
      // spring, which would levitate him mid-run.
      if (runSeatY === 0) {
        seatY.set(0);
        return;
      }
      const seatLeg = withSequence(
        withTiming(runSeatY, { duration: runMs, easing: Easing.linear }),
        withSpring(0, profile.catchSpring)
      );
      seatY.set(arrivedByDrag ? seatLeg : withDelay(CHASE_REACTION_MS, seatLeg));
    },
    [face, profile, x, hop, seatY, arrive, runSpeed]
  );

  // Snap-to-seat catch: an instant teleport normally, but an arrived-by-drag
  // catch already has real distance left to close (x.set(plan.fromX) above
  // baked fromX to targetX) - spring it instead.
  const catchAtSeat = useCallback(
    (
      targetX: number,
      liveXAtFocusStart: number,
      generation: number,
      arrivedByDrag: boolean,
      reduceMotionOn: boolean
    ) => {
      if (!arrivedByDrag || reduceMotionOn) {
        x.set(targetX);
        seatY.set(reduceMotionOn ? 0 : withSpring(0, profile.catchSpring));
        setPose('sit');
        return;
      }
      // x.set(plan.fromX) in the focus effect already jumped to targetX
      // (snap-to-seat bakes fromX===targetX) - start the spring from the
      // real pre-focus position instead, so it has a real gap to close
      const remaining = Math.abs(targetX - liveXAtFocusStart);
      // travelFacing (not a raw sign test) so a couple pt of overshoot on
      // arrival doesn't turn him round to face it
      const direction = travelFacing(targetX, liveXAtFocusStart, facingRef.current);
      if (direction !== facingRef.current) {
        face(direction);
      }
      setPose(remaining > FACING_DEADBAND ? 'run' : 'sit');
      x.set(liveXAtFocusStart);
      x.set(
        withSpring(targetX, profile.catchSpring, (finished) => {
          if (finished) {
            runOnJS(arrive)(generation);
          }
        })
      );
      seatY.set(withSpring(0, profile.catchSpring));
    },
    [face, profile, x, seatY, arrive]
  );

  // A tab-change interrupt mid-underside/curve resumes the outline from
  // wherever the companion actually was. Split out of the focus effect
  // below to keep that function's own branching within the lint's
  // complexity budget.
  const runResumedRoute = useCallback(
    (resumed: ResumedRoute, targetX: number, generation: number) => {
      face(resumed.facing);
      motionSpringRef.current = profile.commitSpring;
      setPose('run');
      routePath.set({ kind: 'resumed', route: resumed });
      // snapVerticalToSeat already zeroed seatY/routeRotation and x is at
      // the live interrupt point - without this, the frame before the
      // reaction's first tick would show him seated (the exact
      // teleport-through-glass bug this route exists to fix). Setting the
      // pose directly, not just routeProgress.set(0), covers the case
      // routeProgress was already 0 (reaction dedupes no-op sets).
      const pose0 = resumedPose(resumed, 0);
      x.set(pose0.x);
      seatY.set(pose0.seatY);
      routeRotation.set(pose0.rotation);
      routeProgress.set(0);
      // no CHASE_REACTION_MS delay - he is already moving, not starting cold
      routeProgress.set(
        withTiming(
          resumed.totalLen,
          { duration: resumed.totalMs, easing: Easing.linear },
          (finished) => {
            if (!finished) {
              return;
            }
            routePath.set(null);
            routeRotation.set(0);
            x.set(
              withSpring(targetX, profile.catchSpring, (done) => {
                if (done) {
                  runOnJS(arrive)(generation);
                }
              })
            );
          }
        )
      );
    },
    [face, profile, x, seatY, routeRotation, routePath, routeProgress, arrive]
  );

  // A fresh end-to-end tap route around one end of the pill.
  const runAroundRoute = useCallback(
    (around: AroundPath, targetX: number, generation: number) => {
      face(around.facing);
      motionSpringRef.current = profile.commitSpring;
      setPose('run');
      // one clock for the whole route: the reaction above turns each
      // progress tick into x/seatY/routeRotation together via aroundPose
      routePath.set({ kind: 'around', path: around });
      routeProgress.set(0);
      routeProgress.set(
        withDelay(
          CHASE_REACTION_MS,
          withTiming(
            around.totalLen,
            { duration: around.totalMs, easing: Easing.linear },
            (finished) => {
              if (!finished) {
                return;
              }
              routePath.set(null);
              routeRotation.set(0); // 360 == 0; never spin back next time
              x.set(
                withSpring(targetX, profile.catchSpring, (done) => {
                  if (done) {
                    runOnJS(arrive)(generation);
                  }
                })
              );
            }
          )
        )
      );
    },
    [face, profile, x, routeRotation, routePath, routeProgress, arrive]
  );

  // updated inside the commit, ahead of any passive effect (including a grace
  // timer that can fire in the same tick) - a timer's bail-out check reads
  // this, not anchor.slotIndex, since its own closure is already stale
  const renderedSlotRef = useRef(anchor.slotIndex);
  useLayoutEffect(() => {
    renderedSlotRef.current = anchor.slotIndex;
  }, [anchor.slotIndex]);

  // oxlint-disable react-compiler -- ported from useFocusEffect (expo-router), which
  // react-compiler doesn't recognize as a focus/mount hook the way it does a plain
  // useEffect; the synchronous face()/setPose() calls below reproduce that hook's
  // exact focus-time behavior, not a derived-state anti-pattern
  useEffect(() => {
    // consumed before the focused guard, unlike interruptedRouteRef below -
    // a pending release becomes an arrival on the focus-cleanup that
    // consumed it, whatever slot this focus-body ends up landing on
    const { state: releaseAfterBody, effect: releaseBodyEffect } = reduceRelease(
      releaseStateRef.current,
      { type: 'focus-body', transientSlot }
    );
    releaseStateRef.current = releaseAfterBody;
    const arrivedByDrag = releaseBodyEffect === 'arrived';
    if (!focused) {
      return;
    }
    const reduceMotionOn = reduceMotion === true;
    // consumed at most once per focus - a plain run-chase clears it below too.
    // A transientSlot perch leaves it staged for the tab perch that refocuses
    // after the pushed screen pops.
    const interrupted = transientSlot ? null : takeInterruptedRoute();
    // a pushed stack screen takes the tab bar out of the window between the
    // JS commit and the native pop, so a focus measured then reports no bar;
    // hold the last seat rather than dropping to the inset fallback
    const measuredCentersNow = measureCenters();
    slotCentersRef.current = measuredCentersNow ?? slotCentersRef.current;
    const barTopNow = measureBarTop();
    if (barTopNow !== undefined) {
      setBarTop(barTopNow);
    }
    const pillNow = measurePill() ?? lastPillRef.current;
    lastPillRef.current = pillNow;
    setPill(pillNow);
    const fromSlot = readPerchHandoff().lastTab;
    const plan = planFocus(readPerchHandoff(), {
      tab: anchor.slotIndex,
      slotCenters: slotCentersRef.current,
      screenWidth,
      bottomExtra,
      transientSlot,
      reduceMotion: reduceMotionOn,
      slotCount: anchor.slotCount,
      // a route interrupt must get a real run-chase from lastX, never a
      // snap-to-seat or same-tab-snap through the glass
      holdRun: interrupted !== null,
    });
    const generation = bumpMotion();
    // a focus always re-plans x - the far approach must not keep stepping
    // it underneath whatever this focus is about to do
    stopFarApproach();
    cancelAnimation(x);
    // read before x.set(plan.fromX) below overwrites it - a snap-to-seat
    // plan bakes fromX to targetX, so this is the only place the real
    // pre-focus position (needed for an arrived-by-drag catch) survives
    const liveXAtFocusStart = x.get();
    cancelRoute();
    // holds runSeatY (bar level) while climbing to a raised seat - going
    // down already dropped it. Also snaps leftover hop/flightLift
    // so a stale ~5s spring can't leave the companion mid-air.
    snapVerticalToSeat(planStartSeatY(plan));
    x.set(plan.fromX);
    if (plan.kind === 'run-chase') {
      const routeChoice = resolveRunChaseRoute({
        interrupted,
        pillNow,
        runSeatY: plan.runSeatY,
        fromX: plan.fromX,
        targetX: plan.targetX,
        fromSlot: focusFromSlot(fromSlot, arrivedByDrag, anchor.slotIndex),
        toSlot: anchor.slotIndex,
        slotCount: anchor.slotCount,
        aroundRoute: profile.aroundRoute,
        flightLift: profile.flightLift,
        reduceMotionOn,
        spriteScale: profile.scale,
        footPad: cellFootPad,
        headPad: profile.headPad ?? 0,
        seatOffset: perchBottomOffset,
        windowWidth: screenWidth,
      });
      if (routeChoice?.kind === 'resumed') {
        runResumedRoute(routeChoice.route, plan.targetX, generation);
      } else if (routeChoice?.kind === 'around') {
        runAroundRoute(routeChoice.path, plan.targetX, generation);
      } else {
        runPlainChase(plan.fromX, plan.targetX, plan.runSeatY, generation, arrivedByDrag);
      }
    } else if (plan.kind === 'reduced-chase') {
      x.set(withTiming(plan.targetX, { duration: REDUCED_DURATION_MS }));
      seatY.set(withTiming(0, { duration: REDUCED_DURATION_MS }));
      setPose('sit');
    } else if (plan.kind === 'snap-to-seat') {
      catchAtSeat(plan.targetX, liveXAtFocusStart, generation, arrivedByDrag, reduceMotionOn);
    } else {
      // transient-snap / same-tab-snap: instant seat, no chase
      x.set(plan.targetX);
      seatY.set(0);
      setPose('sit');
    }
    if (plan.commitsHandoff) {
      writePerchHandoff(plan.next);
    }
    visible.set(1);
    // At launch the first focus can run before UITabBar has laid out:
    // nativeTabBarLayout() reports nothing, so this focus seated on the
    // even-split fallback. Retry for a few frames; a bar with a different
    // slot count than the fallback assumed lands noticeably off-center and
    // nothing else re-measures until the next focus.
    let stopRemeasure: (() => void) | undefined;
    if (!transientSlot && anchor.slotCenters === undefined && measuredCentersNow === undefined) {
      const kindAtFocus = plan.kind;
      stopRemeasure = retryMeasure(measureCenters, (centers) => {
        slotCentersRef.current = centers;
        const barTopFound = measureBarTop();
        if (barTopFound !== undefined) {
          setBarTop(barTopFound);
        }
        const pillFound = measurePill();
        lastPillRef.current = pillFound ?? lastPillRef.current;
        setPill(lastPillRef.current);
        // only correct the visible seat while nothing is moving him - a run,
        // drag chase, or around route owns x/seatY and must not be yanked
        const seated =
          motionGenerationRef.current === generation &&
          kindAtFocus !== 'run-chase' &&
          !chasingRef.current &&
          !dragEngagedRef.current &&
          routePath.get() === null;
        if (!seated) {
          return;
        }
        const seat = tabCenterX(anchor.slotIndex, screenWidth, anchor.slotCount, centers);
        // dragEngagedRef above already rules this out whenever a far
        // approach could be running; stop it again here defensively
        stopFarApproach();
        x.set(seat);
        if (plan.commitsHandoff) {
          // same shape planFocus writes for a settled seat: lastX null means
          // "recompute from tabCenterX next time", so the corrected centers
          // (not this stale fallback) seed the next run's starting point
          writePerchHandoff({ lastTab: anchor.slotIndex, lastX: null, lastSeat: bottomExtra });
        }
      });
    }
    return () => {
      // a pending release becomes an arrival here, whatever focus consumes
      // it next - a re-run that keeps the same slot also ends the wait,
      // since the focus body above always re-plans x
      const { state, effect } = reduceRelease(releaseStateRef.current, { type: 'focus-cleanup' });
      releaseStateRef.current = state;
      if (effect === 'clear-timer') {
        clearReleaseTimer(releaseTimerRef);
      }
      stopRemeasure?.();
      // a tap can land mid-traverse: hand off from where the companion
      // actually is, not the destination it never reached - else the next
      // instance's `from` falls back to tabCenterX(lastTab), which it was
      // still chasing toward, and it teleports. Read live x/seat BEFORE
      // snapVerticalToSeat(0) zeros altitude, or a bounce-back floats wrong.
      const liveX = x.get();
      // stage a resume point for the next focus's run-chase, before
      // cancelRoute() below drops routePath and its progress clock
      const activeRoute = routePath.get();
      const progressAtBlur = routeProgress.get();
      let staged: InterruptedRoute | null = null;
      if (activeRoute?.kind === 'around') {
        const onCurve =
          progressAtBlur > activeRoute.path.legs[0] && progressAtBlur < activeRoute.path.legs[3];
        staged = onCurve ? { path: activeRoute.path, s: progressAtBlur } : null;
      } else if (activeRoute?.kind === 'resumed') {
        const mappedS = resumedBaseS(activeRoute.route, progressAtBlur);
        staged = mappedS === null ? null : { path: activeRoute.route.base, s: mappedS };
      }
      // a transientSlot perch never routes, and its blur (the pushed screen
      // popping) must not wipe what the tab perch staged before it was covered
      if (!transientSlot) {
        stageInterruptedRoute(staged);
      }
      // the route owns the vertical mid-flight (seatY is the underside hang,
      // not a raised composer seat) - hand off at bar level so the next
      // planFocus computes runSeatY===0 and resolveRunChaseRoute can resume;
      // every other blur freezes the live altitude as before
      const liveSeat =
        staged === null ? liveLastSeat(bottomExtra, seatY.get()) : liveLastSeat(bottomExtra, 0);
      stopFarApproach();
      cancelAnimation(x);
      cancelRoute();
      bumpMotion();
      snapVerticalToSeat(0);
      writePerchHandoff(
        applyFocusBlur(readPerchHandoff(), {
          currentX: liveX,
          currentSeat: liveSeat,
          transientSlot,
        })
      );
      visible.set(0);
      setPose('sit');
    };
  }, [
    focused,
    measureCenters,
    measureBarTop,
    measurePill,
    anchor.slotIndex,
    anchor.slotCount,
    anchor.slotCenters,
    screenWidth,
    windowHeight,
    reduceMotion,
    x,
    hop,
    seatY,
    routeRotation,
    routePath,
    routeProgress,
    cancelRoute,
    visible,
    bottomExtra,
    arrive,
    bumpMotion,
    snapVerticalToSeat,
    face,
    profile,
    footPad,
    cellFootPad,
    perchBottomOffset,
    transientSlot,
    stopFarApproach,
    runPlainChase,
    catchAtSeat,
    runResumedRoute,
    runAroundRoute,
  ]);
  // oxlint-enable react-compiler

  // Latest go-home closure for the grace timer below: a host that
  // passes an inline onDragRelease changes it every render, so the timer
  // must not close over this render's props/state - it reads this ref at
  // fire time instead, which always holds the current slot/width/centers.
  useLayoutEffect(() => {
    goHomeRef.current = () => {
      const home = tabCenterX(
        anchor.slotIndex,
        screenWidth,
        anchor.slotCount,
        slotCentersRef.current
      );
      const generation = bumpMotion();
      approach(home, generation);
      seatY.set(withSpring(0, profile.catchSpring));
    };
  });

  // Settles a drag release: home immediately, or approach the awaited slot
  // and arm the grace timer that falls back home if the selection never
  // lands in time. Split out of the finger-source callback below to keep
  // that function's own branching within the lint's complexity budget.
  const settleAfterRelease = useCallback(
    (plan: DragReleasePlan, home: number) => {
      const fromSlot = anchor.slotIndex;
      const generation = bumpMotion();
      const { state, effect } = reduceRelease(releaseStateRef.current, {
        type: 'release',
        plan,
        fromSlot,
        generation,
      });
      releaseStateRef.current = state;
      if (effect === 'go-home') {
        approach(home, generation);
        seatY.set(withSpring(0, profile.catchSpring));
        return;
      }
      if (effect !== 'await' || !state.pending) {
        return;
      }
      const { pending } = state;
      approach(
        tabCenterX(pending.slot, screenWidth, anchor.slotCount, slotCentersRef.current),
        generation
      );
      // leave seatY at bar level - the next focus plans the rise onto its own raised seat
      clearReleaseTimer(releaseTimerRef);
      releaseTimerRef.current = setTimeout(() => {
        const result = reduceRelease(releaseStateRef.current, {
          type: 'timer',
          mounted: mountedRef.current,
          generation: motionGenerationRef.current,
          renderedSlot: renderedSlotRef.current,
        });
        releaseStateRef.current = result.state;
        releaseTimerRef.current = null;
        if (result.effect === 'go-home') {
          goHomeRef.current();
        }
      }, RELEASE_GRACE_MS);
    },
    [bumpMotion, approach, seatY, profile, anchor.slotIndex, anchor.slotCount, screenWidth]
  );

  // oxlint-disable react-compiler -- same rationale as the focus effect above;
  // this ref-mutating helper and the effect below it are one unit
  // Handles a touch-up (ended or cancelled): writes the release handoff,
  // fires onDragRelease (ended + exclusive only, D2), and settles. Split out
  // of the finger-source callback below to keep that function's own
  // branching within the lint's complexity budget.
  const handleDragEnd = useCallback(
    (phase: 'ended' | 'cancelled') => {
      if (!dragEngagedRef.current) {
        // a tap, not a drag: leave handoff state alone, let the native
        // selection drive the commit chase
        dragStartXRef.current = null;
        prevDragTargetRef.current = null;
        return;
      }
      dragEngagedRef.current = false;
      chasingRef.current = false;
      // before the release approach or the trip home takes x over
      stopFarApproach();
      dragStartXRef.current = null;
      const releaseX =
        prevDragTargetRef.current ??
        tabCenterX(anchor.slotIndex, screenWidth, anchor.slotCount, slotCentersRef.current);
      prevDragTargetRef.current = null;
      // ended and the native tab selection are independent callback chains
      // for the same touch-up - if another tab's focus already consumed
      // the handoff, writing here would stomp it and skew the next chase
      writePerchHandoff(
        applyDragRelease(readPerchHandoff(), {
          tab: anchor.slotIndex,
          releaseX,
          bottomExtra,
        })
      );
      // this write only matters until this tab's own blur overwrites
      // lastX (applyFocusBlur always wins) - planDragRelease below, not
      // this write, is what actually decides where he goes next
      const releaseSlot = nearestSlot(
        releaseX + PERCH_SIZE / 2,
        screenWidth,
        anchor.slotCount,
        slotCentersRef.current
      );
      // native mode: the bar's own scrub selects on this same touch-up.
      // A cancelled drag must not navigate - only 'ended' selects.
      if (phase === 'ended' && barScrub === 'exclusive' && releaseSlot !== anchor.slotIndex) {
        onDragRelease?.(releaseSlot);
      }
      const home = tabCenterX(
        anchor.slotIndex,
        screenWidth,
        anchor.slotCount,
        slotCentersRef.current
      );
      // Whether the released-over slot will actually be selected is a
      // property of the bar, not of who supplies the touch stream: a
      // host wrapping the native recognizer in its own FingerSource still
      // rides the native pill on a real drag. A pill the host passed for
      // its own custom bar (anchor.pill) does not count.
      const nativePill = anchor.pill === undefined && (nativeTabBarLayout()?.pill ?? null) !== null;
      const plan = planDragRelease({
        phase,
        releaseSlot,
        currentSlot: anchor.slotIndex,
        selectsOnRelease: selectsOnRelease({
          barScrub,
          hasOnDragRelease: onDragRelease !== undefined,
          nativePill,
        }),
      });
      settleAfterRelease(plan, home);
    },
    [
      anchor.slotIndex,
      anchor.slotCount,
      anchor.pill,
      screenWidth,
      bottomExtra,
      barScrub,
      onDragRelease,
      settleAfterRelease,
      stopFarApproach,
    ]
  );

  // Far is judged from where the finger came down, not from this sample: a
  // fast flick that starts on him keeps the spring follower. The sample that
  // starts an approach does nothing else, and bumps the generation once.
  const beginFarApproachIfNeeded = useCallback(
    (startX: number, glassAtEngage: number): boolean => {
      if (!isFarGrab(glassTargetX(startX, screenWidth) - x.get())) {
        return false;
      }
      // the engage sample itself goes through the same leash test as every
      // later sample - a landing spot behind him (within the not-chasing
      // edge) must fall through to the ordinary leash, not start a run
      const plan = planFarSample({ glassX: glassAtEngage, currentX: x.get(), screenWidth });
      if (plan.kind === 'end') {
        return false;
      }
      // starting the far approach: it, not any leftover spring, owns x
      cancelAnimation(x);
      const generation = bumpMotion();
      farApproachGenerationRef.current = generation;
      farApproachGeneration.set(generation);
      farApproachSpeed.set(runSpeed);
      if (plan.facing !== facingRef.current) {
        face(plan.facing);
      }
      farTargetX.set(plan.target);
      motionSpringRef.current = profile.trackSpring;
      setPose('run');
      farApproachRef.current = true;
      farApproachActive.set(true);
      farApproachFrameCallback.setActive(true);
      return true;
    },
    [
      screenWidth,
      x,
      bumpMotion,
      farApproachGeneration,
      farApproachSpeed,
      runSpeed,
      face,
      farTargetX,
      profile,
      farApproachActive,
      farApproachFrameCallback,
    ]
  );

  // During an approach JS only writes the target; the frame callback moves x.
  // JS reads farApproachRef, never the shared flag: a shared value set from
  // JS is applied later, so reading it back in the same tick returns the old one.
  const trackFarApproachSample = useCallback(
    (glassTarget: number): boolean => {
      if (!farApproachRef.current) {
        return false;
      }
      const plan = planFarSample({
        glassX: glassTarget,
        currentX: x.get(),
        screenWidth,
      });
      if (plan.kind === 'end') {
        const generation = farApproachGenerationRef.current;
        stopFarApproach();
        arrive(generation);
        return true;
      }
      if (plan.facing !== facingRef.current) {
        face(plan.facing);
      }
      farTargetX.set(plan.target);
      return true;
    },
    [x, screenWidth, face, farTargetX, stopFarApproach, arrive]
  );

  useEffect(() => {
    if (!focused) {
      return;
    }
    if (transientSlot) {
      // no real glass bar under a pushed screen to drag, and this instance
      // must never touch lastX/lastSeat - skip rather than guard every branch
      return;
    }
    if (!fingerSource) {
      return;
    }
    const unsubscribe = fingerSource.subscribe((event) => {
      try {
        if (reduceMotion) {
          return;
        }

        if (event.phase === 'began' || event.phase === 'moved') {
          if (event.phase === 'began') {
            dragStartXRef.current = event.x;
            dragEngagedRef.current = false;
            chasingRef.current = false;
            stopFarApproach();
            // A touch on the bar may turn out to be a TAP: while a release
            // is pending, bumping the motion generation or clearing the
            // timer here would strand the companion over the wrong tab in
            // the run pose with no fallback if the touch never engages.
            const { state, effect } = reduceRelease(releaseStateRef.current, { type: 'began' });
            releaseStateRef.current = state;
            if (effect !== 'hold-generation') {
              // invalidate a late catch-sit from the commit chase
              bumpMotion();
            }
            // a bar drag mid-around-route must not leave him rotated or
            // stuck under the pill
            cancelAnimation(routeRotation);
            routeRotation.set(0);
            cancelRoute();
            if (seatY.get() > bottomExtra) {
              seatY.set(withSpring(bottomExtra, profile.trackSpring));
            }
            return;
          }
          const glassTarget = glassTargetX(event.x, screenWidth);
          let startedFarApproach = false;
          if (!dragEngagedRef.current) {
            const startX = dragStartXRef.current ?? event.x;
            if (Math.abs(event.x - startX) <= DRAG_ENGAGE_PT) {
              return;
            }
            dragEngagedRef.current = true;
            startedFarApproach = beginFarApproachIfNeeded(startX, glassTarget);
            // a real drag is engaging: any release it was waiting on no longer applies
            const { state, effect } = reduceRelease(releaseStateRef.current, { type: 'engage' });
            releaseStateRef.current = state;
            if (effect === 'clear-timer') {
              clearReleaseTimer(releaseTimerRef);
            }
          }
          prevDragTargetRef.current = glassTarget;
          if (bottomExtra > 0) {
            // the drag happens ON the glass: drop from a raised seat to
            // bar level for the duration of the drag
            seatY.set(withSpring(bottomExtra, profile.trackSpring));
          }
          // Preserve the glass position, not the trailing companion
          // position, for the cross-screen handoff on release.
          writePerchHandoff(applyDragTrack(readPerchHandoff(), glassTarget));

          if (startedFarApproach) {
            // the sample that started the approach does nothing else -
            // no leash, no extra bumpMotion/chasingRef, no spring
            return;
          }
          if (trackFarApproachSample(glassTarget)) {
            return;
          }

          // Leash follower: inside CHASE_TRAIL he stands his ground - chasing
          // the trailing point from a standstill floated him backward while
          // facing forward. He only ever runs toward the glass.
          const step = chaseStep(glassTarget, x.get(), facingRef.current, chasingRef.current);
          if (step.target === null) {
            chasingRef.current = false;
            // the far-approach branch above already returned when active;
            // this stand-down is always the leash's, never the far run's
            stopFarApproach();
            // soft-brake here: assigning x cancels the in-flight spring, else a
            // still-running commit-chase keeps sliding him under the idle sprite
            x.set(withSpring(x.get(), profile.trackSpring));
            rest();
            return;
          }
          chasingRef.current = true;
          if (step.facing !== facingRef.current) {
            face(step.facing);
          }
          motionSpringRef.current = profile.trackSpring;
          setPose('run');
          // an abrupt stop has no further moved event to stand him down, so
          // the last track spring's completion rests him at the finger
          const generation = bumpMotion();
          x.set(
            withSpring(
              chaseTargetX(glassTarget, step.facing, screenWidth),
              profile.trackSpring,
              (finished) => {
                if (finished) {
                  runOnJS(arrive)(generation);
                }
              }
            )
          );
        } else {
          handleDragEnd(event.phase);
        }
      } catch (error) {
        // JS-thread callback, not a worklet - report directly; recovery
        // still runs so a mid-drag throw can't leave state wedged.
        onError(error, 'perch.drag');
        dragEngagedRef.current = false;
        chasingRef.current = false;
        stopFarApproach();
        dragStartXRef.current = null;
        prevDragTargetRef.current = null;
        const { state, effect } = reduceRelease(releaseStateRef.current, { type: 'abort' });
        releaseStateRef.current = state;
        if (effect === 'clear-timer') {
          clearReleaseTimer(releaseTimerRef);
        }
        cancelAnimation(x);
        cancelRoute();
        if (mountedRef.current) {
          rest();
        }
      }
    });
    return () => {
      // cancel x's in-flight spring before tearing down the subscription,
      // but only when a live drag chase currently owns x - this effect
      // re-subscribes on every dependency change, including an inline
      // onDragRelease/onError that changes on every host render, and
      // cancelling x on every one of those would freeze him mid-bar in the
      // run pose during the release wait. The release approach, the arrival
      // catch and the fallback are generation-gated and belong to the
      // release path and the focus effect, not to this cleanup.
      if (dragEngagedRef.current || chasingRef.current) {
        cancelAnimation(x);
        cancelRoute();
      }
      unsubscribe?.();
      prevDragTargetRef.current = null;
      // blur can outrun the gesture's ended event
      dragEngagedRef.current = false;
      chasingRef.current = false;
      stopFarApproach();
      dragStartXRef.current = null;
      // this effect re-subscribes on every dependency change, including
      // onDragRelease - a host passing an inline callback changes it every
      // render, so this cleanup must not touch the pending release or its
      // timer, or it would strand the companion
    };
  }, [
    focused,
    reduceMotion,
    screenWidth,
    anchor.slotIndex,
    anchor.slotCount,
    fingerSource,
    fingerSourceProp,
    x,
    seatY,
    routeRotation,
    cancelRoute,
    bottomExtra,
    settleAfterRelease,
    handleDragEnd,
    arrive,
    rest,
    bumpMotion,
    face,
    profile,
    stopFarApproach,
    beginFarApproachIfNeeded,
    trackFarApproachSample,
    transientSlot,
    onError,
    onDragRelease,
    barScrub,
  ]);
  // oxlint-enable react-compiler

  // flight-capable companions only; a separate effect so it never touches
  // handoff state. Uses motionSpringRef (falls back to trackSpring) so the
  // lift never races the horizontal motion that caused it.
  useEffect(() => {
    const target = pose === 'run' ? -profile.flightLift : 0;
    const spring = motionSpringRef.current ?? profile.trackSpring;
    flightLift.set(reduceMotion ? target : withSpring(target, spring));
  }, [pose, profile, reduceMotion, flightLift]);

  const routePivotPt = routePivot(profile.scale, cellFootPad);
  const animatedStyle = useAnimatedStyle(() => ({
    opacity: visible.get(),
    transform: [
      { translateX: x.get() },
      { translateY: hop.get() + seatY.get() + flightLift.get() },
      // rotate about the drawn feet, not the box center, so the around route
      // keeps them on the pill's outline through every corner
      { translateY: routePivotPt },
      { rotate: `${routeRotation.get()}deg` },
      { translateY: -routePivotPt },
    ],
  }));

  return (
    <Animated.View
      pointerEvents="box-none"
      style={[
        styles.perch,
        {
          // measured bar top wins; otherwise the bottom inset IS the bar
          // (true inside a native tab screen)
          bottom:
            (barTop === undefined ? insets.bottom : windowHeight - barTop) +
            perchBottomOffset +
            bottomExtra,
          width: PERCH_SIZE,
          height: PERCH_SIZE,
        },
        animatedStyle,
      ]}
    >
      <CompanionSprite
        companionId={id}
        size={PERCH_SIZE}
        pose={pose}
        busy={busy}
        facing={facing}
        onSitDone={settle}
        onPress={onAction}
        pressLabel={actionLabel}
        onHaptic={onHaptic}
      />
    </Animated.View>
  );
}

const styles = StyleSheet.create({
  perch: { position: 'absolute', left: 0 },
});
