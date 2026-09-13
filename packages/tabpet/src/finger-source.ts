/**
 * Finger-position feed the perch's drag-chase reads from: the native
 * UITabBar recognizer, or an RNGH Gesture.Pan fallback for a custom bar.
 * Both emit the same shape so the perch never needs to know which is live.
 */
import { useCallback, useMemo, useRef } from 'react';
import { Gesture } from 'react-native-gesture-handler';
import type { PanGesture } from 'react-native-gesture-handler';

import GlassPan, { subscribeGlassPan } from './native/glass-pan';

export type FingerPhase = 'began' | 'moved' | 'ended' | 'cancelled';

export interface FingerEvent {
  x: number;
  phase: FingerPhase;
}

export interface FingerSource {
  subscribe: (listener: (event: FingerEvent) => void) => () => void;
}

function noop(): void {
  // no teardown needed
}

/** Wraps the native tab-bar drag recognizer; null when the native module is
 *  absent (Expo Go, a build that hasn't compiled it in). */
export function nativeTabBarFingerSource(): FingerSource | null {
  if (!GlassPan) {
    return null;
  }
  return {
    subscribe(listener) {
      const unsubscribe = subscribeGlassPan(listener);
      // null only when GlassPan itself is absent, already checked above
      return unsubscribe ?? noop;
    },
  };
}

/** RNGH fallback for a custom (non-UITabBar) bar: attach `gesture` to the
 *  bar's own View and hand `source` to CompanionPerch. minDistance(0) so the
 *  very first touch sample counts, matching the native recognizer's began. */
export function useGestureFingerSource(): { source: FingerSource; gesture: PanGesture } {
  const listenersRef = useRef(new Set<(event: FingerEvent) => void>());
  const emit = useCallback((event: FingerEvent) => {
    for (const listener of listenersRef.current) {
      listener(event);
    }
  }, []);

  // oxlint-disable react-compiler -- RNGH's Gesture.Pan builder, not a component; its
  // callbacks run on the JS thread post-render (runOnJS(true)), same as the private
  // app's grab gesture - the listenersRef read here is the intended pattern, not a
  // render-time ref access
  return useMemo(() => {
    const source: FingerSource = {
      subscribe(listener) {
        listenersRef.current.add(listener);
        return () => {
          listenersRef.current.delete(listener);
        };
      },
    };
    const gesture = Gesture.Pan()
      .runOnJS(true)
      .minDistance(0)
      .onBegin((e) => {
        emit({ x: e.absoluteX, phase: 'began' });
      })
      .onUpdate((e) => {
        emit({ x: e.absoluteX, phase: 'moved' });
      })
      .onEnd((e) => {
        emit({ x: e.absoluteX, phase: 'ended' });
      })
      .onFinalize((e, success) => {
        if (!success) {
          emit({ x: e.absoluteX, phase: 'cancelled' });
        }
      });
    return { source, gesture };
  }, [emit]);
  // oxlint-enable react-compiler
}
