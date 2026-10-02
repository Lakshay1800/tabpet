import { useIsFocused } from 'expo-router';
import { CompanionPerch } from 'react-native-tabpet';

import { fingerSource } from '@/components/finger';
import { useMountMode } from '@/components/mount-mode';
import { SLOT_COUNT, slotIndex } from '@/components/tabs';
import type { TabName } from '@/components/tabs';

export function ScreenPerch({ name }: { name: TabName }) {
  const mode = useMountMode();
  const focused = useIsFocused();
  if (mode !== 'screen') {
    return null;
  }
  return (
    <CompanionPerch
      anchor={{ slotCount: SLOT_COUNT, slotIndex: slotIndex(name) }}
      focused={focused}
      fingerSource={fingerSource}
    />
  );
}
