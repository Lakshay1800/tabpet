/**
 * Scripted finger source for deep-link demos: feeds the perch the same
 * event shape a real drag would, on a fixed timer schedule, so a
 * drag-and-release race is reproducible without a test tool driving the
 * real tab bar scrub.
 */
import type { FingerEvent, FingerSource } from 'react-native-tabpet';

export interface FingerStep {
  atMs: number;
  x: number;
  phase: FingerEvent['phase'];
}

type Listener = (event: FingerEvent) => void;

const listeners = new Set<Listener>();

/** One scripted source shared by every play() call; merge it with the real
 *  finger via mergeFingerSources() so a physical drag still works too. */
export const demoFingerSource: FingerSource = {
  subscribe(listener) {
    listeners.add(listener);
    return () => listeners.delete(listener);
  },
};

function emit(event: FingerEvent): void {
  for (const listener of listeners) {
    listener(event);
  }
}

/** Runs a script of timed finger events against demoFingerSource; returns a
 *  cancel function that clears any steps still pending. */
export function play(script: readonly FingerStep[]): () => void {
  const timers = script.map((step) =>
    setTimeout(() => emit({ x: step.x, phase: step.phase }), step.atMs)
  );
  return () => {
    for (const timer of timers) {
      clearTimeout(timer);
    }
  };
}

/** Forwards every event from both sources; a null source is skipped, the
 *  same contract nativeTabBarFingerSource() uses for a missing native module. */
export function mergeFingerSources(a: FingerSource | null, b: FingerSource | null): FingerSource {
  return {
    subscribe(listener) {
      const unsubA = a?.subscribe(listener);
      const unsubB = b?.subscribe(listener);
      return () => {
        unsubA?.();
        unsubB?.();
      };
    },
  };
}

/** began -> moved(...) -> ended, stepping stepPt every stepMs from `from`
 *  toward `to`, capped at `limit` pt of travel (default: the whole distance). */
export function rampScript(
  from: number,
  to: number,
  opts: { stepPt?: number; stepMs?: number; limit?: number } = {}
): FingerStep[] {
  const stepPt = opts.stepPt ?? 8;
  const stepMs = opts.stepMs ?? 16;
  const distance = to - from;
  const travel = Math.min(Math.abs(distance), opts.limit ?? Math.abs(distance));
  const sign = Math.sign(distance);
  const steps = Math.max(1, Math.round(travel / stepPt));
  const script: FingerStep[] = [{ atMs: 0, x: from, phase: 'began' }];
  let lastX = from;
  for (let i = 1; i <= steps; i += 1) {
    lastX = from + sign * Math.min(stepPt * i, travel);
    script.push({ atMs: i * stepMs, x: lastX, phase: 'moved' });
  }
  script.push({ atMs: (steps + 1) * stepMs, x: lastX, phase: 'ended' });
  return script;
}

/** Even split of screenWidth, the fallback nativeTabBarLayout() documents
 *  for when it has no measured centers yet. */
export function evenSplitCenterX(slot: number, slotCount: number, screenWidth: number): number {
  return ((slot + 0.5) * screenWidth) / slotCount;
}
