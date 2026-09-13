/**
 * Node-safe entry ('tabpet/core'): the busy claim and the id helpers only -
 * no sprite-sheet requires, no react-native imports anywhere in the graph.
 * Host code that runs under a Node test runner (services, stores, bridges)
 * imports from here; UI code stays on the root entry. Adding an export?
 * It must keep this file importable by plain Node tooling.
 */
export { beginCompanionBusy, isCompanionBusy, subscribeCompanionBusy } from './companion-state';
export { DEFAULT_COMPANION_ID, resolveCompanionId } from './companion-id';
export type { CompanionId } from './companion-id';
