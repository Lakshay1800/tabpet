/**
 * Pure pose-handoff sequencing. Pins increment 2 (pose-thrash): the unused
 * third layer is always hidden, apply-order zeros it before the incoming
 * pop, and a busy-claim cleanup must not snap idle to rest mid-dissolve.
 */
import { deepStrictEqual, ok, strictEqual } from 'node:assert';

import type { PupPose } from './pose-dissolve';
import {
  POSE_FADE_MS,
  PUP_POSES,
  planPoseDissolve,
  poseDissolveApplyOrder,
  shouldResetIncomingFrame,
  shouldSnapBusyIdleFrameToRest,
} from './pose-dissolve';

function thirdPose(previous: PupPose, next: PupPose): PupPose | null {
  if (previous === next) {
    return null;
  }
  for (const pose of PUP_POSES) {
    if (pose !== previous && pose !== next) {
      return pose;
    }
  }
  return null;
}

function assertOneOpaqueTwoNotStacked(previous: PupPose, next: PupPose): void {
  const plan = planPoseDissolve(previous, next);
  const kinds = PUP_POSES.map((pose) => plan[pose].opacity.kind);
  strictEqual(
    kinds.filter((kind) => kind === 'opaque').length,
    1,
    `${previous}→${next}: one opaque`
  );
  if (previous === next) {
    strictEqual(
      kinds.filter((kind) => kind === 'hidden').length,
      2,
      `${previous}→${next}: both others hidden`
    );
    strictEqual(kinds.filter((kind) => kind === 'fade-out').length, 0);
    return;
  }
  strictEqual(
    kinds.filter((kind) => kind === 'fade-out').length,
    1,
    `${previous}→${next}: one fade-out`
  );
  strictEqual(
    kinds.filter((kind) => kind === 'hidden').length,
    1,
    `${previous}→${next}: third hidden`
  );
  const leftover = thirdPose(previous, next);
  if (leftover === null) {
    throw new Error(`${previous}→${next} must have a third pose`);
  }
  strictEqual(plan[leftover].opacity.kind, 'hidden', `${leftover} is the hidden third layer`);
  strictEqual(plan[leftover].z, 0, `${leftover} z is 0`);
}

function testEveryPairHidesTheThirdLayer(): void {
  for (const previous of PUP_POSES) {
    for (const next of PUP_POSES) {
      assertOneOpaqueTwoNotStacked(previous, next);
    }
  }
}

function testGhostDissolveIncomingUnderOutgoing(): void {
  const plan = planPoseDissolve('idle', 'run');
  deepStrictEqual(plan.run.opacity, { kind: 'opaque' });
  strictEqual(plan.run.z, 1);
  deepStrictEqual(plan.idle.opacity, { kind: 'fade-out', durationMs: POSE_FADE_MS });
  strictEqual(plan.idle.z, 2);
  deepStrictEqual(plan.sit.opacity, { kind: 'hidden' });
  strictEqual(plan.sit.z, 0);
  strictEqual(POSE_FADE_MS, 110, 'dissolve window stays 110 ms');
}

function testRapidThrashZerosTheOriginalOutgoing(): void {
  const first = planPoseDissolve('idle', 'run');
  strictEqual(first.sit.opacity.kind, 'hidden', 'first hop: sit is the unused third');
  const second = planPoseDissolve('run', 'sit');
  strictEqual(
    second.idle.opacity.kind,
    'hidden',
    'second hop: idle (was fading) is now the third and hidden'
  );
  strictEqual(second.idle.z, 0);
  strictEqual(second.run.opacity.kind, 'fade-out');
  strictEqual(second.sit.opacity.kind, 'opaque');
}

function testSamePoseReRunHidesUnusedPair(): void {
  const plan = planPoseDissolve('run', 'run');
  strictEqual(plan.run.opacity.kind, 'opaque');
  strictEqual(plan.idle.opacity.kind, 'hidden');
  strictEqual(plan.sit.opacity.kind, 'hidden');
  strictEqual(plan.idle.z, 0);
  strictEqual(plan.sit.z, 0);
}

function testReduceMotionIsAHardCut(): void {
  const plan = planPoseDissolve('idle', 'sit', { reduceMotion: true });
  strictEqual(plan.sit.opacity.kind, 'opaque');
  strictEqual(plan.idle.opacity.kind, 'hidden');
  strictEqual(plan.run.opacity.kind, 'hidden');
}

function testApplyOrderHidesThirdBeforeIncomingPops(): void {
  const plan = planPoseDissolve('idle', 'run');
  deepStrictEqual(
    poseDissolveApplyOrder(plan),
    ['sit', 'run', 'idle'],
    'sit (hidden) applied before run (opaque) before idle (fade)'
  );
}

function testIncomingFrameResetHoldsSitIdleSeam(): void {
  ok(shouldResetIncomingFrame('idle', 'run'), 'idle→run resets the run sheet to frame 0');
  ok(shouldResetIncomingFrame('run', 'sit'), 'run→sit resets sit to frame 0');
  ok(!shouldResetIncomingFrame('sit', 'idle'), 'sit→idle holds the seam (no idle[0] snap)');
  ok(!shouldResetIncomingFrame('idle', 'idle'), 'same-pose leaves the greeting/busy frame alone');
}

function testBusyCleanupFreezesOutgoingIdle(): void {
  ok(shouldSnapBusyIdleFrameToRest('idle'), 'busy ending while still idle may snap back to rest');
  ok(
    !shouldSnapBusyIdleFrameToRest('run'),
    'busy cleanup during idle→run dissolve must freeze, not snap to idle[0]'
  );
  ok(
    !shouldSnapBusyIdleFrameToRest('sit'),
    'busy cleanup during idle→sit must freeze the outgoing idle frame'
  );
}

function main(): void {
  testEveryPairHidesTheThirdLayer();
  testGhostDissolveIncomingUnderOutgoing();
  testRapidThrashZerosTheOriginalOutgoing();
  testSamePoseReRunHidesUnusedPair();
  testReduceMotionIsAHardCut();
  testApplyOrderHidesThirdBeforeIncomingPops();
  testIncomingFrameResetHoldsSitIdleSeam();
  testBusyCleanupFreezesOutgoingIdle();
  // oxlint-disable-next-line no-console -- test runner reporting
  console.log('8 passed (pose-dissolve)');
}

main();
