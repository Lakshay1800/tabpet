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

## Local consumers

Install from a packed tarball, not a `file:` directory:

```bash
cd packages/tabpet && bun pm pack
# in your app's package.json: "react-native-tabpet": "file:../tabpet/packages/tabpet/react-native-tabpet-0.2.1.tgz"
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
