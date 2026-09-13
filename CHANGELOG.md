# Changelog

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
