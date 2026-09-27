import XCTest

import TabPetCore

// number of tab slots in the reference host app's bar - kept as a plain
// fixture so this module has no opinion on any particular app's tab layout
private let SLOT_COUNT = 5

final class PerchGeometryTests: XCTestCase {
    func testPerchCenteredOverEachTabSlot() {
        let width = 402.0 // iPhone 16 Pro pt
        let barWidth = width - 2 * PerchGeometry.BAR_MARGIN_H
        let slotWidth = barWidth / Double(SLOT_COUNT)
        for tab in 0..<SLOT_COUNT {
            let slotCenter = PerchGeometry.BAR_MARGIN_H + slotWidth * (Double(tab) + 0.5)
            let perchCenter =
                PerchGeometry.tabCenterX(tab: tab, screenWidth: width, slotCount: SLOT_COUNT) + PerchGeometry.PERCH_SIZE / 2
            XCTAssertEqual(perchCenter, slotCenter, "tab \(tab) perch center")
        }
    }

    func testPerchStaysOnScreenAtAllWidths() {
        for width in [320.0, 375.0, 402.0, 430.0, 744.0, 1024.0] {
            let first = PerchGeometry.tabCenterX(tab: 0, screenWidth: width, slotCount: SLOT_COUNT)
            let last = PerchGeometry.tabCenterX(tab: SLOT_COUNT - 1, screenWidth: width, slotCount: SLOT_COUNT)
            XCTAssertTrue(first >= 0, "width \(width): first tab on-screen")
            XCTAssertTrue(last + PerchGeometry.PERCH_SIZE <= width, "width \(width): last tab on-screen")
            XCTAssertTrue(last > first, "width \(width): tabs ordered left-to-right")
        }
    }

    func testGlassTargetXCentersOnFinger() {
        let width = 402.0
        let fingerX = 200.0
        XCTAssertEqual(
            PerchGeometry.glassTargetX(fingerX: fingerX, screenWidth: width),
            fingerX - PerchGeometry.PERCH_SIZE / 2,
            "centers under the finger"
        )
    }

    func testGlassTargetXClampsLeftEdge() {
        let width = 402.0
        XCTAssertEqual(PerchGeometry.glassTargetX(fingerX: 0, screenWidth: width), 0, "clamps to the left screen edge")
        XCTAssertEqual(
            PerchGeometry.glassTargetX(fingerX: -50, screenWidth: width),
            0,
            "clamps a negative finger x to the left edge"
        )
    }

    func testGlassTargetXClampsRightEdge() {
        let width = 402.0
        XCTAssertEqual(
            PerchGeometry.glassTargetX(fingerX: width, screenWidth: width),
            width - PerchGeometry.PERCH_SIZE,
            "clamps to the right screen edge"
        )
        XCTAssertEqual(
            PerchGeometry.glassTargetX(fingerX: width + 100, screenWidth: width),
            width - PerchGeometry.PERCH_SIZE,
            "clamps a finger x past the edge to the right edge"
        )
    }

    func testChaseTargetTrailsTravelDirection() {
        let width = 402.0
        let glassX = 180.0
        XCTAssertEqual(
            PerchGeometry.chaseTargetX(glassX: glassX, direction: .right, screenWidth: width),
            glassX - PerchGeometry.CHASE_TRAIL,
            "trails a right-moving glass"
        )
        XCTAssertEqual(
            PerchGeometry.chaseTargetX(glassX: glassX, direction: .left, screenWidth: width),
            glassX + PerchGeometry.CHASE_TRAIL,
            "trails a left-moving glass"
        )
    }

    func testChaseTargetClampsAtEdges() {
        let width = 402.0
        XCTAssertEqual(
            PerchGeometry.chaseTargetX(glassX: 0, direction: .right, screenWidth: width),
            0,
            "rightward chase stays on the left edge"
        )
        XCTAssertEqual(
            PerchGeometry.chaseTargetX(glassX: width - PerchGeometry.PERCH_SIZE, direction: .left, screenWidth: width),
            width - PerchGeometry.PERCH_SIZE,
            "leftward chase stays on the right edge"
        )
    }

    func testTravelFacingFollowsActualTravel() {
        // companion far left, target far right: he travels right regardless of finger wiggle
        XCTAssertEqual(
            PerchGeometry.travelFacing(targetX: 300, currentX: 50, currentFacing: .left),
            .right,
            "faces right toward a far-right target"
        )
        XCTAssertEqual(
            PerchGeometry.travelFacing(targetX: 50, currentX: 300, currentFacing: .right),
            .left,
            "faces left toward a far-left target"
        )
    }

    func testTravelFacingHoldsInsideDeadband() {
        XCTAssertEqual(
            PerchGeometry.travelFacing(targetX: 100, currentX: 100, currentFacing: .left),
            .left,
            "zero delta holds current facing"
        )
        XCTAssertEqual(
            PerchGeometry.travelFacing(targetX: 100 + PerchGeometry.FACING_DEADBAND, currentX: 100, currentFacing: .left),
            .left,
            "delta at the deadband boundary still holds"
        )
        XCTAssertEqual(
            PerchGeometry.travelFacing(
                targetX: 100 + PerchGeometry.FACING_DEADBAND + 1, currentX: 100, currentFacing: .left
            ),
            .right,
            "delta past the deadband flips"
        )
    }

    func testTravelFacingDeadbandStaysUnderChaseTrail() {
        // steady tracking parks the companion CHASE_TRAIL behind the glass; the deadband
        // must not swallow that offset or the mirror would oscillate mid-drag
        XCTAssertTrue(PerchGeometry.FACING_DEADBAND < PerchGeometry.CHASE_TRAIL, "deadband must stay below the chase trail")
    }

    func testChaseStepHoldsInsideLeash() {
        XCTAssertEqual(
            PerchGeometry.chaseStep(glassX: 100, currentX: 100, currentFacing: .right, chasing: false),
            ChaseStep(target: nil, facing: .right),
            "glass directly over the companion: stand"
        )
        XCTAssertEqual(
            PerchGeometry.chaseStep(glassX: 100 + PerchGeometry.CHASE_TRAIL, currentX: 100, currentFacing: .left, chasing: false),
            ChaseStep(target: nil, facing: .left),
            "gap at the leash still holds, facing untouched"
        )
        XCTAssertEqual(
            PerchGeometry.chaseStep(glassX: 100 - PerchGeometry.CHASE_TRAIL, currentX: 100, currentFacing: .right, chasing: false),
            ChaseStep(target: nil, facing: .right),
            "glass slightly behind: he does NOT walk backward"
        )
    }

    func testChaseStepChasesBeyondLeash() {
        let start = PerchGeometry.CHASE_TRAIL + PerchGeometry.CHASE_SLACK + 1
        XCTAssertEqual(
            PerchGeometry.chaseStep(glassX: 100 + start, currentX: 100, currentFacing: .left, chasing: false),
            ChaseStep(target: 100 + start - PerchGeometry.CHASE_TRAIL, facing: .right),
            "leash taut to the right: chase to trailing distance, face right"
        )
        XCTAssertEqual(
            PerchGeometry.chaseStep(glassX: 100 - start, currentX: 100, currentFacing: .right, chasing: false),
            ChaseStep(target: 100 - start + PerchGeometry.CHASE_TRAIL, facing: .left),
            "leash taut to the left: chase to trailing distance, face left"
        )
    }

    func testChaseStepHysteresis() {
        let hover = PerchGeometry.CHASE_TRAIL + 1 // inside the band either way
        XCTAssertEqual(
            PerchGeometry.chaseStep(glassX: 100 + hover, currentX: 100, currentFacing: .right, chasing: false),
            ChaseStep(target: nil, facing: .right),
            "standing: a gap just past the bare leash does not start a chase"
        )
        XCTAssertEqual(
            PerchGeometry.chaseStep(glassX: 100 + hover, currentX: 100, currentFacing: .right, chasing: true),
            ChaseStep(target: 100 + hover - PerchGeometry.CHASE_TRAIL, facing: .right),
            "chasing: the same gap keeps the chase alive"
        )
        XCTAssertEqual(
            PerchGeometry.chaseStep(
                glassX: 100 + PerchGeometry.CHASE_TRAIL - PerchGeometry.CHASE_SLACK,
                currentX: 100,
                currentFacing: .right,
                chasing: true
            ),
            ChaseStep(target: nil, facing: .right),
            "chasing: he stands down only once well inside the leash"
        )
    }

    func testTraverseDurationMsClampsToFloor() {
        XCTAssertEqual(PerchGeometry.traverseDurationMs(distancePt: 0), PerchGeometry.MIN_TRAVERSE_MS, "zero distance clamps to the floor")
        XCTAssertEqual(
            PerchGeometry.traverseDurationMs(distancePt: 80),
            PerchGeometry.MIN_TRAVERSE_MS,
            "one-tab-ish distance clamps to the floor, keeping short hops feeling unchanged"
        )
    }

    func testTraverseDurationMsClampsToCeiling() {
        XCTAssertEqual(
            PerchGeometry.traverseDurationMs(distancePt: 100_000),
            PerchGeometry.MAX_TRAVERSE_MS,
            "a pathologically long distance clamps to the ceiling"
        )
    }

    func testTraverseDurationMsFollowsConstantSpeedUnclamped() {
        // pick a distance whose raw duration lands strictly between the clamps
        let distance = 600.0
        let expected = (distance / PerchGeometry.TRAVERSE_SPEED_PT_S) * 1000
        XCTAssertTrue(expected > PerchGeometry.MIN_TRAVERSE_MS && expected < PerchGeometry.MAX_TRAVERSE_MS, "fixture sits between the clamps")
        XCTAssertEqual(
            PerchGeometry.traverseDurationMs(distancePt: distance),
            expected,
            "unclamped distance follows the constant speed"
        )
    }

    func testTraverseDurationMsLongerTraverseTakesLonger() {
        // a leftmost-to-rightmost tap on a reference-width screen should read
        // clearly longer than a single adjacent-tab hop
        let oneTabHop = PerchGeometry.traverseDurationMs(distancePt: 80)
        let fullWidthTraverse = PerchGeometry.traverseDurationMs(distancePt: 296)
        XCTAssertTrue(fullWidthTraverse > oneTabHop, "a longer distance takes visibly longer to traverse")
    }

    func testTraverseDurationMsIgnoresSign() {
        XCTAssertEqual(
            PerchGeometry.traverseDurationMs(distancePt: -296),
            PerchGeometry.traverseDurationMs(distancePt: 296),
            "direction does not change how long the traverse takes"
        )
    }

    func testTraverseDurationMsSpeedOverride() {
        let speed = PerchGeometry.TRAVERSE_SPEED_PT_S / 2
        XCTAssertEqual(
            PerchGeometry.traverseDurationMs(distancePt: 600, speedPtS: speed),
            PerchGeometry.traverseDurationMs(distancePt: 600) * 2,
            "half speed doubles an unclamped traverse"
        )
        XCTAssertEqual(
            PerchGeometry.traverseDurationMs(distancePt: 80, speedPtS: speed),
            PerchGeometry.MIN_TRAVERSE_MS * 2,
            "the floor stretches with the override - a slow animal stays slow on a short hop"
        )
        XCTAssertEqual(
            PerchGeometry.traverseDurationMs(distancePt: 100_000, speedPtS: speed),
            PerchGeometry.MAX_TRAVERSE_MS * 2,
            "the ceiling stretches with the override"
        )
        XCTAssertEqual(
            PerchGeometry.traverseDurationMs(distancePt: 600, speedPtS: PerchGeometry.TRAVERSE_SPEED_PT_S),
            PerchGeometry.traverseDurationMs(distancePt: 600),
            "passing the default speed matches the no-arg call"
        )
    }

    func testShouldSnapToSeatPinsThreshold() {
        XCTAssertEqual(PerchGeometry.PERCH_SIZE, 54, "fixture assumes the current glass-width value")
        XCTAssertEqual(PerchGeometry.shouldSnapToSeat(distancePt: 53.9), true, "just under one glass width still snaps")
        XCTAssertEqual(PerchGeometry.shouldSnapToSeat(distancePt: 54), false, "exactly one glass width no longer snaps (strict <)")
    }

    func testShouldSnapToSeatTrivialNearZero() {
        XCTAssertEqual(PerchGeometry.shouldSnapToSeat(distancePt: 0), true, "zero distance snaps")
        XCTAssertEqual(PerchGeometry.shouldSnapToSeat(distancePt: 2), true, "the old <2 threshold is well inside the new one")
    }

    func testSeatedFootPadFollowsScale() {
        XCTAssertEqual(PerchGeometry.seatedFootPad(footPad: 11, scale: 1), 11, "identity at reference size")
        // a 1.25x figure's feet land lower in the box, so the seat pads less
        XCTAssertEqual(PerchGeometry.seatedFootPad(footPad: 11.025, scale: 1.25), 7.03125, accuracy: 1e-9, "scaled up pads less")
        // a 0.72x figure's feet float higher, so the seat pads more
        XCTAssertEqual(PerchGeometry.seatedFootPad(footPad: 11, scale: 0.72), 15.48, accuracy: 1e-9, "scaled down pads more")
    }

    func testNearestSlotPicksClosestCenter() {
        let width = 402.0
        // even split, 4 slots: centers at 62.25, 154.75, 247.25, 339.75
        XCTAssertEqual(PerchGeometry.nearestSlot(x: 0, screenWidth: width, slotCount: 4), 0)
        XCTAssertEqual(PerchGeometry.nearestSlot(x: 108, screenWidth: width, slotCount: 4), 0)
        XCTAssertEqual(PerchGeometry.nearestSlot(x: 109, screenWidth: width, slotCount: 4), 1)
        XCTAssertEqual(PerchGeometry.nearestSlot(x: 300, screenWidth: width, slotCount: 4), 3)
        XCTAssertEqual(PerchGeometry.nearestSlot(x: 402, screenWidth: width, slotCount: 4), 3)
        // measured centers win over the even split
        let centers = [40.0, 120.0, 300.0]
        XCTAssertEqual(PerchGeometry.nearestSlot(x: 200, screenWidth: width, slotCount: 3, slotCenters: centers), 1)
        XCTAssertEqual(PerchGeometry.nearestSlot(x: 215, screenWidth: width, slotCount: 3, slotCenters: centers), 2)
    }

    // measured centers win over the even split, and a missing entry falls back
    func testMeasuredCentersWinAndMissingEntryFallsBack() {
        let centers = [40.0, 120.0, 200.0]
        XCTAssertEqual(
            PerchGeometry.tabCenterX(tab: 1, screenWidth: 390, slotCount: 3, slotCenters: centers),
            120 - PerchGeometry.PERCH_SIZE / 2,
            "measured center used"
        )
        XCTAssertEqual(
            PerchGeometry.tabCenterX(tab: 2, screenWidth: 390, slotCount: 5, slotCenters: [40, 120]),
            PerchGeometry.tabCenterX(tab: 2, screenWidth: 390, slotCount: 5),
            "missing entry falls back"
        )
    }

    // Swift-only: the type system makes out-of-range/negative indices and zero
    // slot counts reachable without an optional-chaining undefined check.
    func testTabCenterXIgnoresOutOfRangeAndNegativeTab() {
        let width = 402.0
        let centers = [40.0, 120.0, 200.0]
        XCTAssertEqual(
            PerchGeometry.tabCenterX(tab: -1, screenWidth: width, slotCount: 3, slotCenters: centers),
            PerchGeometry.tabCenterX(tab: -1, screenWidth: width, slotCount: 3),
            "negative tab falls back to the even split"
        )
        XCTAssertEqual(
            PerchGeometry.tabCenterX(tab: 5, screenWidth: width, slotCount: 3, slotCenters: centers),
            PerchGeometry.tabCenterX(tab: 5, screenWidth: width, slotCount: 3),
            "out-of-range tab falls back to the even split"
        )
    }

    func testNearestSlotWithZeroSlotsReturnsZero() {
        XCTAssertEqual(PerchGeometry.nearestSlot(x: 100, screenWidth: 402, slotCount: 0), 0, "zero slots returns 0 without looping")
        XCTAssertEqual(PerchGeometry.nearestSlot(x: 100, screenWidth: 402, slotCount: -1), 0, "negative slot count returns 0 without looping")
    }

    func testClampDoesNotTrapOnScreenNarrowerThanPerch() {
        let width = 30.0 // narrower than PERCH_SIZE, so the clamp's upper bound is below its lower bound
        XCTAssertEqual(
            PerchGeometry.glassTargetX(fingerX: 1000, screenWidth: width),
            width - PerchGeometry.PERCH_SIZE,
            "returns the upper bound instead of trapping like a ClosedRange would"
        )
        XCTAssertEqual(
            PerchGeometry.chaseTargetX(glassX: 1000, direction: .right, screenWidth: width),
            width - PerchGeometry.PERCH_SIZE,
            "the min(max()) nesting returns the upper bound"
        )
        XCTAssertEqual(
            PerchGeometry.glassTargetX(fingerX: 0, screenWidth: width),
            width - PerchGeometry.PERCH_SIZE,
            "the min(max()) nesting returns the upper bound, -24"
        )
    }

    func testTraverseDurationMsZeroSpeedMatchesJavaScript() {
        XCTAssertTrue(
            PerchGeometry.traverseDurationMs(distancePt: 0, speedPtS: 0).isNaN,
            "0/0 is NaN, matching Math.min/Math.max NaN propagation"
        )
        XCTAssertEqual(
            PerchGeometry.traverseDurationMs(distancePt: 100, speedPtS: 0),
            .infinity,
            "stretch and raw are both Infinity in JavaScript, and the clamps leave Infinity"
        )
    }

    func testFacingRawValuesMatchTypeScript() {
        XCTAssertEqual(Facing.left.rawValue, -1)
        XCTAssertEqual(Facing.right.rawValue, 1)
    }
}
