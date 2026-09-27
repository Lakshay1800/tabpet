import XCTest

@testable import TabPetMotion

/// Tolerance rule shared with every other conformance fixture in this repo
/// (relative 1e-9) - motion.json is "tolerance" throughout, since a
/// spring's position and velocity pass through exp/sin/cos. See
/// scripts/gen-motion-fixtures.mjs's header for why.
func motionNumbersEqual(_ a: Double, _ b: Double) -> Bool {
    if a.isNaN || b.isNaN {
        return a.isNaN && b.isNaN
    }
    if !a.isFinite || !b.isFinite {
        return a == b
    }
    let scale = Swift.max(1, abs(a), abs(b))
    return abs(a - b) <= 1e-9 * scale
}

func assertClose(_ actual: Double, _ expected: Double, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(
        motionNumbersEqual(actual, expected),
        "\(message): got \(actual), want \(expected) (tolerance 1e-9)",
        file: file,
        line: line
    )
}

/// Not `private` - TrackEngineReplayTests (a different file in this same
/// test target) reuses this and the other fixture-decoding helpers below.
func springConfig(from raw: [String: Any]) -> SpringConfig {
    let clamp: SpringClamp? = (raw["clamp"] as? [String: Any]).map {
        SpringClamp(min: wireDouble($0["min"]), max: wireDouble($0["max"]))
    }
    return SpringConfig(
        mass: wireDouble(raw["mass"]),
        damping: wireDouble(raw["damping"]),
        stiffness: wireDouble(raw["stiffness"]),
        duration: wireDouble(raw["duration"]),
        dampingRatio: wireDouble(raw["dampingRatio"]),
        velocity: wireDouble(raw["velocity"]),
        overshootClamping: raw["overshootClamping"] as? Bool,
        energyThreshold: wireDouble(raw["energyThreshold"]),
        clamp: clamp
    )
}

/// Drives a SpringAnimation through one fixture case's frames (each frame
/// row carries its own absolute `t` - see gen-motion-fixtures.mjs) and
/// asserts every recorded {current, velocity, finished}. Returns the spring
/// so a retarget case can pass it on as `previous`.
@MainActor
private func replaySpring(
    toValue: Double,
    config: SpringConfig,
    fromValue: Double,
    startT: Double,
    expectAfterStart: [String: Any],
    expectFrames: [[String: Any]],
    previous: SpringAnimation?,
    label: String
) -> SpringAnimation {
    let spring = SpringAnimation(toValue: toValue, config: config)
    spring.onStart(value: fromValue, now: startT, previous: previous.map(ReplacedAnimation.some) ?? .none)

    assertClose(spring.current, wireDouble(expectAfterStart["current"])!, "\(label) afterStart.current")
    if let v = wireDouble(expectAfterStart["velocity"]) {
        assertClose(spring.velocity, v, "\(label) afterStart.velocity")
    }
    if let z = wireDouble(expectAfterStart["zeta"]) {
        assertClose(spring.zeta, z, "\(label) afterStart.zeta")
    }
    if let o0 = wireDouble(expectAfterStart["omega0"]) {
        assertClose(spring.omega0, o0, "\(label) afterStart.omega0")
    }
    if let o1 = wireDouble(expectAfterStart["omega1"]) {
        assertClose(spring.omega1, o1, "\(label) afterStart.omega1")
    }
    if let e = wireDouble(expectAfterStart["initialEnergy"]) {
        assertClose(spring.initialEnergy, e, "\(label) afterStart.initialEnergy")
    }

    for (index, row) in expectFrames.enumerated() {
        let t = wireDouble(row["t"])!
        let finished = spring.onFrame(now: t)
        assertClose(spring.current, wireDouble(row["current"])!, "\(label) frame[\(index)].current")
        if let v = wireDouble(row["velocity"]) {
            assertClose(spring.velocity, v, "\(label) frame[\(index)].velocity")
        }
        XCTAssertEqual(finished, row["finished"] as? Bool, "\(label) frame[\(index)].finished")
    }
    return spring
}

func easing(named name: String) -> @Sendable (Double) -> Double {
    switch name {
    case "linear":
        return { Easing.linear($0) }
    case "inOutQuad":
        return { Easing.inOutQuad($0) }
    default:
        fatalError("unknown easing '\(name)' in fixture - motion.json should never encode one this port doesn't have")
    }
}

/// A fixture timing case's `easing` field is always the NAME that was
/// passed to the generator - `'inOutQuad'` always means "no easing key was
/// given to the real withTiming", never an explicit override. The Swift
/// replay for that case must build its TimingConfig the same way: without
/// an `easing:` argument at all, so it proves TimingAnimation's OWN default
/// really is inOutQuad, rather than just re-injecting the same closure.
func timingConfig(duration: Double, easingName: String) -> TimingConfig {
    if easingName == "inOutQuad" {
        return TimingConfig(duration: duration)
    }
    return TimingConfig(duration: duration, easing: easing(named: easingName))
}

@MainActor
private func assertFrames(
    _ animation: MotionAnimation,
    frameTimes: [Double],
    expectFrames: [[String: Any]],
    isSpring: Bool,
    label: String
) {
    XCTAssertLessThanOrEqual(expectFrames.count, frameTimes.count, "\(label) frame count")
    for (index, row) in expectFrames.enumerated() {
        let finished = animation.onFrame(now: frameTimes[index])
        assertClose(animation.current, wireDouble(row["current"])!, "\(label) frame[\(index)].current")
        if isSpring, let v = wireDouble(row["velocity"]), let spring = animation as? SpringAnimation {
            assertClose(spring.velocity, v, "\(label) frame[\(index)].velocity")
        }
        XCTAssertEqual(finished, row["finished"] as? Bool, "\(label) frame[\(index)].finished")
    }
}

/// One recorded completion firing, tagged with the index of the `set` op
/// that BUILT the animation whose completion just fired - not necessarily
/// the op this firing happened during (a stale, already-replaced
/// animation's completion can refire on a LATER op - see
/// gen-motion-fixtures.mjs's `makeRecord`).
struct RecordedCallback: Equatable {
    let finished: Bool
    let builtByOpIndex: Int
}

/// A stable reference a completion closure can capture across ops - see
/// testTrackCasesReplayValueSetterParity and TrackEngineReplayTests for why
/// a plain local `var` doesn't work here.
@MainActor
final class CallbackRecorder {
    var callbacks: [RecordedCallback] = []
}

/// Decodes one fixture row's `callbacks` array - shared by both track
/// replay tests.
func expectedCallbacks(_ row: [String: Any]) -> [RecordedCallback] {
    (row["callbacks"] as! [[String: Any]]).map {
        RecordedCallback(finished: $0["finished"] as! Bool, builtByOpIndex: ($0["builtByOpIndex"] as! NSNumber).intValue)
    }
}

/// Builds the real MotionAnimation graph a `track` fixture case's op
/// `spec` describes (see gen-motion-fixtures.mjs's encodeAnimSpec) -
/// mirrors buildAnimation in the generator, one level removed from the
/// real reanimated objects.

/// Mirrors gen-motion-fixtures.mjs's own `buildAnimation`: a top-level
/// 'sequence' spec is built through the real `withSequence`, which has no
/// callback parameter in this codebase's API at all (unlike `withTiming`/
/// `withSpring`, which take one directly, and `withDelay`, whose own
/// `.callback` forwards to its inner animation's) - so nothing is ever
/// wired to `record` for it, even when it is itself the TOP-level spec, not
/// just when nested as a sequence's own child. A replay must not attach a
/// Swift completion where the real fixture could never have recorded one.
func specHasRecordableTopLevelCallback(_ spec: [String: Any]) -> Bool {
    (spec["kind"] as! String) != "sequence"
}

@MainActor
func buildAnimation(spec: [String: Any]) -> MotionAnimation {
    let kind = spec["kind"] as! String
    switch kind {
    case "timing":
        let toValue = wireDouble(spec["toValue"])!
        let duration = wireDouble(spec["duration"])!
        let easingName = spec["easing"] as! String
        return TimingAnimation(toValue: toValue, config: timingConfig(duration: duration, easingName: easingName))
    case "spring":
        let toValue = wireDouble(spec["toValue"])!
        let config = springConfig(from: spec["config"] as! [String: Any])
        return SpringAnimation(toValue: toValue, config: config)
    case "delay":
        let delayMs = wireDouble(spec["delayMs"])!
        let inner = buildAnimation(spec: spec["inner"] as! [String: Any])
        return DelayAnimation(delayMs, inner)
    case "sequence":
        let children = (spec["animations"] as! [[String: Any]]).map { buildAnimation(spec: $0) }
        return SequenceAnimation(children)
    default:
        fatalError("unknown track op spec kind '\(kind)' in fixture")
    }
}

@MainActor
final class ConformanceReplayTests: XCTestCase {
    func testMotionFixtureCoverage() throws {
        let fixture = try MotionFixtureLoader.load()
        XCTAssertEqual(fixture.module, "motion")
        XCTAssertEqual(fixture.reanimatedVersion, "4.5.0")
        XCTAssertGreaterThan(fixture.cases.count, 0)

        let known: Set<String> = ["spring", "timing", "delay", "sequence", "repeat", "track"]
        for c in fixture.cases {
            XCTAssertTrue(known.contains(c.fn), "fixture names unknown fn \(c.fn)")
        }
        for fn in known {
            XCTAssertGreaterThan(fixture.cases(fn: fn).count, 0, "no fixture coverage for fn \(fn)")
        }
    }

    func testEverySpringCase() throws {
        let fixture = try MotionFixtureLoader.load()
        var run = 0
        for c in fixture.cases(fn: "spring") {
            try runSpringCase(c)
            run += 1
        }
        XCTAssertGreaterThan(run, 0)
        print("ConformanceReplayTests: \(run) spring fixture cases passed")
    }

    private func runSpringCase(_ c: MotionFixtureCase) throws {
        let args = c.args
        let expect = c.expect
        let fromValue = wireDouble(args["fromValue"])!
        let toValue = wireDouble(args["toValue"])!
        let startT = wireDouble(args["startT"])!
        let config = springConfig(from: args["config"] as! [String: Any])
        let afterStart = expect["afterStart"] as! [String: Any]
        let frames = expect["frames"] as! [[String: Any]]

        let spring = replaySpring(
            toValue: toValue,
            config: config,
            fromValue: fromValue,
            startT: startT,
            expectAfterStart: afterStart,
            expectFrames: frames,
            previous: nil,
            label: c.label
        )

        guard let retargetArgs = args["retarget"] as? [String: Any], let retargetExpect = expect["retarget"] as? [String: Any] else {
            return
        }
        let rToValue = wireDouble(retargetArgs["toValue"])!
        let rT = wireDouble(retargetArgs["t"])!
        let rConfig = springConfig(from: retargetArgs["config"] as! [String: Any])
        let rAfterStart = retargetExpect["afterStart"] as! [String: Any]
        let rFrames = retargetExpect["frames"] as! [[String: Any]]
        _ = replaySpring(
            toValue: rToValue,
            config: rConfig,
            fromValue: spring.current,
            startT: rT,
            expectAfterStart: rAfterStart,
            expectFrames: rFrames,
            previous: spring,
            label: "\(c.label) (retarget)"
        )
    }

    func testEveryTimingCase() throws {
        let fixture = try MotionFixtureLoader.load()
        var run = 0
        for c in fixture.cases(fn: "timing") {
            let args = c.args
            let expect = c.expect
            let fromValue = wireDouble(args["fromValue"])!
            let toValue = wireDouble(args["toValue"])!
            let duration = wireDouble(args["duration"])!
            let easingName = args["easing"] as! String
            let startT = wireDouble(args["startT"])!
            let frameTimes = wireDoubleArray(args["frameTimes"])
            let frames = expect["frames"] as! [[String: Any]]

            let timing = TimingAnimation(toValue: toValue, config: timingConfig(duration: duration, easingName: easingName))
            timing.onStart(value: fromValue, now: startT, previous: .none)
            assertFrames(timing, frameTimes: frameTimes, expectFrames: frames, isSpring: false, label: c.label)
            run += 1
        }
        XCTAssertGreaterThan(run, 0)
    }

    func testDelayCase() throws {
        let fixture = try MotionFixtureLoader.load()
        var run = 0
        for c in fixture.cases(fn: "delay") {
            let args = c.args
            let expect = c.expect
            let delayMs = wireDouble(args["delayMs"])!
            let fromValue = wireDouble(args["fromValue"])!
            let inner = args["inner"] as! [String: Any]
            let innerToValue = wireDouble(inner["toValue"])!
            let innerDuration = wireDouble(inner["duration"])!
            let startT = wireDouble(args["startT"])!
            let frameTimes = wireDoubleArray(args["frameTimes"])
            let frames = expect["frames"] as! [[String: Any]]

            let timing = TimingAnimation(toValue: innerToValue, config: TimingConfig(duration: innerDuration, easing: { Easing.linear($0) }))
            let delay = DelayAnimation(delayMs, timing)
            delay.onStart(value: fromValue, now: startT, previous: .none)
            assertFrames(delay, frameTimes: frameTimes, expectFrames: frames, isSpring: false, label: c.label)
            run += 1
        }
        XCTAssertGreaterThan(run, 0)
    }

    func testSequenceCase() throws {
        let fixture = try MotionFixtureLoader.load()
        var run = 0
        for c in fixture.cases(fn: "sequence") {
            let args = c.args
            let expect = c.expect
            let fromValue = wireDouble(args["fromValue"])!
            let rawAnimations = args["animations"] as! [[String: Any]]
            let startT = wireDouble(args["startT"])!
            let frameTimes = wireDoubleArray(args["frameTimes"])
            let frames = expect["frames"] as! [[String: Any]]

            let children: [MotionAnimation] = rawAnimations.map { raw in
                let toValue = wireDouble(raw["toValue"])!
                switch raw["kind"] as! String {
                case "timing":
                    let duration = wireDouble(raw["duration"])!
                    return TimingAnimation(toValue: toValue, config: TimingConfig(duration: duration, easing: { Easing.linear($0) }))
                case "spring":
                    return SpringAnimation(toValue: toValue, config: springConfig(from: raw["config"] as! [String: Any]))
                default:
                    fatalError("unknown sequence child kind")
                }
            }
            let sequence = SequenceAnimation(children)
            sequence.onStart(value: fromValue, now: startT, previous: .none)
            assertFrames(sequence, frameTimes: frameTimes, expectFrames: frames, isSpring: false, label: c.label)
            run += 1
        }
        XCTAssertGreaterThan(run, 0)
    }

    func testRepeatCase() throws {
        let fixture = try MotionFixtureLoader.load()
        var run = 0
        for c in fixture.cases(fn: "repeat") {
            let args = c.args
            let expect = c.expect
            let fromValue = wireDouble(args["fromValue"])!
            let inner = args["inner"] as! [String: Any]
            let innerToValue = wireDouble(inner["toValue"])!
            let innerDuration = wireDouble(inner["duration"])!
            let numberOfReps = (args["numberOfReps"] as! NSNumber).intValue
            let reverse = args["reverse"] as! Bool
            let startT = wireDouble(args["startT"])!
            let frameTimes = wireDoubleArray(args["frameTimes"])
            let frames = expect["frames"] as! [[String: Any]]

            let timing = TimingAnimation(toValue: innerToValue, config: TimingConfig(duration: innerDuration, easing: { Easing.linear($0) }))
            let repeatAnim = RepeatAnimation(timing, numberOfReps: numberOfReps, reverse: reverse)
            repeatAnim.onStart(value: fromValue, now: startT, previous: .none)
            assertFrames(repeatAnim, frameTimes: frameTimes, expectFrames: frames, isSpring: false, label: c.label)
            run += 1
        }
        XCTAssertGreaterThan(run, 0)
    }

    /// Replays every `track` fixture case (a script of real-valueSetter
    /// operations - see gen-motion-fixtures.mjs's runTrackScript) through
    /// MotionTrack directly: builds the same animation graph the generator
    /// built, drives `set`/`frame` ops through `track.start`/`track.step`,
    /// and asserts the value and every completion callback fired after
    /// each op, in order. TrackEngineReplayTests replays the same scripts
    /// through MotionEngine + ManualClock instead.
    func testTrackCasesReplayValueSetterParity() throws {
        let fixture = try MotionFixtureLoader.load()
        var run = 0
        for c in fixture.cases(fn: "track") {
            let args = c.args
            let expect = c.expect
            let initialValue = wireDouble(args["initialValue"])!
            let ops = args["ops"] as! [[String: Any]]
            let results = expect["results"] as! [[String: Any]]
            XCTAssertEqual(ops.count, results.count, "\(c.label) op/result count")

            let track = MotionTrack(label: c.label, initialValue: initialValue)
            // A completion built on one op can fire again on a LATER op
            // (an already-finished animation's completion refires with
            // false when the next `set` replaces it - real valueSetter.ts
            // behaviour, proven by these fixtures). `recorder` is one
            // stable reference every op's completion closure captures;
            // `recorder.callbacks` is reset at the START of each op, so a
            // callback fired DURING that op lands in that op's own bucket
            // regardless of which earlier op built the animation.
            let recorder = CallbackRecorder()
            for (index, op) in ops.enumerated() {
                let now = wireDouble(op["now"])!
                recorder.callbacks = []
                switch op["kind"] as! String {
                case "set":
                    let spec = op["spec"] as! [String: Any]
                    let animation = buildAnimation(spec: spec)
                    // A top-level 'sequence' spec has no completion to
                    // replay at all - see specHasRecordableTopLevelCallback.
                    let completion: ((Bool) -> Void)? = specHasRecordableTopLevelCallback(spec)
                        ? { finished in recorder.callbacks.append(RecordedCallback(finished: finished, builtByOpIndex: index)) }
                        : nil
                    track.start(animation, now: now, completion: completion)
                case "setValue":
                    track.set(wireDouble(op["value"])!)
                case "cancelSelf":
                    track.cancel()
                default:
                    switch track.step(now: now, maxAgeMs: .infinity) {
                    case .finished(_, let completion):
                        completion?(true)
                    case .timedOut(let completion):
                        completion?(false)
                    case .nonFinite(_, let completion):
                        completion?(false)
                    case .active:
                        break
                    }
                }
                let row = results[index]
                assertClose(track.currentValue, wireDouble(row["value"])!, "\(c.label) op[\(index)].value")
                XCTAssertEqual(recorder.callbacks, expectedCallbacks(row), "\(c.label) op[\(index)].callbacks")
            }
            run += 1
        }
        XCTAssertGreaterThan(run, 0)
    }
}
