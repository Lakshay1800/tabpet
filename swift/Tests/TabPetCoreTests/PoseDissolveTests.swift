import XCTest

import TabPetCore

/// Mirrors pose-dissolve.test.ts. Pins increment 2 (pose-thrash): the unused
/// third layer is always hidden, apply-order zeros it before the incoming
/// pop, and a busy-claim cleanup must not snap idle to rest mid-dissolve.
final class PoseDissolveTests: XCTestCase {
    private func thirdPose(_ previous: PupPose, _ next: PupPose) -> PupPose? {
        if previous == next {
            return nil
        }
        return PoseDissolve.PUP_POSES.first { $0 != previous && $0 != next }
    }

    private func assertOneOpaqueTwoNotStacked(_ previous: PupPose, _ next: PupPose) {
        let plan = PoseDissolve.planPoseDissolve(previous: previous, next: next)
        let kinds = PoseDissolve.PUP_POSES.map { plan[$0].opacity }
        XCTAssertEqual(
            kinds.filter { if case .opaque = $0 { return true } else { return false } }.count,
            1,
            "\(previous)→\(next): one opaque"
        )
        if previous == next {
            XCTAssertEqual(
                kinds.filter { if case .hidden = $0 { return true } else { return false } }.count,
                2,
                "\(previous)→\(next): both others hidden"
            )
            XCTAssertEqual(kinds.filter { if case .fadeOut = $0 { return true } else { return false } }.count, 0)
            return
        }
        XCTAssertEqual(
            kinds.filter { if case .fadeOut = $0 { return true } else { return false } }.count,
            1,
            "\(previous)→\(next): one fade-out"
        )
        XCTAssertEqual(
            kinds.filter { if case .hidden = $0 { return true } else { return false } }.count,
            1,
            "\(previous)→\(next): third hidden"
        )
        guard let leftover = thirdPose(previous, next) else {
            XCTFail("\(previous)→\(next) must have a third pose")
            return
        }
        XCTAssertEqual(plan[leftover].opacity, .hidden, "\(leftover) is the hidden third layer")
        XCTAssertEqual(plan[leftover].z, 0, "\(leftover) z is 0")
    }

    func testEveryPairHidesTheThirdLayer() {
        for previous in PoseDissolve.PUP_POSES {
            for next in PoseDissolve.PUP_POSES {
                assertOneOpaqueTwoNotStacked(previous, next)
            }
        }
    }

    func testGhostDissolveIncomingUnderOutgoing() {
        let plan = PoseDissolve.planPoseDissolve(previous: .idle, next: .run)
        XCTAssertEqual(plan.run.opacity, .opaque)
        XCTAssertEqual(plan.run.z, 1)
        XCTAssertEqual(plan.idle.opacity, .fadeOut(durationMs: PoseDissolve.POSE_FADE_MS))
        XCTAssertEqual(plan.idle.z, 2)
        XCTAssertEqual(plan.sit.opacity, .hidden)
        XCTAssertEqual(plan.sit.z, 0)
        XCTAssertEqual(PoseDissolve.POSE_FADE_MS, 110, "dissolve window stays 110 ms")
    }

    func testRapidThrashZerosTheOriginalOutgoing() {
        let first = PoseDissolve.planPoseDissolve(previous: .idle, next: .run)
        XCTAssertEqual(first.sit.opacity, .hidden, "first hop: sit is the unused third")
        let second = PoseDissolve.planPoseDissolve(previous: .run, next: .sit)
        XCTAssertEqual(
            second.idle.opacity,
            .hidden,
            "second hop: idle (was fading) is now the third and hidden"
        )
        XCTAssertEqual(second.idle.z, 0)
        if case .fadeOut = second.run.opacity {} else {
            XCTFail("run should be fade-out")
        }
        XCTAssertEqual(second.sit.opacity, .opaque)
    }

    func testSamePoseReRunHidesUnusedPair() {
        let plan = PoseDissolve.planPoseDissolve(previous: .run, next: .run)
        XCTAssertEqual(plan.run.opacity, .opaque)
        XCTAssertEqual(plan.idle.opacity, .hidden)
        XCTAssertEqual(plan.sit.opacity, .hidden)
        XCTAssertEqual(plan.idle.z, 0)
        XCTAssertEqual(plan.sit.z, 0)
    }

    func testReduceMotionIsAHardCut() {
        let plan = PoseDissolve.planPoseDissolve(previous: .idle, next: .sit, reduceMotion: true)
        XCTAssertEqual(plan.sit.opacity, .opaque)
        XCTAssertEqual(plan.idle.opacity, .hidden)
        XCTAssertEqual(plan.run.opacity, .hidden)
    }

    func testApplyOrderHidesThirdBeforeIncomingPops() {
        let plan = PoseDissolve.planPoseDissolve(previous: .idle, next: .run)
        XCTAssertEqual(
            PoseDissolve.poseDissolveApplyOrder(plan: plan),
            [.sit, .run, .idle],
            "sit (hidden) applied before run (opaque) before idle (fade)"
        )
    }

    func testIncomingFrameResetHoldsSitIdleSeam() {
        XCTAssertTrue(PoseDissolve.shouldResetIncomingFrame(previous: .idle, next: .run), "idle→run resets the run sheet to frame 0")
        XCTAssertTrue(PoseDissolve.shouldResetIncomingFrame(previous: .run, next: .sit), "run→sit resets sit to frame 0")
        XCTAssertFalse(PoseDissolve.shouldResetIncomingFrame(previous: .sit, next: .idle), "sit→idle holds the seam (no idle[0] snap)")
        XCTAssertFalse(PoseDissolve.shouldResetIncomingFrame(previous: .idle, next: .idle), "same-pose leaves the greeting/busy frame alone")
    }

    func testBusyCleanupFreezesOutgoingIdle() {
        XCTAssertTrue(PoseDissolve.shouldSnapBusyIdleFrameToRest(currentPose: .idle), "busy ending while still idle may snap back to rest")
        XCTAssertFalse(
            PoseDissolve.shouldSnapBusyIdleFrameToRest(currentPose: .run),
            "busy cleanup during idle→run dissolve must freeze, not snap to idle[0]"
        )
        XCTAssertFalse(
            PoseDissolve.shouldSnapBusyIdleFrameToRest(currentPose: .sit),
            "busy cleanup during idle→sit must freeze the outgoing idle frame"
        )
    }
}
