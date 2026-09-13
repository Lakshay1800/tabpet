import * as Haptics from 'expo-haptics';
import { Stack } from 'expo-router';
import { StyleSheet } from 'react-native';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { CompanionProvider } from 'tabpet';

import { fileStorage } from '@/components/file-storage';
import { colors } from '@/components/tokens';

// The provider is optional: without it every component falls back to the
// default companion and in-memory state. Here it persists the picked animal
// to a small JSON file and routes gesture feedback through expo-haptics.
export default function RootLayout() {
  return (
    <GestureHandlerRootView style={styles.root}>
      <CompanionProvider
        storage={fileStorage}
        onHaptic={(kind) => {
          if (kind === 'selection') {
            Haptics.selectionAsync();
          } else {
            Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
          }
        }}
      >
        <Stack
          screenOptions={{ headerShown: false, contentStyle: { backgroundColor: colors.paper } }}
        >
          <Stack.Screen name="(tabs)" />
        </Stack>
      </CompanionProvider>
    </GestureHandlerRootView>
  );
}

// paper behind everything: the tab switch cross-fades screen content, and a
// bare window shows through the dip as a gray full-page flash
const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: colors.paper },
});
