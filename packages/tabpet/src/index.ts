import { registerBuiltinCompanions } from './animals/all';

export { CompanionPerch } from './companion-perch';
export type { CompanionAnchor, CompanionPerchProps } from './companion-perch';
export {
  CompanionProvider,
  useCompanionConfig,
  useCompanionId,
  useSetCompanionId,
} from './companion-provider';
export type { CompanionConfig, CompanionProviderProps } from './companion-provider';
export { CompanionSprite } from './companion-sprite';
export type { CompanionPose, CompanionSpriteProps } from './companion-sprite';
export { CompanionThumb } from './companion-thumb';
export { resolveCompanionId } from './companion-id';
export type { CompanionId } from './companion-id';
export { beginCompanionBusy, isCompanionBusy, subscribeCompanionBusy } from './companion-state';
export { nativeTabBarFingerSource, useGestureFingerSource } from './finger-source';
export { setGlassPanScrub } from './native/glass-pan';
export type { BarScrub } from './native/glass-pan';
export { nativeTabBarLayout } from './native/glass-pan';
export type { PillFrame, TabBarLayout } from './native/glass-pan';
export type { FingerEvent, FingerPhase, FingerSource } from './finger-source';
export { PERCH_SIZE } from './perch-geometry';
export {
  companionIds,
  DEFAULT_COMPANION_ID,
  getCompanion,
  listCompanions,
  registerCompanion,
} from './registry';
export type { CompanionProfile, SheetGeometry, SpringConfig } from './registry';
export { memoryStorage } from './storage';
export type { CompanionStorage } from './storage';
export { registerBuiltinCompanions } from './animals/all';

// root entry registers all six built-ins so existing consumers get them for
// free; `tabpet/bare` skips this and bundles none of the sprite sheets.
registerBuiltinCompanions();
