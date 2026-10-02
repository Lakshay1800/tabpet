import { useSegments } from 'expo-router';
import { NativeTabs } from 'expo-router/unstable-native-tabs';
import { StyleSheet, View } from 'react-native';
import { CompanionPerch } from 'react-native-tabpet';

import { fingerSource } from '@/components/finger';
import { useMountMode } from '@/components/mount-mode';
import { SLOT_COUNT, slotIndex, TABS } from '@/components/tabs';
import type { TabName } from '@/components/tabs';

// One perch for the whole tab bar, mounted once above the navigator. The
// active route drives the slot; the companion is never part of a screen, so tab
// transitions can't touch it and a tab change is just a run to the new slot.
// The 'screen' mode mounts one perch per screen (components/screen-perch.tsx) for the per-screen demos.
export default function TabsLayout() {
  const segments = useSegments() as string[];
  const mountMode = useMountMode();
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
      {mountMode === 'layout' && (
        <CompanionPerch
          anchor={{ slotCount: SLOT_COUNT, slotIndex: slotIndex(active) }}
          fingerSource={fingerSource}
        />
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1 },
});
