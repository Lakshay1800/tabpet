import { useSegments } from 'expo-router';
import { NativeTabs } from 'expo-router/unstable-native-tabs';
import { StyleSheet, View } from 'react-native';
import { CompanionPerch } from 'react-native-tabpet';

import { SLOT_COUNT, slotIndex, TABS } from '@/components/tabs';
import type { TabName } from '@/components/tabs';

// One perch for the whole tab bar, mounted once above the navigator. The
// active route drives the slot; the companion is never part of a screen, so tab
// transitions can't touch it and a tab change is just a run to the new slot.
export default function TabsLayout() {
  const segments = useSegments() as string[];
  const active = (segments[1] ?? 'index') as TabName;
  return (
    <View style={styles.root}>
      <NativeTabs>
        {TABS.map((tab) => (
          <NativeTabs.Trigger key={tab.name} name={tab.name}>
            <NativeTabs.Trigger.Label>{tab.label}</NativeTabs.Trigger.Label>
            <NativeTabs.Trigger.Icon sf={tab.sf} />
          </NativeTabs.Trigger>
        ))}
      </NativeTabs>
      <CompanionPerch anchor={{ slotCount: SLOT_COUNT, slotIndex: slotIndex(active) }} />
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1 },
});
