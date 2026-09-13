import { deepStrictEqual, strictEqual } from 'node:assert';

import { retryMeasure } from './perch-remeasure';

/** fake scheduler: queues ticks, `flush()` runs them one at a time */
function fakeScheduler() {
  const queue: (() => void)[] = [];
  const cancelled = new Set<number>();
  const handleByTick = new Map<() => void, number>();
  let nextHandle = 0;
  const schedule = (fn: () => void): number => {
    const handle = nextHandle;
    nextHandle += 1;
    queue.push(fn);
    handleByTick.set(fn, handle);
    return handle;
  };
  const cancel = (handle: unknown): void => {
    cancelled.add(handle as number);
  };
  const flush = (): void => {
    for (;;) {
      const fn = queue.shift();
      if (!fn) {
        break;
      }
      const handle = handleByTick.get(fn);
      if (handle !== undefined && cancelled.has(handle)) {
        continue;
      }
      fn();
    }
  };
  return { schedule, cancel, flush };
}

function testResolvesOnFirstDefinedValue(): void {
  const { schedule, cancel, flush } = fakeScheduler();
  let attempts = 0;
  const results: number[] = [];
  retryMeasure<number>(
    () => {
      attempts += 1;
      if (attempts < 3) {
        return;
      }
      return 42;
    },
    (value) => results.push(value),
    { schedule, cancel, maxTries: 60 }
  );
  flush();
  deepStrictEqual(results, [42], 'calls onMeasured once with the first defined value');
  strictEqual(attempts, 3, 'stopped measuring once a value was found');
}

function testGivesUpAfterMaxTries(): void {
  const { schedule, cancel, flush } = fakeScheduler();
  let attempts = 0;
  const results: number[] = [];
  retryMeasure<number>(
    () => {
      attempts += 1;
    },
    (value) => results.push(value),
    { schedule, cancel, maxTries: 5 }
  );
  flush();
  strictEqual(attempts, 5, 'stopped after maxTries undefined results');
  deepStrictEqual(results, [], 'onMeasured never called');
}

function testCancelPreventsCallback(): void {
  const { schedule, cancel, flush } = fakeScheduler();
  let attempts = 0;
  const results: number[] = [];
  const stop = retryMeasure<number>(
    () => {
      attempts += 1;
      if (attempts < 3) {
        return;
      }
      return 42;
    },
    (value) => results.push(value),
    { schedule, cancel, maxTries: 60 }
  );
  stop();
  flush();
  deepStrictEqual(results, [], 'onMeasured never called after cancel');
}

function testOnMeasuredFiresExactlyOnce(): void {
  const { schedule, cancel, flush } = fakeScheduler();
  const results: number[] = [];
  retryMeasure<number>(
    () => 7,
    (value) => results.push(value),
    { schedule, cancel, maxTries: 60 }
  );
  flush();
  flush(); // nothing left queued - a second flush must not re-invoke
  strictEqual(results.length, 1, 'onMeasured fires exactly once');
}

function testDefaultsToRequestAnimationFrame(): void {
  // no injected scheduler: must not throw even without a real rAF loop -
  // just verify the returned cancel function is callable and inert.
  const original = globalThis.requestAnimationFrame;
  const originalCancel = globalThis.cancelAnimationFrame;
  let scheduled = 0;
  (globalThis as { requestAnimationFrame?: unknown }).requestAnimationFrame = () => {
    scheduled += 1;
    return scheduled;
  };
  (globalThis as { cancelAnimationFrame?: unknown }).cancelAnimationFrame = () => {
    // no-op fake
  };
  try {
    const stop = retryMeasure<number>(
      () => {
        // never resolves in this test - just checking scheduling wiring
      },
      () => {
        throw new Error('should not be called');
      }
    );
    strictEqual(scheduled, 1, 'scheduled once via the default rAF');
    stop();
  } finally {
    (globalThis as { requestAnimationFrame?: unknown }).requestAnimationFrame = original;
    (globalThis as { cancelAnimationFrame?: unknown }).cancelAnimationFrame = originalCancel;
  }
}

function main(): void {
  testResolvesOnFirstDefinedValue();
  testGivesUpAfterMaxTries();
  testCancelPreventsCallback();
  testOnMeasuredFiresExactlyOnce();
  testDefaultsToRequestAnimationFrame();
  // oxlint-disable-next-line no-console -- test runner reporting
  console.log('5 passed (perch-remeasure)');
}

main();
