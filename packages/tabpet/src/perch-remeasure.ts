/**
 * Bounded retry for a measurement that can be momentarily unavailable (the
 * native tab bar hasn't laid out yet on first focus). Pure/Node-safe: no
 * react-native import, ticked by an injected scheduler so it runs under
 * `bun test` without a UI thread.
 */
export interface RetryMeasureOptions {
  /** frames to try before giving up silently. Default 60 (~1s at 60fps). */
  maxTries?: number;
  /** default requestAnimationFrame */
  schedule?: (fn: () => void) => unknown;
  /** default cancelAnimationFrame */
  cancel?: (handle: unknown) => void;
}

/** Calls `measure()` once per tick until it returns a defined value, then
 *  calls `onMeasured` exactly once and stops. Gives up silently after
 *  `maxTries` undefined results. Returns a cancel function that stops the
 *  retry and guarantees `onMeasured` is never called after it runs. */
export function retryMeasure<T>(
  measure: () => T | undefined,
  onMeasured: (value: T) => void,
  opts?: RetryMeasureOptions
): () => void {
  const maxTries = opts?.maxTries ?? 60;
  const schedule = opts?.schedule ?? requestAnimationFrame;
  const cancel = opts?.cancel ?? (cancelAnimationFrame as (handle: unknown) => void);
  let tries = 0;
  let cancelled = false;
  let handle: unknown;

  const tick = () => {
    if (cancelled) {
      return;
    }
    const value = measure();
    if (value !== undefined) {
      onMeasured(value);
      return;
    }
    tries += 1;
    if (tries >= maxTries) {
      return;
    }
    handle = schedule(tick);
  };

  handle = schedule(tick);

  return () => {
    cancelled = true;
    cancel(handle);
  };
}
