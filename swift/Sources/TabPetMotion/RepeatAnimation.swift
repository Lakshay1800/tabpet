/// Ported from react-native-reanimated@4.5.0 src/animation/repeat.ts (MIT,
/// Software Mansion) - see THIRD-PARTY-NOTICES.md.
///
/// Reduce Motion is not part of this engine - the
/// original's `animation.reduceMotion` early-stop is omitted.
///
/// SURPRISING, kept as-is: on every rep restart, repeat.ts starts the
/// wrapped animation with `nextAnimation.previousAnimation` as its
/// `previous` argument. That field only exists on a DelayAnimation's
/// animation object (Timing/SpringAnimation/SequenceAnimation never carry
/// it) - so for the TimingAnimation/SpringAnimation this repeats, that read
/// is JS `undefined`, never `null`: every rep restart is
/// `.absent`, not `.none`. No velocity or timeline continuity carries
/// across reps, by construction of the original, not by a simplification
/// made here. SequenceAnimation is the only thing downstream that treats
/// `.absent`/`.none` differently, and `next` here is never a Sequence
/// (MotionTargetedAnimationWritable requires a settable `toValue`, which
/// Sequence doesn't have).
@MainActor
package final class RepeatAnimation: MotionAnimation {
    package private(set) var current: Double
    package var hasBeenStepped = false
    package let isHigherOrder = true
    package var cancelled = false

    private var reps = 0
    private var startValue: Double = 0

    private let next: MotionTargetedAnimationWritable
    private let numberOfReps: Int
    private let reverse: Bool

    // Not `package`: a `package` initializer cannot take an internal-only
    // parameter type, and `MotionTargetedAnimationWritable` is internal on
    // purpose (see MotionAnimation.swift). Building a RepeatAnimation is a
    // within-module operation; another target can still hold and drive the
    // result through the plain `MotionAnimation` it conforms to.
    init(_ next: MotionTargetedAnimationWritable, numberOfReps: Int = 2, reverse: Bool = false) {
        self.next = next
        self.numberOfReps = numberOfReps
        self.reverse = reverse
        self.current = next.current
    }

    package func onStart(value: Double, now: Double, previous: ReplacedAnimation) {
        startValue = value
        reps = 0
        next.onStart(value: value, now: now, previous: previous)
        current = next.current
    }

    package func onFrame(now: Double) -> Bool {
        let finished = next.onFrame(now: now)
        current = next.current
        guard finished else {
            return false
        }
        reps += 1
        if numberOfReps > 0 && reps >= numberOfReps {
            return true
        }
        let restartValue = reverse ? next.current : startValue
        if reverse {
            next.toValue = startValue
            startValue = restartValue
        }
        next.onStart(value: restartValue, now: now, previous: .absent)
        return false
    }
}
