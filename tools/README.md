# tools

Generation prompts, cut recipes and profile measurement live in [docs/art-pipeline.md](../docs/art-pipeline.md). This directory holds the scripts.

## sprite-sheet.sh

Slices a pose-loop video (a short clip of the character on a plain background, from any video generator or hand-drawn frames) into a companion sprite sheet: even frame sampling, center square crop, corner-floodfill background keying, and a transparent-background grid montage.

### Prerequisites

- `ffmpeg` / `ffprobe`
- ImageMagick 7 (`magick` on PATH)

### Geometry contract

Every sheet uses 240px square cells. Grid shape and playback rate must match what `registerCompanion` declares for that pose:

- `idle` / `sit`: 5x5 grid, 25 frames, 12 fps
- `run`: 4x3 grid, 11 populated frames (12th cell unused), fps is per-species

### Example invocations

```bash
tools/sprite-sheet.sh -i otter-idle.mp4 -o otter-idle.png
tools/sprite-sheet.sh -i otter-run.mp4 -o otter-run.png --frames 12 --cols 4
# sample one gait period (source frames 18-35) so the 11 used cells loop cleanly
tools/sprite-sheet.sh -i otter-run.mp4 -o otter-run.png --frames 12 --cols 4 --from 18 --to 35
# a sit one-shot: from the first fully-in-frame frame to just past the settle
tools/sprite-sheet.sh -i otter-sit.mp4 -o otter-sit.png --from 28 --to 100
# mirror every frame (an idle drawn with the tail on the wrong side)
tools/sprite-sheet.sh -i otter-idle.mp4 -o otter-idle.png --flip --fuzz 14
# center a body the tail pushed left (120 source px right) and dissolve the
# tail where the clip cut it at the frame's left edge
tools/sprite-sheet.sh -i fox-sit.mp4 -o fox-sit.png --shift 120:0 --fade-edge 24 --fade-sides left
# align a run baseline 45 source px lower without an ffmpeg pad step
tools/sprite-sheet.sh -i fox-run.mp4 -o fox-run.png --frames 12 --cols 4 --from 104 --to 128 --shift 0:45
# one video for all three sheets: the run segment travels across the frame,
# --track re-centers every frame on the body so the stride still loops
tools/sprite-sheet.sh -i cat-single.mp4 -o cat-run.png --frames 12 --cols 4 --from 8 --to 33 --track
tools/sprite-sheet.sh -i cat-single.mp4 -o cat-sit.png --from 96 --to 170
tools/sprite-sheet.sh -i cat-single.mp4 -o cat-idle.png --from 171 --to 230
```

`--from/--to` are 1-based source frames; sampling inside the window is loop-style (the sample after the last would land on `--to` + 1), so a window of exactly one gait period never repeats a frame. Find the period by comparing each frame to the first (`magick a.png b.png -metric RMSE -compare -format %[distortion] info:`) and reading off the minima; a sit settles where the distance to the last frame drops under ~0.02. Raise `--fuzz` to 12-14 when the generator leaves a soft shadow under the character. If two clips draw the character at different sizes, pre-scale one with ffmpeg (`scale`, `pad`, `crop`) so the feet share a baseline before slicing; the perch assumes the feet sit about 11px above the cell bottom at 54pt. `--shift X:Y` moves the drawing X source px right and Y down (white pad, cropped back) for the plain offset cases: a body the tail pushed off-center, a run drawn on a higher baseline. `--fade-edge N` ramps the alpha over N cell px on each source edge the drawing runs off (a tail the generator cut at the frame), so the cut dissolves instead of ending in a line; `--fade-sides left,top` limits it, the default is left, right and top, and the bottom is never faded. `--track` re-centers each sampled frame horizontally on the character's body (center of mass of the keyed lower half, median-smoothed over five frames, white-padded past the frame edge); use it for a run segment where the character travels instead of running in place. The crop keeps its size and vertical position, so `--shift` does not apply with `--track`.

### Registering the result

Sheets are static `require()`s - Metro needs literal paths. Add the PNGs to `packages/tabpet/assets/`, then register a profile:

```ts
import { registerCompanion } from 'tabpet';

registerCompanion({
  id: 'otter',
  label: 'otter',
  sheets: {
    idle: require('../assets/otter-idle-sprite.png'),
    run: require('../assets/otter-run-sprite.png'),
    sit: require('../assets/otter-sit-sprite.png'),
  },
  runFps: 24,
  commitSpring: { duration: 430, dampingRatio: 0.82 },
  trackSpring: { duration: 240, dampingRatio: 0.86 },
  catchSpring: { duration: 260, dampingRatio: 0.9 },
  hopHeight: -8,
  flightLift: 0,
  scale: 1,
});
```

## deshadow.sh

Removes a keyed-but-opaque painted ground shadow from a finished sheet (see the art pipeline's "Removing a painted ground shadow"). ImageMagick 7 only.

```bash
tools/deshadow.sh panda-sit-sprite.png panda-sit-clean.png            # 240px cells, band from row 180, disk 14
tools/deshadow.sh otter-run-sprite.png otter-run-clean.png 240 190 11 # tighter band, smaller opening for a leaner animal
```

## frame-stack.sh

Drives a Maestro flow against a booted simulator while recording, then cuts the recording into frames and a contact sheet. This is how motion changes get verified: not screenshots, a frame stack.

### Prerequisites

- `xcrun`, `maestro`
- `ffmpeg` / `ffprobe`
- ImageMagick 7 (`magick` on PATH)

### Finding a UDID

```bash
xcrun simctl list devices booted
```

### Two lessons this script encodes

- **Never use `booted`.** `simctl io booted` is ambiguous the moment two simulators are booted at once - it can capture a device Maestro never touched, and the run still looks fine (it produces a video). Always pass the same UDID to both `simctl` and `maestro`, which is why `--udid` is required and the script refuses to run without it.
- **Bound the recorder.** `xcrun simctl io <UDID> recordVideo` holds a host-wide recording lock for the life of the process. A recorder that never gets a clean SIGINT (killed with `-9`, an interrupted shell) leaves the lock held: the next run fails with "Host recording is already in progress" and the mp4 write itself can fail EBUSY. The script always sends SIGINT and waits for the file to stop growing, and traps EXIT/INT/TERM so a leaked recorder is the exception, not the rule.

### Example invocations

```bash
UDID=$(xcrun simctl list devices booted | grep -o '[0-9A-F-]\{36\}' | head -1)

tools/frame-stack.sh --udid "$UDID" \
  --flow apps/example/maestro/around.yaml \
  --out out/around

tools/frame-stack.sh --udid "$UDID" \
  --flow apps/example/maestro/drag.yaml \
  --out out/drag --crop-bottom 0.25 --fps 24 --sheet-cols 10 --every 2
```

Note: Maestro's synthetic `swipe` does not drive the UITabBar's built-in scrub gesture. A frame stack from a Maestro swipe proves tap/drag behavior the app itself owns, not a real finger dragging the bar - proving that needs a finger, or a device-recorded touch input as the driver.

## pill-geometry.sh

Measures, per frame, the floating pill's top rim row and left/right edge columns from a frame stack, and prints `frame,top,left,right` CSV. Used to prove exclusivity claims like "the pill did not move during this gesture" (`range 0`).

### Example invocations

```bash
tools/pill-geometry.sh out/around/frames
tools/pill-geometry.sh out/drag/frames --x 200 --bg-threshold 220
```

### Limits

Light-background frames only. Pass `--x` at a column with only glass/background beneath it - a companion or a dark screen element under the sample column will fool the rim scan into reporting its own edge instead of the pill's.

## Verifying motion

1. Build Release and install on the simulator:
   ```bash
   cd apps/example && npx expo run:ios --configuration Release --device <UDID>
   ```
2. Record and cut the flow:
   ```bash
   tools/frame-stack.sh --udid <UDID> --flow apps/example/maestro/around.yaml --out out/around
   ```
3. Read `out/around/sheet.png` by eye for the gross motion, then measure precisely: a seat check compares the companion's feet (lowest opaque row in a frame) against the pill's top rim, from `pill-geometry.sh`.
