/**
 * Companion perch: a JS overlay riding the host's tab bar. Committed tab
 * changes chase after a short reaction delay; live drags trail the glass.
 * Sit is the rest pose. An opted-in profile can take the "around" route
 * (off one pill end, under it, up the other) instead of a straight chase.
 */
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { StyleSheet, useWindowDimensions } from 'react-native';
import Animated, {
  cancelAnimation,
  Easing,
  runOnJS,
  useAnimatedReaction,
  useAnimatedStyle,
  useReducedMotion,
  useSharedValue,
  withDelay,
  withSequence,
  withSpring,
  withTiming,
} from 'react-native-reanimated';
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
  liveLastSeat,
  planFocus,
  planMountSeatY,
  planStartSeatY,
  readPerchHandoff,
  writePerchHandoff,
} from './perch-handoff';
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
  // set by the focus-effect cleanup when a tab change interrupts a companion mid
  // curve/underside; consumed (and cleared) by the next effect run's body.
  // Only survives within this one mounted perch (the single-mount pattern) -
  // a per-screen mount hands off through perch-handoff and never resumes.
  const interruptedRouteRef = useRef<{ path: AroundPath; s: number } | null>(null);

  const face = useCallback((direction: 1 | -1) => {
    facingRef.current = direction;
    setFacing(direction);
  }, []);
  // guards late runOnJS completions from touching state post-unmount
  const mountedRef = useRef(true);
  useEffect(
    () => () => {
      mountedRef.current = false;
    },
    []
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

  // oxlint-disable react-compiler -- ported from useFocusEffect (expo-router), which
  // react-compiler doesn't recognize as a focus/mount hook the way it does a plain
  // useEffect; the synchronous face()/setPose() calls below reproduce that hook's
  // exact focus-time behavior, not a derived-state anti-pattern
  useEffect(() => {
    if (!focused) {
      return;
    }
    const reduceMotionOn = reduceMotion === true;
    // consumed at most once per focus - a plain run-chase clears it below too
    const interrupted = interruptedRouteRef.current;
    interruptedRouteRef.current = null;
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
    cancelAnimation(x);
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
        fromSlot,
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
        const resumed = routeChoice.route;
        face(resumed.facing);
        motionSpringRef.current = profile.commitSpring;
        setPose('run');
        routePath.set({ kind: 'resumed', route: resumed });
        // snapVerticalToSeat above already zeroed seatY/routeRotation and
        // x.set(plan.fromX) put x at the live interrupt point - without this,
        // the frame before the reaction's first tick would show him seated
        // (the exact teleport-through-glass bug this route exists to fix).
        // Setting the pose directly, not just routeProgress.set(0), covers
        // the case routeProgress was already 0 (reaction dedupes no-op sets).
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
                withSpring(plan.targetX, profile.catchSpring, (done) => {
                  if (done) {
                    runOnJS(arrive)(generation);
                  }
                })
              );
            }
          )
        );
      } else if (routeChoice?.kind === 'around') {
        const around = routeChoice.path;
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
                  withSpring(plan.targetX, profile.catchSpring, (done) => {
                    if (done) {
                      runOnJS(arrive)(generation);
                    }
                  })
                );
              }
            )
          )
        );
      } else {
        face(plan.targetX >= plan.fromX ? 1 : -1);
        const distance = Math.abs(plan.targetX - plan.fromX);
        const runMs = traverseDurationMs(distance, profile.runSpeed);
        motionSpringRef.current = profile.commitSpring;
        setPose('run');
        x.set(
          withDelay(
            CHASE_REACTION_MS,
            withSequence(
              // constant-speed run leg, not distance-keyed spring physics,
              // so a full-width tap visibly takes longer than a one-slot hop
              withTiming(plan.targetX, {
                duration: runMs,
                easing: Easing.linear,
              }),
              withSpring(plan.targetX, profile.catchSpring, (finished) => {
                if (finished) {
                  runOnJS(arrive)(generation);
                }
              })
            )
          )
        );
        hop.set(
          withDelay(
            CHASE_REACTION_MS,
            withSequence(
              withTiming(profile.hopHeight, { duration: HOP_STEP_MS }),
              withTiming(0, { duration: HOP_STEP_MS })
            )
          )
        );
        // Rise onto the raised seat with the catch, not the fixed commit
        // spring, which would levitate him mid-run.
        if (plan.runSeatY === 0) {
          seatY.set(0);
        } else {
          seatY.set(
            withDelay(
              CHASE_REACTION_MS,
              withSequence(
                withTiming(plan.runSeatY, {
                  duration: runMs,
                  easing: Easing.linear,
                }),
                withSpring(0, profile.catchSpring)
              )
            )
          );
        }
      }
    } else if (plan.kind === 'reduced-chase') {
      x.set(withTiming(plan.targetX, { duration: REDUCED_DURATION_MS }));
      seatY.set(withTiming(0, { duration: REDUCED_DURATION_MS }));
      setPose('sit');
    } else if (plan.kind === 'snap-to-seat') {
      x.set(plan.targetX);
      seatY.set(reduceMotionOn ? 0 : withSpring(0, profile.catchSpring));
      setPose('sit');
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
      if (activeRoute?.kind === 'around') {
        const onCurve =
          progressAtBlur > activeRoute.path.legs[0] && progressAtBlur < activeRoute.path.legs[3];
        interruptedRouteRef.current = onCurve
          ? { path: activeRoute.path, s: progressAtBlur }
          : null;
      } else if (activeRoute?.kind === 'resumed') {
        const mappedS = resumedBaseS(activeRoute.route, progressAtBlur);
        interruptedRouteRef.current =
          mappedS === null ? null : { path: activeRoute.route.base, s: mappedS };
      } else {
        interruptedRouteRef.current = null;
      }
      // the route owns the vertical mid-flight (seatY is the underside hang,
      // not a raised composer seat) - hand off at bar level so the next
      // planFocus computes runSeatY===0 and resolveRunChaseRoute can resume;
      // every other blur freezes the live altitude as before
      const liveSeat =
        interruptedRouteRef.current === null
          ? liveLastSeat(bottomExtra, seatY.get())
          : liveLastSeat(bottomExtra, 0);
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
  ]);
  // oxlint-enable react-compiler

  // oxlint-disable react-compiler -- same rationale as the focus effect above
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
            // invalidate a late catch-sit from the commit chase
            bumpMotion();
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
          if (!dragEngagedRef.current) {
            const startX = dragStartXRef.current ?? event.x;
            if (Math.abs(event.x - startX) <= DRAG_ENGAGE_PT) {
              return;
            }
            dragEngagedRef.current = true;
          }
          const glassTarget = glassTargetX(event.x, screenWidth);
          prevDragTargetRef.current = glassTarget;
          if (bottomExtra > 0) {
            // the drag happens ON the glass: drop from a raised seat to
            // bar level for the duration of the drag
            seatY.set(withSpring(bottomExtra, profile.trackSpring));
          }
          // Preserve the glass position, not the trailing companion
          // position, for the cross-screen handoff on release.
          writePerchHandoff(applyDragTrack(readPerchHandoff(), glassTarget));

          // Leash follower: inside CHASE_TRAIL he stands his ground - chasing
          // the trailing point from a standstill floated him backward while
          // facing forward. He only ever runs toward the glass.
          const step = chaseStep(glassTarget, x.get(), facingRef.current, chasingRef.current);
          if (step.target === null) {
            chasingRef.current = false;
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
          if (!dragEngagedRef.current) {
            // a tap, not a drag: leave handoff state alone, let the native
            // selection drive the commit chase
            dragStartXRef.current = null;
            prevDragTargetRef.current = null;
            return;
          }
          dragEngagedRef.current = false;
          chasingRef.current = false;
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
          // handoff first: the host's selection focuses the new slot, which
          // reads it for the commit chase from the release point
          const releaseSlot = nearestSlot(
            releaseX + PERCH_SIZE / 2,
            screenWidth,
            anchor.slotCount,
            slotCentersRef.current
          );
          // native mode: the bar's own scrub selects on this same touch-up
          if (barScrub === 'exclusive' && releaseSlot !== anchor.slotIndex) {
            onDragRelease?.(releaseSlot);
          }
          const home = tabCenterX(
            anchor.slotIndex,
            screenWidth,
            anchor.slotCount,
            slotCentersRef.current
          );
          const direction = travelFacing(home, x.get(), facingRef.current);
          if (direction !== facingRef.current) {
            face(direction);
          }
          const generation = bumpMotion();
          x.set(
            withSpring(home, profile.catchSpring, (finished) => {
              if (finished) {
                runOnJS(arrive)(generation);
              }
            })
          );
          seatY.set(withSpring(0, profile.catchSpring));
        }
      } catch (error) {
        // JS-thread callback, not a worklet - report directly; recovery
        // still runs so a mid-drag throw can't leave state wedged.
        onError(error, 'perch.drag');
        dragEngagedRef.current = false;
        chasingRef.current = false;
        dragStartXRef.current = null;
        prevDragTargetRef.current = null;
        cancelAnimation(x);
        cancelRoute();
        if (mountedRef.current) {
          rest();
        }
      }
    });
    return () => {
      // cancel x's in-flight spring before tearing down the subscription -
      // a late completion after unsubscribe would land on a stale closure
      cancelAnimation(x);
      cancelRoute();
      unsubscribe?.();
      prevDragTargetRef.current = null;
      // blur can outrun the gesture's ended event
      dragEngagedRef.current = false;
      chasingRef.current = false;
      dragStartXRef.current = null;
    };
  }, [
    focused,
    reduceMotion,
    screenWidth,
    anchor.slotIndex,
    anchor.slotCount,
    fingerSource,
    x,
    seatY,
    routeRotation,
    cancelRoute,
    bottomExtra,
    arrive,
    rest,
    bumpMotion,
    face,
    profile,
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
