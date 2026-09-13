# How it works

## Sheet playback

Each pose is one PNG in a clipped viewport. A Reanimated worklet translates the image one cell per frame on the UI thread, so playback never touches the JS thread. All three pose layers stay mounted and cross-dissolve on a pose change, which means a switch never waits on a texture load. Sit is the rest pose: after the sit-down clip the companion holds its last frame rather than dissolving to idle, because sheets cut from different clips rarely share a seam frame.

## The seat

Native code walks the `UITabBar` and reports each item's glyph center and the bar's top edge. That matters more than it sounds: the iOS 26 floating bar is much narrower than the screen, its end buttons stretch to the pill's edge, and the selection lens keeps its own copies of the selected button. Measuring the glyph and skipping the lens is what keeps the companion centered on all five tabs. A focus that finds no bar yet - the first focus at launch, before `UITabBar` has laid out - retries the measurement for a bounded number of frames and snaps the seat once it lands, rather than settling for good on the even-split fallback.

## Running

A tab change plans a run from the last seat to the new one and drives it with a duration-parametrized spring; the finger chase uses a shorter, stiffer spring and a leash so the companion only runs toward the finger, never past it. Every spring completion is generation-gated: Reanimated 4 can report `finished` seconds late, and a stale completion must not re-seat a companion that has already moved on.

## The around route

A first-to-last tab tap on an animal with `aroundRoute` runs one continuous, arc-length-parametrized path off the near end of the pill, upside down along its underside, and up the far end: `planAroundPath` plans the whole path once, `aroundPose` evaluates it per frame from a single progress value, so the route runs at one constant speed (300 pt/s) start to finish. The feet trace the pill's real outline the whole way, including a half-ellipse wrap (radius = pill height / 2) around each rounded end cap, and the sprite rotates about its own feet (`routePivot`) through one continuous 360deg roll - no dead stops, never off the glass. Facing is set once, toward the exit end; rotated 180deg it already points the way it travels, so nothing flips mid-route. The hang mirrors the seat: the feet sit as far below the bottom border as they stand above the top one. What doesn't fit in the gap under the pill runs into the home indicator and clips at the screen bottom; the companion never shrinks. The route is skipped for bars without a pill, flying animals, two-tab bars, and Reduce Motion.

A tab change that lands mid-route does not snap the companion to the bar and run it through the glass. The perch re-plans from the companion's current point on the outline to the new slot, whichever way round is shorter (a reversal flips its facing), at the same constant speed, and only uses the straight run when the companion is already on a seat-line leg.

## iOS 26 bar anatomy

Items are `_UITabButton` inside `_UITabBarPlatterView`; `_UILiquidLensView` holds copies of the selected button at the previous tab's position, so measurement skips any subview named Lens and dedupes by midX. The bar's top for seating is the platter's minY (the pill's rim), which sits about 2pt above the visible glass. Glyph midX equals button midX on this bar.
