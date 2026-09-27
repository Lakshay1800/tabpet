import { router, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Dimensions, Pressable, StyleSheet, Text, View } from 'react-native';
import { beginCompanionBusy, nativeTabBarLayout, useSetCompanionId } from 'react-native-tabpet';

import { evenSplitCenterX, play, rampScript } from '@/components/demo-finger';
import type { FingerStep } from '@/components/demo-finger';
import { Screen } from '@/components/screen';
import { SLOT_COUNT, slotIndex, TABS, tabRoute } from '@/components/tabs';
import { colors, radius, space, type } from '@/components/tokens';

// The screen a companion://explore link always lands on, so it stands in
// for "the current tab" for the finger-script demos below.
const HERE = slotIndex('explore');

/** far-grab's default target: whichever end slot sits furthest from `here`. */
function farthestSlotFrom(here: number, slotCount: number): number {
  return here - 0 >= slotCount - 1 - here ? 0 : slotCount - 1;
}

/** Prefers the native bar's measured centers, else the even split fallback. */
function tabCenterXNow(slot: number): number {
  const centers = nativeTabBarLayout()?.centers;
  return centers?.[slot] ?? evenSplitCenterX(slot, SLOT_COUNT, Dimensions.get('window').width);
}

function parseSlot(value: string | undefined, fallback: number): number {
  const n = Number(value);
  return Number.isInteger(n) && n >= 0 && n < SLOT_COUNT ? n : fallback;
}

function parseLag(value: string | undefined, fallback: number): number {
  const n = Number(value);
  return Number.isFinite(n) && n >= 0 ? n : fallback;
}

// The busy claim is how an app tells the companion it is working on the
// user's behalf. While held, the seated companion stands up and fidgets.
export default function Explore() {
  const [working, setWorking] = useState(false);
  const [running, setRunning] = useState(false);
  const setCompanionId = useSetCompanionId();
  const timers = useRef<ReturnType<typeof setTimeout>[]>([]);
  const cancelFinger = useRef<() => void>(() => {
    // no script playing yet - replaced once a demo starts
  });
  const startedRef = useRef(false);
  const { demo, to, lag } = useLocalSearchParams<{ demo?: string; to?: string; lag?: string }>();
  useEffect(
    () => () => {
      for (const t of timers.current) {
        clearTimeout(t);
      }
      cancelFinger.current();
    },
    []
  );
  // Route speed 300 pt/s, ~2.1s end to end on a 402pt-wide screen; 900ms
  // lands on the underside, 2900ms lands on the far cap (keepGoing's Settings
  // start needs the extra travel time the turnBack Home start doesn't).
  const runLongWay = useCallback(
    (steps: [string, number][]) => {
      if (running) {
        return;
      }
      setRunning(true);
      setCompanionId('raccoon');
      const last = steps.length - 1;
      timers.current = steps.map(([route, delay], i) =>
        setTimeout(() => {
          router.navigate(route as never);
          if (i === last) {
            setRunning(false);
            startedRef.current = false; // the next deep link may run again
          }
        }, delay)
      );
    },
    [running, setCompanionId]
  );
  const turnBack = useCallback(
    () =>
      runLongWay([
        ['/(tabs)', 0],
        ['/(tabs)/settings', 1500],
        ['/(tabs)/explore', 1500 + 900],
      ]),
    [runLongWay]
  );
  const keepGoing = useCallback(
    () =>
      runLongWay([
        ['/(tabs)/settings', 0],
        ['/(tabs)', 1500],
        ['/(tabs)/explore', 2900],
      ]),
    [runLongWay]
  );
  // Plays a scripted finger, then after `lag` ms past the script's 'ended'
  // step (the stand-in for a slow host app) navigates - the same race a real
  // drag-and-release runs, but reproducible: no test tool can drive the real
  // tab bar scrub. Counting the lag from 'ended' rather than from the
  // script's first event is what makes the navigation actually land after
  // the release; from the script's start it lands too early to race it.
  const runFingerDemo = useCallback(
    (script: FingerStep[], toSlot: number, lagMs: number) => {
      if (running) {
        return;
      }
      setRunning(true);
      const cancelPlay = play(script);
      const endedAtMs = script.at(-1)?.atMs ?? 0;
      const id = setTimeout(() => {
        router.navigate(tabRoute(TABS[toSlot].name) as never);
        setRunning(false);
        startedRef.current = false; // the next deep link may run again
      }, endedAtMs + lagMs);
      timers.current = [id];
      cancelFinger.current = () => {
        cancelPlay();
        clearTimeout(id);
      };
    },
    [running]
  );
  // Deep link drives the scripted sequence instead of a UI button so it can
  // be triggered from Maestro (or `simctl openurl`) without a real tap:
  // companion://explore?demo=turn-back or companion://explore?demo=keep-going
  //
  // The finger-script demos below take the same shape, plus &to=<slotIndex>
  // and &lag=<ms> - lag counts from the script's 'ended' step, not from the
  // link opening, so the navigation always lands after the release:
  // companion://explore?demo=drag-release&to=<slotIndex>&lag=<ms>
  // companion://explore?demo=far-grab&to=<slotIndex>&lag=<ms>
  useEffect(() => {
    if (running || startedRef.current) {
      return;
    }
    if (demo === 'turn-back' || demo === 'keep-going') {
      startedRef.current = true;
      const start = demo === 'turn-back' ? turnBack : keepGoing;
      // clear the param INSIDE the tick: clearing it here re-runs this
      // effect and its cleanup would cancel the timer before it fires
      const id = setTimeout(() => {
        router.setParams({ demo: '' });
        start();
      }, 0);
      return () => clearTimeout(id);
    }
    if (demo === 'drag-release' || demo === 'far-grab') {
      startedRef.current = true;
      const lagMs = parseLag(lag, 250);
      const toSlot =
        demo === 'drag-release'
          ? parseSlot(to, SLOT_COUNT - 1)
          : parseSlot(to, farthestSlotFrom(HERE, SLOT_COUNT));
      const script =
        demo === 'drag-release'
          ? rampScript(tabCenterXNow(HERE), tabCenterXNow(toSlot))
          : rampScript(tabCenterXNow(toSlot), tabCenterXNow(HERE), { limit: 24 });
      const id = setTimeout(() => {
        router.setParams({ demo: '' });
        runFingerDemo(script, toSlot, lagMs);
      }, 0);
      return () => clearTimeout(id);
    }
  }, [demo, to, lag, running, turnBack, keepGoing, runFingerDemo]);
  const work = () => {
    if (working) {
      return;
    }
    setWorking(true);
    const release = beginCompanionBusy();
    setTimeout(() => {
      release();
      setWorking(false);
    }, 4000);
  };
  return (
    <Screen title="Explore">
      <View style={styles.actions}>
        <Pressable
          onPress={work}
          accessibilityRole="button"
          accessibilityState={{ busy: working, disabled: working }}
          style={({ pressed }) => [styles.button, pressed && styles.pressed]}
        >
          <Text style={styles.buttonLabel}>
            {working ? 'Working for 4 seconds' : 'Start a task'}
          </Text>
        </Pressable>
      </View>
    </Screen>
  );
}

const styles = StyleSheet.create({
  actions: { alignItems: 'flex-start', gap: space.md },
  button: {
    backgroundColor: colors.ink,
    paddingHorizontal: space.lg,
    paddingVertical: space.md,
    borderRadius: radius.button,
  },
  pressed: { opacity: 0.8 },
  buttonLabel: type.button,
});
