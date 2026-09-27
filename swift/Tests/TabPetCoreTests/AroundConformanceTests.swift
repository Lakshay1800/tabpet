import XCTest

import TabPetCore

/// Every PerchAround function the conformance/around.json fixture must
/// cover. Kept in sync by hand with PerchAround.swift's public functions -
/// Swift has no runtime export list to diff against, unlike the TypeScript
/// reader (conformance.test.ts), which enumerates the module namespace.
private let knownAroundFunctions: Set<String> = [
    "isEndToEnd",
    "shouldRouteAround",
    "routePivot",
    "planAroundPath",
    "aroundPose",
    "resumeAroundRoute",
    "resumedPose",
    "resumedBaseS",
]

final class AroundConformanceTests: XCTestCase {
    func testAroundFixtureCoverage() throws {
        let fixture = try ConformanceFixtureLoader.load("around")
        XCTAssertEqual(fixture.module, "perch-around")

        let covered = Set(fixture.cases.map(\.fn))
        for fn in covered {
            XCTAssertTrue(knownAroundFunctions.contains(fn), "fixture names unknown function \(fn)")
        }
        for fn in knownAroundFunctions {
            XCTAssertTrue(covered.contains(fn), "PerchAround.\(fn) has no fixture coverage")
        }

        var casesRun = 0
        for c in fixture.cases {
            try runCase(c)
            casesRun += 1
        }
        XCTAssertEqual(casesRun, fixture.cases.count)
        XCTAssertGreaterThan(casesRun, 0)
        print("AroundConformanceTests: \(casesRun) conformance cases passed")
    }

    /// pins every numeric constant perch-around.ts exports against the
    /// fixture's own copy (ARC_SAMPLES is internal, not exported, and so not pinned).
    func testAroundConstantsMatchModule() throws {
        let fixture = try ConformanceFixtureLoader.load("around")
        XCTAssertEqual(try fixture.constant("AROUND_MIN_SLOT_COUNT"), Double(PerchAround.AROUND_MIN_SLOT_COUNT))
        XCTAssertEqual(try fixture.constant("AROUND_SPEED_PT_S"), PerchAround.AROUND_SPEED_PT_S)
    }

    private func runCase(_ c: ConformanceCase) throws {
        switch c.fn {
        case "isEndToEnd":
            let fromSlot = try require(c.args["fromSlot"]?.intValue, "fromSlot")
            let toSlot = try require(c.args["toSlot"]?.intValue, "toSlot")
            let slotCount = try require(c.args["slotCount"]?.intValue, "slotCount")
            let actual = PerchAround.isEndToEnd(fromSlot: fromSlot, toSlot: toSlot, slotCount: slotCount)
            let expected = try require(c.expect.boolValue, "expect")
            XCTAssertEqual(actual, expected, "isEndToEnd mismatch: \(c.args)")

        case "shouldRouteAround":
            let fromSlot = try require(c.args["fromSlot"]?.intValue, "fromSlot")
            let toSlot = try require(c.args["toSlot"]?.intValue, "toSlot")
            let slotCount = try require(c.args["slotCount"]?.intValue, "slotCount")
            let aroundRoute = try require(c.args["aroundRoute"]?.boolValue, "aroundRoute")
            let flightLift = try require(c.args["flightLift"]?.doubleValue, "flightLift")
            let pillArg = try require(c.args["pill"], "pill")
            let pill = try pillArg.pillFrame()
            let reduceMotion = try require(c.args["reduceMotion"]?.boolValue, "reduceMotion")
            let actual = PerchAround.shouldRouteAround(
                fromSlot: fromSlot,
                toSlot: toSlot,
                slotCount: slotCount,
                aroundRoute: aroundRoute,
                flightLift: flightLift,
                pill: pill,
                reduceMotion: reduceMotion
            )
            let expected = try require(c.expect.boolValue, "expect")
            XCTAssertEqual(actual, expected, "shouldRouteAround mismatch: \(c.args)")

        case "routePivot":
            let spriteScale = try require(c.args["spriteScale"]?.doubleValue, "spriteScale")
            let footPad = try require(c.args["footPad"]?.doubleValue, "footPad")
            let actual = PerchAround.routePivot(spriteScale: spriteScale, footPad: footPad)
            let expected = try require(c.expect.doubleValue, "expect")
            assertNumbersEqual(actual, expected, c.compare, "routePivot")

        case "planAroundPath":
            let fromX = try require(c.args["fromX"]?.doubleValue, "fromX")
            let targetX = try require(c.args["targetX"]?.doubleValue, "targetX")
            let pillArg = try require(c.args["pill"], "pill")
            let pill = try require(try pillArg.pillFrame(), "pill")
            let windowWidth = try require(c.args["windowWidth"]?.doubleValue, "windowWidth")
            let spriteScale = try require(c.args["spriteScale"]?.doubleValue, "spriteScale")
            let footPad = try require(c.args["footPad"]?.doubleValue, "footPad")
            let headPad = try require(c.args["headPad"]?.doubleValue, "headPad")
            let seatOffset = try require(c.args["seatOffset"]?.doubleValue, "seatOffset")
            let actual = PerchAround.planAroundPath(
                fromX: fromX,
                targetX: targetX,
                pill: pill,
                windowWidth: windowWidth,
                spriteScale: spriteScale,
                footPad: footPad,
                headPad: headPad,
                seatOffset: seatOffset
            )
            let expected = try c.expect.aroundPath()
            assertAroundPathEqual(actual, expected, c.compare, "planAroundPath")

        case "aroundPose":
            let pathArg = try require(c.args["path"], "path")
            let path = try pathArg.aroundPath()
            let s = try require(c.args["s"]?.doubleValue, "s")
            let actual = PerchAround.aroundPose(path: path, s: s)
            let expected = try c.expect.aroundPose()
            assertAroundPoseEqual(actual, expected, c.compare, "aroundPose")

        case "resumeAroundRoute":
            let baseArg = try require(c.args["base"], "base")
            let base = try baseArg.aroundPath()
            let s = try require(c.args["s"]?.doubleValue, "s")
            let targetX = try require(c.args["targetX"]?.doubleValue, "targetX")
            let actual = PerchAround.resumeAroundRoute(base: base, s: s, targetX: targetX)
            if c.expect.isNull {
                XCTAssertNil(actual, "resumeAroundRoute expected nil: \(c.args)")
            } else {
                let actualRoute = try require(actual, "resumeAroundRoute result")
                let expected = try c.expect.resumedRoute()
                assertResumedRouteEqual(actualRoute, expected, c.compare, "resumeAroundRoute")
            }

        case "resumedPose":
            let routeArg = try require(c.args["route"], "route")
            let route = try routeArg.resumedRoute()
            let u = try require(c.args["u"]?.doubleValue, "u")
            let actual = PerchAround.resumedPose(route: route, u: u)
            let expected = try c.expect.aroundPose()
            assertAroundPoseEqual(actual, expected, c.compare, "resumedPose")

        case "resumedBaseS":
            let routeArg = try require(c.args["route"], "route")
            let route = try routeArg.resumedRoute()
            let u = try require(c.args["u"]?.doubleValue, "u")
            let actual = PerchAround.resumedBaseS(route: route, u: u)
            if c.expect.isNull {
                XCTAssertNil(actual, "resumedBaseS expected nil: \(c.args)")
            } else {
                let expected = try require(c.expect.doubleValue, "expect")
                let actualValue = try require(actual, "resumedBaseS result")
                assertNumbersEqual(actualValue, expected, c.compare, "resumedBaseS")
            }

        default:
            XCTFail("unknown fn in around fixture: \(c.fn)")
        }
    }

    private func assertNumbersEqual(_ actual: Double, _ expected: Double, _ rule: CompareRule, _ label: String) {
        XCTAssertTrue(
            ConformanceCompare.numbersEqual(actual, expected, rule: rule),
            "\(label) mismatch: actual=\(actual) expected=\(expected)"
        )
    }

    private func assertDoubleArrayEqual(_ actual: [Double], _ expected: [Double], _ rule: CompareRule, _ label: String) {
        XCTAssertEqual(actual.count, expected.count, "\(label) length mismatch")
        for i in 0..<Swift.min(actual.count, expected.count) {
            assertNumbersEqual(actual[i], expected[i], rule, "\(label)[\(i)]")
        }
    }

    private func assertAroundPoseEqual(_ actual: AroundPose, _ expected: AroundPose, _ rule: CompareRule, _ label: String) {
        assertNumbersEqual(actual.x, expected.x, rule, "\(label).x")
        assertNumbersEqual(actual.seatY, expected.seatY, rule, "\(label).seatY")
        assertNumbersEqual(actual.rotation, expected.rotation, rule, "\(label).rotation")
    }

    private func assertAroundPathEqual(_ actual: AroundPath, _ expected: AroundPath, _ rule: CompareRule, _ label: String) {
        XCTAssertEqual(actual.exitSide, expected.exitSide, "\(label).exitSide mismatch")
        XCTAssertEqual(actual.enterSide, expected.enterSide, "\(label).enterSide mismatch")
        XCTAssertEqual(actual.facing, expected.facing, "\(label).facing mismatch")
        XCTAssertEqual(actual.spin, expected.spin, "\(label).spin mismatch")
        assertNumbersEqual(actual.pivot, expected.pivot, rule, "\(label).pivot")
        assertNumbersEqual(actual.seatFeetY, expected.seatFeetY, rule, "\(label).seatFeetY")
        assertNumbersEqual(actual.underY, expected.underY, rule, "\(label).underY")
        assertNumbersEqual(actual.cxExit, expected.cxExit, rule, "\(label).cxExit")
        assertNumbersEqual(actual.cxEnter, expected.cxEnter, rule, "\(label).cxEnter")
        assertNumbersEqual(actual.cy, expected.cy, rule, "\(label).cy")
        assertNumbersEqual(actual.a, expected.a, rule, "\(label).a")
        assertNumbersEqual(actual.b, expected.b, rule, "\(label).b")
        assertNumbersEqual(actual.feetX0, expected.feetX0, rule, "\(label).feetX0")
        assertNumbersEqual(actual.targetFeetX, expected.targetFeetX, rule, "\(label).targetFeetX")
        assertDoubleArrayEqual(actual.arcCum, expected.arcCum, rule, "\(label).arcCum")
        assertNumbersEqual(actual.arcLen, expected.arcLen, rule, "\(label).arcLen")
        assertDoubleArrayEqual(actual.legs, expected.legs, rule, "\(label).legs")
        assertNumbersEqual(actual.totalLen, expected.totalLen, rule, "\(label).totalLen")
        assertNumbersEqual(actual.totalMs, expected.totalMs, rule, "\(label).totalMs")
    }

    private func assertResumedRouteEqual(_ actual: ResumedRoute, _ expected: ResumedRoute, _ rule: CompareRule, _ label: String) {
        assertAroundPathEqual(actual.base, expected.base, rule, "\(label).base")
        assertNumbersEqual(actual.startS, expected.startS, rule, "\(label).startS")
        assertNumbersEqual(actual.endS, expected.endS, rule, "\(label).endS")
        XCTAssertEqual(actual.dir, expected.dir, "\(label).dir mismatch")
        assertNumbersEqual(actual.curveLen, expected.curveLen, rule, "\(label).curveLen")
        assertNumbersEqual(actual.tailFromFeetX, expected.tailFromFeetX, rule, "\(label).tailFromFeetX")
        assertNumbersEqual(actual.tailToFeetX, expected.tailToFeetX, rule, "\(label).tailToFeetX")
        assertNumbersEqual(actual.tailLen, expected.tailLen, rule, "\(label).tailLen")
        assertNumbersEqual(actual.totalLen, expected.totalLen, rule, "\(label).totalLen")
        assertNumbersEqual(actual.totalMs, expected.totalMs, rule, "\(label).totalMs")
        XCTAssertEqual(actual.facing, expected.facing, "\(label).facing mismatch")
        assertNumbersEqual(actual.endRotation, expected.endRotation, rule, "\(label).endRotation")
    }

    private func require<T>(_ value: T?, _ label: String, file: StaticString = #filePath, line: UInt = #line) throws -> T {
        guard let value else {
            XCTFail("missing or mistyped \(label)", file: file, line: line)
            throw AroundConformanceLoadError.missingField(label)
        }
        return value
    }
}

private enum AroundConformanceLoadError: Error {
    case missingField(String)
}
