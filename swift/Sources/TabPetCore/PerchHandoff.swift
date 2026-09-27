/// Shared lastTab / lastX / lastSeat singleton the real tab perches hand off
/// through, ported from perch-handoff.ts. transientSlot never reads or writes
/// this store - a pushed screen must not skew the next genuine tab chase.
public struct PerchHandoffState: Equatable, Hashable, Codable, Sendable {
    public let lastTab: Int
    public let lastX: Double?
    public let lastSeat: Double

    public init(lastTab: Int, lastX: Double?, lastSeat: Double) {
        self.lastTab = lastTab
        self.lastX = lastX
        self.lastSeat = lastSeat
    }
}

/// Ported from perch-handoff.ts's (unexported) `FocusKind`.
public enum FocusKind: String, Sendable, Codable, Hashable, CaseIterable {
    case transientSnap = "transient-snap"
    case sameTabSnap = "same-tab-snap"
    case snapToSeat = "snap-to-seat"
    case reducedChase = "reduced-chase"
    case runChase = "run-chase"
}

/// Ported from perch-handoff.ts's `FocusPlan`.
public struct FocusPlan: Equatable, Hashable, Codable, Sendable {
    public let kind: FocusKind
    public let fromX: Double
    public let targetX: Double
    /// seatY at the start of this focus (departing altitude -> 0 on land)
    public let fromSeatY: Double
    /// altitude held during a run: climbing to a raised seat holds the
    /// departing height until catch; descending drops immediately
    public let runSeatY: Double
    public let next: PerchHandoffState
    /// false for transientSlot - the shared singleton stays untouched
    public let commitsHandoff: Bool

    public init(
        kind: FocusKind,
        fromX: Double,
        targetX: Double,
        fromSeatY: Double,
        runSeatY: Double,
        next: PerchHandoffState,
        commitsHandoff: Bool
    ) {
        self.kind = kind
        self.fromX = fromX
        self.targetX = targetX
        self.fromSeatY = fromSeatY
        self.runSeatY = runSeatY
        self.next = next
        self.commitsHandoff = commitsHandoff
    }
}

/// Ported from perch-handoff.ts's (unexported) `barScrub` string union.
public enum BarScrub: String, Sendable, Codable, Hashable, CaseIterable {
    case native
    case exclusive
}

/// Ported from perch-handoff.ts's (unexported) `phase` string union in `planDragRelease`.
public enum DragPhase: String, Sendable, Codable, Hashable, CaseIterable {
    case ended
    case cancelled
}

/// Ported from perch-handoff.ts's `DragReleasePlan`. `await` is a Swift keyword, hence the backticks.
public enum DragReleasePlan: Equatable, Hashable, Sendable {
    case home
    case `await`(slot: Int)
}

/// Ported from perch-handoff.ts's `ApproachPlan`.
public enum ApproachPlan: Equatable, Hashable, Sendable {
    case spring
    case run(durationMs: Double)
}

/// Ported from perch-handoff.ts's `FarSamplePlan`.
public enum FarSamplePlan: Equatable, Hashable, Sendable {
    case end
    case track(target: Double, facing: Facing)
}

/// Ported from perch-handoff.ts's stepToward return shape (an inline object type on the TypeScript side).
public struct StepTowardResult: Equatable, Hashable, Codable, Sendable {
    public let x: Double
    public let arrived: Bool

    public init(x: Double, arrived: Bool) {
        self.x = x
        self.arrived = arrived
    }
}

/// Ported from perch-handoff.ts's `ReleaseState`. The perch keeps this in a ref
/// and acts on the effect `PerchHandoff.reduceRelease` returns; it decides nothing itself.
public struct ReleaseState: Equatable, Hashable, Codable, Sendable {
    /// Ported from perch-handoff.ts's (unnamed) `pending` field type.
    public struct Pending: Equatable, Hashable, Codable, Sendable {
        public let fromSlot: Int
        public let slot: Int
        public let generation: Int

        public init(fromSlot: Int, slot: Int, generation: Int) {
            self.fromSlot = fromSlot
            self.slot = slot
            self.generation = generation
        }
    }

    public var pending: Pending?
    public var arrival: Bool

    public init(pending: Pending?, arrival: Bool) {
        self.pending = pending
        self.arrival = arrival
    }
}

/// Ported from perch-handoff.ts's `ReleaseEvent`.
public enum ReleaseEvent: Equatable, Hashable, Sendable {
    case release(plan: DragReleasePlan, fromSlot: Int, generation: Int)
    case began
    case engage
    case focusCleanup
    case focusBody(transientSlot: Bool)
    case timer(mounted: Bool, generation: Int, renderedSlot: Int)
    case abort
    case unmount
}

/// Ported from perch-handoff.ts's `ReleaseEffect`.
public enum ReleaseEffect: String, Sendable, Codable, Hashable, CaseIterable {
    case none
    case goHome = "go-home"
    case `await`
    case clearTimer = "clear-timer"
    case holdGeneration = "hold-generation"
    case arrived
}

/// Ported from perch-handoff.ts's reduceRelease return shape (an inline object type on the TypeScript side).
public struct ReduceReleaseResult: Equatable, Hashable, Sendable {
    public let state: ReleaseState
    public let effect: ReleaseEffect

    public init(state: ReleaseState, effect: ReleaseEffect) {
        self.state = state
        self.effect = effect
    }
}

/// Pure companion perch handoff, ported from perch-handoff.ts. Clamps follow
/// JavaScript Math.min and Math.max, NaN included.
public enum PerchHandoff {
    /// How long a release over another slot waits for the host's selection
    /// before going home. Short loses to a busy JS thread; long only costs a
    /// pause over the wrong tab when no selection ever comes.
    public static let RELEASE_GRACE_MS: Double = 800
    /// Gap between the glass target and the companion, at engage, above which
    /// a live drag is a far grab rather than a normal spring chase.
    public static let FAR_GRAB_PT: Double = PerchGeometry.PERCH_SIZE
    /// dt above this is clamped in stepToward - a stale or idle frame
    /// callback cannot cover more travel than this in one step.
    public static let FAR_STEP_MAX_DT_MS: Double = 34

    /// F1: rise onto a higher seat at catch, not mid-run. F2: drop
    /// immediately when the arriving seat is lower so a bounce-back cannot float.
    public static func planRunSeatY(fromSeatY: Double) -> Double {
        JSMath.jsMax(fromSeatY, 0)
    }

    /// seatY to snap to at focus start, before any chase/catch. run-chase
    /// holds runSeatY (F1/F2); reduced-chase/snap-to-seat start at departing
    /// altitude so a reduce-motion glide to 0 isn't clamped away.
    public static func planStartSeatY(kind: FocusKind, runSeatY: Double, fromSeatY: Double) -> Double {
        if kind == .runChase {
            return runSeatY
        }
        if kind == .reducedChase || kind == .snapToSeat {
            return fromSeatY
        }
        return 0
    }

    /// First committed frame, before useFocusEffect; equals
    /// planStartSeatY(planFocus(...)) - a raised seat initialized at 0
    /// instead would flash one frame at bar height.
    public static func planMountSeatY(
        handoff: PerchHandoffState,
        tab: Int,
        screenWidth: Double,
        bottomExtra: Double,
        transientSlot: Bool,
        reduceMotion: Bool,
        slotCount: Int,
        slotCenters: [Double]? = nil
    ) -> Double {
        let plan = planFocus(
            handoff: handoff,
            tab: tab,
            screenWidth: screenWidth,
            bottomExtra: bottomExtra,
            transientSlot: transientSlot,
            reduceMotion: reduceMotion,
            slotCount: slotCount,
            slotCenters: slotCenters
        )
        return planStartSeatY(kind: plan.kind, runSeatY: plan.runSeatY, fromSeatY: plan.fromSeatY)
    }

    /// Live lastSeat from bottomExtra and current seatY. Blur must freeze
    /// this, not the destination lastSeat written at focus start, or a
    /// bounce-back thinks it already reached the raised seat.
    public static func liveLastSeat(bottomExtra: Double, seatY: Double) -> Double {
        bottomExtra - seatY
    }

    public static func initialPerchHandoff() -> PerchHandoffState {
        PerchHandoffState(lastTab: 0, lastX: nil, lastSeat: 0)
    }

    public static func planFocus(
        handoff: PerchHandoffState,
        tab: Int,
        screenWidth: Double,
        bottomExtra: Double,
        transientSlot: Bool,
        reduceMotion: Bool,
        slotCount: Int,
        slotCenters: [Double]? = nil,
        holdRun: Bool = false
    ) -> FocusPlan {
        let targetX = PerchGeometry.tabCenterX(tab: tab, screenWidth: screenWidth, slotCount: slotCount, slotCenters: slotCenters)
        if transientSlot {
            return FocusPlan(kind: .transientSnap, fromX: targetX, targetX: targetX, fromSeatY: 0, runSeatY: 0, next: handoff, commitsHandoff: false)
        }
        if handoff.lastTab == tab, !holdRun {
            return FocusPlan(
                kind: .sameTabSnap,
                fromX: targetX,
                targetX: targetX,
                fromSeatY: 0,
                runSeatY: 0,
                next: PerchHandoffState(lastTab: tab, lastX: nil, lastSeat: bottomExtra),
                commitsHandoff: true
            )
        }
        let fromX = handoff.lastX ?? PerchGeometry.tabCenterX(tab: handoff.lastTab, screenWidth: screenWidth, slotCount: slotCount, slotCenters: slotCenters)
        let fromSeatY = bottomExtra - handoff.lastSeat
        let runSeatY = planRunSeatY(fromSeatY: fromSeatY)
        let next = PerchHandoffState(lastTab: tab, lastX: nil, lastSeat: bottomExtra)
        let distance = abs(targetX - fromX)
        if !holdRun, PerchGeometry.shouldSnapToSeat(distancePt: distance) {
            return FocusPlan(kind: .snapToSeat, fromX: targetX, targetX: targetX, fromSeatY: fromSeatY, runSeatY: runSeatY, next: next, commitsHandoff: true)
        }
        if reduceMotion {
            return FocusPlan(kind: .reducedChase, fromX: fromX, targetX: targetX, fromSeatY: fromSeatY, runSeatY: runSeatY, next: next, commitsHandoff: true)
        }
        return FocusPlan(kind: .runChase, fromX: fromX, targetX: targetX, fromSeatY: fromSeatY, runSeatY: runSeatY, next: next, commitsHandoff: true)
    }

    /// Blur freezes lastX at the pup's actual x, not the destination he may
    /// still be chasing, and lastSeat at the live altitude (F2).
    public static func applyFocusBlur(handoff: PerchHandoffState, currentX: Double, transientSlot: Bool, currentSeat: Double? = nil) -> PerchHandoffState {
        if transientSlot {
            return handoff
        }
        return PerchHandoffState(lastTab: handoff.lastTab, lastX: currentX, lastSeat: currentSeat ?? handoff.lastSeat)
    }

    /// Live glass drag: preserve the glass (not the trailing companion) and
    /// bar level, so a release onto another tab starts from where the finger is.
    public static func applyDragTrack(handoff: PerchHandoffState, glassTarget: Double) -> PerchHandoffState {
        PerchHandoffState(lastTab: handoff.lastTab, lastX: glassTarget, lastSeat: 0)
    }

    /// Release only writes if this instance still owns lastTab - a competing
    /// focus may already have consumed the handoff.
    public static func applyDragRelease(handoff: PerchHandoffState, tab: Int, releaseX: Double, bottomExtra: Double) -> PerchHandoffState {
        if handoff.lastTab != tab {
            return handoff
        }
        return PerchHandoffState(lastTab: handoff.lastTab, lastX: releaseX, lastSeat: bottomExtra)
    }

    /// Whether anything will select the released-over slot. The bar decides,
    /// not the touch source: a wrapped native recognizer still rides a bar
    /// whose pill selects on release. A classic bar has no pill and does not
    /// select on touch-up; a pill the host passed for its own bar does not count.
    public static func selectsOnRelease(barScrub: BarScrub, hasOnDragRelease: Bool, nativePill: Bool) -> Bool {
        (barScrub == .exclusive && hasOnDragRelease) || (barScrub == .native && nativePill)
    }

    /// A cancelled drag, and a release on its own slot or over a slot nothing
    /// will select, are a chase only - the companion walks back to its seat.
    /// Only an ended release over a different slot that selectsOnRelease is worth waiting on.
    public static func planDragRelease(phase: DragPhase, releaseSlot: Int, currentSlot: Int, selectsOnRelease: Bool) -> DragReleasePlan {
        if phase == .ended, releaseSlot != currentSlot, selectsOnRelease {
            return .await(slot: releaseSlot)
        }
        return .home
    }

    /// Under one glass width a catch reads fine as a spring; farther, a
    /// constant-speed run so a long release-driven approach doesn't teleport.
    public static func planApproach(distancePt: Double, speedPtS: Double? = nil) -> ApproachPlan {
        let distance = abs(distancePt)
        if PerchGeometry.shouldSnapToSeat(distancePt: distance) {
            return .spring
        }
        let durationMs = speedPtS.map { PerchGeometry.traverseDurationMs(distancePt: distance, speedPtS: $0) }
            ?? PerchGeometry.traverseDurationMs(distancePt: distance)
        return .run(durationMs: durationMs)
    }

    /// Whether an engaging drag starts far enough from the companion's seat
    /// to need a run instead of the spring follower.
    public static func isFarGrab(gapPt: Double) -> Bool {
        abs(gapPt) > FAR_GRAB_PT
    }

    /// A far approach ends once the glass is inside the leash's not-chasing
    /// edge, or on a non-finite input. That edge, not a deadband, is what
    /// keeps a small gap from flipping him: beyond it the facing is the sign of the gap.
    public static func planFarSample(glassX: Double, currentX: Double, screenWidth: Double) -> FarSamplePlan {
        guard glassX.isFinite, currentX.isFinite else {
            return .end
        }
        let gap = glassX - currentX
        if abs(gap) <= PerchGeometry.CHASE_TRAIL + PerchGeometry.CHASE_SLACK {
            return .end
        }
        let facing: Facing = gap >= 0 ? .right : .left
        return .track(target: PerchGeometry.chaseTargetX(glassX: glassX, direction: facing, screenWidth: screenWidth), facing: facing)
    }

    /// One frame's step toward a target that may move. Stepped per frame
    /// rather than animated: re-issuing an animation per finger sample
    /// restarts its clock and he gains a frame of travel each time. Never returns NaN.
    public static func stepToward(current: Double, target: Double, speedPtS: Double, dtMs: Double) -> StepTowardResult {
        guard current.isFinite, target.isFinite, speedPtS.isFinite, dtMs.isFinite, speedPtS > 0 else {
            return StepTowardResult(x: current, arrived: false)
        }
        let clampedDt = JSMath.jsMin(JSMath.jsMax(dtMs, 0), FAR_STEP_MAX_DT_MS)
        let distance = target - current
        let step = (speedPtS * clampedDt) / 1000
        if abs(distance) <= step {
            return StepTowardResult(x: target, arrived: true)
        }
        let direction: Double = distance >= 0 ? 1 : -1
        return StepTowardResult(x: current + direction * step, arrived: false)
    }

    /// speed when it is a real, positive number, else the shared default - a
    /// host profile's runSpeed is an unvalidated number (a zero or negative
    /// override must not freeze or reverse a run).
    public static func sanitizeRunSpeed(speed: Double?) -> Double {
        if let speed, speed.isFinite, speed > 0 {
            return speed
        }
        return PerchGeometry.TRAVERSE_SPEED_PT_S
    }

    /// A drag that arrives by drag must not be mistaken for an end-to-end tap
    /// and sent round the pill - the focused slot wins as the route's origin
    /// whenever the reducer says this focus is arriving by drag, whatever
    /// slot the bar's own hit test actually picked.
    public static func focusFromSlot(handoffLastTab: Int, arrivedByDrag: Bool, focusedSlot: Int) -> Int {
        arrivedByDrag ? focusedSlot : handoffLastTab
    }

    public static func initialReleaseState() -> ReleaseState {
        ReleaseState(pending: nil, arrival: false)
    }

    /// Unmounted or a newer motion: drop the wait. Slot already changed:
    /// keep pending, the focus cleanup about to run turns it into an arrival.
    private static func reduceTimer(state: ReleaseState, mounted: Bool, generation: Int, renderedSlot: Int) -> ReduceReleaseResult {
        guard let pending = state.pending else {
            return ReduceReleaseResult(state: state, effect: .none)
        }
        if !mounted || generation != pending.generation {
            var next = state
            next.pending = nil
            return ReduceReleaseResult(state: next, effect: .none)
        }
        if renderedSlot != pending.fromSlot {
            return ReduceReleaseResult(state: state, effect: .none)
        }
        var next = state
        next.pending = nil
        return ReduceReleaseResult(state: next, effect: .goHome)
    }

    /// began keeps state: the touch may be a tap, and ending the wait on it
    /// strands him over the wrong tab with no fallback. focus-cleanup ends
    /// any wait, since the focus body re-plans x.
    public static func reduceRelease(state: ReleaseState, event: ReleaseEvent) -> ReduceReleaseResult {
        switch event {
        case .release(let plan, let fromSlot, let generation):
            switch plan {
            case .home:
                var next = state
                next.pending = nil
                return ReduceReleaseResult(state: next, effect: .goHome)
            case .await(let slot):
                var next = state
                next.pending = ReleaseState.Pending(fromSlot: fromSlot, slot: slot, generation: generation)
                return ReduceReleaseResult(state: next, effect: .await)
            }
        case .began:
            return ReduceReleaseResult(state: state, effect: state.pending == nil ? .none : .holdGeneration)
        case .engage:
            let hadPending = state.pending != nil
            var next = state
            next.pending = nil
            return ReduceReleaseResult(state: next, effect: hadPending ? .clearTimer : .none)
        case .focusCleanup:
            let hadPending = state.pending != nil
            let next = ReleaseState(pending: nil, arrival: hadPending)
            return ReduceReleaseResult(state: next, effect: hadPending ? .clearTimer : .none)
        case .focusBody(let transientSlot):
            let arrived = state.arrival && !transientSlot
            var next = state
            next.arrival = false
            return ReduceReleaseResult(state: next, effect: arrived ? .arrived : .none)
        case .timer(let mounted, let generation, let renderedSlot):
            return reduceTimer(state: state, mounted: mounted, generation: generation, renderedSlot: renderedSlot)
        case .abort:
            let hadPending = state.pending != nil
            var next = state
            next.pending = nil
            return ReduceReleaseResult(state: next, effect: hadPending ? .clearTimer : .none)
        case .unmount:
            let hadPending = state.pending != nil
            let next = ReleaseState(pending: nil, arrival: false)
            return ReduceReleaseResult(state: next, effect: hadPending ? .clearTimer : .none)
        }
    }
}

/// The module's state store, ported from perch-handoff.ts's module-level
/// singleton. Tests build their own instance rather than sharing `.shared`.
@MainActor
public final class PerchHandoffStore {
    public static let shared = PerchHandoffStore()

    private var state: PerchHandoffState

    public init() {
        state = PerchHandoff.initialPerchHandoff()
    }

    public func readPerchHandoff() -> PerchHandoffState {
        state
    }

    public func writePerchHandoff(next: PerchHandoffState) {
        state = next
    }

    /// Test-only - module singleton must not leak across suites.
    func resetForTest() {
        state = PerchHandoff.initialPerchHandoff()
    }
}
