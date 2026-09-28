/// Busy claim broadcast, ported from companion-state.ts: one small broadcast the
/// perch renders its own projection of. `beginCompanionBusy` ref-counts overlapping
/// claims; listeners fire only on the idle<->busy edge, never per nested claim.
@MainActor
public final class CompanionState {
    public static let shared = CompanionState()

    public typealias BusyListener = @MainActor @Sendable (Bool) -> Void

    /// Append-only slot in insertion order; `removed` tombstones a slot instead
    /// of deleting it mid-broadcast, mirroring how a JS Set keeps a deleted
    /// entry's position stable for any iteration already in progress.
    private struct Slot {
        let id: Int
        let listener: BusyListener
        var removed = false
    }

    private var busyClaims = 0
    private var slots: [Slot] = []
    private var nextListenerId = 0
    /// >0 while inside notify (including nested re-entrant broadcasts) - defers
    /// compaction so index-based iteration never sees slots shift underneath it.
    private var notifyDepth = 0

    public init() {}

    public func isCompanionBusy() -> Bool {
        busyClaims > 0
    }

    /// Claims busy for one in-flight operation, returns an idempotent release.
    /// Ref-counted - listeners fire only on the idle<->busy edge, not per claim.
    public func beginCompanionBusy() -> @MainActor @Sendable () -> Void {
        busyClaims += 1
        if busyClaims == 1 {
            notify(true)
        }
        var released = false
        return { [weak self] in
            if released {
                return
            }
            released = true
            guard let self else {
                return
            }
            self.busyClaims -= 1
            if self.busyClaims == 0 {
                self.notify(false)
            }
        }
    }

    /// Subscribes to idle<->busy edge transitions; safe to claim busy with zero subscribers mounted.
    /// Closures have no identity in Swift, unlike a JS `Set` keyed by function
    /// reference - subscribing the same closure twice registers it twice.
    public func subscribeCompanionBusy(_ listener: @escaping BusyListener) -> @MainActor @Sendable () -> Void {
        let id = nextListenerId
        nextListenerId += 1
        slots.append(Slot(id: id, listener: listener))
        return { [weak self] in
            self?.removeListener(id: id)
        }
    }

    private func removeListener(id: Int) {
        guard let index = slots.firstIndex(where: { $0.id == id }) else {
            return
        }
        slots[index].removed = true
        if notifyDepth == 0 {
            compact()
        }
    }

    /// Mirrors a JS Set's iterate-while-mutating semantics: walks live slots by
    /// index, re-reading `slots.count` on every step so a listener subscribed
    /// during this broadcast is visited once reached, and skips a slot already
    /// tombstoned before its turn. A re-entrant claim or release made inside a
    /// listener starts its own nested broadcast at once, synchronously, exactly
    /// as the TypeScript's direct call does.
    private func notify(_ busy: Bool) {
        notifyDepth += 1
        var index = 0
        while index < slots.count {
            let slot = slots[index]
            if !slot.removed {
                slot.listener(busy)
            }
            index += 1
        }
        notifyDepth -= 1
        if notifyDepth == 0 {
            compact()
        }
    }

    private func compact() {
        slots.removeAll { $0.removed }
    }

    /// Test-only reset - claims and listeners must not leak between test cases
    /// sharing an instance. The id counter is NOT reset: a handle captured
    /// before a reset must never remove a listener registered after it.
    func resetForTest() {
        busyClaims = 0
        slots.removeAll()
    }

    /// Test-only: the live, already-compacted listener count - proves a
    /// dropped subscriber's own slot was actually removed, not merely tombstoned.
    var debugListenerCount: Int { slots.count }
}
