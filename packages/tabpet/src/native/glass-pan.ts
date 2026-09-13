import { requireOptionalNativeModule } from 'expo';
import type { NativeModule } from 'expo-modules-core';

import type { PillFrame } from '../perch-around';
import { warnMissingNativeModule } from './missing-module';

export type { PillFrame } from '../perch-around';

export interface GlassPanEvent {
  x: number;
  phase: 'began' | 'moved' | 'ended' | 'cancelled';
}

// type (not interface): NativeModule<T>'s EventsMap constraint needs the
// implicit index signature TS only infers for type-literal aliases
// oxlint-disable-next-line typescript/consistent-type-definitions
type GlassPanEvents = {
  onGlassPan: (event: GlassPanEvent) => void;
};

// expo-modules-core idiom: `NativeModule<Events>` alone doesn't expose
// instance methods like addListener to the type checker.
declare class GlassPanModule extends NativeModule<GlassPanEvents> {
  tabBarLayout(): { centers: number[]; top: number | null; pill: PillFrame | null };
  setBarScrub(exclusive: boolean): void;
}

// Optional on purpose: JS must not crash where the module is absent (tests,
// any stale runtime that hasn't rebuilt native code for this build).
const GlassPan = requireOptionalNativeModule<GlassPanModule>('GlassPan');
if (!GlassPan) {
  warnMissingNativeModule(
    'GlassPan',
    'tab positions fall back to an even split of the screen width and there is no finger chase'
  );
}

export default GlassPan;

/** Subscribes to native tab-bar drag events; returns null when the module is missing. */
export function subscribeGlassPan(listener: (event: GlassPanEvent) => void): (() => void) | null {
  if (!GlassPan) {
    return null;
  }
  const subscription = GlassPan.addListener('onGlassPan', listener);
  return () => subscription.remove();
}

export type BarScrub = 'native' | 'exclusive';

/** Whether the perch's bar drag rides the bar's own scrub (`native`) or
 *  cancels it (`exclusive`). No-op when the module is missing, and swallowed
 *  on a native build older than this function (an OTA'd JS bundle over
 *  0.1.5 native code keeps that build's exclusive behaviour). */
export function setGlassPanScrub(mode: BarScrub): void {
  if (!GlassPan) {
    return;
  }
  try {
    GlassPan.setBarScrub(mode === 'exclusive');
  } catch {
    // stale native build without setBarScrub
  }
}

export interface TabBarLayout {
  /** window-space x center of each item button, in bar order */
  centers: number[];
  /** window-space y of the bar's top edge; null when no bar is mounted */
  top: number | null;
  /** window-space frame of the iOS 26 floating pill; null on classic bars or when no bar is mounted */
  pill: PillFrame | null;
}

/** Measured native tab-bar layout; null when the module is absent, empty
 *  centers when no bar is mounted yet. */
export function nativeTabBarLayout(): TabBarLayout | null {
  if (!GlassPan) {
    return null;
  }
  try {
    return GlassPan.tabBarLayout();
  } catch {
    return null;
  }
}
