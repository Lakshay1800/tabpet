import type { ImageSourcePropType } from 'react-native';

import type { CompanionId } from './companion-id';
/**
 * Companion catalog - a runtime registry of animal profiles, empty by
 * default. Built-ins (panda, cat, turtle, raccoon, bird, squirrel) live in
 * src/animals/ as one module per animal so a host importing only what it
 * ships never bundles the other sheets.
 */

export { DEFAULT_COMPANION_ID } from './companion-id';

export interface SpringConfig {
  duration: number;
  dampingRatio: number;
}

export interface SheetGeometry {
  cols: number;
  rows: number;
  /** populated cells; a grid may carry an unused trailing cell */
  frames: number;
  fps: number;
}

export interface CompanionProfile {
  id: CompanionId;
  /** lowercase noun, fits "Your companion {label}" accessibility sentences */
  label: string;
  sheets: {
    idle: ImageSourcePropType;
    run: ImageSourcePropType;
    sit: ImageSourcePropType;
  };
  runFps: number;
  /** tab-change commit chase spring */
  commitSpring: SpringConfig;
  /** live glass-drag tracking spring */
  trackSpring: SpringConfig;
  /** release-to-seat catch spring */
  catchSpring: SpringConfig;
  /** hop peak in pt, negative = up; 0 = never hops */
  hopHeight: number;
  /** pt lifted off the bar line while pose is 'run'; 0 = stays grounded */
  flightLift: number;
  /** Render-size multiplier, applied identically to every pose layer in one
   * transform alongside the facing mirror; 1 = reference size. */
  scale: number;
  /** First-slot <-> last-slot taps take the scenic route around the pill;
   * ground animals only, ignored when flightLift > 0 or there's no pill. */
  aroundRoute: boolean;
  /** Empty pt above the run-cell drawing at reference size (sheet-metrics.ts),
   * used for the around route's wall lean. Omit to assume a full cell. */
  headPad?: number;
  /** Empty pt between the drawing's ground contact and the sit-cell bottom
   * at reference size; overrides the shared 11pt assumption. Animals drawn
   * without a ground shadow carry less air under the feet - left at the
   * default they seat that difference INTO the pill. */
  footPad?: number;
  /** Pt the ground contact sits above the measured bar top; omit for the
   * shared 6pt hover, which suits a classic bar (its "top" is the icons'
   * edge). On the iOS 26 pill the measured top is the glass rim, so a
   * companion meant to sit ON it sets this near 0. */
  seatLift?: number;
  /** Ground speed in pt/s for the tab-tap run leg; omit for the shared
   * TRAVERSE_SPEED_PT_S (340). The duration clamps stretch with it, so a
   * slow animal stays slow on a one-slot hop too. */
  runSpeed?: number;
  /** Sit sheet grid and playback rate; omit for the shared 5x5x25 @ 12fps.
   * A 24fps source cut 1:1 (10x5x50 @ 24) plays the settle without the
   * every-other-frame skip the default grid implies. */
  sitSheet?: SheetGeometry;
}

const registry: Record<string, CompanionProfile> = {};

/** Registers (or overwrites) a profile at runtime - the extension point for
 *  a host app adding animals beyond the six shipped in src/animals/. */
export function registerCompanion(profile: CompanionProfile): void {
  registry[profile.id] = profile;
}

export function getCompanion(id: string): CompanionProfile | undefined {
  return registry[id];
}

export function listCompanions(): CompanionProfile[] {
  return Object.values(registry);
}

export function companionIds(): string[] {
  return Object.keys(registry);
}
