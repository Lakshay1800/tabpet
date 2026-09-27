import XCTest

import TabPetCore

/// Mirrors perch-reentry.test.ts.
final class PerchReentryTests: XCTestCase {
    func testArriveOnlyWhenGenerationMatches() {
        XCTAssertTrue(
            PerchReentry.shouldApplyArrive(callbackGeneration: 3, currentGeneration: 3, mounted: true),
            "matching generation on a live instance may sit"
        )
        XCTAssertFalse(
            PerchReentry.shouldApplyArrive(callbackGeneration: 3, currentGeneration: 4, mounted: true),
            "stale generation after re-entry must not sit"
        )
        XCTAssertFalse(
            PerchReentry.shouldApplyArrive(callbackGeneration: 3, currentGeneration: 3, mounted: false),
            "unmounted arrive is ignored even if the generation matches"
        )
        // exact equality only - a callback generation ahead of current (should
        // never happen, but == must not be loosened to >=) must not sit either
        XCTAssertFalse(
            PerchReentry.shouldApplyArrive(callbackGeneration: 4, currentGeneration: 3, mounted: true),
            "a callback generation greater than current must not sit"
        )
    }
}
