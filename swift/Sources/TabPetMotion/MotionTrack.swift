/// Ported from react-native-reanimated@4.5.0 src/valueSetter.ts (MIT,
/// Software Mansion) - see THIRD-PARTY-NOTICES.md. One composed animation
/// per animated value (an x, a seatY, a hop...), playing the role
/// valueSetter.ts plays for one `SharedValue`: starting a new animation
/// cancels whatever was running (completion false) before the new one's
/// onStart runs, so a retarget still sees the outgoing animation's live
/// state (a SpringAnimation's velocity inheritance) through the `previous`
/// argument - and a plain spring or timing whose target already equals the
/// current value completes true at once and never starts, same short
/// circuit valueSetter.ts takes to avoid re-triggering a no-op animation.
/// The track owns its own value: `start` always begins from whatever the
/// track itself currently holds (`mutable.value` in the original), never
/// from a value the caller hands in - see `MotionEngine.start`/`.set`.
///
/// Deliberate differences from the original, one line each:
/// - `set` and a fresh track both refuse a non-finite value outright,
///   reported through `onError`, rather than storing it.
/// - A track older than `maxAgeMs` (10s default, per-`start` override) is
///   force-completed false (isLoop exempt), its completion cleared right
///   there so a later cancel, set or start never fires it again.
/// - A track can be removed outright (`MotionEngine.remove`); the original
///   has no such lifecycle at all - a SharedValue is just garbage collected.
/// - Completions queued while MotionEngine.tick steps every track all run
///   only after every track in that tick has been stepped, never
///   interleaved with the stepping itself.
/// - The one that needs the longer explanation: if the completion fired
///   while cancelling the outgoing animation reentrantly starts ANOTHER
///   animation on this same track, the original leaves both writing the
///   value (valueSetter.ts's own `mutable._animation = animation`
///   assignment happens AFTER `onStart`, so a reentrant call's own
///   assignment gets silently overwritten while its still-queued
///   `requestAnimationFrame` callback keeps firing anyway). Here the OUTER
///   start always wins: the reentrant one is cancelled the same way
///   (completion false) and handed to the outer's `onStart` as the
///   animation it replaced. Nesting is bounded at 8; beyond that `onError`
///   reports `.nestingOverflow` instead of recursing further, and the new
///   completion is still called, with false, before `start` returns.
///
/// `init`, `start` and `cancel` are internal, not `package`: only
/// MotionEngine (this same target) may drive a track. Another target that
/// merely holds a reference (a future UIKit layer) can read `currentValue`,
/// `isActive`, `label` and `onError`, but cannot start or cancel anything
/// directly - only MotionEngine may, so the clock's `wantsFrames` hint
/// never goes stale.
@MainActor
package final class MotionTrack {
    private static let maxNestDepth = 8

    /// TS has no such limit; MotionEngine force-completes a non-loop track
    /// older than this unless a `start` call overrides it per-call.
    package static let defaultMaxAgeMs: Double = 10_000

    package let label: String
    package private(set) var isActive = false
    /// The age-out ceiling this track's most recent `start` was given -
    /// MotionEngine.tick reads this per track instead of one shared limit,
    /// so a long-running leg (a slow animal's run) can outlive the default.
    private(set) var maxAgeMs: Double = MotionTrack.defaultMaxAgeMs

    /// Reported for a guard that trips inside `start` itself (nesting past
    /// `maxNestDepth`) - the tick-time guards (a non-finite frame, the 10s
    /// age-out) are reported by MotionEngine directly from `step`'s own
    /// outcome instead, since those only ever happen from inside a tick
    /// MotionEngine already owns.
    package var onError: ((MotionError) -> Void)?

    /// Set once by `MotionEngine.remove` - see MotionEngine.remove's doc.
    /// Reanimated has no equivalent (a SharedValue is just garbage
    /// collected); this is TabPetMotion's own lifecycle addition.
    private(set) var isRemoved = false

    private var isLoop = false
    private var animation: MotionAnimation?
    private var completion: ((Bool) -> Void)?
    private var startedAt: Double = 0
    private var lastFiniteValue: Double
    private var nestDepth = 0

    /// The track's current value: the running animation's live `current`
    /// while active, or the last known-good value once a guard has
    /// cancelled it (the non-finite guard's "restored to its last finite
    /// value" - the corrupted animation is discarded, never read again).
    /// Never the target of an animation that has not started.
    package var currentValue: Double {
        animation?.current ?? lastFiniteValue
    }

    /// A non-finite `initialValue` is refused, same as `set` - the track's
    /// held value is an invariant that is always finite; a fresh track
    /// falls back to 0. MotionEngine.makeTrack reports the refusal (it has
    /// the label; this initializer runs before `onError` is even wired up).
    init(label: String, initialValue: Double = 0) {
        self.label = label
        self.lastFiniteValue = initialValue.isFinite ? initialValue : 0
    }

    func markRemoved() {
        isRemoved = true
        cancel()
    }

    /// valueSetter.ts's cancellation phase, factored out for `start`,
    /// `cancel` and `set` to share: unconditional whenever an animation (or
    /// its stale, already-fired-true-but-never-cleared reference) is held -
    /// `previousAnimation.cancelled = true; previousAnimation.callback?.(false);
    /// mutable._animation = null;`. Setting `cancelled` on the discarded
    /// animation itself is what stops a completion(true) MotionEngine's tick
    /// has already queued for it (this same tick, but earlier in the queue)
    /// from reaching a host after this point - see MotionAnimation.cancelled.
    /// Returns whatever was discarded, so `start` can hand it on as the
    /// animation the new one replaces.
    @discardableResult
    private func cancelHeldAnimation() -> MotionAnimation? {
        guard let discarded = animation else {
            return nil
        }
        discarded.cancelled = true
        let firedCompletion = completion
        animation = nil
        completion = nil
        isActive = false
        firedCompletion?(false)
        return discarded
    }

    /// Starts `newAnimation` at time `now`, from whatever value this track
    /// currently holds. `isLoop` exempts this track from the 10s
    /// force-complete guard (the sprite busy loop) until the next `start`.
    func start(
        _ newAnimation: MotionAnimation,
        now: Double,
        isLoop: Bool = false,
        maxAgeMs: Double = MotionTrack.defaultMaxAgeMs,
        completion newCompletion: ((Bool) -> Void)? = nil
    ) {
        nestDepth += 1
        defer { nestDepth -= 1 }
        guard nestDepth <= Self.maxNestDepth else {
            newCompletion?(false)
            onError?(.nestingOverflow)
            return
        }
        // Fires first - may reentrantly call `start`/`cancel`/`set` on this
        // same track.
        let outgoingAnimation = cancelHeldAnimation()

        // The one deliberate difference from the original - see the header
        // comment: whatever the completion fired just above started on this
        // track (if anything) is what THIS start replaces, not whatever was
        // actually running before this call began.
        let replaced = cancelHeldAnimation() ?? outgoingAnimation
        let effectiveValue = lastFiniteValue

        // valueSetter.ts: a plain spring/timing (never a delay/sequence/
        // repeat) whose target already equals the current value completes
        // true at once - onStart/onFrame never run.
        if !newAnimation.isHigherOrder, effectiveValue == newAnimation.current {
            newCompletion?(true)
            return
        }

        // Assigned here, after the outgoing completion above may have
        // reentrantly started its own animation on this track - a reentrant
        // call's own maxAgeMs must not leak into this outer call's ceiling.
        self.maxAgeMs = maxAgeMs
        animation = newAnimation
        completion = newCompletion
        startedAt = now
        self.isLoop = isLoop
        isActive = true
        newAnimation.onStart(value: effectiveValue, now: now, previous: replaced.map(ReplacedAnimation.some) ?? .none)

        // valueSetter.ts runs one frame synchronously at the same timestamp
        // right after onStart, before ever returning to its caller - if
        // that frame finishes the animation, its completion runs with true
        // before `start` returns.
        switch step(now: now, maxAgeMs: .infinity) {
        case .active:
            break
        case .finished(_, let firedCompletion):
            firedCompletion?(true)
        case .nonFinite(let error, let firedCompletion):
            firedCompletion?(false)
            onError?(error)
        case .timedOut:
            break // can't happen: startedAt == now
        }
    }

    /// Cancels whatever this track holds, firing its completion with
    /// false - even an animation that already finished naturally (its
    /// completion already fired true), since a natural finish never clears
    /// the stored animation/completion (only this cancellation, or the
    /// next `start`, does). Mirrors `cancelAnimation`'s own mechanism:
    /// `sharedValue.value = sharedValue.value` (animation/util.ts) runs
    /// through this same unconditional cancellation before the plain-value
    /// branch's same-value short circuit discards the write itself - so
    /// cancelling is ALL `cancelAnimation` actually does. A true no-op if
    /// nothing is held (a fresh track, or one already cancelled/replaced).
    func cancel() {
        cancelHeldAnimation()
    }

    /// valueSetter.ts's plain-value branch: cancellation is unconditional
    /// (`cancelHeldAnimation`), then the value itself is written only if it
    /// is finite - a non-finite value is refused outright and reported,
    /// the same invariant `init` enforces, rather than the JS original's
    /// `mutable._value = value` (which would happily store a NaN).
    func set(_ value: Double) {
        cancelHeldAnimation()
        guard value.isFinite else {
            onError?(.nonFiniteValue)
            return
        }
        lastFiniteValue = value
    }

    /// Advances one tick. Never called on an inactive track - MotionEngine
    /// only steps its active snapshot (`start` also calls this once,
    /// synchronously, for the animation's first frame).
    ///
    /// A normal finish or age-out does NOT clear `animation`/`completion` -
    /// valueSetter.ts never nulls `mutable._animation`/`.callback` just
    /// because a tick finished it; only the NEXT `start`'s own cancellation
    /// phase does (which is exactly what makes an already-finished
    /// animation's completion able to fire AGAIN, with false, if another
    /// animation replaces it later - real behaviour, proven by the
    /// `track` fixture cases). The non-finite guard is the one exception:
    /// the corrupted animation and its completion are discarded outright,
    /// never read again.
    func step(now: Double, maxAgeMs: Double) -> TrackStepOutcome {
        guard isActive, let animation else {
            return .active
        }
        if !isLoop, now - startedAt > maxAgeMs {
            // Unlike a natural finish (which never clears `completion` - a
            // later cancel/set/start can fire it again, real behaviour
            // proven by the `track` fixtures), the age-out guard is
            // TabPetMotion's own addition with no such fixture behind it:
            // its completion is cleared here so it fires with false exactly
            // once, never a second time from a later cancel, set or start.
            let firedCompletion = completion
            completion = nil
            isActive = false
            return .timedOut(completion: firedCompletion)
        }
        let finished = animation.onFrame(now: now)
        // valueSetter.ts sets this unconditionally after every step of the
        // top-level animation, regardless of `finished` - see
        // MotionAnimation.hasBeenStepped.
        animation.hasBeenStepped = true
        if !animation.current.isFinite {
            let firedCompletion = completion
            self.animation = nil
            self.completion = nil
            isActive = false
            return .nonFinite(error: .nonFiniteValue, completion: firedCompletion)
        }
        lastFiniteValue = animation.current
        if finished {
            isActive = false
            return .finished(animation: animation, completion: completion)
        }
        return .active
    }
}
