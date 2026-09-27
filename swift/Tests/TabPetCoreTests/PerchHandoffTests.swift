import XCTest

@testable import TabPetCore

// Pins increment 4 (perch handoff): lastTab / lastX / lastSeat sequences for
// focus, blur, drag, and transientSlot - without a renderer.
private let WIDTH = 402.0
private let SLOT_COUNT = 5
// stand-in for a raised seat (e.g. above a composer bar) above the tab bar
private let RAISED_SEAT = 24.0

private func tabX(_ tab: Int) -> Double {
    PerchGeometry.tabCenterX(tab: tab, screenWidth: WIDTH, slotCount: SLOT_COUNT)
}

private func isSpring(_ plan: ApproachPlan) -> Bool { plan == .spring }
private func isRun(_ plan: ApproachPlan) -> Bool {
    if case .run = plan { return true }
    return false
}
private func isTrack(_ plan: FarSamplePlan) -> Bool {
    if case .track = plan { return true }
    return false
}
private func isEnd(_ plan: FarSamplePlan) -> Bool { plan == .end }
private func isAwait(_ plan: DragReleasePlan) -> Bool {
    if case .await = plan { return true }
    return false
}

/// mirrors the TypeScript template literal `${bad}` in perch-handoff.test.ts's
/// testSanitizeRunSpeed - Swift's default Double/nil descriptions ("0.0",
/// "nan", "inf", "nil", ...) don't match JS's Number-to-string coercion, so
/// the assertion message text would otherwise diverge from the mirrored test.
private func jsNumberDescription(_ value: Double?) -> String {
    guard let value else { return "undefined" }
    if value.isNaN { return "NaN" }
    if value == .infinity { return "Infinity" }
    if value == -.infinity { return "-Infinity" }
    if value == value.rounded(), abs(value) < 1e15 {
        return String(Int(value))
    }
    return String(value)
}

/// Mirrors perch-handoff.test.ts: one XCTest method per TypeScript test
/// function, same name, same fixtures, same assertion messages. Object.is
/// semantics (ObjectIs.swift) stand in for a TypeScript strictEqual/
/// deepStrictEqual on a number, telling -0 from 0 and treating NaN as equal
/// to NaN; a manual tolerance check in the TypeScript (Math.abs(a-b) < 1e-9)
/// stays a tolerance check here, not an exact one. The TypeScript tests that
/// use the module's singleton store use a fresh PerchHandoffStore here.
@MainActor
final class PerchHandoffTests: XCTestCase {
    private func assertHandoffEqual(
        _ actual: PerchHandoffState,
        _ expected: PerchHandoffState,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.lastTab, expected.lastTab, message, file: file, line: line)
        switch (actual.lastX, expected.lastX) {
        case (nil, nil):
            break
        case (let a?, let e?):
            XCTAssertObjectIs(a, e, message, file: file, line: line)
        default:
            XCTFail(
                "\(message) (lastX: \(String(describing: actual.lastX)) vs \(String(describing: expected.lastX)))",
                file: file,
                line: line
            )
        }
        XCTAssertObjectIs(actual.lastSeat, expected.lastSeat, message, file: file, line: line)
    }

    func testInitialHandoff() {
        assertHandoffEqual(PerchHandoff.initialPerchHandoff(), PerchHandoffState(lastTab: 0, lastX: nil, lastSeat: 0))
    }

    func testTransientNeverWritesHandoff() {
        let start = PerchHandoffState(lastTab: 1, lastX: 120, lastSeat: RAISED_SEAT)
        let plan = PerchHandoff.planFocus(
            handoff: start, tab: 4, screenWidth: WIDTH, bottomExtra: RAISED_SEAT,
            transientSlot: true, reduceMotion: false, slotCount: SLOT_COUNT
        )
        XCTAssertEqual(plan.kind, .transientSnap)
        XCTAssertEqual(plan.commitsHandoff, false)
        assertHandoffEqual(plan.next, start, "transientSlot must not touch lastTab/lastX/lastSeat")
        let afterBlur = PerchHandoff.applyFocusBlur(handoff: start, currentX: 200, transientSlot: true)
        assertHandoffEqual(afterBlur, start, "transient blur must not write lastX")
    }

    func testSameTabSnapClearsLastX() {
        let start = PerchHandoffState(lastTab: 2, lastX: 180, lastSeat: 0)
        let plan = PerchHandoff.planFocus(
            handoff: start, tab: 2, screenWidth: WIDTH, bottomExtra: 0,
            transientSlot: false, reduceMotion: false, slotCount: SLOT_COUNT
        )
        XCTAssertEqual(plan.kind, .sameTabSnap)
        XCTAssertObjectIs(plan.fromX, tabX(2), "fromX")
        XCTAssertObjectIs(plan.fromSeatY, 0, "fromSeatY")
        assertHandoffEqual(plan.next, PerchHandoffState(lastTab: 2, lastX: nil, lastSeat: 0))
    }

    func testCrossTabChaseUsesLastXThenClears() {
        let from = tabX(0) + 40
        let start = PerchHandoffState(lastTab: 0, lastX: from, lastSeat: 0)
        let plan = PerchHandoff.planFocus(
            handoff: start, tab: 4, screenWidth: WIDTH, bottomExtra: 0,
            transientSlot: false, reduceMotion: false, slotCount: SLOT_COUNT
        )
        XCTAssertEqual(plan.kind, .runChase)
        XCTAssertObjectIs(plan.fromX, from, "chase starts from the frozen mid-traverse x")
        XCTAssertObjectIs(plan.targetX, tabX(4), "")
        XCTAssertTrue(abs(plan.targetX - plan.fromX) >= PerchGeometry.PERCH_SIZE, "fixture is a real run")
        assertHandoffEqual(plan.next, PerchHandoffState(lastTab: 4, lastX: nil, lastSeat: 0))
    }

    func testCrossTabFallsBackToLastTabCenter() {
        let start = PerchHandoffState(lastTab: 0, lastX: nil, lastSeat: 0)
        let plan = PerchHandoff.planFocus(
            handoff: start, tab: 3, screenWidth: WIDTH, bottomExtra: 0,
            transientSlot: false, reduceMotion: false, slotCount: SLOT_COUNT
        )
        XCTAssertEqual(plan.kind, .runChase)
        XCTAssertObjectIs(plan.fromX, tabX(0), "without lastX, origin is lastTab center")
    }

    func testAltitudeGlideUsesLastSeat() {
        let start = PerchHandoffState(lastTab: 4, lastX: tabX(4), lastSeat: RAISED_SEAT)
        let plan = PerchHandoff.planFocus(
            handoff: start, tab: 0, screenWidth: WIDTH, bottomExtra: 0,
            transientSlot: false, reduceMotion: false, slotCount: SLOT_COUNT
        )
        XCTAssertObjectIs(plan.fromSeatY, 0 - RAISED_SEAT, "land at bar level from the raised seat")
        XCTAssertObjectIs(plan.runSeatY, 0, "drop immediately when leaving the raised seat, do not float")
        XCTAssertObjectIs(plan.next.lastSeat, 0, "")
    }

    func testArriveAtRaisedSeatHoldsBarUntilCatch() {
        let start = PerchHandoffState(lastTab: 0, lastX: tabX(0), lastSeat: 0)
        let plan = PerchHandoff.planFocus(
            handoff: start, tab: 4, screenWidth: WIDTH, bottomExtra: RAISED_SEAT,
            transientSlot: false, reduceMotion: false, slotCount: SLOT_COUNT
        )
        XCTAssertEqual(plan.kind, .runChase)
        XCTAssertObjectIs(plan.fromSeatY, RAISED_SEAT, "raised-seat instance starts at bar (24pt down from the seat)")
        XCTAssertObjectIs(plan.runSeatY, RAISED_SEAT, "hold bar altitude during the run")
        assertHandoffEqual(plan.next, PerchHandoffState(lastTab: 4, lastX: nil, lastSeat: RAISED_SEAT))
    }

    func testPlanRunSeatYDirectional() {
        XCTAssertObjectIs(PerchHandoff.planRunSeatY(fromSeatY: RAISED_SEAT), RAISED_SEAT, "climb: hold the lower seat")
        XCTAssertObjectIs(PerchHandoff.planRunSeatY(fromSeatY: -RAISED_SEAT), 0, "descend: drop immediately")
        XCTAssertObjectIs(PerchHandoff.planRunSeatY(fromSeatY: 0), 0, "")
    }

    func testPlanStartSeatY() {
        let climb = PerchHandoff.planFocus(
            handoff: PerchHandoffState(lastTab: 0, lastX: tabX(0), lastSeat: 0),
            tab: 4, screenWidth: WIDTH, bottomExtra: RAISED_SEAT,
            transientSlot: false, reduceMotion: false, slotCount: SLOT_COUNT
        )
        XCTAssertObjectIs(
            PerchHandoff.planStartSeatY(kind: climb.kind, runSeatY: climb.runSeatY, fromSeatY: climb.fromSeatY),
            RAISED_SEAT,
            ""
        )

        let leave = PerchHandoff.planFocus(
            handoff: PerchHandoffState(lastTab: 4, lastX: tabX(4), lastSeat: RAISED_SEAT),
            tab: 0, screenWidth: WIDTH, bottomExtra: 0,
            transientSlot: false, reduceMotion: false, slotCount: SLOT_COUNT
        )
        XCTAssertObjectIs(
            PerchHandoff.planStartSeatY(kind: leave.kind, runSeatY: leave.runSeatY, fromSeatY: leave.fromSeatY),
            0,
            ""
        )

        // reduced-chase glides seatY to 0 over the transition, so the descent must not be clamped away
        let reducedLeave = PerchHandoff.planFocus(
            handoff: PerchHandoffState(lastTab: 4, lastX: tabX(4), lastSeat: RAISED_SEAT),
            tab: 0, screenWidth: WIDTH, bottomExtra: 0,
            transientSlot: false, reduceMotion: true, slotCount: SLOT_COUNT
        )
        XCTAssertEqual(reducedLeave.kind, .reducedChase)
        XCTAssertObjectIs(reducedLeave.fromSeatY, -RAISED_SEAT, "")
        XCTAssertObjectIs(
            PerchHandoff.planStartSeatY(kind: reducedLeave.kind, runSeatY: reducedLeave.runSeatY, fromSeatY: reducedLeave.fromSeatY),
            -RAISED_SEAT,
            "RM descent glide starts at raised-seat height"
        )

        let reducedClimb = PerchHandoff.planFocus(
            handoff: PerchHandoffState(lastTab: 0, lastX: tabX(0), lastSeat: 0),
            tab: 4, screenWidth: WIDTH, bottomExtra: RAISED_SEAT,
            transientSlot: false, reduceMotion: true, slotCount: SLOT_COUNT
        )
        XCTAssertObjectIs(
            PerchHandoff.planStartSeatY(kind: reducedClimb.kind, runSeatY: reducedClimb.runSeatY, fromSeatY: reducedClimb.fromSeatY),
            RAISED_SEAT,
            "RM climb glide starts at bar height"
        )
    }

    func testPlanMountSeatYSeedsFirstFrame() {
        let fromHome = PerchHandoffState(lastTab: 0, lastX: tabX(0), lastSeat: 0)
        let climb = PerchHandoff.planFocus(
            handoff: fromHome, tab: 4, screenWidth: WIDTH, bottomExtra: RAISED_SEAT,
            transientSlot: false, reduceMotion: false, slotCount: SLOT_COUNT
        )
        XCTAssertEqual(climb.kind, .runChase)

        let mount1 = PerchHandoff.planMountSeatY(
            handoff: fromHome, tab: 4, screenWidth: WIDTH, bottomExtra: RAISED_SEAT,
            transientSlot: false, reduceMotion: false, slotCount: SLOT_COUNT
        )
        XCTAssertObjectIs(
            mount1, RAISED_SEAT, "raised-seat mount first frame is bar height, not the seat itself (0)"
        )
        XCTAssertObjectIs(
            mount1,
            PerchHandoff.planStartSeatY(kind: climb.kind, runSeatY: climb.runSeatY, fromSeatY: climb.fromSeatY),
            "mount seed equals the focus snap - not a second altitude rule"
        )

        let mountReducedClimb = PerchHandoff.planMountSeatY(
            handoff: fromHome, tab: 4, screenWidth: WIDTH, bottomExtra: RAISED_SEAT,
            transientSlot: false, reduceMotion: true, slotCount: SLOT_COUNT
        )
        XCTAssertObjectIs(mountReducedClimb, RAISED_SEAT, "RM climb mount still starts at bar (fromSeatY), not 0")

        let fromRaisedSeat = PerchHandoffState(lastTab: 4, lastX: tabX(4), lastSeat: RAISED_SEAT)
        let mountLeave = PerchHandoff.planMountSeatY(
            handoff: fromRaisedSeat, tab: 0, screenWidth: WIDTH, bottomExtra: 0,
            transientSlot: false, reduceMotion: false, slotCount: SLOT_COUNT
        )
        XCTAssertObjectIs(mountLeave, 0, "leave-raised-seat run-chase mount is already at bar")

        let mountReducedLeave = PerchHandoff.planMountSeatY(
            handoff: fromRaisedSeat, tab: 0, screenWidth: WIDTH, bottomExtra: 0,
            transientSlot: false, reduceMotion: true, slotCount: SLOT_COUNT
        )
        XCTAssertObjectIs(mountReducedLeave, -RAISED_SEAT, "RM descent mount keeps fromSeatY so the glide is not a no-op")

        let mountTransient = PerchHandoff.planMountSeatY(
            handoff: fromHome, tab: 4, screenWidth: WIDTH, bottomExtra: RAISED_SEAT,
            transientSlot: true, reduceMotion: false, slotCount: SLOT_COUNT
        )
        XCTAssertObjectIs(mountTransient, 0, "transient mount stays at its own seat (no cross-tab first frame)")
    }

    func testBlurFreezesLiveSeatNotDestination() {
        let start = PerchHandoffState(lastTab: 4, lastX: nil, lastSeat: RAISED_SEAT)
        let midRise = PerchHandoff.liveLastSeat(bottomExtra: RAISED_SEAT, seatY: 12)
        XCTAssertObjectIs(midRise, 12, "seatY 12pt down from the raised seat is lastSeat 12")
        let stillAtBar = PerchHandoff.liveLastSeat(bottomExtra: RAISED_SEAT, seatY: RAISED_SEAT)
        XCTAssertObjectIs(stillAtBar, 0, "still at bar during a run toward the raised seat")
        let next = PerchHandoff.applyFocusBlur(handoff: start, currentX: tabX(0) + 90, transientSlot: false, currentSeat: stillAtBar)
        XCTAssertObjectIs(next.lastSeat, 0, "bounce-back must not keep the destination raised seat")
        XCTAssertObjectIs(next.lastX ?? .nan, tabX(0) + 90, "")
    }

    func testSnapToSeatWhenHandoffIsUnderOneGlass() {
        let start = PerchHandoffState(lastTab: 1, lastX: tabX(2) - 10, lastSeat: 0)
        let plan = PerchHandoff.planFocus(
            handoff: start, tab: 2, screenWidth: WIDTH, bottomExtra: 0,
            transientSlot: false, reduceMotion: false, slotCount: SLOT_COUNT
        )
        XCTAssertEqual(plan.kind, .snapToSeat)
        XCTAssertObjectIs(plan.fromX, plan.targetX, "")
    }

    func testHoldRunSkipsSnapToSeat() {
        let startLastX = tabX(2) - 30
        let start = PerchHandoffState(lastTab: 1, lastX: startLastX, lastSeat: 0)
        let defaultPlan = PerchHandoff.planFocus(
            handoff: start, tab: 2, screenWidth: WIDTH, bottomExtra: 0,
            transientSlot: false, reduceMotion: false, slotCount: SLOT_COUNT
        )
        XCTAssertEqual(defaultPlan.kind, .snapToSeat, "default: under one glass still snaps")
        let heldPlan = PerchHandoff.planFocus(
            handoff: start, tab: 2, screenWidth: WIDTH, bottomExtra: 0,
            transientSlot: false, reduceMotion: false, slotCount: SLOT_COUNT, holdRun: true
        )
        XCTAssertEqual(heldPlan.kind, .runChase, "holdRun: a route interrupt gets a real run instead")
        XCTAssertObjectIs(heldPlan.fromX, startLastX, "holdRun keeps the live fromX, not targetX")
        XCTAssertObjectIs(heldPlan.runSeatY, 0, "holdRun run starts at bar level")
    }

    func testHoldRunTreatsSameTabAsRunChase() {
        let startLastX = tabX(4) - 30
        let start = PerchHandoffState(lastTab: 4, lastX: startLastX, lastSeat: 0)
        let defaultPlan = PerchHandoff.planFocus(
            handoff: start, tab: 4, screenWidth: WIDTH, bottomExtra: 0,
            transientSlot: false, reduceMotion: false, slotCount: SLOT_COUNT
        )
        XCTAssertEqual(defaultPlan.kind, .sameTabSnap, "default: a re-tap of the current tab snaps")
        let heldPlan = PerchHandoff.planFocus(
            handoff: start, tab: 4, screenWidth: WIDTH, bottomExtra: 0,
            transientSlot: false, reduceMotion: false, slotCount: SLOT_COUNT, holdRun: true
        )
        XCTAssertEqual(heldPlan.kind, .runChase, "holdRun: a same-tab re-tap mid-route gets a run back to it too")
        XCTAssertObjectIs(heldPlan.fromX, startLastX, "holdRun keeps the live fromX for the same-tab case")
        XCTAssertObjectIs(heldPlan.targetX, tabX(4), "")
        XCTAssertObjectIs(heldPlan.runSeatY, 0, "")
    }

    func testReduceMotionIsReducedChase() {
        let start = PerchHandoffState(lastTab: 0, lastX: nil, lastSeat: 0)
        let plan = PerchHandoff.planFocus(
            handoff: start, tab: 4, screenWidth: WIDTH, bottomExtra: 0,
            transientSlot: false, reduceMotion: true, slotCount: SLOT_COUNT
        )
        XCTAssertEqual(plan.kind, .reducedChase)
    }

    func testBlurWritesActualXNotDestination() {
        let start = PerchHandoffState(lastTab: 4, lastX: nil, lastSeat: 0)
        let mid = tabX(0) + 90
        let next = PerchHandoff.applyFocusBlur(handoff: start, currentX: mid, transientSlot: false)
        XCTAssertObjectIs(next.lastX ?? .nan, mid, "mid-traverse blur hands off where the pup is")
        XCTAssertEqual(next.lastTab, 4, "blur does not rewrite lastTab - focus already did")
    }

    func testDragTrackWritesGlassAndBarLevel() {
        let start = PerchHandoffState(lastTab: 2, lastX: tabX(2), lastSeat: RAISED_SEAT)
        let next = PerchHandoff.applyDragTrack(handoff: start, glassTarget: 200)
        assertHandoffEqual(next, PerchHandoffState(lastTab: 2, lastX: 200, lastSeat: 0))
    }

    func testDragReleaseWritesOnlyWhenThisTabOwnsHandoff() {
        let owned = PerchHandoffState(lastTab: 2, lastX: 200, lastSeat: 0)
        assertHandoffEqual(
            PerchHandoff.applyDragRelease(handoff: owned, tab: 2, releaseX: 210, bottomExtra: RAISED_SEAT),
            PerchHandoffState(lastTab: 2, lastX: 210, lastSeat: RAISED_SEAT)
        )
        let stolen = PerchHandoffState(lastTab: 4, lastX: tabX(4), lastSeat: 0)
        assertHandoffEqual(
            PerchHandoff.applyDragRelease(handoff: stolen, tab: 2, releaseX: 210, bottomExtra: RAISED_SEAT),
            stolen,
            "ended after another tab consumed lastTab must not stomp"
        )
    }

    // literal expected values - never derived from planDragRelease's own condition
    func testPlanDragReleaseTable() {
        let currentSlot = 2
        let table: [(phase: DragPhase, releaseSlot: Int, selectsOnRelease: Bool, expected: DragReleasePlan)] = [
            (.ended, 3, true, .await(slot: 3)),
            (.ended, 3, false, .home),
            (.ended, 2, true, .home),
            (.ended, 2, false, .home),
            (.cancelled, 3, true, .home),
            (.cancelled, 3, false, .home),
            (.cancelled, 2, true, .home),
            (.cancelled, 2, false, .home),
        ]
        for row in table {
            let label = "phase=\(row.phase.rawValue) releaseSlot=\(row.releaseSlot) selectsOnRelease=\(row.selectsOnRelease)"
            let actual = PerchHandoff.planDragRelease(
                phase: row.phase, releaseSlot: row.releaseSlot, currentSlot: currentSlot, selectsOnRelease: row.selectsOnRelease
            )
            XCTAssertEqual(actual, row.expected, label)
        }
    }

    // literal expected values - never derived from selectsOnRelease's own expression
    func testSelectsOnReleaseAllCombinations() {
        let table: [(barScrub: BarScrub, hasOnDragRelease: Bool, nativePill: Bool, expected: Bool)] = [
            (.native, false, false, false),
            (.native, false, true, true),
            (.native, true, false, false),
            (.native, true, true, true),
            (.exclusive, false, false, false),
            (.exclusive, false, true, false),
            (.exclusive, true, false, true),
            (.exclusive, true, true, true),
        ]
        for row in table {
            let label = "barScrub=\(row.barScrub.rawValue) hasOnDragRelease=\(row.hasOnDragRelease) nativePill=\(row.nativePill)"
            let actual = PerchHandoff.selectsOnRelease(barScrub: row.barScrub, hasOnDragRelease: row.hasOnDragRelease, nativePill: row.nativePill)
            XCTAssertEqual(actual, row.expected, label)
        }
    }

    func testPlanApproach() {
        XCTAssertTrue(isSpring(PerchHandoff.planApproach(distancePt: 53.9)), "under one glass width is a spring")
        let at54 = PerchHandoff.planApproach(distancePt: 54)
        let atNeg54 = PerchHandoff.planApproach(distancePt: -54)
        XCTAssertTrue(isRun(at54), "exactly one glass width is a run")
        XCTAssertTrue(isRun(atNeg54), "negative distance is not under the threshold either")
        guard case .run(let at54Ms) = at54, case .run(let atNeg54Ms) = atNeg54 else {
            XCTFail("expected run plans")
            return
        }
        XCTAssertObjectIs(atNeg54Ms, at54Ms, "a negative distance behaves like its magnitude")
        // 54 / 340 * 1000 = 158.82ms raw, below the 400ms floor at the default speed
        XCTAssertObjectIs(at54Ms, 400, "a short run is clamped to the floor")
        guard case .run(let midRunMs) = PerchHandoff.planApproach(distancePt: 600) else {
            XCTFail("expected a run plan")
            return
        }
        // 600 / 340 * 1000, between the floor and ceiling so the raw linear rate applies
        XCTAssertObjectIs(midRunMs, 1764.7058823529412, "a mid-distance run uses the raw rate")
        guard case .run(let cappedMs) = PerchHandoff.planApproach(distancePt: 100_000) else {
            XCTFail("expected a run plan")
            return
        }
        // 100_000 / 340 * 1000 = 294117.6ms raw, above the 2200ms ceiling at the default speed
        XCTAssertObjectIs(cappedMs, 2200, "an extreme distance is clamped to the ceiling")
        guard case .run(let stretchedMs) = PerchHandoff.planApproach(distancePt: 200, speedPtS: 100) else {
            XCTFail("expected a run plan")
            return
        }
        // speed 100 stretches floor/ceiling by 340/100 = 3.4x (1360ms/7480ms); the
        // raw rate 200 / 100 * 1000 = 2000ms falls between them, so it applies unclamped
        XCTAssertObjectIs(stretchedMs, 2000, "a speed override stretches the floor and ceiling")
    }

    // literal expected values - never derived from isFarGrab's own expression
    func testIsFarGrab() {
        XCTAssertObjectIs(PerchHandoff.FAR_GRAB_PT, 54, "fixture assumes FAR_GRAB_PT === PERCH_SIZE")
        XCTAssertEqual(PerchHandoff.isFarGrab(gapPt: 54), false, "exactly the threshold is not far (strict greater-than)")
        XCTAssertEqual(PerchHandoff.isFarGrab(gapPt: 54.1), true)
        XCTAssertEqual(PerchHandoff.isFarGrab(gapPt: -54.1), true)
        XCTAssertEqual(PerchHandoff.isFarGrab(gapPt: 0), false)
    }

    // literal expected values - never derived from sanitizeRunSpeed's own expression
    func testSanitizeRunSpeed() {
        XCTAssertObjectIs(PerchHandoff.sanitizeRunSpeed(speed: 340), 340, "")
        XCTAssertObjectIs(PerchHandoff.sanitizeRunSpeed(speed: 200), 200, "")
        XCTAssertObjectIs(PerchHandoff.sanitizeRunSpeed(speed: 5000), 5000, "")
        let bad: [Double?] = [0, -5, .nan, .infinity, -.infinity, nil]
        for value in bad {
            XCTAssertObjectIs(
                PerchHandoff.sanitizeRunSpeed(speed: value), 340,
                "\(jsNumberDescription(value)) must fall back to TRAVERSE_SPEED_PT_S"
            )
        }
    }

    // literal expected values - never derived from stepToward's own expression
    func testStepToward() {
        let speed = 340.0
        let stepPt = 5.44 // 340 * 16 / 1000
        let base = PerchHandoff.stepToward(current: 0, target: 300, speedPtS: speed, dtMs: 16)
        XCTAssertTrue(abs(base.x - stepPt) < 1e-9, "dt 16 must step \(stepPt), got \(base.x)")
        XCTAssertEqual(base.arrived, false)

        let dtZero = PerchHandoff.stepToward(current: 0, target: 300, speedPtS: speed, dtMs: 0)
        XCTAssertObjectIs(dtZero.x, 0, "dt 0 makes no step")
        XCTAssertEqual(dtZero.arrived, false)

        let dtOverLong = PerchHandoff.stepToward(current: 0, target: 300, speedPtS: speed, dtMs: 1000)
        XCTAssertTrue(
            abs(dtOverLong.x - 11.56) < 1e-9,
            "dt above FAR_STEP_MAX_DT_MS clamps to 34ms (11.56pt), not the raw 1000ms"
        )
        XCTAssertEqual(dtOverLong.arrived, false)

        let leftward = PerchHandoff.stepToward(current: 100, target: 50, speedPtS: speed, dtMs: 16)
        XCTAssertTrue(
            abs(leftward.x - (100 - stepPt)) < 1e-9,
            "a target on the left moves him left by the same step"
        )
        XCTAssertEqual(leftward.arrived, false)

        let closeIn = PerchHandoff.stepToward(current: 298, target: 300, speedPtS: speed, dtMs: 16)
        XCTAssertObjectIs(closeIn.x, 300, "a step past the target lands exactly on it")
        XCTAssertEqual(closeIn.arrived, true)

        let already = PerchHandoff.stepToward(current: 50, target: 50, speedPtS: speed, dtMs: 16)
        XCTAssertObjectIs(already.x, 50, "current equal to target: x unchanged")
        XCTAssertEqual(already.arrived, true)

        // speed 0 at current === target: the speedPtS <= 0 guard returns not-arrived
        // before the arithmetic ever sees the zero distance - a mutation to < 0
        // would let speed 0 fall through and report arrived true instead
        let zeroSpeedAtTarget = PerchHandoff.stepToward(current: 50, target: 50, speedPtS: 0, dtMs: 16)
        XCTAssertObjectIs(zeroSpeedAtTarget.x, 50, "")
        XCTAssertEqual(zeroSpeedAtTarget.arrived, false, "the guard, not the arithmetic, decides")

        let nanTarget = PerchHandoff.stepToward(current: 10, target: .nan, speedPtS: speed, dtMs: 16)
        XCTAssertObjectIs(nanTarget.x, 10, "")
        XCTAssertEqual(nanTarget.arrived, false)
        let nanSpeed = PerchHandoff.stepToward(current: 10, target: 300, speedPtS: .nan, dtMs: 16)
        XCTAssertObjectIs(nanSpeed.x, 10, "")
        XCTAssertEqual(nanSpeed.arrived, false)
        let nanDt = PerchHandoff.stepToward(current: 10, target: 300, speedPtS: speed, dtMs: .nan)
        XCTAssertObjectIs(nanDt.x, 10, "")
        XCTAssertEqual(nanDt.arrived, false)
    }

    // A FIXED 300pt target at 340pt/s in 16ms steps: every step but the last
    // moves the raw 5.44pt/step; the last step clamps to the target exactly,
    // never past it. Steps counted by hand: 300 / 5.44 = 55.14..., so 55 full
    // steps (299.2pt) plus one clamped step to 300.
    func testStepTowardFixedTargetStepCount() {
        let speed = 340.0
        var x = 0.0
        var steps = 0
        var arrived = false
        while !arrived, steps < 200 {
            let result = PerchHandoff.stepToward(current: x, target: 300, speedPtS: speed, dtMs: 16)
            if steps < 55 {
                XCTAssertTrue(
                    abs(result.x - (x + 5.44)) < 1e-9,
                    "step \(steps) must move the raw 5.44pt, got \(result.x - x)"
                )
            }
            x = result.x
            arrived = result.arrived
            steps += 1
        }
        XCTAssertEqual(steps, 56, "closing 300pt at 5.44pt/step arrives on the 56th step")
        XCTAssertObjectIs(x, 300, "the last step lands exactly on the target, never past it")
    }

    // A MOVING target that recedes at 100pt/s: stepToward only sees the live
    // gap each call, so x still steps the raw 5.44pt/step (50 steps = 272pt);
    // the gap itself only closes by 5.44 - 1.6 = 3.84pt per step, so he has not
    // caught the ever-receding target.
    func testStepTowardRecedingTarget() {
        let speed = 340.0
        var x = 0.0
        var target = 300.0
        var arrived = false
        for _ in 0..<50 {
            target += 1.6 // recedes at 100pt/s over this 16ms step
            let result = PerchHandoff.stepToward(current: x, target: target, speedPtS: speed, dtMs: 16)
            x = result.x
            arrived = result.arrived
        }
        XCTAssertTrue(abs(x - 272) < 1e-9, "x after 50 receding steps must be 272, got \(x)")
        XCTAssertFalse(arrived, "a target receding faster than he closes on it is never reached")
    }

    // A MOVING target that approaches him still steps the raw 5.44pt/step -
    // stepToward only knows the live gap, not the target's own velocity.
    func testStepTowardApproachingTarget() {
        let speed = 340.0
        var x = 0.0
        var target = 300.0
        for i in 0..<3 {
            target -= 1.6 // approaches at 100pt/s over this 16ms step
            let result = PerchHandoff.stepToward(current: x, target: target, speedPtS: speed, dtMs: 16)
            XCTAssertTrue(
                abs(result.x - (x + 5.44)) < 1e-9,
                "step \(i) toward an approaching target must still move 5.44pt"
            )
            x = result.x
        }
    }

    // A target that jumps to the other side of him mid-approach reverses -
    // same 5.44pt/step magnitude, opposite direction.
    func testStepTowardTargetJumpsSides() {
        let speed = 340.0
        var x = 0.0
        x = PerchHandoff.stepToward(current: x, target: 300, speedPtS: speed, dtMs: 16).x
        x = PerchHandoff.stepToward(current: x, target: 300, speedPtS: speed, dtMs: 16).x
        XCTAssertTrue(abs(x - 10.88) < 1e-9, "two steps toward 300 land at 10.88")
        let jumpedTarget = x - 300 // now well to the left of x
        let reversed = PerchHandoff.stepToward(current: x, target: jumpedTarget, speedPtS: speed, dtMs: 16)
        XCTAssertTrue(
            abs(reversed.x - (x - 5.44)) < 1e-9,
            "a target jumping to the other side reverses, still 5.44pt/step"
        )
    }

    // Frame times that vary (8, 16, 33, 16, 8ms), none above FAR_STEP_MAX_DT_MS:
    // the distance covered equals speed * sum(dt) / 1000 exactly.
    func testStepTowardVariableFrameTimesSumExactly() {
        let speed = 340.0
        let dts: [Double] = [8, 16, 33, 16, 8]
        var x = 0.0
        let target = 10_000.0 // far enough that no arrival interrupts the sum
        for dt in dts {
            x = PerchHandoff.stepToward(current: x, target: target, speedPtS: speed, dtMs: dt).x
        }
        let totalDtS = dts.reduce(0, +) / 1000
        XCTAssertTrue(
            abs(x - speed * totalDtS) < 1e-9,
            "distance covered must equal speed * total dt exactly, got \(x)"
        )
    }

    // literal expected values - a mutation that drops the lower dt clamp must fail
    func testStepTowardNegativeDtDoesNotMove() {
        let result = PerchHandoff.stepToward(current: 50, target: 300, speedPtS: 340, dtMs: -5)
        XCTAssertObjectIs(result.x, 50, "a negative dt clamps to 0 - it must not step backward in time")
        XCTAssertEqual(result.arrived, false)
    }

    // literal expected values - non-finite inputs and a non-positive speed are total, not NaN-producing
    func testStepTowardTotalOnNonFiniteAndBadSpeed() {
        let infTarget = PerchHandoff.stepToward(current: 10, target: .infinity, speedPtS: 340, dtMs: 16)
        XCTAssertObjectIs(infTarget.x, 10, "")
        XCTAssertEqual(infTarget.arrived, false)
        let infSpeed = PerchHandoff.stepToward(current: 10, target: 300, speedPtS: .infinity, dtMs: 16)
        XCTAssertObjectIs(infSpeed.x, 10, "")
        XCTAssertEqual(infSpeed.arrived, false)
        let infDt = PerchHandoff.stepToward(current: 10, target: 300, speedPtS: 340, dtMs: .infinity)
        XCTAssertObjectIs(infDt.x, 10, "")
        XCTAssertEqual(infDt.arrived, false)
        let zeroSpeed = PerchHandoff.stepToward(current: 10, target: 300, speedPtS: 0, dtMs: 16)
        XCTAssertObjectIs(zeroSpeed.x, 10, "speed 0 must not freeze at a wrong x nor throw")
        XCTAssertEqual(zeroSpeed.arrived, false)
        let negSpeed = PerchHandoff.stepToward(current: 10, target: 300, speedPtS: -5, dtMs: 16)
        XCTAssertObjectIs(negSpeed.x, 10, "a negative speed must not reverse him")
        XCTAssertEqual(negSpeed.arrived, false)
        let nanCurrent = PerchHandoff.stepToward(current: .nan, target: 300, speedPtS: 340, dtMs: 16)
        XCTAssertTrue(nanCurrent.x.isNaN, "current itself not finite: x is returned as it is")
        XCTAssertEqual(nanCurrent.arrived, false)
    }

    // literal expected values - never derived from planFarSample's own expression;
    // worked out from CHASE_TRAIL (18) + CHASE_SLACK (4) = 22 and chaseTargetX
    func testPlanFarSample() {
        let screenWidth = WIDTH
        let endAtThreshold = PerchHandoff.planFarSample(glassX: 122, currentX: 100, screenWidth: screenWidth)
        XCTAssertTrue(isEnd(endAtThreshold), "gap of exactly 22 is inside the not-chasing edge")

        let tracksJustPast = PerchHandoff.planFarSample(glassX: 122.1, currentX: 100, screenWidth: screenWidth)
        XCTAssertTrue(isTrack(tracksJustPast))
        if case .track(let target, let facing) = tracksJustPast {
            XCTAssertEqual(facing, .right)
            XCTAssertTrue(abs(target - 104.1) < 1e-9, "expected 104.1, got \(target)")
        }

        let endAtNegThreshold = PerchHandoff.planFarSample(glassX: 78, currentX: 100, screenWidth: screenWidth)
        XCTAssertTrue(isEnd(endAtNegThreshold), "gap of exactly -22 is inside the not-chasing edge too")

        let tracksJustPastNeg = PerchHandoff.planFarSample(glassX: 77.9, currentX: 100, screenWidth: screenWidth)
        XCTAssertTrue(isTrack(tracksJustPastNeg))
        if case .track(let target, let facing) = tracksJustPastNeg {
            XCTAssertEqual(facing, .left, "a gap of -22.1 flips facing to -1")
            XCTAssertTrue(abs(target - 95.9) < 1e-9, "expected 95.9, got \(target)")
        }

        let bigGapFlips = PerchHandoff.planFarSample(glassX: 300, currentX: 0, screenWidth: screenWidth)
        XCTAssertTrue(isTrack(bigGapFlips))
        if case .track(let target, let facing) = bigGapFlips {
            XCTAssertEqual(facing, .right, "a gap of 300 is a positive gap, facing 1")
            XCTAssertObjectIs(target, 300 - 18, "target is glass - 18 once facing is 1")
        }

        let clampedLeft = PerchHandoff.planFarSample(glassX: 10, currentX: -20, screenWidth: screenWidth)
        XCTAssertTrue(isTrack(clampedLeft))
        if case .track(let target, _) = clampedLeft {
            XCTAssertObjectIs(target, 0, "chaseTargetX(10, 1, ...) = -8, clamped to the left edge")
        }

        let clampedRight = PerchHandoff.planFarSample(glassX: 345, currentX: 400, screenWidth: screenWidth)
        XCTAssertTrue(isTrack(clampedRight))
        if case .track(let target, _) = clampedRight {
            XCTAssertObjectIs(target, 348, "chaseTargetX(345, -1, ...) = 363, clamped to the right edge (402 - 54)")
        }

        let nanGlassEnds = PerchHandoff.planFarSample(glassX: .nan, currentX: 100, screenWidth: screenWidth)
        XCTAssertTrue(isEnd(nanGlassEnds), "NaN glassX is total, not a track toward NaN")
        let nanCurrentEnds = PerchHandoff.planFarSample(glassX: 122.1, currentX: .nan, screenWidth: screenWidth)
        XCTAssertTrue(isEnd(nanCurrentEnds), "NaN currentX is total, not a track toward NaN")
        let infGlassEnds = PerchHandoff.planFarSample(glassX: .infinity, currentX: 100, screenWidth: screenWidth)
        XCTAssertTrue(isEnd(infGlassEnds), "Infinity glassX is total, not a track toward Infinity")
    }

    func testFocusFromSlot() {
        XCTAssertEqual(PerchHandoff.focusFromSlot(handoffLastTab: 0, arrivedByDrag: true, focusedSlot: 3), 3, "arrived by drag: the focused slot wins as fromSlot")
        XCTAssertEqual(PerchHandoff.focusFromSlot(handoffLastTab: 0, arrivedByDrag: false, focusedSlot: 3), 0, "not arrived: falls back to handoffLastTab")
    }

    func testReplayFromPlanDragReleaseAwaitSnapsWhenCloseAtBlur() {
        let plan = PerchHandoff.planDragRelease(phase: .ended, releaseSlot: 3, currentSlot: 1, selectsOnRelease: true)
        XCTAssertTrue(isAwait(plan))
        guard case .await(let slot) = plan else {
            XCTFail("expected an await plan")
            return
        }
        let afterRelease = PerchHandoff.applyDragRelease(
            handoff: PerchHandoffState(lastTab: 1, lastX: tabX(1), lastSeat: 0),
            tab: 1, releaseX: tabX(slot) - 5, bottomExtra: 0
        )
        let liveXNearB = tabX(slot) - 10 // within one glass width of the awaited slot's seat
        let afterBlur = PerchHandoff.applyFocusBlur(handoff: afterRelease, currentX: liveXNearB, transientSlot: false)
        let focusPlan = PerchHandoff.planFocus(
            handoff: afterBlur, tab: slot, screenWidth: WIDTH, bottomExtra: 0,
            transientSlot: false, reduceMotion: false, slotCount: SLOT_COUNT
        )
        XCTAssertEqual(focusPlan.kind, .snapToSeat, "a live x within one glass width of the awaited slot snaps to seat")
    }

    func testReplayFromPlanDragReleaseGoesHomeWhenNothingSelects() {
        let plan = PerchHandoff.planDragRelease(phase: .ended, releaseSlot: 3, currentSlot: 1, selectsOnRelease: false)
        XCTAssertEqual(plan, .home, "nothing will select the slot - a chase home, not a wait")
    }

    func testReplayReleaseAwaitRunsWhenFarAtBlur() {
        let releaseX = tabX(3) - 120
        let afterRelease = PerchHandoff.applyDragRelease(
            handoff: PerchHandoffState(lastTab: 1, lastX: tabX(1), lastSeat: 0),
            tab: 1, releaseX: releaseX, bottomExtra: 0
        )
        let liveXFar = tabX(3) - 60 // approach closed some distance, still over one glass width out
        XCTAssertTrue(
            abs(liveXFar - tabX(3)) < abs(releaseX - tabX(3)),
            "live x is on B's side of the release point"
        )
        let afterBlur = PerchHandoff.applyFocusBlur(handoff: afterRelease, currentX: liveXFar, transientSlot: false)
        let plan = PerchHandoff.planFocus(
            handoff: afterBlur, tab: 3, screenWidth: WIDTH, bottomExtra: 0,
            transientSlot: false, reduceMotion: false, slotCount: SLOT_COUNT
        )
        XCTAssertEqual(plan.kind, .runChase)
        XCTAssertObjectIs(plan.fromX, liveXFar, "run-chase starts from the live x at blur, not the release point")
    }

    func testReplayDragReleaseWriteIsOverwrittenByBlur() {
        let afterRelease = PerchHandoff.applyDragRelease(
            handoff: PerchHandoffState(lastTab: 1, lastX: tabX(1), lastSeat: 0),
            tab: 1, releaseX: tabX(3) - 5, bottomExtra: 0
        )
        XCTAssertObjectIs(afterRelease.lastX ?? .nan, tabX(3) - 5, "")
        let liveX = tabX(1) + 30 // wherever he actually is by the time the blur runs
        let afterBlur = PerchHandoff.applyFocusBlur(handoff: afterRelease, currentX: liveX, transientSlot: false)
        XCTAssertObjectIs(
            afterBlur.lastX ?? .nan, liveX,
            "applyFocusBlur always overwrites the release write - nothing may rely on it surviving"
        )
    }

    func testSingletonReset() {
        let store = PerchHandoffStore()
        store.resetForTest()
        assertHandoffEqual(store.readPerchHandoff(), PerchHandoff.initialPerchHandoff())
        store.writePerchHandoff(next: PerchHandoffState(lastTab: 3, lastX: 99, lastSeat: 8))
        assertHandoffEqual(store.readPerchHandoff(), PerchHandoffState(lastTab: 3, lastX: 99, lastSeat: 8))
        store.resetForTest()
        assertHandoffEqual(store.readPerchHandoff(), PerchHandoff.initialPerchHandoff())
    }

    func testSharedStoreExistsAndFreshStoreStartsAtInitialHandoff() {
        XCTAssertTrue(PerchHandoffStore.shared === PerchHandoffStore.shared, "shared is a stable singleton")
        let fresh = PerchHandoffStore()
        assertHandoffEqual(fresh.readPerchHandoff(), PerchHandoff.initialPerchHandoff())
    }

    // a: release(await) -> focus-cleanup -> focus-body: await, clear-timer, arrived
    func testReduceReleaseSequenceA() {
        var state = PerchHandoff.initialReleaseState()
        var step = PerchHandoff.reduceRelease(state: state, event: .release(plan: .await(slot: 3), fromSlot: 1, generation: 1))
        state = step.state
        XCTAssertEqual(step.effect, .await)
        XCTAssertEqual(state, ReleaseState(pending: ReleaseState.Pending(fromSlot: 1, slot: 3, generation: 1), arrival: false))
        step = PerchHandoff.reduceRelease(state: state, event: .focusCleanup)
        state = step.state
        XCTAssertEqual(step.effect, .clearTimer)
        XCTAssertEqual(state, ReleaseState(pending: nil, arrival: true))
        step = PerchHandoff.reduceRelease(state: state, event: .focusBody(transientSlot: false))
        state = step.state
        XCTAssertEqual(step.effect, .arrived)
        XCTAssertEqual(state, ReleaseState(pending: nil, arrival: false))
    }

    // b: release(await) -> timer, slot unchanged: go-home; a second timer is none
    func testReduceReleaseSequenceB() {
        var state = PerchHandoff.initialReleaseState()
        var step = PerchHandoff.reduceRelease(state: state, event: .release(plan: .await(slot: 3), fromSlot: 1, generation: 1))
        state = step.state
        XCTAssertEqual(step.effect, .await)
        XCTAssertEqual(state, ReleaseState(pending: ReleaseState.Pending(fromSlot: 1, slot: 3, generation: 1), arrival: false))
        step = PerchHandoff.reduceRelease(state: state, event: .timer(mounted: true, generation: 1, renderedSlot: 1))
        state = step.state
        XCTAssertEqual(step.effect, .goHome)
        XCTAssertEqual(state, ReleaseState(pending: nil, arrival: false))
        step = PerchHandoff.reduceRelease(state: state, event: .timer(mounted: true, generation: 1, renderedSlot: 1))
        XCTAssertEqual(step.effect, .none, "a second timer event has nothing left pending")
        XCTAssertEqual(step.state, ReleaseState(pending: nil, arrival: false))
    }

    // c: release(await) -> timer with renderedSlot different: none, pending KEPT for the
    // focus-cleanup that is about to run -> focus-cleanup: clear-timer, arrival true, pending null
    // -> focus-body: arrived
    func testReduceReleaseSequenceC() {
        var state = PerchHandoff.initialReleaseState()
        var step = PerchHandoff.reduceRelease(state: state, event: .release(plan: .await(slot: 3), fromSlot: 1, generation: 1))
        state = step.state
        XCTAssertEqual(step.effect, .await)
        XCTAssertEqual(state, ReleaseState(pending: ReleaseState.Pending(fromSlot: 1, slot: 3, generation: 1), arrival: false))
        step = PerchHandoff.reduceRelease(state: state, event: .timer(mounted: true, generation: 1, renderedSlot: 4))
        state = step.state
        XCTAssertEqual(step.effect, .none)
        XCTAssertEqual(
            state,
            ReleaseState(pending: ReleaseState.Pending(fromSlot: 1, slot: 3, generation: 1), arrival: false),
            "the selection committed but focus has not run yet - pending survives for focus-cleanup"
        )
        step = PerchHandoff.reduceRelease(state: state, event: .focusCleanup)
        state = step.state
        XCTAssertEqual(step.effect, .clearTimer)
        XCTAssertEqual(state, ReleaseState(pending: nil, arrival: true))
        step = PerchHandoff.reduceRelease(state: state, event: .focusBody(transientSlot: false))
        XCTAssertEqual(step.effect, .arrived)
        XCTAssertEqual(step.state, ReleaseState(pending: nil, arrival: false))
    }

    // d: release(await) -> timer with a generation that differs from pending.generation: none,
    // pending cleared
    func testReduceReleaseSequenceD() {
        var state = PerchHandoff.initialReleaseState()
        var step = PerchHandoff.reduceRelease(state: state, event: .release(plan: .await(slot: 3), fromSlot: 1, generation: 1))
        state = step.state
        XCTAssertEqual(step.effect, .await)
        XCTAssertEqual(state, ReleaseState(pending: ReleaseState.Pending(fromSlot: 1, slot: 3, generation: 1), arrival: false))
        step = PerchHandoff.reduceRelease(state: state, event: .timer(mounted: true, generation: 2, renderedSlot: 1))
        XCTAssertEqual(step.effect, .none)
        XCTAssertEqual(step.state, ReleaseState(pending: nil, arrival: false))
    }

    // e: release(await) -> timer while unmounted: none, pending cleared
    func testReduceReleaseSequenceE() {
        var state = PerchHandoff.initialReleaseState()
        var step = PerchHandoff.reduceRelease(state: state, event: .release(plan: .await(slot: 3), fromSlot: 1, generation: 1))
        state = step.state
        XCTAssertEqual(step.effect, .await)
        XCTAssertEqual(state, ReleaseState(pending: ReleaseState.Pending(fromSlot: 1, slot: 3, generation: 1), arrival: false))
        step = PerchHandoff.reduceRelease(state: state, event: .timer(mounted: false, generation: 1, renderedSlot: 1))
        XCTAssertEqual(step.effect, .none)
        XCTAssertEqual(step.state, ReleaseState(pending: nil, arrival: false))
    }

    // f: release(await) -> began -> (a tap, no engage) -> timer: hold-generation, then go-home
    func testReduceReleaseSequenceF() {
        var state = PerchHandoff.initialReleaseState()
        var step = PerchHandoff.reduceRelease(state: state, event: .release(plan: .await(slot: 3), fromSlot: 1, generation: 1))
        state = step.state
        XCTAssertEqual(step.effect, .await)
        XCTAssertEqual(state, ReleaseState(pending: ReleaseState.Pending(fromSlot: 1, slot: 3, generation: 1), arrival: false))
        step = PerchHandoff.reduceRelease(state: state, event: .began)
        state = step.state
        XCTAssertEqual(step.effect, .holdGeneration)
        XCTAssertEqual(
            state,
            ReleaseState(pending: ReleaseState.Pending(fromSlot: 1, slot: 3, generation: 1), arrival: false),
            "a tap must not touch the pending release"
        )
        // no 'engage' event - the touch never travelled past DRAG_ENGAGE_PT
        step = PerchHandoff.reduceRelease(state: state, event: .timer(mounted: true, generation: 1, renderedSlot: 1))
        XCTAssertEqual(step.effect, .goHome, "the timer still fires after a tap that never engaged")
        XCTAssertEqual(step.state, ReleaseState(pending: nil, arrival: false))
    }

    // g: release(await) -> began -> engage: hold-generation, then clear-timer; a later timer is none
    func testReduceReleaseSequenceG() {
        var state = PerchHandoff.initialReleaseState()
        var step = PerchHandoff.reduceRelease(state: state, event: .release(plan: .await(slot: 3), fromSlot: 1, generation: 1))
        state = step.state
        XCTAssertEqual(step.effect, .await)
        XCTAssertEqual(state, ReleaseState(pending: ReleaseState.Pending(fromSlot: 1, slot: 3, generation: 1), arrival: false))
        step = PerchHandoff.reduceRelease(state: state, event: .began)
        state = step.state
        XCTAssertEqual(step.effect, .holdGeneration)
        XCTAssertEqual(state, ReleaseState(pending: ReleaseState.Pending(fromSlot: 1, slot: 3, generation: 1), arrival: false))
        step = PerchHandoff.reduceRelease(state: state, event: .engage)
        state = step.state
        XCTAssertEqual(step.effect, .clearTimer)
        XCTAssertEqual(state, ReleaseState(pending: nil, arrival: false))
        step = PerchHandoff.reduceRelease(state: state, event: .timer(mounted: true, generation: 1, renderedSlot: 1))
        XCTAssertEqual(step.effect, .none)
        XCTAssertEqual(step.state, ReleaseState(pending: nil, arrival: false))
    }

    // h: release(await) -> focus-cleanup -> focus-body(transientSlot): not arrived, arrival cleared
    func testReduceReleaseSequenceH() {
        var state = PerchHandoff.initialReleaseState()
        var step = PerchHandoff.reduceRelease(state: state, event: .release(plan: .await(slot: 3), fromSlot: 1, generation: 1))
        state = step.state
        XCTAssertEqual(step.effect, .await)
        XCTAssertEqual(state, ReleaseState(pending: ReleaseState.Pending(fromSlot: 1, slot: 3, generation: 1), arrival: false))
        step = PerchHandoff.reduceRelease(state: state, event: .focusCleanup)
        state = step.state
        XCTAssertEqual(step.effect, .clearTimer)
        XCTAssertEqual(state, ReleaseState(pending: nil, arrival: true))
        step = PerchHandoff.reduceRelease(state: state, event: .focusBody(transientSlot: true))
        XCTAssertEqual(step.effect, .none)
        XCTAssertEqual(step.state, ReleaseState(pending: nil, arrival: false))
    }

    // i: release(home): go-home, nothing pending; a later focus-body is not an arrival
    func testReduceReleaseSequenceI() {
        var state = PerchHandoff.initialReleaseState()
        var step = PerchHandoff.reduceRelease(state: state, event: .release(plan: .home, fromSlot: 1, generation: 1))
        state = step.state
        XCTAssertEqual(step.effect, .goHome)
        XCTAssertEqual(state, ReleaseState(pending: nil, arrival: false))
        step = PerchHandoff.reduceRelease(state: state, event: .focusBody(transientSlot: false))
        XCTAssertEqual(step.effect, .none)
        XCTAssertEqual(step.state, ReleaseState(pending: nil, arrival: false))
    }

    // j: focus-cleanup with nothing pending -> focus-body: not an arrival
    func testReduceReleaseSequenceJ() {
        var state = PerchHandoff.initialReleaseState()
        var step = PerchHandoff.reduceRelease(state: state, event: .focusCleanup)
        state = step.state
        XCTAssertEqual(step.effect, .none)
        XCTAssertEqual(state, ReleaseState(pending: nil, arrival: false))
        step = PerchHandoff.reduceRelease(state: state, event: .focusBody(transientSlot: false))
        XCTAssertEqual(step.effect, .none)
        XCTAssertEqual(step.state, ReleaseState(pending: nil, arrival: false))
    }

    // k: release(await) -> focus-cleanup -> focus-body -> focus-body: arrived exactly once
    func testReduceReleaseSequenceK() {
        var state = PerchHandoff.initialReleaseState()
        var step = PerchHandoff.reduceRelease(state: state, event: .release(plan: .await(slot: 3), fromSlot: 1, generation: 1))
        state = step.state
        XCTAssertEqual(step.effect, .await)
        XCTAssertEqual(state, ReleaseState(pending: ReleaseState.Pending(fromSlot: 1, slot: 3, generation: 1), arrival: false))
        step = PerchHandoff.reduceRelease(state: state, event: .focusCleanup)
        state = step.state
        XCTAssertEqual(step.effect, .clearTimer)
        XCTAssertEqual(state, ReleaseState(pending: nil, arrival: true))
        step = PerchHandoff.reduceRelease(state: state, event: .focusBody(transientSlot: false))
        state = step.state
        XCTAssertEqual(step.effect, .arrived)
        XCTAssertEqual(state, ReleaseState(pending: nil, arrival: false))
        step = PerchHandoff.reduceRelease(state: state, event: .focusBody(transientSlot: false))
        XCTAssertEqual(step.effect, .none, "arrived only once")
        XCTAssertEqual(step.state, ReleaseState(pending: nil, arrival: false))
    }

    // l: release(await) -> unmount -> timer: clear-timer, then none
    func testReduceReleaseSequenceL() {
        var state = PerchHandoff.initialReleaseState()
        var step = PerchHandoff.reduceRelease(state: state, event: .release(plan: .await(slot: 3), fromSlot: 1, generation: 1))
        state = step.state
        XCTAssertEqual(step.effect, .await)
        XCTAssertEqual(state, ReleaseState(pending: ReleaseState.Pending(fromSlot: 1, slot: 3, generation: 1), arrival: false))
        step = PerchHandoff.reduceRelease(state: state, event: .unmount)
        state = step.state
        XCTAssertEqual(step.effect, .clearTimer)
        XCTAssertEqual(state, ReleaseState(pending: nil, arrival: false))
        step = PerchHandoff.reduceRelease(state: state, event: .timer(mounted: true, generation: 1, renderedSlot: 1))
        XCTAssertEqual(step.effect, .none)
        XCTAssertEqual(step.state, ReleaseState(pending: nil, arrival: false))
    }

    // m: release(await) -> abort: clear-timer, pending null; a later timer is none; a later
    // focus-cleanup then focus-body is not an arrival
    func testReduceReleaseSequenceM() {
        var state = PerchHandoff.initialReleaseState()
        var step = PerchHandoff.reduceRelease(state: state, event: .release(plan: .await(slot: 3), fromSlot: 1, generation: 1))
        state = step.state
        XCTAssertEqual(step.effect, .await)
        XCTAssertEqual(state, ReleaseState(pending: ReleaseState.Pending(fromSlot: 1, slot: 3, generation: 1), arrival: false))
        step = PerchHandoff.reduceRelease(state: state, event: .abort)
        state = step.state
        XCTAssertEqual(step.effect, .clearTimer)
        XCTAssertEqual(state, ReleaseState(pending: nil, arrival: false))
        step = PerchHandoff.reduceRelease(state: state, event: .timer(mounted: true, generation: 1, renderedSlot: 1))
        state = step.state
        XCTAssertEqual(step.effect, .none)
        XCTAssertEqual(state, ReleaseState(pending: nil, arrival: false))
        step = PerchHandoff.reduceRelease(state: state, event: .focusCleanup)
        state = step.state
        XCTAssertEqual(step.effect, .none)
        XCTAssertEqual(state, ReleaseState(pending: nil, arrival: false))
        step = PerchHandoff.reduceRelease(state: state, event: .focusBody(transientSlot: false))
        XCTAssertEqual(step.effect, .none, "not an arrival - abort cleared pending before it could")
        XCTAssertEqual(step.state, ReleaseState(pending: nil, arrival: false))
    }

    // n: abort with nothing pending: none
    func testReduceReleaseSequenceN() {
        let state = PerchHandoff.initialReleaseState()
        let step = PerchHandoff.reduceRelease(state: state, event: .abort)
        XCTAssertEqual(step.effect, .none)
        XCTAssertEqual(step.state, ReleaseState(pending: nil, arrival: false))
    }

    // o: release(await) -> focus-cleanup sets arrival -> unmount: arrival cleared alongside
    // pending, effect none - unmount must not leave arrival set for the next mount to see
    func testReduceReleaseSequenceO() {
        var state = PerchHandoff.initialReleaseState()
        var step = PerchHandoff.reduceRelease(state: state, event: .release(plan: .await(slot: 3), fromSlot: 1, generation: 1))
        state = step.state
        XCTAssertEqual(step.effect, .await)
        step = PerchHandoff.reduceRelease(state: state, event: .focusCleanup)
        state = step.state
        XCTAssertEqual(step.effect, .clearTimer)
        XCTAssertEqual(state, ReleaseState(pending: nil, arrival: true))
        step = PerchHandoff.reduceRelease(state: state, event: .unmount)
        XCTAssertEqual(step.effect, .none, "nothing pending left to clear a timer for")
        XCTAssertEqual(step.state, ReleaseState(pending: nil, arrival: false), "unmount clears arrival too")
    }
}
