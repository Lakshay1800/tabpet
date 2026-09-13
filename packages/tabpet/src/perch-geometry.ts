/**
 * Pure geometry for the companion perch - kept free of react-native imports
 * so the node test runner can exercise it directly.
 */
export const PERCH_SIZE = 54;
/** horizontal inset of the floating liquid-glass bar from screen edges - visually tuned against the real bar */
export const BAR_MARGIN_H = 16;
/** how far the pup intentionally trails a moving glass target, like chasing a tossed ball */
export const CHASE_TRAIL = 18;

/** left edge for the perch frame, centered over a tab slot. Prefers measured
 *  item centers, falls back to an even split minus BAR_MARGIN_H. */
export function tabCenterX(
  tab: number,
  screenWidth: number,
  slotCount: number,
  slotCenters?: readonly number[]
): number {
  const measured = slotCenters?.[tab];
  if (measured !== undefined) {
    return measured - PERCH_SIZE / 2;
  }
  return (
    BAR_MARGIN_H + (screenWidth - 2 * BAR_MARGIN_H) * ((tab + 0.5) / slotCount) - PERCH_SIZE / 2
  );
}

/** slot whose center is nearest a window-space x (a drag's release point);
 *  same center source as tabCenterX so measured and even-split bars agree */
export function nearestSlot(
  x: number,
  screenWidth: number,
  slotCount: number,
  slotCenters?: readonly number[]
): number {
  let best = 0;
  let bestDistance = Number.POSITIVE_INFINITY;
  for (let slot = 0; slot < slotCount; slot += 1) {
    const center = tabCenterX(slot, screenWidth, slotCount, slotCenters) + PERCH_SIZE / 2;
    const distance = Math.abs(x - center);
    if (distance < bestDistance) {
      best = slot;
      bestDistance = distance;
    }
  }
  return best;
}

/** translateX that centers the perch under a raw finger x, clamped to screen */
export function glassTargetX(fingerX: number, screenWidth: number): number {
  const target = fingerX - PERCH_SIZE / 2;
  return Math.min(Math.max(target, 0), screenWidth - PERCH_SIZE);
}

/** A moving glass target leads the pup rather than carrying him directly
 *  underneath; trail flips with direction, clamped to the screen. */
export function chaseTargetX(glassX: number, direction: 1 | -1, screenWidth: number): number {
  const target = glassX - direction * CHASE_TRAIL;
  return Math.min(Math.max(target, 0), screenWidth - PERCH_SIZE);
}

/** deadband under which travelFacing holds facing; must stay well under
 * CHASE_TRAIL or steady tracking would oscillate the mirror */
export const FACING_DEADBAND = 3;

/** hysteresis half-band around CHASE_TRAIL: start chasing only past
 * TRAIL+SLACK, stand down only inside TRAIL-SLACK, so a gap hovering at the
 * bare threshold doesn't flip run/idle on every pan sample */
export const CHASE_SLACK = 4;

/** Leash-follower step for live drags. Within the leash the pup holds his
 *  ground (target null) - chasing from a standstill would command retrograde
 *  motion (the "floating backward" bug). Beyond it he closes back to trailing
 *  distance, always toward the glass. `chasing` selects the hysteresis edge. */
export function chaseStep(
  glassX: number,
  currentX: number,
  currentFacing: 1 | -1,
  chasing: boolean
): { target: number | null; facing: 1 | -1 } {
  const gap = glassX - currentX;
  const threshold = chasing ? CHASE_TRAIL - CHASE_SLACK : CHASE_TRAIL + CHASE_SLACK;
  if (Math.abs(gap) <= threshold) {
    return { target: null, facing: currentFacing };
  }
  const facing: 1 | -1 = gap >= 0 ? 1 : -1;
  return { target: glassX - facing * CHASE_TRAIL, facing };
}

/** Face where the pup is actually traveling (sign of target - current), not
 *  the finger's own movement - else grabbing far from the pup turns him
 *  toward small finger wiggles (the "running backwards" bug). */
export function travelFacing(targetX: number, currentX: number, currentFacing: 1 | -1): 1 | -1 {
  const delta = targetX - currentX;
  if (Math.abs(delta) <= FACING_DEADBAND) {
    return currentFacing;
  }
  return delta >= 0 ? 1 : -1;
}

/** a handoff under one glass width reads as a catch, not a run - snap straight to seat */
export function shouldSnapToSeat(distancePt: number): boolean {
  return distancePt < PERCH_SIZE;
}

/** Tab-tap traverse speed: a committed tap runs the full distance at this
 * constant speed (not a fixed-duration spring) so a full-width tap reads as
 * a run, not a teleport - tuned for ~0.9s on a 402pt/5-slot reference screen. */
export const TRAVERSE_SPEED_PT_S = 340;
/** floor: clamps a short adjacent-tab hop to the old commitSpring's ~430ms feel instead of reading sped-up */
export const MIN_TRAVERSE_MS = 400;
/** ceiling: a very wide screen still reads as a run, not an endless slog */
export const MAX_TRAVERSE_MS = 2200;

/** Linear run duration for a tab-tap traverse of the given distance;
 * sign-independent. The floor/ceiling stretch with a profile speed override,
 * else the floor would clamp a slow animal's short hop back to the shared
 * pace and erase the slowness where it's most visible. */
export function traverseDurationMs(
  distancePt: number,
  speedPtS: number = TRAVERSE_SPEED_PT_S
): number {
  const stretch = TRAVERSE_SPEED_PT_S / speedPtS;
  const raw = (Math.abs(distancePt) / speedPtS) * 1000;
  return Math.min(MAX_TRAVERSE_MS * stretch, Math.max(MIN_TRAVERSE_MS * stretch, raw));
}

/** Pose layers scale about the cell center, so a scaled sprite's drawn feet
 * sit (PERCH_SIZE / 2 - footPad) * scale below it: the pad the perch seats
 * on. A cell-measured footPad passes through unchanged at scale 1. */
export function seatedFootPad(footPad: number, scale: number): number {
  return PERCH_SIZE / 2 - (PERCH_SIZE / 2 - footPad) * scale;
}
