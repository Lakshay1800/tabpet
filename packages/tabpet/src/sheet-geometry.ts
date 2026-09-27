/**
 * Pure sprite-sheet grid constants for the built-in idle/run/sit layout,
 * kept free of react-native and PNG imports so a Node script (the Swift
 * conformance generator) can import it directly.
 */
import type { SheetGeometry } from './registry';

/** idle stays 5x5x25 @ 12fps for every animal */
export const IDLE_SHEET_GRID: SheetGeometry = { cols: 5, rows: 5, frames: 25, fps: 12 };
/** run's grid is shared; fps is per-animal (profile.runFps) */
export const RUN_SHEET_GRID: Omit<SheetGeometry, 'fps'> = { cols: 4, rows: 3, frames: 11 };
/** sit defaults to idle's grid; a profile may carry its own (profile.sitSheet)
 *  for a 1:1 24fps settle */
export const DEFAULT_SIT_SHEET: SheetGeometry = { cols: 5, rows: 5, frames: 25, fps: 12 };
