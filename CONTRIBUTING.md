# Contributing

## Setup

- Bun 1.3 or later (Node 25+ LTS compatible)
- `bun install` from the repo root
- `bun run check` runs leak-check, typecheck, fmt:check, lint, and test
- `bun run test` runs every `*.test.ts` under tsx via `node scripts/run-tests.mjs`

## Repo Layout

- `packages/tabpet/src/` - the library (TypeScript, ESM)
- `apps/example/` - demo app using the library
- `packages/tabpet/ios/` - the Swift module (UITabBar pan events and bar layout); `packages/tabpet/src/native/` wraps it
- `tools/sprite-sheet.sh` - sprite-sheet slicing pipeline (`--from/--to` window, `--flip`)
- `assets/` - sprite sheets for the six shipped animals (PNG)

## Tests

Pure unit tests use `node:assert` (no external framework). Run via `bun run test`, which invokes `tsx` on Node (not `bun test`).

Current test suites:

- `companion-state.test.ts` - state machine tests
- `perch-geometry.test.ts` - slot/center/lift calculations
- `perch-reentry.test.ts` - late-arrive generation gate
- `sheets.test.ts` - sprite-sheet geometry contract (add new animals to the ANIMALS list here)

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

## Local consumers

Install from a packed tarball, not a `file:` directory:

```bash
cd packages/tabpet && bun pm pack
# in your app's package.json: "react-native-tabpet": "file:../tabpet/packages/tabpet/react-native-tabpet-0.2.0.tgz"
```

bun materializes `file:` directories as per-file symlinks. Metro follows them out of your project and resolves tabpet's imports against the tabpet workspace's own node_modules - a second Reanimated boots and the app dies at launch with `property is not writable`. The tarball installs real files, which is also exactly what an npm install gives you.

## Adding an animal

1. Create pose-loop clips for idle, run, and sit. The prompts and settings that made the bundled animals are in `docs/art-pipeline.md`. Hand-drawn frames or another generator are fine if they match the geometry contract.
2. Run the sprite-sheet pipeline for each: `tools/sprite-sheet.sh -i video.mp4 -o sheet.png --frames N --cols C`.
3. Add the three PNGs to `packages/tabpet/assets/`.
4. Add the animal to `packages/tabpet/src/sheets.test.ts` - add the new ID to the ANIMALS list.
5. Register the profile in your app (or in `src/registry.ts` to ship it with the library).

See `docs/profiles.md` for the profile contract and `docs/art-pipeline.md` for geometry details (idle/sit: 5x5, 12 fps; run: 4xN, per-species fps).
