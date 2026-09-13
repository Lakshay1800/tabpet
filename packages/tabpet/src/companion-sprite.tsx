/**
 * Companion sprite: a sprite-grid frame player, pure Views + Reanimated. All
 * textures stay mounted so pose changes never wait on a new expo-image
 * texture. Pose layers cross-dissolve in place - outgoing freezes on its
 * last frame while incoming starts underneath. Never continuous at rest.
 */
import { Image } from 'expo-image';
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef } from 'react';
import { StyleSheet, View } from 'react-native';
import type { ImageSourcePropType } from 'react-native';
import { Gesture, GestureDetector } from 'react-native-gesture-handler';
import Animated, {
  cancelAnimation,
  Easing,
  ReduceMotion,
  runOnJS,
  useAnimatedStyle,
  useReducedMotion,
  useSharedValue,
  withDelay,
  withRepeat,
  withTiming,
} from 'react-native-reanimated';
import type { SharedValue } from 'react-native-reanimated';

import { useCompanionConfig, useCompanionId } from './companion-provider';
import {
  planPoseDissolve,
  poseDissolveApplyOrder,
  shouldResetIncomingFrame,
  shouldSnapBusyIdleFrameToRest,
} from './pose-dissolve';
import type { PupPose } from './pose-dissolve';
import { DEFAULT_COMPANION_ID, getCompanion, listCompanions } from './registry';
import type { CompanionProfile } from './registry';

export type { PupPose } from './pose-dissolve';
/** Same shape as PupPose, named separately so callers don't need to know
 *  the internal pose-dissolve module exists. */
export type CompanionPose = PupPose;

interface SheetSpec {
  source: ImageSourcePropType;
  cols: number;
  rows: number;
  frames: number;
  fps: number;
}

/** Falls back to the default companion, then to whatever's registered first,
 *  when `id` is unknown; throws only in the pathological case where the
 *  registry is completely empty (a host importing `react-native-tabpet/bare` without
 *  registering anything before render). */
export function resolveProfile(id: string): CompanionProfile {
  const profile = getCompanion(id) ?? getCompanion(DEFAULT_COMPANION_ID) ?? listCompanions()[0];
  if (!profile) {
    throw new Error(`default companion "${DEFAULT_COMPANION_ID}" is not registered`);
  }
  return profile;
}

// a stand-in with no real image data: only used while `profile` is
// undefined (empty registry), and that path always renders null - these
// specs never actually reach an <Image>.
const EMPTY_SHEET: SheetSpec = { source: { uri: '' }, cols: 1, rows: 1, frames: 1, fps: 1 };
const EMPTY_SHEETS: Record<PupPose, SheetSpec> = {
  idle: EMPTY_SHEET,
  run: EMPTY_SHEET,
  sit: EMPTY_SHEET,
};

// idle stays 12fps 5x5x25 for every animal;
// run's fps is per-animal (profile.runFps); sit defaults to idle's grid but a
// profile may carry its own (profile.sitSheet) for a 1:1 24fps settle
const DEFAULT_SIT_SHEET = { cols: 5, rows: 5, frames: 25, fps: 12 };
function buildSheets(profile: CompanionProfile | undefined): Record<PupPose, SheetSpec> {
  if (!profile) {
    return EMPTY_SHEETS;
  }
  return {
    idle: { source: profile.sheets.idle, cols: 5, rows: 5, frames: 25, fps: 12 },
    run: { source: profile.sheets.run, cols: 4, rows: 3, frames: 11, fps: profile.runFps },
    sit: { source: profile.sheets.sit, ...(profile.sitSheet ?? DEFAULT_SIT_SHEET) },
  };
}

const DISPLAY = 88;
/** busy loop plays idle at this multiple of its duration, slow + low-contrast per the ambient-motion doctrine */
const BUSY_SLOWDOWN = 1.6;
const sheetDurationMs = (s: SheetSpec) => (s.frames / s.fps) * 1000;

const PRESS_SCALE = 0.98;
const PRESS_IN_MS = 120;
const PRESS_OUT_MS = 160;

interface LayerValues {
  frame: SharedValue<number>;
  opacity: SharedValue<number>;
  facing: SharedValue<1 | -1>;
  z: SharedValue<number>;
}

function PoseLayer({
  spec,
  size,
  values,
  scale,
}: {
  spec: SheetSpec;
  size: number;
  values: LayerValues;
  /** profile.scale, folded into the facing-mirror transform so idle/run/sit
   * share one multiplier (registry.ts) */
  scale: number;
}) {
  const layerStyle = useAnimatedStyle(() => ({
    opacity: values.opacity.get(),
    zIndex: values.z.get(),
    transform: [{ scaleX: values.facing.get() * scale }, { scaleY: scale }],
  }));
  const sheetStyle = useAnimatedStyle(() => {
    const i = Math.min(spec.frames - 1, Math.max(0, Math.round(values.frame.get())));
    return {
      transform: [
        { translateX: -(i % spec.cols) * size },
        { translateY: -Math.floor(i / spec.cols) * size },
      ],
    };
  });

  return (
    <Animated.View
      pointerEvents="none"
      style={[styles.layer, { width: size, height: size }, layerStyle]}
    >
      <View style={[styles.viewport, { width: size, height: size }]}>
        <Animated.View
          style={[styles.sheet, { width: size * spec.cols, height: size * spec.rows }, sheetStyle]}
        >
          <Image source={spec.source} style={styles.sheetImage} contentFit="fill" />
        </Animated.View>
      </View>
    </Animated.View>
  );
}

export interface CompanionSpriteProps {
  companionId?: string;
  size?: number;
  pose?: CompanionPose;
  /** app is working on the user's behalf - idle animates gently instead of resting */
  busy?: boolean;
  facing?: 1 | -1;
  onSitDone?: () => void;
  onPress?: () => void;
  pressLabel?: string;
  /** overrides the provider's onHaptic for this instance */
  onHaptic?: (kind: 'selection' | 'impact') => void;
}

export function CompanionSprite({
  companionId: companionIdProp,
  size = DISPLAY,
  pose = 'idle',
  busy = false,
  facing = 1,
  onSitDone,
  onPress,
  pressLabel,
  onHaptic: onHapticProp,
}: CompanionSpriteProps = {}) {
  const reduceMotion = useReducedMotion();
  const ctxId = useCompanionId();
  const companionId = companionIdProp ?? ctxId;
  // unlike resolveProfile(), never throws: a host on `react-native-tabpet/bare` that
  // hasn't registered anything yet gets no companion rendered, not a crash.
  const profile =
    getCompanion(companionId) ?? getCompanion(DEFAULT_COMPANION_ID) ?? listCompanions()[0];
  const { onError, onHaptic: onHapticConfig } = useCompanionConfig();
  const onHapticResolved = onHapticProp ?? onHapticConfig;
  // stable ref refreshed every render: gesture builders rebuild each render
  // and call these wrappers via runOnJS, which stay referentially stable by
  // always reading the latest onError/onHaptic off this ref.
  const configRef = useRef({ onError, onHaptic: onHapticResolved });
  useEffect(() => {
    configRef.current = { onError, onHaptic: onHapticResolved };
  });
  const reportGestureError = useCallback((site: string, thrown: unknown) => {
    configRef.current.onError(thrown, site);
  }, []);
  const triggerHaptic = useCallback((kind: 'selection' | 'impact') => {
    configRef.current.onHaptic(kind);
  }, []);
  const sheets = useMemo(() => buildSheets(profile), [profile]);
  const pressed = useSharedValue(0);
  const idleFrame = useSharedValue(0);
  const runFrame = useSharedValue(0);
  const sitFrame = useSharedValue(0);
  const idleOpacity = useSharedValue(1);
  const runOpacity = useSharedValue(0);
  const sitOpacity = useSharedValue(0);
  const idleFacing = useSharedValue<1 | -1>(facing);
  const runFacing = useSharedValue<1 | -1>(facing);
  const sitFacing = useSharedValue<1 | -1>(facing);
  const idleZ = useSharedValue(1);
  const runZ = useSharedValue(0);
  const sitZ = useSharedValue(0);
  const previousPose = useRef<PupPose>('idle');
  // live pose for busy-loop cleanup, written in layout so cleanup below sees the NEW pose before it snaps early
  const poseRef = useRef<PupPose>(pose);
  useLayoutEffect(() => {
    poseRef.current = pose;
  }, [pose]);

  const layers: Record<PupPose, LayerValues> = {
    idle: { frame: idleFrame, opacity: idleOpacity, facing: idleFacing, z: idleZ },
    run: { frame: runFrame, opacity: runOpacity, facing: runFacing, z: runZ },
    sit: { frame: sitFrame, opacity: sitOpacity, facing: sitFacing, z: sitZ },
  };

  const playGreeting = (delayMs = 0) => {
    if (reduceMotion) {
      return;
    }
    cancelAnimation(idleFrame);
    idleFrame.set(0);
    idleFrame.set(
      withDelay(
        delayMs,
        withTiming(sheets.idle.frames - 1, {
          duration: sheetDurationMs(sheets.idle),
          easing: Easing.linear,
          reduceMotion: ReduceMotion.System,
        })
      )
    );
  };

  // guards late runOnJS/async completions from touching state post-unmount
  const mountedRef = useRef(true);
  useEffect(
    () => () => {
      mountedRef.current = false;
    },
    []
  );

  useEffect(() => {
    playGreeting(600);
    // oxlint-disable-next-line exhaustive-deps
  }, []);

  useEffect(() => {
    layers[pose].facing.set(facing);
    // oxlint-disable-next-line exhaustive-deps
  }, [facing, pose]);

  useEffect(() => {
    const previous = previousPose.current;
    const incoming = layers[pose];
    const plan = planPoseDissolve(previous, pose, { reduceMotion });

    // cancel first so an older transition can't change visibility mid-handoff
    cancelAnimation(idleOpacity);
    cancelAnimation(runOpacity);
    cancelAnimation(sitOpacity);

    // hidden layer first, then incoming opaque, then outgoing fade - wrong order could leave sit stacked for a frame
    for (const name of poseDissolveApplyOrder(plan)) {
      const assignment = plan[name];
      const layer = layers[name];
      layer.z.set(assignment.z);
      if (assignment.opacity.kind === 'hidden') {
        layer.opacity.set(0);
        if (name === 'idle') {
          // idle is invisible here: rest at idle[0] now, covering a run -> sit
          // hop landing inside the 110ms idle fade (finished=false otherwise).
          cancelAnimation(idleFrame);
          idleFrame.set(0);
        }
      } else if (assignment.opacity.kind === 'opaque') {
        layer.opacity.set(1);
      } else {
        // busy cleanup freezes idle while it's the outgoing layer; once the
        // fade completes restore idle[0] for the next sit -> idle seam.
        const fadingIdle = name === 'idle';
        layer.opacity.set(
          withTiming(0, { duration: assignment.opacity.durationMs }, (finished) => {
            'worklet';
            if (finished && fadingIdle) {
              idleFrame.set(0);
            }
          })
        );
      }
    }

    if (reduceMotion) {
      cancelAnimation(idleFrame);
      cancelAnimation(runFrame);
      cancelAnimation(sitFrame);
      incoming.frame.set(pose === 'sit' ? sheets.sit.frames - 1 : 0);
      previousPose.current = pose;
      return;
    }

    if (previous === pose) {
      // same-pose re-run (mount, reduceMotion flip): leave frames alone so
      // playGreeting / the busy loop survive this effect firing right after.
      return;
    }

    cancelAnimation(incoming.frame);
    if (pose === 'run') {
      incoming.frame.set(0);
      incoming.frame.set(
        withRepeat(
          withTiming(sheets.run.frames - 1, {
            duration: sheetDurationMs(sheets.run),
            easing: Easing.linear,
            reduceMotion: ReduceMotion.System,
          }),
          -1,
          false
        )
      );
    } else if (pose === 'sit') {
      incoming.frame.set(0);
      incoming.frame.set(
        withTiming(
          sheets.sit.frames - 1,
          {
            duration: sheetDurationMs(sheets.sit),
            easing: Easing.linear,
            reduceMotion: ReduceMotion.System,
          },
          (finished) => {
            if (finished && onSitDone) {
              runOnJS(onSitDone)();
            }
          }
        )
      );
    } else if (shouldResetIncomingFrame(previous, pose) || incoming.frame.get() !== 0) {
      // sit -> idle holds the seam only because idle[0] matches sit's last
      // frame; if idle was frozen elsewhere, the seam is already broken -
      // start at the rest cell instead.
      incoming.frame.set(0);
    }

    cancelAnimation(layers[previous].frame);
    previousPose.current = pose;
    // oxlint-disable-next-line exhaustive-deps
  }, [pose, reduceMotion]);

  // idle loops on a slowed cadence while busy (the doctrine's exception);
  // declared AFTER the pose effect so a frame reset can't stomp it.
  useEffect(() => {
    if (!busy || reduceMotion || pose !== 'idle') {
      return;
    }
    cancelAnimation(idleFrame);
    idleFrame.set(0);
    idleFrame.set(
      withRepeat(
        withTiming(sheets.idle.frames - 1, {
          duration: sheetDurationMs(sheets.idle) * BUSY_SLOWDOWN,
          easing: Easing.linear,
          reduceMotion: ReduceMotion.System,
        }),
        -1,
        false
      )
    );
    return () => {
      cancelAnimation(idleFrame);
      if (shouldSnapBusyIdleFrameToRest(poseRef.current)) {
        idleFrame.set(0);
      }
    };
    // oxlint-disable-next-line exhaustive-deps
  }, [busy, pose, reduceMotion]);

  const handleTap = () => {
    if (!mountedRef.current) {
      return;
    }
    // while busy the loop owns idleFrame - a one-shot greeting here would
    // cancel it and freeze the companion on the sheet's last frame
    if (pose === 'idle' && !busy) {
      playGreeting();
    }
    onPress?.();
  };

  // oxlint-disable react-compiler -- RNGH's Gesture.Tap builder, not a component;
  // callbacks run JS-thread post-render via runOnJS, so reading configRef here
  // is the intended latest-ref pattern
  const tapGesture = Gesture.Tap()
    .maxDistance(12)
    .onBegin(() => {
      try {
        pressed.set(reduceMotion ? 0 : withTiming(1, { duration: PRESS_IN_MS }));
      } catch (error) {
        runOnJS(reportGestureError)('companion-sprite.tap.onBegin', error);
      }
    })
    .onFinalize(() => {
      try {
        pressed.set(reduceMotion ? 0 : withTiming(0, { duration: PRESS_OUT_MS }));
      } catch (error) {
        runOnJS(reportGestureError)('companion-sprite.tap.onFinalize', error);
        pressed.set(0);
      }
    })
    .onEnd((_event, success) => {
      try {
        if (!success) {
          return;
        }
        runOnJS(triggerHaptic)('selection');
        runOnJS(handleTap)();
      } catch (error) {
        runOnJS(reportGestureError)('companion-sprite.tap.onEnd', error);
      }
    });
  // oxlint-enable react-compiler

  const pressStyle = useAnimatedStyle(() => {
    const pressScale = reduceMotion ? 1 : 1 + pressed.get() * (PRESS_SCALE - 1);
    return { transform: [{ scale: pressScale }] };
  });

  // every hook above runs unconditionally every render (Rules of Hooks);
  // only the returned element depends on a profile actually existing - a
  // host on `react-native-tabpet/bare` that hasn't registered anything yet renders nothing.
  if (!profile) {
    return null;
  }

  return (
    <GestureDetector gesture={tapGesture}>
      <Animated.View
        accessible
        accessibilityRole="button"
        accessibilityLabel={pressLabel ?? `Your companion ${profile.label}. Tap to say hi.`}
        style={[styles.wrap, { width: size, height: size }]}
      >
        <Animated.View style={[styles.viewportSizer, pressStyle]}>
          <PoseLayer spec={sheets.idle} size={size} values={layers.idle} scale={profile.scale} />
          <PoseLayer spec={sheets.run} size={size} values={layers.run} scale={profile.scale} />
          <PoseLayer spec={sheets.sit} size={size} values={layers.sit} scale={profile.scale} />
        </Animated.View>
      </Animated.View>
    </GestureDetector>
  );
}

const styles = StyleSheet.create({
  wrap: { alignSelf: 'flex-start', marginTop: 4 },
  viewportSizer: { width: '100%', height: '100%' },
  layer: { position: 'absolute', top: 0, left: 0 },
  viewport: { overflow: 'hidden' },
  sheet: { position: 'absolute' },
  sheetImage: { width: '100%', height: '100%' },
});
