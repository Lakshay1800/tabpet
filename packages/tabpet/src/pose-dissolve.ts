/**
 * Pure pose-handoff planner for the companion sprite. Ghost dissolve:
 * incoming goes fully opaque underneath, outgoing fades on top over
 * POSE_FADE_MS, and the unused third layer hides first so a rapid
 * idle -> run -> sit can't stack three sheets.
 */
export type PupPose = 'idle' | 'run' | 'sit';

export const PUP_POSES: readonly PupPose[] = ['idle', 'run', 'sit'];
export const POSE_FADE_MS = 110;

type PoseOpacityKind =
  | { kind: 'hidden' }
  | { kind: 'opaque' }
  | { kind: 'fade-out'; durationMs: number };

interface PoseLayerAssignment {
  opacity: PoseOpacityKind;
  z: number;
}

export type PoseDissolvePlan = Record<PupPose, PoseLayerAssignment>;

/** Hard cut for reduce-motion and same-pose re-runs: one opaque layer, the
 * other two hidden - else a mid-fade leftover can stack as a third sheet. */
function hardCut(next: PupPose): PoseDissolvePlan {
  return {
    idle: { opacity: { kind: next === 'idle' ? 'opaque' : 'hidden' }, z: next === 'idle' ? 1 : 0 },
    run: { opacity: { kind: next === 'run' ? 'opaque' : 'hidden' }, z: next === 'run' ? 1 : 0 },
    sit: { opacity: { kind: next === 'sit' ? 'opaque' : 'hidden' }, z: next === 'sit' ? 1 : 0 },
  };
}

function assignmentFor(pose: PupPose, previous: PupPose, next: PupPose): PoseLayerAssignment {
  if (pose === next) {
    return { opacity: { kind: 'opaque' }, z: 1 };
  }
  if (pose === previous) {
    return { opacity: { kind: 'fade-out', durationMs: POSE_FADE_MS }, z: 2 };
  }
  return { opacity: { kind: 'hidden' }, z: 0 };
}

export function planPoseDissolve(
  previous: PupPose,
  next: PupPose,
  opts: { reduceMotion?: boolean } = {}
): PoseDissolvePlan {
  if (opts.reduceMotion === true || previous === next) {
    return hardCut(next);
  }
  return {
    idle: assignmentFor('idle', previous, next),
    run: assignmentFor('run', previous, next),
    sit: assignmentFor('sit', previous, next),
  };
}

/** Hidden first, then incoming opaque, then outgoing fade - never pop the
 *  incoming sheet while a leftover third layer is still non-zero. */
export function poseDissolveApplyOrder(plan: PoseDissolvePlan): PupPose[] {
  const hidden: PupPose[] = [];
  const opaque: PupPose[] = [];
  const fadeOut: PupPose[] = [];
  for (const pose of PUP_POSES) {
    const { kind } = plan[pose].opacity;
    if (kind === 'hidden') {
      hidden.push(pose);
    } else if (kind === 'opaque') {
      opaque.push(pose);
    } else {
      fadeOut.push(pose);
    }
  }
  return [...hidden, ...opaque, ...fadeOut];
}

/** sit→idle holds the seam (idle[0] == sit last). Every other incoming pose
 *  resets to frame 0. Same-pose leaves frames alone (greeting / busy loop). */
export function shouldResetIncomingFrame(previous: PupPose, next: PupPose): boolean {
  if (previous === next) {
    return false;
  }
  return !(next === 'idle' && previous === 'sit');
}

/** Only snap idle to rest while still seated at idle - snapping to idle[0]
 *  while it's the top dissolve layer is the wrong-sheet flash. */
export function shouldSnapBusyIdleFrameToRest(currentPose: PupPose): boolean {
  return currentPose === 'idle';
}
