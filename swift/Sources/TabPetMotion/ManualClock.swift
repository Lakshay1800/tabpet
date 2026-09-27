/// Test-only MotionClock: time only moves when `advance` is called, and
/// nothing here ever sleeps or touches a real timer or thread.
@MainActor
public final class ManualClock: MotionClock {
    private struct Timer {
        let id: Int
        let fireAt: Double
        let action: @MainActor () -> Void
    }

    private final class Handle: MotionCancellable {
        weak var owner: ManualClock?
        let id: Int

        init(owner: ManualClock, id: Int) {
            self.owner = owner
            self.id = id
        }

        func cancel() {
            owner?.cancelTimer(id)
        }
    }

    public private(set) var now: Double
    public private(set) var wantsFrames = false
    public var frameHandler: (@MainActor (Double) -> Void)?

    private var timers: [Timer] = []
    private var nextTimerID = 0

    public init(now: Double = 0) {
        self.now = now
    }

    public func setWantsFrames(_ wantsFrames: Bool) {
        self.wantsFrames = wantsFrames
    }

    public func after(milliseconds: Double, _ action: @escaping @MainActor () -> Void) -> MotionCancellable {
        let id = nextTimerID
        nextTimerID += 1
        timers.append(Timer(id: id, fireAt: now + milliseconds, action: action))
        return Handle(owner: self, id: id)
    }

    private func cancelTimer(_ id: Int) {
        timers.removeAll { $0.id == id }
    }

    /// Steps `now` forward in `frameMs` increments up to `ms` total (the
    /// last step is clamped so `now` lands exactly on the requested total,
    /// never past it). At EACH step: timers due at that time fire first, in
    /// order of due time (ties broken by the order they were scheduled), then
    /// `frameHandler` runs once if `wantsFrames` is true - that order
    /// (timers, then the frame) is fixed and documented, never the other way
    /// round. Nothing sleeps; a caller never has to `tick` an engine by hand
    /// after calling this.
    ///
    /// Does nothing at all - no timers fire, `now` is unchanged - unless
    /// both `ms` and `frameMs` are finite and positive: the library never
    /// traps a host app over a bad interval, rather than looping forever
    /// (`ms == .infinity`) or not stepping at all (`frameMs <= 0`). Also
    /// stops early if a step's addition no longer changes `now` at all - at
    /// a large enough absolute time, floating-point precision loss can make
    /// `now + step == now`, which would otherwise loop forever.
    public func advance(ms: Double, frameMs: Double) {
        guard ms.isFinite, ms > 0, frameMs.isFinite, frameMs > 0 else {
            return
        }
        let target = now + ms
        while now < target {
            let previous = now
            let step = Swift.min(frameMs, target - now)
            now += step
            if now == previous {
                break
            }
            fireDueTimers()
            if wantsFrames {
                frameHandler?(now)
            }
        }
    }

    private func fireDueTimers() {
        // A fired timer can itself schedule a new one (a completion starting
        // a new track) - snapshot the due set, remove it from `timers`, then
        // fire, so this never mutates `timers` while iterating it. Ordered
        // by due time first, then by creation order for timers due at the
        // same step - never creation order alone, which would fire a timer
        // scheduled first but due LATER ahead of one scheduled after it but
        // due sooner.
        let due = timers.filter { $0.fireAt <= now }.sorted {
            $0.fireAt != $1.fireAt ? $0.fireAt < $1.fireAt : $0.id < $1.id
        }
        guard !due.isEmpty else {
            return
        }
        let dueIDs = Set(due.map(\.id))
        timers.removeAll { dueIDs.contains($0.id) }
        for timer in due {
            timer.action()
        }
    }
}
