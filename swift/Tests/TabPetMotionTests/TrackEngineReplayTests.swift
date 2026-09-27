import XCTest

@testable import TabPetMotion

/// Replays every `track` fixture case a second way: through MotionEngine +
/// MotionTrack + a ManualClock, the way a real host actually drives this
/// library, rather than calling `MotionTrack.step` by hand
/// (ConformanceReplayTests.testTrackCasesReplayValueSetterParity does that
/// lower-level replay). `frame` ops advance the clock (which drives the
/// engine itself, per MotionClock.frameHandler) rather than stepping the
/// track directly.
@MainActor
final class TrackEngineReplayTests: XCTestCase {
    func testTrackCasesReplayThroughEngineAndManualClock() throws {
        let fixture = try MotionFixtureLoader.load()
        var run = 0
        for c in fixture.cases(fn: "track") {
            let args = c.args
            let expect = c.expect
            let initialValue = wireDouble(args["initialValue"])!
            let ops = args["ops"] as! [[String: Any]]
            let results = expect["results"] as! [[String: Any]]
            XCTAssertEqual(ops.count, results.count, "\(c.label) op/result count")

            let firstNow = wireDouble(ops.first?["now"]) ?? 0
            let clock = ManualClock(now: firstNow)
            let engine = MotionEngine(clock: clock)
            let track = engine.makeTrack(label: c.label, initialValue: initialValue)

            // See ConformanceReplayTests.CallbackRecorder: an already-
            // finished animation's completion can refire (with false) on a
            // LATER op than the one that started it, so every op's
            // completion closure must share ONE recorder, reset per op.
            let recorder = CallbackRecorder()
            for (index, op) in ops.enumerated() {
                let now = wireDouble(op["now"])!
                recorder.callbacks = []
                switch op["kind"] as! String {
                case "set":
                    let spec = op["spec"] as! [String: Any]
                    let animation = buildAnimation(spec: spec)
                    // Jump the clock to `now` with no frame in between (a
                    // `set` in the fixture script is not itself a frame),
                    // then start on it - `engine.start` reads `clock.now`.
                    jumpClock(clock, to: now)
                    // A top-level 'sequence' spec has no completion to
                    // replay at all - see specHasRecordableTopLevelCallback.
                    let completion: ((Bool) -> Void)? = specHasRecordableTopLevelCallback(spec)
                        ? { finished in recorder.callbacks.append(RecordedCallback(finished: finished, builtByOpIndex: index)) }
                        : nil
                    engine.start(track, animation, completion: completion)
                case "setValue":
                    jumpClock(clock, to: now)
                    engine.set(track, wireDouble(op["value"])!)
                case "cancelSelf":
                    jumpClock(clock, to: now)
                    engine.cancel(track)
                default:
                    let delta = now - clock.now
                    XCTAssertGreaterThan(delta, 0, "\(c.label) op[\(index)]: frame times must strictly increase")
                    clock.advance(ms: delta, frameMs: delta)
                }
                let row = results[index]
                assertClose(track.currentValue, wireDouble(row["value"])!, "\(c.label) op[\(index)].value (engine replay)")
                XCTAssertEqual(recorder.callbacks, expectedCallbacks(row), "\(c.label) op[\(index)].callbacks (engine replay)")
            }
            run += 1
        }
        XCTAssertGreaterThan(run, 0)
    }
}

/// Moves a ManualClock's `now` directly to `target` without firing any
/// frame handler - used only to align the clock ahead of a `set` op, which
/// (like a real `valueSetter` call arriving between frames) is not itself a
/// frame. Timers still fire in order, same as `advance`.
@MainActor
private func jumpClock(_ clock: ManualClock, to target: Double) {
    let delta = target - clock.now
    guard delta > 0 else {
        return
    }
    let wasWantingFrames = clock.wantsFrames
    clock.setWantsFrames(false)
    clock.advance(ms: delta, frameMs: delta)
    clock.setWantsFrames(wasWantingFrames)
}
