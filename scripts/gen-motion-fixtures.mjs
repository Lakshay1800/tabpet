#!/usr/bin/env node
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import nodeModule, { createRequire } from 'node:module';
import path from 'node:path';
/**
 * Generates conformance/motion.json by driving the REAL react-native-reanimated
 * 4.5.0 animation objects (`withSpring`, `withTiming`, `withDelay`,
 * `withSequence`, `withRepeat`) and recording what their own `onStart`/
 * `onFrame` produce at chosen timestamps, and by driving the real
 * `valueSetter` (the thing that actually runs an animation on a value) with
 * a plain mutable object. Every fixture in this file comes from the real
 * source - none are hand-derived or computed from a reading of the
 * algorithm. Run under tsx (`bun run motion-fixtures`), the same way
 * `bun run conformance` runs scripts/gen-conformance.mjs.
 *
 * `bun run motion-fixtures --check` regenerates every case in memory and
 * exits 1 with a diff summary if the committed file differs, without
 * writing - same convention as `bun run conformance --check`.
 *
 * Loading the real source: Reanimated's animation code (spring.ts, timing.ts,
 * sequence.ts, delay.ts, repeat.ts, Easing.ts, valueSetter.ts) is otherwise
 * plain TypeScript/JS math with no native dependency, but three of its
 * transitive imports exist ONLY to reach a native runtime and cannot be
 * loaded outside one:
 *   - `react-native-worklets` (the JSI worklet bridge: createSerializable,
 *     scheduleOnUI, RuntimeKind, ...) - its real package entry point calls a
 *     native `init()` at import time.
 *   - `src/common/index.ts` (a barrel most files reach only for `logger`,
 *     but which also re-exports `src/common/style` and `src/common/utils`,
 *     pulling in native style-processing machinery unrelated to animation
 *     math).
 *   - `src/featureFlags/index.ts` (a native feature-flag passthrough via
 *     `ReanimatedModule`, reached transitively through `mutables.ts`, itself
 *     only needed so `withSpring`'s onStart can read the current Reduce
 *     Motion system setting - never true in this generator).
 * `registerHooks` (node:module) below stubs exactly those three module
 * specifiers with small pure-JS replacements before any real reanimated file
 * is imported, so the real spring/timing/sequence/delay/repeat/Easing/
 * valueSetter source loads and runs completely unmodified. A fourth hook
 * stubs any `*.png` specifier (the six animal profile modules import their
 * sprite sheets this way) with a trivial default export - this generator
 * only reads each profile's spring configs, never its pixels. Every other
 * file in the animation import chain (springUtils.ts, springConfigs.ts,
 * Easing.ts, Bezier.ts, Colors.ts, ReducedMotion.ts, mutables.ts,
 * valueSetter.ts, matrixUtils.tsx) is the real, unmodified source.
 * `globalThis.__DEV__ = false` is the one small global the code expects
 * outside a bundled RN app (it gates dev-only warnings and a
 * worklet-compilation assertion, neither of which apply here since we call
 * onStart/onFrame directly rather than through the Babel worklet transform).
 *
 * Compare rule: every case in this file is "tolerance" (relative 1e-9,
 * matching conformance/{around,geometry,handoff,pose-dissolve}.json's shared
 * rule) because a spring's position and velocity pass through Math.exp,
 * Math.sin and Math.cos - see wireNumbersEqual below.
 *
 * Determinism: every case is built by explicit, fixed enumeration (animal
 * profiles read from packages/tabpet/src/animals/*.ts, spread grids listed
 * inline below). No Math.random, no Date, no environment reads beyond the
 * one-time __DEV__ shim.
 *
 * Time: every case drives its animation with strictly increasing absolute
 * timestamps, starting at its own start time, run until the real onFrame
 * reports finished (capped at 600 frames) - see driveSpringUntilFinished/
 * driveUntilFinished below. Exactly one case starts at absolute time zero
 * (retarget-at-t-zero-defeats-triggered-twice, whose whole point is what
 * happens at t=0); every other case starts at a nonzero time.
 */

const MIN_NODE_LABEL = 'Node >= 22.15 (module.registerHooks)';
if (typeof nodeModule.registerHooks !== 'function') {
  console.error(
    `gen-motion-fixtures: module.registerHooks is missing on ${process.version} - ${MIN_NODE_LABEL}`
  );
  process.exit(1);
}

const root = path.resolve(import.meta.dirname, '..');
const outDir = path.join(root, 'conformance');
const outFile = path.join(outDir, 'motion.json');

// ---------------------------------------------------------------------------
// module hooks: stub the native-only / logging-only / asset modules, load
// everything else (including all of spring.ts/timing.ts/sequence.ts/
// delay.ts/repeat.ts/Easing.ts/springUtils.ts/springConfigs.ts/
// valueSetter.ts) for real. See header above.
// ---------------------------------------------------------------------------

const COMMON_BARREL_SUFFIX = '/react-native-reanimated/src/common/index.ts';
const FEATURE_FLAGS_SUFFIX = '/react-native-reanimated/src/featureFlags/index.ts';

// createSerializable/serializableMappingCache/scheduleOnUI are called at
// module-load time by animation/util.ts and mutables.ts for style-updater
// bookkeeping this generator never exercises (no UI thread, no shared
// values) - each is a harmless no-op or identity. RuntimeKind only needs to
// exist as an object: globalThis.__RUNTIME_KIND is never set in Node, so
// every `!== RuntimeKind.ReactNative` comparison in the real source is true
// regardless of RuntimeKind's actual values, which is the correct outcome
// (we are, genuinely, not running inside React Native).
const WORKLETS_STUB_SRC = `
export const RuntimeKind = { ReactNative: 1, UI: 2, Worker: 3 };
export function createSerializable(value) { return value; }
export function isWorkletFunction() { return false; }
export function scheduleOnUI() {}
export const serializableMappingCache = { set() {}, get() { return undefined; }, delete() {} };
export function createShareable(_uiRuntimeId, initial) { return initial; }
export function createSynchronizable(initial) { return initial; }
export function runOnUISync(fn, arg) { return fn(arg); }
export const UIRuntimeId = 1;
`;

// The only export the animation code actually needs from this barrel is
// `logger` (springUtils.ts, animation/util.ts) plus a handful of booleans
// (mutables.ts, ReducedMotion.ts). SHOULD_BE_USE_WEB: true is the load-bearing
// value here - it routes animation/util.ts's `defineAnimation` and
// mutables.ts's `makeMutable` down their pure-JS "web" branch, which is what
// makes the rest of the real source runnable without any native bridge at
// all (no createShareable/createSynchronizable call ever actually happens).
const COMMON_STUB_SRC = `
export const logger = { warn() {}, error() {} };
export const IS_JEST = true;
export const IS_WEB = false;
export const IS_WINDOWS = false;
export const IS_ANDROID = false;
export const IS_IOS = true;
export const IS_WINDOW_AVAILABLE = false;
export const SHOULD_BE_USE_WEB = true;
`;

// Real getStaticFeatureFlag reads a native module (through ReanimatedModule)
// for flags that only matter on the native makeMutable path - unreachable
// here since SHOULD_BE_USE_WEB is true above. Always-false is a safe stand-in.
const FEATURE_FLAGS_STUB_SRC = `
export function getStaticFeatureFlag() { return false; }
export function getDynamicFeatureFlag() { return false; }
export function setDynamicFeatureFlag() {}
`;

// The six animal profile modules import their sprite sheets this way -
// this generator only reads spring configs off the exported profile object,
// never pixels, so a trivial default export is a safe stand-in.
const PNG_STUB_SRC = `export default 'motion-fixtures-stub:png-asset';`;

const STUB_SOURCES = {
  'motion-fixtures-stub:react-native-worklets': WORKLETS_STUB_SRC,
  'motion-fixtures-stub:common': COMMON_STUB_SRC,
  'motion-fixtures-stub:feature-flags': FEATURE_FLAGS_STUB_SRC,
  'motion-fixtures-stub:png-asset': PNG_STUB_SRC,
};

nodeModule.registerHooks({
  resolve(specifier, context, nextResolve) {
    if (specifier === 'react-native-worklets') {
      return { url: 'motion-fixtures-stub:react-native-worklets', shortCircuit: true };
    }
    if (specifier.endsWith('.png')) {
      return { url: 'motion-fixtures-stub:png-asset', shortCircuit: true };
    }
    const result = nextResolve(specifier, context);
    if (result.url.endsWith(COMMON_BARREL_SUFFIX)) {
      return { url: 'motion-fixtures-stub:common', shortCircuit: true };
    }
    if (result.url.endsWith(FEATURE_FLAGS_SUFFIX)) {
      return { url: 'motion-fixtures-stub:feature-flags', shortCircuit: true };
    }
    return result;
  },
  load(url, context, nextLoad) {
    if (url in STUB_SOURCES) {
      return { format: 'module', shortCircuit: true, source: STUB_SOURCES[url] };
    }
    return nextLoad(url, context);
  },
});

// The one small global the real source expects outside a bundled RN app -
// see header. false (production) skips dev-only warnings and the
// worklet-compilation assertion in withTiming, neither applicable here.
globalThis.__DEV__ = false;

// ---------------------------------------------------------------------------
// locate the installed react-native-reanimated package's TS source, pinned
// to the lockfile version - resolved via node's own module resolution from
// packages/tabpet (its real dependent), never a hardcoded machine path.
// ---------------------------------------------------------------------------

const PINNED_VERSION = '4.5.0';

function resolveReanimatedSrcDir() {
  const requireFromTabpet = createRequire(path.join(root, 'packages/tabpet/package.json'));
  const pkgJsonPath = requireFromTabpet.resolve('react-native-reanimated/package.json');
  const pkg = JSON.parse(readFileSync(pkgJsonPath, 'utf-8'));
  if (pkg.version !== PINNED_VERSION) {
    throw new Error(
      `gen-motion-fixtures: expected react-native-reanimated@${PINNED_VERSION} (pinned in bun.lock), found ${pkg.version} - this generator was read against ${PINNED_VERSION}; re-verify before bumping the pin.`
    );
  }
  return path.join(path.dirname(pkgJsonPath), 'src');
}

const srcDir = resolveReanimatedSrcDir();
const srcRelLabel = 'node_modules/react-native-reanimated/src'; // stable label for the fixture's "source" field

const { withSpring } = await import(path.join(srcDir, 'animation/spring/spring.ts'));
const { GentleSpringConfig, GentleSpringConfigWithDuration } = await import(
  path.join(srcDir, 'animation/spring/springConfigs.ts')
);
const { withTiming } = await import(path.join(srcDir, 'animation/timing.ts'));
const { withDelay } = await import(path.join(srcDir, 'animation/delay.ts'));
const { withSequence } = await import(path.join(srcDir, 'animation/sequence.ts'));
const { withRepeat } = await import(path.join(srcDir, 'animation/repeat.ts'));
const { Easing } = await import(path.join(srcDir, 'Easing.ts'));
const { valueSetter } = await import(path.join(srcDir, 'valueSetter.ts'));

// ---------------------------------------------------------------------------
// wire-format encoding - identical convention to scripts/gen-conformance.mjs
// ---------------------------------------------------------------------------

function encodeNumber(x) {
  const buf = Buffer.alloc(8);
  buf.writeDoubleBE(x, 0);
  const bits = buf.toString('hex');
  let value;
  if (Number.isNaN(x)) {
    value = 'NaN';
  } else if (x === Infinity) {
    value = 'Infinity';
  } else if (x === -Infinity) {
    value = '-Infinity';
  } else if (Object.is(x, -0)) {
    value = '-0';
  } else {
    value = x;
  }
  return { bits, value };
}

function encodeSpringConfig(config) {
  const out = {};
  for (const [key, value] of Object.entries(config)) {
    if (value === undefined) {
      continue;
    }
    if (key === 'clamp') {
      out.clamp = {
        min: value.min === undefined ? null : encodeNumber(value.min),
        max: value.max === undefined ? null : encodeNumber(value.max),
      };
    } else if (key === 'overshootClamping') {
      out[key] = value;
    } else {
      out[key] = encodeNumber(value);
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// driving the real animation objects directly (spring/timing/delay/sequence/
// repeat cases) - each case now drives with strictly increasing absolute
// times, starting at its own start time, until the real onFrame reports
// finished, capped at 600 frames. Nothing here re-derives the algorithm:
// every recorded number comes straight out of the real onStart/onFrame.
// ---------------------------------------------------------------------------

const MAX_FRAMES = 600;

/** Records {current, velocity, zeta, omega0, omega1, initialEnergy} right
 *  after onStart - a direct probe of the stiffness solve
 *  (calculateNewStiffnessToMatchDuration/initialCalculations), independent
 *  of any later onFrame step. velocity/zeta/omega0/omega1/initialEnergy are
 *  null for non-spring animations (timing/sequence/delay/repeat animation
 *  objects don't carry them). */
function snapshotAfterStart(anim, isSpring) {
  return {
    current: encodeNumber(anim.current),
    velocity: isSpring ? encodeNumber(anim.velocity) : null,
    zeta: isSpring ? encodeNumber(anim.zeta) : null,
    omega0: isSpring ? encodeNumber(anim.omega0) : null,
    omega1: isSpring ? encodeNumber(anim.omega1) : null,
    initialEnergy: isSpring ? encodeNumber(anim.initialEnergy) : null,
  };
}

/** Drives the real onFrame with strictly increasing absolute times
 *  `startAt + dt, startAt + 2*dt, ...`, recording {t, current, velocity,
 *  finished} after each call, until `finished` is true or MAX_FRAMES is
 *  reached (whichever first). Throws if it never finishes within the cap -
 *  a case that can't finish in 600 frames is a case with a bad dt/config,
 *  not something to silently truncate. */
function driveUntilFinished(anim, startAt, dt, isSpring, label) {
  const frames = [];
  let t = startAt;
  for (let i = 0; i < MAX_FRAMES; i += 1) {
    t += dt;
    const finished = anim.onFrame(anim, t);
    frames.push({
      t: encodeNumber(t),
      current: encodeNumber(anim.current),
      velocity: isSpring ? encodeNumber(anim.velocity) : null,
      finished,
    });
    if (finished) {
      return frames;
    }
  }
  throw new Error(
    `gen-motion-fixtures: case '${label}' did not finish within ${MAX_FRAMES} frames at dt=${dt}`
  );
}

/** Self-check (not written to the fixture): asserts frame times strictly
 *  increase, and - unless the case starts at rest (x0 == 0) - that it
 *  records at least 10 distinct `current` values before finishing. */
function assertSpringShape(label, frames, exemptRestStart) {
  for (let i = 1; i < frames.length; i += 1) {
    const prev = frames[i - 1].t.value;
    const cur = frames[i].t.value;
    if (!(cur > prev)) {
      throw new Error(
        `gen-motion-fixtures: case '${label}' frame times are not strictly increasing at index ${i}`
      );
    }
  }
  if (!frames.at(-1).finished) {
    throw new Error(`gen-motion-fixtures: case '${label}' never reported finished`);
  }
  if (!exemptRestStart) {
    const distinct = new Set(frames.map((f) => f.current.value));
    if (distinct.size < 10) {
      throw new Error(
        `gen-motion-fixtures: case '${label}' recorded only ${distinct.size} distinct values before finishing (want >= 10)`
      );
    }
  }
}

const cases = [];

/** Interrupted mid-flight, on purpose: a retarget case's own frames before
 *  the retarget are a FIXED short run (not driven to completion) - the
 *  whole point is to retarget a spring that has NOT yet settled. Only the
 *  post-retarget leg (or a case with no retarget at all) is driven until
 *  the real onFrame reports finished. */
const PRE_RETARGET_FRAME_COUNT = 6;

function addSpringCase(
  label,
  { fromValue, toValue, config, startT, dt = 16.666, restStart = false, retarget = null }
) {
  const anim = withSpring(toValue, config);
  anim.onStart(anim, fromValue, startT);
  const afterStart = snapshotAfterStart(anim, true);

  let frames;
  if (retarget) {
    frames = [];
    let t = startT;
    for (let i = 0; i < PRE_RETARGET_FRAME_COUNT; i += 1) {
      t += dt;
      const finished = anim.onFrame(anim, t);
      frames.push({
        t: encodeNumber(t),
        current: encodeNumber(anim.current),
        velocity: encodeNumber(anim.velocity),
        finished,
      });
      if (finished) {
        throw new Error(
          `gen-motion-fixtures: case '${label}' finished before its own retarget at t=${retarget.t} - pick a later retarget time or a slower config`
        );
      }
    }
  } else {
    frames = driveUntilFinished(anim, startT, dt, true, label);
    assertSpringShape(label, frames, restStart);
  }

  let retargetOut = null;
  if (retarget) {
    const anim2 = withSpring(retarget.toValue, retarget.config);
    anim2.onStart(anim2, anim.current, retarget.t, anim);
    const afterStart2 = snapshotAfterStart(anim2, true);
    const frames2 = driveUntilFinished(
      anim2,
      retarget.t,
      retarget.dt ?? dt,
      true,
      `${label} (retarget)`
    );
    assertSpringShape(`${label} (retarget)`, frames2, retarget.restStart ?? false);
    if (frames2.length === 0) {
      throw new Error(
        `gen-motion-fixtures: case '${label}' retarget has no frames after the retarget`
      );
    }
    retargetOut = {
      t: encodeNumber(retarget.t),
      toValue: encodeNumber(retarget.toValue),
      config: encodeSpringConfig(retarget.config),
      afterStart: afterStart2,
      frames: frames2,
    };
  }

  cases.push({
    fn: 'spring',
    label,
    args: {
      fromValue: encodeNumber(fromValue),
      toValue: encodeNumber(toValue),
      config: encodeSpringConfig(config),
      startT: encodeNumber(startT),
      dt: encodeNumber(dt),
      retarget: retarget
        ? {
            t: encodeNumber(retarget.t),
            toValue: encodeNumber(retarget.toValue),
            config: encodeSpringConfig(retarget.config),
            dt: encodeNumber(retarget.dt ?? dt),
          }
        : null,
    },
    expect: { afterStart, frames, retarget: retargetOut },
    compare: 'tolerance',
  });
}

/** The overshoot-clamp case's whole point is that the clamp changes the
 *  trajectory - this asserts that directly (never written to the fixture,
 *  since it isn't itself something Swift needs to replay): the same case
 *  built WITHOUT `overshootClamping` must overshoot the target at some
 *  frame, while the real clamped one never does. */
function assertOvershootClampMatters(label, { fromValue, toValue, config, startT, dt }) {
  const clampedConfig = { ...config, overshootClamping: true };
  const unclampedConfig = { ...config, overshootClamping: false };

  function overshoots(cfg) {
    const anim = withSpring(toValue, cfg);
    anim.onStart(anim, fromValue, startT);
    let t = startT;
    const direction = toValue - fromValue;
    for (let i = 0; i < MAX_FRAMES; i += 1) {
      t += dt;
      const finished = anim.onFrame(anim, t);
      const past = direction >= 0 ? anim.current > toValue : anim.current < toValue;
      if (past) {
        return true;
      }
      if (finished) {
        return false;
      }
    }
    throw new Error(
      `gen-motion-fixtures: overshoot probe for '${label}' did not finish within ${MAX_FRAMES} frames`
    );
  }

  if (overshoots(clampedConfig)) {
    throw new Error(
      `gen-motion-fixtures: '${label}' overshot even WITH overshootClamping - the clamp case proves nothing`
    );
  }
  if (!overshoots(unclampedConfig)) {
    throw new Error(
      `gen-motion-fixtures: '${label}' never overshot even without overshootClamping - pick a case that actually would`
    );
  }
}

function addTimingCase(label, { fromValue, toValue, config, easingName, startT, frameTimes }) {
  const realConfig = { ...config };
  if (easingName === 'linear') {
    realConfig.easing = Easing.linear;
  } else if (easingName === 'inOutQuad') {
    // omit `easing` entirely - proves withTiming's own default IS
    // inOut(quad); this string always means "no easing key was given".
  }
  const anim = withTiming(toValue, realConfig);
  anim.onStart(anim, fromValue, startT);
  const frames = [];
  for (const t of frameTimes) {
    const finished = anim.onFrame(anim, t);
    frames.push({
      t: encodeNumber(t),
      current: encodeNumber(anim.current),
      velocity: null,
      finished,
    });
    if (finished) {
      break;
    }
  }
  assertStrictlyIncreasing(label, frameTimes);
  cases.push({
    fn: 'timing',
    label,
    args: {
      fromValue: encodeNumber(fromValue),
      toValue: encodeNumber(toValue),
      duration: encodeNumber(config.duration ?? 300),
      easing: easingName,
      startT: encodeNumber(startT),
      frameTimes: frameTimes.map(encodeNumber),
    },
    expect: { frames },
    compare: 'tolerance',
  });
}

function assertStrictlyIncreasing(label, times) {
  for (let i = 1; i < times.length; i += 1) {
    if (!(times[i] > times[i - 1])) {
      throw new Error(
        `gen-motion-fixtures: case '${label}' frame times are not strictly increasing at index ${i}`
      );
    }
  }
  if (times.length > 0 && !(times[0] > 0) && label !== ZERO_START_LABEL) {
    throw new Error(
      `gen-motion-fixtures: case '${label}' starts at or before time zero - only ${ZERO_START_LABEL} may`
    );
  }
}

const ZERO_START_LABEL = 'retarget-at-t-zero-defeats-triggered-twice';

function cumulative(startT, steps) {
  const out = [];
  let t = startT;
  for (const dt of steps) {
    t += dt;
    out.push(t);
  }
  return out;
}

function repeatStep(dt, n) {
  return Array.from({ length: n }, () => dt);
}

function addDelayCase(label, { delayMs, fromValue, inner, startT, frameTimes }) {
  const innerAnim = withTiming(inner.toValue, { duration: inner.duration, easing: Easing.linear });
  const anim = withDelay(delayMs, innerAnim);
  anim.onStart(anim, fromValue, startT);
  const frames = [];
  for (const t of frameTimes) {
    const finished = anim.onFrame(anim, t);
    frames.push({
      t: encodeNumber(t),
      current: encodeNumber(anim.current),
      velocity: null,
      finished,
    });
    if (finished) {
      break;
    }
  }
  assertStrictlyIncreasing(label, frameTimes);
  cases.push({
    fn: 'delay',
    label,
    args: {
      delayMs: encodeNumber(delayMs),
      fromValue: encodeNumber(fromValue),
      inner: {
        kind: 'timing',
        toValue: encodeNumber(inner.toValue),
        duration: encodeNumber(inner.duration),
        easing: 'linear',
      },
      startT: encodeNumber(startT),
      frameTimes: frameTimes.map(encodeNumber),
    },
    expect: { frames },
    compare: 'tolerance',
  });
}

function addSequenceCase(label, { fromValue, timing, spring, startT, frameTimes }) {
  const timingAnim = withTiming(timing.toValue, {
    duration: timing.duration,
    easing: Easing.linear,
  });
  const springAnim = withSpring(spring.toValue, spring.config);
  const anim = withSequence(timingAnim, springAnim);
  anim.onStart(anim, fromValue, startT);
  const frames = [];
  for (const t of frameTimes) {
    const finished = anim.onFrame(anim, t);
    frames.push({
      t: encodeNumber(t),
      current: encodeNumber(anim.current),
      velocity: null,
      finished,
    });
    if (finished) {
      break;
    }
  }
  assertStrictlyIncreasing(label, frameTimes);
  cases.push({
    fn: 'sequence',
    label,
    args: {
      fromValue: encodeNumber(fromValue),
      animations: [
        {
          kind: 'timing',
          toValue: encodeNumber(timing.toValue),
          duration: encodeNumber(timing.duration),
          easing: 'linear',
        },
        {
          kind: 'spring',
          toValue: encodeNumber(spring.toValue),
          config: encodeSpringConfig(spring.config),
        },
      ],
      startT: encodeNumber(startT),
      frameTimes: frameTimes.map(encodeNumber),
    },
    expect: { frames },
    compare: 'tolerance',
  });
}

function addRepeatCase(label, { fromValue, inner, numberOfReps, reverse, startT, frameTimes }) {
  const innerAnim = withTiming(inner.toValue, { duration: inner.duration, easing: Easing.linear });
  const anim = withRepeat(innerAnim, numberOfReps, reverse);
  anim.onStart(anim, fromValue, startT);
  const frames = [];
  for (const t of frameTimes) {
    const finished = anim.onFrame(anim, t);
    frames.push({
      t: encodeNumber(t),
      current: encodeNumber(anim.current),
      velocity: null,
      finished,
    });
    if (finished) {
      break;
    }
  }
  assertStrictlyIncreasing(label, frameTimes);
  cases.push({
    fn: 'repeat',
    label,
    args: {
      fromValue: encodeNumber(fromValue),
      inner: {
        kind: 'timing',
        toValue: encodeNumber(inner.toValue),
        duration: encodeNumber(inner.duration),
        easing: 'linear',
      },
      numberOfReps,
      reverse,
      startT: encodeNumber(startT),
      frameTimes: frameTimes.map(encodeNumber),
    },
    expect: { frames },
    compare: 'tolerance',
  });
}

// ---- 1. spread of start displacement / start velocity ----

const DURATION_CFG = { duration: 500, dampingRatio: 0.8 };
const BASE_T = 1000; // every case but ZERO_START_LABEL starts at a nonzero time

addSpringCase('spread-zero-displacement-zero-velocity', {
  fromValue: 100,
  toValue: 100,
  config: { ...DURATION_CFG, velocity: 0 },
  startT: BASE_T,
  restStart: true,
}); // initialEnergy===0, finishes on frame 1
addSpringCase('spread-zero-displacement-nonzero-velocity', {
  fromValue: 100,
  toValue: 100,
  config: { ...DURATION_CFG, velocity: 150 },
  startT: BASE_T,
});
addSpringCase('spread-zero-velocity-positive-displacement', {
  fromValue: 0,
  toValue: 100,
  config: { ...DURATION_CFG, velocity: 0 },
  startT: BASE_T,
});
addSpringCase('spread-zero-velocity-negative-displacement', {
  fromValue: 0,
  toValue: -100,
  config: { ...DURATION_CFG, velocity: 0 },
  startT: BASE_T,
});
addSpringCase('spread-velocity-toward-target', {
  fromValue: 0,
  toValue: 100,
  config: { ...DURATION_CFG, velocity: 300 },
  startT: BASE_T,
});
addSpringCase('spread-velocity-away-from-target', {
  fromValue: 0,
  toValue: 100,
  config: { ...DURATION_CFG, velocity: -300 },
  startT: BASE_T,
}); // onStart's clip: velocity pointing away from toValue is clipped to 0
addSpringCase('spread-large-displacement', {
  fromValue: -500,
  toValue: 500,
  config: DURATION_CFG,
  startT: BASE_T,
});
addSpringCase('spread-tiny-displacement', {
  fromValue: 99.5,
  toValue: 100,
  config: DURATION_CFG,
  startT: BASE_T,
});
addSpringCase('spread-default-config', {
  fromValue: 0,
  toValue: 100,
  config: { ...GentleSpringConfig, ...GentleSpringConfigWithDuration },
  startT: BASE_T,
});
addSpringCase('spread-stiffness-damping-not-duration', {
  fromValue: 0,
  toValue: 100,
  config: { stiffness: 200, damping: 20, mass: 1 },
  startT: BASE_T,
});
addSpringCase('spread-overshoot-clamping', {
  fromValue: 0,
  toValue: 100,
  config: { duration: 400, dampingRatio: 0.5, overshootClamping: true },
  startT: BASE_T,
  dt: 2,
});
assertOvershootClampMatters('spread-overshoot-clamping', {
  fromValue: 0,
  toValue: 100,
  config: { duration: 400, dampingRatio: 0.5 },
  startT: BASE_T,
  dt: 2,
});

// ---- 2. the three spring configs of all six animal profiles, read from
//         the TS profile modules themselves, never a literal here ----

const { bird } = await import(path.join(root, 'packages/tabpet/src/animals/bird.ts'));
const { cat } = await import(path.join(root, 'packages/tabpet/src/animals/cat.ts'));
const { panda } = await import(path.join(root, 'packages/tabpet/src/animals/panda.ts'));
const { raccoon } = await import(path.join(root, 'packages/tabpet/src/animals/raccoon.ts'));
const { squirrel } = await import(path.join(root, 'packages/tabpet/src/animals/squirrel.ts'));
const { turtle } = await import(path.join(root, 'packages/tabpet/src/animals/turtle.ts'));

const ANIMAL_PROFILES = { panda, cat, bird, raccoon, squirrel, turtle };

for (const [animalId, profile] of Object.entries(ANIMAL_PROFILES)) {
  for (const kind of ['commitSpring', 'trackSpring', 'catchSpring']) {
    addSpringCase(`animal-${animalId}-${kind}`, {
      fromValue: 0,
      toValue: 120,
      config: profile[kind],
      startT: BASE_T,
    });
  }
}

// ---- 3. retargets mid-spring ----
//
// isTriggeredTwice (spring.ts) reads previousAnimation?.duration and
// previousAnimation?.dampingRatio, but spring.ts never actually assigns a
// `duration` or `dampingRatio` field onto the animation object it returns
// (verified directly against the installed package: both are `undefined` on
// every spring animation, always) - so those two comparisons are always
// `undefined === undefined`, i.e. always true, and play no real part in the
// decision. The only conditions that actually gate isTriggeredTwice are: a
// truthy previous.lastTimestamp, a truthy previous.startTimestamp, and
// toValue equality. A spring whose own startTimestamp happens to be exactly
// 0 (a fresh start at absolute time zero) therefore can NEVER be
// "triggered twice" on its next retarget, no matter how closely the new
// config matches the old one - see retarget-at-t-zero-defeats-triggered-twice
// below, kept and documented rather than fixed. A retarget's config
// (duration/dampingRatio) is otherwise completely irrelevant to whether
// isTriggeredTwice fires - see retarget-same-target-different-config below.

const RETARGET_START_CFG = {
  fromValue: 0,
  toValue: 100,
  config: DURATION_CFG,
  startT: BASE_T,
};

addSpringCase('retarget-same-target-same-config', {
  ...RETARGET_START_CFG,
  retarget: { t: BASE_T + 100, toValue: 100, config: DURATION_CFG },
});

addSpringCase('retarget-same-target-different-config', {
  ...RETARGET_START_CFG,
  retarget: { t: BASE_T + 100, toValue: 100, config: { duration: 250, dampingRatio: 1 } },
});

// the isTriggeredTwice quirk itself: identical target AND config, but the
// FIRST spring started at absolute t=0, so its own startTimestamp is 0
// (falsy) - isTriggeredTwice's `previousAnimation?.startTimestamp &&` check
// fails even though every other condition matches, so this retarget gets a
// fresh stiffness solve (still inheriting velocity - that part is
// unconditional on `previousAnimation` truthy, not on isTriggeredTwice).
// This is the one case in the whole fixture allowed to start at t=0.
addSpringCase(ZERO_START_LABEL, {
  fromValue: 0,
  toValue: 100,
  config: DURATION_CFG,
  startT: 0,
  retarget: { t: 100, toValue: 100, config: DURATION_CFG },
});

addSpringCase('retarget-new-target-velocity-toward', {
  ...RETARGET_START_CFG,
  retarget: { t: BASE_T + 100, toValue: 250, config: DURATION_CFG },
});

addSpringCase('retarget-new-target-velocity-clipped', {
  ...RETARGET_START_CFG,
  retarget: { t: BASE_T + 100, toValue: -50, config: DURATION_CFG },
});

// spring.ts resets `lastTimestamp` to 0 on natural termination ("clear
// lastTimestamp to avoid using stale value by the next spring animation
// that starts after this one"). Confirmed to matter by breaking the REAL
// installed spring.ts the same way in a scratch copy (the one line removed,
// the file restored byte-for-byte after) and re-driving this exact scenario
// against both: leg1 finishes naturally, then leg2 - a real gap later, not
// a same-tick handoff - is started with leg1 as its own previousAnimation
// (exactly what sequence.ts's own onFrame does when handing a finished leg
// to the next leg's onStart). With the reset removed, leg2's own
// `lastTimestamp = previousAnimation?.lastTimestamp || now` picks up leg1's
// STALE finish time instead of leg2's own start time, changing leg2's dt
// clamp on its very first onFrame call and producing a materially
// different current/velocity. This case proves the real (unmodified)
// behavior: leg2's own start time wins, not leg1's stale one.
{
  const leg1 = withSpring(50, { duration: 120, dampingRatio: 1 });
  leg1.onStart(leg1, 0, BASE_T);
  const leg1AfterStart = snapshotAfterStart(leg1, true);
  const leg1Frames = driveUntilFinished(
    leg1,
    BASE_T,
    16.666,
    true,
    'retarget-after-natural-finish-leg1'
  );
  const leg1FinishTime = leg1Frames.at(-1).t.value;

  const leg2StartT = leg1FinishTime + 40; // a real gap, never a same-tick handoff
  const leg2 = withSpring(200, { duration: 300, dampingRatio: 0.8 });
  leg2.onStart(leg2, leg1.current, leg2StartT, leg1);
  const leg2AfterStart = snapshotAfterStart(leg2, true);
  const leg2Frames = driveUntilFinished(
    leg2,
    leg2StartT,
    16.666,
    true,
    'retarget-after-natural-finish-leg2'
  );
  assertSpringShape('retarget-after-natural-finish-leg2', leg2Frames, false);

  cases.push({
    fn: 'spring',
    label: 'retarget-after-natural-finish-uses-fresh-lastTimestamp',
    args: {
      fromValue: encodeNumber(0),
      toValue: encodeNumber(50),
      config: encodeSpringConfig({ duration: 120, dampingRatio: 1 }),
      startT: encodeNumber(BASE_T),
      dt: encodeNumber(16.666),
      retarget: {
        t: encodeNumber(leg2StartT),
        toValue: encodeNumber(200),
        config: encodeSpringConfig({ duration: 300, dampingRatio: 0.8 }),
        dt: encodeNumber(16.666),
      },
    },
    expect: {
      afterStart: leg1AfterStart,
      frames: leg1Frames,
      retarget: {
        t: encodeNumber(leg2StartT),
        toValue: encodeNumber(200),
        config: encodeSpringConfig({ duration: 300, dampingRatio: 0.8 }),
        afterStart: leg2AfterStart,
        frames: leg2Frames,
      },
    },
    compare: 'tolerance',
  });
}

// ---- 4. frame steps of 8.33 / 16.67 / 33.3 / 64 / 200 ms ----

for (const dt of [8.33, 16.666, 33.3, 64, 200]) {
  addSpringCase(`dt-step-${dt}`, {
    fromValue: 0,
    toValue: 100,
    config: DURATION_CFG,
    startT: BASE_T,
    dt,
  });
}
// a single 5000ms stall proves the 64ms clamp independent of a fixed dt grid.
// Irregular gaps (5000ms then 16.666ms) - `frames[i].t` carries each frame's
// own absolute time, so no single `dt` field describes this case; `dt` is
// left null (informational only - the Swift replay always reads time off
// each frame row, never recomputes it from `dt`).
{
  const stallTimes = [BASE_T + 5000, BASE_T + 5016.666];
  assertStrictlyIncreasing('dt-clamp-single-huge-stall', stallTimes);
  const anim = withSpring(100, DURATION_CFG);
  anim.onStart(anim, 0, BASE_T);
  const afterStart = snapshotAfterStart(anim, true);
  const frames = [];
  let lastT = BASE_T;
  for (const t of stallTimes) {
    const finished = anim.onFrame(anim, t);
    frames.push({
      t: encodeNumber(t),
      current: encodeNumber(anim.current),
      velocity: encodeNumber(anim.velocity),
      finished,
    });
    lastT = t;
    if (finished) {
      throw new Error(
        "gen-motion-fixtures: case 'dt-clamp-single-huge-stall' finished during the stall frames themselves - pick a slower config so driving past the stall at a normal step still means something"
      );
    }
  }
  // The stall alone never finishes this config - keep driving at a normal
  // step afterward until it does, then run the same shape assertion every
  // other spring case gets (strictly increasing times, actually finishes,
  // and visits at least 10 distinct values along the way).
  let t = lastT;
  for (let i = 0; i < MAX_FRAMES; i += 1) {
    t += 16.666;
    const finished = anim.onFrame(anim, t);
    frames.push({
      t: encodeNumber(t),
      current: encodeNumber(anim.current),
      velocity: encodeNumber(anim.velocity),
      finished,
    });
    if (finished) {
      break;
    }
    if (i === MAX_FRAMES - 1) {
      throw new Error(
        "gen-motion-fixtures: case 'dt-clamp-single-huge-stall' did not finish within the post-stall frame cap"
      );
    }
  }
  assertSpringShape('dt-clamp-single-huge-stall', frames, false);
  cases.push({
    fn: 'spring',
    label: 'dt-clamp-single-huge-stall',
    args: {
      fromValue: encodeNumber(0),
      toValue: encodeNumber(100),
      config: encodeSpringConfig(DURATION_CFG),
      startT: encodeNumber(BASE_T),
      dt: null,
      retarget: null,
    },
    expect: { afterStart, frames, retarget: null },
    compare: 'tolerance',
  });
}

// ---- 5. timing: linear and the default easing ----

addTimingCase('timing-linear', {
  fromValue: 0,
  toValue: 100,
  config: { duration: 300 },
  easingName: 'linear',
  startT: BASE_T,
  frameTimes: cumulative(BASE_T, repeatStep(16.666, 25)),
});
addTimingCase('timing-default-easing-inout-quad', {
  fromValue: 0,
  toValue: 100,
  config: { duration: 300 },
  easingName: 'inOutQuad',
  startT: BASE_T,
  frameTimes: cumulative(BASE_T, repeatStep(16.666, 25)),
});
// timing runs on absolute elapsed time, so it catches up after a stall
addTimingCase('timing-catches-up-after-stall', {
  fromValue: 0,
  toValue: 100,
  config: { duration: 300 },
  easingName: 'linear',
  startT: BASE_T,
  frameTimes: [BASE_T + 16.666, BASE_T + 500, BASE_T + 516.666],
});

// ---- 6. a delay ----

addDelayCase('delay-65ms-then-timing', {
  delayMs: 65,
  fromValue: 0,
  inner: { toValue: 100, duration: 200 },
  startT: BASE_T,
  frameTimes: [16.666, 33.3, 64.9, 65.1, 100, 200, 265, 300].map((dt) => BASE_T + dt),
});

// ---- 7. a sequence of timing then spring ----

addSequenceCase('sequence-timing-then-spring', {
  fromValue: 0,
  timing: { toValue: 100, duration: 200 },
  spring: { toValue: 100, config: DURATION_CFG },
  startT: BASE_T,
  frameTimes: cumulative(BASE_T, [...repeatStep(16.666, 15), ...repeatStep(16.666, 40)]),
});

// ---- 8. a repeat ----

addRepeatCase('repeat-3-reverse', {
  fromValue: 0,
  inner: { toValue: 100, duration: 100 },
  numberOfReps: 3,
  reverse: true,
  startT: BASE_T,
  frameTimes: cumulative(BASE_T, repeatStep(16.666, 30)),
});
addRepeatCase('repeat-infinite-no-reverse', {
  fromValue: 0,
  inner: { toValue: 100, duration: 100 },
  numberOfReps: 0,
  reverse: false,
  startT: BASE_T,
  frameTimes: cumulative(BASE_T, repeatStep(16.666, 40)),
});

// ---------------------------------------------------------------------------
// 9. a script of operations on one value, driven through the real
//    valueSetter - proves MotionTrack's start/cancel/replace behaviour
//    (including velocity/zeta inheritance, the same-value short circuit,
//    and a delay holding the value of whatever it replaced) against the
//    thing that actually runs an animation on a value, not just the
//    animation objects in isolation.
// ---------------------------------------------------------------------------

/** { _value, _animation, value getter } - the shape valueSetter needs. Not
 *  the real makeMutableWeb (which also wires listeners, checkInvalidWrite,
 *  toJSON, etc. - all irrelevant here): just the three members valueSetter.ts
 *  itself actually reads or writes. */
function makeMutable(initial) {
  return {
    _value: initial,
    _animation: null,
    get value() {
      return this._value;
    },
  };
}

function encodeAnimSpec(spec) {
  switch (spec.kind) {
    case 'timing': {
      return {
        kind: 'timing',
        toValue: encodeNumber(spec.toValue),
        duration: encodeNumber(spec.duration),
        easing: spec.easing,
      };
    }
    case 'spring': {
      return {
        kind: 'spring',
        toValue: encodeNumber(spec.toValue),
        config: encodeSpringConfig(spec.config),
      };
    }
    case 'delay': {
      return {
        kind: 'delay',
        delayMs: encodeNumber(spec.delayMs),
        inner: encodeAnimSpec(spec.inner),
      };
    }
    case 'sequence': {
      return { kind: 'sequence', animations: spec.animations.map(encodeAnimSpec) };
    }
    default: {
      throw new Error(`gen-motion-fixtures: unknown track op spec kind '${spec.kind}'`);
    }
  }
}

/** No-op stand-in for `record` on a sequence child - see buildAnimation's
 *  'sequence' case for why. */
function noLegCallback(finished) {
  void finished;
}

function buildAnimation(spec, record) {
  switch (spec.kind) {
    case 'timing': {
      const cfg = { duration: spec.duration };
      if (spec.easing === 'linear') {
        cfg.easing = Easing.linear;
      }
      return withTiming(spec.toValue, cfg, (finished) => record(finished));
    }
    case 'spring': {
      return withSpring(spec.toValue, spec.config, (finished) => record(finished));
    }
    case 'delay': {
      // delay.ts's own `.callback` FORWARDS to the inner animation's
      // callback (`(finished) => nextAnimation.callback?.(finished)`), so
      // wiring `record` onto the inner IS wiring it onto the delay's own
      // top-level completion - not a per-leg callback distinct from it.
      return withDelay(spec.delayMs, buildAnimation(spec.inner, record));
    }
    case 'sequence': {
      // UNLIKE delay, sequence.ts calls EACH child's own `.callback`
      // directly as that child finishes (`if (currentAnim.callback)
      // currentAnim.callback(true)`) - a real, per-leg callback distinct
      // from the sequence's own top-level one. TabPetMotion's
      // SequenceAnimation has no per-leg callback field at all (see its
      // own header comment) - a fixture case built from a top-level
      // `record` wired onto every leg would record firings no Swift replay
      // could ever reproduce. Every leg here gets a no-op instead; only a
      // callback wired onto the OUTERMOST animation (never a `sequence`'s
      // own children) is ever recorded.
      return withSequence(...spec.animations.map((a) => buildAnimation(a, noLegCallback)));
    }
    default: {
      throw new Error(`gen-motion-fixtures: unknown track op spec kind '${spec.kind}'`);
    }
  }
}

/** Runs `ops` (a script of {kind:'set', now, spec} / {kind:'setValue', now,
 *  value} / {kind:'cancelSelf', now} / {kind:'frame', now}) through the
 *  real valueSetter on one fresh mutable, driving requestAnimationFrame
 *  with a queue this drains ourselves: a 'frame' op drains every callback
 *  pending BEFORE that frame (matching how a real host frame pump invokes
 *  every rAF callback registered before it, not just the newest one -
 *  replacing an animation leaves its own still-queued callback in the
 *  queue, and that stale entry must fire as a harmless no-op on the next
 *  frame, not be skipped or mistaken for the new one).
 *
 *  'setValue' drives valueSetter's plain-value branch directly (a host
 *  writing a bare number, not an animation object) - `MotionEngine.set`'s
 *  real-world counterpart. 'cancelSelf' drives `cancelAnimation`'s own
 *  mechanism (animation/util.ts): `sharedValue.value = sharedValue.value` -
 *  self-assignment through the ordinary setter. */
function runTrackScript(label, initialValue, ops) {
  const mutable = makeMutable(initialValue);
  let rafQueue = [];
  const savedRAF = globalThis.requestAnimationFrame;
  globalThis.requestAnimationFrame = (frameStep) => {
    rafQueue.push(frameStep);
    return rafQueue.length;
  };

  // A callback can fire on a LATER op than the one that built its
  // animation (a timing finishing on a `frame` op, or a replaced-but-not-
  // yet-cancelled animation's callback firing again on a later `set` - see
  // valueSetter.ts's own `previousAnimation.callback?.(false)`) - each
  // `set` op therefore gets its OWN record closure, bound to that op's own
  // index, so every firing can be tagged with which op actually built the
  // animation whose callback just ran, not just which op it ran DURING.
  // `currentOpCallbacks` is reassigned at the START of each op, so every
  // firing (regardless of which earlier op built the animation) lands in
  // the CURRENT op's own bucket for that reason alone.
  let currentOpCallbacks = [];
  function makeRecord(builtByOpIndex) {
    return (finished) => currentOpCallbacks.push({ finished: !!finished, builtByOpIndex });
  }

  const results = [];
  try {
    for (const [opIndex, op] of ops.entries()) {
      currentOpCallbacks = [];
      if (op.kind === 'set') {
        const value = buildAnimation(op.spec, makeRecord(opIndex));
        globalThis.__frameTimestamp = op.now;
        valueSetter(mutable, value);
        globalThis.__frameTimestamp = undefined;
      } else if (op.kind === 'setValue') {
        globalThis.__frameTimestamp = op.now;
        valueSetter(mutable, op.value);
        globalThis.__frameTimestamp = undefined;
      } else if (op.kind === 'cancelSelf') {
        // util.ts cancelAnimationNative: `sharedValue.value = sharedValue.value;`
        // - forceUpdate is passed explicitly true here for clarity, not
        // because it changes the outcome: the cancellation this proves
        // (previousAnimation.callback?.(false), unconditional) runs BEFORE
        // valueSetter ever consults forceUpdate.
        globalThis.__frameTimestamp = op.now;
        valueSetter(mutable, mutable.value, true);
        globalThis.__frameTimestamp = undefined;
      } else if (op.kind === 'frame') {
        const due = rafQueue;
        rafQueue = [];
        if (due.length === 0) {
          throw new Error(
            `gen-motion-fixtures: track case '${label}': no pending frame to run at t=${op.now}`
          );
        }
        globalThis.__frameTimestamp = op.now;
        for (const frameStep of due) {
          frameStep(op.now);
        }
        globalThis.__frameTimestamp = undefined;
      } else {
        throw new Error(`gen-motion-fixtures: unknown op kind '${op.kind}'`);
      }
      results.push({
        value: encodeNumber(mutable._value),
        callbacks: currentOpCallbacks,
      });
    }
  } finally {
    globalThis.requestAnimationFrame = savedRAF;
  }
  return results;
}

function encodeTrackOp(op) {
  switch (op.kind) {
    case 'set': {
      return { kind: 'set', now: encodeNumber(op.now), spec: encodeAnimSpec(op.spec) };
    }
    case 'setValue': {
      return { kind: 'setValue', now: encodeNumber(op.now), value: encodeNumber(op.value) };
    }
    case 'cancelSelf': {
      return { kind: 'cancelSelf', now: encodeNumber(op.now) };
    }
    case 'frame': {
      return { kind: 'frame', now: encodeNumber(op.now) };
    }
    default: {
      throw new Error(`gen-motion-fixtures: unknown track op kind '${op.kind}'`);
    }
  }
}

function addTrackCase(label, { initialValue, ops }) {
  const results = runTrackScript(label, initialValue, ops);
  cases.push({
    fn: 'track',
    label,
    args: {
      initialValue: encodeNumber(initialValue),
      ops: ops.map(encodeTrackOp),
    },
    expect: { results },
    compare: 'tolerance',
  });
}

// a timing replaced in the middle by a spring
addTrackCase('track-timing-replaced-midflight-by-spring', {
  initialValue: 0,
  ops: [
    {
      kind: 'set',
      now: BASE_T,
      spec: { kind: 'timing', toValue: 100, duration: 400, easing: 'linear' },
    },
    { kind: 'frame', now: BASE_T + 16.666 },
    { kind: 'frame', now: BASE_T + 200 },
    {
      kind: 'set',
      now: BASE_T + 250,
      spec: { kind: 'spring', toValue: 100, config: DURATION_CFG },
    },
    { kind: 'frame', now: BASE_T + 266.666 },
    { kind: 'frame', now: BASE_T + 300 },
  ],
});

// a spring replaced by a spring to the same target
addTrackCase('track-spring-replaced-by-spring-same-target', {
  initialValue: 0,
  ops: [
    { kind: 'set', now: BASE_T, spec: { kind: 'spring', toValue: 100, config: DURATION_CFG } },
    { kind: 'frame', now: BASE_T + 16.666 },
    { kind: 'frame', now: BASE_T + 33.3 },
    { kind: 'set', now: BASE_T + 50, spec: { kind: 'spring', toValue: 100, config: DURATION_CFG } },
    { kind: 'frame', now: BASE_T + 66.666 },
  ],
});

// ...and to a new target
addTrackCase('track-spring-replaced-by-spring-new-target', {
  initialValue: 0,
  ops: [
    { kind: 'set', now: BASE_T, spec: { kind: 'spring', toValue: 100, config: DURATION_CFG } },
    { kind: 'frame', now: BASE_T + 16.666 },
    { kind: 'frame', now: BASE_T + 33.3 },
    { kind: 'set', now: BASE_T + 50, spec: { kind: 'spring', toValue: 250, config: DURATION_CFG } },
    { kind: 'frame', now: BASE_T + 66.666 },
  ],
});

// a running timing replaced by a delay of 65ms then a timing - the value
// must hold during the delay
addTrackCase('track-timing-replaced-by-delay-then-timing', {
  initialValue: 0,
  ops: [
    {
      kind: 'set',
      now: BASE_T,
      spec: { kind: 'timing', toValue: 100, duration: 1000, easing: 'linear' },
    },
    { kind: 'frame', now: BASE_T + 16.666 },
    { kind: 'frame', now: BASE_T + 33.3 },
    {
      kind: 'set',
      now: BASE_T + 50,
      spec: {
        kind: 'delay',
        delayMs: 65,
        inner: { kind: 'timing', toValue: 200, duration: 200, easing: 'linear' },
      },
    },
    { kind: 'frame', now: BASE_T + 60 }, // 10ms into the delay - holds
    { kind: 'frame', now: BASE_T + 80 }, // 30ms into the delay - still holds
    { kind: 'frame', now: BASE_T + 120 }, // 70ms - delay elapsed, inner timing starts
    { kind: 'frame', now: BASE_T + 136.666 },
  ],
});

// a set to the value the track already has (via a running animation
// reaching it, then a plain spring/timing retarget to that same value -
// valueSetter's short circuit: completes true at once, nothing starts)
addTrackCase('track-set-to-already-held-value', {
  initialValue: 0,
  ops: [
    {
      kind: 'set',
      now: BASE_T,
      spec: { kind: 'timing', toValue: 50, duration: 50, easing: 'linear' },
    },
    { kind: 'frame', now: BASE_T + 16.666 },
    { kind: 'frame', now: BASE_T + 33.3 },
    { kind: 'frame', now: BASE_T + 66.666 }, // finishes at current=50
    {
      kind: 'set',
      now: BASE_T + 100,
      spec: { kind: 'timing', toValue: 50, duration: 300, easing: 'linear' },
    },
  ],
});

// a spring with a start velocity in its config that follows a timing - the
// timing has no `.velocity` field, so the sum is JS `undefined + number`
// (NaN), and `|| 0` makes the start velocity 0 regardless of config.velocity
addTrackCase('track-spring-velocity-after-timing', {
  initialValue: 0,
  ops: [
    {
      kind: 'set',
      now: BASE_T,
      spec: { kind: 'timing', toValue: 100, duration: 300, easing: 'linear' },
    },
    { kind: 'frame', now: BASE_T + 16.666 },
    { kind: 'frame', now: BASE_T + 320 }, // finishes (300ms elapsed)
    {
      kind: 'set',
      now: BASE_T + 340,
      spec: { kind: 'spring', toValue: 150, config: { ...DURATION_CFG, velocity: 300 } },
    },
    { kind: 'frame', now: BASE_T + 356.666 },
  ],
});

/** Drives a throwaway copy of the same animation graph via plain onStart/
 *  onFrame (bypassing valueSetter entirely) to find how many `dt`-spaced
 *  frames it takes to finish - used only to size the frame-op list a real
 *  track case then drives, never to compute any recorded value itself. */
function framesUntilFinished(buildFn, fromValue, startT, dt) {
  const anim = buildFn();
  anim.onStart(anim, fromValue, startT);
  let t = startT;
  for (let count = 1; count <= MAX_FRAMES; count += 1) {
    t += dt;
    if (anim.onFrame(anim, t)) {
      return count;
    }
  }
  throw new Error('gen-motion-fixtures: framesUntilFinished did not finish within MAX_FRAMES');
}

function frameOpsUntil(startT, dt, count) {
  return cumulative(startT, repeatStep(dt, count)).map((now) => ({ kind: 'frame', now }));
}

// a sequence whose first leg is a spring with a start velocity, on a FRESH
// value (previous is JS null, not undefined - sequence.ts's fallback to its
// last leg does NOT fire, so the spring's own onStart sees previous=null and
// keeps its config velocity) - driven all the way to the end (both legs
// finish), not just one frame past the start.
{
  const dt = 16.666;
  const frameCount = framesUntilFinished(
    () =>
      withSequence(
        withSpring(100, { ...DURATION_CFG, velocity: 300 }),
        withTiming(100, { duration: 100, easing: Easing.linear })
      ),
    0,
    BASE_T,
    dt
  );
  addTrackCase('track-sequence-first-leg-spring-velocity-fresh', {
    initialValue: 0,
    ops: [
      {
        kind: 'set',
        now: BASE_T,
        spec: {
          kind: 'sequence',
          animations: [
            { kind: 'spring', toValue: 100, config: { ...DURATION_CFG, velocity: 300 } },
            { kind: 'timing', toValue: 100, duration: 100, easing: 'linear' },
          ],
        },
      },
      ...frameOpsUntil(BASE_T, dt, frameCount),
    ],
  });
}

// ...and on a value with a running timing (previous is a real object, not
// undefined - sequence.ts's fallback still does not fire, but the spring's
// own onStart now sees a non-spring previous and drops the config velocity,
// same NaN||0 rule as track-spring-velocity-after-timing above) - this one
// is cancelled (cancelSelf) DURING its first leg, before that leg ever
// finishes, rather than driven to the end (the fresh case above already
// covers driving a sequence track case all the way through).
addTrackCase('track-sequence-first-leg-spring-velocity-after-timing', {
  initialValue: 0,
  ops: [
    {
      kind: 'set',
      now: BASE_T,
      spec: { kind: 'timing', toValue: 50, duration: 1000, easing: 'linear' },
    },
    { kind: 'frame', now: BASE_T + 16.666 },
    {
      kind: 'set',
      now: BASE_T + 50,
      spec: {
        kind: 'sequence',
        animations: [
          { kind: 'spring', toValue: 100, config: { ...DURATION_CFG, velocity: 300 } },
          { kind: 'timing', toValue: 100, duration: 100, easing: 'linear' },
        ],
      },
    },
    { kind: 'frame', now: BASE_T + 66.666 },
    { kind: 'frame', now: BASE_T + 83.332 },
    { kind: 'cancelSelf', now: BASE_T + 90 },
  ],
});

// a spring that starts at its own target with no velocity, on a fresh
// mutable already holding that value - valueSetter's OUTER short circuit
// (distinct from the spring's own onStart/onFrame zero-displacement case
// covered elsewhere): onStart/onFrame never run at all
addTrackCase('track-spring-starts-at-target-no-velocity', {
  initialValue: 80,
  ops: [{ kind: 'set', now: BASE_T, spec: { kind: 'spring', toValue: 80, config: DURATION_CFG } }],
});

// a sequence whose SECOND leg is a delay wrapping a timing - proves
// sequence.ts's own `currentAnim.finished = true` (set on the first leg
// once it finishes, before the sequence ever advances) actually reaches a
// later leg that inherits it as `previous`
addTrackCase('track-sequence-timing-then-delay-then-timing', {
  initialValue: 0,
  ops: [
    {
      kind: 'set',
      now: BASE_T,
      spec: {
        kind: 'sequence',
        animations: [
          { kind: 'timing', toValue: 50, duration: 100, easing: 'linear' },
          {
            kind: 'delay',
            delayMs: 65,
            inner: { kind: 'timing', toValue: 150, duration: 100, easing: 'linear' },
          },
        ],
      },
    },
    { kind: 'frame', now: BASE_T + 16.666 },
    { kind: 'frame', now: BASE_T + 100 }, // first leg (timing) finishes, the delay leg starts
    { kind: 'frame', now: BASE_T + 120 }, // 20ms into the 65ms delay - holds
    { kind: 'frame', now: BASE_T + 165 }, // delay elapsed - the inner timing starts
    { kind: 'frame', now: BASE_T + 200 },
  ],
});

// engine.set's real-world counterpart: valueSetter's plain-value branch,
// once while an animation is still running (cancels it, completion false,
// then writes the value), once with the value the track already holds
// (still a plain write - nothing is running to cancel by that point)
addTrackCase('track-set-value-while-running-and-already-held', {
  initialValue: 0,
  ops: [
    {
      kind: 'set',
      now: BASE_T,
      spec: { kind: 'timing', toValue: 50, duration: 100, easing: 'linear' },
    },
    { kind: 'frame', now: BASE_T + 16.666 },
    { kind: 'setValue', now: BASE_T + 30, value: 77 },
    { kind: 'setValue', now: BASE_T + 40, value: 77 },
  ],
});

// cancelAnimation's own mechanism (`sharedValue.value = sharedValue.value`):
// once against a still-running animation (fires its completion false),
// once against one that already finished naturally and fired true (fires
// the SAME completion again, with false - a natural finish never clears
// the stored animation/callback), and a third time against nothing at all
// (a true no-op by then)
addTrackCase('track-cancel-self-fires-completion-false', {
  initialValue: 0,
  ops: [
    {
      kind: 'set',
      now: BASE_T,
      spec: { kind: 'timing', toValue: 50, duration: 50, easing: 'linear' },
    },
    { kind: 'frame', now: BASE_T + 16.666 },
    { kind: 'cancelSelf', now: BASE_T + 30 },
    {
      kind: 'set',
      now: BASE_T + 40,
      spec: { kind: 'timing', toValue: 100, duration: 50, easing: 'linear' },
    },
    { kind: 'frame', now: BASE_T + 56.666 },
    { kind: 'frame', now: BASE_T + 90.666 },
    { kind: 'cancelSelf', now: BASE_T + 100 },
    { kind: 'cancelSelf', now: BASE_T + 110 },
  ],
});

// ---------------------------------------------------------------------------
// payload / write / check
// ---------------------------------------------------------------------------

const constants = {
  ENERGY_THRESHOLD: encodeNumber(6e-9),
  DT_CLAMP_MS: encodeNumber(64),
  GENTLE_MASS: encodeNumber(GentleSpringConfig.mass),
  GENTLE_DAMPING: encodeNumber(GentleSpringConfig.damping),
  GENTLE_STIFFNESS: encodeNumber(GentleSpringConfig.stiffness),
  GENTLE_DURATION: encodeNumber(GentleSpringConfigWithDuration.duration),
  GENTLE_DAMPING_RATIO: encodeNumber(GentleSpringConfigWithDuration.dampingRatio),
  DEFAULT_TIMING_DURATION_MS: encodeNumber(300),
};

const payload = {
  module: 'motion',
  source: srcRelLabel,
  reanimatedVersion: PINNED_VERSION,
  constants,
  cases,
};

function renderPayload(p) {
  return `${JSON.stringify(p)}\n`;
}

function decodeWireNumber(node) {
  return Buffer.from(node.bits, 'hex').readDoubleBE(0);
}

function isWireNumber(node) {
  return (
    node !== null &&
    typeof node === 'object' &&
    !Array.isArray(node) &&
    typeof node.bits === 'string' &&
    'value' in node &&
    Object.keys(node).length === 2
  );
}

/** every case in motion.json is "tolerance" - see header. NaN matches only NaN. */
function numbersEqual(a, b) {
  if (Number.isNaN(a) || Number.isNaN(b)) {
    return Number.isNaN(a) && Number.isNaN(b);
  }
  if (!Number.isFinite(a) || !Number.isFinite(b)) {
    return a === b;
  }
  const scale = Math.max(1, Math.abs(a), Math.abs(b));
  return Math.abs(a - b) <= 1e-9 * scale;
}

function structuralEqual(a, b) {
  if (isWireNumber(a) && isWireNumber(b)) {
    return numbersEqual(decodeWireNumber(a), decodeWireNumber(b));
  }
  if (a === null || b === null) {
    return a === b;
  }
  if (Array.isArray(a) && Array.isArray(b)) {
    return a.length === b.length && a.every((v, i) => structuralEqual(v, b[i]));
  }
  if (typeof a === 'object' && typeof b === 'object') {
    const keys = new Set([...Object.keys(a), ...Object.keys(b)]);
    for (const k of keys) {
      if (!structuralEqual(a[k], b[k])) {
        return false;
      }
    }
    return true;
  }
  return a === b;
}

function firstStructuralDiff(fresh, committed) {
  if (fresh.module !== committed.module) {
    return `module ${committed.module} -> ${fresh.module}`;
  }
  if (fresh.reanimatedVersion !== committed.reanimatedVersion) {
    return `reanimatedVersion ${committed.reanimatedVersion} -> ${fresh.reanimatedVersion}`;
  }
  if (!structuralEqual(fresh.constants, committed.constants)) {
    return 'constants differ';
  }
  if (fresh.cases.length !== committed.cases.length) {
    return `case count ${committed.cases.length} -> ${fresh.cases.length}`;
  }
  for (let i = 0; i < fresh.cases.length; i += 1) {
    const f = fresh.cases[i];
    const c = committed.cases[i];
    if (f.fn !== c.fn || f.label !== c.label) {
      return `case ${i}: ${c.fn}/${c.label} -> ${f.fn}/${f.label}`;
    }
    if (!structuralEqual(f.args, c.args)) {
      return `case ${i} (${f.label}): args differ`;
    }
    if (!structuralEqual(f.expect, c.expect)) {
      return `case ${i} (${f.label}): expect differs`;
    }
  }
  return null;
}

function main() {
  const check = process.argv.includes('--check');
  const label = path.relative(root, outFile);

  if (check) {
    if (!existsSync(outFile)) {
      console.error(
        `motion-fixtures --check: ${label} is missing - run \`bun run motion-fixtures\` and commit the result`
      );
      process.exit(1);
    }
    let committed;
    try {
      committed = JSON.parse(readFileSync(outFile, 'utf-8'));
    } catch (error) {
      console.error(`motion-fixtures --check: ${label} is not valid JSON: ${error.message}`);
      process.exit(1);
    }
    const diff = firstStructuralDiff(payload, committed);
    if (diff === null) {
      console.log(`motion-fixtures --check: ${label} up to date (${payload.cases.length} cases)`);
      return;
    }
    console.error(
      `motion-fixtures --check: ${diff} - run \`bun run motion-fixtures\` and commit the result`
    );
    process.exit(1);
  }

  if (!existsSync(outDir)) {
    mkdirSync(outDir, { recursive: true });
  }
  const rendered = renderPayload(payload);
  writeFileSync(outFile, rendered);
  console.log(
    `motion-fixtures: wrote ${label} (${rendered.length} bytes, ${payload.cases.length} cases)`
  );
}

main();
