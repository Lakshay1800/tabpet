import XCTest

import TabPetCore

/// registry.ts has no TS test file to mirror. Covers the semantics the port
/// commits to: duplicate registration overwrites in place (does not reorder),
/// list()/ids() return insertion order, and get() on an unknown id is nil.
@MainActor
final class RegistryTests: XCTestCase {
    private func profile(
        _ id: String,
        label: String = "test",
        footPad: Double? = nil,
        seatLift: Double? = nil,
        headPad: Double? = nil,
        runSpeed: Double? = nil,
        sitSheet: SheetGeometry? = nil
    ) -> CompanionProfile {
        CompanionProfile(
            id: id,
            label: label,
            runFps: 12,
            commitSpring: SpringConfig(duration: 400, dampingRatio: 0.9),
            trackSpring: SpringConfig(duration: 240, dampingRatio: 0.86),
            catchSpring: SpringConfig(duration: 260, dampingRatio: 0.9),
            hopHeight: 0,
            flightLift: 0,
            scale: 1,
            aroundRoute: false,
            headPad: headPad,
            footPad: footPad,
            seatLift: seatLift,
            runSpeed: runSpeed,
            sitSheet: sitSheet
        )
    }

    func testStartsEmpty() {
        let registry = CompanionRegistry()
        XCTAssertEqual(registry.list(), [])
        XCTAssertEqual(registry.ids(), [])
    }

    func testGetUnknownIdIsNil() {
        let registry = CompanionRegistry()
        XCTAssertNil(registry.get("panda"))
    }

    func testGetUnknownIdInNonEmptyRegistryIsNil() {
        let registry = CompanionRegistry()
        registry.register(profile("panda"))
        XCTAssertNil(registry.get("cat"), "an id that was never registered is nil even alongside other entries")
    }

    /// list()/ids() return insertion order, matching Object.values/Object.keys
    /// for the string keys this registry actually uses. A real JS object lists
    /// integer-like keys ("2", "1", ...) first, in NUMERIC order, ahead of any
    /// insertion-ordered string keys - not reproduced here since companion ids
    /// (panda, cat, ...) are never integer-like.
    func testListAndIdsReturnInsertionOrder() {
        let registry = CompanionRegistry()
        registry.register(profile("panda"))
        registry.register(profile("cat"))
        registry.register(profile("turtle"))
        XCTAssertEqual(registry.ids(), ["panda", "cat", "turtle"])
        XCTAssertEqual(registry.list().map(\.id), ["panda", "cat", "turtle"])
    }

    func testDuplicateIdOverwritesInPlaceWithoutReordering() {
        let registry = CompanionRegistry()
        registry.register(profile("panda", label: "first"))
        registry.register(profile("cat"))
        registry.register(profile("panda", label: "second"))
        XCTAssertEqual(registry.ids(), ["panda", "cat"], "re-registering an id keeps its original position")
        XCTAssertEqual(registry.get("panda")?.label, "second", "re-registering an id overwrites its profile")
    }

    // MARK: - Resolved defaults (registry.ts's `??` sites, applied at the profile level)

    func testResolvedFootPadUsesTheFieldWhenPresent() {
        XCTAssertEqual(profile("panda", footPad: 3.6).resolvedFootPad, 3.6)
    }

    func testResolvedFootPadFallsBackToSpriteFootPadWhenAbsent() {
        XCTAssertEqual(profile("panda").resolvedFootPad, 11)
    }

    func testResolvedSeatLiftUsesTheFieldWhenPresent() {
        XCTAssertEqual(profile("panda", seatLift: 2).resolvedSeatLift, 2)
    }

    func testResolvedSeatLiftFallsBackToBarTopAboveInsetWhenAbsent() {
        XCTAssertEqual(profile("panda").resolvedSeatLift, 6)
    }

    func testResolvedHeadPadUsesTheFieldWhenPresent() {
        XCTAssertEqual(profile("panda", headPad: 2).resolvedHeadPad, 2)
    }

    func testResolvedHeadPadFallsBackToZeroWhenAbsent() {
        XCTAssertEqual(profile("panda").resolvedHeadPad, 0)
    }

    func testResolvedRunSpeedUsesTheFieldWhenPresent() {
        XCTAssertEqual(profile("turtle", runSpeed: 200).resolvedRunSpeed, 200)
    }

    func testResolvedRunSpeedFallsBackToTraverseSpeedWhenAbsent() {
        XCTAssertEqual(profile("panda").resolvedRunSpeed, 340)
    }

    func testResolvedSitSheetUsesTheFieldWhenPresent() {
        let custom = SheetGeometry(cols: 10, rows: 5, frames: 50, fps: 24)
        XCTAssertEqual(profile("panda", sitSheet: custom).resolvedSitSheet, custom)
    }

    func testResolvedSitSheetFallsBackToTheSharedDefaultWhenAbsent() {
        XCTAssertEqual(profile("panda").resolvedSitSheet, SheetGeometry(cols: 5, rows: 5, frames: 25, fps: 12))
    }
}
