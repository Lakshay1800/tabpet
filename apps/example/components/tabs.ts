/** Tab order is the native bar order; each screen's perch slot derives from it. */
export const TABS = [
  { name: 'index', label: 'Home', sf: 'house' },
  { name: 'explore', label: 'Explore', sf: 'safari' },
  { name: 'activity', label: 'Activity', sf: 'figure.walk' },
  { name: 'library', label: 'Library', sf: 'books.vertical' },
  { name: 'settings', label: 'Settings', sf: 'gearshape' },
] as const;

export type TabName = (typeof TABS)[number]['name'];
export const SLOT_COUNT = TABS.length;
export function slotIndex(name: TabName): number {
  return TABS.findIndex((t) => t.name === name);
}
