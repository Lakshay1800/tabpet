import TabPetCore

/// Platform-neutral mirror of TabPetUIKit's `TabBarLayout` - the native
/// measurement `PerchController`'s `measure` closure returns, ported 1:1
/// from `nativeTabBarLayout()`'s TS shape (`{centers?, top?, pill?}`).
package struct BarLayout: Equatable, Sendable {
    package var centers: [Double]
    package var top: Double?
    package var pill: PillFrame?

    package init(centers: [Double] = [], top: Double? = nil, pill: PillFrame? = nil) {
        self.centers = centers
        self.top = top
        self.pill = pill
    }
}

/// Host-supplied overrides, mirroring `CompanionAnchor` (TS). `nil` means
/// "not supplied, fall back to `measure()`", matching TS's `undefined`;
/// `pill` has no separate "explicitly no pill" state (routes are out of scope here).
package struct PerchAnchor: Equatable, Sendable {
    package var slotCount: Int
    package var slotIndex: Int
    package var slotCenters: [Double]?
    package var barTop: Double?
    package var pill: PillFrame?

    package init(slotCount: Int, slotIndex: Int, slotCenters: [Double]? = nil, barTop: Double? = nil, pill: PillFrame? = nil) {
        self.slotCount = slotCount
        self.slotIndex = slotIndex
        self.slotCenters = slotCenters
        self.barTop = barTop
        self.pill = pill
    }
}

/// One coalesced output commit - the TS perch's `x`/`hop`/`seatY`/
/// `flightLift`/`routeRotation`/`pose`/`facing`/`busy`, read together as one
/// transaction, plus the currently resolved `barTop` for the view's layout.
package struct PerchRenderState: Equatable, Sendable {
    package var x: Double
    package var seatY: Double
    package var hop: Double
    package var flightLift: Double
    package var rotationDegrees: Double
    package var visible: Double
    package var pose: PupPose
    package var facing: Facing
    package var busy: Bool
    package var barTop: Double?

    package init(
        x: Double,
        seatY: Double,
        hop: Double,
        flightLift: Double,
        rotationDegrees: Double,
        visible: Double,
        pose: PupPose,
        facing: Facing,
        busy: Bool,
        barTop: Double?
    ) {
        self.x = x
        self.seatY = seatY
        self.hop = hop
        self.flightLift = flightLift
        self.rotationDegrees = rotationDegrees
        self.visible = visible
        self.pose = pose
        self.facing = facing
        self.busy = busy
        self.barTop = barTop
    }
}

/// Wraps a `MotionCancellable` as `PerchRemeasure`'s generic `Handle:
/// Sendable` parameter - only ever touched on the main actor, like every
/// value its schedule/cancel closures pass around.
@MainActor
private final class RemeasureToken: @unchecked Sendable {
    let cancellable: MotionCancellable
    init(_ cancellable: MotionCancellable) { self.cancellable = cancellable }
}

private final class NoOpCancellable: MotionCancellable {
    func cancel() {}
}

/// The tab-change path of `companion-perch.tsx`, on plain stored properties
/// and `MotionEngine` tracks. Platform neutral, tested on macOS with
/// `ManualClock`; the clock and engine are injected, shared with `SpritePlayer`.
@MainActor
package final class PerchController {
    private static let chaseReactionMs: Double = 65
    private static let reducedDurationMs: Double = 200
    private static let hopStepMs: Double = 120
    private static let remeasureMaxTries = 60
    /// TS paces retryMeasure's retries by requestAnimationFrame - about 16ms
    /// a try at 60fps.
    private static let remeasureRetryMs: Double = 16
    /// Headroom past a run leg's own worst-case duration before the engine's
    /// age guard may force-complete it, so a slow animal's long traverse
    /// never freezes mid-bar with the link left awake.
    private static let runLegSettleMs: Double = 5000

    package var onError: ((MotionError, String) -> Void)?
    package var onRenderState: ((PerchRenderState) -> Void)?

    private let mounted: @MainActor @Sendable () -> Bool
    private let measure: @MainActor @Sendable () -> BarLayout?
    private let reduceMotion: @MainActor @Sendable () -> Bool
    private let clock: MotionClock
    private let engine: MotionEngine
    private let handoffStore: PerchHandoffStore
    private let busyState: CompanionState

    private var profile: CompanionProfile
    private var anchor: PerchAnchor
    private var isFocused: Bool
    private var transientSlot: Bool
    private var bottomExtra: Double
    private var screenWidth: Double

    private let xTrack: MotionTrack
    private let hopTrack: MotionTrack
    private let seatYTrack: MotionTrack
    private let flightLiftTrack: MotionTrack
    private let rotationTrack: MotionTrack
    private let visibleTrack: MotionTrack

    private var pose: PupPose
    private var facing: Facing
    private var busy: Bool
    /// TS: `motionSpringRef` - the spring that drove the motion currently in
    /// progress, so `flightLift`'s own spring matches whatever caused it.
    private var motionSpring: TabPetCore.SpringConfig

    private var motionGeneration = 0
    private var releaseState = PerchHandoff.initialReleaseState()
    private var releaseTimerHandle: MotionCancellable?
    private var slotCenters: [Double]?
    private var barTop: Double?
    private var lastPill: PillFrame?
    private var hasActiveFocus = false
    private var stopRemeasure: (@MainActor @Sendable () -> Void)?
    private var unsubscribeBusy: (@MainActor @Sendable () -> Void)?

    package init(
        profile: CompanionProfile,
        anchor: PerchAnchor,
        transientSlot: Bool = false,
        bottomExtra: Double = 0,
        screenWidth: Double,
        mounted: @escaping @MainActor @Sendable () -> Bool,
        measure: @escaping @MainActor @Sendable () -> BarLayout?,
        reduceMotion: @escaping @MainActor @Sendable () -> Bool,
        clock: MotionClock,
        engine: MotionEngine,
        handoff: PerchHandoffStore,
        busy: CompanionState,
        onError: ((MotionError, String) -> Void)? = nil
    ) {
        self.profile = profile
        self.anchor = anchor
        self.transientSlot = transientSlot
        self.bottomExtra = bottomExtra
        self.screenWidth = screenWidth
        self.isFocused = false
        self.mounted = mounted
        self.measure = measure
        self.reduceMotion = reduceMotion
        self.clock = clock
        self.engine = engine
        self.handoffStore = handoff
        self.busyState = busy
        self.onError = onError

        self.xTrack = engine.makeTrack(label: "perch.x", initialValue: 0)
        self.hopTrack = engine.makeTrack(label: "perch.hop", initialValue: 0)
        self.seatYTrack = engine.makeTrack(label: "perch.seatY", initialValue: 0)
        self.flightLiftTrack = engine.makeTrack(label: "perch.flightLift", initialValue: 0)
        self.rotationTrack = engine.makeTrack(label: "perch.rotation", initialValue: 0)
        self.visibleTrack = engine.makeTrack(label: "perch.visible", initialValue: 1)

        self.motionSpring = profile.trackSpring
        self.pose = .sit
        self.facing = .right
        self.busy = busy.isCompanionBusy()

        // Shared-engine mode: whoever owns the engine owns this slot - a
        // view running both a controller and a sprite player on one engine
        // must combine their reporting itself to route both.
        engine.onError = { [weak self] error, label in self?.onError?(error, label) }

        // Not subscribed here: see `activateBusyTracking()`.

        // Seat on mount: one commit, no track started, link idle - a
        // separate `focus()` call is the caller's own next transaction,
        // mirroring the TS mount render committing before `useEffect` runs.
        let handoffState = handoff.readPerchHandoff()
        let initialCenters = measuredCenters(for: anchor)
        let seedX = PerchGeometry.tabCenterX(
            tab: handoffState.lastTab,
            screenWidth: screenWidth,
            slotCount: anchor.slotCount,
            slotCenters: initialCenters
        )
        engine.set(xTrack, seedX)
        let seedSeatY = PerchHandoff.planMountSeatY(
            handoff: handoffState,
            tab: anchor.slotIndex,
            screenWidth: screenWidth,
            bottomExtra: bottomExtra,
            transientSlot: transientSlot,
            reduceMotion: reduceMotion(),
            slotCount: anchor.slotCount,
            slotCenters: initialCenters
        )
        engine.set(seatYTrack, seedSeatY)

        emitRenderState()
    }

    // MARK: - Public lifecycle

    /// The current drawable state, read on demand - used by tests and by a
    /// caller with no `onRenderState` installed.
    package var currentState: PerchRenderState { buildState() }

    /// Call once, on the first window entry - a perch never attached leaves
    /// no live busy listener. Idempotent: seeds `busy` only on the call that
    /// actually subscribes, never resyncing it on a later call.
    package func activateBusyTracking() {
        guard unsubscribeBusy == nil else { return }
        busy = busyState.isCompanionBusy()
        unsubscribeBusy = busyState.subscribeCompanionBusy { [weak self] next in
            self?.handleBusyEdge(next)
        }
    }

    /// The counterpart of `activateBusyTracking()` - call only from
    /// `teardown()`, never on a window loss the perch survives.
    package func deactivateBusyTracking() {
        unsubscribeBusy?()
        unsubscribeBusy = nil
    }

    /// Call once, right after the shared engine's owner ticks it - re-reads
    /// the continuously-animating tracks and publishes a fresh commit,
    /// expected every tick something is moving.
    package func renderTick() {
        emitRenderState()
    }

    /// The whole tab-change path (TS: the focus `useEffect`, body and
    /// cleanup together). Blurs any active focus first, then, only if
    /// `isFocused`, runs the new body - call after construction and on every argument change.
    package func focus(
        anchor: PerchAnchor,
        isFocused: Bool = true,
        transientSlot: Bool,
        bottomExtra: Double,
        screenWidth: Double
    ) {
        if hasActiveFocus {
            performBlur()
        }
        hasActiveFocus = false

        // Consumed before the `isFocused` guard, unlike everything else
        // below - a pending release becomes an arrival on whatever slot
        // this focus lands on, focused or not.
        let bodyResult = PerchHandoff.reduceRelease(state: releaseState, event: .focusBody(transientSlot: transientSlot))
        releaseState = bodyResult.state
        let arrivedByDrag = bodyResult.effect == .arrived

        self.anchor = anchor
        self.transientSlot = transientSlot
        self.bottomExtra = bottomExtra
        self.screenWidth = screenWidth
        self.isFocused = isFocused

        guard isFocused else { return }
        hasActiveFocus = true

        let reduceMotionOn = reduceMotion()
        let measuredCentersNow = measuredCenters(for: anchor)
        slotCenters = measuredCentersNow ?? slotCenters
        if let barTopNow = measuredBarTop(for: anchor) {
            barTop = barTopNow
        }
        let pillNow = measuredPill(for: anchor) ?? lastPill
        lastPill = pillNow

        let handoffState = handoffStore.readPerchHandoff()
        let plan = PerchHandoff.planFocus(
            handoff: handoffState,
            tab: anchor.slotIndex,
            screenWidth: screenWidth,
            bottomExtra: bottomExtra,
            transientSlot: transientSlot,
            reduceMotion: reduceMotionOn,
            slotCount: anchor.slotCount,
            slotCenters: slotCenters,
            holdRun: false
        )

        let generation = bumpMotion()
        let liveXAtFocusStart = xTrack.currentValue

        engine.cancel(rotationTrack)
        snapVerticalToSeat(PerchHandoff.planStartSeatY(kind: plan.kind, runSeatY: plan.runSeatY, fromSeatY: plan.fromSeatY))
        engine.cancel(xTrack)
        engine.set(xTrack, plan.fromX)

        switch plan.kind {
        case .runChase:
            switch routeChoice() {
            case .plain:
                runPlainChase(fromX: plan.fromX, targetX: plan.targetX, runSeatY: plan.runSeatY, generation: generation, arrivedByDrag: arrivedByDrag)
            }
        case .reducedChase:
            // Reduce Motion snaps every animation lacking an explicit
            // setting under Reanimated (the TS 200ms timing here is a
            // snap in practice); this engine has no such auto-snap.
            engine.set(xTrack, plan.targetX)
            engine.set(seatYTrack, 0)
            setPose(.sit)
        case .snapToSeat:
            catchAtSeat(targetX: plan.targetX, liveXAtFocusStart: liveXAtFocusStart, generation: generation, arrivedByDrag: arrivedByDrag, reduceMotionOn: reduceMotionOn)
        case .transientSnap, .sameTabSnap:
            engine.set(xTrack, plan.targetX)
            engine.set(seatYTrack, 0)
            setPose(.sit)
        }

        if plan.commitsHandoff {
            handoffStore.writePerchHandoff(next: plan.next)
        }
        engine.set(visibleTrack, 1)

        if !transientSlot, anchor.slotCenters == nil, measuredCentersNow == nil {
            startRemeasure(generation: generation, kindAtFocus: plan.kind, commitsHandoff: plan.commitsHandoff)
        }

        emitRenderState()
    }

    /// A profile change (companionID swap) reruns blur+focus with whatever
    /// anchor/params are already in effect, mirroring `profile` in the TS
    /// focus effect's own dependency list. A no-op before the first `focus()` call.
    package func updateProfile(_ newProfile: CompanionProfile) {
        profile = newProfile
        guard hasActiveFocus else { return }
        focus(anchor: anchor, isFocused: isFocused, transientSlot: transientSlot, bottomExtra: bottomExtra, screenWidth: screenWidth)
    }

    /// Call once, when the owning view tears the perch down: unsubscribes
    /// busy, cancels any remeasure/release timer, and removes only this
    /// controller's own tracks. Nothing runs from `deinit` (no isolated deinit in Swift 5.9).
    package func teardown() {
        deactivateBusyTracking()
        hasActiveFocus = false
        stopRemeasure?()
        stopRemeasure = nil
        releaseTimerHandle?.cancel()
        releaseTimerHandle = nil
        engine.remove(xTrack)
        engine.remove(hopTrack)
        engine.remove(seatYTrack)
        engine.remove(flightLiftTrack)
        engine.remove(rotationTrack)
        engine.remove(visibleTrack)
    }

    // MARK: - Test-only hooks

    /// Test-only: seeds the release-state machine directly, standing in for
    /// the finger path's own 'release' event (absent this change), so a
    /// test can exercise an arrived-by-drag catch without a live drag.
    package var debugReleaseState: ReleaseState {
        get { releaseState }
        set { releaseState = newValue }
    }

    /// Test-only: bumps the motion generation without cancelling any active
    /// track - standing in for the finger path's own 'began' effect, absent
    /// this change. See `PerchReentry`.
    @discardableResult
    package func debugBumpGeneration() -> Int {
        bumpMotion()
    }

    /// Test-only: sets `x` directly (a plain value, cancelling whatever was
    /// running) - standing in for the finger path's own live drag position,
    /// so a test can leave `x` off the seat before an arrived-by-drag catch runs.
    package func debugSetX(_ value: Double) {
        engine.set(xTrack, value)
    }

    // MARK: - Route choice

    private enum RunChaseRoute {
        case plain
    }

    /// TS: `resolveRunChaseRoute`. Always "plain" in this change - no around
    /// or resumed route yet (a later change replaces this body only).
    private func routeChoice() -> RunChaseRoute {
        .plain
    }

    // MARK: - Focus branches

    private func runPlainChase(fromX: Double, targetX: Double, runSeatY: Double, generation: Int, arrivedByDrag: Bool) {
        setFacing(targetX >= fromX ? .right : .left)
        let distance = abs(targetX - fromX)
        let runMs = PerchGeometry.traverseDurationMs(distancePt: distance, speedPtS: sanitizedRunSpeed)
        motionSpring = profile.commitSpring
        setPose(.run)

        let completion: (Bool) -> Void = { [weak self] finished in
            guard finished else { return }
            self?.arrive(generation: generation)
        }
        let runLeg = SequenceAnimation(
            TimingAnimation(toValue: targetX, config: TimingConfig(duration: runMs, easing: { Easing.linear($0) })),
            SpringAnimation(toValue: targetX, config: springConfig(profile.catchSpring))
        )
        // The reaction pause plus the run itself plus a settle allowance -
        // wide enough that a slow animal's own catch spring always finishes
        // naturally, never force-completed mid-bar by the engine's age guard.
        let runLegMaxAgeMs = Self.chaseReactionMs + runMs + Self.runLegSettleMs
        if arrivedByDrag {
            engine.start(xTrack, runLeg, maxAgeMs: runLegMaxAgeMs, completion: completion)
        } else {
            engine.start(xTrack, DelayAnimation(Self.chaseReactionMs, runLeg), maxAgeMs: runLegMaxAgeMs, completion: completion)
        }

        if !arrivedByDrag {
            let hopLeg = SequenceAnimation(
                TimingAnimation(toValue: profile.hopHeight, config: TimingConfig(duration: Self.hopStepMs)),
                TimingAnimation(toValue: 0, config: TimingConfig(duration: Self.hopStepMs))
            )
            engine.start(hopTrack, DelayAnimation(Self.chaseReactionMs, hopLeg))
        }

        guard runSeatY != 0 else {
            engine.set(seatYTrack, 0)
            return
        }
        let seatLeg = SequenceAnimation(
            TimingAnimation(toValue: runSeatY, config: TimingConfig(duration: runMs, easing: { Easing.linear($0) })),
            SpringAnimation(toValue: 0, config: springConfig(profile.catchSpring))
        )
        if arrivedByDrag {
            engine.start(seatYTrack, seatLeg)
        } else {
            engine.start(seatYTrack, DelayAnimation(Self.chaseReactionMs, seatLeg))
        }
    }

    /// TS: `catchAtSeat`. The fast path (an instant teleport) runs unless
    /// this is a real arrived-by-drag catch, which springs instead from the
    /// live pre-focus position (`x.set(plan.fromX)` already baked `fromX == targetX`).
    private func catchAtSeat(targetX: Double, liveXAtFocusStart: Double, generation: Int, arrivedByDrag: Bool, reduceMotionOn: Bool) {
        guard arrivedByDrag, !reduceMotionOn else {
            engine.set(xTrack, targetX)
            if reduceMotionOn {
                engine.set(seatYTrack, 0)
            } else {
                engine.start(seatYTrack, SpringAnimation(toValue: 0, config: springConfig(profile.catchSpring)))
            }
            setPose(.sit)
            return
        }
        let remaining = abs(targetX - liveXAtFocusStart)
        let direction = PerchGeometry.travelFacing(targetX: targetX, currentX: liveXAtFocusStart, currentFacing: facing)
        if direction != facing {
            setFacing(direction)
        }
        setPose(remaining > PerchGeometry.FACING_DEADBAND ? .run : .sit)
        engine.set(xTrack, liveXAtFocusStart)
        engine.start(xTrack, SpringAnimation(toValue: targetX, config: springConfig(profile.catchSpring))) { [weak self] finished in
            guard finished else { return }
            self?.arrive(generation: generation)
        }
        engine.start(seatYTrack, SpringAnimation(toValue: 0, config: springConfig(profile.catchSpring)))
    }

    // MARK: - Blur

    /// TS: the focus effect's own cleanup. No route staging here (no route
    /// ever runs this change), so `liveSeat` always takes the plain `liveLastSeat` branch.
    private func performBlur() {
        let cleanupResult = PerchHandoff.reduceRelease(state: releaseState, event: .focusCleanup)
        releaseState = cleanupResult.state
        if cleanupResult.effect == .clearTimer {
            releaseTimerHandle?.cancel()
            releaseTimerHandle = nil
        }
        stopRemeasure?()
        stopRemeasure = nil

        let liveX = xTrack.currentValue
        let liveSeat = PerchHandoff.liveLastSeat(bottomExtra: bottomExtra, seatY: seatYTrack.currentValue)

        engine.cancel(xTrack)
        engine.cancel(rotationTrack)
        bumpMotion()
        snapVerticalToSeat(0)

        handoffStore.writePerchHandoff(
            next: PerchHandoff.applyFocusBlur(handoff: handoffStore.readPerchHandoff(), currentX: liveX, transientSlot: transientSlot, currentSeat: liveSeat)
        )
        engine.set(visibleTrack, 0)
        setPose(.sit)
        emitRenderState()
    }

    // MARK: - Completions

    /// TS: `arrive`. Every spring/timing completion routes through here - a
    /// late one applies only when its generation is still current and the
    /// owner is still mounted, the same reentry gate Reanimated's own late-firing springs need.
    private func arrive(generation: Int) {
        guard PerchReentry.shouldApplyArrive(callbackGeneration: generation, currentGeneration: motionGeneration, mounted: mounted()) else { return }
        rest()
    }

    /// TS: `rest`. The sit sheet's last frame, or the idle loop while a busy
    /// claim is held - never idle[0] at rest with no busy claim (a
    /// different drawing from sit's last frame on some animals).
    private func rest() {
        setPose(busy ? .idle : .sit)
        emitRenderState()
    }

    private func handleBusyEdge(_ next: Bool) {
        busy = next
        // TS also gates this on the finger leash's own state, absent here
        // (no finger path), so nothing blocks it; the flip below only ever
        // touches sit<->idle, a no-op mid-chase (pose 'run') by construction.
        if next, pose == .sit {
            setPose(.idle)
        } else if !next, pose == .idle {
            setPose(.sit)
        }
        emitRenderState()
    }

    // MARK: - Pose/facing/flight lift

    private func setPose(_ next: PupPose) {
        let changed = pose != next
        pose = next
        guard changed else { return }
        updateFlightLift()
    }

    private func setFacing(_ next: Facing) {
        facing = next
    }

    /// TS: the flight-lift effect - springs (or snaps, under Reduce Motion)
    /// toward `-profile.flightLift` while running, 0 otherwise, on
    /// whichever spring drove the motion that caused this pose change.
    private func updateFlightLift() {
        let target = pose == .run ? -profile.flightLift : 0
        if reduceMotion() {
            engine.set(flightLiftTrack, target)
        } else {
            engine.start(flightLiftTrack, SpringAnimation(toValue: target, config: springConfig(motionSpring)))
        }
    }

    // MARK: - Vertical snap

    /// TS: `snapVerticalToSeat`. Cancels hop/flightLift/seatY/rotation and
    /// any in-flight route, then seeds `seatY` at `seatYStart`.
    private func snapVerticalToSeat(_ seatYStart: Double) {
        engine.cancel(hopTrack)
        engine.set(hopTrack, 0)
        engine.cancel(flightLiftTrack)
        engine.set(flightLiftTrack, 0)
        engine.cancel(seatYTrack)
        engine.set(seatYTrack, seatYStart)
        engine.cancel(rotationTrack)
        engine.set(rotationTrack, 0)
    }

    // MARK: - Remeasure

    private func startRemeasure(generation: Int, kindAtFocus: FocusKind, commitsHandoff: Bool) {
        stopRemeasure = PerchRemeasure.retryMeasure(
            measure: { [weak self] () -> BarLayout? in
                guard let self, let centers = self.measuredCenters(for: self.anchor) else { return nil }
                return BarLayout(centers: centers)
            },
            onMeasured: { [weak self] layout in
                self?.applyRemeasure(layout, generation: generation, kindAtFocus: kindAtFocus, commitsHandoff: commitsHandoff)
            },
            maxTries: Self.remeasureMaxTries,
            schedule: { [weak self] action -> RemeasureToken in
                guard let self else { return RemeasureToken(NoOpCancellable()) }
                // TS paces retries by requestAnimationFrame (~16ms); a
                // same-turn reschedule here would burn through all 60 tries
                // in a fraction of that pacing.
                return RemeasureToken(self.clock.after(milliseconds: Self.remeasureRetryMs, action))
            },
            cancel: { token in token.cancellable.cancel() }
        )
    }

    /// TS: `retryMeasure`'s own `onMeasured` body. Only corrects the seat
    /// while nothing owns motion for this same generation and this focus
    /// did not itself start a run-chase, which must never be yanked.
    private func applyRemeasure(_ layout: BarLayout, generation: Int, kindAtFocus: FocusKind, commitsHandoff: Bool) {
        slotCenters = layout.centers
        if let barTopFound = measuredBarTop(for: anchor) {
            barTop = barTopFound
        }
        let pillFound = measuredPill(for: anchor)
        lastPill = pillFound ?? lastPill

        let seated = motionGeneration == generation && kindAtFocus != .runChase
        guard seated else { return }

        let seat = PerchGeometry.tabCenterX(tab: anchor.slotIndex, screenWidth: screenWidth, slotCount: anchor.slotCount, slotCenters: slotCenters)
        engine.set(xTrack, seat)
        if commitsHandoff {
            handoffStore.writePerchHandoff(next: PerchHandoffState(lastTab: anchor.slotIndex, lastX: nil, lastSeat: bottomExtra))
        }
        emitRenderState()
    }

    // MARK: - Measurement (anchor overrides, native fallback)

    /// TS: `measureCenters`. A non-finite entry, at either source, is
    /// treated as not provided - the controller's own sanitization
    /// boundary: the view sanitizes host input too, but never assumes it did.
    private func measuredCenters(for anchor: PerchAnchor) -> [Double]? {
        if let slotCenters = anchor.slotCenters, slotCenters.allSatisfy(\.isFinite) {
            return slotCenters
        }
        guard let layout = measure(), layout.centers.count >= anchor.slotCount, layout.centers.allSatisfy(\.isFinite) else {
            return nil
        }
        return layout.centers
    }

    /// TS: `measureBarTop`.
    private func measuredBarTop(for anchor: PerchAnchor) -> Double? {
        if let barTop = anchor.barTop, barTop.isFinite {
            return barTop
        }
        guard let top = measure()?.top, top.isFinite else { return nil }
        return top
    }

    /// TS: `measurePill`.
    private func measuredPill(for anchor: PerchAnchor) -> PillFrame? {
        if let pill = anchor.pill {
            return pill
        }
        return measure()?.pill
    }

    // MARK: - Small helpers

    @discardableResult
    private func bumpMotion() -> Int {
        motionGeneration += 1
        return motionGeneration
    }

    private var sanitizedRunSpeed: Double {
        PerchHandoff.sanitizeRunSpeed(speed: profile.runSpeed)
    }

    private func springConfig(_ profileSpring: TabPetCore.SpringConfig) -> SpringConfig {
        SpringConfig(duration: profileSpring.duration, dampingRatio: profileSpring.dampingRatio)
    }

    private func emitRenderState() {
        onRenderState?(buildState())
    }

    private func buildState() -> PerchRenderState {
        PerchRenderState(
            x: xTrack.currentValue,
            seatY: seatYTrack.currentValue,
            hop: hopTrack.currentValue,
            flightLift: flightLiftTrack.currentValue,
            rotationDegrees: rotationTrack.currentValue,
            visible: visibleTrack.currentValue,
            pose: pose,
            facing: facing,
            busy: busy,
            barTop: barTop
        )
    }
}
