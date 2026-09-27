import XCTest

import TabPetCore

/// Every PerchGeometry function the conformance/geometry.json fixture must
/// cover. Kept in sync by hand with PerchGeometry.swift's public functions -
/// Swift has no runtime export list to diff against, unlike the TypeScript
/// reader (conformance.test.ts), which enumerates the module namespace.
private let knownGeometryFunctions: Set<String> = [
    "tabCenterX",
    "nearestSlot",
    "glassTargetX",
    "chaseTargetX",
    "chaseStep",
    "travelFacing",
    "shouldSnapToSeat",
    "traverseDurationMs",
    "seatedFootPad",
]

final class GeometryConformanceTests: XCTestCase {
    func testGeometryFixtureCoverage() throws {
        let fixture = try ConformanceFixtureLoader.load("geometry")
        XCTAssertEqual(fixture.module, "perch-geometry")

        let covered = Set(fixture.cases.map(\.fn))
        for fn in covered {
            XCTAssertTrue(knownGeometryFunctions.contains(fn), "fixture names unknown function \(fn)")
        }
        for fn in knownGeometryFunctions {
            XCTAssertTrue(covered.contains(fn), "PerchGeometry.\(fn) has no fixture coverage")
        }

        var casesRun = 0
        for c in fixture.cases {
            try runCase(c)
            casesRun += 1
        }
        XCTAssertEqual(casesRun, fixture.cases.count)
        XCTAssertGreaterThan(casesRun, 0)
        print("GeometryConformanceTests: \(casesRun) conformance cases passed")
    }

    /// direct unit checks of the tolerance rule, independent of any fixture.
    func testToleranceRule() {
        let checks: [(Double, Double, Bool)] = [
            (.infinity, .infinity, true),
            (.infinity, 5, false),
            (-.infinity, .infinity, false),
            (.nan, .nan, true),
            (.nan, 1, false),
            (1, 1 + 1e-12, true),
            (1, 1.001, false),
        ]
        for (a, b, expected) in checks {
            XCTAssertEqual(
                ConformanceCompare.numbersEqual(a, b, rule: .tolerance),
                expected,
                "tolerance rule: numbersEqual(\(a), \(b)) should be \(expected)"
            )
        }
    }

    private func runCase(_ c: ConformanceCase) throws {
        switch c.fn {
        case "tabCenterX":
            let tab = try require(c.args["tab"]?.intValue, "tab")
            let screenWidth = try require(c.args["screenWidth"]?.doubleValue, "screenWidth")
            let slotCount = try require(c.args["slotCount"]?.intValue, "slotCount")
            let slotCenters = try c.args["slotCenters"]?.doubleArray()
            let actual = PerchGeometry.tabCenterX(tab: tab, screenWidth: screenWidth, slotCount: slotCount, slotCenters: slotCenters)
            let expected = try require(c.expect.doubleValue, "expect")
            assertNumbersEqual(actual, expected, c.compare, c)

        case "nearestSlot":
            let x = try require(c.args["x"]?.doubleValue, "x")
            let screenWidth = try require(c.args["screenWidth"]?.doubleValue, "screenWidth")
            let slotCount = try require(c.args["slotCount"]?.intValue, "slotCount")
            let slotCenters = try c.args["slotCenters"]?.doubleArray()
            let actual = PerchGeometry.nearestSlot(x: x, screenWidth: screenWidth, slotCount: slotCount, slotCenters: slotCenters)
            let expected = try require(c.expect.intValue, "expect")
            XCTAssertEqual(actual, expected, "nearestSlot mismatch: \(c.args)")

        case "glassTargetX":
            let fingerX = try require(c.args["fingerX"]?.doubleValue, "fingerX")
            let screenWidth = try require(c.args["screenWidth"]?.doubleValue, "screenWidth")
            let actual = PerchGeometry.glassTargetX(fingerX: fingerX, screenWidth: screenWidth)
            let expected = try require(c.expect.doubleValue, "expect")
            assertNumbersEqual(actual, expected, c.compare, c)

        case "chaseTargetX":
            let glassX = try require(c.args["glassX"]?.doubleValue, "glassX")
            let directionRaw = try require(c.args["direction"]?.intValue, "direction")
            let direction = try require(Facing(rawValue: directionRaw), "direction")
            let screenWidth = try require(c.args["screenWidth"]?.doubleValue, "screenWidth")
            let actual = PerchGeometry.chaseTargetX(glassX: glassX, direction: direction, screenWidth: screenWidth)
            let expected = try require(c.expect.doubleValue, "expect")
            assertNumbersEqual(actual, expected, c.compare, c)

        case "chaseStep":
            let glassX = try require(c.args["glassX"]?.doubleValue, "glassX")
            let currentX = try require(c.args["currentX"]?.doubleValue, "currentX")
            let currentFacingRaw = try require(c.args["currentFacing"]?.intValue, "currentFacing")
            let currentFacing = try require(Facing(rawValue: currentFacingRaw), "currentFacing")
            let chasing = try require(c.args["chasing"]?.boolValue, "chasing")
            let actual = PerchGeometry.chaseStep(glassX: glassX, currentX: currentX, currentFacing: currentFacing, chasing: chasing)

            let expectedTarget = try require(c.expect["target"], "expect.target")
            if expectedTarget.isNull {
                XCTAssertNil(actual.target, "chaseStep target should be nil: \(c.args)")
            } else if let actualTarget = actual.target {
                let expectedValue = try require(expectedTarget.doubleValue, "expect.target")
                XCTAssertTrue(
                    ConformanceCompare.numbersEqual(actualTarget, expectedValue, rule: c.compare),
                    "chaseStep target mismatch: \(c.args) actual=\(actualTarget) expected=\(expectedValue)"
                )
            } else {
                XCTFail("chaseStep expected a non-nil target: \(c.args)")
            }
            let expectedFacingRaw = try require(c.expect["facing"]?.intValue, "expect.facing")
            let expectedFacing = try require(Facing(rawValue: expectedFacingRaw), "expect.facing")
            XCTAssertEqual(actual.facing, expectedFacing, "chaseStep facing mismatch: \(c.args)")

        case "travelFacing":
            let targetX = try require(c.args["targetX"]?.doubleValue, "targetX")
            let currentX = try require(c.args["currentX"]?.doubleValue, "currentX")
            let currentFacingRaw = try require(c.args["currentFacing"]?.intValue, "currentFacing")
            let currentFacing = try require(Facing(rawValue: currentFacingRaw), "currentFacing")
            let actual = PerchGeometry.travelFacing(targetX: targetX, currentX: currentX, currentFacing: currentFacing)
            let expectedRaw = try require(c.expect.intValue, "expect")
            let expected = try require(Facing(rawValue: expectedRaw), "expect")
            XCTAssertEqual(actual, expected, "travelFacing mismatch: \(c.args)")

        case "shouldSnapToSeat":
            let distancePt = try require(c.args["distancePt"]?.doubleValue, "distancePt")
            let actual = PerchGeometry.shouldSnapToSeat(distancePt: distancePt)
            let expected = try require(c.expect.boolValue, "expect")
            XCTAssertEqual(actual, expected, "shouldSnapToSeat mismatch: \(c.args)")

        case "traverseDurationMs":
            let distancePt = try require(c.args["distancePt"]?.doubleValue, "distancePt")
            let speedJSON = c.args["speedPtS"]
            let actual: Double
            if let speedJSON, !speedJSON.isNull {
                let speedPtS = try require(speedJSON.doubleValue, "speedPtS")
                actual = PerchGeometry.traverseDurationMs(distancePt: distancePt, speedPtS: speedPtS)
            } else {
                actual = PerchGeometry.traverseDurationMs(distancePt: distancePt)
            }
            let expected = try require(c.expect.doubleValue, "expect")
            assertNumbersEqual(actual, expected, c.compare, c)

        case "seatedFootPad":
            let footPad = try require(c.args["footPad"]?.doubleValue, "footPad")
            let scale = try require(c.args["scale"]?.doubleValue, "scale")
            let actual = PerchGeometry.seatedFootPad(footPad: footPad, scale: scale)
            let expected = try require(c.expect.doubleValue, "expect")
            assertNumbersEqual(actual, expected, c.compare, c)

        default:
            XCTFail("unknown fn in geometry fixture: \(c.fn)")
        }
    }

    private func assertNumbersEqual(_ actual: Double, _ expected: Double, _ rule: CompareRule, _ c: ConformanceCase) {
        XCTAssertTrue(
            ConformanceCompare.numbersEqual(actual, expected, rule: rule),
            "\(c.fn) mismatch: args=\(c.args) actual=\(actual) expected=\(expected)"
        )
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
