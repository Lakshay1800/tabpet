import XCTest

@testable import TabPetMotion

/// A test-only animation whose behavior is dictated entirely by the closures
/// passed in - used to drive MotionEngine/MotionTrack guard paths that no
/// real SpringAnimation/TimingAnimation scenario reaches on its own (a
/// non-finite value, an animation that never finishes).
@MainActor
private final class ScriptedAnimation: MotionAnimation {
    private(set) var current: Double
    var hasBeenStepped = false
    var cancelled = false
    // Always starts regardless of a value match with the track's current
    // value - these tests want the scripted frame closure to actually run,
    // never MotionTrack's same-value short circuit (which is keyed off a
    // REAL spring/timing's pre-onStart `current == toValue`, not applicable
    // to a scripted double standing in for an arbitrary custom animation).
    let isHigherOrder = true
    private let frame: (Double) -> (value: Double, finished: Bool)

    init(current: Double, frame: @escaping (Double) -> (value: Double, finished: Bool)) {
        self.current = current
        self.frame = frame
    }

    func onStart(value: Double, now: Double, previous: ReplacedAnimation) {
        current = value
    }

    func onFrame(now: Double) -> Bool {
        let result = frame(now)
        current = result.value
        return result.finished
    }
}

@MainActor
final class EngineTests: XCTestCase {
    /// The library never traps a host app - a non-finite or non-positive
    /// `ms`/`frameMs` can't step forward in place, so `advance` does
    /// nothing at all rather than looping forever or crashing.
    func testManualClockAdvanceDoesNothingWhenMsOrFrameMsIsNotFiniteOrNotPositive() {
        let zeroFrame = ManualClock()
        zeroFrame.advance(ms: 100, frameMs: 0)
        XCTAssertEqual(zeroFrame.now, 0, "non-positive frameMs: advance does nothing")

        let negativeFrame = ManualClock()
        negativeFrame.advance(ms: 50, frameMs: -5)
        XCTAssertEqual(negativeFrame.now, 0, "non-positive frameMs: advance does nothing")

        let negativeMs = ManualClock()
        negativeMs.advance(ms: -10, frameMs: 16)
        XCTAssertEqual(negativeMs.now, 0, "non-positive ms: advance does nothing")

        let nanMs = ManualClock()
        nanMs.advance(ms: .nan, frameMs: 16)
        XCTAssertEqual(nanMs.now, 0, "non-finite ms: advance does nothing")
    }

    /// `ms == .infinity` can never reach its target - `advance` returns at
    /// once instead, with the clock's time left exactly where it was.
    func testAdvanceWithInfiniteMsReturnsAtOnceWithTimeUnchanged() {
        let clock = ManualClock()
        clock.advance(ms: .infinity, frameMs: 16)
        XCTAssertEqual(clock.now, 0)
    }

    /// At a large enough absolute time, adding a small positive step no
    /// longer changes a Double at all (floating-point precision loss) -
    /// `advance` must stop rather than loop forever re-adding a step that
    /// never moves `now`. Reaching the assertion below IS the proof.
    func testAdvanceAtAHugeAbsoluteTimeReturnsRatherThanLoopingForever() {
        let clock = ManualClock(now: 1e17)
        clock.advance(ms: 100, frameMs: 1)
        XCTAssertGreaterThanOrEqual(clock.now, 1e17)
    }

    /// Timers due within one step fire in order of due time, not creation
    /// order - a timer scheduled FIRST but due LATER must still fire AFTER
    /// one scheduled second but due sooner, when a single big step covers
    /// both.
    func testTimersDueInTheSameStepFireInOrderOfDueTimeThenCreation() {
        let clock = ManualClock()
        var fired: [String] = []
        _ = clock.after(milliseconds: 30) { fired.append("a") }
        _ = clock.after(milliseconds: 10) { fired.append("b") }

        clock.advance(ms: 50, frameMs: 50)

        XCTAssertEqual(fired, ["b", "a"], "due at 10 fires before due at 30, even though 'a' was scheduled first")
    }

    func testClockUnitsBothWays() {
        XCTAssertEqual(ClockUnits.ms(fromSeconds: 1), 1000)
        XCTAssertEqual(ClockUnits.ms(fromSeconds: 0.016_666), 16.666, accuracy: 1e-9)
        XCTAssertEqual(ClockUnits.seconds(fromMs: 1000), 1)
        XCTAssertEqual(ClockUnits.seconds(fromMs: 16.666), 0.016_666, accuracy: 1e-9)
        // round trip both ways
        XCTAssertEqual(ClockUnits.seconds(fromMs: ClockUnits.ms(fromSeconds: 0.4321)), 0.4321, accuracy: 1e-12)
        XCTAssertEqual(ClockUnits.ms(fromSeconds: ClockUnits.seconds(fromMs: 432.1)), 432.1, accuracy: 1e-9)
    }

    func testManualClockAdvanceFiresTimersInOrderAndNeverSleeps() {
        let clock = ManualClock()
        var fired: [String] = []
        _ = clock.after(milliseconds: 30) { fired.append("a") }
        _ = clock.after(milliseconds: 10) { fired.append("b") }
        _ = clock.after(milliseconds: 10) { fired.append("c") } // same fireAt as b - scheduled after b, fires after b
        let cancelled = clock.after(milliseconds: 5) { fired.append("cancelled") }
        cancelled.cancel()

        clock.advance(ms: 50, frameMs: 5)

        XCTAssertEqual(clock.now, 50, accuracy: 1e-9)
        XCTAssertEqual(fired, ["b", "c", "a"], "timers fire in the order they were scheduled, at whichever step they become due")
    }

    /// The fixed order `advance` documents: every due timer fires before
    /// the frame handler runs on that same step, never the other way round.
    func testManualClockRunsTimersBeforeTheFrameOnTheSameStep() {
        let clock = ManualClock()
        var order: [String] = []
        _ = clock.after(milliseconds: 10) { order.append("timer") }
        clock.frameHandler = { _ in order.append("frame") }
        clock.setWantsFrames(true)

        clock.advance(ms: 10, frameMs: 10)

        XCTAssertEqual(order, ["timer", "frame"])
    }

    func testEngineAsksForFramesOnlyWhileAtLeastOneTrackIsActive() {
        let clock = ManualClock()
        let engine = MotionEngine(clock: clock)
        let track = engine.makeTrack(label: "x")

        XCTAssertFalse(clock.wantsFrames)

        let timing = TimingAnimation(toValue: 100, config: TimingConfig(duration: 50, easing: { Easing.linear($0) }))
        engine.start(track, timing)
        XCTAssertTrue(clock.wantsFrames, "starting the first active track asks the clock for frames")

        // The clock's own frameHandler drives the engine now - tests never
        // call `engine.tick` by hand after an `advance`.
        clock.advance(ms: 16, frameMs: 16)
        XCTAssertTrue(clock.wantsFrames, "still running")

        clock.advance(ms: 50, frameMs: 16)
        XCTAssertFalse(clock.wantsFrames, "the clock is told to stop in the same tick the last active track finishes")
        XCTAssertFalse(track.isActive)
    }

    func testCompletionThatStartsANewTrackInsideATickIsSafe() {
        let clock = ManualClock()
        let engine = MotionEngine(clock: clock)
        let trackA = engine.makeTrack(label: "a")
        let trackB = engine.makeTrack(label: "b")

        var completionRan = false
        let quickTiming = TimingAnimation(toValue: 10, config: TimingConfig(duration: 1, easing: { Easing.linear($0) }))
        engine.start(trackA, quickTiming) { finished in
            completionRan = true
            XCTAssertTrue(finished)
            // starting a new track from inside a completion, mid-tick, must
            // not corrupt the snapshot MotionEngine.tick is iterating.
            let newTiming = TimingAnimation(toValue: 5, config: TimingConfig(duration: 50, easing: { Easing.linear($0) }))
            engine.start(trackB, newTiming)
        }

        clock.advance(ms: 10, frameMs: 10)

        XCTAssertTrue(completionRan)
        XCTAssertTrue(trackB.isActive, "the track started from inside the completion is running")
        // the engine must still want frames - trackB is active, even though
        // trackA (the only track active at the START of this tick) finished.
        XCTAssertTrue(clock.wantsFrames)
    }

    func testCancelCallsCompletionWithFalse() {
        let clock = ManualClock()
        let engine = MotionEngine(clock: clock)
        let track = engine.makeTrack(label: "x")

        var result: Bool?
        let timing = TimingAnimation(toValue: 100, config: TimingConfig(duration: 1000, easing: { Easing.linear($0) }))
        engine.start(track, timing) { finished in result = finished }

        engine.cancel(track)

        XCTAssertEqual(result, false)
        XCTAssertFalse(track.isActive)
        XCTAssertFalse(clock.wantsFrames, "cancelling the only active track stops asking for frames")
    }

    /// A start from inside a cancel completion is safe, and a read of
    /// another track's value inside that same completion just works.
    func testStartFromInsideACancelCompletionCanStartAndReadAnotherTrack() {
        let clock = ManualClock()
        let engine = MotionEngine(clock: clock)
        let trackA = engine.makeTrack(label: "a")
        let trackB = engine.makeTrack(label: "b")

        engine.start(trackB, TimingAnimation(toValue: 50, config: TimingConfig(duration: 100, easing: { Easing.linear($0) })))

        var completionRan = false
        var valueSeenInsideCompletion: Double?
        let timingA = TimingAnimation(toValue: 100, config: TimingConfig(duration: 1000, easing: { Easing.linear($0) }))
        engine.start(trackA, timingA) { finished in
            completionRan = true
            XCTAssertFalse(finished, "cancel fires the completion with false")
            // starting a new animation on trackA from inside its own
            // cancel completion, and reading trackB's value, must both be
            // safe.
            engine.start(trackA, TimingAnimation(toValue: 5, config: TimingConfig(duration: 10, easing: { Easing.linear($0) })))
            valueSeenInsideCompletion = trackB.currentValue
        }

        engine.cancel(trackA)

        XCTAssertTrue(completionRan)
        XCTAssertEqual(valueSeenInsideCompletion ?? .nan, trackB.currentValue, accuracy: 1e-9)
        XCTAssertTrue(trackA.isActive, "the animation started from inside the cancel completion is running")
    }

    func testStartingANewAnimationOnATrackCancelsTheOldOneWithFalse() {
        let clock = ManualClock()
        let engine = MotionEngine(clock: clock)
        let track = engine.makeTrack(label: "x")

        var oldResult: Bool?
        let first = TimingAnimation(toValue: 100, config: TimingConfig(duration: 1000, easing: { Easing.linear($0) }))
        engine.start(track, first) { finished in oldResult = finished }

        let second = TimingAnimation(toValue: 200, config: TimingConfig(duration: 1000, easing: { Easing.linear($0) }))
        engine.start(track, second)

        XCTAssertEqual(oldResult, false, "starting a new animation on a track cancels the old one with false")
    }

    func testNonFiniteGuardCancelsRestoresAndReportsError() {
        let clock = ManualClock()
        let engine = MotionEngine(clock: clock)
        let track = engine.makeTrack(label: "seatY", initialValue: 42)

        var reported: (MotionError, String)?
        engine.onError = { error, label in reported = (error, label) }

        var completionResult: Bool?
        let poison = ScriptedAnimation(current: 42) { _ in (.nan, false) }
        engine.start(track, poison) { finished in completionResult = finished }

        clock.advance(ms: 16, frameMs: 16)

        XCTAssertEqual(completionResult, false)
        XCTAssertFalse(track.isActive)
        XCTAssertEqual(track.currentValue, 42, "restored to its last finite value")
        XCTAssertEqual(reported?.0, .nonFiniteValue)
        XCTAssertEqual(reported?.1, "seatY")
        XCTAssertFalse(clock.wantsFrames)
    }

    /// A non-finite `initialValue` is refused: the track falls back to 0
    /// (not left uninitialized, not NaN), and the refusal is reported.
    func testMakeTrackWithNonFiniteInitialValueFallsBackToZeroAndReports() {
        let clock = ManualClock()
        let engine = MotionEngine(clock: clock)

        var reported: (MotionError, String)?
        engine.onError = { error, label in reported = (error, label) }

        let track = engine.makeTrack(label: "x", initialValue: .nan)

        XCTAssertEqual(track.currentValue, 0)
        XCTAssertEqual(reported?.0, .nonFiniteValue)
        XCTAssertEqual(reported?.1, "x")
    }

    /// `engine.set` refuses a non-finite value the same way: the track's
    /// value is left exactly as it was, and the refusal is reported -
    /// never a poisoned value becoming `currentValue`.
    func testSetWithNonFiniteValueIsRefusedAndKeepsThePriorValue() {
        let clock = ManualClock()
        let engine = MotionEngine(clock: clock)
        let track = engine.makeTrack(label: "x", initialValue: 7)

        var reported: (MotionError, String)?
        engine.onError = { error, label in reported = (error, label) }

        engine.set(track, .nan)

        XCTAssertEqual(track.currentValue, 7)
        XCTAssertEqual(reported?.0, .nonFiniteValue)
        XCTAssertEqual(reported?.1, "x")
    }

    /// `engine.set` cancels whatever animation is running on the track
    /// (completion false) before writing the value - mirrors
    /// valueSetter.ts's plain-value branch, which cancels unconditionally
    /// before the value/animation split.
    func testSetCancelsARunningAnimationWithFalseThenWritesTheValue() {
        let clock = ManualClock()
        let engine = MotionEngine(clock: clock)
        let track = engine.makeTrack(label: "x")

        var result: Bool?
        let timing = TimingAnimation(toValue: 100, config: TimingConfig(duration: 1000, easing: { Easing.linear($0) }))
        engine.start(track, timing) { finished in result = finished }

        engine.set(track, 55)

        XCTAssertEqual(result, false)
        XCTAssertFalse(track.isActive)
        XCTAssertEqual(track.currentValue, 55)
        XCTAssertFalse(clock.wantsFrames, "setting the only active track's value directly stops asking for frames")
    }

    func testTenSecondGuardForceCompletesAnAgingTrack() {
        let clock = ManualClock()
        let engine = MotionEngine(clock: clock)
        let track = engine.makeTrack(label: "x")

        var result: Bool?
        let neverFinishes = ScriptedAnimation(current: 0) { _ in (0, false) }
        engine.start(track, neverFinishes) { finished in result = finished }

        // one tick per 500ms "frame", same cadence a real driver would use.
        for _ in 0..<25 {
            clock.advance(ms: 500, frameMs: 500)
            if result != nil {
                break
            }
        }

        XCTAssertEqual(result, false, "a track older than 10 seconds is force-completed with false")
        XCTAssertFalse(track.isActive)
    }

    /// The library never traps a host app - an empty Sequence (a call-site
    /// mistake) must behave like a trivial, immediately-finished animation
    /// rather than crashing, and a frame asked for after it finishes must
    /// also not trap.
    func testEmptySequenceNeverTraps() {
        let sequence = SequenceAnimation([])
        sequence.onStart(value: 7, now: 0, previous: .none)
        XCTAssertEqual(sequence.current, 7)
        XCTAssertTrue(sequence.onFrame(now: 1))
    }

    /// A sequence asked for a frame after it already finished (a call-site
    /// mistake, never something MotionTrack itself does) returns true and
    /// does nothing, rather than indexing past its last child.
    func testSequenceAskedForAFrameAfterItFinishedNeverTraps() {
        let timing = TimingAnimation(toValue: 10, config: TimingConfig(duration: 1, easing: { Easing.linear($0) }))
        let sequence = SequenceAnimation([timing])
        sequence.onStart(value: 0, now: 0, previous: .none)
        XCTAssertTrue(sequence.onFrame(now: 100))
        XCTAssertTrue(sequence.onFrame(now: 200), "asked again after finishing - returns true, does nothing")
        XCTAssertEqual(sequence.current, 10)
    }

    func testTenSecondGuardExemptsALoopTrack() {
        let clock = ManualClock()
        let engine = MotionEngine(clock: clock)
        let track = engine.makeTrack(label: "busyLoop")

        var result: Bool?
        let neverFinishes = ScriptedAnimation(current: 0) { _ in (0, false) }
        engine.start(track, neverFinishes, isLoop: true) { finished in result = finished }

        clock.advance(ms: 10, frameMs: 10)
        clock.advance(ms: 20_000, frameMs: 500)

        XCTAssertNil(result, "a loop track is exempt from the 10 second force-complete guard")
        XCTAssertTrue(track.isActive)
    }

    /// Nesting past MotionTrack's bound of 8 (a completion that starts an
    /// animation whose completion starts another, and so on) reports
    /// `.nestingOverflow` instead of recursing further - never a trap.
    /// Past the nesting bound, `start` never just silently drops the new
    /// completion - it is still called, with false, before `start` returns.
    func testNestingOverflowReportsAnErrorInsteadOfRecursingForever() {
        let clock = ManualClock()
        let engine = MotionEngine(clock: clock)
        let track = engine.makeTrack(label: "x")

        var reported: MotionError?
        engine.onError = { error, _ in reported = error }
        var lastResult: Bool?

        func startAgain(depth: Int) {
            let instant = TimingAnimation(toValue: 1, config: TimingConfig(duration: 0, easing: { Easing.linear($0) }))
            engine.start(track, instant) { finished in
                lastResult = finished
                if depth < 20 {
                    startAgain(depth: depth + 1)
                }
            }
        }
        startAgain(depth: 0)

        XCTAssertEqual(reported, .nestingOverflow)
        XCTAssertEqual(lastResult, false, "the deepest call is well past the bound - its own completion still fires, with false")
    }

    // MARK: - Completions run after the tick's own integration step

    /// Two tracks in one tick: the first finishes (its completion is
    /// queued), the second merely advances. By the time the first track's
    /// completion runs, the second track's value already reflects THIS
    /// tick's own integration step - and a track started from inside that
    /// completion is not stepped again within the same tick.
    func testCompletionsSeeThisTicksIntegrationAndReentrantTracksStepOnlyOnce() {
        let clock = ManualClock()
        let engine = MotionEngine(clock: clock)
        let quick = engine.makeTrack(label: "quick")
        let slow = engine.makeTrack(label: "slow")

        engine.start(slow, TimingAnimation(toValue: 100, config: TimingConfig(duration: 1000, easing: { Easing.linear($0) })))

        var slowValueInsideCompletion: Double?
        var completionRan = false
        var reentrantFrameCount = 0
        engine.start(quick, TimingAnimation(toValue: 10, config: TimingConfig(duration: 10, easing: { Easing.linear($0) }))) { finished in
            completionRan = true
            XCTAssertTrue(finished)
            slowValueInsideCompletion = slow.currentValue
            // a track started from inside this completion must not be
            // stepped again in this same tick - a ScriptedAnimation that
            // counts its own onFrame calls proves it directly.
            let extra = engine.makeTrack(label: "extra")
            let counting = ScriptedAnimation(current: 0) { _ in
                reentrantFrameCount += 1
                return (Double(reentrantFrameCount), false)
            }
            engine.start(extra, counting)
        }

        clock.advance(ms: 10, frameMs: 10)

        XCTAssertTrue(completionRan)
        // slow's value at t=10ms of a 1000ms/0->100 linear timing is 1.0
        XCTAssertEqual(slowValueInsideCompletion ?? -1, slow.currentValue, accuracy: 1e-9, "the completion saw THIS tick's already-integrated value, same as reading it right after")
        XCTAssertEqual(reentrantFrameCount, 1, "the reentrant track's synchronous first frame ran once, and was not stepped again this tick")
    }

    // MARK: - A start inside a tick uses the tick's own time

    /// A clock whose `now` can read differently from the time it hands to
    /// its own frame handler - a real display link's `now` can move on
    /// between the frame callback firing and a completion inside it running
    /// synchronously. `engine.start` must use the TICK's time, not
    /// whatever `clock.now` happens to read by the time a completion
    /// inside that tick calls it.
    @MainActor
    private final class DivergingClock: MotionClock {
        private final class Handle: MotionCancellable {
            func cancel() {}
        }

        var now: Double
        var frameHandler: (@MainActor (Double) -> Void)?
        private(set) var wantsFrames = false

        init(now: Double) {
            self.now = now
        }

        func setWantsFrames(_ wantsFrames: Bool) {
            self.wantsFrames = wantsFrames
        }

        func after(milliseconds: Double, _ action: @escaping @MainActor () -> Void) -> MotionCancellable {
            Handle()
        }

        /// Sets `now` to `divergedNow` FIRST, then fires the frame handler
        /// with the unrelated `frameTime` - simulating `clock.now` already
        /// having moved on by the time a completion synchronously fired
        /// from inside this very frame callback goes looking for the time.
        func fire(frameTime: Double, thenLetNowRead divergedNow: Double) {
            now = divergedNow
            frameHandler?(frameTime)
        }
    }

    func testStartInsideATickUsesTheTicksTimeNotClockNow() {
        let clock = DivergingClock(now: 0)
        let engine = MotionEngine(clock: clock)
        let quick = engine.makeTrack(label: "quick")
        let springTrack = engine.makeTrack(label: "spring")

        var startedSpring: SpringAnimation?
        engine.start(quick, TimingAnimation(toValue: 10, config: TimingConfig(duration: 1, easing: { Easing.linear($0) }))) { finished in
            XCTAssertTrue(finished)
            let spring = SpringAnimation(toValue: 5, config: SpringConfig(duration: 500, dampingRatio: 1))
            engine.start(springTrack, spring)
            startedSpring = spring
        }

        // `quick` (duration 1ms) finishes as soon as this tick reaches
        // t=100 - its completion (above) starts `springTrack` reentrantly,
        // still inside this same tick.
        clock.fire(frameTime: 100, thenLetNowRead: 9999)

        XCTAssertEqual(startedSpring?.startTimestamp, 100, "the spring's own start time must be the TICK's time (100), not the diverged clock.now (9999) read afterward")
    }

    // MARK: - The deliberate difference: a completion fired by the cancel phase

    /// A completion fired while cancelling the outgoing animation (the
    /// FIRST phase of a start) that reentrantly starts animation B on the
    /// same track: the outer start still wins over B, B's own completion
    /// fires with false, the track ends up running the outer animation
    /// only, and - since the outer animation here is a spring - it
    /// inherits B's velocity, proving B really was handed to the outer's
    /// onStart as the animation it replaced.
    func testCancelPhaseReentrantStartIsReplacedByTheOuterStartWhichInheritsItsVelocity() {
        let clock = ManualClock()
        let engine = MotionEngine(clock: clock)
        let track = engine.makeTrack(label: "x")

        var capturedB: SpringAnimation?
        var bResult: Bool?
        // toValue != the track's initial value (0) - otherwise this seed
        // would short-circuit at start (a plain timing whose target
        // already equals the current value completes at once) and never
        // become the thing the outer start's cancel phase fires.
        let seed = TimingAnimation(toValue: 50, config: TimingConfig(duration: 1000, easing: { Easing.linear($0) }))
        engine.start(track, seed) { _ in
            let b = SpringAnimation(toValue: 300, config: SpringConfig(duration: 500, dampingRatio: 0.8, velocity: 500))
            engine.start(track, b) { finished in bResult = finished }
            capturedB = b
        }

        var outerResult: Bool?
        let outer = SpringAnimation(toValue: 999, config: SpringConfig(duration: 500, dampingRatio: 0.8, velocity: 0))
        engine.start(track, outer) { finished in outerResult = finished }

        // 1: the outer start wins - the track's own onStart ran with the
        // outer animation, not B (proven below via velocity inheritance,
        // and via the track only ever completing through `outer`'s own
        // completion from here on).
        // 2: B's completion fired with false.
        XCTAssertEqual(bResult, false, "B, reentrantly started during the outer start's cancel phase, is itself cancelled by that same outer start")
        // 3: the track runs the outer animation only - cancelling it now
        // fires ONLY outer's completion, never B's again.
        engine.cancel(track)
        XCTAssertEqual(outerResult, false)
        XCTAssertEqual(bResult, false, "B's completion does not fire a second time")
        // 4: the outer spring inherited B's velocity (outer's own config
        // velocity is 0, so any nonzero velocity came from B).
        XCTAssertEqual(outer.velocity, capturedB?.velocity ?? .nan, accuracy: 1e-9, "the outer spring's velocity came from B, proving B was handed to onStart as the replaced animation")
        XCTAssertNotEqual(outer.velocity, 0, "sanity: B's own velocity (500 toward its target) was actually nonzero to inherit")
    }

    // MARK: - Removing a track

    func testRemoveCancelsAndUnregistersATrackAndRefusesFurtherStarts() {
        let clock = ManualClock()
        let engine = MotionEngine(clock: clock)
        let track = engine.makeTrack(label: "x")

        var cancelResult: Bool?
        let timing = TimingAnimation(toValue: 100, config: TimingConfig(duration: 1000, easing: { Easing.linear($0) }))
        engine.start(track, timing) { finished in cancelResult = finished }

        engine.remove(track)

        XCTAssertEqual(cancelResult, false, "remove cancels whatever was running, same as cancel")
        XCTAssertFalse(track.isActive)
        XCTAssertFalse(clock.wantsFrames, "removing the only active track stops asking for frames")

        var reported: (MotionError, String)?
        engine.onError = { error, label in reported = (error, label) }
        var startResult: Bool?
        engine.start(track, TimingAnimation(toValue: 5, config: TimingConfig(duration: 10, easing: { Easing.linear($0) }))) { finished in startResult = finished }

        XCTAssertEqual(startResult, false, "a removed track reports an error and does nothing when started again")
        XCTAssertFalse(track.isActive)
        XCTAssertEqual(reported?.0, .trackRemoved)
        XCTAssertEqual(reported?.1, "x")
    }

    /// `MotionEngine.remove` unregisters the track, not just cancels it - it
    /// must drop the engine's own strong reference. Held only through a weak
    /// reference from outside `makeAndRemove`, so once that local function
    /// returns, the track is deallocated if and only if the engine really
    /// dropped it - proving `tracks.removeAll { $0 === track }` actually
    /// does something (removing that line leaves this test's `weakTrack`
    /// non-nil).
    func testRemoveDropsTheEnginesOwnReferenceToTheTrack() {
        let clock = ManualClock()
        let engine = MotionEngine(clock: clock)

        weak var weakTrack: MotionTrack?
        func makeAndRemove() {
            let track = engine.makeTrack(label: "x")
            weakTrack = track
            engine.remove(track)
        }
        makeAndRemove()

        XCTAssertNil(weakTrack, "engine.remove must drop its own reference - nothing else in this test still holds the track")
    }

    /// The 10 second age-out guard clears its own held completion the
    /// moment it force-completes a track (see MotionTrack.step) - unlike a
    /// natural finish, which deliberately leaves its completion refireable
    /// (see testCancelOnANaturallyFinishedTrackFiresItsCompletionAgainWithFalse
    /// below). Without that clear, a cancel made after the age-out fires
    /// would call the same completion a second time, still with false.
    func testAgingOutClearsTheHeldCompletionSoALaterCancelDoesNotRefireIt() {
        let clock = ManualClock()
        let engine = MotionEngine(clock: clock)
        let track = engine.makeTrack(label: "x")

        var results: [Bool] = []
        let neverFinishes = ScriptedAnimation(current: 0) { _ in (0, false) }
        engine.start(track, neverFinishes) { finished in results.append(finished) }

        for _ in 0..<25 {
            clock.advance(ms: 500, frameMs: 500)
            if !results.isEmpty {
                break
            }
        }
        XCTAssertEqual(results, [false], "aged out - the completion fired once, with false")

        engine.cancel(track)
        XCTAssertEqual(results, [false], "the age-out already cleared the held completion - a later cancel does not fire it again")
    }

    // MARK: - Cancel matches cancelAnimation's own mechanism

    /// `cancelAnimation` (animation/util.ts) is `sharedValue.value =
    /// sharedValue.value` - which runs through valueSetter's UNCONDITIONAL
    /// cancellation before the plain-value branch's same-value short
    /// circuit ever runs. A natural finish never clears the stored
    /// animation/completion, so `engine.cancel` on a track whose animation
    /// already finished (and already fired its completion with true) must
    /// still fire that same completion AGAIN, with false - not do nothing.
    func testCancelOnANaturallyFinishedTrackFiresItsCompletionAgainWithFalse() {
        let clock = ManualClock()
        let engine = MotionEngine(clock: clock)
        let track = engine.makeTrack(label: "x")

        var results: [Bool] = []
        let timing = TimingAnimation(toValue: 10, config: TimingConfig(duration: 1, easing: { Easing.linear($0) }))
        engine.start(track, timing) { finished in results.append(finished) }

        clock.advance(ms: 10, frameMs: 10)
        XCTAssertEqual(results, [true], "the timing finished naturally")

        engine.cancel(track)
        XCTAssertEqual(results, [true, false], "cancel fires the same, already-finished completion again, with false")

        // A second cancel is a true no-op - nothing is held any more.
        engine.cancel(track)
        XCTAssertEqual(results, [true, false])
    }

    // MARK: - A queued completion(true) is dropped once its own animation is cancelled

    /// Two tracks finish in the SAME tick. MotionEngine.tick's snapshot (and
    /// so its queued-completions list) preserves creation order, so track
    /// A's completion is queued, and runs, before track B's - and A's
    /// completion cancels B before B's own queued `completion(true)` has a
    /// chance to run. B must hear false only, never true afterward - the
    /// original never does this either, its own step closure returns early
    /// on `animation.cancelled` (valueSetter.ts).
    func testCancelFromAFirstCompletionDropsASecondsQueuedTrueInTheSameTick() {
        let clock = ManualClock()
        let engine = MotionEngine(clock: clock)
        let trackA = engine.makeTrack(label: "a")
        let trackB = engine.makeTrack(label: "b")

        var bResults: [Bool] = []
        engine.start(trackB, TimingAnimation(toValue: 10, config: TimingConfig(duration: 10, easing: { Easing.linear($0) }))) { finished in
            bResults.append(finished)
        }
        engine.start(trackA, TimingAnimation(toValue: 10, config: TimingConfig(duration: 10, easing: { Easing.linear($0) }))) { _ in
            engine.cancel(trackB)
        }

        clock.advance(ms: 10, frameMs: 10)

        XCTAssertEqual(bResults, [false], "B's queued true was dropped - A's completion had already cancelled B's animation")
    }

    /// Same shape, but A's completion calls `engine.set` on B instead of
    /// `cancel` - `set`'s own unconditional cancellation phase marks B's
    /// animation cancelled the same way.
    func testSetFromAFirstCompletionDropsASecondsQueuedTrueInTheSameTick() {
        let clock = ManualClock()
        let engine = MotionEngine(clock: clock)
        let trackA = engine.makeTrack(label: "a")
        let trackB = engine.makeTrack(label: "b")

        var bResults: [Bool] = []
        engine.start(trackB, TimingAnimation(toValue: 10, config: TimingConfig(duration: 10, easing: { Easing.linear($0) }))) { finished in
            bResults.append(finished)
        }
        engine.start(trackA, TimingAnimation(toValue: 10, config: TimingConfig(duration: 10, easing: { Easing.linear($0) }))) { _ in
            engine.set(trackB, 999)
        }

        clock.advance(ms: 10, frameMs: 10)

        XCTAssertEqual(bResults, [false], "B's queued true was dropped - A's completion had already cancelled B's animation via set")
        XCTAssertEqual(trackB.currentValue, 999)
    }

    /// Same shape, but A's completion calls `engine.remove` on B - `remove`
    /// cancels (marking B's animation cancelled) before it unregisters B.
    func testRemoveFromAFirstCompletionDropsASecondsQueuedTrueInTheSameTick() {
        let clock = ManualClock()
        let engine = MotionEngine(clock: clock)
        let trackA = engine.makeTrack(label: "a")
        let trackB = engine.makeTrack(label: "b")

        var bResults: [Bool] = []
        engine.start(trackB, TimingAnimation(toValue: 10, config: TimingConfig(duration: 10, easing: { Easing.linear($0) }))) { finished in
            bResults.append(finished)
        }
        engine.start(trackA, TimingAnimation(toValue: 10, config: TimingConfig(duration: 10, easing: { Easing.linear($0) }))) { _ in
            engine.remove(trackB)
        }

        clock.advance(ms: 10, frameMs: 10)

        XCTAssertEqual(bResults, [false], "B's queued true was dropped - A's completion had already cancelled B's animation via remove")
    }

    /// Same shape, but A's completion calls `engine.start` on B with a new
    /// animation - `start`'s own cancellation phase marks B's OLD animation
    /// cancelled before the new one begins, so the old completion's queued
    /// true is still dropped even though B itself keeps animating.
    func testStartFromAFirstCompletionDropsASecondsQueuedTrueInTheSameTick() {
        let clock = ManualClock()
        let engine = MotionEngine(clock: clock)
        let trackA = engine.makeTrack(label: "a")
        let trackB = engine.makeTrack(label: "b")

        var bOldResults: [Bool] = []
        engine.start(trackB, TimingAnimation(toValue: 10, config: TimingConfig(duration: 10, easing: { Easing.linear($0) }))) { finished in
            bOldResults.append(finished)
        }
        engine.start(trackA, TimingAnimation(toValue: 10, config: TimingConfig(duration: 10, easing: { Easing.linear($0) }))) { _ in
            let replacement = TimingAnimation(toValue: 50, config: TimingConfig(duration: 100, easing: { Easing.linear($0) }))
            engine.start(trackB, replacement)
        }

        clock.advance(ms: 10, frameMs: 10)

        XCTAssertEqual(bOldResults, [false], "B's OLD completion's queued true was dropped - A's completion had already replaced B's animation")
        XCTAssertTrue(trackB.isActive, "B is still running - now the replacement animation started from inside A's completion")
    }

    // MARK: - A nested tick restores the outer tick's own time on exit

    /// A completion advances a ManualClock, causing a NESTED call to
    /// `MotionEngine.tick` before the outer one returns. Once that inner
    /// tick returns, a start made by one of the OUTER tick's remaining
    /// completions must still use the outer tick's own time, not
    /// `clock.now` (which the nested advance already moved past it).
    func testNestedTickRestoresTheOuterTicksTimeForARemainingCompletion() {
        let clock = ManualClock()
        let engine = MotionEngine(clock: clock)
        let innerTrack = engine.makeTrack(label: "inner")
        let outerTrack = engine.makeTrack(label: "outer")
        let lateTrack = engine.makeTrack(label: "late")

        // `inner` is queued first (created first) - its completion runs
        // before `outer`'s, and nests a whole second tick by advancing the
        // clock further, to a time strictly past this outer tick's own
        // `now` (1).
        engine.start(innerTrack, TimingAnimation(toValue: 1, config: TimingConfig(duration: 1, easing: { Easing.linear($0) }))) { _ in
            clock.advance(ms: 100, frameMs: 100)
        }

        var lateStartTime: Double?
        engine.start(outerTrack, TimingAnimation(toValue: 1, config: TimingConfig(duration: 1, easing: { Easing.linear($0) }))) { _ in
            let spring = SpringAnimation(toValue: 5, config: SpringConfig(duration: 500, dampingRatio: 1))
            engine.start(lateTrack, spring)
            lateStartTime = spring.startTimestamp
        }

        // The outer tick: both inner and outer finish here, at now = 1.
        clock.advance(ms: 1, frameMs: 1)

        XCTAssertEqual(clock.now, 101, "sanity: the nested advance really did move clock.now past the outer tick's own time")
        XCTAssertEqual(lateStartTime, 1, "the outer tick's remaining completion must see ITS OWN tick time (1), not clock.now (101) after the nested tick already ran and returned")
    }
}
