/**
 * Host-app wiring for the companion: which animal is active, persistence,
 * and error/haptic plumbing. Two contexts, not one, so an id-only reader
 * (sprite, perch) doesn't re-render on a config change. Every hook works
 * with no provider mounted - defaults make the library usable standalone.
 */
import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
} from 'react';
import type { ReactNode } from 'react';

import { resolveCompanionId } from './companion-id';
import { companionIds, DEFAULT_COMPANION_ID } from './registry';
import type { CompanionStorage } from './storage';

export interface CompanionConfig {
  setId: (id: string) => void;
  onError: (error: unknown, site: string) => void;
  onHaptic: (kind: 'selection' | 'impact') => void;
}

const CompanionIdContext = createContext<string>(DEFAULT_COMPANION_ID);

const defaultConfig: CompanionConfig = {
  setId() {
    // no provider mounted - nothing to persist to
  },
  onError(error, site) {
    console.error(`[tabpet] ${site}`, error);
  },
  onHaptic() {
    // no provider mounted - haptics are host-owned
  },
};

const CompanionConfigContext = createContext<CompanionConfig>(defaultConfig);

const DEFAULT_STORAGE_KEY = 'tabpet:id';

export interface CompanionProviderProps {
  children: ReactNode;
  storage?: CompanionStorage;
  storageKey?: string;
  defaultCompanionId?: string;
  onError?: (error: unknown, site: string) => void;
  onHaptic?: (kind: 'selection' | 'impact') => void;
}

export function CompanionProvider({
  children,
  storage,
  storageKey = DEFAULT_STORAGE_KEY,
  defaultCompanionId,
  onError,
  onHaptic,
}: CompanionProviderProps) {
  const initial = defaultCompanionId ?? DEFAULT_COMPANION_ID;
  const [companionId, setCompanionId] = useState(initial);
  const mountedRef = useRef(true);
  useEffect(
    () => () => {
      mountedRef.current = false;
    },
    []
  );

  const handleError = onError ?? defaultConfig.onError;
  const handleHaptic = onHaptic ?? defaultConfig.onHaptic;

  useEffect(() => {
    if (!storage) {
      return;
    }
    (async () => {
      try {
        const stored = await storage.getItem(storageKey);
        if (!mountedRef.current) {
          return;
        }
        setCompanionId(resolveCompanionId(stored, companionIds(), initial));
      } catch (error) {
        handleError(error, 'provider.hydrate');
      }
    })();
    // oxlint-disable-next-line exhaustive-deps -- storage/storageKey/initial are read once at mount (hydrate-on-mount)
  }, []);

  const persist = useCallback(
    async (value: string) => {
      if (!storage) {
        return;
      }
      try {
        await storage.setItem(storageKey, value);
      } catch (error) {
        handleError(error, 'provider.persist');
      }
    },
    [storage, storageKey, handleError]
  );

  const setId = useCallback(
    (nextId: string) => {
      if (!companionIds().includes(nextId)) {
        handleError(new Error(`unknown companion id: ${nextId}`), 'provider.setId');
        return;
      }
      setCompanionId(nextId);
      void persist(nextId);
    },
    [handleError, persist]
  );

  const config = useMemo<CompanionConfig>(
    () => ({ setId, onError: handleError, onHaptic: handleHaptic }),
    [setId, handleError, handleHaptic]
  );

  return (
    <CompanionIdContext.Provider value={companionId}>
      <CompanionConfigContext.Provider value={config}>{children}</CompanionConfigContext.Provider>
    </CompanionIdContext.Provider>
  );
}

export function useCompanionId(): string {
  return useContext(CompanionIdContext);
}

export function useSetCompanionId(): (id: string) => void {
  return useContext(CompanionConfigContext).setId;
}

/** Exported for hosts that need the raw config (error/haptic hooks); most
 *  consumers want useCompanionId/useSetCompanionId instead. */
export function useCompanionConfig(): CompanionConfig {
  return useContext(CompanionConfigContext);
}
