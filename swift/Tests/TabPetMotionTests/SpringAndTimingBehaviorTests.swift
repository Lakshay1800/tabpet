import XCTest

@testable import TabPetMotion

/// The spring and timing behaviours called out by name (not just replayed
/// generically from the fixture) per the TEST STRATEGY: the stiffness
/// solve, retarget velocity inheritance, a zero-displacement start, the
/// 64ms dt clamp, the timing stall catch-up, and the inOutQuad curve.
@MainActor
final class SpringAndTimingBehaviorTests: XCTestCase {
    /// The stiffness is solved at every start from the starting
    /// displacement AND velocity, not fixed per config. Two springs with
    /// the SAME {duration, dampingRatio, x0} but different starting
    /// velocity must get DIFFERENT omega0 - a fixed-stiffness spring (a
    /// `CASpringAnimation`, say) could not reproduce this. (Displacement
    /// alone does not prove this: at zero starting velocity, the energy
    /// ratio the stiffness search targets is scale-invariant in |x0| - two
    /// springs with v0=0 and different x0 but the same config actually
    /// solve to the SAME omega0. Velocity is what breaks that invariance.)
    func testStiffnessIsSolvedPerStartNotPerConfig() {
        let stationary = SpringAnimation(toValue: 100, config: SpringConfig(duration: 500, dampingRatio: 0.8, velocity: 0))
        stationary.onStart(value: 0, now: 0, previous: .none)

        let moving = SpringAnimation(toValue: 100, config: SpringConfig(duration: 500, dampingRatio: 0.8, velocity: 600))
        moving.onStart(value: 0, now: 0, previous: .none)

        XCTAssertNotEqual(stationary.omega0, moving.omega0, "same config, same x0, different v0, must solve a different stiffness")
    }

    /// Retargeting inherits the previous spring's velocity, clipped to 0
    /// only if it now points away from the new target.
    func testRetargetInheritsVelocityWithClip() {
        let config = SpringConfig(duration: 500, dampingRatio: 0.8)

        let first = SpringAnimation(toValue: 100, config: config)
        first.onStart(value: 0, now: 10, previous: .none)
        for i in 1...6 {
            _ = first.onFrame(now: 10 + Double(i) * 16.666)
        }
        XCTAssertGreaterThan(first.velocity, 0, "moving toward 100, velocity should be positive")

        // retarget to a target AHEAD of the motion - velocity toward it, inherited unclipped
        let ahead = SpringAnimation(toValue: 250, config: config)
        ahead.onStart(value: first.current, now: 110, previous: .some(first))
        XCTAssertEqual(ahead.velocity, first.velocity, accuracy: 1e-9, "velocity toward the new target is inherited, not clipped")

        // retarget to a target BEHIND the motion - inherited velocity now points away, must clip to 0
        let behind = SpringAnimation(toValue: -50, config: config)
        behind.onStart(value: first.current, now: 110, previous: .some(first))
        XCTAssertEqual(behind.velocity, 0, "velocity pointing away from the new target is clipped to 0")
    }

    /// A spring that starts at its own target (displacement 0, default
    /// zero velocity) has initialEnergy == 0 and terminates on its very
    /// first onFrame call.
    func testZeroDisplacementFinishesOnFirstFrame() {
        let spring = SpringAnimation(toValue: 50, config: SpringConfig(duration: 400, dampingRatio: 1))
        spring.onStart(value: 50, now: 0, previous: .none)
        XCTAssertEqual(spring.initialEnergy, 0)
        let finished = spring.onFrame(now: 16.666)
        XCTAssertTrue(finished, "a spring starting at its target must finish on frame 1")
        XCTAssertEqual(spring.current, 50, accuracy: 1e-9)
    }

    /// Every frame's dt is clamped to 64ms - a 5 second stall must produce
    /// exactly the same result as a single 64ms step, never a jump to the
    /// full elapsed gap.
    func testDtClampIs64Milliseconds() {
        let config = SpringConfig(duration: 500, dampingRatio: 1)

        let stalled = SpringAnimation(toValue: 100, config: config)
        stalled.onStart(value: 0, now: 0, previous: .none)
        _ = stalled.onFrame(now: 5000)

        let stepped = SpringAnimation(toValue: 100, config: config)
        stepped.onStart(value: 0, now: 0, previous: .none)
        _ = stepped.onFrame(now: 64)

        XCTAssertEqual(stalled.current, stepped.current, accuracy: 1e-9)
        XCTAssertEqual(stalled.velocity, stepped.velocity, accuracy: 1e-9)
    }

    /// withTiming runs on absolute elapsed time (`now - startTime`), so a
    /// stall is caught up rather than losing the missed distance - unlike
    /// a spring's per-frame dt integration.
    func testTimingCatchesUpAfterStall() {
        let timing = TimingAnimation(toValue: 100, config: TimingConfig(duration: 300, easing: { Easing.linear($0) }))
        timing.onStart(value: 0, now: 0, previous: .none)
        _ = timing.onFrame(now: 16.666)
        let firstStep = timing.current
        XCTAssertGreaterThan(firstStep, 0)

        // a long stall, then resuming - current must reflect the FULL
        // elapsed time (500ms / 300ms duration => already past toValue),
        // not a 64ms-clamped crawl the way a spring would.
        _ = timing.onFrame(now: 500)
        XCTAssertEqual(timing.current, 100, accuracy: 1e-9, "500ms elapsed on a 300ms timing must already be at rest")
    }

    // MARK: - JS number rules (truthiness/orZero), one spot per test, NaN input

    /// isTriggeredTwice reads `previousAnimation?.lastTimestamp &&
    /// previousAnimation?.startTimestamp` - plain JS truthiness. A NaN
    /// timestamp must be treated as falsy (never triggered twice), not as
    /// truthy the way a plain `!= 0` check would (every `!=` comparison
    /// with NaN is true).
    func testIsTriggeredTwiceTreatsANaNTimestampAsFalsyNotTruthy() {
        let config = SpringConfig(duration: 500, dampingRatio: 0.8)
        let first = SpringAnimation(toValue: 100, config: config)
        // now: .nan poisons both first.lastTimestamp and first.startTimestamp.
        first.onStart(value: 0, now: .nan, previous: .none)

        let second = SpringAnimation(toValue: 100, config: config)
        second.onStart(value: first.current, now: 10, previous: .some(first))

        XCTAssertEqual(second.startTimestamp, 10, "a NaN previous timestamp must not count as truthy - this retarget gets a fresh start time, not first's NaN")
    }

    /// The triggered-twice copy of zeta/omega0/omega1 has its own `|| 0`
    /// fallback in the original (`previousAnimation?.zeta || 0`), not just
    /// on whatever fed the original computation - a NaN zeta must not
    /// propagate through the copy itself.
    func testTriggeredTwiceCopyOfZetaFallsBackToZeroOnNaN() {
        // dampingRatio: .nan on a `useDuration` spring passes straight
        // through `checkIfConfigIsValid` (`NaN <= 0` is false, same as JS)
        // and becomes `zeta` directly in the non-triggered-twice branch.
        let poisoned = SpringAnimation(toValue: 100, config: SpringConfig(duration: 500, dampingRatio: .nan))
        poisoned.onStart(value: 0, now: 10, previous: .none)
        XCTAssertTrue(poisoned.zeta.isNaN, "sanity: the poisoned spring really does carry a NaN zeta")

        // Same toValue, valid nonzero timestamps - isTriggeredTwice is true,
        // so the retarget copies `poisoned.zeta` rather than computing fresh.
        let retarget = SpringAnimation(toValue: 100, config: SpringConfig(duration: 500, dampingRatio: 0.8))
        retarget.onStart(value: poisoned.current, now: 20, previous: .some(poisoned))

        XCTAssertEqual(retarget.zeta, 0, "the copy itself falls back to 0 on a NaN zeta, not just the computation that fed it")
    }

    /// The animation object's own initial `velocity` field (spring.ts:
    /// `velocity: config.velocity || 0`, in the object literal, before
    /// `onStart` ever runs) has the same fallback - reachable directly off
    /// a freshly constructed SpringAnimation.
    func testInitialVelocityFallsBackToZeroOnNaNConfigVelocityBeforeOnStart() {
        let spring = SpringAnimation(toValue: 100, config: SpringConfig(velocity: .nan))
        XCTAssertEqual(spring.velocity, 0, "a NaN config.velocity must not survive into the animation object's own initial velocity")
    }

    /// TimingAnimation's continuity check reads `previousTiming.startTime`
    /// truthy, not `!= 0` - a NaN startTime must not count as truthy and
    /// wrongly continue a timeline.
    func testTimingContinuityCheckTreatsANaNStartTimeAsFalsyNotTruthy() {
        let first = TimingAnimation(toValue: 100, config: TimingConfig(duration: 300, easing: { Easing.linear($0) }))
        first.onStart(value: 0, now: .nan, previous: .none) // poisons first.startTime

        let second = TimingAnimation(toValue: 100, config: TimingConfig(duration: 300, easing: { Easing.linear($0) }))
        second.onStart(value: first.current, now: 20, previous: .some(first))

        XCTAssertEqual(second.startTime, 20, "a NaN previous startTime must not count as truthy - this continues from a fresh start time, not first's NaN")
    }

    /// withTiming's own default easing IS inOut(quad), not linear.
    func testInOutQuadValues() {
        // hand-computed from Easing.ts's own inOut(quad): t<0.5 => quad(2t)/2, else 1 - quad(2(1-t))/2
        XCTAssertEqual(Easing.inOutQuad(0), 0, accuracy: 1e-12)
        XCTAssertEqual(Easing.inOutQuad(0.25), 0.125, accuracy: 1e-12) // quad(0.5)/2 = 0.25/2
        XCTAssertEqual(Easing.inOutQuad(0.5), 0.5, accuracy: 1e-12) // symmetry midpoint
        XCTAssertEqual(Easing.inOutQuad(0.75), 0.875, accuracy: 1e-12) // 1 - quad(0.5)/2 = 1 - 0.125
        XCTAssertEqual(Easing.inOutQuad(1), 1, accuracy: 1e-12)
        XCTAssertEqual(Easing.linear(0.37), 0.37, accuracy: 1e-12)
    }
}
