import TabPetCore
import XCTest

@testable import TabPetMotion

/// Bundles a fresh `ManualClock`/`MotionEngine`/`PerchHandoffStore`/
/// `CompanionState` and controllable `mounted`/`measure`/`reduceMotion`
/// closures, so each test only states what it changes from the defaults.
@MainActor
private final class Harness {
    let clock = ManualClock()
    let engine: MotionEngine
    let handoff = PerchHandoffStore()
    let busy = CompanionState()

    var mountedFlag = true
    var reduceMotionFlag = false
    var measureResult: BarLayout?

    private(set) var renderStates: [PerchRenderState] = []
    private(set) var errors: [(MotionError, String)] = []
    var renderStateCount: Int { renderStates.count }

    init() {
        engine = MotionEngine(clock: clock)
    }

    func makeController(
        profile: CompanionProfile,
        anchor: PerchAnchor,
        screenWidth: Double = 402,
        transientSlot: Bool = false,
        bottomExtra: Double = 0
    ) -> PerchController {
        let controller = PerchController(
            profile: profile,
            anchor: anchor,
            transientSlot: transientSlot,
            bottomExtra: bottomExtra,
            screenWidth: screenWidth,
            mounted: { [weak self] in self?.mountedFlag ?? false },
            measure: { [weak self] in self?.measureResult },
            reduceMotion: { [weak self] in self?.reduceMotionFlag ?? false },
            clock: clock,
            engine: engine,
            handoff: handoff,
            busy: busy,
            onError: { [weak self] error, site in self?.errors.append((error, site)) }
        )
        controller.onRenderState = { [weak self] state in self?.renderStates.append(state) }
        // The harness stands in for an always-mounted host: real callers
        // activate this on window entry.
        controller.activateBusyTracking()
        return controller
    }
}

@MainActor
private func makeProfile(
    hopHeight: Double = -6,
    flightLift: Double = 0,
    runSpeed: Double? = nil,
    scale: Double = 1,
    footPad: Double? = nil,
    seatLift: Double? = nil,
    aroundRoute: Bool = false,
    commitSpring: TabPetCore.SpringConfig = TabPetCore.SpringConfig(duration: 560, dampingRatio: 0.86),
    trackSpring: TabPetCore.SpringConfig = TabPetCore.SpringConfig(duration: 300, dampingRatio: 0.9),
    catchSpring: TabPetCore.SpringConfig = TabPetCore.SpringConfig(duration: 260, dampingRatio: 0.9)
) -> CompanionProfile {
    CompanionProfile(
        id: "testAnimal",
        label: "test animal",
        runFps: 12,
        commitSpring: commitSpring,
        trackSpring: trackSpring,
        catchSpring: catchSpring,
        hopHeight: hopHeight,
        flightLift: flightLift,
        scale: scale,
        aroundRoute: aroundRoute,
        footPad: footPad,
        seatLift: seatLift,
        runSpeed: runSpeed
    )
}

@MainActor
final class PerchControllerTests: XCTestCase {
    // MARK: - Seat on mount

    func testSeatOnMount_FirstCommitMatchesPlanMountSeatYWithNoTrackAndAnIdleLink() {
        let harness = Harness()
        let seededHandoff = PerchHandoffState(lastTab: 2, lastX: 120, lastSeat: 24)
        harness.handoff.writePerchHandoff(next: seededHandoff)
        let anchor = PerchAnchor(slotCount: 5, slotIndex: 2)
        let screenWidth = 402.0

        let controller = harness.makeController(profile: makeProfile(), anchor: anchor, screenWidth: screenWidth, bottomExtra: 0)

        let expectedSeatY = PerchHandoff.planMountSeatY(
            handoff: seededHandoff,
            tab: 2,
            screenWidth: screenWidth,
            bottomExtra: 0,
            transientSlot: false,
            reduceMotion: false,
            slotCount: 5
        )
        XCTAssertEqual(controller.currentState.seatY, expectedSeatY, accuracy: 1e-9)
        XCTAssertFalse(harness.clock.wantsFrames, "no track started at mount - the link stays idle")
        // onRenderState fires from inside init(), before any caller can
        // assign the callback property - `currentState` (checked above) is
        // the observable proof for this first commit.
    }

    // MARK: - Plain run-chase formula and the 65ms reaction pause

    func testPlainRunChase_LinearFormulaAfterA65msReactionPause() {
        let harness = Harness()
        let profile = makeProfile(runSpeed: 340)
        let screenWidth = 402.0
        let controller = harness.makeController(profile: profile, anchor: PerchAnchor(slotCount: 5, slotIndex: 0), screenWidth: screenWidth)
        controller.focus(anchor: PerchAnchor(slotCount: 5, slotIndex: 0), transientSlot: false, bottomExtra: 0, screenWidth: screenWidth)

        controller.focus(anchor: PerchAnchor(slotCount: 5, slotIndex: 4), transientSlot: false, bottomExtra: 0, screenWidth: screenWidth)

        let fromX = PerchGeometry.tabCenterX(tab: 0, screenWidth: screenWidth, slotCount: 5)
        let targetX = PerchGeometry.tabCenterX(tab: 4, screenWidth: screenWidth, slotCount: 5)
        let distance = abs(targetX - fromX)
        let runMs = PerchGeometry.traverseDurationMs(distancePt: distance, speedPtS: 340)

        XCTAssertEqual(controller.currentState.pose, .run)

        // unchanged through t=64 (still inside the reaction pause).
        harness.clock.advance(ms: 64, frameMs: 1)
        controller.renderTick()
        XCTAssertEqual(controller.currentState.x, fromX, accuracy: 1e-6, "x unchanged through t=64 on a fresh chase")

        var t = harness.clock.now
        while t < 65 + runMs - 10 {
            let step = max(20.0, runMs / 8)
            harness.clock.advance(ms: step, frameMs: 1)
            t = harness.clock.now
            controller.renderTick()
            let expectedX = fromX + (targetX - fromX) * (t - 65) / runMs
            XCTAssertEqual(controller.currentState.x, expectedX, accuracy: 1e-3, "t=\(t)")
        }

        harness.clock.advance(ms: 2000, frameMs: 1)
        controller.renderTick()
        XCTAssertEqual(controller.currentState.x, targetX, accuracy: 1e-6, "arrived")
        XCTAssertEqual(controller.currentState.pose, .sit, "arrival rests")
        XCTAssertFalse(harness.clock.wantsFrames, "nothing left for this controller's own tracks to animate")
    }

    /// arrivedByDrag skips the reaction pause entirely - x moves on the very
    /// first tick, not after 65ms.
    func testArrivedByDragSkipsTheReactionPause() {
        let harness = Harness()
        let profile = makeProfile(runSpeed: 340)
        let screenWidth = 402.0
        let controller = harness.makeController(profile: profile, anchor: PerchAnchor(slotCount: 5, slotIndex: 0), screenWidth: screenWidth)
        controller.focus(anchor: PerchAnchor(slotCount: 5, slotIndex: 0), transientSlot: false, bottomExtra: 0, screenWidth: screenWidth)

        // Seed a pending release that this focus will consume as an arrival.
        controller.debugReleaseState = ReleaseState(pending: ReleaseState.Pending(fromSlot: 0, slot: 0, generation: 0), arrival: false)
        controller.focus(anchor: PerchAnchor(slotCount: 5, slotIndex: 4), transientSlot: false, bottomExtra: 0, screenWidth: screenWidth)

        let fromX = PerchGeometry.tabCenterX(tab: 0, screenWidth: screenWidth, slotCount: 5)
        harness.clock.advance(ms: 10, frameMs: 1)
        controller.renderTick()
        XCTAssertNotEqual(controller.currentState.x, fromX, accuracy: 1e-9, "arrivedByDrag moves on the first tick, no 65ms delay")
    }

    // MARK: - The run leg outlives the engine's default age guard

    /// runSpeed 30 over a tab0->tab4 traverse (width 500, measured to clear
    /// 10s including the catch spring's own settle) - without the run leg's
    /// own per-call override this freezes mid-bar in run instead of arriving.
    func testASlowAnimalsLongRunOutlivesTheEnginesDefaultAgeGuard() {
        let harness = Harness()
        let profile = makeProfile(runSpeed: 30)
        let screenWidth = 500.0
        let controller = harness.makeController(profile: profile, anchor: PerchAnchor(slotCount: 5, slotIndex: 0), screenWidth: screenWidth)
        controller.focus(anchor: PerchAnchor(slotCount: 5, slotIndex: 0), transientSlot: false, bottomExtra: 0, screenWidth: screenWidth)

        controller.focus(anchor: PerchAnchor(slotCount: 5, slotIndex: 4), transientSlot: false, bottomExtra: 0, screenWidth: screenWidth)
        XCTAssertEqual(controller.currentState.pose, .run, "sanity: really running")

        harness.clock.advance(ms: 20_000, frameMs: 20)
        controller.renderTick()

        let targetX = PerchGeometry.tabCenterX(tab: 4, screenWidth: screenWidth, slotCount: 5)
        XCTAssertEqual(controller.currentState.pose, .sit, "arrived naturally, not frozen mid-bar by the age guard")
        XCTAssertEqual(controller.currentState.x, targetX, accuracy: 1e-6)
        XCTAssertFalse(harness.clock.wantsFrames)
    }

    // MARK: - Hop

    func testHopPeaksAt185AndReturnsToZeroBy305() {
        let harness = Harness()
        let profile = makeProfile(hopHeight: -8)
        let screenWidth = 402.0
        let controller = harness.makeController(profile: profile, anchor: PerchAnchor(slotCount: 5, slotIndex: 0), screenWidth: screenWidth)
        controller.focus(anchor: PerchAnchor(slotCount: 5, slotIndex: 0), transientSlot: false, bottomExtra: 0, screenWidth: screenWidth)
        controller.focus(anchor: PerchAnchor(slotCount: 5, slotIndex: 3), transientSlot: false, bottomExtra: 0, screenWidth: screenWidth)

        harness.clock.advance(ms: 185, frameMs: 1)
        controller.renderTick()
        XCTAssertEqual(controller.currentState.hop, -8, accuracy: 0.05, "peaks at hopHeight at t=185 (65 + 120)")

        harness.clock.advance(ms: 125, frameMs: 1)
        controller.renderTick()
        XCTAssertEqual(controller.currentState.hop, 0, accuracy: 1e-6, "back to 0 at t>=305 (65 + 120 + 120)")
    }

    /// Mutation: "the hop applied to a turtle" - hopHeight 0 means hop never
    /// leaves 0, whatever the run leg is doing.
    func testMutation_ZeroHopHeightNeverMoves() {
        let harness = Harness()
        let profile = makeProfile(hopHeight: 0)
        let screenWidth = 402.0
        let controller = harness.makeController(profile: profile, anchor: PerchAnchor(slotCount: 5, slotIndex: 0), screenWidth: screenWidth)
        controller.focus(anchor: PerchAnchor(slotCount: 5, slotIndex: 0), transientSlot: false, bottomExtra: 0, screenWidth: screenWidth)
        controller.focus(anchor: PerchAnchor(slotCount: 5, slotIndex: 4), transientSlot: false, bottomExtra: 0, screenWidth: screenWidth)

        for ms in stride(from: 0.0, through: 400, by: 40) {
            harness.clock.advance(ms: 40, frameMs: 1)
            controller.renderTick()
            XCTAssertEqual(controller.currentState.hop, 0, accuracy: 1e-9, "ms=\(ms)")
        }
    }

    func testArrivedByDragGivesNoHop() {
        let harness = Harness()
        let profile = makeProfile(hopHeight: -8)
        let screenWidth = 402.0
        let controller = harness.makeController(profile: profile, anchor: PerchAnchor(slotCount: 5, slotIndex: 0), screenWidth: screenWidth)
        controller.focus(anchor: PerchAnchor(slotCount: 5, slotIndex: 0), transientSlot: false, bottomExtra: 0, screenWidth: screenWidth)

        controller.debugReleaseState = ReleaseState(pending: ReleaseState.Pending(fromSlot: 0, slot: 0, generation: 0), arrival: false)
        controller.focus(anchor: PerchAnchor(slotCount: 5, slotIndex: 3), transientSlot: false, bottomExtra: 0, screenWidth: screenWidth)

        harness.clock.advance(ms: 185, frameMs: 1)
        controller.renderTick()
        XCTAssertEqual(controller.currentState.hop, 0, accuracy: 1e-9)
    }

    // MARK: - Raised seat holds bar level until the catch; descending drops at once

    func testClimbingToARaisedSeatHoldsBarLevelUntilTheCatch() {
        let harness = Harness()
        let profile = makeProfile(runSpeed: 340)
        let screenWidth = 402.0
        // lastSeat 0 at bottomExtra 0 (tab 0), climbing to bottomExtra 24 (tab 1, a raised tab).
        harness.handoff.writePerchHandoff(next: PerchHandoffState(lastTab: 0, lastX: nil, lastSeat: 0))
        let controller = harness.makeController(profile: profile, anchor: PerchAnchor(slotCount: 5, slotIndex: 0), screenWidth: screenWidth)
        controller.focus(anchor: PerchAnchor(slotCount: 5, slotIndex: 0), transientSlot: false, bottomExtra: 0, screenWidth: screenWidth)

        controller.focus(anchor: PerchAnchor(slotCount: 5, slotIndex: 1), transientSlot: false, bottomExtra: 24, screenWidth: screenWidth)

        let fromX = PerchGeometry.tabCenterX(tab: 0, screenWidth: screenWidth, slotCount: 5)
        let targetX = PerchGeometry.tabCenterX(tab: 1, screenWidth: screenWidth, slotCount: 5)
        let runMs = PerchGeometry.traverseDurationMs(distancePt: abs(targetX - fromX), speedPtS: 340)
        let expectedRunSeatY = PerchHandoff.planRunSeatY(fromSeatY: 24 - 0)
        XCTAssertGreaterThan(expectedRunSeatY, 0, "sanity: this is really a climb")

        harness.clock.advance(ms: 65 + runMs / 2, frameMs: 1)
        controller.renderTick()
        XCTAssertEqual(controller.currentState.seatY, expectedRunSeatY, accuracy: 1e-6, "holds the departing (raised-relative) offset through the timing leg")

        harness.clock.advance(ms: 2000, frameMs: 1)
        controller.renderTick()
        XCTAssertEqual(controller.currentState.seatY, 0, accuracy: 1e-6, "the catch spring lands seatY at 0 (the new, raised seat)")
    }

    func testDescendingToALowerSeatDropsAtOnce() {
        let harness = Harness()
        let profile = makeProfile(runSpeed: 340)
        let screenWidth = 402.0
        harness.handoff.writePerchHandoff(next: PerchHandoffState(lastTab: 0, lastX: nil, lastSeat: 24))
        let controller = harness.makeController(profile: profile, anchor: PerchAnchor(slotCount: 5, slotIndex: 0), screenWidth: screenWidth, bottomExtra: 24)
        controller.focus(anchor: PerchAnchor(slotCount: 5, slotIndex: 0), transientSlot: false, bottomExtra: 24, screenWidth: screenWidth)

        controller.focus(anchor: PerchAnchor(slotCount: 5, slotIndex: 1), transientSlot: false, bottomExtra: 0, screenWidth: screenWidth)

        harness.clock.advance(ms: 1, frameMs: 1)
        controller.renderTick()
        XCTAssertEqual(controller.currentState.seatY, 0, accuracy: 1e-9, "descending seatY snaps to 0 immediately, no gradual glide")
    }

    // MARK: - Reduced chase snaps in one commit

    func testReducedChaseSnapsInOneCommitWithNoActiveTrack() {
        let harness = Harness()
        harness.reduceMotionFlag = true
        let profile = makeProfile()
        let screenWidth = 402.0
        let controller = harness.makeController(profile: profile, anchor: PerchAnchor(slotCount: 5, slotIndex: 0), screenWidth: screenWidth)
        controller.focus(anchor: PerchAnchor(slotCount: 5, slotIndex: 0), transientSlot: false, bottomExtra: 0, screenWidth: screenWidth)

        controller.focus(anchor: PerchAnchor(slotCount: 5, slotIndex: 4), transientSlot: false, bottomExtra: 0, screenWidth: screenWidth)

        let targetX = PerchGeometry.tabCenterX(tab: 4, screenWidth: screenWidth, slotCount: 5)
        XCTAssertEqual(controller.currentState.x, targetX, accuracy: 1e-9, "reaches the target in the same commit - reduce motion snaps")
        XCTAssertEqual(controller.currentState.seatY, 0, accuracy: 1e-9)
        XCTAssertEqual(controller.currentState.pose, .sit)
        XCTAssertFalse(harness.clock.wantsFrames, "no track active")
    }

    // MARK: - Snap kinds

    func testTransientSlotSnapsInstantlyAndNeverWritesTheHandoffStore() {
        let harness = Harness()
        let before = harness.handoff.readPerchHandoff()
        let profile = makeProfile()
        let screenWidth = 402.0
        let controller = harness.makeController(profile: profile, anchor: PerchAnchor(slotCount: 5, slotIndex: 0), screenWidth: screenWidth, transientSlot: true)
        controller.focus(anchor: PerchAnchor(slotCount: 5, slotIndex: 3), transientSlot: true, bottomExtra: 0, screenWidth: screenWidth)

        let targetX = PerchGeometry.tabCenterX(tab: 3, screenWidth: screenWidth, slotCount: 5)
        XCTAssertEqual(controller.currentState.x, targetX, accuracy: 1e-9)
        XCTAssertEqual(controller.currentState.pose, .sit)
        XCTAssertEqual(harness.handoff.readPerchHandoff(), before, "transient never writes the shared store")
    }

    func testSameTabSnapWritesTheHandoffButSnapsInstantly() {
        let harness = Harness()
        harness.handoff.writePerchHandoff(next: PerchHandoffState(lastTab: 2, lastX: nil, lastSeat: 0))
        let profile = makeProfile()
        let screenWidth = 402.0
        let controller = harness.makeController(profile: profile, anchor: PerchAnchor(slotCount: 5, slotIndex: 2), screenWidth: screenWidth)
        controller.focus(anchor: PerchAnchor(slotCount: 5, slotIndex: 2), transientSlot: false, bottomExtra: 0, screenWidth: screenWidth)

        let targetX = PerchGeometry.tabCenterX(tab: 2, screenWidth: screenWidth, slotCount: 5)
        XCTAssertEqual(controller.currentState.x, targetX, accuracy: 1e-9)
        XCTAssertEqual(harness.handoff.readPerchHandoff().lastTab, 2)
    }

    func testSnapToSeatCatchesFromAShortDistance() {
        let harness = Harness()
        // Slot 0 and 1's centers are within PERCH_SIZE (54pt) of each other
        // on a narrow screen - forces `shouldSnapToSeat`.
        let narrowWidth = 80.0
        harness.handoff.writePerchHandoff(next: PerchHandoffState(lastTab: 0, lastX: nil, lastSeat: 0))
        let profile = makeProfile()
        let controller = harness.makeController(profile: profile, anchor: PerchAnchor(slotCount: 2, slotIndex: 0), screenWidth: narrowWidth)
        controller.focus(anchor: PerchAnchor(slotCount: 2, slotIndex: 0), transientSlot: false, bottomExtra: 0, screenWidth: narrowWidth)

        controller.focus(anchor: PerchAnchor(slotCount: 2, slotIndex: 1), transientSlot: false, bottomExtra: 0, screenWidth: narrowWidth)

        let targetX = PerchGeometry.tabCenterX(tab: 1, screenWidth: narrowWidth, slotCount: 2)
        XCTAssertEqual(controller.currentState.x, targetX, accuracy: 1e-9, "the ordinary (not arrived-by-drag) catch is an instant teleport")
        XCTAssertEqual(controller.currentState.pose, .sit)
    }

    // MARK: - Arrived-by-drag catch

    func testArrivedByDragCatchSpringsFromTheCapturedLiveXNotPlanFromX() {
        let harness = Harness()
        let narrowWidth = 80.0
        harness.handoff.writePerchHandoff(next: PerchHandoffState(lastTab: 0, lastX: nil, lastSeat: 0))
        let profile = makeProfile()
        let controller = harness.makeController(profile: profile, anchor: PerchAnchor(slotCount: 2, slotIndex: 0), screenWidth: narrowWidth)
        controller.focus(anchor: PerchAnchor(slotCount: 2, slotIndex: 0), transientSlot: false, bottomExtra: 0, screenWidth: narrowWidth)

        // Live position drifts away from the seat (as a drag would leave it)
        // before the arriving focus lands - captured as liveXAtFocusStart.
        let liveX = controller.currentState.x + 12
        controller.debugSetX(liveX)

        controller.debugReleaseState = ReleaseState(pending: ReleaseState.Pending(fromSlot: 0, slot: 0, generation: 0), arrival: false)
        controller.focus(anchor: PerchAnchor(slotCount: 2, slotIndex: 1), transientSlot: false, bottomExtra: 0, screenWidth: narrowWidth)

        let targetX = PerchGeometry.tabCenterX(tab: 1, screenWidth: narrowWidth, slotCount: 2)
        // The spring's synchronous first frame (dt=0) leaves `current` at its
        // own start value - proving the spring began at liveX, not at
        // plan.fromX (which a snap-to-seat plan bakes to targetX already).
        XCTAssertEqual(controller.currentState.x, liveX, accuracy: 1e-6)
        if abs(targetX - liveX) > PerchGeometry.FACING_DEADBAND {
            XCTAssertEqual(controller.currentState.pose, .run, "remaining distance over 3pt runs, not sits")
        }
    }

    // MARK: - Re-entry generation gate

    func testALateCompletionFromAStaleGenerationDoesNotRest() {
        let harness = Harness()
        let profile = makeProfile(runSpeed: 340)
        let screenWidth = 402.0
        let controller = harness.makeController(profile: profile, anchor: PerchAnchor(slotCount: 5, slotIndex: 0), screenWidth: screenWidth)
        controller.focus(anchor: PerchAnchor(slotCount: 5, slotIndex: 0), transientSlot: false, bottomExtra: 0, screenWidth: screenWidth)
        controller.focus(anchor: PerchAnchor(slotCount: 5, slotIndex: 4), transientSlot: false, bottomExtra: 0, screenWidth: screenWidth)
        XCTAssertEqual(controller.currentState.pose, .run)

        // TS: a finger 'began' bumps the generation without cancelling the
        // in-flight commit chase - absent finger path here, so the test
        // drives the same generation bump directly.
        controller.debugBumpGeneration()

        harness.clock.advance(ms: 5000, frameMs: 1)
        controller.renderTick()

        XCTAssertEqual(controller.currentState.pose, .run, "the stale generation's arrival must not rest a newer motion")
    }

    func testMutation_MountedFalseAlsoBlocksAStaleArrival() {
        let harness = Harness()
        let profile = makeProfile(runSpeed: 340)
        let screenWidth = 402.0
        let controller = harness.makeController(profile: profile, anchor: PerchAnchor(slotCount: 5, slotIndex: 0), screenWidth: screenWidth)
        controller.focus(anchor: PerchAnchor(slotCount: 5, slotIndex: 0), transientSlot: false, bottomExtra: 0, screenWidth: screenWidth)
        controller.focus(anchor: PerchAnchor(slotCount: 5, slotIndex: 3), transientSlot: false, bottomExtra: 0, screenWidth: screenWidth)
        harness.mountedFlag = false

        harness.clock.advance(ms: 5000, frameMs: 1)
        controller.renderTick()

        XCTAssertEqual(controller.currentState.pose, .run, "unmounted: the completion must not rest the pose either")
    }

    // MARK: - Remeasure

    func testRemeasureRetriesThenSeatsOnceMeasurementArrives() {
        let harness = Harness()
        var callCount = 0
        harness.measureResult = nil
        let profile = makeProfile()
        let screenWidth = 402.0
        // No slotCenters on the anchor, and no measurement yet - this is
        // exactly the "first focus before the bar has laid out" case.
        let controller = harness.makeController(profile: profile, anchor: PerchAnchor(slotCount: 5, slotIndex: 0), screenWidth: screenWidth)

        controller.focus(anchor: PerchAnchor(slotCount: 5, slotIndex: 0), transientSlot: false, bottomExtra: 0, screenWidth: screenWidth)
        let fallbackX = controller.currentState.x

        // Each retry is paced 16ms apart (matching TS's own
        // requestAnimationFrame cadence) - one `advance` per retry.
        for _ in 0..<10 {
            harness.clock.advance(ms: 16, frameMs: 1)
            callCount += 1
        }
        XCTAssertEqual(controller.currentState.x, fallbackX, accuracy: 1e-9, "still on the even-split fallback after 10 misses")

        harness.measureResult = BarLayout(centers: [10, 100, 200, 300, 390])
        harness.clock.advance(ms: 16, frameMs: 1)
        controller.renderTick()

        XCTAssertEqual(controller.currentState.x, 10 - PerchGeometry.PERCH_SIZE / 2, accuracy: 1e-6, "seated on the measured center once found")
        _ = callCount
    }

    /// TS paces `retryMeasure` with `requestAnimationFrame` - roughly 16ms a
    /// try, 60 tries max, about 960ms of survivable delay before giving up.
    /// This proves the retry loop survives a real-looking 300ms delay.
    func testRemeasureSurvivesA300msDelayPacedLikeTheTypeScriptRetryLoop() {
        let harness = Harness()
        harness.measureResult = nil
        let profile = makeProfile()
        let screenWidth = 402.0
        let controller = harness.makeController(profile: profile, anchor: PerchAnchor(slotCount: 5, slotIndex: 0), screenWidth: screenWidth)
        controller.focus(anchor: PerchAnchor(slotCount: 5, slotIndex: 0), transientSlot: false, bottomExtra: 0, screenWidth: screenWidth)
        let fallbackX = controller.currentState.x

        let retryPacingMs = 16.0
        let maxTries = 60.0
        let survivableBudgetMs = retryPacingMs * maxTries
        XCTAssertLessThan(300, survivableBudgetMs, "sanity: this test's own delay fits inside the TS-derived retry budget")

        harness.clock.advance(ms: 300, frameMs: 1)
        controller.renderTick()
        XCTAssertEqual(controller.currentState.x, fallbackX, accuracy: 1e-9, "still unmeasured at 300ms - not yet given up")

        harness.measureResult = BarLayout(centers: [10, 100, 200, 300, 390])
        harness.clock.advance(ms: 700, frameMs: 1)
        controller.renderTick()

        XCTAssertEqual(controller.currentState.x, 10 - PerchGeometry.PERCH_SIZE / 2, accuracy: 1e-6, "seated on the measured center once it arrives")
    }

    func testXCorrectsOnlyWhileSeatedNeverDuringAnActiveRunChase() {
        let harness = Harness()
        harness.measureResult = nil
        let profile = makeProfile(runSpeed: 340)
        let screenWidth = 402.0
        let controller = harness.makeController(profile: profile, anchor: PerchAnchor(slotCount: 5, slotIndex: 0), screenWidth: screenWidth)
        controller.focus(anchor: PerchAnchor(slotCount: 5, slotIndex: 0), transientSlot: false, bottomExtra: 0, screenWidth: screenWidth)
        controller.focus(anchor: PerchAnchor(slotCount: 5, slotIndex: 4), transientSlot: false, bottomExtra: 0, screenWidth: screenWidth)
        harness.clock.advance(ms: 70, frameMs: 1)
        controller.renderTick()
        let xDuringChase = controller.currentState.x
        XCTAssertEqual(controller.currentState.pose, .run)

        harness.measureResult = BarLayout(centers: [10, 100, 200, 300, 390])
        harness.clock.advance(ms: 1, frameMs: 1)
        controller.renderTick()

        XCTAssertNotEqual(controller.currentState.x, 390 - PerchGeometry.PERCH_SIZE / 2, accuracy: 1e-6, "a run-chase owns x - the remeasure must not yank it")
        XCTAssertGreaterThan(controller.currentState.x, xDuringChase - 1, "still progressing the chase, not snapped")
    }

    func testBlurCancelsAnInFlightRemeasure() {
        let harness = Harness()
        harness.measureResult = nil
        let profile = makeProfile()
        let screenWidth = 402.0
        let controller = harness.makeController(profile: profile, anchor: PerchAnchor(slotCount: 5, slotIndex: 0), screenWidth: screenWidth)
        controller.focus(anchor: PerchAnchor(slotCount: 5, slotIndex: 0), transientSlot: false, bottomExtra: 0, screenWidth: screenWidth)

        controller.focus(anchor: PerchAnchor(slotCount: 5, slotIndex: 1), transientSlot: false, bottomExtra: 0, screenWidth: screenWidth)

        harness.measureResult = BarLayout(centers: [10, 100, 200, 300, 390])
        harness.clock.advance(ms: 200, frameMs: 1)
        controller.renderTick()

        XCTAssertNotEqual(controller.currentState.x, 100 - PerchGeometry.PERCH_SIZE / 2, accuracy: 1e-6, "the blurred focus's own remeasure must not still be running")
    }

    func testGivesUpAfter60Tries() {
        let harness = Harness()
        harness.measureResult = nil
        let profile = makeProfile()
        let screenWidth = 402.0
        let controller = harness.makeController(profile: profile, anchor: PerchAnchor(slotCount: 5, slotIndex: 0), screenWidth: screenWidth)
        controller.focus(anchor: PerchAnchor(slotCount: 5, slotIndex: 0), transientSlot: false, bottomExtra: 0, screenWidth: screenWidth)
        let fallbackX = controller.currentState.x

        harness.clock.advance(ms: 70, frameMs: 1)
        harness.measureResult = BarLayout(centers: [10, 100, 200, 300, 390])
        controller.renderTick()

        XCTAssertEqual(controller.currentState.x, fallbackX, accuracy: 1e-9, "gave up after 60 tries - a later measurement is never adopted")
    }

    // MARK: - Busy

    func testBusyDuringARunChangesNothingUntilArriveThenRestGivesIdle() {
        let harness = Harness()
        let profile = makeProfile(runSpeed: 340)
        let screenWidth = 402.0
        let controller = harness.makeController(profile: profile, anchor: PerchAnchor(slotCount: 5, slotIndex: 0), screenWidth: screenWidth)
        controller.focus(anchor: PerchAnchor(slotCount: 5, slotIndex: 0), transientSlot: false, bottomExtra: 0, screenWidth: screenWidth)
        controller.focus(anchor: PerchAnchor(slotCount: 5, slotIndex: 4), transientSlot: false, bottomExtra: 0, screenWidth: screenWidth)
        XCTAssertEqual(controller.currentState.pose, .run)

        let release = harness.busy.beginCompanionBusy()
        XCTAssertEqual(controller.currentState.pose, .run, "busy during a run changes nothing")

        harness.clock.advance(ms: 5000, frameMs: 1)
        controller.renderTick()
        XCTAssertEqual(controller.currentState.pose, .idle, "rest chooses idle while a busy claim is held")

        release()
    }

    /// Mutation: "rest choosing idle when not busy" - `rest()` must choose
    /// `.sit`, not `.idle`, when no busy claim is held.
    func testMutation_RestChoosesSitWhenNotBusy() {
        let harness = Harness()
        let profile = makeProfile(runSpeed: 340)
        let screenWidth = 402.0
        let controller = harness.makeController(profile: profile, anchor: PerchAnchor(slotCount: 5, slotIndex: 0), screenWidth: screenWidth)
        controller.focus(anchor: PerchAnchor(slotCount: 5, slotIndex: 0), transientSlot: false, bottomExtra: 0, screenWidth: screenWidth)
        controller.focus(anchor: PerchAnchor(slotCount: 5, slotIndex: 4), transientSlot: false, bottomExtra: 0, screenWidth: screenWidth)

        harness.clock.advance(ms: 5000, frameMs: 1)
        controller.renderTick()

        XCTAssertEqual(controller.currentState.pose, .sit)
    }

    // MARK: - Blur handoff

    func testBlurFreezesTheHandoffAtTheLiveXAndLiveSeat() {
        let harness = Harness()
        let profile = makeProfile(runSpeed: 340)
        let screenWidth = 402.0
        let controller = harness.makeController(profile: profile, anchor: PerchAnchor(slotCount: 5, slotIndex: 0), screenWidth: screenWidth, bottomExtra: 12)
        controller.focus(anchor: PerchAnchor(slotCount: 5, slotIndex: 0), transientSlot: false, bottomExtra: 12, screenWidth: screenWidth)
        controller.focus(anchor: PerchAnchor(slotCount: 5, slotIndex: 4), transientSlot: false, bottomExtra: 12, screenWidth: screenWidth)

        harness.clock.advance(ms: 100, frameMs: 1)
        controller.renderTick()
        let liveXBeforeBlur = controller.currentState.x
        let liveSeatYBeforeBlur = controller.currentState.seatY

        // isFocused: false runs only the blur, not a new focus body (which
        // would overwrite the handoff again via its own `plan.next`) - the
        // one way to observe the blur's own write in isolation.
        controller.focus(anchor: PerchAnchor(slotCount: 5, slotIndex: 1), isFocused: false, transientSlot: false, bottomExtra: 12, screenWidth: screenWidth)

        let handoffAfterBlur = harness.handoff.readPerchHandoff()
        XCTAssertEqual(handoffAfterBlur.lastX ?? .nan, liveXBeforeBlur, accuracy: 1e-6)
        let expectedLiveSeat = PerchHandoff.liveLastSeat(bottomExtra: 12, seatY: liveSeatYBeforeBlur)
        XCTAssertEqual(handoffAfterBlur.lastSeat, expectedLiveSeat, accuracy: 1e-6)
    }

    // MARK: - Flight lift

    func testRunGivesNegativeFlightLiftSitGivesZero() {
        let harness = Harness()
        let profile = makeProfile(flightLift: 14, runSpeed: 40) // slow: gives a long window to sample mid-run
        let screenWidth = 402.0
        let controller = harness.makeController(profile: profile, anchor: PerchAnchor(slotCount: 5, slotIndex: 0), screenWidth: screenWidth)
        controller.focus(anchor: PerchAnchor(slotCount: 5, slotIndex: 0), transientSlot: false, bottomExtra: 0, screenWidth: screenWidth)
        controller.focus(anchor: PerchAnchor(slotCount: 5, slotIndex: 3), transientSlot: false, bottomExtra: 0, screenWidth: screenWidth)
        XCTAssertEqual(controller.currentState.pose, .run, "sanity: still mid-chase")

        // Sample well before arrival (a slow runSpeed keeps this chase going
        // far longer than the flight-lift spring's own settle time).
        harness.clock.advance(ms: 1500, frameMs: 1)
        controller.renderTick()
        XCTAssertEqual(controller.currentState.pose, .run, "sanity: still running, not yet arrived")
        XCTAssertEqual(controller.currentState.flightLift, -14, accuracy: 0.5, "run springs toward -flightLift")

        harness.clock.advance(ms: 20_000, frameMs: 1)
        controller.renderTick()
        XCTAssertEqual(controller.currentState.pose, .sit, "sanity: arrived and rested")
        XCTAssertEqual(controller.currentState.flightLift, 0, accuracy: 0.5, "sit (at rest) springs back to 0")
    }

    // MARK: - Reduce Motion

    /// reducedChase snaps straight to `.sit`, already the resting pose, so
    /// `setPose` short-circuits before `updateFlightLift` ever runs its
    /// reduceMotion branch. This starts a real run and flips it mid-chase.
    func testFlightLiftSnapsInsteadOfSpringingUnderReduceMotion() {
        let harness = Harness()
        let profile = makeProfile(flightLift: 14, runSpeed: 40)
        let screenWidth = 402.0
        let controller = harness.makeController(profile: profile, anchor: PerchAnchor(slotCount: 5, slotIndex: 0), screenWidth: screenWidth)
        controller.focus(anchor: PerchAnchor(slotCount: 5, slotIndex: 0), transientSlot: false, bottomExtra: 0, screenWidth: screenWidth)
        controller.focus(anchor: PerchAnchor(slotCount: 5, slotIndex: 3), transientSlot: false, bottomExtra: 0, screenWidth: screenWidth)
        XCTAssertEqual(controller.currentState.pose, .run, "sanity: really running, reduce motion off")

        harness.clock.advance(ms: 1500, frameMs: 1)
        controller.renderTick()
        XCTAssertEqual(controller.currentState.pose, .run, "sanity: still mid-chase")
        XCTAssertLessThan(controller.currentState.flightLift, -0.5, "sanity: the spring already moved before the flip")

        harness.reduceMotionFlag = true

        // Step 1ms at a time, checking right after the tick the arrival
        // lands in - a spring (the bug) has barely moved off its pre-flip
        // value after only 1ms, unlike a later, settled read.
        var caughtAtArrival = false
        for _ in 0..<20_000 {
            harness.clock.advance(ms: 1, frameMs: 1)
            controller.renderTick()
            if controller.currentState.pose == .sit {
                caughtAtArrival = true
                break
            }
        }
        XCTAssertTrue(caughtAtArrival, "sanity: the run arrived within this loop's own bound")
        XCTAssertEqual(controller.currentState.flightLift, 0, accuracy: 1e-9, "arrival's own pose flip snapped flightLift in the same commit, not sprang")
        XCTAssertFalse(harness.clock.wantsFrames, "a snap starts no track")
    }

    func testCatchAtSeatSnapsInstantlyUnderReduceMotionEvenArrivedByDrag() {
        let harness = Harness()
        let narrowWidth = 80.0
        harness.handoff.writePerchHandoff(next: PerchHandoffState(lastTab: 0, lastX: nil, lastSeat: 0))
        let profile = makeProfile()
        let controller = harness.makeController(profile: profile, anchor: PerchAnchor(slotCount: 2, slotIndex: 0), screenWidth: narrowWidth)
        controller.focus(anchor: PerchAnchor(slotCount: 2, slotIndex: 0), transientSlot: false, bottomExtra: 0, screenWidth: narrowWidth)

        harness.reduceMotionFlag = true
        controller.debugReleaseState = ReleaseState(pending: ReleaseState.Pending(fromSlot: 0, slot: 0, generation: 0), arrival: false)
        controller.focus(anchor: PerchAnchor(slotCount: 2, slotIndex: 1), transientSlot: false, bottomExtra: 0, screenWidth: narrowWidth)

        let targetX = PerchGeometry.tabCenterX(tab: 1, screenWidth: narrowWidth, slotCount: 2)
        XCTAssertEqual(controller.currentState.x, targetX, accuracy: 1e-9, "reduceMotion takes the fast (instant) path even when arrivedByDrag")
        XCTAssertEqual(controller.currentState.pose, .sit)
    }

    // MARK: - Profile / window-size change reruns blur + focus

    /// Asserts the render-state count, not just `pose == .sit` (a same-tab
    /// snap already leaves it there): a real rerun publishes exactly two
    /// transactions, the blur then the focus body - fails if deleted.
    func testUpdateProfileRerunsBlurAndFocus() {
        let harness = Harness()
        let profile = makeProfile()
        let screenWidth = 402.0
        let controller = harness.makeController(profile: profile, anchor: PerchAnchor(slotCount: 5, slotIndex: 2), screenWidth: screenWidth)
        controller.focus(anchor: PerchAnchor(slotCount: 5, slotIndex: 2), transientSlot: false, bottomExtra: 0, screenWidth: screenWidth)
        let countBefore = harness.renderStateCount

        let newProfile = makeProfile(hopHeight: -20)
        controller.updateProfile(newProfile)

        XCTAssertEqual(harness.renderStateCount - countBefore, 2, "a real rerun fires its own blur transaction plus its own focus-body transaction")
    }

    func testWindowSizeChangeRerunsBlurAndFocusAtTheNewWidth() {
        let harness = Harness()
        let profile = makeProfile()
        let controller = harness.makeController(profile: profile, anchor: PerchAnchor(slotCount: 5, slotIndex: 2), screenWidth: 402)
        controller.focus(anchor: PerchAnchor(slotCount: 5, slotIndex: 2), transientSlot: false, bottomExtra: 0, screenWidth: 402)
        let xAt402 = controller.currentState.x

        controller.focus(anchor: PerchAnchor(slotCount: 5, slotIndex: 2), transientSlot: false, bottomExtra: 0, screenWidth: 800)

        let expectedXAt800 = PerchGeometry.tabCenterX(tab: 2, screenWidth: 800, slotCount: 5)
        XCTAssertEqual(controller.currentState.x, expectedXAt800, accuracy: 1e-9)
        XCTAssertNotEqual(controller.currentState.x, xAt402, accuracy: 1e-6)
    }

    // MARK: - Mutations that concern the controller specifically

    /// "a non finite center accepted at the controller boundary" - a NaN in
    /// the anchor's own `slotCenters` must be treated as not provided.
    func testMutation_NonFiniteCenterIsRejectedAtTheBoundary() {
        let harness = Harness()
        let profile = makeProfile()
        let screenWidth = 402.0
        // Tab 0 matches the default handoff's lastTab (0), so this lands on
        // a same-tab-snap - instant, so the sanitized x is directly readable
        // right after focus() with no chase in flight to sample mid-way.
        let anchor = PerchAnchor(slotCount: 5, slotIndex: 0, slotCenters: [.nan, 100, 200, 300, 390])
        let controller = harness.makeController(profile: profile, anchor: anchor, screenWidth: screenWidth)
        controller.focus(anchor: anchor, transientSlot: false, bottomExtra: 0, screenWidth: screenWidth)

        let evenSplitX = PerchGeometry.tabCenterX(tab: 0, screenWidth: screenWidth, slotCount: 5)
        XCTAssertEqual(controller.currentState.x, evenSplitX, accuracy: 1e-9, "a NaN anywhere in the provided centers falls back to the even split, never NaN")
        XCTAssertTrue(controller.currentState.x.isFinite)
    }

    /// "sanitizeRunSpeed not used" - an invalid profile.runSpeed must still
    /// produce the sanitized default's duration, not a frozen/reversed run.
    func testMutation_InvalidRunSpeedFallsBackToTheSanitizedDefault() {
        let harness = Harness()
        let profile = makeProfile(runSpeed: -5)
        let screenWidth = 402.0
        let controller = harness.makeController(profile: profile, anchor: PerchAnchor(slotCount: 5, slotIndex: 0), screenWidth: screenWidth)
        controller.focus(anchor: PerchAnchor(slotCount: 5, slotIndex: 0), transientSlot: false, bottomExtra: 0, screenWidth: screenWidth)
        controller.focus(anchor: PerchAnchor(slotCount: 5, slotIndex: 4), transientSlot: false, bottomExtra: 0, screenWidth: screenWidth)

        let fromX = PerchGeometry.tabCenterX(tab: 0, screenWidth: screenWidth, slotCount: 5)
        let targetX = PerchGeometry.tabCenterX(tab: 4, screenWidth: screenWidth, slotCount: 5)
        let sanitizedRunMs = PerchGeometry.traverseDurationMs(distancePt: abs(targetX - fromX), speedPtS: PerchGeometry.TRAVERSE_SPEED_PT_S)

        harness.clock.advance(ms: 65 + sanitizedRunMs / 2, frameMs: 1)
        controller.renderTick()
        let expectedX = fromX + (targetX - fromX) * (harness.clock.now - 65) / sanitizedRunMs
        XCTAssertEqual(controller.currentState.x, expectedX, accuracy: 1e-3, "duration derived from the sanitized default speed, not -5")
    }

    /// "the seat not raised through bottomExtra" - a simple case beyond the
    /// climbing/descending run-chase tests above: a mount seed straight
    /// onto a raised tab reads `bottomExtra`, not 0.
    func testMutation_MountSeedReadsBottomExtraIntoTheSeatPlan() {
        let harness = Harness()
        // lastTab 1 != the mounting tab 0, so this is a real run-chase/
        // snap-to-seat plan, not a same-tab-snap (which ignores bottomExtra
        // entirely, always planting seatY at 0).
        let seededHandoff = PerchHandoffState(lastTab: 1, lastX: nil, lastSeat: 0)
        harness.handoff.writePerchHandoff(next: seededHandoff)
        let profile = makeProfile()
        let controller = harness.makeController(profile: profile, anchor: PerchAnchor(slotCount: 5, slotIndex: 0), screenWidth: 402, bottomExtra: 24)

        let expectedSeatY = PerchHandoff.planMountSeatY(
            handoff: seededHandoff,
            tab: 0, screenWidth: 402, bottomExtra: 24, transientSlot: false, reduceMotion: false, slotCount: 5
        )
        XCTAssertGreaterThan(expectedSeatY, 0, "sanity: bottomExtra really does raise the plan")
        XCTAssertEqual(controller.currentState.seatY, expectedSeatY, accuracy: 1e-9)
    }

    /// "a tab change leaving visible at 0" - a blur sets visible to 0; the
    /// next focus must set it back to 1.
    func testMutation_ATabChangeLeavesVisibleAtOne() {
        let harness = Harness()
        let profile = makeProfile()
        let screenWidth = 402.0
        let controller = harness.makeController(profile: profile, anchor: PerchAnchor(slotCount: 5, slotIndex: 0), screenWidth: screenWidth)
        controller.focus(anchor: PerchAnchor(slotCount: 5, slotIndex: 0), transientSlot: false, bottomExtra: 0, screenWidth: screenWidth)
        XCTAssertEqual(controller.currentState.visible, 1)

        controller.focus(anchor: PerchAnchor(slotCount: 5, slotIndex: 1), transientSlot: false, bottomExtra: 0, screenWidth: screenWidth)

        XCTAssertEqual(controller.currentState.visible, 1, "the new focus restores visible to 1, not left at 0 from its own blur")
    }

    /// "pose writes applied one by one instead of one commit" - one
    /// `focus()` call must publish only as many commits as it has
    /// transactions, never one per intermediate write.
    func testMutation_OneFocusCallPublishesExactlyOneRenderCommit() {
        let harness = Harness()
        let profile = makeProfile()
        let screenWidth = 402.0
        let controller = harness.makeController(profile: profile, anchor: PerchAnchor(slotCount: 5, slotIndex: 0), screenWidth: screenWidth)
        controller.focus(anchor: PerchAnchor(slotCount: 5, slotIndex: 0), transientSlot: false, bottomExtra: 0, screenWidth: screenWidth)
        let countBefore = harness.renderStateCount

        controller.focus(anchor: PerchAnchor(slotCount: 5, slotIndex: 3), transientSlot: false, bottomExtra: 0, screenWidth: screenWidth)

        // Blur (if any was active) plus the focus body are two separate
        // transactions, each its own commit - the first call above had
        // no prior focus to blur, so this one fires blur (1) + body (1).
        XCTAssertEqual(harness.renderStateCount - countBefore, 2, "blur is its own transaction, the focus body is its own transaction - never more")
    }

    // MARK: - Teardown

    func testTeardownUnsubscribesFromBusyClaims() {
        let harness = Harness()
        let profile = makeProfile()
        let controller = harness.makeController(profile: profile, anchor: PerchAnchor(slotCount: 5, slotIndex: 0), screenWidth: 402)
        controller.focus(anchor: PerchAnchor(slotCount: 5, slotIndex: 0), transientSlot: false, bottomExtra: 0, screenWidth: 402)

        controller.teardown()
        let release = harness.busy.beginCompanionBusy()
        XCTAssertEqual(controller.currentState.pose, .sit, "no longer subscribed - a busy claim after teardown does not toggle pose")
        release()
    }
}

