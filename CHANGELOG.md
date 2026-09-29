# Changelog

## 0.3.0

- Added: a Swift package for a native iOS app, from the same repository URL. Products: `TabPetUIKit` for the views, `TabPetCore` for the registry and profiles, one `TabPetAnimal<Name>` product per animal, and `TabPetAnimals` for all six. An app that links one animal ships only that animal's sheets.
- Added: `CompanionPerchView` for UIKit and `CompanionPerch` for SwiftUI, the animal on the tab bar. Also `CompanionSpriteView` and `CompanionSprite`, the animal on its own.
- Added: in Swift, the animal chases a finger along the bar, with `barScrub`, `onDragRelease` and `fingerSource`, and the raccoon and the squirrel take the route around the pill.
- Added: a demo app in `apps/swift-demo`, in UIKit and SwiftUI, with launch arguments for repeatable recordings.
- Docs: a Swift guide in `docs/swift.md` and a release checklist in `docs/releasing.md`.

## 0.2.3

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
