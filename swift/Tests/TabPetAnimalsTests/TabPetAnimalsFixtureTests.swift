import XCTest

import TabPetAnimals
import TabPetCore

/// Every test in this file reads conformance/animals.json by repository
/// path, so it does not run on the simulator (tools/swift-sim-test.sh leaves
/// this whole class out) - only macOS `swift test`.
@MainActor
final class TabPetAnimalsFixtureTests: XCTestCase {
    func testSheetGridConstantsMatchTheFixtureConstants() throws {
        let fixture = try AnimalsFixture.load()
        func value(_ name: String) throws -> Double {
            try XCTUnwrap(fixture.constants[name], "fixture is missing constant \(name)").value
        }

        let idleGrid = CompanionProfile.IDLE_SHEET_GRID
        XCTAssertEqual(Double(idleGrid.cols), try value("idleCols"))
        XCTAssertEqual(Double(idleGrid.rows), try value("idleRows"))
        XCTAssertEqual(Double(idleGrid.frames), try value("idleFrames"))
        XCTAssertEqual(idleGrid.fps.bitPattern, try value("idleFps").bitPattern)

        let runGrid = CompanionProfile.RUN_SHEET_GRID
        XCTAssertEqual(Double(runGrid.cols), try value("runCols"))
        XCTAssertEqual(Double(runGrid.rows), try value("runRows"))
        XCTAssertEqual(Double(runGrid.frames), try value("runFrames"))

        let sitGrid = CompanionProfile.DEFAULT_SIT_SHEET
        XCTAssertEqual(Double(sitGrid.cols), try value("sitCols"))
        XCTAssertEqual(Double(sitGrid.rows), try value("sitRows"))
        XCTAssertEqual(Double(sitGrid.frames), try value("sitFrames"))
        XCTAssertEqual(sitGrid.fps.bitPattern, try value("sitFps").bitPattern)
    }

    /// Proves the pinned literals in AssetHashes.swift haven't drifted from
    /// the generator's own copy.
    func testPinnedHashesMatchTheFixture() throws {
        let fixture = try AnimalsFixture.load()
        XCTAssertEqual(pinnedLicenseSHA256, fixture.assetHashes.license)
        for animal in animalsUnderTest {
            let expected = try XCTUnwrap(fixture.assetHashes.sheets[animal.id])
            let pinned = try XCTUnwrap(pinnedSheetSHA256[animal.id])
            XCTAssertEqual(pinned.idle, expected.idle, "\(animal.id) idle")
            XCTAssertEqual(pinned.run, expected.run, "\(animal.id) run")
            XCTAssertEqual(pinned.sit, expected.sit, "\(animal.id) sit")
        }
    }

    // MARK: - profile equals the fixture exactly, bit for bit

    func testEachProfileEqualsTheFixtureExactly() throws {
        let fixture = try AnimalsFixture.load()
        XCTAssertEqual(fixture.cases.count, animalsUnderTest.count)

        for (animalCase, animal) in zip(fixture.cases, animalsUnderTest) {
            XCTAssertEqual(animalCase.args.id, animal.id)
            let expect = animalCase.expect
            let profile = animal.profile

            XCTAssertEqual(profile.id, expect.id, "\(animal.id).id")
            XCTAssertEqual(profile.label, expect.label, "\(animal.id).label")
            XCTAssertEqual(profile.runFps.bitPattern, expect.runFps.bitPattern, "\(animal.id).runFps")
            assertSpringEqual(profile.commitSpring, expect.commitSpring, "\(animal.id).commitSpring")
            assertSpringEqual(profile.trackSpring, expect.trackSpring, "\(animal.id).trackSpring")
            assertSpringEqual(profile.catchSpring, expect.catchSpring, "\(animal.id).catchSpring")
            XCTAssertEqual(profile.hopHeight.bitPattern, expect.hopHeight.bitPattern, "\(animal.id).hopHeight")
            XCTAssertEqual(profile.flightLift.bitPattern, expect.flightLift.bitPattern, "\(animal.id).flightLift")
            XCTAssertEqual(profile.scale.bitPattern, expect.scale.bitPattern, "\(animal.id).scale")
            XCTAssertEqual(profile.aroundRoute, expect.aroundRoute, "\(animal.id).aroundRoute")
            XCTAssertEqual(profile.headPad?.bitPattern, expect.headPad?.bitPattern, "\(animal.id).headPad")
            XCTAssertEqual(profile.footPad?.bitPattern, expect.footPad?.bitPattern, "\(animal.id).footPad")
            XCTAssertEqual(profile.seatLift?.bitPattern, expect.seatLift?.bitPattern, "\(animal.id).seatLift")
            XCTAssertEqual(profile.runSpeed?.bitPattern, expect.runSpeed?.bitPattern, "\(animal.id).runSpeed")
            if let expectSit = expect.sitSheet {
                XCTAssertEqual(profile.sitSheet?.cols, expectSit.cols, "\(animal.id).sitSheet.cols")
                XCTAssertEqual(profile.sitSheet?.rows, expectSit.rows, "\(animal.id).sitSheet.rows")
                XCTAssertEqual(profile.sitSheet?.frames, expectSit.frames, "\(animal.id).sitSheet.frames")
                XCTAssertEqual(profile.sitSheet?.fps.bitPattern, expectSit.fps.bitPattern, "\(animal.id).sitSheet.fps")
            } else {
                XCTAssertNil(profile.sitSheet, "\(animal.id).sitSheet")
            }
        }
    }

    private func assertSpringEqual(_ spring: SpringConfig, _ expect: SpringFixture, _ label: String) {
        XCTAssertEqual(spring.duration.bitPattern, expect.duration.bitPattern, "\(label).duration")
        XCTAssertEqual(spring.dampingRatio.bitPattern, expect.dampingRatio.bitPattern, "\(label).dampingRatio")
    }

    // MARK: - umbrella and registry order match the fixture's case order,
    // not a literal

    func testUmbrellaAndRegistryOrderMatchTheFixture() throws {
        let fixture = try AnimalsFixture.load()
        let expectedIds = fixture.cases.map(\.args.id)
        XCTAssertEqual(expectedIds.count, animalsUnderTest.count)

        let registry = CompanionRegistry()
        TabPetAnimals.registerAll(in: registry)
        XCTAssertEqual(registry.ids(), expectedIds)
        XCTAssertEqual(TabPetAnimals.profiles.map(\.id), expectedIds)
        XCTAssertEqual(registry.list().map(\.id), TabPetAnimals.profiles.map(\.id))
    }
}
