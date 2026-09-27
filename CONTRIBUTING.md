# Contributing

## Setup

- Bun 1.3 or later (Node 22 or newer)
- `bun install` from the repo root
- `bun run check` runs leak-check, typecheck, fmt:check, lint, and test
- `bun run test` runs every `*.test.ts` under tsx via `node scripts/run-tests.mjs`

## Repo Layout

- `packages/tabpet/src/` - the library (TypeScript, ESM)
- `apps/example/` - demo app using the library
- `packages/tabpet/ios/` - the Swift module (UITabBar pan events and bar layout); `packages/tabpet/src/native/` wraps it
- `tools/sprite-sheet.sh` - sprite-sheet slicing pipeline (`--from/--to` window, `--flip`)
- `packages/tabpet/assets/` - sprite sheets for the six shipped animals (PNG)
- `assets/` - `LICENSE-ART.md` only

## Tests

Pure unit tests use `node:assert` (no external framework). Run via `bun run test`, which discovers every `*.test.ts` under `packages/` (see `scripts/run-tests.mjs`) and runs each under `tsx` on Node (not `bun test`).

Adding an animal means editing `sheets.test.ts` - add the new ID to its ANIMALS list.

## Verifying motion

The finger chase and the bar's own scrub are simulator-blind. Sign off on a device before shipping motion changes. See `tools/README.md` for `frame-stack.sh` (records a simulator flow and cuts it into a frame stack and contact sheet) and `pill-geometry.sh` (measures the pill's edges per frame).

## Motion Invariants

Every gesture callback body and spring completion must obey these constraints:

- **Gesture callback recovery**: Wrap every callback in try/catch; recovery must reset refs (animation position, seat, facing) and re-seat the companion.
- **Spring completion gating**: Every spring completion that gates state must be generation-gated (`shouldApplyArrive`) and duration-parametrized (use `{duration, dampingRatio}` only; never mass/stiffness).
- **Finger source cleanup**: Call `cancelAnimation(x)` before unsubscribing from a finger source in effects.
- **Blur cleanup ordering**: When blurring a tab, read the live x and seat BEFORE zeroing altitude (so the departing sprite can hand off the exact position).
- **Error signature**: `onError` receives only an Error and a site string (never event payloads).
- **Reduce Motion**: All branches must stay reachable; test with a Motion setting reduced.
- **Simulator blind**: the native bar's pan and Fabric clipping are simulator-specific; device verification is required before shipping motion changes.
- **Sit is the rest pose**: Never dissolve sit to idle at rest; idle is only for busy and greeting. The seam between the sit sheet's last frame and idle's first frame is not guaranteed for sheets cut from different clips.
- **Sheet metrics**: `sheet-metrics.ts` holds the measured empty rows above each run sheet's drawing (`RUN_HEAD_PAD`); re-measure when a run sheet changes, `sheets.test.ts` fails if it drifts.
- **Route legs**: the around route never changes facing mid-route; the 360deg roll about the feet (`routePivot`) does the turning. Facing is set once, before the exit run.
- **Leak gate**: Run `bun run leak-check` before final PR; the gate must stay green.

## Leak Check

`bun run leak-check` guards against a private identifier landing in the tree. The pattern it checks against is not in the repo - it comes from a maintainer-only `tools/.leak-pattern` file (gitignored) or a `LEAK_PATTERN` secret in CI, so forks and fresh clones never receive it. Without a pattern the check prints a notice that nothing was enforced and exits clean rather than failing. Export `LEAK_CHECK_REQUIRED=1` in your own shell if you want a missing pattern to fail closed instead. In CI, it is enforced with the real pattern on pushes to `main`, on manual runs, and on pull requests from this repository, except Dependabot pull requests, which receive no Actions secrets and therefore skip.

With a pattern configured the check covers tracked files and new files that are not staged yet; ignored files are skipped. A pattern that cannot be searched (a malformed expression, a tree outside its own repository) exits 2: nothing was checked, which is a failure, not a pass.

## Conformance Fixtures

`conformance/*.json` (one file per module: geometry, around, handoff, pose-dissolve) are golden test vectors generated from the TypeScript pure functions in `packages/tabpet/src/{perch-geometry,perch-around,perch-handoff,pose-dissolve}.ts`. Both the TypeScript test suite (`packages/tabpet/src/conformance.test.ts`) and the Swift test suite (`swift/Tests/TabPetCoreTests/GeometryConformanceTests.swift`, `AroundConformanceTests.swift`, `HandoffConformanceTests.swift`, `PoseDissolveConformanceTests.swift` - all four modules) replay the same cases, so the two implementations cannot silently drift apart.

These files are **generated and never hand-edited**. Regenerate with:

```bash
bun run conformance
```

`bun run conformance` also asserts, per function, the output classes its MUST-HIT and sampled cases must together produce (both sides of a boolean, null and non-null, every discriminant value, every leg of a route, and so on). Every module's payload is built first - which runs every one of its assertions - and only once all four have built successfully does the generator write any file, so a coverage regression on the last module cannot leave the first three files freshly overwritten while the fourth goes stale; the whole committed set is left untouched.

`bun run conformance --check` regenerates in memory and fails if any committed file differs from what the generator produces - this runs in CI after the test step, so a stale fixture (e.g. after changing one of the four source modules) fails the build until you regenerate and commit the result. The comparison is structural, not byte-for-byte: the committed files and CI can be generated on different Node/V8 builds, and a value that passes through `Math.sin`, `Math.cos`, `Math.atan2`, or `Math.hypot` can round its last bit differently between them. For `geometry.json`, `handoff.json` and `pose-dissolve.json`, `--check` compares the same cases in the same order with the same function names, compares arguments exactly, compares an `"exact"` case's expected value exactly, and compares a `"tolerance"` case's expected value with the tolerance rule below. `around.json`'s arguments themselves embed a whole route built from those same trig calls (arc lengths, leg boundaries, ellipse centers), so in `--check` only, every float leaf of `around.json` - arguments and expectations alike, for every function in the file - compares with the tolerance rule regardless of that case's own pinned compare mode. On a mismatch it names the first differing case (file, function, index).

`bun run conformance --self-test` proves that tolerance rule actually does something: it bumps an around.json argument float and an expectation float by one ULP in memory and asserts the structural diff still reports none, then bumps a geometry.json expectation by one ULP and asserts a diff IS reported. `bun run check` runs both `--check` and `--self-test`.

Every floating-point number in a fixture, in both arguments and expected values, is wrapped as `{"bits": "<16 hex digits>", "value": <number-or-"NaN"/"Infinity"/"-Infinity"/"-0">}`. `bits` is the authoritative IEEE 754 double bit pattern (JSON numbers cannot carry `-0`, `NaN`, or the infinities, all of which these functions return); `value` is only for human readers. A `bits` string that is not exactly 16 lowercase hex digits is a decode error in both readers, never a silent zero.

Each file also carries a top-level `"constants"` object: every numeric constant its source module exports, wrapped in the same `{bits, value}` format as any case argument or expectation. Both readers check every one of them against their own module's copy of the same constant (bit-identical - these are literal numbers, never a trig result), so a constant drifting out of sync between the TypeScript and the Swift port fails loudly instead of only showing up later as an unrelated case mismatch.

Each case carries a `"compare"` rule, decided per function by whether its result passes through `Math.sin`, `Math.cos`, `Math.atan2`, or `Math.hypot`; the TypeScript reader pins the expected mode per function in a table and fails if a fixture disagrees, and both readers reject any `"compare"` string other than the two below:

- `"exact"` - bit-identical (any NaN equals any NaN).
- `"tolerance"` - if either value is NaN, they match only when both are NaN; else if either value is infinite, they match only when they are equal; else two doubles match when `|a - b| <= 1e-9 * max(1, |a|, |b|)`.

Each Swift test file keeps its own coverage list by hand (`knownGeometryFunctions`, `knownAroundFunctions`, `knownHandoffFunctions`, `knownPoseDissolveFunctions`), since Swift has no runtime export list to diff against. The TypeScript reader (`conformance.test.ts`) is the one that detects a new export with no fixture coverage, by enumerating the module's actual namespace.

## Local consumers

Install from a packed tarball, not a `file:` directory:

```bash
cd packages/tabpet && bun pm pack
# in your app's package.json: "react-native-tabpet": "file:../tabpet/packages/tabpet/react-native-tabpet-0.2.2.tgz"
```

bun materializes `file:` directories as per-file symlinks. Metro follows them out of your project and resolves tabpet's imports against the tabpet workspace's own node_modules - a second Reanimated boots and the app dies at launch with `property is not writable`. The tarball installs real files, which is also exactly what an npm install gives you.

## Adding an animal

1. Create pose-loop clips for idle, run, and sit. The prompts and settings that made the bundled animals are in `docs/art-pipeline.md`. Hand-drawn frames or another generator are fine if they match the geometry contract.
2. Run the sprite-sheet pipeline for each: `tools/sprite-sheet.sh -i video.mp4 -o sheet.png --frames N --cols C`.
3. Add the three PNGs to `packages/tabpet/assets/`.
4. Measure the run sheet's empty rows above the drawing and add its `RUN_HEAD_PAD` entry in `packages/tabpet/src/sheet-metrics.ts`.
5. Add the animal to `packages/tabpet/src/sheets.test.ts` - add the new ID to the ANIMALS list.
6. Create the profile in `packages/tabpet/src/animals/<id>.ts` and register it in `packages/tabpet/src/animals/all.ts` to ship it with the library (or register it at runtime in your own app instead).

See `docs/profiles.md` for the profile contract and `docs/art-pipeline.md` for geometry details (idle/sit: 5x5, 12 fps; run: 4xN, per-species fps).
