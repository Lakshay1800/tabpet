import TabPetCore
import XCTest

@testable import TabPetMotion

/// One controller on a five slot bar with measured centers, focused on `startSlot`.
@MainActor
private final class FingerRig {
    static let centers: [Double] = [50, 130, 210, 290, 370]
    static let screenWidth = 402.0

    let harness = Harness()
    let profile: CompanionProfile
    let pill: PillFrame?
    var controller: PerchController!
    private(set) var released: [Int] = []

    init(
        profile: CompanionProfile = makeProfile(runSpeed: 340),
        startSlot: Int = 2,
        bottomExtra: Double = 0,
        pill: PillFrame? = nil
    ) {
        self.profile = profile
        self.pill = pill
        harness.handoff.writePerchHandoff(next: PerchHandoffState(lastTab: startSlot, lastX: nil, lastSeat: bottomExtra))
        controller = harness.makeController(profile: profile, anchor: anchor(startSlot), screenWidth: Self.screenWidth, bottomExtra: bottomExtra)
        go(startSlot, bottomExtra: bottomExtra)
        controller.onDragRelease = { [weak self] slot in self?.released.append(slot) }
    }

    func anchor(_ slot: Int) -> PerchAnchor {
        PerchAnchor(slotCount: 5, slotIndex: slot, slotCenters: Self.centers, pill: pill)
    }

    func go(_ slot: Int, bottomExtra: Double = 0, isFocused: Bool = true) {
        controller.focus(anchor: anchor(slot), isFocused: isFocused, transientSlot: false, bottomExtra: bottomExtra, screenWidth: Self.screenWidth)
    }

    func seatX(_ slot: Int) -> Double {
        PerchGeometry.tabCenterX(tab: slot, screenWidth: Self.screenWidth, slotCount: 5, slotCenters: Self.centers)
    }

    var state: PerchRenderState { controller.currentState }
    var store: PerchHandoffState { harness.handoff.readPerchHandoff() }
    var perchTrackActive: Bool { harness.engine.isAnyTrackActive(labelPrefix: "perch.") }

    func finger(_ x: Double, _ phase: FingerPhase) {
        controller.handleFinger(x: x, phase: phase)
    }

    func advance(_ ms: Double, frameMs: Double = 8) {
        harness.clock.advance(ms: ms, frameMs: frameMs)
        controller.renderTick()
    }

    /// Down and one move past the engage distance, on the same slot.
    func engage(on slot: Int, by delta: Double = 40) {
        finger(Self.centers[slot], .began)
        finger(Self.centers[slot] + delta, .moved)
    }
}

@MainActor
final class PerchControllerFingerTests: XCTestCase {
    // MARK: - Engage and leash

    func testBeganThenEndedWithNoMoveChangesNothing() {
        let rig = FingerRig()
        rig.advance(50)
        let store = rig.store
        let x = rig.state.x
        let pose = rig.state.pose
        rig.finger(FingerRig.centers[2], .began)
        rig.finger(FingerRig.centers[2], .ended)
        XCTAssertEqual(rig.store, store)
        XCTAssertEqual(rig.state.x, x, accuracy: 1e-9)
        XCTAssertEqual(rig.state.pose, pose)
        XCTAssertFalse(rig.perchTrackActive)
    }

    func testAMoveOfSixPointsDoesNotEngageAndMoreDoes() {
        let rig = FingerRig()
        let start = FingerRig.centers[2]
        let store = rig.store
        rig.finger(start, .began)
        rig.finger(start + 6, .moved)
        XCTAssertEqual(rig.store, store, "6 pt is not a drag")
        XCTAssertFalse(rig.perchTrackActive)
        rig.finger(start + 6.5, .moved)
        let glass = PerchGeometry.glassTargetX(fingerX: start + 6.5, screenWidth: FingerRig.screenWidth)
        XCTAssertEqual(rig.store.lastX ?? .nan, glass, accuracy: 1e-9)
    }

    func testSamplesAcrossTheLeashEdgesFollowChaseStepAndChaseTarget() {
        let rig = FingerRig()
        var facing = rig.state.facing
        var chasing = false
        rig.finger(FingerRig.centers[2], .began)
        for fingerX in [217.0, 233, 236, 226, 205, 190, 175, 236] {
            let glass = PerchGeometry.glassTargetX(fingerX: fingerX, screenWidth: FingerRig.screenWidth)
            let before = rig.state.x
            let step = PerchGeometry.chaseStep(glassX: glass, currentX: before, currentFacing: facing, chasing: chasing)
            rig.finger(fingerX, .moved)
            if let _ = step.target {
                chasing = true
                facing = step.facing
                XCTAssertEqual(rig.state.pose, .run, "fingerX \(fingerX)")
                rig.advance(2000)
                let expected = PerchGeometry.chaseTargetX(glassX: glass, direction: step.facing, screenWidth: FingerRig.screenWidth)
                XCTAssertEqual(rig.state.x, expected, accuracy: 1e-3, "fingerX \(fingerX)")
            } else {
                chasing = false
                XCTAssertFalse(rig.perchTrackActive, "inside the leash no chase starts, fingerX \(fingerX)")
                XCTAssertEqual(rig.state.x, before, accuracy: 1e-9, "fingerX \(fingerX)")
                XCTAssertEqual(rig.state.pose, .sit, "fingerX \(fingerX)")
            }
        }
    }

    func testSoftBrakeStopsACommitChaseAtOnceAndRests() {
        let rig = FingerRig(startSlot: 0)
        rig.go(4)
        rig.advance(400)
        let live = rig.state.x
        XCTAssertEqual(rig.state.pose, .run)
        let fingerX = live + 5 + PerchGeometry.PERCH_SIZE / 2
        rig.finger(fingerX - 8, .began)
        rig.finger(fingerX, .moved)
        let stopped = rig.state.x
        XCTAssertEqual(stopped, live, accuracy: 1e-6)
        XCTAssertEqual(rig.state.pose, .sit)
        for _ in 0..<40 {
            rig.advance(8)
            XCTAssertEqual(rig.state.x, stopped, accuracy: 1e-9)
        }
    }

    func testTwoChaseSamplesInARowKeepTheSpringVelocity() {
        func deltaOverOneFrame(resample: Bool) -> Double {
            let rig = FingerRig()
            rig.finger(FingerRig.centers[2], .began)
            rig.finger(260, .moved)
            rig.advance(100)
            if resample {
                rig.finger(260, .moved)
            }
            let start = rig.state.x
            rig.advance(8)
            return rig.state.x - start
        }
        let resampled = deltaOverOneFrame(resample: true)
        let untouched = deltaOverOneFrame(resample: false)
        XCTAssertGreaterThan(resampled, 0)
        XCTAssertEqual(resampled, untouched, accuracy: untouched * 0.25, "the second spring inherits the first one's speed")
    }

    func testARaisedSeatDropsToBarLevelOnAnEngagedSample() {
        let rig = FingerRig(bottomExtra: 24)
        XCTAssertEqual(rig.state.seatY, 0, accuracy: 1e-9)
        rig.engage(on: 2)
        rig.advance(100)
        XCTAssertGreaterThan(rig.state.seatY, 0)
        rig.advance(1500)
        XCTAssertEqual(rig.state.seatY, 24, accuracy: 0.05)
    }

    func testTheStoreKeepsTheGlassTargetWhileDragging() {
        let rig = FingerRig()
        rig.engage(on: 2, by: 55)
        let glass = PerchGeometry.glassTargetX(fingerX: FingerRig.centers[2] + 55, screenWidth: FingerRig.screenWidth)
        XCTAssertEqual(rig.store.lastX ?? .nan, glass, accuracy: 1e-9)
        XCTAssertEqual(rig.store.lastSeat, 0, accuracy: 1e-9)
    }

    func testTheFingerStopsAndTheLastSpringRestsThePose() {
        let rig = FingerRig()
        rig.engage(on: 2, by: 60)
        XCTAssertEqual(rig.state.pose, .run)
        rig.advance(2000)
        XCTAssertEqual(rig.state.pose, .sit)
        XCTAssertFalse(rig.harness.clock.wantsFrames)
    }

    func testEachFingerCallEmitsAtMostOneRenderState() {
        let rig = FingerRig()
        for (x, phase) in [(210.0, FingerPhase.began), (250, .moved), (270, .moved), (270, .ended)] {
            let before = rig.harness.renderStateCount
            rig.finger(x, phase)
            XCTAssertLessThanOrEqual(rig.harness.renderStateCount - before, 1, "\(phase)")
        }
    }

    // MARK: - Far approach

    private struct FarSetup {
        let rig: FingerRig
        let target: Double
        let startX: Double
    }

    /// Animal on the last slot, finger down on the first, engaged.
    private func farEngaged(profile: CompanionProfile = makeProfile(runSpeed: 340)) -> FarSetup {
        let rig = FingerRig(profile: profile, startSlot: 4)
        let startX = rig.state.x
        rig.finger(FingerRig.centers[0], .began)
        rig.finger(FingerRig.centers[0] + 7, .moved)
        let glass = PerchGeometry.glassTargetX(fingerX: FingerRig.centers[0] + 7, screenWidth: FingerRig.screenWidth)
        let target = PerchGeometry.chaseTargetX(glassX: glass, direction: .left, screenWidth: FingerRig.screenWidth)
        return FarSetup(rig: rig, target: target, startX: startX)
    }

    func testFarApproachRunsAtTheRunSpeedAndTheFirstTickStandsStill() {
        let setup = farEngaged()
        let rig = setup.rig
        XCTAssertEqual(rig.state.pose, .run)
        XCTAssertEqual(rig.state.facing, .left)
        XCTAssertEqual(rig.state.x, setup.startX, accuracy: 1e-9, "the engage frame does not move x")
        var x = setup.startX
        for _ in 0..<10 {
            rig.advance(8, frameMs: 8)
            let expected = PerchHandoff.stepToward(current: x, target: setup.target, speedPtS: 340, dtMs: 8).x
            XCTAssertEqual(rig.state.x, expected, accuracy: 1e-9)
            XCTAssertEqual(x - rig.state.x, 340 * 8 / 1000, accuracy: 1e-9)
            x = rig.state.x
        }
    }

    func testAFrameGapOf200msMovesAtMost34msWorth() {
        let setup = farEngaged()
        setup.rig.advance(200, frameMs: 200)
        let moved = setup.startX - setup.rig.state.x
        XCTAssertGreaterThan(moved, 0)
        XCTAssertLessThanOrEqual(moved, 340 * 34 / 1000 + 1e-9)
    }

    func testAStillFingerLetsTheApproachArriveAndRest() {
        let setup = farEngaged()
        setup.rig.advance(3000)
        XCTAssertEqual(setup.rig.state.x, setup.target, accuracy: 1e-9)
        XCTAssertEqual(setup.rig.state.pose, .sit)
        XCTAssertFalse(setup.rig.harness.clock.wantsFrames)
        XCTAssertFalse(setup.rig.perchTrackActive)
    }

    func testSamplesDuringTheApproachOnlyMoveTheTargetWithNoPause() {
        let setup = farEngaged()
        let rig = setup.rig
        var x = setup.startX
        var elapsed = 0.0
        let fingerXs = [57.0, 60, 58, 62, 59, 64]
        for tick in 0..<50 {
            if tick % 5 == 0 {
                rig.finger(fingerXs[(tick / 5) % fingerXs.count], .moved)
            }
            rig.advance(8)
            elapsed += 8
            XCTAssertEqual(x - rig.state.x, 340 * 8 / 1000, accuracy: 1e-9, "tick \(tick)")
            x = rig.state.x
        }
        XCTAssertEqual(setup.startX - rig.state.x, 340 * elapsed / 1000, accuracy: 1e-6)
    }

    func testASampleInsideTheLeashEndsTheApproachAndRests() {
        let setup = farEngaged()
        let rig = setup.rig
        rig.advance(80)
        let live = rig.state.x
        rig.finger(live + 10 + PerchGeometry.PERCH_SIZE / 2, .moved)
        XCTAssertEqual(rig.state.pose, .sit)
        XCTAssertEqual(rig.state.x, live, accuracy: 1e-9)
        rig.advance(500)
        XCTAssertEqual(rig.state.x, live, accuracy: 1e-9)
        XCTAssertFalse(rig.harness.clock.wantsFrames)
    }

    func testANonFiniteSampleDuringTheApproachChangesNothing() {
        let setup = farEngaged()
        let rig = setup.rig
        rig.advance(80)
        let renders = rig.harness.renderStateCount
        let store = rig.store
        rig.finger(.nan, .moved)
        XCTAssertEqual(rig.harness.renderStateCount, renders)
        XCTAssertEqual(rig.store, store)
        let x = rig.state.x
        rig.advance(8)
        XCTAssertEqual(x - rig.state.x, 340 * 8 / 1000, accuracy: 1e-9)
        rig.advance(3000)
        XCTAssertEqual(rig.state.x, setup.target, accuracy: 1e-9)
        XCTAssertEqual(rig.state.pose, .sit)
    }

    func testAFarApproachAnimationIsNotCutShortAtItsStartByTheTrackShortcut() {
        let clock = ManualClock()
        let engine = MotionEngine(clock: clock)
        let track = engine.makeTrack(label: "t", initialValue: 10)
        let animation = FarApproachAnimation(toValue: 10, speedPtS: 100)
        var completions: [Bool] = []
        engine.start(track, animation) { completions.append($0) }
        // Arrived on the synchronous first frame, not skipped before it.
        XCTAssertEqual(completions, [true])
        let second = engine.makeTrack(label: "u", initialValue: 0)
        let follower = FarApproachAnimation(toValue: 20, speedPtS: 100)
        engine.start(second, follower)
        follower.retarget(10)
        clock.advance(ms: 300, frameMs: 10)
        XCTAssertEqual(second.currentValue, 10, accuracy: 1e-9)
        XCTAssertFalse(second.isActive)
    }

    // MARK: - Release and timer

    func testEndedOnTheOwnSlotGoesHome() {
        let rig = FingerRig(bottomExtra: 24)
        rig.engage(on: 2, by: 30)
        rig.advance(600)
        rig.finger(0, .ended)
        rig.advance(3000)
        XCTAssertEqual(rig.state.x, rig.seatX(2), accuracy: 1e-3)
        XCTAssertEqual(rig.state.seatY, 0, accuracy: 1e-3)
        XCTAssertEqual(rig.state.pose, .sit)
        XCTAssertEqual(rig.store.lastTab, 2)
    }

    func testCancelledOverAnotherSlotGoesHomeAndNeverReports() {
        let rig = FingerRig()
        rig.controller.barScrub = .exclusive
        rig.engage(on: 2, by: 80)
        rig.advance(1500)
        rig.finger(0, .cancelled)
        rig.advance(700)
        XCTAssertEqual(rig.state.x, rig.seatX(2), accuracy: 1e-3)
        XCTAssertEqual(rig.released, [])
    }

    func testExclusiveEndedOverAnotherSlotReportsOnceAndApproachesThatSlot() {
        let rig = FingerRig(bottomExtra: 24)
        rig.controller.barScrub = .exclusive
        rig.engage(on: 2, by: 80)
        rig.advance(1500)
        rig.finger(0, .ended)
        XCTAssertEqual(rig.released, [3])
        rig.advance(600)
        XCTAssertEqual(rig.state.x, rig.seatX(3), accuracy: 0.5)
        XCTAssertEqual(rig.state.seatY, 24, accuracy: 0.05, "stays at bar level")
    }

    func testNativeWithAMeasuredPillAndNoAnchorPillWaitsOnTheSlot() {
        let rig = FingerRig()
        rig.harness.measureResult = BarLayout(centers: FingerRig.centers, pill: PillFrame(x: 16, y: 760, width: 370, height: 62))
        rig.engage(on: 2, by: 80)
        rig.advance(1500)
        rig.finger(0, .ended)
        rig.advance(600)
        XCTAssertEqual(rig.state.x, rig.seatX(3), accuracy: 0.5)
        XCTAssertEqual(rig.released, [])
    }

    func testNativeWithoutAPillGoesHome() {
        let rig = FingerRig()
        rig.engage(on: 2, by: 80)
        rig.advance(1500)
        rig.finger(0, .ended)
        rig.advance(700)
        XCTAssertEqual(rig.state.x, rig.seatX(2), accuracy: 1e-3)
    }

    func testNativeWithAnAnchorPillAndNoneMeasuredGoesHome() {
        let rig = FingerRig(pill: PillFrame(x: 16, y: 760, width: 370, height: 62))
        rig.harness.measureResult = nil
        rig.engage(on: 2, by: 80)
        rig.advance(1500)
        rig.finger(0, .ended)
        rig.advance(700)
        XCTAssertEqual(rig.state.x, rig.seatX(2), accuracy: 1e-3)
    }

    /// Exclusive drag from slot 2 released over slot 3, settled, then waiting.
    private func waitingNear() -> FingerRig {
        let rig = FingerRig()
        rig.controller.barScrub = .exclusive
        rig.engage(on: 2, by: 80)
        rig.advance(1500)
        rig.finger(0, .ended)
        return rig
    }

    func testNothingSelectsSoTheAnimalGoesHomeAt800msNotBefore() {
        let rig = waitingNear()
        rig.advance(799, frameMs: 1)
        XCTAssertEqual(rig.state.x, rig.seatX(3), accuracy: 0.5)
        XCTAssertNotEqual(rig.state.pose, .run)
        rig.advance(1, frameMs: 1)
        XCTAssertEqual(rig.state.pose, .run, "the timer sent it home")
        rig.advance(3000)
        XCTAssertEqual(rig.state.x, rig.seatX(2), accuracy: 1e-3)
    }

    /// Exclusive drag from slot 0 released over slot 4 at once: a long run.
    private func waitingFar() -> FingerRig {
        let rig = FingerRig(startSlot: 0)
        rig.controller.barScrub = .exclusive
        rig.finger(FingerRig.centers[0], .began)
        rig.finger(FingerRig.centers[4], .moved)
        rig.finger(0, .ended)
        return rig
    }

    func testAFocusOnTheAwaitedSlotAt799msCatchesFromTheLiveXAndNothingGoesHome() {
        let rig = waitingFar()
        XCTAssertEqual(rig.released, [4])
        rig.advance(799, frameMs: 1)
        let live = rig.state.x
        XCTAssertGreaterThan(live, rig.seatX(0) + 100)
        XCTAssertLessThan(live, rig.seatX(4) - 20)
        rig.go(4)
        XCTAssertEqual(rig.state.x, live, accuracy: 1e-6)
        XCTAssertEqual(rig.state.pose, .run)
        var previous = live
        for _ in 0..<400 {
            rig.advance(8)
            XCTAssertGreaterThanOrEqual(rig.state.x, previous - 0.5, "never turns back home")
            previous = rig.state.x
        }
        XCTAssertEqual(rig.state.x, rig.seatX(4), accuracy: 1e-3)
        XCTAssertEqual(rig.state.pose, .sit)
    }

    func testTheTimerFiringWhileUnmountedDropsThePendingRelease() {
        let rig = waitingFar()
        rig.advance(799, frameMs: 1)
        rig.harness.mountedFlag = false
        rig.advance(1, frameMs: 1)
        rig.harness.mountedFlag = true
        XCTAssertNil(rig.controller.debugReleaseState.pending)
        rig.go(4)
        let atFocus = rig.state.x
        rig.advance(30, frameMs: 1)
        XCTAssertEqual(rig.state.x, atFocus, accuracy: 1e-9, "an ordinary chase, with its reaction pause, not an arrival")
        rig.advance(4000)
        XCTAssertEqual(rig.state.x, rig.seatX(4), accuracy: 1e-3)
        XCTAssertEqual(rig.state.pose, .sit)
    }

    func testABeganAndTapWhileWaitingKeepsTheApproachAndTheTimer() {
        let rig = waitingNear()
        rig.advance(100)
        rig.finger(FingerRig.centers[3], .began)
        rig.finger(FingerRig.centers[3], .ended)
        rig.advance(300)
        XCTAssertEqual(rig.state.x, rig.seatX(3), accuracy: 0.5)
        XCTAssertEqual(rig.state.pose, .sit, "the approach still ends in the rest pose")
        rig.advance(500, frameMs: 1)
        XCTAssertEqual(rig.state.pose, .run, "the timer still fired")
    }

    func testEngagingWhileWaitingClearsTheTimer() {
        let rig = waitingNear()
        rig.advance(300)
        rig.finger(FingerRig.centers[3], .began)
        rig.finger(FingerRig.centers[3] + 40, .moved)
        XCTAssertNil(rig.controller.debugReleaseState.pending)
        rig.advance(2000)
        let expected = PerchGeometry.chaseTargetX(
            glassX: PerchGeometry.glassTargetX(fingerX: FingerRig.centers[3] + 40, screenWidth: FingerRig.screenWidth),
            direction: .right,
            screenWidth: FingerRig.screenWidth
        )
        XCTAssertEqual(rig.state.x, expected, accuracy: 1e-3, "nothing sent it home")
    }

    func testAHostThatSelectsInsideOnDragReleaseStillGetsTheArrivalCatch() {
        let rig = FingerRig()
        rig.controller.barScrub = .exclusive
        rig.controller.onDragRelease = { [weak rig] slot in rig?.go(slot) }
        rig.engage(on: 2, by: 80)
        rig.advance(1500)
        rig.finger(0, .ended)
        rig.advance(3000)
        XCTAssertEqual(rig.state.x, rig.seatX(3), accuracy: 1e-3)
        XCTAssertEqual(rig.state.pose, .sit)
    }

    // MARK: - Gates

    func testABeganDuringACommitChaseKeepsItRunningAndItsArrivalStaysStale() {
        let rig = FingerRig(startSlot: 0)
        rig.go(4)
        rig.advance(200)
        rig.finger(FingerRig.centers[1], .began)
        let x = rig.state.x
        rig.advance(300)
        XCTAssertGreaterThan(rig.state.x, x)
        rig.advance(5000)
        XCTAssertEqual(rig.state.x, rig.seatX(4), accuracy: 1e-3)
        XCTAssertEqual(rig.state.pose, .run)
    }

    func testABeganDuringAnAroundRouteStopsItAndZeroesTheRotation() {
        let pill = PillFrame(x: 16, y: 760, width: 370, height: 62)
        let rig = FingerRig(profile: makeProfile(aroundRoute: true), startSlot: 0, pill: pill)
        rig.go(4)
        var found = false
        for _ in 0..<400 where !found {
            rig.advance(8)
            found = rig.state.rotationDegrees != 0
        }
        XCTAssertTrue(found, "sanity: the route turns the animal")
        rig.finger(FingerRig.centers[1], .began)
        XCTAssertEqual(rig.state.rotationDegrees, 0, accuracy: 1e-9)
        let frozen = rig.state
        rig.advance(500)
        XCTAssertEqual(rig.state.rotationDegrees, 0, accuracy: 1e-9)
        XCTAssertEqual(rig.state.x, frozen.x, accuracy: 1e-9)
        XCTAssertEqual(rig.state.seatY, 0, accuracy: 1e-3, "seatY springs back to bar level")
    }

    private func assertIgnoresAFullDrag(_ rig: FingerRig, file: StaticString = #filePath, line: UInt = #line) {
        let store = rig.store
        let x = rig.state.x
        let pose = rig.state.pose
        rig.finger(FingerRig.centers[0], .began)
        rig.finger(FingerRig.centers[0] + 40, .moved)
        rig.advance(300)
        rig.finger(0, .ended)
        rig.advance(300)
        XCTAssertEqual(rig.store, store, file: file, line: line)
        XCTAssertEqual(rig.state.x, x, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(rig.state.pose, pose, file: file, line: line)
    }

    func testReduceMotionIgnoresTheFinger() {
        let rig = FingerRig(startSlot: 4)
        rig.harness.reduceMotionFlag = true
        assertIgnoresAFullDrag(rig)
    }

    func testATransientSlotIgnoresTheFinger() {
        let rig = FingerRig(startSlot: 4)
        rig.controller.focus(anchor: rig.anchor(4), transientSlot: true, bottomExtra: 0, screenWidth: FingerRig.screenWidth)
        assertIgnoresAFullDrag(rig)
    }

    func testNoActiveFocusIgnoresTheFinger() {
        let rig = FingerRig(startSlot: 4)
        rig.go(4, isFocused: false)
        assertIgnoresAFullDrag(rig)
    }

    func testABlurMidDragStopsTheApproachAndALaterEndedChangesNothing() {
        let setup = farEngaged()
        let rig = setup.rig
        rig.advance(80)
        rig.go(4, isFocused: false)
        XCTAssertFalse(rig.perchTrackActive)
        let frozen = rig.state.x
        rig.advance(1000)
        XCTAssertEqual(rig.state.x, frozen, accuracy: 1e-9)
        let store = rig.store
        rig.finger(0, .ended)
        XCTAssertEqual(rig.store, store)
        rig.go(4)
        rig.finger(0, .ended)
        XCTAssertEqual(rig.store.lastTab, store.lastTab, "not a drag any more, a tap")
    }

    func testABusyEdgeDuringADragLeavesThePoseAndTheRestIsIdle() {
        let rig = FingerRig()
        rig.engage(on: 2, by: 60)
        XCTAssertEqual(rig.state.pose, .run)
        let release = rig.harness.busy.beginCompanionBusy()
        XCTAssertEqual(rig.state.pose, .run)
        XCTAssertTrue(rig.state.busy)
        rig.advance(2000)
        XCTAssertEqual(rig.state.pose, .idle)
        release()
    }

    func testTeardownWhileWaitingCancelsTheTimerAndEveryTrack() {
        let rig = waitingFar()
        rig.advance(100)
        rig.controller.teardown()
        XCTAssertFalse(rig.perchTrackActive)
        XCTAssertNil(rig.controller.debugReleaseState.pending)
        let renders = rig.harness.renderStateCount
        rig.harness.clock.advance(ms: 2000, frameMs: 8)
        XCTAssertEqual(rig.harness.renderStateCount, renders, "the grace timer never fired")
    }

    // MARK: - Reset and recovery

    func testResetFingerMidDragCancelsTheChaseAndRests() {
        let rig = FingerRig()
        rig.engage(on: 2, by: 60)
        rig.controller.resetFinger()
        XCTAssertEqual(rig.state.pose, .sit)
        let x = rig.state.x
        rig.advance(500)
        XCTAssertEqual(rig.state.x, x, accuracy: 1e-9)
        let store = rig.store
        rig.finger(0, .ended)
        XCTAssertEqual(rig.store, store, "the drag is gone, so an ended is a tap")
    }

    func testResetFingerLeavesAReleaseApproachAndItsTimerAlone() {
        let rig = waitingNear()
        rig.controller.resetFinger()
        XCTAssertNotNil(rig.controller.debugReleaseState.pending)
        rig.advance(800, frameMs: 1)
        XCTAssertEqual(rig.state.pose, .run, "the timer still sent it home")
    }
}
