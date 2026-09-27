/// Ported from react-native-reanimated@4.5.0 src/animation/sequence.ts (MIT,
/// Software Mansion) - see THIRD-PARTY-NOTICES.md.
///
/// Two deliberate simplifications:
/// - Reduce Motion is not handled here - the
///   original's `findNextNonReducedMotionAnimationIndex` skip-ahead is
///   omitted, so this is a plain `+ 1` advance.
/// - Reanimated lets each animation in the list carry its own completion
///   callback, fired individually as that leg finishes. TabPetMotion has no
///   per-animation callback field on `MotionAnimation` - MotionTrack's
///   single completion covers the whole composed animation - so that
///   per-leg callback plumbing has no counterpart here. The fixtures that
///   cover this type attach a callback to the top-level animation only,
///   never to an individual leg.
@MainActor
package final class SequenceAnimation: MotionAnimation {
    package private(set) var current: Double
    package var hasBeenStepped = false
    package let isHigherOrder = true
    package var cancelled = false

    private var animationIndex = 0
    private let animations: [MotionAnimation]

    /// sequence.ts's own "no animation was provided" fallback (it logs a
    /// warning there is no logger here to route to) is a trivial animation
    /// that starts at whatever value it's given and finishes immediately -
    /// never a trap, since the library never traps a host app over a call
    /// site's mistake.
    package init(_ animations: [MotionAnimation]) {
        self.animations = animations
        self.current = animations.first?.current ?? 0
    }

    package convenience init(_ animations: MotionAnimation...) {
        self.init(animations)
    }

    package func onStart(value: Double, now: Double, previous: ReplacedAnimation) {
        current = value
        guard !animations.isEmpty else {
            return
        }
        animationIndex = 0
        // sequence.ts: `previousAnimation === undefined` falls back to the
        // sequence's OWN last leg as the "previous" its first leg sees -
        // but ONLY for `undefined` (repeat.ts restarting a Sequence, whose
        // animation object has no `.previousAnimation` field). A genuinely
        // fresh start (JS `null`, MotionTrack's very first start on a
        // value) is left as `.none` and reaches the first leg's own
        // onStart unchanged.
        let effectivePrevious: ReplacedAnimation
        if case .absent = previous {
            effectivePrevious = .some(animations[animations.count - 1])
        } else {
            effectivePrevious = previous
        }
        let currentAnimation = animations[animationIndex]
        currentAnimation.onStart(value: value, now: now, previous: effectivePrevious)
        current = currentAnimation.current
    }

    package func onFrame(now: Double) -> Bool {
        guard !animations.isEmpty else {
            return true
        }
        // A sequence asked for a frame after it already finished (a call-
        // site mistake - nothing in MotionTrack's own tick loop does this)
        // returns true and does nothing further; the library never traps.
        guard animationIndex < animations.count else {
            return true
        }
        let currentAnim = animations[animationIndex]
        let finished = currentAnim.onFrame(now: now)
        current = currentAnim.current
        if finished {
            // sequence.ts: `currentAnim.finished = true`, set on the leg
            // that just finished before ever advancing - a later leg that
            // inherits this one as `previous` (a Delay's own hasBeenStepped
            // check) must see it as already stepped. Kept for parity with
            // the original; no leg type this module ships (Timing, Spring,
            // Delay, Repeat) reads a finished child's hasBeenStepped again,
            // so no test can observe this line doing anything.
            currentAnim.hasBeenStepped = true
            animationIndex += 1
            if animationIndex < animations.count {
                let nextAnim = animations[animationIndex]
                nextAnim.onStart(value: currentAnim.current, now: now, previous: .some(currentAnim))
                return false
            }
            return true
        }
        return false
    }
}
