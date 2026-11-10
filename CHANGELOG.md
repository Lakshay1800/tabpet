# Changelog

## Unreleased

- Fixed: after a StrictMode or Activity re-mount, the provider's stored companion, the sprite's tap and the perch's run arrival no longer stay switched off.
- Fixed: `useGestureFingerSource` reports a cancelled drag as `cancelled` only. Before, it sent `ended` first, so a cancelled drag could navigate with `barScrub: 'exclusive'`.
- Fixed: `react-native-tabpet/core` loads in plain Node. The `build` output is now CommonJS.
- Fixed: in Swift, with one perch per screen sharing a `PerchHandoffStore`, a tab change mid-route resumes along the outline from the arriving perch, as 0.3.1 did for React Native. A `transientSlot` perch neither takes nor clears the resume point.
- Fixed: in Swift, a busy claim on a seated perch shows at once, not at the next tab change or touch.
- Fixed: in Swift, a slow animal climbing to a raised seat lands on it; a tap on a torn-down sprite does nothing; a sprite error raised while a perch is built reaches the `onError` passed to its initializer; a cached sheet is checked against the grid of each request.
- Tools: `sprite-sheet.sh` rejects `--flip` with `--track` and prints its whole help; `frame-stack.sh` stops on ctrl-C and lets the recorder flush; `sheet-compare.py` skips a cell with no anchor pixels.
- Docs: `headPad` is recorded per sheet but not read at runtime; the fallback tab positions are an even split of the screen width inset 16pt on each side.

## 0.3.1

- Fixed: with one perch per screen, a tab change that lands while the raccoon or squirrel is on the curve or the underside of the pill now resumes along the outline from the arriving perch. Before, the resume point stayed with the departing perch, so the arriving one snapped the companion up through the glass to its seat. A single perch above the navigator was never affected.
- Example: `companion://explore?mount=screen` switches the example to one perch per tab screen, and `maestro/around-interrupt-screen.yaml` and `around-interrupt-forward-screen.yaml` record the interrupt in that mode.

## 0.3.0

- Added: a Swift package for a native iOS app, from the same repository URL. Products: `TabPetUIKit` for the views, `TabPetCore` for the registry and profiles, one `TabPetAnimal<Name>` product per animal, and `TabPetAnimals` for all six. An app that links one animal ships only that animal's sheets.
- Added: `CompanionPerchView` for UIKit and `CompanionPerch` for SwiftUI, the animal on the tab bar. Also `CompanionSpriteView` and `CompanionSprite`, the animal on its own.
- Added: in Swift, the animal chases a finger along the bar, with `barScrub`, `onDragRelease` and `fingerSource`, and the raccoon and the squirrel take the route around the pill.
- Added: a demo app in `apps/swift-demo`, in UIKit and SwiftUI, with launch arguments for repeatable recordings.
- Docs: a Swift guide in `docs/swift.md` and a release checklist in `docs/releasing.md`.

## 0.2.3

Not tagged or published to npm on its own; these changes first shipped in 0.3.0.

- Fixed: the squirrel no longer shows a light patch under its feet on a dark tab bar. Its three sheets lose the painted ground shadow, the white matte edge and the background sealed between the legs. The seat is unchanged.
- Tools: `tools/ground-shadow.py` separates a painted ground shadow from the fur by position when color cannot, `tools/defringe.py` cleans the white matte edge, sealed pockets and specks, and `tools/sheet-compare.py` reports what a cleaning changed against the original sheet, cell by cell.
- Docs: the art pipeline covers a shadow that color cannot separate from the fur, and asks for a review on a dark background before a sheet ships. The profile reference corrects what `scale` does to the seat: a `footPad` that is not the measured value shifts it.

## 0.2.2

- Fixed: a drag released over another tab no longer runs back to the old tab before the selection lands.
- Fixed: onDragRelease is no longer called for a cancelled drag.
- Changed: a release or cancel far from the companion's seat runs home at its run speed instead of crossing the bar on one spring.
- Fixed: a drag that starts far from the companion now runs to the finger at its run speed, steadily, instead of crossing the bar in a quarter second.

## 0.2.1

- Docs: the per-animal entry reads `react-native-tabpet/animals/<id>` everywhere, including the source comment that ships in the package. The npm README now points at the bare entry for shipping one animal.

## 0.2.0

First public release.

- Six companions: panda, cat, turtle, raccoon, bird and squirrel. Each is three sprite sheets and a profile of springs, speeds and seat measurements.
- Perch: measures the native `UITabBar`, the iOS 26 floating pill included, and keeps measuring across the first frames at launch so the seat is exact from the first focus.
- Runs between tabs at a constant speed, with a hop for the animals that hop. Chases the finger along the bar; the bar's own scrub keeps working by default, `barScrub="exclusive"` takes it over.
- Around route for the raccoon and squirrel: over the end of the pill, along its underside, and up the far side. A tab change mid-route resumes along the outline instead of cutting through the glass.
- Busy claims stand the companion up until the last one releases. Reduce Motion is honored throughout.
- Entries: `react-native-tabpet` registers all six, `react-native-tabpet/bare` registers none, `react-native-tabpet/animals/<id>` one each, `react-native-tabpet/core` is Node-safe state.
- Dev builds warn once when the GlassPan native module is not linked.
- Tools: the sprite-sheet slicer, deshadow, and the frame-stack and pill-geometry verifiers.
