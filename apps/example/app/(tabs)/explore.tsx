import { router, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { beginCompanionBusy, useSetCompanionId } from 'tabpet';

import { Screen } from '@/components/screen';
import { colors, radius, space, type } from '@/components/tokens';

// The busy claim is how an app tells the companion it is working on the
// user's behalf. While held, the seated companion stands up and fidgets.
export default function Explore() {
  const [working, setWorking] = useState(false);
  const [running, setRunning] = useState(false);
  const setCompanionId = useSetCompanionId();
  const timers = useRef<ReturnType<typeof setTimeout>[]>([]);
  const startedRef = useRef(false);
  const { demo } = useLocalSearchParams<{ demo?: string }>();
  useEffect(
    () => () => {
      for (const t of timers.current) {
        clearTimeout(t);
      }
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
  // Deep link drives the scripted sequence instead of a UI button so it can
  // be triggered from Maestro (or `simctl openurl`) without a real tap:
  // companion://explore?demo=turn-back or companion://explore?demo=keep-going
  useEffect(() => {
    if (running || startedRef.current) {
      return;
    }
    if (demo !== 'turn-back' && demo !== 'keep-going') {
      return;
    }
    startedRef.current = true;
    const start = demo === 'turn-back' ? turnBack : keepGoing;
    // clear the param INSIDE the tick: clearing it here re-runs this effect
    // and its cleanup would cancel the timer before it fires
    const id = setTimeout(() => {
      router.setParams({ demo: '' });
      start();
    }, 0);
    return () => clearTimeout(id);
  }, [demo, running, turnBack, keepGoing]);
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
