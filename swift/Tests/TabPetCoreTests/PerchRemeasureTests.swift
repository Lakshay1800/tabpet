import XCTest

import TabPetCore

/// Mirrors perch-remeasure.test.ts. TabPetCore has no default frame scheduler
/// (see PerchRemeasure.swift), so every test injects the fake one below,
/// including testDefaultsToRequestAnimationFrame, which in the TypeScript
/// exercises the default requestAnimationFrame wiring.
@MainActor
final class PerchRemeasureTests: XCTestCase {
    /// fake scheduler: queues (handle, tick) pairs, `flush()` runs them one at
    /// a time and SKIPS a tick whose handle was cancelled before its turn -
    /// mirrors the TypeScript fake exactly (perch-remeasure.test.ts).
    @MainActor
    private final class FakeScheduler {
        private var queue: [(handle: Int, fn: @MainActor @Sendable () -> Void)] = []
        private(set) var cancelledHandles: Set<Int> = []
        private var nextHandle = 0
        /// the handle of the most recently scheduled, not-yet-run tick
        private(set) var lastHandle: Int?

        func schedule(_ fn: @escaping @MainActor @Sendable () -> Void) -> Int {
            let handle = nextHandle
            nextHandle += 1
            queue.append((handle, fn))
            lastHandle = handle
            return handle
        }

        func cancel(_ handle: Int) {
            cancelledHandles.insert(handle)
        }

        func flush() {
            while !queue.isEmpty {
                let next = queue.removeFirst()
                if cancelledHandles.contains(next.handle) {
                    continue
                }
                next.fn()
            }
        }

        /// Runs exactly one queued tick, skipping it if already cancelled - not
        /// in the TypeScript fake (whose flush always drains fully); needed here
        /// to leave a tick outstanding and inspect which handle is current.
        func step() {
            guard !queue.isEmpty else {
                return
            }
            let next = queue.removeFirst()
            if cancelledHandles.contains(next.handle) {
                return
            }
            next.fn()
        }
    }

    func testResolvesOnFirstDefinedValue() {
        let scheduler = FakeScheduler()
        var attempts = 0
        var results: [Int] = []
        _ = PerchRemeasure.retryMeasure(
            measure: {
                attempts += 1
                if attempts < 3 {
                    return nil
                }
                return 42
            },
            onMeasured: { value in results.append(value) },
            maxTries: 60,
            schedule: { scheduler.schedule($0) },
            cancel: { scheduler.cancel($0) }
        )
        scheduler.flush()
        XCTAssertEqual(results, [42], "calls onMeasured once with the first defined value")
        XCTAssertEqual(attempts, 3, "stopped measuring once a value was found")
    }

    func testGivesUpAfterMaxTries() {
        let scheduler = FakeScheduler()
        var attempts = 0
        var results: [Int] = []
        _ = PerchRemeasure.retryMeasure(
            measure: { () -> Int? in
                attempts += 1
                return nil
            },
            onMeasured: { value in results.append(value) },
            maxTries: 5,
            schedule: { scheduler.schedule($0) },
            cancel: { scheduler.cancel($0) }
        )
        scheduler.flush()
        XCTAssertEqual(attempts, 5, "stopped after maxTries undefined results")
        XCTAssertEqual(results, [], "onMeasured never called")
    }

    func testCancelPreventsCallback() {
        let scheduler = FakeScheduler()
        var attempts = 0
        var results: [Int] = []
        let stop = PerchRemeasure.retryMeasure(
            measure: {
                attempts += 1
                if attempts < 3 {
                    return nil
                }
                return 42
            },
            onMeasured: { value in results.append(value) },
            maxTries: 60,
            schedule: { scheduler.schedule($0) },
            cancel: { scheduler.cancel($0) }
        )
        stop()
        scheduler.flush()
        XCTAssertEqual(results, [], "onMeasured never called after cancel")
    }

    func testOnMeasuredFiresExactlyOnce() {
        let scheduler = FakeScheduler()
        var results: [Int] = []
        _ = PerchRemeasure.retryMeasure(
            measure: { 7 },
            onMeasured: { value in results.append(value) },
            maxTries: 60,
            schedule: { scheduler.schedule($0) },
            cancel: { scheduler.cancel($0) }
        )
        scheduler.flush()
        scheduler.flush() // nothing left queued - a second flush must not re-invoke
        XCTAssertEqual(results.count, 1, "onMeasured fires exactly once")
    }

    /// Not in perch-remeasure.test.ts (the TS fake scheduler is the same one
    /// used above; this is new coverage this port owed it). Advances two
    /// ticks without resolving, then cancels - the scheduler must see the
    /// handle from the tick still outstanding, not a stale one from an
    /// already-run tick.
    func testCancelPassesTheLatestOutstandingHandle() {
        let scheduler = FakeScheduler()
        let stop = PerchRemeasure.retryMeasure(
            measure: { () -> Int? in nil },
            onMeasured: { _ in XCTFail("should not be called") },
            maxTries: 60,
            schedule: { scheduler.schedule($0) },
            cancel: { scheduler.cancel($0) }
        )
        scheduler.step() // runs the initial tick (handle 0), schedules handle 1
        scheduler.step() // runs handle 1's tick, schedules handle 2 - still outstanding

        stop()

        XCTAssertEqual(scheduler.lastHandle, 2, "sanity: handle 2 is the latest scheduled")
        XCTAssertEqual(scheduler.cancelledHandles, [2], "cancel was passed the currently outstanding handle")
    }

    /// Not in perch-remeasure.test.ts. TypeScript's returned stop closure has
    /// no re-entrancy guard either - a second call just cancels the same
    /// handle again, which a real cancelAnimationFrame tolerates.
    func testCancelCalledTwiceIsHarmless() {
        let scheduler = FakeScheduler()
        let stop = PerchRemeasure.retryMeasure(
            measure: { () -> Int? in nil },
            onMeasured: { _ in XCTFail("should not be called") },
            maxTries: 60,
            schedule: { scheduler.schedule($0) },
            cancel: { scheduler.cancel($0) }
        )
        stop()
        stop()
        XCTAssertEqual(scheduler.cancelledHandles, [0], "double-cancel of the same handle is a harmless no-op")
    }

    /// TypeScript checks the default-rAF wiring; here a manual scheduler stands in
    /// (schedule/cancel are required, not defaulted - see PerchRemeasure.swift).
    func testDefaultsToRequestAnimationFrame() {
        var scheduled = 0
        let stop = PerchRemeasure.retryMeasure(
            measure: { () -> Int? in
                nil // never resolves in this test - just checking scheduling wiring
            },
            onMeasured: { _ in
                XCTFail("should not be called")
            },
            schedule: { _ in
                scheduled += 1
                return scheduled
            },
            cancel: { _ in
                // no-op fake
            }
        )
        XCTAssertEqual(scheduled, 1, "scheduled once via the default rAF")
        stop()
    }
}
