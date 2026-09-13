/**
 * Companion id allowlist helper - pure, PNG-free (the registry requires the
 * sprite sheets and must never be imported from a test file; a caller's own
 * known-id list is the single source of truth so hydration logic stays
 * testable without pulling images into the test runner).
 */
export type CompanionId = string;

/** the companion the provider starts on when nothing is stored */
export const DEFAULT_COMPANION_ID: CompanionId = 'panda';

/** allowlist-validates a saved setting value, defaulting to `fallback` for anything unrecognized */
export function resolveCompanionId(
  value: unknown,
  known: readonly string[],
  fallback: string
): string {
  if (typeof value === 'string' && known.includes(value)) {
    return value;
  }
  return fallback;
}
