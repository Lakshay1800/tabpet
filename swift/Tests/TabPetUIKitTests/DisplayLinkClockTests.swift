#if canImport(UIKit)
import TabPetCore
import TabPetMotion
import XCTest

@testable import TabPetUIKit

@MainActor
private func makeRealClockTestProfile() -> CompanionProfile {
    CompanionProfile(
        id: "testAnimal",
        label: "test animal",
        runFps: 12,
        commitSpring: SpringConfig(duration: 500, dampingRatio: 1),
        trackSpring: SpringConfig(duration: 500, dampingRatio: 1),
        catchSpring: SpringConfig(duration: 500, dampingRatio: 1),
        hopHeight: 0,
        flightLift: 0,
        scale: 1,
        aroundRoute: false,
        sitSheet: nil
    )
}

@MainActor
final class DisplayLinkClockTests: XCTestCase {
    // MARK: - Real-time tests (the only two in this target that use real time, loose bounds)

    func testAfterFiresWithinALooseOneSecondBound() {
        let clock = DisplayLinkClock()
        let expectation = expectation(description: "after(50ms) fires")
        let start = Date()
        _ = clock.after(milliseconds: 50) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        // Mutation: milliseconds passed to `asyncAfter` unconverted would
        // schedule this 1000x late (50 real seconds) and time the test out
        // above instead of landing here.
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.0)
    }

    func testARunningLinkProducesDtBetweenOneAndOneHundredMilliseconds() {
        let clock = DisplayLinkClock()
        var readings: [Double] = []
        let expectation = expectation(description: "two ticks")
        clock.frameHandler = { now in
            readings.append(now)
            if readings.count == 2 {
                expectation.fulfill()
            }
        }
        clock.setWantsFrames(true)
        wait(for: [expectation], timeout: 2.0)
        clock.setWantsFrames(false)
        let dt = readings[1] - readings[0]
        // Mutation: dropping the `* 1000` (via ClockUnits.ms) in the frame
        // time would make `now` read in seconds, putting dt far under 1ms.
        XCTAssertGreaterThan(dt, 1)
        XCTAssertLessThan(dt, 100)
    }

    // MARK: - Deterministic state tests

    func testSetWantsFramesFalsePausesTheLinkInTheSameTick() {
        let clock = DisplayLinkClock()
        clock.setWantsFrames(true)
        XCTAssertEqual(clock.debugIsLinkPaused, false)
        clock.setWantsFrames(false)
        XCTAssertEqual(clock.debugIsLinkPaused, true, "the link must be paused as soon as nothing wants frames, not left running")
    }

    func testNoLinkIsCreatedUntilFramesAreWanted() {
        let clock = DisplayLinkClock()
        XCTAssertNil(clock.debugIsLinkPaused, "no link should exist before the first setWantsFrames(true)")
    }

    func testSuspendTearsDownTheLinkAndResumeRecreatesItWhenStillWanted() {
        let clock = DisplayLinkClock()
        clock.setWantsFrames(true)
        XCTAssertNotNil(clock.debugIsLinkPaused)

        clock.suspend()
        XCTAssertNil(clock.debugIsLinkPaused, "suspend tears the link down completely, not just pauses it")

        clock.resume()
        XCTAssertEqual(clock.debugIsLinkPaused, false, "resume recreates the link, unpaused, since frames are still wanted")
    }

    func testSuspendedClockRecordsWantsFramesButCreatesNoLinkUntilResume() {
        let clock = DisplayLinkClock()
        clock.suspend()
        clock.setWantsFrames(true)
        XCTAssertNil(clock.debugIsLinkPaused, "suspended: the flag is recorded, no link is touched")
        clock.resume()
        XCTAssertEqual(clock.debugIsLinkPaused, false, "resume applies the flag that arrived while suspended")
    }

    func testResumeWithNoFramesWantedCreatesNoLink() {
        let clock = DisplayLinkClock()
        clock.suspend()
        clock.resume()
        XCTAssertNil(clock.debugIsLinkPaused)
    }

    // MARK: - Frame rate hint

    func testALowSpriteFpsHintNeverProducesAnInvalidFrameRateRange() {
        // CAFrameRateRange requires minimum <= preferred <= maximum and
        // throws otherwise. Every sheet fps here (12/18/24) is below the
        // motion floor of 30, so a naive "minimum always 30" crashes here.
        let clock = DisplayLinkClock()
        clock.frameRateHint = .sprite(fps: 12)
        clock.setWantsFrames(true)
        XCTAssertEqual(clock.debugIsLinkPaused, false, "must not throw applying a 12fps sprite hint")
        clock.setWantsFrames(false)
    }

    // MARK: - Ownership (the fault this whole design exists to avoid)

    func testTheProxyHoldsItsOwnerWeaklyNotStrongly() {
        weak var weakClock: DisplayLinkClock?
        autoreleasepool {
            let clock = DisplayLinkClock()
            weakClock = clock
            // Starts the link (and hands the proxy to CADisplayLink, which
            // retains the proxy strongly - never `clock` itself).
            clock.setWantsFrames(true)
            XCTAssertNotNil(weakClock)
        }
        // Mutation: the proxy holding `owner` strongly (or the link's
        // target being `self` directly) would keep this alive forever, even
        // though nothing outside this scope now references it.
        XCTAssertNil(weakClock, "DisplayLinkClock must deallocate even while its CADisplayLink is still live on the run loop")
    }

    func testPlayerEngineAndDisplayLinkClockAllDeallocateTogether() {
        weak var weakPlayer: SpritePlayer?
        weak var weakEngine: MotionEngine?
        weak var weakClock: DisplayLinkClock?
        autoreleasepool {
            let clock = DisplayLinkClock()
            let player = SpritePlayer(profile: makeRealClockTestProfile(), clock: clock)
            weakPlayer = player
            weakEngine = player.debugEngine
            weakClock = clock
            player.commit(SpriteCommit(pose: .run))
        }
        XCTAssertNil(weakPlayer, "sanity: nothing outside this scope holds the player")
        XCTAssertNil(weakEngine, "the engine must not be kept alive by the display link's frame handler closure")
        XCTAssertNil(weakClock, "the clock must not be kept alive by the engine it drives")
    }

    // MARK: - `now` on one continuous line (real clock, no ManualClock)

    func testNowIsFreshOutsideATickEvenBeforeAnyTickEverFires() {
        let clock = DisplayLinkClock()
        let first = clock.now
        let waited = expectation(description: "a short real wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { waited.fulfill() }
        wait(for: [waited], timeout: 1.0)
        XCTAssertGreaterThan(clock.now, first, "now must track live time on its own, with no tick and no setWantsFrames ever having run")
    }

    func testNowDoesNotAdvanceWhileSuspendedAndDoesNotJumpOnResume() {
        let clock = DisplayLinkClock()
        clock.suspend()
        let frozen = clock.now

        let waited = expectation(description: "real time passes while suspended")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { waited.fulfill() }
        wait(for: [waited], timeout: 1.0)
        XCTAssertEqual(clock.now, frozen, accuracy: 0.001, "now must not move while suspended, however long real time passes")

        clock.resume()
        XCTAssertEqual(clock.now, frozen, accuracy: 5, "resume must not jump now forward by the length of the suspended stretch")
    }

    /// A fade started after the display link sat paused (nothing animating,
    /// not suspended) for a real stretch of time must run from a fresh
    /// reading, not force-complete against a clock that never ticked.
    func testAFadeStartedAfterAPausedStretchUsesFreshTimeNotAStaleReading() {
        let clock = DisplayLinkClock()
        let player = SpritePlayer(profile: makeRealClockTestProfile(), clock: clock, initialReduceMotion: true)
        XCTAssertNil(clock.debugIsLinkPaused, "sanity: the mount greeting was suppressed, nothing has ever animated")

        let rested = expectation(description: "a real stretch before the first commit")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { rested.fulfill() }
        wait(for: [rested], timeout: 1.0)

        player.commit(SpriteCommit(pose: .run))
        let firstTick = expectation(description: "the fade's first real tick")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { firstTick.fulfill() }
        wait(for: [firstTick], timeout: 1.0)
        XCTAssertLessThan(player.currentState.idle.opacity, 1, "still fading, not force-completed by a stale start time")

        let fadeDone = expectation(description: "past the 110ms fade")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { fadeDone.fulfill() }
        wait(for: [fadeDone], timeout: 1.0)
        XCTAssertEqual(player.currentState.idle.opacity, 0, "the fade completes normally once real time actually passes")
    }

    func testTheMountGreetingPlaysOnlyAfterTheClockIsResumed() {
        let clock = DisplayLinkClock()
        clock.suspend() // mirrors a view built before it has a window
        let player = SpritePlayer(profile: makeRealClockTestProfile(), clock: clock)

        let whileSuspended = expectation(description: "real time passes before the view enters a window")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { whileSuspended.fulfill() }
        wait(for: [whileSuspended], timeout: 1.0)
        XCTAssertEqual(player.currentState.idle.frame, 0, "the greeting's delay has not started counting yet")

        clock.resume() // mirrors didMoveToWindow acquiring a window
        let afterResume = expectation(description: "past the 600ms delay, into the greeting itself")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { afterResume.fulfill() }
        wait(for: [afterResume], timeout: 2.0)
        XCTAssertGreaterThan(player.currentState.idle.frame, 0, "the mount greeting is playing now that the clock actually runs")
    }

    // MARK: - Seeded background suspension at init

    func testAClockCreatedWhileAlreadyBackgroundedStartsSuspended() {
        let clock = DisplayLinkClock(startsBackgroundSuspended: true)
        let frozen = clock.now

        let waited = expectation(description: "real time passes right after construction")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { waited.fulfill() }
        wait(for: [waited], timeout: 1.0)
        XCTAssertEqual(clock.now, frozen, accuracy: 0.001, "seeded-backgrounded must start frozen, not free-running")
    }

    // MARK: - Background/foreground notifications, real clock

    func testBackgroundNotificationFreezesNowAndForegroundResumesWithoutAJump() {
        let clock = DisplayLinkClock()
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        let frozen = clock.now

        let waited = expectation(description: "real time passes while backgrounded")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { waited.fulfill() }
        wait(for: [waited], timeout: 1.0)
        XCTAssertEqual(clock.now, frozen, accuracy: 0.001, "now must not move while backgrounded, however long real time passes")

        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        XCTAssertEqual(clock.now, frozen, accuracy: 5, "foreground must not jump now forward by the backgrounded stretch")
    }

    func testWindowAndBackgroundReasonsOverlappingEndInEitherOrder() {
        // Window suspends first, background second; window resumes first
        // (background still holds), foreground clears the rest.
        autoreleasepool {
            let clock = DisplayLinkClock()
            clock.suspend()
            NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
            let frozen = clock.now
            clock.resume()
            XCTAssertEqual(clock.now, frozen, accuracy: 0.001, "the background reason alone must keep it frozen")
            NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
            XCTAssertEqual(clock.now, frozen, accuracy: 5, "both reasons cleared: resumes without a jump")
        }

        // Background first, window second; foreground first (window still
        // holds), window resume clears the rest.
        autoreleasepool {
            let clock = DisplayLinkClock()
            NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
            clock.suspend()
            let frozen = clock.now
            NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
            XCTAssertEqual(clock.now, frozen, accuracy: 0.001, "the window reason alone must keep it frozen")
            clock.resume()
            XCTAssertEqual(clock.now, frozen, accuracy: 5, "both reasons cleared: resumes without a jump")
        }
    }

    // MARK: - `now` never steps backwards

    func testNowIsMonotonicAcrossASuspensionThatBeginsRightAfterATick() {
        let clock = DisplayLinkClock()
        var lastTickNow: Double?
        let sawTick = expectation(description: "at least one tick")
        clock.frameHandler = { now in
            if lastTickNow == nil {
                lastTickNow = now
                sawTick.fulfill()
            }
        }
        clock.setWantsFrames(true)
        wait(for: [sawTick], timeout: 2.0)
        guard let insideTick = lastTickNow else {
            return XCTFail("never ticked")
        }
        clock.suspend()
        XCTAssertGreaterThanOrEqual(clock.now, insideTick, "a suspension right after a tick must not freeze now behind that tick's own value")
    }

    // MARK: - Frame rate hint above the ceiling

    func testAHighSpriteFpsHintAboveOneHundredTwentyIsClampedAndNeverThrows() {
        // Mirrors testALowSpriteFpsHintNeverProducesAnInvalidFrameRateRange:
        // an unclamped 240 would set preferred above CAFrameRateRange's own
        // maximum (120), which throws (NSInvalidArgumentException) right here.
        let clock = DisplayLinkClock()
        clock.frameRateHint = .sprite(fps: 240)
        clock.setWantsFrames(true)
        XCTAssertEqual(clock.debugIsLinkPaused, false, "must not throw applying a 240fps sprite hint")
        clock.setWantsFrames(false)
    }
}
#endif
