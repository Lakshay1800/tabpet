# Integration guide

The companion lives in a `CompanionPerch` that rides your app's native tab bar. Mount it once at the root layout and keep passing the active tab index as the user navigates.

## Requirements

- Expo SDK 57+, New Architecture, a dev build (custom native code, so not Expo Go)
- iOS 15.1+
- iOS only. The Swift module (tab-bar measurement and pan) has no Android counterpart. In a cross-platform app, gate the mount on `Platform.OS === 'ios'`
- Reanimated 4.x, Gesture Handler, Worklets, `expo-image`, `react-native-safe-area-context` (all declared as peer dependencies in package.json)

## Install

```bash
npx expo install tabpet react-native-reanimated react-native-gesture-handler react-native-worklets expo-image react-native-safe-area-context
npx expo prebuild --clean --platform ios
npx expo run:ios
```

The package is ~13MB installed - nearly all of it the six bundled sprite sheets.

### Trying it from a local checkout

Install from a packed tarball, not a `file:` directory:

```bash
cd tabpet/packages/tabpet && bun pm pack
# in your app's package.json: "tabpet": "file:../tabpet/packages/tabpet/tabpet-0.2.0.tgz"
```

Reason: bun materializes `file:` directories as per-file symlinks. Metro follows them out of your project and resolves tabpet's imports against the tabpet workspace's own node_modules. A second Reanimated boots and the app dies at launch with `property is not writable`. The tarball installs real files, which is also exactly what an npm install gives you.

Re-packing under the same filename does not reinstall: bun caches a local tarball by path, so `bun install`, even with `--force`, re-extracts the old bytes. Give the new pack a new name, or `bun add ./path/to/tabpet-0.2.0.tgz` to refresh that one lock entry.

## Check the pod linked

After `npx expo prebuild`, verify the native module linked:

```bash
grep TabPet ios/Podfile.lock
```

If absent, your app's iOS deployment target is below the podspec floor (15.1) and CocoaPods skipped it without an error. Dev builds also warn at launch: `[tabpet] Native module GlassPan is not linked ...`

## Mount once

Wrap the root in `GestureHandlerRootView` and `CompanionProvider`:

```tsx
// app/_layout.tsx
import { CompanionProvider } from 'tabpet';
import { Stack } from 'expo-router';
import { GestureHandlerRootView } from 'react-native-gesture-handler';

export default function RootLayout() {
  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <CompanionProvider>
        <Stack screenOptions={{ headerShown: false }} />
      </CompanionProvider>
    </GestureHandlerRootView>
  );
}
```

Mount one `CompanionPerch` next to the tab navigator and point it at the active tab:

```tsx
// app/(tabs)/_layout.tsx
import { CompanionPerch } from 'tabpet';
import { useSegments } from 'expo-router';
import { NativeTabs } from 'expo-router/unstable-native-tabs';
import { View } from 'react-native';

const TABS = [
  { name: 'index', label: 'Home' },
  { name: 'explore', label: 'Explore' },
  { name: 'settings', label: 'Settings' },
];

export default function TabsLayout() {
  const segments = useSegments() as string[];
  const active = segments[1] ?? 'index';
  const slotIndex = Math.max(
    0,
    TABS.findIndex((t) => t.name === active)
  );

  return (
    <View style={{ flex: 1 }}>
      <NativeTabs>
        {TABS.map((tab) => (
          <NativeTabs.Trigger key={tab.name} name={tab.name}>
            <NativeTabs.Trigger.Label>{tab.label}</NativeTabs.Trigger.Label>
          </NativeTabs.Trigger>
        ))}
      </NativeTabs>
      <CompanionPerch anchor={{ slotCount: TABS.length, slotIndex }} />
    </View>
  );
}
```

The perch measures the native tab bar for item centers and bar height, so it seats correctly on the iOS 26 floating bar and the classic full-width bar alike. Because the perch lives above the navigator instead of inside a screen, a tab change never unmounts it.

`slotCount` must equal the number of `NativeTabs.Trigger`s, and `slotIndex` is the trigger order, not a route name. The perch measures item centers natively; an even split of the screen width is only the fallback when the native module is missing.

## Pushed screens over the tabs

While a root-stack screen covers the tabs, `useSegments()` reports the pushed route instead of a tab, and the bar leaves the window. Two things follow. The perch keeps the last bar geometry it measured, so it does not fall back to the even split. Your `slotIndex` derivation must hold the last real tab, or the lookup misses, resolves to 0, and the companion runs to the first tab behind the pushed screen:

```tsx
const segments = useSegments() as string[];
const lastTabRef = useRef(0);
const tabIndex = TABS.findIndex((t) => t.name === segments[1]);
if (tabIndex >= 0) {
  lastTabRef.current = tabIndex;
}
const slotIndex = lastTabRef.current;
```

`transientSlot` is for the other case, a pushed screen that wants the companion at a seat of its own: mount a perch in that screen with `transientSlot` and an `anchor.slotIndex` used only as an x position. It snaps there with no chase and never touches the handoff the real tab seats share.

## Bar drag handling

Default behavior (`barScrub: 'native'`): the iOS 26 pill follows the finger, the bar selects on release, the companion chases alongside. Nothing to wire.

If you want exclusive control, pass `barScrub: 'exclusive'` and wire `onDragRelease`:

```tsx
<CompanionPerch
  anchor={{ slotCount, slotIndex }}
  barScrub="exclusive"
  onDragRelease={(newSlotIndex) => {
    navigate(TABS[newSlotIndex].name);
  }}
/>
```

In exclusive mode the perch's recognizer cancels the bar's scrub, the bar holds still, and the host selects the tab on release. Omit `onDragRelease` and the drag is a chase only: the companion walks back to its seat. The platform behavior is the default; the deviation is the opt-in. `barScrub` only applies to the native recognizer; a custom `fingerSource` is whatever gesture you built.

## Theme sync

The native bar follows the system appearance. If your app forces its own theme, call `Appearance.setColorScheme(scheme)` so the bar matches:

```tsx
import { Appearance } from 'react-native';

Appearance.setColorScheme('light'); // or 'dark', or null for system
```

Gotcha: on iOS 26 the tab-switch cross-fade blends through the system backdrop. A light-only app on a device in dark mode dims every tab switch for a few frames. Pin `userInterfaceStyle: 'light'` in app config or sync Appearance.

## Custom JS tab bars

If you built your own tab bar in JS, there is no `UITabBar` to measure, so pass the geometry yourself, all in window space: `slotCenters` (x of each item), `barTop` (y of the bar's top edge), and `pill` (the floating pill's frame, or `null` for a bar without one, which also disables the around route). Measure them with `onLayout` plus `measureInWindow` on your bar. For the chase, `useGestureFingerSource()` returns `{ source, gesture }`: attach `gesture` to your bar with `GestureDetector` and pass `source` as `fingerSource`. Pass `fingerSource={null}` for no chase.

```tsx
const { source, gesture } = useGestureFingerSource();

<GestureDetector gesture={gesture}>
  <MyTabBar onLayout={measureBar} />
</GestureDetector>
<CompanionPerch
  anchor={{ slotCount, slotIndex, slotCenters, barTop, pill }}
  fingerSource={source}
/>
```

## Ship one animal

The root entry `tabpet` registers all six built-ins and bundles every sprite sheet (~13MB). To ship only one or a subset, import from `tabpet/bare` and register only what you use:

```tsx
import { CompanionPerch, CompanionProvider, registerCompanion } from 'tabpet/bare';
import { cat } from 'tabpet/animals/cat';

registerCompanion(cat);
// ... <CompanionProvider defaultCompanionId="cat"> ... <CompanionPerch ... />
```

Each animal's three sheets weigh 1.4MB to 3.2MB; the root entry bundles all six.

## Busy claims and the picker

Tell the companion you're busy:

```ts
import { beginCompanionBusy } from 'tabpet';

const release = beginCompanionBusy(); // stands up, fidgets
await syncEverything();
release(); // sits back down
```

Claims stack, so several callers can be busy at once; the companion sits when the last one releases.

Let people pick their animal:

```tsx
import { CompanionThumb, companionIds, useCompanionId, useSetCompanionId } from 'tabpet';

function CompanionPicker() {
  const current = useCompanionId();
  const setId = useSetCompanionId();
  return companionIds().map((id) => (
    <Pressable key={id} onPress={() => setId(id)}>
      <CompanionThumb id={id} size={64} />
    </Pressable>
  ));
}
```

The choice is held in memory by default. Persist it with a storage adapter:

```tsx
<CompanionProvider storage={{ getItem: AsyncStorage.getItem, setItem: AsyncStorage.setItem }}>
```

## What only a device shows

The finger chase and the bar's own scrub are only visible on a physical device. The simulator's synthetic gestures do not drive the `UITabBar` pan, so a Maestro swipe shows a still bar and no chase. Reduce Motion is honored: hard cuts instead of dissolves, no finger chase, no busy fidget.

## Further reading

- [API reference](./api.md)
- [Profile reference](./profiles.md)
- [Art pipeline](./art-pipeline.md)
