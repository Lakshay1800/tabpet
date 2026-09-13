# Art pipeline

An animal is three short video clips (run, sit, idle) rendered on a plain background, sliced into sprite sheets with `sprite-sheet.sh`, and registered with a profile. Two generators were used: Higgsfield (seedance 2.0 / 2.5 with an existing finished sprite sheet as a style reference) for panda, cat, turtle, raccoon, and bird; Grok Imagine (still first, then image-to-video from the still, no reference input) for squirrel and housecat.

## Clip geometry and settings

All clips: 5-6 seconds, 1:1 aspect (16:9 crops the character), no audio, locked camera with no pan or zoom. Three poses on plain background:

- **Run**: the character moves in place like a game sprite, perfectly loopable
- **Sit**: one smooth non-looping action from the start position to a settled front-facing sit held in the last frame
- **Idle**: seeded from the sit clip's LAST frame (not the still), so the sit-to-idle handoff has no visible pop; a looping perky greeting or fidget

## Prompt patterns that held for every clip

- Run in place, perfectly loopable, like a game sprite
- Sit is ONE smooth non-looping action ending front-facing with a 1-second hold
- Idle seeded from the sit's last frame so there is no pop at the handoff
- Species lock lines in caps ("IMPORTANT: absolutely NOT a dog"), and name what it is NOT
- Moods content or proud only; a sad companion is a companion nobody picks
- "Use the reference image ONLY for the painting style, never for the species"

## Higgsfield animals (seedance 2.0)

All reference-seeded from an existing finished sprite sheet, which carries the painting style (warm storybook gouache, soft painted edges, oversized head, plush painterly texture) across species. When a species bled through from the reference (e.g., a kitten rendered as the reference animal), the fix was a species lock in caps plus the phrase "use the reference image ONLY for the painting style, never for the species."

### Panda

**Run:**

2D character animation in the exact warm storybook gouache illustration style of the reference sprite sheet: soft painted edges, warm cozy palette, oversized head, plush painterly texture. A chubby baby panda bouncing in a joyful run cycle, round body jiggling, short legs churning. Side view, facing right, running in place like a game sprite, perfectly loopable cycle, static locked-off camera, plain pure white background, full body always in frame, no shadow under the character, no text, no watermark.

**Sit:**

2D character animation in the exact warm storybook gouache illustration style of the reference sprite sheet. The same chubby baby panda: bouncing in from the left, stops, plops down into a sit and turns to face the camera, ending in a calm front-facing sit. One smooth non-looping action, static locked-off camera, plain pure white background, full body in frame, no shadow, no text, no watermark.

**Idle:**

2D character animation in the exact warm storybook gouache illustration style of the reference sprite sheet. The same chubby baby panda, sitting upright FACING THE CAMERA, happy greeting loop: round belly bounce, head tilt, one paw lifts in a little wave, then settles back to a calm sit. Perfectly loopable, static locked-off camera, plain pure white background, full body in frame, no shadow, no text, no watermark.

### Cat

**Run:**

2D character animation in the exact warm storybook gouache illustration style of the reference sprite sheet: soft painted edges, warm cozy palette, oversized head, plush painterly texture. A fluffy cream-and-ginger kitten bounding in a happy gallop run cycle. Side view, facing right, running in place like a game sprite, perfectly loopable cycle, static locked-off camera, plain pure white background, full body always in frame, no shadow under the character, no text, no watermark.

**Sit:**

2D character animation. IMPORTANT: the character is a fluffy cream-and-ginger tabby KITTEN, a cat, absolutely NOT a dog - use the reference image ONLY for the painting style (warm storybook gouache, soft edges, oversized head), never for the species. The kitten trots in from the left, stops, sits down and turns to face the camera, ending in a calm front-facing sit with tail curled. One smooth non-looping action, static locked-off camera, plain pure white background, full body in frame, no shadow, no text, no watermark.

**Idle:**

2D character animation in the exact warm storybook gouache illustration style of the reference sprite sheet. The same fluffy cream-and-ginger kitten, sitting upright FACING THE CAMERA, happy greeting loop: tail swish, small head tilt, one front paw lifts in a little wave, then settles back to a calm sit. Perfectly loopable, static locked-off camera, plain pure white background, full body in frame, no shadow, no text, no watermark.

### Turtle

**Walk:**

2D character animation in the exact warm storybook gouache illustration style of the reference sprite sheet: soft painted edges, warm cozy palette, oversized head, plush painterly texture. A small cheerful green turtle with a warm brown shell waddling forward in a SLOW determined walk cycle, stubby legs paddling, head gently bobbing. Side view, facing right, walking in place like a game sprite, perfectly loopable cycle, static locked-off camera, plain pure white background, full body always in frame, no shadow under the character, no text, no watermark.

**Sit:**

2D character animation in the exact warm storybook gouache illustration style of the reference sprite sheet. A small cheerful green turtle with a WARM BROWN shell (rich warm brown like aged leather, NOT green or teal): waddling slowly in from the left, stops, settles down onto its belly and turns its head to face the camera, ending calm and front-facing. One smooth non-looping action, static locked-off camera, plain pure white background, full body in frame, no shadow, no text, no watermark.

**Idle:**

2D character animation in the exact warm storybook gouache illustration style of the reference sprite sheet. The same small cheerful green turtle, sitting FACING THE CAMERA, gentle greeting loop: slow blink, small head bob, tiny front flipper wave, then settles calm. Perfectly loopable, static locked-off camera, plain pure white background, full body in frame, no shadow, no text, no watermark.

### Raccoon

**Run:**

2D character animation in the exact warm storybook gouache illustration style of the reference sprite sheet. A cute fluffy WARM BROWN raccoon kit (warm tan-brown fur like the reference animal's palette, NOT grey or cool-toned) with a striped bushy tail and dark eye mask, scampering in a quick run cycle, tail streaming behind, tiny paws churning. Side view, facing right, running in place like a game sprite, perfectly loopable cycle, static locked-off camera, plain pure white background, full body always in frame, no shadow, no text, no watermark.

**Sit:**

2D character animation. IMPORTANT: the character is a cute fluffy warm-brown RACCOON kit with a striped bushy tail and dark eye mask, absolutely NOT a dog - use the reference image ONLY for the painting style (warm storybook gouache, soft edges, oversized head), never for the species. The raccoon scampers in from the left, skids to a stop, sits down and turns to face the camera with tail curled around, ending in a calm front-facing sit. One smooth non-looping action, static locked-off camera, plain pure white background, full body in frame, no shadow, no text, no watermark.

**Idle:**

2D character animation in the exact warm storybook gouache illustration style of the reference sprite sheet. The same cute fluffy raccoon kit with striped bushy tail, sitting upright FACING THE CAMERA, mischievous greeting loop: head tilt, tiny paws rub together, one paw waves, tail curls, then settles back to a calm sit. Perfectly loopable, static locked-off camera, plain pure white background, full body in frame, no shadow, no text, no watermark.

### Bird

**Fly:**

2D character animation in the exact warm storybook gouache illustration style of the reference sprite sheet: soft painted edges, warm cozy palette, oversized head, plush painterly texture. A tiny round songbird FLYING in place, smooth wing flap cycle, gentle body bob while hovering, feet tucked up, never touching the ground. Side view, facing right, hovering like a game sprite, perfectly loopable cycle, static locked-off camera, plain pure white background, full body always in frame, no shadow under the character, no text, no watermark.

**Sit:**

2D character animation in the exact warm storybook gouache illustration style of the reference sprite sheet. A tiny ROUND ROBIN songbird with a bright ORANGE breast and warm brown wings (exactly like a European robin): flying in from the left, brakes mid-air with spread wings, lands softly, folds its wings and settles facing the camera. One smooth non-looping action, static locked-off camera, plain pure white background, full body in frame, no shadow, no text, no watermark.

**Idle:**

2D character animation in the exact warm storybook gouache illustration style of the reference sprite sheet. The same tiny round songbird, perched FACING THE CAMERA, cheerful greeting loop: feathers fluff up, a little hop, quick wing flutter, head tilt, then settles calm. Perfectly loopable, static locked-off camera, plain pure white background, full body in frame, no shadow, no text, no watermark.

## Grok Imagine animals (no reference input)

Grok has no sprite-sheet reference mode. Carry the style in words: generate a still, then image-to-video from that still. That avoids species bleed. Do not rewrite prompts for a new animal; the pose language for one species produces wrong postures on another. Idle seeded from the sit clip's last frame, same as Higgsfield.

### Squirrel

#### Reference stills (text-to-image, 1:1)

**Front sit** (seeds the idle loop after the sit clip exists):

Cute chubby baby red squirrel character, rust-orange fur with a cream belly, tufted ears, huge fluffy bushy tail curled up behind its back, tiny paws held together at the chest, big dark shiny eyes. Warm storybook gouache illustration: soft painted edges, plush painterly texture, oversized head, warm cozy palette. Sitting upright facing the camera, whole body and full tail inside the frame with generous margin. Plain pure white background, no shadow, no ground line, no text, no watermark.

**Side profile** (seeds run and the sit one-shot):

IMPORTANT: a RED squirrel, NOT a chipmunk, no stripes. Same chubby baby red squirrel, rust-orange fur, cream belly, tufted ears, huge fluffy bushy tail, warm storybook gouache style. Full body side profile facing RIGHT, standing on all fours, alert and ready to dash, bushy tail arched up over its back. Whole squirrel and tail fully in frame with margin on all sides. Plain pure white background, no shadow, no ground, no other elements, no text.

#### Run loop (image-to-video from the side still)

IMPORTANT: a RED squirrel, NOT a chipmunk, no stripes. Static locked-off camera, no pan, no zoom, running in place. 2D character animation of this exact squirrel, identical design and painting style. Scampering in a quick bounding run cycle, back arched, tiny paws churning, bushy tail flowing and bouncing behind. Side view, facing right, perfectly loopable. Plain pure white background, full body and tail always in frame, no shadow, no text, no watermark.

#### Sit one-shot (image-to-video from the side still)

IMPORTANT: a RED squirrel, NOT a chipmunk, no stripes. Static locked-off camera, no pan, no zoom, no jump cuts. 2D character animation of this exact squirrel, identical design and painting style. Continuous motion, no snap: scampers in from the left, skids to a stop, sits up on its haunches, and turns to face the camera in one unbroken action. Paws tuck to the chest, tail curls up behind, ending in a calm front-facing sit. Hold that sit for the last second. Plain pure white background, full body and tail always in frame, no shadow, no text, no watermark.

#### Idle loop (image-to-video from the sit clip LAST frame, not the still)

Seeding idle from the sit clip's last frame is the trick that made the seam invisible. Seeding from the still gives a visible pop.

IMPORTANT: a RED squirrel, NOT a chipmunk, no stripes. 2D character animation of this exact squirrel, identical design and painting style. Sitting upright FACING THE CAMERA, perky greeting loop: nose twitch, quick head tilt, tail flicks once, paws rub together, then settles back to exactly the starting pose. Perfectly loopable, static locked-off camera, plain pure white background, full body in frame, no shadow, no text, no watermark.

### Housecat

Do not reuse squirrel pose language for a cat. The squirrel stills ask for oversized head, stubby paws, and "tiny paws held together at the chest"; those lines produce a squirrel-beg sit and chibi proportions on a cat.

#### Reference stills (text-to-image, 1:1)

**Front sit** (seeds the idle loop after the sit clip exists):

IMPORTANT: a HOUSECAT, not a squirrel, not a chipmunk. Cute housecat character sitting the way a real cat sits: haunches down, both front paws planted firmly on the ground directly under the shoulders. NOT paws held together at the chest, NOT begging, NOT a squirrel sit. Natural cute proportions: head only slightly large, legs with real length, not stubby chibi limbs. Warm storybook gouache illustration: soft painted edges, plush painterly texture, clean dark outlines. Front-facing sit, whole body and full tail inside the frame with generous margin. Plain pure white background, no shadow, no ground line, no text, no watermark.

**Side profile** (seeds run and the sit one-shot):

IMPORTANT: a HOUSECAT, not a squirrel, not a chipmunk. Same housecat, warm storybook gouache style. Natural cute proportions, head only slightly large, full-length legs visible, not stubby. Full body side profile facing RIGHT, standing on all fours, alert and ready to dash, tail arched up over its back. Whole cat and tail fully in frame with margin on all sides. Match the front-sit frame fill. Plain pure white background, no shadow, no ground, no other elements, no text.

#### Run loop (image-to-video from the side still)

IMPORTANT: a HOUSECAT, not a squirrel, not a chipmunk. Static locked-off camera, no pan, no zoom, running in place. 2D character animation of this exact housecat, identical design and painting style. Cat run cycle: a real housecat gallop, full-length legs reaching, tail flowing and bouncing behind. Side view, facing right, perfectly loopable. Plain pure white background, full body and tail always in frame, no shadow, no text, no watermark.

#### Sit one-shot (image-to-video from the side still)

IMPORTANT: a HOUSECAT, not a squirrel, not a chipmunk. Static locked-off camera, no pan, no zoom, no jump cuts. 2D character animation of this exact housecat, identical design and painting style. Continuous motion, no snap: runs in from the left, skids to a stop, sits like a real housecat with both front paws planted on the ground under the shoulders, and turns to face the camera in one unbroken action. Do NOT end with paws at the chest. Do NOT sit like a squirrel or beg. Tail settles behind or to the side, ending in a calm front-facing housecat sit. Hold that sit for the last second. Plain pure white background, full body and tail always in frame, no shadow, no text, no watermark.

#### Idle loop (image-to-video from the sit clip LAST frame, not the still)

Same seam trick as squirrel: seed idle from the sit clip's last frame.

IMPORTANT: a HOUSECAT, not a squirrel, not a chipmunk. 2D character animation of this exact housecat, identical design and painting style. Sitting like a real housecat FACING THE CAMERA, front paws planted on the ground, natural cat sit greeting loop: ear flick, quick head tilt, tail flicks once, then settles back to exactly the starting pose. No paw rub. No paws lifting to the chest. Perfectly loopable, static locked-off camera, plain pure white background, full body in frame, no shadow, no text, no watermark.

#### Housecat anti-patterns

- No oversized chibi head. Keep the head only slightly large.
- No stubby legs. Show real length on the front and back legs.
- No squirrel beg sit. Paws stay planted on the ground under the shoulders, never clasped at the chest.
- Keep size consistent across stills. Front sit and side profile should fill the frame about the same.

## One video per animal

Three clips per animal means three chances for the style to drift and a seam the idle has to be seeded across. One longer clip with the segments in order cuts into all three sheets, and the sit-to-idle seam is exact because both come from the same frames. The prompt has to say the segments in order and give the run its own seconds; a clip that opens seated and walks off does not loop (the cat's first single clip: the walk-in accelerates out of the seed pose and turns to camera within 19 frames, no RMSE minimum). Ask for 10-12 seconds:

```
Static locked-off camera, no pan, no zoom, plain pure white background, no shadow, no text, no watermark. 2D character animation of this exact <animal>, identical design and painting style. One continuous shot in four parts. First, for four full seconds it runs in place in a perfectly loopable cycle, side view facing right, staying in the center of the frame. Then it slows, stops, sits down and turns to face the camera in one smooth motion. Then a small greeting that returns to exactly the seated pose: slow blink, ear flick, tail tip flicks once. Then it holds perfectly still for the last two seconds. Whole body and full tail inside the frame with generous margin at all times, nothing touching the edges.
```

This four-part structure produced a usable 10 s clip in Grok Imagine, Sora and Seedance, pasted with a seed still of the character. Paste order matters: species lock, camera, the four parts, the sit constraints, the character description last. The raccoon, built from the bundled raccoon's description (the same words as its three-clip prompts above; swap the species lock and the last two sentences for your own animal and keep everything between them word for word):

```
IMPORTANT: a RACCOON, not a dog, not a cat. Static locked-off camera, no pan, no zoom, no jump cuts. 2D character animation of this exact raccoon kit, identical design and painting style. One continuous shot in four parts, continuous motion, no snap. Part one, the first four seconds: a quick raccoon scamper RUNNING IN PLACE, tiny paws churning, striped bushy tail streaming behind, side view facing right, staying in the center of the frame, perfectly loopable. Part two: it slows, skids to a stop, sits down with both front paws planted under the shoulders, and turns to face the camera in one unbroken action, tail curling around to the side. Part three: a mischievous greeting that returns to exactly the seated pose: head tilt, slow blink, one paw lifts in a small wave and comes back down, tail tip flicks once. No paws lifting to the chest. Part four: holds that sit perfectly still for the last two seconds. Plain pure white background, whole body and full tail inside the frame with generous margin at all times, nothing touching the edges, no shadow, no text, no watermark. Cute fluffy warm tan-brown raccoon kit with a striped bushy tail and a dark eye mask, warm storybook gouache illustration style with soft painted edges, an oversized head and plush painterly texture, full-length legs.
```

Cut it as three windows of the same file. Run: `--track` (the character drifts even when told to run in place), then find the stride period with the RMSE-vs-first-frame minima inside the run seconds and take 12/11 of one period. Sit: from the stride's last step to the settle. Idle: the greeting as a ping-pong (`select` + `reverse` + `concat` into a lossless mkv, then `--from 1 --to N`) when it does not close on its own, or the hold when it does; the sit's last cell and the idle's first cell are then the same source frame.

## Cutting sheets

Use `tools/sprite-sheet.sh` to slice pose-loop videos into sprite sheets. See [`tools/README.md`](../tools/README.md) for full flags and geometry rules.

**Geometry contract:** Every sheet uses 240px square cells. Grid shape and playback rate must match what `registerCompanion` declares:

- `idle` / `sit`: 5x5 grid, 25 frames, 12 fps
- `run`: 4x3 grid, 11 populated frames (12th unused), fps is per-species
- A 24fps sit source can be cut 1:1 instead (`--frames 50 --cols 10`) and declared with `sitSheet: { cols: 10, rows: 5, frames: 50, fps: 24 }`, which plays the settle without skipping every other frame. Idle and run grids are fixed.

**Finding a gait period:** For a run loop, compare each frame to frame 1 using `magick` RMSE (read the command in `tools/README.md`). The minima show the loop closure points; use a window of exactly one period so the 11 used cells loop cleanly. Example: if RMSE minima are at frames 18/34/50, the period is 16 frames, so `--from 18 --to 35` samples 12 frames of that period and uses 11 (the 12th cell is unused).

**Settling a sit:** A sit settles where the RMSE distance to the last frame drops under about 0.02. Cut to just past that frame.

**Checking the front of the sit clip:** The perch plays the whole sit sheet on every arrival and at launch. If a sit clip walks in for 70 frames before sitting, the companion will run in place for that whole section on arrival. Check the FRONT of the clip before cutting and start the cut at the stride's last step, so arrival reads stop, turn, sit. The housecat sit was recut from frames 72-123 of 145 for exactly this reason; the first cut (1-125) front-loaded about 70 frames of treading and the cat jogged in place on every arrival.

**Idle seam:** The sit's last cell must equal the idle's first cell, RMSE 0. When the generator hands back a re-export of the sit as the idle (it happens), cut the idle from the sit clip's settled tail instead, for example `--from 121 --to 145`. Find an idle's loop closure the same way as a gait period: the frame with the lowest RMSE against frame 1 near the end of the clip.

**Keying:** `--fuzz 8` by default. Raise it to 10-14 when the generator leaves a soft shadow under the character (Grok does). Check what it eats: 14 removed a nebula tail's wisps that 10 kept.

**Flipping:** `--flip` when a clip is drawn mirrored, for example an idle with the tail on the other side from the sit.

**Pre-scaling and padding:** When clips draw the character at different sizes, pre-scale one with ffmpeg (`scale`, `pad`, `crop`) so the feet share a baseline. The perch assumes the feet sit about 11px above the cell bottom at 54pt. Cells should match within 2px after cutting. Two real cases from the squirrel: its run clip drew the character 10% smaller with a higher baseline, fixed with `ffmpeg -vf "scale=1056:1056,pad=1056:1096:0:40:white,crop=960:960:50:20"` before slicing; its idle was mirrored and 13% larger, fixed with `ffmpeg -vf "hflip,scale=851:851,pad=960:960:88:57:white"`.

**Run-off at the frame edge:** Generators crop long tails. The comet fox's nebula tail hit the left edge of every run frame and the top of the sit-down frames, and its nose the right edge of a few run frames; nothing in the cut can draw the missing pixels. Ask for it in the prompt ("whole body and full tail inside the frame with generous margin on all sides, nothing touching the edges") and regenerate when it still clips. Until then, `--fade-edge 24` ramps the alpha over 24 cell px on each source edge the drawing runs off, so a tail dissolves instead of ending in a line; keep `--fade-sides left` (or `left,top`) when a nose also runs off the right edge, a dissolving face looks broken where a cropped one only looks cropped. `--shift 120:0` moves the drawing right in source px (white pad, cropped back) to center a body its tail pushed to one side, and `--shift 0:45` is the baseline pad from the previous paragraph without the ffmpeg step; the fade ramps start where the source edge landed, not at the cell edge.

**Measuring paw and head lines:** `-trim` reports nonsense when the drawing touches a cell edge (the corner pixel becomes the trim color). Collapse the alpha to one column instead: `magick cell.png -alpha extract -threshold 50% -scale 1x240! -threshold 0 -format '%@' info:` gives the top and bottom rows of the drawing; `240x1!` gives the sides.

## Removing a painted ground shadow

Generators paint a soft shadow under the character even when the prompt says not to. Corner keying removes its light fringe and leaves a near-opaque puddle beside the feet that reads as a blob on the glass. `tools/deshadow.sh <in.png> <out.png> [cell=240] [band=180] [disk=14]` cuts it: a pixel goes when it is opaque, light (HSL lightness 0.25 to 1.0), in the bottom rows of its cell, thinner than the opening disk (the body survives a morphological opening, a sliver does not), and not within 1.5px of dark drawing, so paw outlines keep their anti-aliased edge; the mask is dilated 2px and feathered before it is subtracted, and alpha islands under 30px are dropped. Check the result the same way as a cut: render a few cells over a mid-gray, and compare the per-cell opaque pixel counts before and after (a seated cell loses the puddle, a few hundred pixels; a cell without a shadow should lose almost nothing). A dark shadow core fused to a paw can survive the opening; at 54pt it is under 2pt and the alternative is a regenerated clip. Re-measure `footPad` afterwards: the shadow's bottom row was doing the grounding. The opening disk is sized for chunky gouache animals; a slender character's pale legs are thinner than it and get eaten with the shadow (the comet fox's run cells lost 30 rows of leg, its sit-down cells 700-1600 px each). Compare a run cell's bottom row before and after; if it moves, skip the tool: a one-row shadow strip is under a third of a point at bar scale.

## Measuring the profile numbers

Every field is documented in the [profile reference](./profiles.md). Three of them are measured from the art.

**`footPad`:** Empty rows under the paws in a cell divided by (cell px / 54). For each sheet, use ImageMagick to find the lowest opaque row in a cell:

```bash
magick sheet.png -crop 240x240+X+Y +repage -alpha extract -threshold 10% -format %@ info:
```

The trim box gives the lowest opaque row. Every sheet of one animal must share the paw line. An alpha threshold cannot separate a painted ground shadow from the feet (the shadow is near-opaque even at 96%), so animals drawn with a shadow keep the default 11 and the final check is a screenshot of the seated companion against the pill's rim. A scaled profile passes the cell-measured footPad unchanged; the perch seats a scaled sprite by its scaled paw line.

**`headPad`:** Empty rows above the tallest run-cell drawing at alpha > 20%, in pt at reference size, measured the same way from the top. The around route uses it to size the companion's reach from feet to head.

**`seatLift`:** About 2 to sit on the iOS 26 rim (the measured platter frame sits about 2pt above the visible glass), 6 to hover, which suits a classic bar.

**Outline:** iOS 26 glass takes the tone of the content beneath it, light over a light page and dark over a dark image, so a character needs an outline that reads on both. Screenshot the seated companion over a light page and over a dark one.

## Licensing

Bundled art is CC BY 4.0 ([LICENSE-ART](../assets/LICENSE-ART.md)). Use it in anything, commercial or otherwise; credit "tabpet" somewhere in your app or repo. Art made with Grok carries "Created with Grok" wherever it is distributed (xAI's brand guidelines); Higgsfield output needs no attribution. Keep source clips out of the package; they are not shipped and not committed.
