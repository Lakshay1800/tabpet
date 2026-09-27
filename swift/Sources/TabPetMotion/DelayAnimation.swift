/// Ported from react-native-reanimated@4.5.0 src/animation/delay.ts (MIT,
/// Software Mansion) - see THIRD-PARTY-NOTICES.md.
///
/// A delay does NOT keep animating the animation it replaces while it
/// waits: valueSetter.ts sets `hasBeenStepped` (its real field is named
/// `finished`, meaning "has been stepped", not "is finished" - see
/// MotionAnimation.hasBeenStepped) on the top-level animation after EVERY
/// step, so by the time an animation is replaced by a delay it has almost
/// always already been ticked at least once as the top-level animation -
/// its flag is already true. `onFrame` below reads that flag before ever
/// calling the replaced animation's own `onFrame`: the replaced animation
/// is ticked at most once more (only if it had somehow never been stepped
/// before being replaced), and the value HOLDS at whatever it was for the
/// rest of the delay.
///
/// One deliberate simplification: Reduce Motion is not handled here - the
/// original's `|| animation.reduceMotion` early-exit is omitted.
@MainActor
package final class DelayAnimation: MotionAnimation {
    package private(set) var current: Double
    package var hasBeenStepped = false
    package let isHigherOrder = true
    package var cancelled = false

    private let delayMs: Double
    private let next: MotionAnimation
    private var startTime: Double = 0
    private var started = false
    private var replaced: ReplacedAnimation = .none

    package init(_ delayMs: Double, _ next: MotionAnimation) {
        self.delayMs = delayMs
        self.next = next
        self.current = next.current
    }

    package func onStart(value: Double, now: Double, previous: ReplacedAnimation) {
        startTime = now
        started = false
        current = value
        // delay.ts's own self-reference guard: if MotionTrack ever hands
        // this SAME DelayAnimation instance back as its own `previous` (a
        // same-object retarget), inherit whatever IT was itself waiting on
        // rather than treating itself as the thing to catch up on.
        if case .some(let previousAnimation) = previous, previousAnimation === self {
            // already `self.replaced` - leave it alone rather than
            // treating this same instance as the thing to catch up on.
        } else {
            replaced = previous
        }
    }

    package func onFrame(now: Double) -> Bool {
        if now - startTime >= delayMs {
            if !started {
                next.onStart(value: current, now: now, previous: replaced)
                replaced = .none
                started = true
            }
            let finished = next.onFrame(now: now)
            current = next.current
            return finished
        }
        if case .some(let replacedAnimation) = replaced {
            let finished = replacedAnimation.hasBeenStepped || replacedAnimation.onFrame(now: now)
            current = replacedAnimation.current
            if finished {
                replaced = .none
            }
        }
        return false
    }
}
