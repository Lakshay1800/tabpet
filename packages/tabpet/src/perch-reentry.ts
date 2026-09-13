/**
 * Late-spring re-entry gate: Reanimated 4 physical configs can fire
 * `finished` up to ~5s after visual settle, so a stale arrive() would sit
 * the pup mid-air on a newer chase. Generation bumps on every re-entry
 * (focus, blur, new drag/catch); a late arrive applies only when its
 * captured generation is still current.
 */
export function shouldApplyArrive(args: {
  callbackGeneration: number;
  currentGeneration: number;
  mounted: boolean;
}): boolean {
  return args.mounted && args.callbackGeneration === args.currentGeneration;
}
