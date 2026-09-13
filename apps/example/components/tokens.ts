/**
 * Demo-app tokens, inferred from the screens as they already shipped:
 * warm paper, ink type, white tiles, 12-14pt radii. Not a second system.
 */
export const colors = {
  paper: '#f4f4f2',
  ink: '#111',
  body: '#444',
  muted: '#666',
  card: '#fff',
  onInk: '#fff',
  hairline: 'rgba(0,0,0,0.08)',
} as const;

export const space = {
  xs: 6,
  sm: 8,
  md: 12,
  lg: 18,
  xl: 20,
  xxl: 24,
} as const;

export const radius = {
  button: 12,
  tile: 14,
} as const;

export const type = {
  title: { fontSize: 32, fontWeight: '700' as const, color: colors.ink },
  body: { fontSize: 17, lineHeight: 24, color: colors.body },
  label: { fontSize: 13, fontWeight: '500' as const, color: colors.muted },
  button: { fontSize: 16, fontWeight: '600' as const, color: colors.onInk },
  tile: { fontSize: 14, color: colors.ink },
} as const;
