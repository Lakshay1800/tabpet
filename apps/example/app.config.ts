import type { ExpoConfig } from 'expo/config';

// Placeholder identity. Change before building for a device or TestFlight.
const BUNDLE_ID = 'dev.example.companion';

const config: ExpoConfig = {
  name: 'Companion',
  slug: 'companion-example',
  version: '0.1.0',
  scheme: 'companion',
  orientation: 'portrait',
  platforms: ['ios'],
  // the example's tokens are light-only; under 'automatic' on a dark-mode
  // device the tab-switch cross-fade blends through a black system backdrop
  // and every tab change flashes gray
  userInterfaceStyle: 'light',
  ios: {
    bundleIdentifier: BUNDLE_ID,
    supportsTablet: false,
  },
  plugins: ['expo-router'],
  experiments: {
    typedRoutes: true,
    reactCompiler: true,
  },
};

export default config;
