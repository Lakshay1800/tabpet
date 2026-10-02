import { useSyncExternalStore } from 'react';

export type MountMode = 'layout' | 'screen';

let mode: MountMode = 'layout';
const listeners = new Set<() => void>();

export function setMountMode(next: MountMode): void {
  if (next === mode) {
    return;
  }
  mode = next;
  for (const listener of listeners) {
    listener();
  }
}

function subscribe(listener: () => void): () => void {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

function getSnapshot(): MountMode {
  return mode;
}

export function useMountMode(): MountMode {
  return useSyncExternalStore(subscribe, getSnapshot, getSnapshot);
}
