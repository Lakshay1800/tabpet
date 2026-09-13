/**
 * Minimal storage seam a host app plugs its own persistence into (AsyncStorage,
 * MMKV, expo-secure-store, ...). Sync or async either way - callers always await.
 */
export interface CompanionStorage {
  getItem: (key: string) => Promise<string | null> | string | null;
  setItem: (key: string, value: string) => Promise<void> | void;
}

/** In-memory storage for tests and hosts that don't want persistence. */
export function memoryStorage(): CompanionStorage {
  const map = new Map<string, string>();
  return {
    getItem(key) {
      return map.get(key) ?? null;
    },
    setItem(key, value) {
      map.set(key, value);
    },
  };
}
