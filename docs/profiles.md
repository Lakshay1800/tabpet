# Profile reference

Every animal is a `CompanionProfile` with these fields:

| field | type | default | meaning |
| --- | --- | --- | --- |
| `id` | `string` | required | unique identifier |
| `label` | `string` | required | lowercase noun, fits "Your companion {label}" accessibility sentences |
| `sheets` | `{ idle, run, sit }` | required | static requires of 240px-cell PNGs |
| `runFps` | `number` | required | frames per second for the run animation |
| `commitSpring` | `SpringConfig` | required | `{ duration, dampingRatio }` for tab-change run |
| `trackSpring` | `SpringConfig` | required | `{ duration, dampingRatio }` for finger chase |
| `catchSpring` | `SpringConfig` | required | `{ duration, dampingRatio }` for release to seat |
| `hopHeight` | `number` | required | peak in pt, negative = up; 0 = never hops |
| `flightLift` | `number` | required | pt lifted off bar while running; 0 = stays grounded |
| `scale` | `number` | required | render multiplier about the cell center; 1 = reference size. The perch seats a scaled sprite by its scaled paw line, so pass the cell-measured `footPad` unchanged |
| `aroundRoute` | `boolean` | required | first-slot to last-slot taps take the long way round the pill; ignored when `flightLift` > 0, on bars without a pill, with fewer than 3 slots, or under Reduce Motion |
| `headPad` | `number` | per-animal | empty pt above run-cell drawing at reference size (see `RUN_HEAD_PAD` per animal) |
| `footPad` | `number` | 11 | empty pt between drawing's ground contact and sit-cell bottom at reference size; animals drawn without a ground shadow carry less air under the feet |
| `seatLift` | `number` | 6 | pt ground contact sits above the measured bar top; 6 suits a classic bar (its "top" is the icons' edge), but on the iOS 26 pill the measured top is the glass rim so a companion sitting on it sets this near 0 |
| `runSpeed` | `number` | 340 pt/s | ground speed for the tab-tap run leg; duration clamps stretch with it so slow animals stay slow on one-slot hops |
| `sitSheet` | `SheetGeometry` | `{ cols: 5, rows: 5, frames: 25, fps: 12 }` | sit sheet grid and playback rate; a 24fps source cut 1:1 uses `{ cols: 10, rows: 5, frames: 50, fps: 24 }` |

## Built-in animals

| animal | id | runFps | hopHeight | flightLift | scale | aroundRoute | footPad | headPad | commitSpring | trackSpring | catchSpring | runSpeed |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Panda | `panda` | 18 | -6 | 0 | 1 | false | 3.6 | 2 | 560/0.86 | 300/0.9 | 260/0.9 | 340 |
| Cat | `cat` | 24 | -8 | 0 | 1 | false | 6.5 | 12 | 380/0.8 | 240/0.86 | 260/0.9 | 340 |
| Turtle | `turtle` | 12 | 0 | 0 | 1 | false | 6.5 | 24 | 1050/1 | 700/1 | 600/1 | 200 |
| Raccoon | `raccoon` | 24 | -8 | 0 | 0.72 | true | 11 | 21 | 430/0.82 | 240/0.86 | 260/0.9 | 340 |
| Bird | `bird` | 24 | 0 | 14 | 1 | false | 7.5 | 19 | 380/0.75 | 220/0.8 | 260/0.9 | 340 |
| Squirrel | `squirrel` | 24 | -14 | 0 | 0.85 | true | 11 | 9 | 400/0.78 | 220/0.82 | 240/0.9 | 340 |

Spring values are `duration/dampingRatio`. `seatLift` is the default 6 for every built-in except the panda, which sets 2 and sits on the rim (a painted ground shadow would otherwise do the grounding; see the art pipeline). The default `sitSheet` (5x5x25 @ 12fps) applies to all. Idle and run grids are fixed: idle 5x5 25 frames at 12 fps; run 4x3 11 frames used (12th cell unused) at the per-animal `runFps`.

## Measuring a new sheet

See `./art-pipeline.md` for the generation prompts, sprite-sheet cutting recipe, and how to measure `headPad` and `footPad`.
