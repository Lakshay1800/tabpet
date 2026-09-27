import TabPetCore

/// Mirrors react-native-reanimated's `TimingConfig` (animation/timing.ts).
/// `easing` defaults to `Easing.inOutQuad` - withTiming's own default
/// easing IS inOut(quad), not linear.
package struct TimingConfig: Sendable {
    package var duration: Double
    package var easing: @Sendable (Double) -> Double

    package init(duration: Double = 300, easing: @escaping @Sendable (Double) -> Double = { Easing.inOutQuad($0) }) {
        self.duration = duration
        self.easing = easing
    }
}

/// Ported from react-native-reanimated@4.5.0 src/animation/timing.ts (MIT,
/// Software Mansion) - see THIRD-PARTY-NOTICES.md.
///
/// Runs on absolute elapsed time (`now - startTime`), so it catches up
/// after a stall rather than losing the missed time, unlike a spring's
/// per-frame dt integration.
@MainActor
package final class TimingAnimation: MotionTargetedAnimationWritable {
    package internal(set) var toValue: Double
    package private(set) var current: Double
    package var hasBeenStepped = false
    package let isHigherOrder = false
    package var cancelled = false

    private(set) var startValue: Double = 0
    private(set) var startTime: Double = 0

    private let config: TimingConfig

    package init(toValue: Double, config: TimingConfig = TimingConfig()) {
        self.toValue = toValue
        self.config = config
        self.current = toValue
    }

    package func onStart(value: Double, now: Double, previous: ReplacedAnimation) {
        // Continuity check: a new timing over the same toValue as a still-
        // running timing continues its timeline instead of restarting it.
        // `previous.startTime` JS-truthy (not `!= 0`, which would treat a
        // NaN startTime as truthy) - a previous timing whose own start
        // happened at absolute time zero cannot be continued, same
        // falsy-zero quirk as SpringAnimation.isTriggeredTwice.
        if let previousTiming = previous.animation as? TimingAnimation, previousTiming.toValue == toValue, JSMath.isTruthy(previousTiming.startTime) {
            startTime = previousTiming.startTime
            startValue = previousTiming.startValue
        } else {
            startTime = now
            startValue = value
        }
        current = value
    }

    package func onFrame(now: Double) -> Bool {
        let runtime = now - startTime
        if runtime >= config.duration {
            // reset startTime to avoid reusing a finished animation's
            // timeline if the next timing over this toValue starts later
            startTime = 0
            current = toValue
            return true
        }
        let progress = config.easing(runtime / config.duration)
        current = startValue + (toValue - startValue) * progress
        return false
    }
}
