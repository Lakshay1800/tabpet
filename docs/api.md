# API reference

## Provider

### `<CompanionProvider>`

| prop                 | type                                      | default                       |
| -------------------- | ----------------------------------------- | ----------------------------- |
| `storage`            | `{ getItem, setItem }`                    | in-memory                     |
| `storageKey`         | `string`                                  | `'tabpet:id'`                 |
| `defaultCompanionId` | `string`                                  | `'panda'`                     |
| `onError`            | `(error: unknown, site: string) => void`  | `console.error`               |
| `onHaptic`           | `(kind: 'selection' \| 'impact') => void` | none (wire to `expo-haptics`) |

Wrap your root layout in `CompanionProvider` and `GestureHandlerRootView`:

```tsx
import { CompanionProvider } from 'react-native-tabpet';
import { GestureHandlerRootView } from 'react-native-gesture-handler';

export default function RootLayout() {
  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <CompanionProvider>{/* Your app */}</CompanionProvider>
    </GestureHandlerRootView>
  );
}
```

The choice of companion is held in memory by default. Pass a `storage` adapter to persist it across sessions:

```tsx
<CompanionProvider storage={{ getItem: AsyncStorage.getItem, setItem: AsyncStorage.setItem }}>
```

## Perch

### `<CompanionPerch>`

Mount one perch in your tab navigator, pointing it at the active tab:

```tsx
const TABS = [
  { name: 'index', label: 'Home' },
  { name: 'explore', label: 'Explore' },
  { name: 'settings', label: 'Settings' },
];
const active = segments[1] ?? 'index';
const slotIndex = Math.max(0, TABS.findIndex((t) => t.name === active));

<NativeTabs>
  {TABS.map((tab) => (
    <NativeTabs.Trigger key={tab.name} name={tab.name}>
      <NativeTabs.Trigger.Label>{tab.label}</NativeTabs.Trigger.Label>
    </NativeTabs.Trigger>
  ))}
</NativeTabs>
<CompanionPerch anchor={{ slotCount: TABS.length, slotIndex }} />
```

The perch measures the native tab bar for item centers and bar height, so it seats correctly on the iOS 26 floating pill and classic full-width bars alike.

| prop | type | notes |
| --- | --- | --- |
| `anchor` | `CompanionAnchor` | required. `slotCount`, `slotIndex`, optional `slotCenters` / `barTop` for custom bars |
| `focused` | `boolean` | default `true`; pass `useIsFocused()` when mounting per screen |
| `fingerSource` | `FingerSource \| null` | `undefined` = native `UITabBar` pan, `null` = no chase |
| `onAction` | `() => void` | tap on the companion |
| `actionLabel` | `string` | accessibility label for the tap, default `"Your companion <label>. Tap to say hi."` |
| `bottomExtra` | `number` | extra lift above the bar, pt |
| `onHaptic` | see provider | overrides the provider's |
| `barScrub` | `'native' \| 'exclusive'` | default `'native'`: the bar's scrub runs and selects on release, the companion chases alongside. `'exclusive'`: the scrub is cancelled, bar stays still, host selects via `onDragRelease` |
| `onDragRelease` | `(slotIndex: number) => void` | only called in `barScrub: 'exclusive'` mode when a drag is released over another slot |
| `transientSlot` | `boolean` | default `false`. A pushed screen's own seat: snaps to `anchor.slotIndex` as an x position, no chase, and never touches the handoff the tab seats share |

`slotCenters` and `barTop` are window-space. When omitted the perch measures the native bar via `nativeTabBarLayout()` and falls back to an even split of the screen width. `anchor.pill` is the floating pill's window-space frame, for custom bars that know their own geometry; omit it to measure the native bar, or pass `null` to say there is no pill (a classic `UITabBar`), which also disables the around route.

## Sprite

### `<CompanionSprite>`

The animator underneath the perch, for custom placements. Props: `companionId`, `size` (default 88), `pose` (`'idle' | 'sit' | 'run'`), `busy`, `facing` (1 or -1), `onPress`, `pressLabel`, `onSitDone`, `onHaptic`.

## Thumb

### `<CompanionThumb id size>`

Static thumbnail (first idle frame) for pickers and settings rows.

## Hooks

- `useCompanionId(): string`
- `useSetCompanionId(): (id: string) => void` - rejects ids that aren't registered

## Registry

- `registerCompanion(profile)` - register (or overwrite) a profile at runtime
- `getCompanion(id)` - fetch a profile by id
- `listCompanions()` - array of all registered profiles
- `companionIds()` - array of all ids
- `DEFAULT_COMPANION_ID` - the default (panda)

## State

Everything in this section is also exported from **`react-native-tabpet/core`**, a Node-safe entry with no sprite sheets or `react-native` anywhere in its import graph (plus `resolveCompanionId` and `DEFAULT_COMPANION_ID`). Host modules that run under a Node test runner should import state from `react-native-tabpet/core`; importing the root entry pulls the whole UI graph in with it.

- `beginCompanionBusy(): () => void` - returns the release function; claims stack, so several callers can be busy at once
- `isCompanionBusy()` - current busy state
- `subscribeCompanionBusy(listener)` - subscribe to changes

Tell the companion you are busy:

```ts
import { beginCompanionBusy } from 'react-native-tabpet';

const release = beginCompanionBusy(); // stands up, fidgets
await syncEverything();
release(); // sits back down
```

## Adapters

- `nativeTabBarFingerSource()` - the native pan stream, `null` if the module is missing
- `useGestureFingerSource()` - a Gesture Handler `Pan` you attach to a custom tab bar, same event shape
- `nativeTabBarLayout()` - measured `{ centers, top, pill }` of the native bar, `null` before layout (returns the measured `{ centers, top, pill }` for exact geometry)
- `memoryStorage()` - the default storage
- `setGlassPanScrub(mode)` - pushes `'native' | 'exclusive'` to the native recognizer; the perch calls it from its `barScrub` prop, so only a host driving the native pan itself needs it
- `useCompanionConfig()` - the provider's `onError` and `onHaptic`, for custom placements built on `CompanionSprite`
- `PERCH_SIZE` - the perch's square, 54pt, for hosts laying out around it

## Entries

- `react-native-tabpet` - registers all six animals (panda, cat, turtle, raccoon, bird, squirrel), bundles every sheet, approximately 13MB
- `react-native-tabpet/bare` - registers none, so you can ship one or two animals without the others
- `react-native-tabpet/animals/<id>` - one profile each (panda, cat, turtle, raccoon, bird, squirrel)
- `react-native-tabpet/core` - Node-safe state, no react-native in its import graph

To ship one animal without bundling the rest:

```tsx
import { CompanionPerch, CompanionProvider, registerCompanion } from 'react-native-tabpet/bare';
import { cat } from 'react-native-tabpet/animals/cat';

registerCompanion(cat);
<CompanionProvider defaultCompanionId="cat">{/* ... */}</CompanionProvider>;
```

## Per-screen mounting

If different screens need different seats, mount a `CompanionPerch` in each tab screen with `focused={useIsFocused()}` (from `expo-router`). A module-level handoff makes the arriving instance start from where the departing one left off, so the run still looks continuous.

## Accessibility

Reduce Motion is honored: hard cuts instead of dissolves, no finger chase, no busy fidget. The companion is a button with an accessibility label and a custom action label.
