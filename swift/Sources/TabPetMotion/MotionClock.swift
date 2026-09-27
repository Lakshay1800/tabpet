import Foundation

/// A handle to a scheduled timer. `cancel()` is a no-op once already fired
/// or already cancelled. Named `MotionCancellable`, not `Cancellable` - the
/// latter collides with Combine's protocol of the same name in any file
/// that imports both.
@MainActor
public protocol MotionCancellable: AnyObject {
    func cancel()
}

/// The one seam between the pure integrator (MotionTrack, MotionEngine) and
/// a real time source. `now` is always milliseconds - ClockUnits is the
/// only place seconds become milliseconds and back, so a real adapter (a
/// display link's seconds-based dt, `DispatchQueue`'s seconds-based
/// deadline) converts at its own boundary, never inline here.
@MainActor
public protocol MotionClock: AnyObject {
    /// Current time in milliseconds. Only meaningful relative to another
    /// reading from the same clock instance.
    var now: Double { get }

    /// Set once by the MotionEngine constructed with this clock (one engine
    /// per clock) to its own `tick`. A real adapter (a display link) calls
    /// this on every frame while `wantsFrames` is true; `ManualClock.advance`
    /// calls it itself. A MotionClock never calls back into anything else
    /// through this protocol.
    var frameHandler: (@MainActor (Double) -> Void)? { get set }

    /// MotionEngine's hint that at least one track is active (true) or that
    /// the active set just emptied (false). Whatever owns the real frame
    /// source reads this to know whether to keep requesting frames and
    /// calling `frameHandler`.
    func setWantsFrames(_ wantsFrames: Bool)

    /// Schedules `action` to run after `milliseconds` have elapsed on this
    /// clock. Returns a handle whose `cancel()` prevents a not-yet-fired
    /// action from running.
    func after(milliseconds: Double, _ action: @escaping @MainActor () -> Void) -> MotionCancellable
}
