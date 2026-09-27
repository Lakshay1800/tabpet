import Foundation
import XCTest

import TabPetCore

// pill, footPad, and seatOffset shared by every planAroundPath fixture below
private let PILL = PillFrame(x: 24, y: 800, width: 354, height: 64)
private let FOOT_PAD = 11.0
private let SEAT_OFFSET = -5.0
private let SPRITE_SCALE = 0.72
private let WINDOW_WIDTH = 402.0
private let HEAD_PAD = 0.0

// slot 0 -> 4 of 5 on the shared fixture
private let FROM_X = 40.0
private let TARGET_X = 320.0

private let FIT_TOLERANCE = 0.5
private let ARC_EPSILON = 1e-6

// a target left/right of the pill center (201), used by the resume tests -
// arbitrary window x's, not tied to any particular slot layout
private let LEFT_TARGET_X = 120.0
private let RIGHT_TARGET_X = 280.0
private let RESUME_EPSILON = 1e-9

/// planAroundPath with the shared PILL/footPad/seatOffset/spriteScale fixture
private func plan(fromX: Double, targetX: Double, headPad: Double = HEAD_PAD) -> AroundPath {
    PerchAround.planAroundPath(
        fromX: fromX,
        targetX: targetX,
        pill: PILL,
        windowWidth: WINDOW_WIDTH,
        spriteScale: SPRITE_SCALE,
        footPad: FOOT_PAD,
        headPad: headPad,
        seatOffset: SEAT_OFFSET
    )
}

/// window-space y of the drawn feet for a given seatY (the pivot keeps the
/// feet there through every rotation)
private func feetY(_ seatY: Double) -> Double {
    let boxCenterY0 = PILL.y - SEAT_OFFSET - PerchGeometry.PERCH_SIZE / 2
    return boxCenterY0 + seatY + PerchAround.routePivot(spriteScale: SPRITE_SCALE, footPad: FOOT_PAD)
}

/// which of the 5 legs s falls in, matching aroundPose's own boundaries
private func legOf(_ path: AroundPath, _ s: Double) -> Int {
    let legs = path.legs
    if s <= legs[0] {
        return 1
    }
    if s <= legs[1] {
        return 2
    }
    if s <= legs[2] {
        return 3
    }
    if s <= legs[3] {
        return 4
    }
    return 5
}

private struct PathSample {
    let s: Double
    let pose: AroundPose
}

private func samplePath(_ path: AroundPath) -> [PathSample] {
    var samples: [PathSample] = []
    var s = 0.0
    while s <= path.totalLen {
        samples.append(PathSample(s: s, pose: PerchAround.aroundPose(path: path, s: s)))
        s += 1
    }
    if let last = samples.last, last.s != path.totalLen {
        samples.append(PathSample(s: path.totalLen, pose: PerchAround.aroundPose(path: path, s: path.totalLen)))
    }
    return samples
}

/// which of the 5 legs s falls in on the RESUME path's own boundaries
private func resumeLegOf(_ route: ResumedRoute, _ u: Double) -> Int {
    if u >= route.curveLen {
        return 5 // the straight tail - never a seat-line leg of `base`
    }
    return legOf(route.base, route.startS + Double(route.dir.rawValue) * u)
}

/// mirrors perch-around.test.ts one XCTest method per TypeScript test function
final class PerchAroundTests: XCTestCase {
    func testShouldRouteAroundTruthTable() {
        func base(
            fromSlot: Int = 0,
            toSlot: Int = 4,
            slotCount: Int = 5,
            aroundRoute: Bool = true,
            flightLift: Double = 0,
            pill: PillFrame? = PILL,
            reduceMotion: Bool = false
        ) -> Bool {
            PerchAround.shouldRouteAround(
                fromSlot: fromSlot,
                toSlot: toSlot,
                slotCount: slotCount,
                aroundRoute: aroundRoute,
                flightLift: flightLift,
                pill: pill,
                reduceMotion: reduceMotion
            )
        }
        XCTAssertEqual(base(), true, "first -> last routes around")
        XCTAssertEqual(base(fromSlot: 4, toSlot: 0), true, "last -> first routes around")
        XCTAssertEqual(base(toSlot: 3), false, "a stop one short of the end (0 -> 3 of 5) stays on the pill")
        XCTAssertEqual(base(fromSlot: 1, toSlot: 4), false, "from the second slot (1 -> 4 of 5) stays on the pill")
        XCTAssertEqual(base(toSlot: 2, slotCount: 3), true, "a three-tab bar still routes end to end")
        XCTAssertEqual(base(toSlot: 1, slotCount: 2), false, "a two-tab bar never routes around (adjacent hop)")
        XCTAssertEqual(PerchAround.isEndToEnd(fromSlot: 0, toSlot: 0, slotCount: 5), false, "same slot is not end to end")
        XCTAssertEqual(base(aroundRoute: false), false, "opted-out profile never routes around")
        XCTAssertEqual(base(flightLift: 14), false, "a flying companion never routes around")
        XCTAssertEqual(base(pill: nil), false, "no pill (classic bar) never routes around")
        XCTAssertEqual(base(reduceMotion: true), false, "reduce motion never routes around")
        XCTAssertEqual(PerchAround.AROUND_MIN_SLOT_COUNT, 3, "fixture assumes the current AROUND_MIN_SLOT_COUNT")
    }

    func testPlanAroundPathHomeToSettings() {
        let path = plan(fromX: FROM_X, targetX: TARGET_X)
        XCTAssertEqual(path.exitSide, .left, "departs off the pill's left end")
        XCTAssertEqual(path.enterSide, .right, "climbs the pill's right end")
        XCTAssertEqual(path.facing, .left, "faces the exit end for the whole route")
        XCTAssertEqual(path.spin, .left, "rolls head-first over the left end: counter-clockwise")
        XCTAssertObjectIs(path.pivot, PerchAround.routePivot(spriteScale: SPRITE_SCALE, footPad: FOOT_PAD), "pivot is the feet offset")
        let start = PerchAround.aroundPose(path: path, s: 0)
        XCTAssertObjectIs(start.x, FROM_X, "pose at s=0 sits at the departure x")
        XCTAssertObjectIs(start.seatY, 0, "pose at s=0 sits on the seat")
        XCTAssertObjectIs(start.rotation, 0, "pose at s=0 is unrotated")
        let end = PerchAround.aroundPose(path: path, s: path.totalLen)
        XCTAssertObjectIs(end.x, TARGET_X, "pose at totalLen sits at the destination x")
        XCTAssertObjectIs(end.seatY, 0, "pose at totalLen sits back on the seat")
        XCTAssertObjectIs(end.rotation, Double(path.spin.rawValue) * 360, "pose at totalLen completes the roll")
        // the hang mirrors the seat: as far below the bottom edge as above the top
        let aboveTop = PILL.y - feetY(0)
        XCTAssertTrue(
            abs(feetY(path.underY) - (PILL.y + PILL.height) - aboveTop) <= FIT_TOLERANCE,
            "the feet hang as far below the pill's bottom edge as they stand above its top"
        )
    }

    func testPlanAroundPathMirrorTripSwapsSidesAndSpin() {
        let there = plan(fromX: FROM_X, targetX: TARGET_X)
        let back = plan(fromX: TARGET_X, targetX: FROM_X)
        XCTAssertEqual(back.exitSide, there.enterSide, "the return trip exits where the outbound entered")
        XCTAssertEqual(back.enterSide, there.exitSide, "the return trip enters where the outbound exited")
        XCTAssertEqual(back.facing, .right, "the return trip faces the right end")
        XCTAssertEqual(back.spin, .right, "the return trip rolls clockwise")
        XCTAssertObjectIs(back.underY, there.underY, "the hang height does not depend on direction")
    }

    func testPlanAroundPathHangIgnoresTheGap() {
        // the hang is fixed by the pill alone - a taller body clips at the window
        // bottom instead of lifting the feet into the pill
        let path = plan(fromX: FROM_X, targetX: TARGET_X)
        let shortHead = plan(fromX: FROM_X, targetX: TARGET_X, headPad: 10)
        XCTAssertObjectIs(shortHead.underY, path.underY, "headPad never moves the hang")
        XCTAssertTrue(feetY(path.underY) > PILL.y + PILL.height, "the feet hang below the pill bottom")
    }

    func testOnOutline() {
        let path = plan(fromX: FROM_X, targetX: TARGET_X)
        let seatFeetY = path.seatFeetY
        let hangFeetY = path.seatFeetY + path.underY
        for sample in samplePath(path) {
            let fx = sample.pose.x + PerchGeometry.PERCH_SIZE / 2
            let fy = seatFeetY + sample.pose.seatY
            let leg = legOf(path, sample.s)
            if leg == 1 || leg == 5 {
                XCTAssertObjectIs(fy, seatFeetY, "leg \(leg) at s=\(sample.s) sits at seat height")
            } else if leg == 3 {
                XCTAssertObjectIs(fy, hangFeetY, "leg 3 at s=\(sample.s) hangs at the mirrored height")
            } else {
                let cx = leg == 2 ? path.cxExit : path.cxEnter
                let norm = pow((fx - cx) / path.a, 2) + pow((fy - path.cy) / path.b, 2)
                XCTAssertTrue(abs(norm - 1) <= ARC_EPSILON, "leg \(leg) at s=\(sample.s) sits on the ellipse (norm=\(norm))")
            }
        }
    }

    func testContinuity() {
        let path = plan(fromX: FROM_X, targetX: TARGET_X)
        let samples = samplePath(path)
        for i in 1..<samples.count {
            let prev = samples[i - 1].pose
            let cur = samples[i].pose
            let dx = abs(cur.x - prev.x)
            let dy = abs(cur.seatY - prev.seatY)
            let dRot = abs(cur.rotation - prev.rotation)
            XCTAssertTrue(dx <= 1.5, "x moves <= 1.5pt between s=\(samples[i - 1].s) and s=\(samples[i].s) (was \(dx))")
            XCTAssertTrue(dy <= 1.5, "y moves <= 1.5pt between s=\(samples[i - 1].s) and s=\(samples[i].s) (was \(dy))")
            XCTAssertTrue(dRot <= 6, "rotation moves <= 6deg between s=\(samples[i - 1].s) and s=\(samples[i].s) (was \(dRot))")
        }
    }

    func testConstantSpeedOnArcs() {
        let path = plan(fromX: FROM_X, targetX: TARGET_X)
        let samples = samplePath(path)
        for i in 1..<samples.count {
            let a = samples[i - 1]
            let b = samples[i]
            if b.s - a.s != 1 {
                continue // skip the appended exact-totalLen sample if it lands off-grid
            }
            let legA = legOf(path, a.s)
            let legB = legOf(path, b.s)
            if legA != legB || (legA != 2 && legA != 4) {
                continue // only both-in-the-same-arc pairs are checked here
            }
            let chord = hypot(b.pose.x - a.pose.x, b.pose.seatY - a.pose.seatY)
            XCTAssertTrue(abs(chord - 1) <= 0.05, "arc chord at s=\(a.s)->\(b.s) stays within 5% of 1pt (was \(chord))")
        }
    }

    func testEndpointsMonotoneAndTiming() {
        let path = plan(fromX: FROM_X, targetX: TARGET_X)
        let start = PerchAround.aroundPose(path: path, s: 0)
        XCTAssertObjectIs(start.x, FROM_X, "endpoint: x starts at fromX")
        XCTAssertObjectIs(start.seatY, 0, "endpoint: seatY starts at 0")
        XCTAssertObjectIs(start.rotation, 0, "endpoint: rotation starts at 0")
        let end = PerchAround.aroundPose(path: path, s: path.totalLen)
        XCTAssertObjectIs(end.x, TARGET_X, "endpoint: x ends at targetX")
        XCTAssertObjectIs(end.seatY, 0, "endpoint: seatY ends at 0")
        XCTAssertObjectIs(end.rotation, Double(path.spin.rawValue) * 360, "endpoint: rotation ends at spin * 360")
        XCTAssertObjectIs(
            path.totalMs,
            (path.totalLen / PerchAround.AROUND_SPEED_PT_S) * 1000,
            "totalMs matches totalLen at the one route speed"
        )
        var prevRotation = 0.0
        for sample in samplePath(path) {
            if path.spin.rawValue > 0 {
                XCTAssertTrue(sample.pose.rotation >= prevRotation - ARC_EPSILON, "rotation is monotone non-decreasing")
            } else {
                XCTAssertTrue(sample.pose.rotation <= prevRotation + ARC_EPSILON, "rotation is monotone non-increasing")
            }
            prevRotation = sample.pose.rotation
        }
    }

    func testMirrorTripFlipsRotationSign() {
        let there = plan(fromX: FROM_X, targetX: TARGET_X)
        let back = plan(fromX: TARGET_X, targetX: FROM_X)
        XCTAssertEqual(back.exitSide, there.enterSide, "the return trip exits where the outbound entered")
        XCTAssertEqual(back.enterSide, there.exitSide, "the return trip enters where the outbound exited")
        XCTAssertEqual(back.spin.rawValue, -there.spin.rawValue, "the return trip spins the opposite way")
        let thereEnd = PerchAround.aroundPose(path: there, s: there.totalLen).rotation
        let backEnd = PerchAround.aroundPose(path: back, s: back.totalLen).rotation
        XCTAssertObjectIs(thereEnd, Double(there.spin.rawValue) * 360, "the 0 -> 4 trip ends its roll at spin * 360")
        XCTAssertObjectIs(backEnd, Double(back.spin.rawValue) * 360, "the 4 -> 0 trip ends its roll at spin * 360")
        XCTAssertObjectIs(backEnd, -thereEnd, "the return trip ends the roll at the opposite sign")
    }

    func testResumeContinuityAtInterrupt() {
        let path = plan(fromX: FROM_X, targetX: TARGET_X)
        let s1 = path.legs[0]
        let s2 = path.legs[1]
        let s3 = path.legs[2]
        let s4 = path.legs[3]
        let midS = [s1 + (s2 - s1) / 2, s2 + (s3 - s2) / 2, s3 + (s4 - s3) / 2]
        for targetX in [LEFT_TARGET_X, RIGHT_TARGET_X] {
            for s in midS {
                guard let route = PerchAround.resumeAroundRoute(base: path, s: s, targetX: targetX) else {
                    XCTFail("s=\(s) inside legs 2-4 always resumes")
                    continue
                }
                let expected = PerchAround.aroundPose(path: path, s: s)
                let actual = PerchAround.resumedPose(route: route, u: 0)
                XCTAssertTrue(abs(actual.x - expected.x) <= RESUME_EPSILON, "resume x continuous at s=\(s)")
                XCTAssertTrue(abs(actual.seatY - expected.seatY) <= RESUME_EPSILON, "resume seatY continuous at s=\(s)")
                XCTAssertTrue(abs(actual.rotation - expected.rotation) <= RESUME_EPSILON, "resume rotation continuous at s=\(s)")
            }
        }
    }

    func testResumeOnOutline() {
        let path = plan(fromX: FROM_X, targetX: TARGET_X)
        let midLeg3 = path.legs[1] + (path.legs[2] - path.legs[1]) / 2
        guard let route = PerchAround.resumeAroundRoute(base: path, s: midLeg3, targetX: RIGHT_TARGET_X) else {
            XCTFail("midpoint of leg 3 resumes")
            return
        }
        let seatFeetY = path.seatFeetY
        let hangFeetY = path.seatFeetY + path.underY
        var prevRotation: Double?
        var u = 0.0
        while u <= route.curveLen {
            let pose = PerchAround.resumedPose(route: route, u: u)
            let fx = pose.x + PerchGeometry.PERCH_SIZE / 2
            let fy = seatFeetY + pose.seatY
            let leg = resumeLegOf(route, u)
            if leg == 3 {
                XCTAssertObjectIs(fy, hangFeetY, "curve u=\(u) hangs at the mirrored height")
            } else {
                let cx = leg == 2 ? path.cxExit : path.cxEnter
                let norm = pow((fx - cx) / path.a, 2) + pow((fy - path.cy) / path.b, 2)
                XCTAssertTrue(abs(norm - 1) <= ARC_EPSILON, "curve u=\(u) sits on the ellipse (norm=\(norm))")
            }
            if let prevRotation {
                XCTAssertTrue(
                    abs(pose.rotation - prevRotation) <= 6,
                    "rotation continuous at u=\(u) (was \(pose.rotation) vs \(prevRotation))"
                )
            }
            prevRotation = pose.rotation
            u += 1
        }
    }

    func testResumeDirectionChoice() {
        let path = plan(fromX: FROM_X, targetX: TARGET_X)
        let s1 = path.legs[0]
        let s4 = path.legs[3]

        // just past the exit cap, target right at the exit end: backing off is short
        let nearExitS = s1 + 1
        let exitEndTargetX = path.cxExit - PerchGeometry.PERCH_SIZE / 2
        let backRoute = PerchAround.resumeAroundRoute(base: path, s: nearExitS, targetX: exitEndTargetX)
        XCTAssertNotNil(backRoute, "near-exit interrupt resumes")
        if let backRoute {
            XCTAssertEqual(backRoute.dir, .left, "backing toward the exit end is shorter")
            XCTAssertEqual(backRoute.facing.rawValue, -path.facing.rawValue, "a backward resume flips facing")
            let forwardLen = s4 - nearExitS + abs(exitEndTargetX + PerchGeometry.PERCH_SIZE / 2 - path.cxEnter)
            XCTAssertTrue(backRoute.totalLen <= forwardLen, "the chosen (backward) length is the shorter one")
        }

        // just before the enter cap, target right at the enter end: continuing on is short
        let nearEnterS = s4 - 1
        let enterEndTargetX = path.cxEnter - PerchGeometry.PERCH_SIZE / 2
        let fwdRoute = PerchAround.resumeAroundRoute(base: path, s: nearEnterS, targetX: enterEndTargetX)
        XCTAssertNotNil(fwdRoute, "near-enter interrupt resumes")
        if let fwdRoute {
            XCTAssertEqual(fwdRoute.dir, .right, "continuing toward the enter end is shorter")
            let backwardLen = nearEnterS - s1 + abs(enterEndTargetX + PerchGeometry.PERCH_SIZE / 2 - path.cxExit)
            XCTAssertTrue(fwdRoute.totalLen <= backwardLen, "the chosen (forward) length is the shorter one")
        }
    }

    func testResumeEndpoint() {
        let path = plan(fromX: FROM_X, targetX: TARGET_X)
        let midLeg2 = path.legs[0] + (path.legs[1] - path.legs[0]) / 2
        guard let route = PerchAround.resumeAroundRoute(base: path, s: midLeg2, targetX: RIGHT_TARGET_X) else {
            XCTFail("midpoint of leg 2 resumes")
            return
        }
        let end = PerchAround.resumedPose(route: route, u: route.totalLen)
        XCTAssertTrue(abs(end.x - RIGHT_TARGET_X) <= RESUME_EPSILON, "resume ends at the new target x")
        XCTAssertObjectIs(end.seatY, 0, "resume ends seated")
        XCTAssertObjectIs(end.rotation, route.endRotation, "resume ends at endRotation")
    }

    func testResumeSeatLineReturnsNull() {
        let path = plan(fromX: FROM_X, targetX: TARGET_X)
        let s1 = path.legs[0]
        let s4 = path.legs[3]
        let s5 = path.legs[4]
        XCTAssertNil(PerchAround.resumeAroundRoute(base: path, s: 0, targetX: RIGHT_TARGET_X), "s=0 is on leg 1")
        XCTAssertNil(PerchAround.resumeAroundRoute(base: path, s: s1, targetX: RIGHT_TARGET_X), "s=legs[0] is the leg 1/2 seam")
        XCTAssertNil(PerchAround.resumeAroundRoute(base: path, s: s4, targetX: RIGHT_TARGET_X), "s=legs[3] is the leg 4/5 seam")
        XCTAssertNil(PerchAround.resumeAroundRoute(base: path, s: s5, targetX: RIGHT_TARGET_X), "s=totalLen is on leg 5")
    }

    func testResumedBaseSRoundTrips() {
        let path = plan(fromX: FROM_X, targetX: TARGET_X)
        let midLeg4 = path.legs[2] + (path.legs[3] - path.legs[2]) / 2
        guard let route = PerchAround.resumeAroundRoute(base: path, s: midLeg4, targetX: LEFT_TARGET_X) else {
            XCTFail("midpoint of leg 4 resumes")
            return
        }
        var u = 0.0
        while u < route.curveLen {
            guard let s = PerchAround.resumedBaseS(route: route, u: u) else {
                XCTFail("u=\(u) is still on the curve")
                u += 1
                continue
            }
            let fromBase = PerchAround.aroundPose(path: route.base, s: s)
            let fromResumed = PerchAround.resumedPose(route: route, u: u)
            XCTAssertObjectIs(fromBase.x, fromResumed.x, "x round-trips at u=\(u)")
            XCTAssertObjectIs(fromBase.seatY, fromResumed.seatY, "seatY round-trips at u=\(u)")
            XCTAssertObjectIs(fromBase.rotation, fromResumed.rotation, "rotation round-trips at u=\(u)")
            u += 1
        }
        XCTAssertNil(
            PerchAround.resumedBaseS(route: route, u: route.curveLen + 1),
            "a point on the straight tail has no base s"
        )
    }

    func testResumeConstantSpeedTiming() {
        let path = plan(fromX: FROM_X, targetX: TARGET_X)
        let midLeg3 = path.legs[1] + (path.legs[2] - path.legs[1]) / 2
        guard let route = PerchAround.resumeAroundRoute(base: path, s: midLeg3, targetX: LEFT_TARGET_X) else {
            XCTFail("midpoint of leg 3 resumes")
            return
        }
        XCTAssertObjectIs(
            route.totalMs,
            (route.totalLen / PerchAround.AROUND_SPEED_PT_S) * 1000,
            "totalMs matches totalLen at the one route speed"
        )
    }

    // Expected values below come from running perch-around.ts on this fixture.
    // A value reached through sin/cos/atan2/hypot is checked within ARC_EPSILON,
    // everything else must match the TypeScript's bit pattern.

    /// asserts actual matches the TypeScript-captured expected value: any NaN
    /// equals any NaN, otherwise exact unless a tolerance is given
    private func assertMatchesTS(
        _ actual: Double,
        _ expected: Double,
        tolerance: Double = 0,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if expected.isNaN {
            XCTAssertTrue(actual.isNaN, "\(message) (was \(actual), expected NaN)", file: file, line: line)
            return
        }
        if tolerance == 0 {
            XCTAssertObjectIs(actual, expected, message, file: file, line: line)
        } else {
            XCTAssertTrue(
                abs(actual - expected) <= tolerance,
                "\(message) (was \(actual), expected \(expected))",
                file: file,
                line: line
            )
        }
    }

    func testAroundPoseEmptyLegsReadsAsUndefined() {
        let path = plan(fromX: FROM_X, targetX: TARGET_X)
        let emptyLegs = AroundPath(
            exitSide: path.exitSide, enterSide: path.enterSide, facing: path.facing, spin: path.spin,
            pivot: path.pivot, seatFeetY: path.seatFeetY, underY: path.underY, cxExit: path.cxExit,
            cxEnter: path.cxEnter, cy: path.cy, a: path.a, b: path.b, feetX0: path.feetX0,
            targetFeetX: path.targetFeetX, arcCum: path.arcCum, arcLen: path.arcLen, legs: [],
            totalLen: path.totalLen, totalMs: path.totalMs
        )
        let pose = PerchAround.aroundPose(path: emptyLegs, s: 10)
        assertMatchesTS(pose.x, 320, "legs=[] falls through to the last leg like undefined bounds do")
        assertMatchesTS(pose.seatY, 0, "legs=[] still lands on the seat line")
        assertMatchesTS(pose.rotation, -360, "legs=[] still completes the roll")
    }

    func testAroundPoseShortArcCumReadsAsUndefined() {
        let path = plan(fromX: FROM_X, targetX: TARGET_X)
        let s = path.legs[0] + 1
        func withArcCum(_ arcCum: [Double]) -> AroundPath {
            AroundPath(
                exitSide: path.exitSide, enterSide: path.enterSide, facing: path.facing, spin: path.spin,
                pivot: path.pivot, seatFeetY: path.seatFeetY, underY: path.underY, cxExit: path.cxExit,
                cxEnter: path.cxEnter, cy: path.cy, a: path.a, b: path.b, feetX0: path.feetX0,
                targetFeetX: path.targetFeetX, arcCum: arcCum, arcLen: path.arcLen, legs: path.legs,
                totalLen: path.totalLen, totalMs: path.totalMs
            )
        }

        let emptyPose = PerchAround.aroundPose(path: withArcCum([]), s: s)
        assertMatchesTS(emptyPose.x, 29, tolerance: ARC_EPSILON, "arcCum=[] degenerates to phi=-0 at cxExit")
        assertMatchesTS(emptyPose.seatY, 0, tolerance: ARC_EPSILON, "arcCum=[] degenerates to seat height")
        assertMatchesTS(emptyPose.rotation, 0, tolerance: ARC_EPSILON, "arcCum=[] degenerates to zero rotation")

        let onePose = PerchAround.aroundPose(path: withArcCum([0]), s: s)
        assertMatchesTS(onePose.x, .nan, "arcCum=[0] divides phi's k=0 by zero")
        assertMatchesTS(onePose.seatY, .nan, "arcCum=[0] divides phi's k=0 by zero")
        assertMatchesTS(onePose.rotation, .nan, "arcCum=[0] divides phi's k=0 by zero")

        let fivePose = PerchAround.aroundPose(path: withArcCum(Array(path.arcCum.prefix(5))), s: s)
        assertMatchesTS(fivePose.x, 21.087065419599625, tolerance: ARC_EPSILON, "a truncated arcCum still interpolates within its own bounds")
        assertMatchesTS(fivePose.seatY, 1.3192474960345635, tolerance: ARC_EPSILON, "a truncated arcCum still interpolates within its own bounds")
        assertMatchesTS(fivePose.rotation, -18.71557543599932, tolerance: ARC_EPSILON, "a truncated arcCum still interpolates within its own bounds")
    }

    func testResumeAroundRouteShortLegsReadsAsUndefined() {
        let path = plan(fromX: FROM_X, targetX: TARGET_X)
        let emptyLegs = AroundPath(
            exitSide: path.exitSide, enterSide: path.enterSide, facing: path.facing, spin: path.spin,
            pivot: path.pivot, seatFeetY: path.seatFeetY, underY: path.underY, cxExit: path.cxExit,
            cxEnter: path.cxEnter, cy: path.cy, a: path.a, b: path.b, feetX0: path.feetX0,
            targetFeetX: path.targetFeetX, arcCum: path.arcCum, arcLen: path.arcLen, legs: [],
            totalLen: path.totalLen, totalMs: path.totalMs
        )
        guard let route = PerchAround.resumeAroundRoute(base: emptyLegs, s: 10, targetX: 200) else {
            XCTFail("legs=[] never satisfies s <= s1 or s >= s4 since both read as NaN")
            return
        }
        assertMatchesTS(route.endS, .nan, "legs=[] leaves s4 undefined")
        XCTAssertEqual(route.dir, .right, "backwardLen < forwardLen is false when both are NaN")
        assertMatchesTS(route.curveLen, .nan, "curveLen inherits the undefined endS")
        assertMatchesTS(route.tailFromFeetX, 346, "tailFromFeetX only depends on cxEnter, not legs")
        assertMatchesTS(route.tailToFeetX, 227, "tailToFeetX is just the requested target's feet x")
        assertMatchesTS(route.tailLen, 119, "tailLen only depends on cxEnter, not legs")
        assertMatchesTS(route.totalLen, .nan, "totalLen inherits the undefined curveLen")
        assertMatchesTS(route.totalMs, .nan, "totalMs inherits the undefined totalLen")
        XCTAssertEqual(route.facing, .left, "dir=1 keeps the base facing")
        assertMatchesTS(route.endRotation, -360, "dir=1 still completes the roll")

        let twoLegs = AroundPath(
            exitSide: path.exitSide, enterSide: path.enterSide, facing: path.facing, spin: path.spin,
            pivot: path.pivot, seatFeetY: path.seatFeetY, underY: path.underY, cxExit: path.cxExit,
            cxEnter: path.cxEnter, cy: path.cy, a: path.a, b: path.b, feetX0: path.feetX0,
            targetFeetX: path.targetFeetX, arcCum: path.arcCum, arcLen: path.arcLen,
            legs: Array(path.legs.prefix(2)), totalLen: path.totalLen, totalMs: path.totalMs
        )
        XCTAssertNil(
            PerchAround.resumeAroundRoute(base: twoLegs, s: 10, targetX: 200),
            "legs of 2 entries still reads a real s1, so s <= s1 short-circuits before s4 is ever touched"
        )
    }

    func testResumedPoseAndBaseSWithEmptyArcCumBase() {
        let path = plan(fromX: FROM_X, targetX: TARGET_X)
        let emptyArcBase = AroundPath(
            exitSide: path.exitSide, enterSide: path.enterSide, facing: path.facing, spin: path.spin,
            pivot: path.pivot, seatFeetY: path.seatFeetY, underY: path.underY, cxExit: path.cxExit,
            cxEnter: path.cxEnter, cy: path.cy, a: path.a, b: path.b, feetX0: path.feetX0,
            targetFeetX: path.targetFeetX, arcCum: [], arcLen: path.arcLen, legs: path.legs,
            totalLen: path.totalLen, totalMs: path.totalMs
        )
        guard let baseRoute = PerchAround.resumeAroundRoute(base: path, s: path.legs[1] + 1, targetX: 200) else {
            XCTFail("midpoint of leg 3 always resumes")
            return
        }
        let route = ResumedRoute(
            base: emptyArcBase, startS: baseRoute.startS, endS: baseRoute.endS, dir: baseRoute.dir,
            curveLen: baseRoute.curveLen, tailFromFeetX: baseRoute.tailFromFeetX,
            tailToFeetX: baseRoute.tailToFeetX, tailLen: baseRoute.tailLen, totalLen: baseRoute.totalLen,
            totalMs: baseRoute.totalMs, facing: baseRoute.facing, endRotation: baseRoute.endRotation
        )

        let atZero = PerchAround.resumedPose(route: route, u: 0)
        assertMatchesTS(atZero.x, 30, "u=0 lands on leg 3 (the hang), which never reads arcCum")
        assertMatchesTS(atZero.seatY, 84.96000000000004, "u=0 lands on leg 3 (the hang), which never reads arcCum")
        assertMatchesTS(atZero.rotation, -180, "u=0 lands on leg 3 (the hang), which never reads arcCum")

        let mid = route.curveLen / 2
        let atMid = PerchAround.resumedPose(route: route, u: mid)
        assertMatchesTS(atMid.x, 29, tolerance: ARC_EPSILON, "past leg 3 the arc degenerates to phi=-0 at cxExit, same as an empty arcCum on aroundPose")
        assertMatchesTS(atMid.seatY, 0, tolerance: ARC_EPSILON, "past leg 3 the arc degenerates to seat height")
        assertMatchesTS(atMid.rotation, 0, tolerance: ARC_EPSILON, "past leg 3 the arc degenerates to zero rotation")

        guard let s = PerchAround.resumedBaseS(route: route, u: mid) else {
            XCTFail("u=curveLen/2 is still on the curve")
            return
        }
        assertMatchesTS(s, 70.26275262296289, "resumedBaseS never reads arcCum, so an empty base arcCum doesn't affect it")
    }
}
