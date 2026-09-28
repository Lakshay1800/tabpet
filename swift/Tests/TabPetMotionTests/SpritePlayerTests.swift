import TabPetCore
import XCTest

@testable import TabPetMotion

/// Records every `didRender` call, in order - a recording renderer, used
/// instead of a real UIKit view.
@MainActor
private final class RecordingRenderer: SpriteRenderer {
    private(set) var states: [SpriteRenderState] = []

    func spritePlayer(_ player: SpritePlayer, didRender state: SpriteRenderState) {
        states.append(state)
    }

    var last: SpriteRenderState? { states.last }
}

@MainActor
private func makeProfile(runFps: Double = 12, scale: Double = 1, sitSheet: SheetGeometry? = nil) -> CompanionProfile {
    CompanionProfile(
        id: "testAnimal",
        label: "test animal",
        runFps: runFps,
        commitSpring: SpringConfig(duration: 500, dampingRatio: 1),
        trackSpring: SpringConfig(duration: 500, dampingRatio: 1),
        catchSpring: SpringConfig(duration: 500, dampingRatio: 1),
        hopHeight: 0,
        flightLift: 0,
        scale: scale,
        aroundRoute: false,
        sitSheet: sitSheet
    )
}

@MainActor
final class SpritePlayerTests: XCTestCase {
    // MARK: - Frame index formula (round, not floor)

    /// `clamp(round(progress * (frames - 1)))` - a `floor` port would give
    /// 5 here, not 6. `frameIndex` is a pure static helper so this needs no
    /// engine at all.
    func testFrameIndexRoundsRatherThanFloors() {
        XCTAssertEqual(SpritePlayer.frameIndex(rawValue: 5.6, frameCount: 25), 6, "round(5.6) = 6, floor(5.6) = 5")
        XCTAssertEqual(SpritePlayer.frameIndex(rawValue: 5.4, frameCount: 25), 5)
    }

    func testFrameIndexClampsIntoTheValidRange() {
        XCTAssertEqual(SpritePlayer.frameIndex(rawValue: -3, frameCount: 11), 0)
        XCTAssertEqual(SpritePlayer.frameIndex(rawValue: 999, frameCount: 11), 10)
        XCTAssertEqual(SpritePlayer.frameIndex(rawValue: .nan, frameCount: 11), 0, "a non-finite raw value is refused to frame 0, never propagated")
    }

    // MARK: - Mount greeting

    /// TS: `useEffect(() => playGreeting(600), [])` - fires from
    /// construction alone, with no `commit(_:)` call at all.
    func testMountGreetingPlaysAfterTheMountDelayWithNoCommitAtAll() {
        let clock = ManualClock()
        let player = SpritePlayer(profile: makeProfile(), clock: clock)

        clock.advance(ms: SpritePlayer.mountGreetingDelayMs - 1, frameMs: 1)
        XCTAssertEqual(player.currentState.idle.frame, 0, "still waiting out the delay")

        // idle: 25 frames @ 12fps = 2083.33ms; halfway through the delay's
        // aftermath the frame should have advanced well past 0.
        clock.advance(ms: 1 + 1200, frameMs: 1)
        XCTAssertGreaterThan(player.currentState.idle.frame, 0)

        clock.advance(ms: 2000, frameMs: 1)
        XCTAssertEqual(player.currentState.idle.frame, 24, "the greeting plays to the sheet's last frame and stops")
        XCTAssertFalse(clock.wantsFrames, "nothing left to animate once the greeting finishes")
    }

    func testMountGreetingDoesNotPlayUnderReduceMotion() {
        let clock = ManualClock()
        let player = SpritePlayer(profile: makeProfile(), clock: clock, initialReduceMotion: true)

        clock.advance(ms: 5000, frameMs: 50)

        XCTAssertEqual(player.currentState.idle.frame, 0)
        XCTAssertFalse(clock.wantsFrames)
    }

    // MARK: - The pose before the first commit counts as idle

    func testFirstCommitIntoSitDissolvesFromTheHardcodedIdleSource() {
        let clock = ManualClock()
        let player = SpritePlayer(profile: makeProfile(), clock: clock)
        clock.advance(ms: SpritePlayer.mountGreetingDelayMs, frameMs: 1) // clear of the mount greeting's own delay window

        player.commit(SpriteCommit(pose: .sit))

        let state = player.currentState
        XCTAssertEqual(state.sit.opacity, 1, "sit is immediately opaque")
        XCTAssertEqual(state.sit.z, 1)
        XCTAssertGreaterThan(state.idle.opacity, 0, "idle - the hardcoded previous pose - is fading out, not hidden")
        XCTAssertEqual(state.idle.z, 2)
    }

    // MARK: - A real transition's opacity/z wiring

    func testARealTransitionAssignsOpaqueFadeOutAndHiddenCorrectly() {
        let clock = ManualClock()
        let player = SpritePlayer(profile: makeProfile(), clock: clock)

        player.commit(SpriteCommit(pose: .run))
        let state = player.currentState

        XCTAssertEqual(state.run.opacity, 1)
        XCTAssertEqual(state.run.z, 1)
        XCTAssertEqual(state.sit.opacity, 0, "uninvolved layer hides immediately")
        XCTAssertEqual(state.sit.z, 0)
        XCTAssertGreaterThan(state.idle.opacity, 0, "idle - the previous pose - fades out")
        XCTAssertEqual(state.idle.z, 2)

        clock.advance(ms: 200, frameMs: 1) // past the 110ms fade
        XCTAssertEqual(player.currentState.idle.opacity, 0, "the fade finished")
    }

    // MARK: - Same-pose commit leaves frames alone

    /// The first `commit(_:)` call is the one place the dissolve's own
    /// "previous == next" branch runs with idle's frame already mid-flight
    /// (the mount greeting); deleting that early return would stomp it.
    func testFirstCommitWithPoseIdleLeavesAnInFlightMountGreetingUndisturbed() {
        let clock = ManualClock()
        let player = SpritePlayer(profile: makeProfile(), clock: clock)
        clock.advance(ms: SpritePlayer.mountGreetingDelayMs + 400, frameMs: 1)
        let midGreeting = player.currentState.idle.frame
        XCTAssertGreaterThan(midGreeting, 0, "sanity: the greeting is mid-flight")

        player.commit(SpriteCommit(pose: .idle))

        XCTAssertEqual(player.currentState.idle.frame, midGreeting, "the first commit's own same-pose (idle -> idle) branch must not stomp the in-flight greeting")
        XCTAssertTrue(clock.wantsFrames, "the greeting keeps animating")
    }

    func testASamePoseCommitLeavesAnInFlightRunLoopUndisturbed() {
        let clock = ManualClock()
        let player = SpritePlayer(profile: makeProfile(), clock: clock)

        player.commit(SpriteCommit(pose: .run))
        clock.advance(ms: 300, frameMs: 1)
        let before = player.currentState.run.frame
        XCTAssertGreaterThan(before, 0, "sanity: the run loop is actually progressing")

        // an exact repeat of the same commit
        player.commit(SpriteCommit(pose: .run))

        XCTAssertEqual(player.currentState.run.frame, before, "a same-pose re-commit must not reset or restart the run loop")
        XCTAssertTrue(clock.wantsFrames, "the run loop is still active")

        clock.advance(ms: 50, frameMs: 1)
        XCTAssertGreaterThanOrEqual(player.currentState.run.frame, before, "still progressing normally, not restarted from 0")
    }

    // MARK: - Busy loop: applied after the pose pass, not before

    /// A commit that turns busy on and moves pose to idle in one call. If
    /// the busy loop ran before the pose pass, the pose pass's own reset
    /// would run afterward and stomp it, freezing idle at frame 0.
    func testBusyLoopIsAppliedAfterThePosePassWithinOneCommit() {
        let clock = ManualClock()
        let player = SpritePlayer(profile: makeProfile(), clock: clock)

        player.commit(SpriteCommit(pose: .run))
        player.commit(SpriteCommit(pose: .idle, busy: true))

        XCTAssertTrue(clock.wantsFrames, "the busy loop just started")
        // idle busy loop: 25 frames @ 12fps * 1.6 slowdown = 3333ms; at
        // 500ms progress ~0.15 -> frame ~4. A stomped loop would read 0
        // instead.
        clock.advance(ms: 500, frameMs: 1)
        XCTAssertGreaterThan(player.currentState.idle.frame, 0, "the busy loop survived the same commit's pose pass")
    }

    func testBusyLoopSurvivesASamePoseCommit() {
        let clock = ManualClock()
        let player = SpritePlayer(profile: makeProfile(), clock: clock)

        // forced (first commit): idle & busy together
        player.commit(SpriteCommit(pose: .idle, busy: true))
        clock.advance(ms: 500, frameMs: 1)
        let before = player.currentState.idle.frame
        XCTAssertGreaterThan(before, 0)

        player.commit(SpriteCommit(pose: .idle, busy: true)) // identical re-commit

        XCTAssertEqual(player.currentState.idle.frame, before, "the busy loop is untouched by an identical re-commit")
        XCTAssertTrue(clock.wantsFrames)
    }

    func testBusyLoopStopsAndSnapsToRestWhenPoseLeavesIdle() {
        let clock = ManualClock()
        let player = SpritePlayer(profile: makeProfile(), clock: clock)
        player.commit(SpriteCommit(pose: .idle, busy: true))
        clock.advance(ms: 500, frameMs: 1)

        player.commit(SpriteCommit(pose: .sit, busy: true))

        // idle is no longer the current pose - shouldSnapBusyIdleFrameToRest
        // is false for .sit, so idle just holds wherever the loop's cleanup
        // cancel left it; it must not still be running.
        let idleFrameAfter = player.currentState.idle.frame
        clock.advance(ms: 50, frameMs: 1)
        XCTAssertEqual(player.currentState.idle.frame, idleFrameAfter, "idle's frame no longer moves once busy's loop was torn down")
    }

    func testBusyLoopNeverStartsUnderReduceMotion() {
        let clock = ManualClock()
        let player = SpritePlayer(profile: makeProfile(), clock: clock)

        player.commit(SpriteCommit(pose: .idle, busy: true, reduceMotion: true))

        XCTAssertFalse(clock.wantsFrames, "reduce motion: no busy loop")
        XCTAssertEqual(player.currentState.idle.frame, 0)
    }

    // MARK: - Idle resets on a hidden layer, and only on a finished fade

    func testIdleFrameHoldsThroughAnUnfinishedFadeAndResetsOnlyOnceItFinishes() {
        let clock = ManualClock()
        let player = SpritePlayer(profile: makeProfile(), clock: clock)

        // get idle animating away from frame 0 first (the busy loop), then
        // transition away from idle so idle becomes the fading-out layer.
        player.commit(SpriteCommit(pose: .idle, busy: true))
        clock.advance(ms: 500, frameMs: 1)
        let idleFrameAtHandoff = player.currentState.idle.frame
        XCTAssertGreaterThan(idleFrameAtHandoff, 0, "sanity")

        player.commit(SpriteCommit(pose: .run, busy: false))

        // immediately after the transition - the fade (110ms) has not
        // finished yet - idle's frame must be untouched.
        XCTAssertEqual(player.currentState.idle.frame, idleFrameAtHandoff, "idle holds its frame through an unfinished fade")

        clock.advance(ms: 50, frameMs: 1) // still short of 110ms
        XCTAssertEqual(player.currentState.idle.frame, idleFrameAtHandoff, "still unfinished - still untouched")

        clock.advance(ms: 100, frameMs: 1) // now past 110ms total
        XCTAssertEqual(player.currentState.idle.frame, 0, "the fade finished - idle resets for the next seam")
    }

    func testIdleFrameResetsImmediatelyWhenHidden() {
        let clock = ManualClock()
        let player = SpritePlayer(profile: makeProfile(), clock: clock)
        player.commit(SpriteCommit(pose: .idle, busy: true))
        clock.advance(ms: 500, frameMs: 1)
        XCTAssertGreaterThan(player.currentState.idle.frame, 0, "sanity")

        // run -> sit: idle is the uninvolved third layer, hidden at once
        // (not faded), so its frame resets synchronously, not after 110ms.
        player.commit(SpriteCommit(pose: .run, busy: false))
        player.commit(SpriteCommit(pose: .sit, busy: false))

        XCTAssertEqual(player.currentState.idle.frame, 0, "hidden resets at once")
        XCTAssertEqual(player.currentState.idle.opacity, 0)
    }

    // MARK: - Per-layer facing: only the current pose's layer takes a new facing

    func testOnlyTheCurrentPoseLayerTakesANewFacing() {
        let clock = ManualClock()
        let player = SpritePlayer(profile: makeProfile(), clock: clock, initialFacing: .right)

        player.commit(SpriteCommit(pose: .run, facing: .right))
        // idle is now the outgoing (fading) layer.
        player.commit(SpriteCommit(pose: .run, facing: .left))

        let state = player.currentState
        XCTAssertEqual(state.run.facing, .left, "the current pose's layer takes the new facing")
        XCTAssertEqual(state.idle.facing, .right, "the outgoing layer keeps its own facing through the fade")
    }

    // MARK: - Press scale

    func testPressBeginAnimatesTowardThePressScaleAndPressEndReturns() {
        let clock = ManualClock()
        let player = SpritePlayer(profile: makeProfile(), clock: clock)
        player.commit(SpriteCommit())

        player.pressBegin()
        clock.advance(ms: SpritePlayer.pressInMs, frameMs: 1)
        XCTAssertEqual(player.currentState.pressScale, SpritePlayer.pressScaleFactor, accuracy: 1e-6)

        player.pressEnd()
        clock.advance(ms: SpritePlayer.pressOutMs, frameMs: 1)
        XCTAssertEqual(player.currentState.pressScale, 1.0, accuracy: 1e-6)
    }

    func testPressScaleIsAlwaysOneUnderReduceMotion() {
        let clock = ManualClock()
        let player = SpritePlayer(profile: makeProfile(), clock: clock)
        player.commit(SpriteCommit(reduceMotion: true))

        player.pressBegin()
        clock.advance(ms: 60, frameMs: 1)

        XCTAssertEqual(player.currentState.pressScale, 1.0, "reduce motion: hard cut, no press-scale animation")
    }

    // MARK: - Tap / greeting gating

    func testTapPlaysAGreetingOnlyWhileIdleAndNotBusy() {
        let clock = ManualClock()
        let player = SpritePlayer(profile: makeProfile(), clock: clock)
        player.commit(SpriteCommit(pose: .idle, busy: false))
        clock.advance(ms: SpritePlayer.mountGreetingDelayMs + 2200, frameMs: 1) // clear of the mount greeting entirely

        XCTAssertTrue(player.tap())
        clock.advance(ms: 1200, frameMs: 1)
        XCTAssertGreaterThan(player.currentState.idle.frame, 0, "the tap greeting is actually playing")
    }

    /// A tap must never restart the greeting while busy owns the idle loop.
    func testTapDoesNotGreetWhileBusy() {
        let clock = ManualClock()
        let player = SpritePlayer(profile: makeProfile(), clock: clock)
        player.commit(SpriteCommit(pose: .idle, busy: true))
        clock.advance(ms: 500, frameMs: 1)
        let frameBeforeTap = player.currentState.idle.frame

        XCTAssertFalse(player.tap(), "busy: no greeting")
        // a greeting call does `cancel` + `set(0)` synchronously, even
        // before any further tick - so this is observable immediately.
        XCTAssertEqual(player.currentState.idle.frame, frameBeforeTap, "tap() must not touch the busy loop at all")
    }

    func testTapDoesNotGreetWhileNotIdle() {
        let clock = ManualClock()
        let player = SpritePlayer(profile: makeProfile(), clock: clock)
        player.commit(SpriteCommit(pose: .run))

        XCTAssertFalse(player.tap())
    }

    // MARK: - Sit: plays once, fires onSitDone once, never twice

    func testSitPlaysOnceAndFiresOnSitDoneExactlyOnce() {
        let clock = ManualClock()
        let player = SpritePlayer(profile: makeProfile(), clock: clock)
        var sitDoneCount = 0
        player.onSitDone = { sitDoneCount += 1 }

        player.commit(SpriteCommit(pose: .sit))
        // sit: 25 frames @ 12fps = 2083.33ms.
        clock.advance(ms: 2200, frameMs: 1)

        XCTAssertEqual(sitDoneCount, 1)
        XCTAssertEqual(player.currentState.sit.frame, 24, "holds the last frame, does not wrap")

        // a later transition away from sit cancels its track - MotionTrack
        // never clears a naturally-finished animation's completion, so this
        // refires it, with false. onSitDone must not fire again.
        player.commit(SpriteCommit(pose: .idle))
        XCTAssertEqual(sitDoneCount, 1, "the cancel-driven refire is `false` and must not call onSitDone again")
    }

    // MARK: - The engine stops requesting frames once everything settles

    func testEngineStopsRequestingFramesTheSameTickTheLastAnimationEnds() {
        let clock = ManualClock()
        let player = SpritePlayer(profile: makeProfile(), clock: clock)
        player.commit(SpriteCommit(pose: .sit))

        // 110ms fade + 2083.33ms sit settle, comfortably covered.
        clock.advance(ms: 2300, frameMs: 1)

        XCTAssertFalse(clock.wantsFrames, "nothing left to animate")
    }

    /// The outgoing layer's own frame animation (run's still-looping cycle)
    /// must be cancelled by the transition that leaves it behind, not left
    /// to keep the engine awake after everything else has settled.
    func testTheOutgoingLayersFrameAnimationIsCancelledSoItCannotOutliveTheTransition() {
        let clock = ManualClock()
        let player = SpritePlayer(profile: makeProfile(), clock: clock)
        player.commit(SpriteCommit(pose: .run))
        clock.advance(ms: 200, frameMs: 1)

        player.commit(SpriteCommit(pose: .sit))
        clock.advance(ms: 2300, frameMs: 1) // fade + sit settle, comfortably covered

        XCTAssertFalse(clock.wantsFrames, "run's loop must not outlive the transition away from run")
    }

    // MARK: - Reduce Motion: hard cuts, rest cells, no busy loop, no greeting

    func testReduceMotionIsAHardCutToRestCellsWithNothingLeftActive() {
        let clock = ManualClock()
        let player = SpritePlayer(profile: makeProfile(), clock: clock)
        player.commit(SpriteCommit(pose: .run)) // establish a normal run first
        clock.advance(ms: 100, frameMs: 1)

        player.commit(SpriteCommit(pose: .sit, busy: true, reduceMotion: true))

        let state = player.currentState
        XCTAssertEqual(state.sit.opacity, 1)
        XCTAssertEqual(state.run.opacity, 0)
        XCTAssertEqual(state.idle.opacity, 0)
        XCTAssertEqual(state.sit.frame, 24, "sit's rest cell is its last frame")
        XCTAssertFalse(clock.wantsFrames, "a hard cut leaves nothing animating, even with busy true")

        clock.advance(ms: 500, frameMs: 1)
        XCTAssertEqual(player.currentState.sit.frame, 24, "still resting - reduce motion never starts the busy loop")
    }

    // MARK: - Non-finite profile numbers are refused at the boundary

    func testNonFiniteRunFpsIsRefusedAtTheBoundaryAndNeverReachesTheEngine() {
        let clock = ManualClock()
        var reported: [(MotionError, String)] = []
        let profile = makeProfile(runFps: .nan)
        let player = SpritePlayer(profile: profile, clock: clock) { error, label in
            reported.append((error, label))
        }

        XCTAssertTrue(reported.contains { $0.1 == "profile.runFps" }, "the refusal is reported at construction, before any commit")

        player.commit(SpriteCommit(pose: .run))
        clock.advance(ms: 500, frameMs: 1)
        // a sane fallback fps was used instead - frame stays a valid,
        // in-range index, never NaN-derived garbage.
        XCTAssertGreaterThanOrEqual(player.currentState.run.frame, 0)
        XCTAssertLessThanOrEqual(player.currentState.run.frame, 10)
    }

    func testNonFiniteScaleIsRefusedAndFallsBackToReferenceSize() {
        let clock = ManualClock()
        var reported: [(MotionError, String)] = []
        let profile = makeProfile(scale: .infinity)
        let player = SpritePlayer(profile: profile, clock: clock) { error, label in
            reported.append((error, label))
        }

        XCTAssertTrue(reported.contains { $0.1 == "profile.scale" })
        XCTAssertEqual(player.currentState.idle.scale, 1, "falls back to reference size, never Infinity")
    }

    // MARK: - Renderer contract

    func testRendererReceivesACommitAndSubsequentTicks() {
        let clock = ManualClock()
        let player = SpritePlayer(profile: makeProfile(), clock: clock)
        let renderer = RecordingRenderer()
        player.renderer = renderer

        player.commit(SpriteCommit(pose: .run))
        XCTAssertFalse(renderer.states.isEmpty, "the commit itself pushes a render")
        let afterCommit = renderer.states.count

        clock.advance(ms: 100, frameMs: 10)
        XCTAssertGreaterThan(renderer.states.count, afterCommit, "each active tick pushes another render")
        XCTAssertEqual(renderer.last?.run.opacity, 1)
    }

    // MARK: - Retain cycle: the clock's frame handler must not keep the engine alive

    func testPlayerEngineAndClockAllDeallocateTogether() {
        weak var weakPlayer: SpritePlayer?
        weak var weakEngine: MotionEngine?
        weak var weakClock: ManualClock?
        autoreleasepool {
            let clock = ManualClock()
            let player = SpritePlayer(profile: makeProfile(), clock: clock)
            weakPlayer = player
            weakEngine = player.debugEngine
            weakClock = clock
            player.commit(SpriteCommit(pose: .run))
            clock.advance(ms: 50, frameMs: 1)
        }
        XCTAssertNil(weakPlayer, "sanity: nothing outside this scope holds the player")
        XCTAssertNil(weakEngine, "the engine must not be kept alive by the clock's frame handler closure")
        XCTAssertNil(weakClock, "the clock must not be kept alive by the engine it drives")
    }

    /// The clock itself is kept alive here (unlike the test above), so a
    /// frame arriving after the player and engine are already gone must
    /// tell it to stop asking for more, rather than ticking forever.
    func testFrameHandlerTurnsWantsFramesOffWhenThePlayerAndEngineAreGone() {
        let clock = ManualClock()
        autoreleasepool {
            let player = SpritePlayer(profile: makeProfile(), clock: clock)
            player.commit(SpriteCommit(pose: .run))
        }
        XCTAssertTrue(clock.wantsFrames, "sanity: the run loop left the clock wanting frames")
        clock.frameHandler?(clock.now + 1)
        XCTAssertFalse(clock.wantsFrames, "a frame arriving with the player and engine gone must turn wantsFrames off")
    }

    // MARK: - onSitDone is delivered after commit returns, never re-entrantly

    /// A sit with a single frame completes synchronously inside `commit`.
    /// A host `onSitDone` that itself calls `commit` must not corrupt the
    /// still-running outer call.
    func testOnSitDoneFromAOneFrameSitIsDeferredPastTheCommitThatTriggeredIt() {
        let clock = ManualClock()
        let oneFrameSit = SheetGeometry(cols: 1, rows: 1, frames: 1, fps: 12)
        let player = SpritePlayer(profile: makeProfile(sitSheet: oneFrameSit), clock: clock)
        var calledAtAll = false
        player.onSitDone = {
            calledAtAll = true
            player.commit(SpriteCommit(pose: .idle))
        }

        player.commit(SpriteCommit(pose: .sit))
        XCTAssertFalse(calledAtAll, "onSitDone must not fire before the triggering commit call has even returned")

        clock.advance(ms: 1, frameMs: 1)
        XCTAssertTrue(calledAtAll, "still delivered, just on a later turn")
    }

    // MARK: - Frame index at sampled times, against a formula computed independently

    func testRunFrameIndexAtSampledTimesMatchesTheElapsedTimeFormula() {
        let clock = ManualClock()
        let runFps = 10.0
        let player = SpritePlayer(profile: makeProfile(runFps: runFps), clock: clock)
        player.commit(SpriteCommit(pose: .run))

        let frames = CompanionProfile.RUN_SHEET_GRID.frames
        let durationMs = Double(frames) / runFps * 1000
        var elapsed = 0.0
        for step in [80.0, 240.0, 500.0] {
            clock.advance(ms: step, frameMs: 1)
            elapsed += step
            let progress = Swift.min(1, elapsed / durationMs)
            let raw = (progress * Double(frames - 1)).rounded()
            let expected = Int(Swift.min(Double(frames - 1), Swift.max(0, raw)))
            XCTAssertEqual(player.currentState.run.frame, expected, "at \(elapsed)ms elapsed")
        }
    }

    // MARK: - The run loop wraps back to frame 0

    func testRunLoopWrapsBackToFrameZeroAfterOneFullCycle() {
        let clock = ManualClock()
        let runFps = 20.0
        let player = SpritePlayer(profile: makeProfile(runFps: runFps), clock: clock)
        player.commit(SpriteCommit(pose: .run))

        let frames = CompanionProfile.RUN_SHEET_GRID.frames
        let durationMs = Double(frames) / runFps * 1000

        clock.advance(ms: durationMs - 10, frameMs: 1)
        XCTAssertEqual(player.currentState.run.frame, frames - 1, "reaches the sheet's last frame at the end of one cycle")

        clock.advance(ms: 30, frameMs: 1) // past the cycle boundary, into a fresh repetition
        XCTAssertLessThanOrEqual(player.currentState.run.frame, 1, "wraps back near frame 0 rather than staying pinned at the last frame")
    }

    // MARK: - runFps is read from the profile, not a fixed constant

    func testRunFrameDurationScalesWithTheProfilesRunFps() {
        let elapsedMs = 200.0

        let slowClock = ManualClock()
        let slowPlayer = SpritePlayer(profile: makeProfile(runFps: 5), clock: slowClock)
        slowPlayer.commit(SpriteCommit(pose: .run))
        slowClock.advance(ms: elapsedMs, frameMs: 1)

        let fastClock = ManualClock()
        let fastPlayer = SpritePlayer(profile: makeProfile(runFps: 40), clock: fastClock)
        fastPlayer.commit(SpriteCommit(pose: .run))
        fastClock.advance(ms: elapsedMs, frameMs: 1)

        XCTAssertLessThan(
            slowPlayer.currentState.run.frame,
            fastPlayer.currentState.run.frame,
            "a lower profile.runFps must take longer to reach the same frame - proves the duration is read from the profile, not a fixed constant"
        )
    }

    // MARK: - Write order within one pose change: hidden, then opaque, then fade-out

    /// A transition that exercises all three roles at once (run fading out,
    /// sit coming in opaque, idle hidden) - every write must land correctly
    /// in this one synchronous commit, not only once a later tick runs.
    func testAPoseChangeWithAllThreeRolesEndsWithEachLayerInItsOwnState() {
        let clock = ManualClock()
        let player = SpritePlayer(profile: makeProfile(), clock: clock)
        player.commit(SpriteCommit(pose: .run))
        clock.advance(ms: 50, frameMs: 1)

        player.commit(SpriteCommit(pose: .sit))
        let state = player.currentState

        XCTAssertEqual(state.sit.opacity, 1, "incoming: opaque immediately")
        XCTAssertEqual(state.sit.z, 1)
        XCTAssertEqual(state.idle.opacity, 0, "uninvolved: hidden immediately, not fading")
        XCTAssertEqual(state.idle.z, 0)
        XCTAssertEqual(state.idle.frame, 0, "hidden resets its frame in the same write, not on a later tick")
        XCTAssertGreaterThan(state.run.opacity, 0, "outgoing: still fading out, not yet hidden")
        XCTAssertEqual(state.run.z, 2)
    }

    // MARK: - Shared-engine mode

    /// Two players sharing one engine and clock both advance on one tick -
    /// neither installs its own frame handler, so nothing but the owner's
    /// explicit `engine.tick` + `renderTick()` pair drives either of them.
    func testTwoPlayersOnOneSharedEngineBothAdvanceOnOneTick() {
        let clock = ManualClock()
        let engine = MotionEngine(clock: clock)
        let rendererA = RecordingRenderer()
        let rendererB = RecordingRenderer()
        let playerA = SpritePlayer(profile: makeProfile(), engine: engine, clock: clock)
        let playerB = SpritePlayer(profile: makeProfile(), engine: engine, clock: clock)
        playerA.renderer = rendererA
        playerB.renderer = rendererB
        playerA.commit(SpriteCommit(pose: .run))
        playerB.commit(SpriteCommit(pose: .run))
        let framesBeforeTick = (a: rendererA.states.count, b: rendererB.states.count)

        engine.tick(now: 100)
        playerA.renderTick()
        playerB.renderTick()

        XCTAssertGreaterThan(playerA.currentState.run.frame, 0, "player A advanced")
        XCTAssertGreaterThan(playerB.currentState.run.frame, 0, "player B advanced on the same tick call")
        XCTAssertEqual(playerA.currentState.run.frame, playerB.currentState.run.frame, "identical profiles on one clock stay in lockstep")
        XCTAssertGreaterThan(rendererA.states.count, framesBeforeTick.a)
        XCTAssertGreaterThan(rendererB.states.count, framesBeforeTick.b)
    }

    /// Releasing one shared-engine player (letting it deallocate) must not
    /// touch tracks the other player still owns on the same engine - the
    /// engine's own `tick` stays safe, and the survivor is unaffected.
    func testReleasingOneSharedPlayerDoesNotReleaseAnythingTheOtherStillOwns() {
        let clock = ManualClock()
        let engine = MotionEngine(clock: clock)
        var playerA: SpritePlayer? = SpritePlayer(profile: makeProfile(), engine: engine, clock: clock)
        let playerB = SpritePlayer(profile: makeProfile(), engine: engine, clock: clock)
        weak var weakA: SpritePlayer?
        weakA = playerA
        playerB.commit(SpriteCommit(pose: .run))

        playerA = nil
        XCTAssertNil(weakA, "playerA deallocates on its own - shared mode holds no reference from the engine back to either player beyond what its own tracks need")

        engine.tick(now: 50)
        playerB.renderTick()
        XCTAssertGreaterThan(playerB.currentState.run.frame, 0, "playerB's own tracks are untouched by playerA's deallocation")
    }

    /// The shared-mode initializer installs no frame handler at all - proven
    /// behaviourally, since a closure has no identity to compare: a track
    /// belonging to the engine alone still advances after construction.
    func testSharedModeNeverTouchesClockFrameHandler() {
        let clock = ManualClock()
        let engine = MotionEngine(clock: clock)
        let sentinelTrack = engine.makeTrack(label: "sentinel", initialValue: 0)
        engine.start(sentinelTrack, TimingAnimation(toValue: 100, config: TimingConfig(duration: 100, easing: { Easing.linear($0) })))

        _ = SpritePlayer(profile: makeProfile(), engine: engine, clock: clock)

        clock.advance(ms: 50, frameMs: 1)
        XCTAssertGreaterThan(sentinelTrack.currentValue, 0, "the engine's own frameHandler still runs ticks after a shared-mode player is constructed")
    }

    // MARK: - Teardown (shared-engine mode)

    /// A shared-engine profile swap must not leave the outgoing player's
    /// loop tracks (the busy idle loop here) animating the shared clock -
    /// both isLoop tracks are exempt from the engine's own 10s age guard.
    func testTeardownStopsABusyIdleLoopLeftOnTheSharedEngine() {
        let clock = ManualClock()
        let engine = MotionEngine(clock: clock)
        let playerA = SpritePlayer(profile: makeProfile(), engine: engine, clock: clock)
        playerA.commit(SpriteCommit(pose: .idle, busy: true))

        playerA.teardown()

        let playerB = SpritePlayer(profile: makeProfile(), engine: engine, clock: clock)
        playerB.commit(SpriteCommit(pose: .sit, busy: false))

        clock.advance(ms: 30_000, frameMs: 50)

        XCTAssertFalse(engine.isAnyTrackActive(labelPrefix: "sprite."), "player A's busy idle loop must not still be active")
        XCTAssertFalse(clock.wantsFrames, "nothing left on the shared engine wants a frame")
    }

    /// Same shape, with a held run instead of a busy idle loop - `.run` is
    /// also started with `isLoop: true` (a host can hold it indefinitely),
    /// so it needs the same teardown.
    func testTeardownStopsAHeldRunLoopLeftOnTheSharedEngine() {
        let clock = ManualClock()
        let engine = MotionEngine(clock: clock)
        let playerA = SpritePlayer(profile: makeProfile(), engine: engine, clock: clock)
        playerA.commit(SpriteCommit(pose: .run))

        playerA.teardown()

        let playerB = SpritePlayer(profile: makeProfile(), engine: engine, clock: clock)
        playerB.commit(SpriteCommit(pose: .sit, busy: false))

        clock.advance(ms: 30_000, frameMs: 50)

        XCTAssertFalse(engine.isAnyTrackActive(labelPrefix: "sprite."), "player A's held run loop must not still be active")
        XCTAssertFalse(clock.wantsFrames, "nothing left on the shared engine wants a frame")
    }

    /// Calling `teardown()` twice (or on a player nothing was ever committed
    /// to) must not throw, double-remove, or otherwise misbehave.
    func testTeardownIsIdempotent() {
        let clock = ManualClock()
        let engine = MotionEngine(clock: clock)
        let player = SpritePlayer(profile: makeProfile(), engine: engine, clock: clock)
        player.commit(SpriteCommit(pose: .run))

        player.teardown()
        player.teardown()

        XCTAssertFalse(engine.isAnyTrackActive(labelPrefix: "sprite."))
    }

    // MARK: - Mutation: inert after teardown

    /// A commit into a torn-down player must not update `lastAppliedCommit`
    /// or start a track, even for a pose genuinely different from the last
    /// one applied before teardown.
    func testMutation_CommitAfterTeardownIsANoOp() {
        let clock = ManualClock()
        let engine = MotionEngine(clock: clock)
        let player = SpritePlayer(profile: makeProfile(), engine: engine, clock: clock)
        player.commit(SpriteCommit(pose: .idle))
        let commitBefore = player.lastAppliedCommit

        player.teardown()
        player.commit(SpriteCommit(pose: .run))

        XCTAssertEqual(player.lastAppliedCommit, commitBefore, "a commit after teardown must not update the last applied commit")
        XCTAssertFalse(engine.isAnyTrackActive(labelPrefix: "sprite."), "a commit after teardown must start no new track")
    }

    /// `isAnyTrackActive` alone can't tell inert apart from broken here: the
    /// press track is already removed from the engine either way, so a
    /// non-inert pressBegin only shows up as a `.trackRemoved` report.
    func testMutation_PressBeginAndPressEndAfterTeardownReportNothing() {
        let clock = ManualClock()
        let engine = MotionEngine(clock: clock)
        var errors: [MotionError] = []
        engine.onError = { error, _ in errors.append(error) }
        let player = SpritePlayer(profile: makeProfile(), engine: engine, clock: clock)
        player.commit(SpriteCommit(pose: .idle))
        player.teardown()

        player.pressBegin()
        player.pressEnd()

        XCTAssertTrue(errors.isEmpty, "pressBegin/pressEnd after teardown must report nothing, not a trackRemoved error")
    }
}
