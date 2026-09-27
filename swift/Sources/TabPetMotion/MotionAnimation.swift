/// Mirrors the three states react-native-reanimated's own `previousAnimation`
/// argument can carry through valueSetter.ts and its composite animations:
/// JS `null` (nothing was previously running - a value's very first start),
/// JS `undefined` (a field read off an animation object that never defines
/// it - repeat.ts restarting a TimingAnimation/SpringAnimation/
/// SequenceAnimation, none of which carry a `.previousAnimation` field), or
/// a real animation object. sequence.ts's own fallback to its last leg fires
/// ONLY for `undefined` - `.absent` and `.none` are deliberately not the
/// same case.
package enum ReplacedAnimation {
    case none
    case absent
    case some(MotionAnimation)

    /// JS truthiness of `previousAnimation` itself - false for BOTH `null`
    /// and `undefined`, true only for a real object. SpringAnimation's own
    /// `if (previousAnimation)` branch reads this, not `.none` specifically.
    var animation: MotionAnimation? {
        if case .some(let animation) = self {
            return animation
        }
        return nil
    }
}

/// A composed animation exactly as MotionTrack drives it - mirrors the shape
/// of a Reanimated animation object (onStart/onFrame/current) closely
/// enough that a retarget's velocity inheritance only has to special-case
/// SpringAnimation, the same way spring.ts's own `isTriggeredTwice` does.
@MainActor
package protocol MotionAnimation: AnyObject {
    /// The animated value, valid once `onStart` has run.
    var current: Double { get }

    /// Set to true by whatever drove this animation's onFrame directly -
    /// MotionTrack, on the top-level animation, after every step regardless
    /// of that step's own return value (ports valueSetter.ts's
    /// `animation.finished = true`); ALSO set by SequenceAnimation on
    /// whichever child just finished, before it advances to the next leg
    /// (ports sequence.ts's own `currentAnim.finished = true`) - a composite
    /// ticking its own children is not exempt. Its real meaning is "has
    /// been stepped at least once", not "is finished" - DelayAnimation
    /// reads it on the animation it replaces to decide whether it needs to
    /// tick that animation at all.
    var hasBeenStepped: Bool { get set }

    /// True for DelayAnimation/SequenceAnimation/RepeatAnimation (composites
    /// with no target of their own) - mirrors the real animation object's
    /// own `isHigherOrder` flag. MotionTrack's start-time short circuit
    /// reads this: a plain SpringAnimation/TimingAnimation whose target
    /// already equals the current value completes immediately and never
    /// starts at all; a composite always starts.
    var isHigherOrder: Bool { get }

    /// Set true by whatever cancels the animation this instance is - ports
    /// the original's own `animation.cancelled` flag (valueSetter.ts), whose
    /// `step` closure checks it before ever calling `onFrame` again.
    /// MotionEngine's own tick queues a `.finished` completion to run only
    /// AFTER every track has stepped, so a track's queued completion can run
    /// after a LATER completion in that same tick already cancelled it
    /// (started, set, removed or cancelled it) - the tick checks this flag
    /// right before firing that queued completion, so a host is never told
    /// "true" for an animation that was, by then, already cancelled.
    var cancelled: Bool { get set }

    /// Starts (or restarts) this animation at `value`, at time `now`.
    /// `previous` is the animation MotionTrack is replacing on this tick, if
    /// any - a SpringAnimation reads it to inherit velocity; everything
    /// else mostly ignores it, same as the TypeScript source.
    func onStart(value: Double, now: Double, previous: ReplacedAnimation)

    /// Advances to `now` and returns true once the animation has reached
    /// its rest state. Must not be called again after returning true -
    /// well-behaved callers (MotionTrack) simply stop; a composite that IS
    /// driven further (a call-site mistake) returns true and does nothing
    /// further. The library never traps a host app over this.
    func onFrame(now: Double) -> Bool
}

/// A `MotionAnimation` with a single target - `SpringAnimation` and
/// `TimingAnimation` conform; `DelayAnimation` and `SequenceAnimation`
/// (composites with no single target of their own) do not. Read-only at
/// this access level on purpose - see `MotionTargetedAnimationWritable`.
@MainActor
package protocol MotionTargetedAnimation: MotionAnimation {
    var toValue: Double { get }
}

/// The write side of `toValue`, kept out of the package-visible protocol:
/// only `RepeatAnimation`'s `reverse` mode ever needs to WRITE it (repeat.ts
/// mutates the wrapped animation's `toValue` directly between reps -
/// `nextAnimation.toValue = animation.startValue` - rather than building a
/// new animation each cycle), and that's a detail internal to this module,
/// not something a host or another target should be able to do to a
/// targeted animation it merely holds a reference to.
protocol MotionTargetedAnimationWritable: MotionTargetedAnimation {
    var toValue: Double { get set }
}
