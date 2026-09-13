/**
 * Static thumbnail for a companion picker: the sit sheet's last cell, which is
 * the rest pose the perch holds, so the picker shows the same drawing as the
 * bar. Reuses the grid-crop trick of the pose layers - no animation, no new
 * assets, just a translate to the cell already loaded for the perch.
 */
import { Image } from 'expo-image';
import { StyleSheet, View } from 'react-native';

import { getCompanion } from './registry';

// mirrors companion-sprite's default; a profile's sitSheet overrides it
const DEFAULT_SIT_SHEET = { cols: 5, rows: 5, frames: 25 };

export function CompanionThumb({ id, size }: { id: string; size: number }) {
  const profile = getCompanion(id);
  if (!profile) {
    return null;
  }
  const { cols, rows, frames } = profile.sitSheet ?? DEFAULT_SIT_SHEET;
  const last = frames - 1;
  const col = last % cols;
  const row = Math.floor(last / cols);
  return (
    <View style={[styles.viewport, { width: size, height: size }]}>
      <Image
        source={profile.sheets.sit}
        style={{
          width: size * cols,
          height: size * rows,
          transform: [{ translateX: -col * size }, { translateY: -row * size }],
        }}
        contentFit="fill"
      />
    </View>
  );
}

const styles = StyleSheet.create({
  viewport: { overflow: 'hidden' },
});
