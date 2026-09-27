# Companion example

A sprite-sheet companion that perches on the native tab bar, runs between tabs, and chases your finger (iOS 15.1+).

[![iOS](https://img.shields.io/badge/iOS-4630EB.svg?style=flat-square&logo=APPLE&labelColor=999999&logoColor=fff)](<>)

[![Launch with Expo](https://img.shields.io/badge/Launch-Expo-4630EB.svg?style=flat-square&logo=EXPO&labelColor=f3f3f3&logoColor=000)](https://launch.expo.dev/?github=https://github.com/Lakshay1800/tabpet/tree/main/apps/example)

## How to use

From the repo root:

```bash
bun install
cd apps/example
bunx expo prebuild --clean --platform ios
bunx expo run:ios
```

This example requires a dev build (custom native code; not compatible with Expo Go). The finger chase works on physical devices only.

## What it shows

- **Five tabs** (Home, Explore, Activity, Library, Settings) on the native tab bar. One `CompanionPerch` sits above the navigator so a tab change is just a run to the new seat.
- **Persistent storage**: `CompanionProvider` wraps the app with a file-backed storage adapter (`components/file-storage.ts`), saving the selected companion to disk.
- **Busy**: Explore holds a busy claim with `beginCompanionBusy()` for a 4-second task; the seated companion stands up and fidgets until it releases.
- **Long way round**: opening `companion://explore?demo=turn-back` or `?demo=keep-going` (from a Maestro flow, or `xcrun simctl openurl <UDID> <url>`, then tap Open on the confirmation iOS shows for a custom scheme) scripts an around route and interrupts it mid-route, for the two `around-interrupt*.yaml` flows.
- **Drag and release**: opening `companion://explore?demo=drag-release&to=<slotIndex>&lag=<ms>` scripts a finger starting on the companion and releasing over another slot, then has a host app navigate `lag` ms after the scripted release (not after the link opens) - with the fix he heads to the release slot, seats there, and stays put once the navigation lands; without it he runs home first, then turns round once the new selection arrives. A `lag` above 800ms (the library's grace window) shows the fallback either way: he waits at the release slot, gives up, runs home, then turns round when the navigation lands. For the `drag-release.yaml` flow.
- **Far grab**: opening `companion://explore?demo=far-grab&to=<slotIndex>&lag=<ms>` scripts the same release race starting far from a seated companion instead of on top of him - the default target is the slot furthest from the current tab. Same landing behavior as drag and release, with and without the fix, and the same fallback above the 800ms grace window. For the `far-grab.yaml` flow.
- **Species picker**: Settings lists the shipped companions as selectable tiles using `useCompanionId()` and `useSetCompanionId()`.
- **Quiet hops**: Activity and Library exist so the companion has somewhere to run across the floating bar.
- **Tab order**: `components/tabs.ts` defines the native tab bar order and perch slot mapping. Colors live in `components/tokens.ts`.

## Notes

See the [API reference in the root README](../../README.md#api) and the [NativeTabs routing documentation](https://docs.expo.dev/router/advanced/native-tabs/).
