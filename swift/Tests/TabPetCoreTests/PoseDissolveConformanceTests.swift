import XCTest

import TabPetCore

/// Every PoseDissolve function the conformance/pose-dissolve.json fixture must
/// cover. Kept in sync by hand with PoseDissolve.swift's public functions -
/// Swift has no runtime export list to diff against, unlike the TypeScript
/// reader (conformance.test.ts), which enumerates the module namespace.
private let knownPoseDissolveFunctions: Set<String> = [
    "planPoseDissolve",
    "poseDissolveApplyOrder",
    "shouldResetIncomingFrame",
    "shouldSnapBusyIdleFrameToRest",
]

final class PoseDissolveConformanceTests: XCTestCase {
    func testPoseDissolveFixtureCoverage() throws {
        let fixture = try ConformanceFixtureLoader.load("pose-dissolve")
        XCTAssertEqual(fixture.module, "pose-dissolve")

        let covered = Set(fixture.cases.map(\.fn))
        for fn in covered {
            XCTAssertTrue(knownPoseDissolveFunctions.contains(fn), "fixture names unknown function \(fn)")
        }
        for fn in knownPoseDissolveFunctions {
            XCTAssertTrue(covered.contains(fn), "PoseDissolve.\(fn) has no fixture coverage")
        }

        var casesRun = 0
        for c in fixture.cases {
            try runCase(c)
            casesRun += 1
        }
        XCTAssertEqual(casesRun, fixture.cases.count)
        XCTAssertGreaterThan(casesRun, 0)
        print("PoseDissolveConformanceTests: \(casesRun) conformance cases passed")
    }

    /// pins POSE_FADE_MS against the fixture's own copy.
    func testPoseDissolveConstantsMatchModule() throws {
        let fixture = try ConformanceFixtureLoader.load("pose-dissolve")
        XCTAssertEqual(try fixture.constant("POSE_FADE_MS"), PoseDissolve.POSE_FADE_MS)
    }

    private func runCase(_ c: ConformanceCase) throws {
        switch c.fn {
        case "planPoseDissolve":
            let previous = try requirePose(c.args["previous"], "previous")
            let next = try requirePose(c.args["next"], "next")
            // opts itself, and opts.reduceMotion within it, are each optional -
            // missing/null at either level means false; a wrongly-typed
            // reduceMotion still throws rather than silently reading as false.
            let optsJSON = c.args["opts"]
            let reduceMotion: Bool
            if let optsJSON, !optsJSON.isNull {
                reduceMotion = try optsJSON.optionalBool("reduceMotion", "opts.reduceMotion") ?? false
            } else {
                reduceMotion = false
            }
            let actual = PoseDissolve.planPoseDissolve(previous: previous, next: next, reduceMotion: reduceMotion)
            try assertPlanMatches(actual, c.expect, rule: c.compare, c)

        case "poseDissolveApplyOrder":
            let planJSON = try require(c.args["plan"], "plan")
            let plan = try parsePlan(planJSON)
            let actual = PoseDissolve.poseDissolveApplyOrder(plan: plan)
            let expectedArray = try require(c.expect.arrayValue, "expect")
            let expected = try expectedArray.map { try requirePose($0, "expect element") }
            XCTAssertEqual(actual, expected, "poseDissolveApplyOrder mismatch: \(c.args)")

        case "shouldResetIncomingFrame":
            let previous = try requirePose(c.args["previous"], "previous")
            let next = try requirePose(c.args["next"], "next")
            let actual = PoseDissolve.shouldResetIncomingFrame(previous: previous, next: next)
            let expected = try require(c.expect.boolValue, "expect")
            XCTAssertEqual(actual, expected, "shouldResetIncomingFrame mismatch: \(c.args)")

        case "shouldSnapBusyIdleFrameToRest":
            let currentPose = try requirePose(c.args["currentPose"], "currentPose")
            let actual = PoseDissolve.shouldSnapBusyIdleFrameToRest(currentPose: currentPose)
            let expected = try require(c.expect.boolValue, "expect")
            XCTAssertEqual(actual, expected, "shouldSnapBusyIdleFrameToRest mismatch: \(c.args)")

        default:
            XCTFail("unknown fn in pose-dissolve fixture: \(c.fn)")
        }
    }

    private func assertPlanMatches(_ actual: PoseDissolvePlan, _ expected: JSONValue, rule: CompareRule, _ c: ConformanceCase) throws {
        for pose in PoseDissolve.PUP_POSES {
            let poseKey = pose.rawValue
            let expectedPose = try require(expected[poseKey], "expect.\(poseKey)")
            let actualAssignment = actual[pose]
            let expectedOpacity = try require(expectedPose["opacity"], "expect.\(poseKey).opacity")
            let expectedKind = try require(expectedOpacity["kind"]?.stringValue, "expect.\(poseKey).opacity.kind")
            switch (actualAssignment.opacity, expectedKind) {
            case (.hidden, "hidden"), (.opaque, "opaque"):
                break
            case (.fadeOut(let durationMs), "fade-out"):
                let expectedDuration = try require(expectedOpacity["durationMs"]?.doubleValue, "expect.\(poseKey).opacity.durationMs")
                XCTAssertTrue(
                    ConformanceCompare.numbersEqual(durationMs, expectedDuration, rule: rule),
                    "\(poseKey) durationMs mismatch: \(c.args) actual=\(durationMs) expected=\(expectedDuration)"
                )
            default:
                XCTFail("\(poseKey) opacity kind mismatch: actual=\(actualAssignment.opacity) expected=\(expectedKind) args=\(c.args)")
            }
            let expectedZ = try require(expectedPose["z"]?.intValue, "expect.\(poseKey).z")
            XCTAssertEqual(actualAssignment.z, expectedZ, "\(poseKey) z mismatch: \(c.args)")
        }
    }

    /// parses a fixture's `plan` argument (a `PoseDissolvePlan`'s own JSON shape) back into a `PoseDissolvePlan`
    private func parsePlan(_ json: JSONValue) throws -> PoseDissolvePlan {
        func parseAssignment(_ poseKey: String) throws -> PoseLayerAssignment {
            let poseJSON = try require(json[poseKey], poseKey)
            let opacityJSON = try require(poseJSON["opacity"], "\(poseKey).opacity")
            let kind = try require(opacityJSON["kind"]?.stringValue, "\(poseKey).opacity.kind")
            let opacity: PoseOpacityKind
            switch kind {
            case "hidden":
                opacity = .hidden
            case "opaque":
                opacity = .opaque
            case "fade-out":
                let durationMs = try require(opacityJSON["durationMs"]?.doubleValue, "\(poseKey).opacity.durationMs")
                opacity = .fadeOut(durationMs: durationMs)
            default:
                XCTFail("unknown opacity kind in fixture plan: \(kind)")
                throw ConformanceLoadError.missingField("\(poseKey).opacity.kind")
            }
            let z = try require(poseJSON["z"]?.intValue, "\(poseKey).z")
            return PoseLayerAssignment(opacity: opacity, z: z)
        }
        return PoseDissolvePlan(idle: try parseAssignment("idle"), run: try parseAssignment("run"), sit: try parseAssignment("sit"))
    }

    private func requirePose(_ value: JSONValue?, _ label: String, file: StaticString = #filePath, line: UInt = #line) throws -> PupPose {
        guard let raw = value?.stringValue, let pose = PupPose(rawValue: raw) else {
            XCTFail("missing or unrecognized \(label)", file: file, line: line)
            throw ConformanceLoadError.missingField(label)
        }
        return pose
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
