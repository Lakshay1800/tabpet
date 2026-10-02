import { nativeTabBarFingerSource } from 'react-native-tabpet';

import { demoFingerSource, mergeFingerSources } from './demo-finger';

// Built once so the real finger keeps working exactly as before; the demo
// emitter is silent until a deep link calls play() on it.
export const fingerSource = mergeFingerSources(nativeTabBarFingerSource(), demoFingerSource);
