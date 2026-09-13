import { StyleSheet, Text, View } from 'react-native';

import { Screen } from '@/components/screen';
import { space, type } from '@/components/tokens';

const HINTS = [
  'Tap another tab and the companion runs there.',
  'Drag your finger along the tab bar and it chases.',
];

export default function Home() {
  return (
    <Screen title="Home">
      <View style={styles.stack}>
        {HINTS.map((hint) => (
          <Text key={hint} style={styles.body}>
            {hint}
          </Text>
        ))}
      </View>
    </Screen>
  );
}

const styles = StyleSheet.create({
  stack: { gap: space.md },
  body: type.body,
});
