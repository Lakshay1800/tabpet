import { Platform } from 'react-native';

// One warning per module per process - a mounted perch calls into these
// getters every frame and must not spam the console.
const warned = new Set<string>();

/** Loud, dev-only heads-up when a required native module didn't link. Silent
 *  in prod, on non-iOS, and under Node test runs (no __DEV__ there). */
export function warnMissingNativeModule(name: 'GlassPan', consequence: string): void {
  if (!(typeof __DEV__ !== 'undefined' && __DEV__)) {
    return;
  }
  if (Platform.OS !== 'ios') {
    return;
  }
  if (warned.has(name)) {
    return;
  }
  warned.add(name);
  try {
    console.warn(
      `[tabpet] Native module ${name} is not linked; ${consequence}. Rebuild the dev client (npx expo prebuild && npx expo run:ios). If TabPet is missing from ios/Podfile.lock, your iOS deployment target is below the podspec floor (15.1): CocoaPods skips the pod without an error.`
    );
  } catch {
    // console.warn unavailable in this runtime
  }
}
