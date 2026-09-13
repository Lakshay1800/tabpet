import { Pressable, StyleSheet, Text, View } from 'react-native';
import {
  CompanionThumb,
  getCompanion,
  listCompanions,
  useCompanionId,
  useSetCompanionId,
} from 'react-native-tabpet';

import { Screen } from '@/components/screen';
import { colors, radius, space, type } from '@/components/tokens';

export default function Settings() {
  const current = useCompanionId();
  const setCompanion = useSetCompanionId();
  const companions = listCompanions();
  return (
    <Screen title="Settings">
      <Text style={styles.label}>Companion</Text>
      <View style={styles.grid}>
        {companions.map((profile) => {
          const selected = profile.id === current;
          return (
            <Pressable
              key={profile.id}
              onPress={() => setCompanion(profile.id)}
              accessibilityRole="button"
              accessibilityState={{ selected }}
              accessibilityLabel={`Choose ${profile.label}`}
              accessibilityHint={
                selected ? 'Currently selected' : `Sets the companion to ${profile.label}`
              }
              style={[styles.tile, selected && styles.tileSelected]}
            >
              <CompanionThumb id={profile.id} size={64} />
              <Text style={styles.tileLabel}>{getCompanion(profile.id)?.label}</Text>
            </Pressable>
          );
        })}
      </View>
    </Screen>
  );
}

const styles = StyleSheet.create({
  label: { ...type.label, marginBottom: space.sm },
  grid: { flexDirection: 'row', flexWrap: 'wrap', gap: space.md },
  tile: {
    alignItems: 'center',
    gap: space.xs,
    padding: space.md,
    borderRadius: radius.tile,
    borderWidth: 1,
    borderColor: colors.hairline,
    backgroundColor: colors.card,
  },
  tileSelected: { borderColor: colors.ink },
  tileLabel: { ...type.tile, textTransform: 'capitalize' },
});
