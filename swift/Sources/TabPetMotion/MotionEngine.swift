/// Errors MotionEngine reports through its `onError` callback. Never thrown
/// across a host boundary - the library never traps a host app.
package enum MotionError: Error, Sendable, Equatable {
    case nonFiniteValue
    /// A completion reentrantly starting another animation on the same
    /// track, itself starting another, past MotionTrack's bound of 8.
    case nestingOverflow
    /// `MotionEngine.start` called on a track already removed by
    /// `MotionEngine.remove`.
    case trackRemoved
}

/// Outcome of one `MotionTrack.step(now:maxAgeMs:)` call - MotionEngine
/// decides what to do with it (queue a completion, report an error) after
/// the tick's whole snapshot has been stepped, never mutating any track
/// mid-loop.
enum TrackStepOutcome {
    case active
    /// `animation` is the one that just finished - MotionEngine.tick checks
    /// its `cancelled` flag right before firing `completion(true)`, since a
    /// completion queued earlier in this same tick can have cancelled it
    /// (started, set, removed or cancelled it) before this one runs.
    case finished(animation: MotionAnimation, completion: ((Bool) -> Void)?)
    case nonFinite(error: MotionError, completion: ((Bool) -> Void)?)
    case timedOut(completion: ((Bool) -> Void)?)
}

/// Drives every registered MotionTrack from one clock. Main-actor: nothing
/// here runs off the main thread. One MotionEngine per MotionClock - the
/// engine's `init` sets the clock's `frameHandler` to its own `tick`,
/// holding itself weakly, so a real adapter (a display link) or
/// `ManualClock.advance` never has to call `tick` by hand.
///
/// Guards:
/// - A track whose animation produces a non-finite value is cancelled,
///   restored to its last finite value (MotionTrack.currentValue does this
///   once the corrupted animation is discarded), completes with false, and
///   is reported through `onError`.
/// - A track older than 10 seconds is force-completed with false, unless it
///   was started with `isLoop: true` (the sprite busy loop is exempt).
@MainActor
package final class MotionEngine {
    private static let maxTrackAgeMs: Double = 10_000

    /// Reported once per guard trip: the error and the track's own label.
    package var onError: ((MotionError, String) -> Void)?

    private let clock: MotionClock
    private var tracks: [MotionTrack] = []

    /// The time argument of the `tick` currently running, `nil` outside one.
    /// `start`/`set` read this in preference to `clock.now`: valueSetter.ts
    /// itself starts an animation at `global.__frameTimestamp` whenever one
    /// is set (i.e. from inside a frame callback), falling back to
    /// `global._getAnimationTimestamp()` only outside one - a completion
    /// that reentrantly starts a new animation mid-tick must see the TICK's
    /// own time, not whatever `clock.now` happens to read by the time that
    /// completion runs.
    private var tickNow: Double?

    package init(clock: MotionClock) {
        self.clock = clock
        clock.frameHandler = { [weak self] now in
            self?.tick(now: now)
        }
    }

    /// Creates and registers a new track for one animated value. `label` is
    /// only ever used for `onError` reporting. A non-finite `initialValue`
    /// is refused - the track falls back to 0 (see `MotionTrack.init`) and
    /// this reports it, since `MotionTrack` itself has no label to report
    /// with until this call wires `onError` up.
    package func makeTrack(label: String, initialValue: Double = 0) -> MotionTrack {
        let track = MotionTrack(label: label, initialValue: initialValue)
        track.onError = { [weak self] error in self?.onError?(error, label) }
        tracks.append(track)
        if !initialValue.isFinite {
            onError?(.nonFiniteValue, label)
        }
        return track
    }

    /// Starts `animation` on `track`, from whatever value the track itself
    /// currently holds, then resyncs the clock's `wantsFrames` to whatever
    /// is actually active afterward - a start that short-circuits or
    /// finishes on its own synchronous first frame must not leave the
    /// clock asking for frames nobody needs. A track already removed by
    /// `remove` refuses the start outright and reports `.trackRemoved`.
    ///
    /// An animation instance is single use: pass a new one to every start.
    /// An instance that was cancelled keeps its `cancelled` flag, so if it
    /// is started again its completion never reports true.
    package func start(
        _ track: MotionTrack,
        _ animation: MotionAnimation,
        isLoop: Bool = false,
        completion: ((Bool) -> Void)? = nil
    ) {
        guard !track.isRemoved else {
            completion?(false)
            onError?(.trackRemoved, track.label)
            return
        }
        track.start(animation, now: tickNow ?? clock.now, isLoop: isLoop, completion: completion)
        clock.setWantsFrames(anyTrackActive)
    }

    /// Sets `track`'s value directly, cancelling whatever animation is
    /// running on it (completion false) - `MotionTrack.set`, mirroring
    /// valueSetter.ts's plain-value branch.
    package func set(_ track: MotionTrack, _ value: Double) {
        track.set(value)
        clock.setWantsFrames(anyTrackActive)
    }

    /// Cancels `track` directly (not via a retarget) - its completion fires
    /// with false. Stops asking for frames if this was the last active track.
    package func cancel(_ track: MotionTrack) {
        track.cancel()
        clock.setWantsFrames(anyTrackActive)
    }

    /// Cancels `track` (as `cancel` does) and unregisters it - it is never
    /// ticked again, and `start` on it afterward reports `.trackRemoved`
    /// and does nothing. Reanimated has no equivalent (a SharedValue is
    /// just garbage collected); this is TabPetMotion's own lifecycle
    /// addition for a host that tears down a companion view.
    package func remove(_ track: MotionTrack) {
        track.markRemoved()
        tracks.removeAll { $0 === track }
        clock.setWantsFrames(anyTrackActive)
    }

    private var anyTrackActive: Bool {
        tracks.contains { $0.isActive }
    }

    /// Advances every active track by one tick. The active set is
    /// snapshotted up front, so a completion that starts a new track mid-tick
    /// (on this track or another) never mutates the collection this loop is
    /// iterating - a track started from inside a completion is never
    /// stepped again in this same tick. Every completion and error report
    /// queued while stepping runs only after every snapshotted track has
    /// been stepped (so a still-active track's value already reflects this
    /// tick's own integration by the time any completion sees it), then the
    /// clock is told to stop in this same tick if the active set is now empty.
    package func tick(now: Double) {
        // Saved and restored, not just set/cleared: a completion queued
        // below can itself advance a ManualClock, causing a NESTED call to
        // this same method before this one returns. That inner tick's own
        // `defer` must hand `tickNow` back to what THIS tick had it at, not
        // to `nil` - otherwise a start made by one of this tick's own
        // remaining completions, running after the nested tick already
        // returned, would fall back to `clock.now` (which the nested
        // advance already moved past this tick's own time) instead of this
        // tick's time.
        let outerTickNow = tickNow
        tickNow = now
        defer { tickNow = outerTickNow }
        let snapshot = tracks.filter(\.isActive)
        var queued: [() -> Void] = []
        for track in snapshot {
            switch track.step(now: now, maxAgeMs: Self.maxTrackAgeMs) {
            case .active:
                break
            case .finished(let animation, let completion):
                if let completion {
                    // Checked at RUN time, not queue time: a completion
                    // earlier in this same queue can cancel this track (or
                    // start/set/remove it) before this closure runs, which
                    // marks `animation.cancelled` - the port of the
                    // original's own step-time check (valueSetter.ts:
                    // `if (animation.cancelled) return;`). Without it, a
                    // track a host just cancelled mid-tick would still hear
                    // "true" right after hearing "false".
                    queued.append {
                        guard !animation.cancelled else { return }
                        completion(true)
                    }
                }
            case .timedOut(let completion):
                if let completion {
                    queued.append { completion(false) }
                }
            case .nonFinite(let error, let completion):
                let label = track.label
                queued.append { [weak self] in
                    completion?(false)
                    self?.onError?(error, label)
                }
            }
        }
        for run in queued {
            run()
        }
        clock.setWantsFrames(anyTrackActive)
    }
}
