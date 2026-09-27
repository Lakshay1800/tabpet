import Foundation
import TabPetCore

/// Optional clamp bounds for `scaleZetaToMatchClamps` - a spring with
/// `clamp` set widens its damping ratio just enough to keep the trajectory
/// inside `min`/`max`. None of the six shipped animal profiles use this, but
/// it is part of the port.
package struct SpringClamp: Equatable, Sendable {
    package var min: Double?
    package var max: Double?

    package init(min: Double? = nil, max: Double? = nil) {
        self.min = min
        self.max = max
    }
}

/// Mirrors react-native-reanimated's `SpringConfig` (spring/springConfigs.ts).
/// Every field is optional because the real defaults - GentleSpringConfig
/// (mass 4, damping 120, stiffness 900) merged with
/// GentleSpringConfigWithDuration (duration 550, dampingRatio 1) - apply
/// only to whatever the caller omits; see SpringAnimation.resolve.
package struct SpringConfig: Equatable, Sendable {
    package var mass: Double?
    package var damping: Double?
    package var stiffness: Double?
    package var duration: Double?
    package var dampingRatio: Double?
    package var velocity: Double?
    package var overshootClamping: Bool?
    package var energyThreshold: Double?
    package var clamp: SpringClamp?

    package init(
        mass: Double? = nil,
        damping: Double? = nil,
        stiffness: Double? = nil,
        duration: Double? = nil,
        dampingRatio: Double? = nil,
        velocity: Double? = nil,
        overshootClamping: Bool? = nil,
        energyThreshold: Double? = nil,
        clamp: SpringClamp? = nil
    ) {
        self.mass = mass
        self.damping = damping
        self.stiffness = stiffness
        self.duration = duration
        self.dampingRatio = dampingRatio
        self.velocity = velocity
        self.overshootClamping = overshootClamping
        self.energyThreshold = energyThreshold
        self.clamp = clamp
    }
}

/// Fully-defaulted spring config, mirroring springConfigs.ts's
/// `DefaultSpringConfig & SpringConfigInner`. `stiffness` is mutated in
/// place once per onStart when `useDuration` is true - `spring.ts`'s own
/// `config.stiffness = stiffness` after `calculateNewStiffnessToMatchDuration`.
private struct ResolvedSpringConfig {
    var mass: Double
    var damping: Double
    var stiffness: Double
    var duration: Double
    var dampingRatio: Double
    var velocity: Double
    var overshootClamping: Bool
    var energyThreshold: Double
    var clamp: SpringClamp?
    var useDuration: Bool
    var skipAnimation: Bool
}

/// Ported from react-native-reanimated@4.5.0 src/animation/spring/{spring.ts,
/// springUtils.ts} (MIT, Software Mansion) - see THIRD-PARTY-NOTICES.md.
///
/// The stiffness is solved at every start (`calculateNewStiffnessToMatchDuration`)
/// from the starting displacement and velocity, not fixed per config - a
/// `{duration, dampingRatio}` spring is not a `CASpringAnimation`. A retarget
/// inherits the previous spring's velocity (clipped to 0 if it now points
/// away from the new target) whenever a previous animation is passed to
/// `onStart`, independent of `isTriggeredTwice`. A spring starting at its
/// own target (displacement 0) has `initialEnergy == 0` and terminates on
/// its very first frame. Every frame's dt is clamped to 64ms (`dtClampMs`),
/// so a spring slows down rather than jumping after a stall.
@MainActor
package final class SpringAnimation: MotionTargetedAnimationWritable {
    private static let dtClampMs: Double = 64
    private static let defaultMass: Double = 4
    private static let defaultDamping: Double = 120
    private static let defaultStiffness: Double = 900
    private static let defaultDuration: Double = 550
    private static let defaultDampingRatio: Double = 1
    private static let defaultEnergyThreshold: Double = 6e-9

    package internal(set) var toValue: Double
    package private(set) var current: Double
    package var hasBeenStepped = false
    package let isHigherOrder = false
    package var cancelled = false

    private(set) var velocity: Double
    private(set) var startValue: Double = 0
    private(set) var zeta: Double = 0
    private(set) var omega0: Double = 0
    private(set) var omega1: Double = 0
    private(set) var initialEnergy: Double = 0
    private(set) var lastTimestamp: Double = 0
    private(set) var startTimestamp: Double = 0

    private var config: ResolvedSpringConfig

    package init(toValue: Double, config: SpringConfig = SpringConfig()) {
        self.toValue = toValue
        self.config = Self.resolve(config)
        self.current = toValue
        // spring.ts's own animation-object literal: `velocity: config.velocity || 0`.
        self.velocity = Self.orZero(self.config.velocity)
    }

    private static func resolve(_ user: SpringConfig) -> ResolvedSpringConfig {
        var resolved = ResolvedSpringConfig(
            mass: user.mass ?? defaultMass,
            damping: user.damping ?? defaultDamping,
            stiffness: user.stiffness ?? defaultStiffness,
            duration: user.duration ?? defaultDuration,
            dampingRatio: user.dampingRatio ?? defaultDampingRatio,
            // safeMergeConfigs only filters `undefined` - it keeps a raw 0
            // or NaN user.velocity as-is; the `|| 0` truthy fallback JS
            // applies happens at each point of USE (onStart), not here.
            velocity: user.velocity ?? 0,
            overshootClamping: user.overshootClamping ?? false,
            energyThreshold: user.energyThreshold ?? defaultEnergyThreshold,
            clamp: user.clamp,
            // spring.ts: `!!(userConfig?.duration || userConfig?.dampingRatio)` -
            // read from the CALLER's raw values, never the defaulted ones.
            useDuration: isTruthy(user.duration) || isTruthy(user.dampingRatio),
            skipAnimation: false
        )
        resolved.skipAnimation = !checkIfConfigIsValid(resolved)
        if resolved.duration == 0 {
            resolved.skipAnimation = true
        }
        return resolved
    }

    /// Delegates to JSMath's JS-truthiness helpers (shared with
    /// TimingAnimation's own continuity check) - see JSMath.isTruthy/orZero.
    private static func isTruthy(_ value: Double) -> Bool {
        JSMath.isTruthy(value)
    }

    private static func isTruthy(_ value: Double?) -> Bool {
        guard let value else {
            return false
        }
        return isTruthy(value)
    }

    private static func orZero(_ value: Double) -> Double {
        JSMath.orZero(value)
    }

    private static func checkIfConfigIsValid(_ config: ResolvedSpringConfig) -> Bool {
        var valid = true
        for value in [config.stiffness, config.damping, config.dampingRatio, config.mass, config.energyThreshold] {
            if value <= 0 {
                valid = false
            }
        }
        if config.duration < 0 {
            valid = false
        }
        if let clamp = config.clamp, let min = clamp.min, let max = clamp.max, isTruthy(min), isTruthy(max), min > max {
            valid = false
        }
        return valid
    }

    private static func getEnergy(displacement: Double, velocity: Double, stiffness: Double, mass: Double) -> Double {
        let potentialEnergy = 0.5 * stiffness * displacement * displacement
        let kineticEnergy = 0.5 * mass * velocity * velocity
        return potentialEnergy + kineticEnergy
    }

    private static func initialCalculations(
        stiffness: Double,
        config: ResolvedSpringConfig
    ) -> (zeta: Double, omega0: Double, omega1: Double) {
        if config.skipAnimation {
            return (0, 0, 0)
        }
        if config.useDuration {
            let m = config.mass
            let zeta = config.dampingRatio
            let omega0 = (stiffness / m).squareRoot()
            let omega1 = zeta < 1 ? omega0 * (1 - zeta * zeta).squareRoot() : 0
            return (zeta, omega0, omega1)
        }
        let c = config.damping
        let m = config.mass
        let k = config.stiffness
        let zeta = c / (2 * (k * m).squareRoot())
        let omega0 = (k / m).squareRoot()
        let omega1 = zeta < 1 ? omega0 * (1 - zeta * zeta).squareRoot() : 0
        return (zeta, omega0, omega1)
    }

    /// bisectRoot (springUtils.ts): bisection over `[min, max]` for the root
    /// of `f`, `maxIterations` steps or until `|f(current)| <= precision`.
    private static func bisectRoot(
        min: Double,
        max: Double,
        precision: Double,
        maxIterations: Int,
        _ f: (Double) -> Double
    ) -> Double {
        var lo = min
        var hi = max
        let direction = f(hi) >= f(lo) ? 1.0 : -1.0
        var iterations = maxIterations
        var current = (hi + lo) / 2
        while abs(f(current)) > precision, iterations > 0 {
            iterations -= 1
            if f(current) * direction < 0 {
                lo = current
            } else {
                hi = current
            }
            current = (lo + hi) / 2
        }
        return current
    }

    /// calculateNewStiffnessToMatchDuration (springUtils.ts) - runs BEFORE
    /// initialCalculations. Solves for the stiffness whose energy decays to
    /// `energyThreshold` at 1.5x the requested duration.
    private static func calculateNewStiffnessToMatchDuration(
        x0: Double,
        config: ResolvedSpringConfig,
        v0: Double
    ) -> Double {
        if config.skipAnimation {
            return 0
        }
        let zeta = config.dampingRatio
        let threshold = config.energyThreshold
        let m = config.mass
        let targetDuration = config.duration

        func energyDiff(forStiffness stiffness: Double) -> Double {
            let perceptualCoefficient = 1.5
            let millisecondsInSecond = 1000.0
            let settlingDuration = (targetDuration * perceptualCoefficient) / millisecondsInSecond
            let omega0 = (stiffness / m).squareRoot() * zeta
            let envelope = exp(-omega0 * settlingDuration)
            let xtk = (x0 + (v0 + x0 * omega0) * settlingDuration) * envelope
            let vtk = (x0 + (v0 + x0 * omega0) * settlingDuration) * envelope * -omega0
                + (v0 + x0 * omega0) * envelope
            let e0 = getEnergy(displacement: x0, velocity: v0, stiffness: stiffness, mass: m)
            let etk = getEnergy(displacement: xtk, velocity: vtk, stiffness: stiffness, mass: m)
            let energyFraction = etk / e0
            return energyFraction - threshold
        }

        let precision = config.energyThreshold * 1e-3
        return bisectRoot(min: .ulpOfOne, max: 8e3, precision: precision, maxIterations: 100, energyDiff(forStiffness:))
    }

    private static func criticallyDampedSpringCalculations(
        toValue: Double,
        v0: Double,
        x0: Double,
        omega0: Double,
        t: Double
    ) -> (position: Double, velocity: Double) {
        let envelope = exp(-omega0 * t)
        let position = toValue + envelope * (x0 + (v0 + omega0 * x0) * t)
        let velocity = envelope * -omega0 * (x0 + (v0 + omega0 * x0) * t) + envelope * (v0 + omega0 * x0)
        return (position, velocity)
    }

    private static func underDampedSpringCalculations(
        toValue: Double,
        zeta: Double,
        v0: Double,
        x0: Double,
        omega0: Double,
        omega1: Double,
        t: Double
    ) -> (position: Double, velocity: Double) {
        let sin1 = sin(omega1 * t)
        let cos1 = cos(omega1 * t)
        let envelope = exp(-zeta * omega0 * t)
        let frag1 = envelope * (sin1 * ((v0 + zeta * omega0 * x0) / omega1) + x0 * cos1)
        let position = toValue + frag1
        // "This looks crazy - it's actually just the derivative of the
        // oscillation function" (spring.ts's own comment on this line).
        let velocity = -zeta * omega0 * frag1 + envelope * (cos1 * (v0 + zeta * omega0 * x0) - omega1 * x0 * sin1)
        return (position, velocity)
    }

    private static func isAnimationTerminating(
        toValue: Double,
        velocity: Double,
        startValue: Double,
        current: Double,
        initialEnergy: Double,
        config: ResolvedSpringConfig
    ) -> Bool {
        if config.overshootClamping {
            let leftBound = startValue >= 0 ? toValue : toValue + startValue
            let rightBound = leftBound + abs(startValue)
            if current < leftBound || current > rightBound {
                return true
            }
        }
        let currentEnergy = getEnergy(displacement: toValue - current, velocity: velocity, stiffness: config.stiffness, mass: config.mass)
        return initialEnergy == 0 || currentEnergy / initialEnergy <= config.energyThreshold
    }

    /// "We make an assumption that we can manipulate zeta without changing
    /// duration of movement" (springUtils.ts's own comment). Uses JSMath's
    /// jsMax, not Swift's `Array.max()`: `log(ratio)` is NaN whenever a
    /// bound puts `ratio <= 0`, and `Math.max` in JS propagates that NaN
    /// through the whole comparison, while `Array.max()` (comparison-based)
    /// would silently skip it and return a real number instead.
    private static func scaleZetaToMatchClamps(zeta: Double, toValue: Double, startValue: Double, clamp: SpringClamp) -> Double {
        if startValue == 0 {
            return zeta
        }
        let (firstBound, secondBound) = startValue <= 0 ? (clamp.min, clamp.max) : (clamp.max, clamp.min)
        let relativeExtremum1 = secondBound.map { abs(($0 - toValue) / startValue) }
        let relativeExtremum2 = firstBound.map { abs(($0 - toValue) / startValue) }
        let newZeta1 = relativeExtremum1.map { abs(log($0) / Double.pi) }
        let newZeta2 = relativeExtremum2.map { abs(log($0) / (2 * Double.pi)) }
        var result = zeta
        if let newZeta1 {
            result = JSMath.jsMax(result, newZeta1)
        }
        if let newZeta2 {
            result = JSMath.jsMax(result, newZeta2)
        }
        return result
    }

    /// isTriggeredTwice (spring.ts). SURPRISING: this reads
    /// `previousAnimation.duration`/`.dampingRatio`, but spring.ts never
    /// assigns either field onto the animation object it returns - verified
    /// directly against the installed package, both are always absent - so
    /// those two comparisons are always vacuously equal and take no real
    /// part in the decision. The only conditions that actually gate this are
    /// a nonzero `previous.lastTimestamp`, a NONZERO `previous.startTimestamp`
    /// (zero is falsy in JS, so a spring whose own start happened at
    /// absolute time zero can never be "triggered twice" on its next
    /// retarget), and `toValue` equality. Kept as-is: a retarget's own
    /// duration/dampingRatio are irrelevant to whether this fires.
    private func isTriggeredTwice(previous: SpringAnimation?) -> Bool {
        guard let previous else {
            return false
        }
        // spring.ts: `previousAnimation?.lastTimestamp && previousAnimation?.startTimestamp`
        // - plain JS truthiness, not `!= 0` (which would treat a NaN
        // timestamp as truthy, since every `!=` comparison with NaN is true).
        guard Self.isTruthy(previous.lastTimestamp), Self.isTruthy(previous.startTimestamp) else {
            return false
        }
        return previous.toValue == toValue
    }

    package func onStart(value: Double, now: Double, previous: ReplacedAnimation) {
        current = value
        let previousSpring = previous.animation as? SpringAnimation
        let triggeredTwice = isTriggeredTwice(previous: previousSpring)

        let x0 = triggeredTwice ? (previousSpring?.startValue ?? 0) : value - toValue
        startValue = x0

        if previous.animation != nil {
            // spring.ts: `(triggeredTwice ? previousAnimation?.velocity :
            // previousAnimation?.velocity + config.velocity) || 0`.
            // `previousAnimation?.velocity` only exists on a SpringAnimation
            // - any other kind (Timing/Delay/Sequence) reads as JS
            // `undefined`, and `undefined + config.velocity` is NaN,
            // `NaN || 0` is 0: a spring's config velocity is silently
            // dropped whenever it follows anything that isn't itself a
            // spring, REGARDLESS of the config's own value.
            let raw: Double = if triggeredTwice, let previousSpring {
                previousSpring.velocity
            } else {
                previousSpring.map { $0.velocity + config.velocity } ?? .nan
            }
            velocity = Self.orZero(raw)
        } else {
            velocity = Self.orZero(config.velocity)
        }

        // Clip velocity that would drive the first frame away from the new
        // target - inertia is only preserved when it already points toward
        // toValue.
        if (toValue > value && velocity < 0) || (toValue < value && velocity > 0) {
            velocity = 0
        }

        if triggeredTwice, let previousSpring {
            // spring.ts: `previousAnimation?.zeta || 0` (and same for omega0/
            // omega1) - a defensive fallback on the copy itself, not just on
            // the values that fed the original computation.
            zeta = Self.orZero(previousSpring.zeta)
            omega0 = Self.orZero(previousSpring.omega0)
            omega1 = Self.orZero(previousSpring.omega1)
        } else {
            if config.useDuration {
                // spring.ts computes `actualDuration` with a `triggeredTwice
                // ? ... : duration` ternary here too, but this whole block
                // only ever runs in the `!triggeredTwice` branch already -
                // the ternary's true side is dead, so `actualDuration` is
                // always just the plain duration. Kept as a no-op rather
                // than "simplified", to match the original's control flow.
                let stiffness = Self.calculateNewStiffnessToMatchDuration(x0: x0, config: config, v0: velocity)
                config.stiffness = stiffness
            }
            let (z, o0, o1) = Self.initialCalculations(stiffness: config.stiffness, config: config)
            zeta = z
            omega0 = o0
            omega1 = o1
            if let clamp = config.clamp {
                zeta = Self.scaleZetaToMatchClamps(zeta: zeta, toValue: toValue, startValue: startValue, clamp: clamp)
            }
        }

        initialEnergy = Self.getEnergy(displacement: x0, velocity: config.velocity, stiffness: config.stiffness, mass: config.mass)
        // spring.ts: `previousAnimation?.lastTimestamp || now` - falls back
        // to `now` both when there is no previous spring and when its
        // lastTimestamp happens to be exactly 0.
        let previousLastTimestamp = previousSpring?.lastTimestamp ?? 0
        lastTimestamp = Self.isTruthy(previousLastTimestamp) ? previousLastTimestamp : now
        startTimestamp = triggeredTwice ? (previousSpring?.startTimestamp ?? now) : now
    }

    package func onFrame(now: Double) -> Bool {
        if config.skipAnimation {
            current = toValue
            lastTimestamp = 0
            return true
        }
        let deltaTime = Swift.min(Swift.max(now - lastTimestamp, 0), Self.dtClampMs)
        lastTimestamp = now

        let t = deltaTime / 1000
        let v0 = velocity
        let x0 = current - toValue

        let result: (position: Double, velocity: Double) = zeta < 1
            ? Self.underDampedSpringCalculations(toValue: toValue, zeta: zeta, v0: v0, x0: x0, omega0: omega0, omega1: omega1, t: t)
            : Self.criticallyDampedSpringCalculations(toValue: toValue, v0: v0, x0: x0, omega0: omega0, t: t)

        current = result.position
        velocity = result.velocity

        if Self.isAnimationTerminating(
            toValue: toValue,
            velocity: velocity,
            startValue: startValue,
            current: current,
            initialEnergy: initialEnergy,
            config: config
        ) {
            velocity = 0
            current = toValue
            lastTimestamp = 0
            return true
        }
        return false
    }
}
