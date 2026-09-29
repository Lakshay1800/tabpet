import TabPetCore
import XCTest

@testable import TabPetMotion

/// One controller on a five slot bar with a pill frame, focused on `startSlot`.
@MainActor
private final class RouteRig {
    let harness = Harness()
    let profile: CompanionProfile
    let screenWidth: Double
    let pill: PillFrame?
    let slotCount: Int
    var controller: PerchController!

    static let defaultPill = PillFrame(x: 16, y: 760, width: 370, height: 62)

    init(
        profile: CompanionProfile = makeProfile(aroundRoute: true),
        slotCount: Int = 5,
        screenWidth: Double = 402,
        pill: PillFrame? = RouteRig.defaultPill,
        startSlot: Int = 0
    ) {
        self.profile = profile
        self.slotCount = slotCount
        self.screenWidth = screenWidth
        self.pill = pill
        controller = harness.makeController(profile: profile, anchor: anchor(startSlot), screenWidth: screenWidth)
        go(startSlot)
    }

    func anchor(_ slot: Int) -> PerchAnchor {
        PerchAnchor(slotCount: slotCount, slotIndex: slot, pill: pill)
    }

    func go(_ slot: Int, bottomExtra: Double = 0, isFocused: Bool = true) {
        controller.focus(anchor: anchor(slot), isFocused: isFocused, transientSlot: false, bottomExtra: bottomExtra, screenWidth: screenWidth)
    }

    func seatX(_ slot: Int) -> Double {
        PerchGeometry.tabCenterX(tab: slot, screenWidth: screenWidth, slotCount: slotCount)
    }

    /// The path the controller plans for a fresh route between two slots.
    func path(from: Int, to: Int) -> AroundPath {
        PerchAround.planAroundPath(
            fromX: seatX(from),
            targetX: seatX(to),
            pill: pill ?? RouteRig.defaultPill,
            windowWidth: screenWidth,
            spriteScale: profile.scale,
            footPad: profile.resolvedFootPad,
            headPad: profile.resolvedHeadPad,
            seatOffset: profile.resolvedSeatLift - PerchGeometry.seatedFootPad(footPad: profile.resolvedFootPad, scale: profile.scale)
        )
    }

    func advance(_ ms: Double, frameMs: Double = 1) {
        harness.clock.advance(ms: ms, frameMs: frameMs)
        controller.renderTick()
    }

    /// Advances to the point where a fresh route has covered `s` points.
    func advanceToProgress(_ s: Double, of path: AroundPath) {
        advance(65 + s / path.totalLen * path.totalMs)
    }

    /// Runs out `ms` in frames, calling `each` with the state after every tick.
    func run(_ ms: Double, frameMs: Double = 8, each: (PerchRenderState) -> Void = { _ in }) {
        var elapsed = 0.0
        while elapsed < ms {
            advance(frameMs, frameMs: frameMs)
            elapsed += frameMs
            each(controller.currentState)
        }
    }

    var perchTrackActive: Bool {
        harness.engine.isAnyTrackActive(labelPrefix: "perch.")
    }
}

@MainActor
final class PerchControllerRouteTests: XCTestCase {
    private func assertPose(
        _ state: PerchRenderState,
        equals pose: AroundPose,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(state.x, pose.x, accuracy: 1e-6, "x \(message)", file: file, line: line)
        XCTAssertEqual(state.seatY, pose.seatY, accuracy: 1e-6, "seatY \(message)", file: file, line: line)
        XCTAssertEqual(state.rotationDegrees, pose.rotation, accuracy: 1e-6, "rotation \(message)", file: file, line: line)
    }

    // MARK: - Fresh route

    func testTheRouteIsTaken_RotatesAndDropsBelowTheSeat() {
        let rig = RouteRig()
        rig.go(4)
        let path = rig.path(from: 0, to: 4)

        var sawRotation = false
        var sawBelowSeat = false
        rig.run(path.totalMs + 400) { state in
            if state.rotationDegrees != 0 { sawRotation = true }
            if state.seatY > 1 { sawBelowSeat = true }
        }
        XCTAssertTrue(sawRotation)
        XCTAssertTrue(sawBelowSeat)
    }

    func testPoseFollowsTheRoutePathAtSampledProgress() {
        let rig = RouteRig()
        rig.go(4)
        let path = rig.path(from: 0, to: 4)
        XCTAssertGreaterThan(path.legs[0], 0, "sanity: a straight leg before the curve")

        rig.advance(65)
        var progress = 0.0
        for fraction in [0.05, 0.2, 0.35, 0.5, 0.65, 0.8, 0.95] {
            let target = path.totalLen * fraction
            rig.advance((target - progress) / path.totalLen * path.totalMs)
            progress = target
            assertPose(rig.controller.currentState, equals: PerchAround.aroundPose(path: path, s: target), "at s=\(target)")
        }
    }

    func testFacingIsSetOnceAtTheFocusAndNeverChangesDuringTheRoute() {
        let rig = RouteRig()
        rig.go(4)
        let path = rig.path(from: 0, to: 4)
        let atFocus = rig.controller.currentState.facing
        XCTAssertEqual(atFocus, path.facing)

        var changes = 0
        var last = atFocus
        rig.run(path.totalMs + 400) { state in
            if state.facing != last { changes += 1 }
            last = state.facing
        }
        XCTAssertEqual(changes, 0, "no facing change after the focus itself")
    }

    func testReactionPauseHoldsTheRouteStillThrough64msThenItMoves() {
        let rig = RouteRig()
        rig.go(4)
        let base = rig.controller.currentState

        rig.advance(64)
        let held = rig.controller.currentState
        XCTAssertEqual(held.x, base.x, accuracy: 1e-9)
        XCTAssertEqual(held.seatY, base.seatY, accuracy: 1e-9)
        XCTAssertEqual(held.rotationDegrees, base.rotationDegrees, accuracy: 1e-9)

        rig.advance(17)
        XCTAssertNotEqual(rig.controller.currentState.x, base.x, accuracy: 1e-6, "moving by the first tick after the pause")
    }

    func testFinishSeatsOnTheTargetAtRestWithNoTrackLeft() {
        let rig = RouteRig()
        rig.go(4)
        let path = rig.path(from: 0, to: 4)
        rig.run(path.totalMs + 65 + 3000)

        let state = rig.controller.currentState
        XCTAssertEqual(state.x, rig.seatX(4), accuracy: 0.5)
        XCTAssertEqual(state.seatY, 0, accuracy: 1e-9)
        XCTAssertEqual(state.rotationDegrees, 0, accuracy: 1e-9)
        XCTAssertEqual(state.pose, .sit)
        XCTAssertFalse(rig.perchTrackActive)
    }

    // MARK: - No route

    private func assertPlainRun(
        _ rig: RouteRig,
        to slot: Int,
        bottomExtra: Double = 0,
        expectRun: Bool = true,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        rig.go(slot, bottomExtra: bottomExtra)
        var sawRun = false
        var rotated = false
        rig.run(3000) { state in
            if state.pose == .run { sawRun = true }
            if state.rotationDegrees != 0 { rotated = true }
        }
        XCTAssertFalse(rotated, "\(message): rotation stays 0", file: file, line: line)
        XCTAssertEqual(sawRun, expectRun, "\(message): a plain run", file: file, line: line)
        XCTAssertEqual(rig.controller.currentState.x, rig.seatX(slot), accuracy: 0.5, "\(message): lands on the target", file: file, line: line)
    }

    func testNoRoute_ProfileWithoutAroundRoute() {
        let rig = RouteRig(profile: makeProfile(aroundRoute: false))
        assertPlainRun(rig, to: 4, "aroundRoute false")
    }

    func testNoRoute_FlightLiftAboveZero() {
        let rig = RouteRig(profile: makeProfile(flightLift: 10, aroundRoute: true))
        assertPlainRun(rig, to: 4, "flightLift above 0")
    }

    func testNoRoute_TwoSlotBar() {
        let rig = RouteRig(slotCount: 2)
        assertPlainRun(rig, to: 1, "two slots")
    }

    func testNoRoute_NoPill() {
        let rig = RouteRig(pill: nil)
        assertPlainRun(rig, to: 4, "no pill")
    }

    func testNoRoute_ReduceMotion() {
        let rig = RouteRig()
        rig.harness.reduceMotionFlag = true
        assertPlainRun(rig, to: 4, expectRun: false, "reduce motion")
    }

    func testNoRoute_RaisedSeat() {
        let rig = RouteRig()
        assertPlainRun(rig, to: 4, bottomExtra: 12, "raised seat")
    }

    func testNoRoute_SeatAlreadyRaised() {
        let rig = RouteRig()
        rig.go(0, bottomExtra: 12)
        rig.run(3000)
        assertPlainRun(rig, to: 4, bottomExtra: 12, "a seat already raised")
    }

    func testNoRoute_NotEndToEnd() {
        let rig = RouteRig()
        assertPlainRun(rig, to: 2, "slot 0 to slot 2")
    }

    // MARK: - Resume

    /// Starts slot 0 to slot 4 and stops mid first curve; returns the base path and progress.
    private func routeToMidCurve(_ rig: RouteRig) -> (path: AroundPath, s: Double) {
        rig.go(4)
        let path = rig.path(from: 0, to: 4)
        let s = path.legs[0] + path.arcLen / 2
        rig.advanceToProgress(s, of: path)
        return (path, s)
    }

    func testResumeStartsOnTheOutlineAtOnceAndMovesWithNoPause() {
        let rig = RouteRig()
        let (path, s) = routeToMidCurve(rig)
        guard let route = PerchAround.resumeAroundRoute(base: path, s: s, targetX: rig.seatX(2)) else {
            return XCTFail("expected a resumed route")
        }

        rig.go(2)
        let first = rig.controller.currentState
        assertPose(first, equals: PerchAround.resumedPose(route: route, u: 0), "first state of the new focus")
        XCTAssertNotEqual(first.rotationDegrees, 0, "on the curve, not seated")
        XCTAssertEqual(first.pose, .run)
        XCTAssertEqual(rig.harness.renderStates.last?.x ?? .nan, first.x, accuracy: 1e-9)

        rig.advance(8, frameMs: 8)
        XCTAssertNotEqual(rig.controller.currentState.x, first.x, accuracy: 1e-6, "no reaction pause")
    }

    func testResumeFinishesSeatedOnTheNewTarget() {
        let rig = RouteRig()
        _ = routeToMidCurve(rig)
        rig.go(2)
        rig.run(8000)

        let state = rig.controller.currentState
        XCTAssertEqual(state.x, rig.seatX(2), accuracy: 0.5)
        XCTAssertEqual(state.rotationDegrees, 0, accuracy: 1e-9)
        XCTAssertEqual(state.seatY, 0, accuracy: 1e-9)
        XCTAssertEqual(state.pose, .sit)
        XCTAssertFalse(rig.perchTrackActive)
    }

    func testInterruptOnAStraightLegIsAPlainRunFromTheLiveX() {
        let rig = RouteRig()
        rig.go(4)
        let path = rig.path(from: 0, to: 4)
        rig.advanceToProgress(path.legs[0] / 2, of: path)
        let liveX = rig.controller.currentState.x

        rig.go(2)
        XCTAssertEqual(rig.controller.currentState.x, liveX, accuracy: 1e-6)
        var rotated = false
        rig.run(3000) { if $0.rotationDegrees != 0 { rotated = true } }
        XCTAssertFalse(rotated)
        XCTAssertEqual(rig.controller.currentState.x, rig.seatX(2), accuracy: 0.5)
    }

    func testInterruptOfAResumedRouteResumesAgainFromTheMappedProgress() {
        let rig = RouteRig()
        let (path, s) = routeToMidCurve(rig)
        guard let first = PerchAround.resumeAroundRoute(base: path, s: s, targetX: rig.seatX(2)) else {
            return XCTFail("expected a resumed route")
        }
        rig.go(2)
        let u = first.curveLen / 2
        rig.advance(u / first.totalLen * first.totalMs)
        guard
            let mapped = PerchAround.resumedBaseS(route: first, u: u),
            let second = PerchAround.resumeAroundRoute(base: path, s: mapped, targetX: rig.seatX(3))
        else {
            return XCTFail("expected a second resumed route")
        }

        rig.go(3)
        let state = rig.controller.currentState
        assertPose(state, equals: PerchAround.resumedPose(route: second, u: 0), "second resume")
        XCTAssertNotEqual(state.rotationDegrees, 0)
        XCTAssertEqual(state.pose, .run)
    }

    func testAStagedInterruptIsConsumedOnce() {
        let rig = RouteRig()
        _ = routeToMidCurve(rig)
        rig.go(2)
        rig.run(8000)

        rig.go(3)
        var rotated = false
        rig.run(3000) { if $0.rotationDegrees != 0 { rotated = true } }
        XCTAssertFalse(rotated, "a later ordinary change is a plain run")
        XCTAssertEqual(rig.controller.currentState.x, rig.seatX(3), accuracy: 0.5)
    }

    func testHandoffAtAStagedBlurRecordsBarLevelAndTheLiveX() {
        let rig = RouteRig()
        _ = routeToMidCurve(rig)
        let before = rig.controller.currentState
        XCTAssertGreaterThan(before.seatY, 1, "sanity: hanging below the seat")

        rig.go(2, isFocused: false)

        let handoff = rig.harness.handoff.readPerchHandoff()
        XCTAssertEqual(handoff.lastSeat, PerchHandoff.liveLastSeat(bottomExtra: 0, seatY: 0), accuracy: 1e-9)
        XCTAssertEqual(handoff.lastX ?? .nan, before.x, accuracy: 1e-6)
    }

    func testAnInterruptWithANearbyTargetStillResumesInsteadOfSnapping() {
        let rig = RouteRig()
        let (path, s) = routeToMidCurve(rig)
        guard let route = PerchAround.resumeAroundRoute(base: path, s: s, targetX: rig.seatX(0)) else {
            return XCTFail("expected a resumed route")
        }

        rig.go(0)
        assertPose(rig.controller.currentState, equals: PerchAround.resumedPose(route: route, u: 0), "resumed, not snapped to the seat")
        XCTAssertEqual(rig.controller.currentState.pose, .run)
    }

    func testAnInterruptUnderReduceMotionIsAPlainRun() {
        let rig = RouteRig()
        _ = routeToMidCurve(rig)
        rig.harness.reduceMotionFlag = true

        rig.go(2)
        var rotated = false
        rig.run(3000) { if $0.rotationDegrees != 0 { rotated = true } }
        XCTAssertFalse(rotated)
        XCTAssertEqual(rig.controller.currentState.x, rig.seatX(2), accuracy: 0.5)
    }

    func testTheInterruptSurvivesAnUnfocusedPassAndTheNextFocusedPassResumes() {
        let rig = RouteRig()
        let (path, s) = routeToMidCurve(rig)
        rig.go(2, isFocused: false)
        rig.advance(200, frameMs: 8)
        guard let route = PerchAround.resumeAroundRoute(base: path, s: s, targetX: rig.seatX(2)) else {
            return XCTFail("expected a resumed route")
        }

        rig.go(2)
        assertPose(rig.controller.currentState, equals: PerchAround.resumedPose(route: route, u: 0), "resumed after the unfocused pass")
        XCTAssertEqual(rig.controller.currentState.pose, .run)
    }

    // MARK: - Remeasure, teardown, age limit

    func testRemeasureDuringARouteDoesNotMoveXOffTheRoute() {
        let rig = RouteRig()
        rig.harness.measureResult = nil
        rig.go(4)
        let path = rig.path(from: 0, to: 4)
        rig.advanceToProgress(path.legs[0] + path.arcLen / 2, of: path)
        let before = rig.controller.currentState.x

        rig.harness.measureResult = BarLayout(centers: [40, 120, 200, 280, 360])
        // Without a render tick, so only the remeasure itself can move x.
        rig.harness.clock.advance(ms: 20, frameMs: 20)

        XCTAssertEqual(rig.controller.currentState.x, before, accuracy: 1e-9)
    }

    func testTeardownMidRouteLeavesNoTrackActiveAndLaterTicksChangeNothing() {
        let rig = RouteRig()
        rig.go(4)
        let path = rig.path(from: 0, to: 4)
        rig.advanceToProgress(path.legs[0] + path.arcLen / 2, of: path)

        rig.controller.teardown()
        XCTAssertFalse(rig.perchTrackActive)

        let frozen = rig.controller.currentState
        rig.run(500)
        XCTAssertEqual(rig.controller.currentState, frozen)
    }

    func testAVeryLongRouteOutlivesTheEnginesDefaultAgeGuard() {
        let width = 9000.0
        let rig = RouteRig(screenWidth: width, pill: PillFrame(x: 16, y: 760, width: width - 32, height: 62))
        rig.go(4)
        let path = rig.path(from: 0, to: 4)
        XCTAssertGreaterThan(path.totalMs + 65, 10_000, "sanity: past the default age guard")

        rig.run(path.totalMs + 65 + 3000, frameMs: 16)

        XCTAssertEqual(rig.controller.currentState.x, rig.seatX(4), accuracy: 0.5)
        XCTAssertEqual(rig.controller.currentState.rotationDegrees, 0, accuracy: 1e-9)
        XCTAssertFalse(rig.perchTrackActive)
    }
}
