/**
 * Busy claim: one small module-level broadcast (not a Redux/Zustand store)
 * the perch renders its own projection of. beginCompanionBusy ref-counts
 * overlapping claims; presentation stays in the perch.
 */

type BusyListener = (busy: boolean) => void;

let busyClaims = 0;
const busyListeners = new Set<BusyListener>();

export function isCompanionBusy(): boolean {
  return busyClaims > 0;
}

/** Claims busy for one in-flight operation, returns an idempotent release.
 *  Ref-counted - listeners fire only on the idle<->busy edge, not per claim. */
export function beginCompanionBusy(): () => void {
  busyClaims += 1;
  if (busyClaims === 1) {
    for (const listener of busyListeners) {
      listener(true);
    }
  }
  let released = false;
  return () => {
    if (released) {
      return;
    }
    released = true;
    busyClaims -= 1;
    if (busyClaims === 0) {
      for (const listener of busyListeners) {
        listener(false);
      }
    }
  };
}

/** Subscribes to idle<->busy edge transitions; safe to claim busy with zero subscribers mounted. */
export function subscribeCompanionBusy(listener: BusyListener): () => void {
  busyListeners.add(listener);
  return () => {
    busyListeners.delete(listener);
  };
}

/** Test-only reset - module-level state must not leak between test cases
 *  in the same process. */
export function __resetCompanionStateForTest(): void {
  busyClaims = 0;
  busyListeners.clear();
}
