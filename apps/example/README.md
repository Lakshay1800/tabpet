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
- **Species picker**: Settings lists the shipped companions as selectable tiles using `useCompanionId()` and `useSetCompanionId()`.
- **Quiet hops**: Activity and Library exist so the companion has somewhere to run across the floating bar.
- **Tab order**: `components/tabs.ts` defines the native tab bar order and perch slot mapping. Colors live in `components/tokens.ts`.

## Notes

See the [API reference in the root README](../../README.md#api) and the [NativeTabs routing documentation](https://docs.expo.dev/router/advanced/native-tabs/).
