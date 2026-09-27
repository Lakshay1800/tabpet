import XCTest

import TabPetCore

/// Every PerchHandoff pure function the conformance/handoff.json fixture must
/// cover. Kept in sync by hand with PerchHandoff.swift's public functions -
/// Swift has no runtime export list to diff against, unlike the TypeScript
/// reader (conformance.test.ts), which enumerates the module namespace.
/// readPerchHandoff/writePerchHandoff/resetPerchHandoffForTest are module-state
/// mutators, not pure functions, and are intentionally absent here too.
private let knownHandoffFunctions: Set<String> = [
    "planRunSeatY",
    "planStartSeatY",
    "planMountSeatY",
    "liveLastSeat",
    "initialPerchHandoff",
    "planFocus",
    "applyFocusBlur",
    "applyDragTrack",
    "applyDragRelease",
    "planDragRelease",
    "selectsOnRelease",
    "planApproach",
    "isFarGrab",
    "planFarSample",
    "stepToward",
    "sanitizeRunSpeed",
    "focusFromSlot",
    "initialReleaseState",
    "reduceRelease",
]

final class HandoffConformanceTests: XCTestCase {
    func testHandoffFixtureCoverage() throws {
        let fixture = try ConformanceFixtureLoader.load("handoff")
        XCTAssertEqual(fixture.module, "perch-handoff")

        let covered = Set(fixture.cases.map(\.fn))
        for fn in covered {
            XCTAssertTrue(knownHandoffFunctions.contains(fn), "fixture names unknown function \(fn)")
        }
        for fn in knownHandoffFunctions {
            XCTAssertTrue(covered.contains(fn), "PerchHandoff.\(fn) has no fixture coverage")
        }

        var casesRun = 0
        for c in fixture.cases {
            try runCase(c)
            casesRun += 1
        }
        XCTAssertEqual(casesRun, fixture.cases.count)
        XCTAssertGreaterThan(casesRun, 0)
        print("HandoffConformanceTests: \(casesRun) conformance cases passed")
    }

    /// pins RELEASE_GRACE_MS/FAR_GRAB_PT/FAR_STEP_MAX_DT_MS against the
    /// fixture's own copy of perch-handoff.ts's exported constants.
    func testHandoffConstantsMatchModule() throws {
        let fixture = try ConformanceFixtureLoader.load("handoff")
        XCTAssertEqual(try fixture.constant("RELEASE_GRACE_MS"), PerchHandoff.RELEASE_GRACE_MS)
        XCTAssertEqual(try fixture.constant("FAR_GRAB_PT"), PerchHandoff.FAR_GRAB_PT)
        XCTAssertEqual(try fixture.constant("FAR_STEP_MAX_DT_MS"), PerchHandoff.FAR_STEP_MAX_DT_MS)
    }

    private func runCase(_ c: ConformanceCase) throws {
        switch c.fn {
        case "planRunSeatY":
            let fromSeatY = try require(c.args["fromSeatY"]?.doubleValue, "fromSeatY")
            let actual = PerchHandoff.planRunSeatY(fromSeatY: fromSeatY)
            let expected = try require(c.expect.doubleValue, "expect")
            assertNumbersEqual(actual, expected, c.compare, "planRunSeatY")

        case "planStartSeatY":
            let kind = try require(c.args["kind"], "kind").focusKind("kind")
            let runSeatY = try require(c.args["runSeatY"]?.doubleValue, "runSeatY")
            let fromSeatY = try require(c.args["fromSeatY"]?.doubleValue, "fromSeatY")
            let actual = PerchHandoff.planStartSeatY(kind: kind, runSeatY: runSeatY, fromSeatY: fromSeatY)
            let expected = try require(c.expect.doubleValue, "expect")
            assertNumbersEqual(actual, expected, c.compare, "planStartSeatY")

        case "planMountSeatY":
            let handoff = try require(c.args["handoff"], "handoff").perchHandoffState()
            let argsJSON = try require(c.args["args"], "args")
            let actual = PerchHandoff.planMountSeatY(
                handoff: handoff,
                tab: try require(argsJSON["tab"]?.intValue, "args.tab"),
                screenWidth: try require(argsJSON["screenWidth"]?.doubleValue, "args.screenWidth"),
                bottomExtra: try require(argsJSON["bottomExtra"]?.doubleValue, "args.bottomExtra"),
                transientSlot: try require(argsJSON["transientSlot"]?.boolValue, "args.transientSlot"),
                reduceMotion: try require(argsJSON["reduceMotion"]?.boolValue, "args.reduceMotion"),
                slotCount: try require(argsJSON["slotCount"]?.intValue, "args.slotCount"),
                slotCenters: try argsJSON["slotCenters"]?.doubleArray()
            )
            let expected = try require(c.expect.doubleValue, "expect")
            assertNumbersEqual(actual, expected, c.compare, "planMountSeatY")

        case "liveLastSeat":
            let bottomExtra = try require(c.args["bottomExtra"]?.doubleValue, "bottomExtra")
            let seatY = try require(c.args["seatY"]?.doubleValue, "seatY")
            let actual = PerchHandoff.liveLastSeat(bottomExtra: bottomExtra, seatY: seatY)
            let expected = try require(c.expect.doubleValue, "expect")
            assertNumbersEqual(actual, expected, c.compare, "liveLastSeat")

        case "initialPerchHandoff":
            let actual = PerchHandoff.initialPerchHandoff()
            let expected = try c.expect.perchHandoffState()
            assertHandoffEqual(actual, expected, c.compare, "initialPerchHandoff")

        case "planFocus":
            let handoff = try require(c.args["handoff"], "handoff").perchHandoffState()
            let argsJSON = try require(c.args["args"], "args")
            let actual = PerchHandoff.planFocus(
                handoff: handoff,
                tab: try require(argsJSON["tab"]?.intValue, "args.tab"),
                screenWidth: try require(argsJSON["screenWidth"]?.doubleValue, "args.screenWidth"),
                bottomExtra: try require(argsJSON["bottomExtra"]?.doubleValue, "args.bottomExtra"),
                transientSlot: try require(argsJSON["transientSlot"]?.boolValue, "args.transientSlot"),
                reduceMotion: try require(argsJSON["reduceMotion"]?.boolValue, "args.reduceMotion"),
                slotCount: try require(argsJSON["slotCount"]?.intValue, "args.slotCount"),
                slotCenters: try argsJSON["slotCenters"]?.doubleArray(),
                holdRun: try argsJSON.optionalBool("holdRun", "args.holdRun") ?? false
            )
            let expected = try c.expect.focusPlan()
            assertFocusPlanEqual(actual, expected, c.compare, "planFocus")

        case "applyFocusBlur":
            let handoff = try require(c.args["handoff"], "handoff").perchHandoffState()
            let argsJSON = try require(c.args["args"], "args")
            let actual = PerchHandoff.applyFocusBlur(
                handoff: handoff,
                currentX: try require(argsJSON["currentX"]?.doubleValue, "args.currentX"),
                transientSlot: try require(argsJSON["transientSlot"]?.boolValue, "args.transientSlot"),
                currentSeat: try argsJSON.optionalDouble("currentSeat", "args.currentSeat")
            )
            let expected = try c.expect.perchHandoffState()
            assertHandoffEqual(actual, expected, c.compare, "applyFocusBlur")

        case "applyDragTrack":
            let handoff = try require(c.args["handoff"], "handoff").perchHandoffState()
            let glassTarget = try require(c.args["glassTarget"]?.doubleValue, "glassTarget")
            let actual = PerchHandoff.applyDragTrack(handoff: handoff, glassTarget: glassTarget)
            let expected = try c.expect.perchHandoffState()
            assertHandoffEqual(actual, expected, c.compare, "applyDragTrack")

        case "applyDragRelease":
            let handoff = try require(c.args["handoff"], "handoff").perchHandoffState()
            let argsJSON = try require(c.args["args"], "args")
            let actual = PerchHandoff.applyDragRelease(
                handoff: handoff,
                tab: try require(argsJSON["tab"]?.intValue, "args.tab"),
                releaseX: try require(argsJSON["releaseX"]?.doubleValue, "args.releaseX"),
                bottomExtra: try require(argsJSON["bottomExtra"]?.doubleValue, "args.bottomExtra")
            )
            let expected = try c.expect.perchHandoffState()
            assertHandoffEqual(actual, expected, c.compare, "applyDragRelease")

        case "planDragRelease":
            let phase = try require(c.args["phase"], "phase").dragPhase("phase")
            let releaseSlot = try require(c.args["releaseSlot"]?.intValue, "releaseSlot")
            let currentSlot = try require(c.args["currentSlot"]?.intValue, "currentSlot")
            let selectsOnReleaseArg = try require(c.args["selectsOnRelease"]?.boolValue, "selectsOnRelease")
            let actual = PerchHandoff.planDragRelease(
                phase: phase,
                releaseSlot: releaseSlot,
                currentSlot: currentSlot,
                selectsOnRelease: selectsOnReleaseArg
            )
            let expected = try c.expect.dragReleasePlan()
            XCTAssertEqual(actual, expected, "planDragRelease mismatch: \(c.args)")

        case "selectsOnRelease":
            let barScrub = try require(c.args["barScrub"], "barScrub").barScrub("barScrub")
            let hasOnDragRelease = try require(c.args["hasOnDragRelease"]?.boolValue, "hasOnDragRelease")
            let nativePill = try require(c.args["nativePill"]?.boolValue, "nativePill")
            let actual = PerchHandoff.selectsOnRelease(barScrub: barScrub, hasOnDragRelease: hasOnDragRelease, nativePill: nativePill)
            let expected = try require(c.expect.boolValue, "expect")
            XCTAssertEqual(actual, expected, "selectsOnRelease mismatch: \(c.args)")

        case "planApproach":
            let distancePt = try require(c.args["distancePt"]?.doubleValue, "distancePt")
            let speedPtS = try c.args.optionalDouble("speedPtS", "speedPtS")
            let actual = PerchHandoff.planApproach(distancePt: distancePt, speedPtS: speedPtS)
            let expected = try c.expect.approachPlan()
            assertApproachPlanEqual(actual, expected, c.compare, "planApproach")

        case "isFarGrab":
            let gapPt = try require(c.args["gapPt"]?.doubleValue, "gapPt")
            let actual = PerchHandoff.isFarGrab(gapPt: gapPt)
            let expected = try require(c.expect.boolValue, "expect")
            XCTAssertEqual(actual, expected, "isFarGrab mismatch: \(c.args)")

        case "planFarSample":
            let glassX = try require(c.args["glassX"]?.doubleValue, "glassX")
            let currentX = try require(c.args["currentX"]?.doubleValue, "currentX")
            let screenWidth = try require(c.args["screenWidth"]?.doubleValue, "screenWidth")
            let actual = PerchHandoff.planFarSample(glassX: glassX, currentX: currentX, screenWidth: screenWidth)
            let expected = try c.expect.farSamplePlan()
            assertFarSamplePlanEqual(actual, expected, c.compare, "planFarSample")

        case "stepToward":
            let current = try require(c.args["current"]?.doubleValue, "current")
            let target = try require(c.args["target"]?.doubleValue, "target")
            let speedPtS = try require(c.args["speedPtS"]?.doubleValue, "speedPtS")
            let dtMs = try require(c.args["dtMs"]?.doubleValue, "dtMs")
            let actual = PerchHandoff.stepToward(current: current, target: target, speedPtS: speedPtS, dtMs: dtMs)
            let expected = try c.expect.stepTowardResult()
            assertNumbersEqual(actual.x, expected.x, c.compare, "stepToward.x")
            XCTAssertEqual(actual.arrived, expected.arrived, "stepToward.arrived mismatch: \(c.args)")

        case "sanitizeRunSpeed":
            let speed = try c.args.optionalDouble("speed", "speed")
            let actual = PerchHandoff.sanitizeRunSpeed(speed: speed)
            let expected = try require(c.expect.doubleValue, "expect")
            assertNumbersEqual(actual, expected, c.compare, "sanitizeRunSpeed")

        case "focusFromSlot":
            let handoffLastTab = try require(c.args["handoffLastTab"]?.intValue, "handoffLastTab")
            let arrivedByDrag = try require(c.args["arrivedByDrag"]?.boolValue, "arrivedByDrag")
            let focusedSlot = try require(c.args["focusedSlot"]?.intValue, "focusedSlot")
            let actual = PerchHandoff.focusFromSlot(handoffLastTab: handoffLastTab, arrivedByDrag: arrivedByDrag, focusedSlot: focusedSlot)
            let expected = try require(c.expect.intValue, "expect")
            XCTAssertEqual(actual, expected, "focusFromSlot mismatch: \(c.args)")

        case "initialReleaseState":
            let actual = PerchHandoff.initialReleaseState()
            let expected = try c.expect.releaseState()
            XCTAssertEqual(actual, expected, "initialReleaseState mismatch")

        case "reduceRelease":
            let state = try require(c.args["state"], "state").releaseState()
            let event = try require(c.args["event"], "event").releaseEvent()
            let actual = PerchHandoff.reduceRelease(state: state, event: event)
            let expected = try c.expect.reduceReleaseResult()
            XCTAssertEqual(actual, expected, "reduceRelease mismatch: \(c.args)")

        default:
            XCTFail("unknown fn in handoff fixture: \(c.fn)")
        }
    }

    private func assertNumbersEqual(_ actual: Double, _ expected: Double, _ rule: CompareRule, _ label: String) {
        XCTAssertTrue(
            ConformanceCompare.numbersEqual(actual, expected, rule: rule),
            "\(label) mismatch: actual=\(actual) expected=\(expected)"
        )
    }

    private func assertHandoffEqual(_ actual: PerchHandoffState, _ expected: PerchHandoffState, _ rule: CompareRule, _ label: String) {
        XCTAssertEqual(actual.lastTab, expected.lastTab, "\(label).lastTab mismatch")
        switch (actual.lastX, expected.lastX) {
        case (nil, nil):
            break
        case (let a?, let e?):
            assertNumbersEqual(a, e, rule, "\(label).lastX")
        default:
            XCTFail("\(label).lastX mismatch: actual=\(String(describing: actual.lastX)) expected=\(String(describing: expected.lastX))")
        }
        assertNumbersEqual(actual.lastSeat, expected.lastSeat, rule, "\(label).lastSeat")
    }

    private func assertFocusPlanEqual(_ actual: FocusPlan, _ expected: FocusPlan, _ rule: CompareRule, _ label: String) {
        XCTAssertEqual(actual.kind, expected.kind, "\(label).kind mismatch")
        assertNumbersEqual(actual.fromX, expected.fromX, rule, "\(label).fromX")
        assertNumbersEqual(actual.targetX, expected.targetX, rule, "\(label).targetX")
        assertNumbersEqual(actual.fromSeatY, expected.fromSeatY, rule, "\(label).fromSeatY")
        assertNumbersEqual(actual.runSeatY, expected.runSeatY, rule, "\(label).runSeatY")
        assertHandoffEqual(actual.next, expected.next, rule, "\(label).next")
        XCTAssertEqual(actual.commitsHandoff, expected.commitsHandoff, "\(label).commitsHandoff mismatch")
    }

    private func assertApproachPlanEqual(_ actual: ApproachPlan, _ expected: ApproachPlan, _ rule: CompareRule, _ label: String) {
        switch (actual, expected) {
        case (.spring, .spring):
            break
        case (.run(let actualMs), .run(let expectedMs)):
            assertNumbersEqual(actualMs, expectedMs, rule, "\(label).durationMs")
        default:
            XCTFail("\(label) kind mismatch: actual=\(actual) expected=\(expected)")
        }
    }

    private func assertFarSamplePlanEqual(_ actual: FarSamplePlan, _ expected: FarSamplePlan, _ rule: CompareRule, _ label: String) {
        switch (actual, expected) {
        case (.end, .end):
            break
        case (.track(let actualTarget, let actualFacing), .track(let expectedTarget, let expectedFacing)):
            assertNumbersEqual(actualTarget, expectedTarget, rule, "\(label).target")
            XCTAssertEqual(actualFacing, expectedFacing, "\(label).facing mismatch")
        default:
            XCTFail("\(label) kind mismatch: actual=\(actual) expected=\(expected)")
        }
    }

    private func require<T>(_ value: T?, _ label: String, file: StaticString = #filePath, line: UInt = #line) throws -> T {
        guard let value else {
            XCTFail("missing or mistyped \(label)", file: file, line: line)
            throw ConformanceLoadError.missingField(label)
        }
        return value
    }
}

private enum ConformanceLoadError: Error {
    case missingField(String)
}
