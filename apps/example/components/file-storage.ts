import { File, Paths } from 'expo-file-system';
import type { CompanionStorage } from 'react-native-tabpet';

// Minimal persistence with no extra dependency: one JSON file in the
// document directory. Swap for AsyncStorage or MMKV by implementing the
// same two methods.
const store = new File(Paths.document, 'companion-preferences.json');

function read(): Record<string, string> {
  try {
    if (!store.exists) {
      return {};
    }
    return JSON.parse(store.textSync()) as Record<string, string>;
  } catch {
    return {};
  }
}

export const fileStorage: CompanionStorage = {
  getItem(key) {
    return read()[key] ?? null;
  },
  setItem(key, value) {
    const next = { ...read(), [key]: value };
    store.write(JSON.stringify(next));
  },
};
