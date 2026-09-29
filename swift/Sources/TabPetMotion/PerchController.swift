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
/// `pill` has no separate "explicitly no pill" state.
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

/// One phase of a finger on the tab bar, as the finger source reports it.
package enum FingerPhase: Sendable {
    case began, moved, ended, cancelled
}

/// The tab-change and finger paths of `companion-perch.tsx`, on plain stored
/// properties and `MotionEngine` tracks. Platform neutral, tested on macOS with
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
    /// Travel from the touch-down x, in pt, before a touch counts as a drag:
    /// a tap also fires the bar's pan recognizer, began and ended on one slot.
    private static let dragEngagePt: Double = 6

    package var onError: ((MotionError, String) -> Void)?
    package var onRenderState: ((PerchRenderState) -> Void)?
    /// Whether the bar's own scrub selects on release (`.native`) or the host
    /// does, through `onDragRelease` (`.exclusive`).
    package var barScrub: BarScrub = .native
    /// Called once, with the slot, for an ended drag released over another
    /// slot in `.exclusive` mode. Never for a cancelled drag.
    package var onDragRelease: ((Int) -> Void)?

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
    private let routeProgressTrack: MotionTrack

    private var pose: PupPose
    private var facing: Facing
    private var busy: Bool
    /// TS: `motionSpringRef` - the spring that drove the motion currently in
    /// progress, so `flightLift`'s own spring matches whatever caused it.
    private var motionSpring: TabPetCore.SpringConfig

    private var motionGeneration = 0
    private var releaseState = PerchHandoff.initialReleaseState()
    private var releaseTimerHandle: MotionCancellable?
    private var dragStartX: Double?
    private var dragEngaged = false
    /// Which hysteresis edge `chaseStep` uses.
    private var chasing = false
    private var lastGlassTarget: Double?
    private var farApproach: FarApproachAnimation?
    private var farApproachOn = false
    private var farApproachGeneration = 0
    /// Nonzero while one finger call runs: render states requested inside it
    /// are folded into the single one emitted at its end.
    private var transactionDepth = 0
    private var slotCenters: [Double]?
    private var barTop: Double?
    private var lastPill: PillFrame?
    private var hasActiveFocus = false
    private var stopRemeasure: (@MainActor @Sendable () -> Void)?
    private var unsubscribeBusy: (@MainActor @Sendable () -> Void)?
    private var activeRoute: ActiveRoute?
    private var interruptedRoute: InterruptedRoute?

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
        self.routeProgressTrack = engine.makeTrack(label: "perch.routeProgress", initialValue: 0)

        self.motionSpring = profile.trackSpring
        self.pose = .sit
        self.facing = .right
        self.busy = busy.isCompanionBusy()

        // Shared-engine mode: whoever owns the engine owns this slot - a
        // view running both a controller and a sprite player on one engine
        // must combine their reporting itself to route both.
        engine.onError = { [weak self] error, label in self?.handleEngineError(error, label) }

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
    /// expected every tick something is moving. While a route is active,
    /// x, seatY and rotation all come from one pose call here.
    package func renderTick() {
        applyRoutePose()
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

        // Consumed at most once per focus, and only by a focused pass, so an
        // interrupt survives an unfocused pass in between.
        let interrupted = interruptedRoute
        interruptedRoute = nil

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
            holdRun: interrupted != nil
        )

        let generation = bumpMotion()
        let liveXAtFocusStart = xTrack.currentValue

        cancelRoute()
        engine.cancel(rotationTrack)
        snapVerticalToSeat(PerchHandoff.planStartSeatY(kind: plan.kind, runSeatY: plan.runSeatY, fromSeatY: plan.fromSeatY))
        engine.cancel(xTrack)
        engine.set(xTrack, plan.fromX)

        switch plan.kind {
        case .runChase:
            let choice = routeChoice(
                interrupted: interrupted,
                pill: pillNow,
                plan: plan,
                fromSlot: PerchHandoff.focusFromSlot(handoffLastTab: handoffState.lastTab, arrivedByDrag: arrivedByDrag, focusedSlot: anchor.slotIndex),
                reduceMotionOn: reduceMotionOn
            )
            switch choice {
            case .resumed(let route):
                runResumedRoute(route, targetX: plan.targetX, generation: generation)
            case .around(let path):
                runAroundRoute(path, targetX: plan.targetX, generation: generation)
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
        releaseState = PerchHandoff.reduceRelease(state: releaseState, event: .unmount).state
        releaseTimerHandle?.cancel()
        releaseTimerHandle = nil
        stopFarApproach()
        resetDragState()
        engine.remove(xTrack)
        engine.remove(hopTrack)
        engine.remove(seatYTrack)
        engine.remove(flightLiftTrack)
        engine.remove(rotationTrack)
        engine.remove(visibleTrack)
        engine.remove(routeProgressTrack)
        activeRoute = nil
        interruptedRoute = nil
    }

    // MARK: - Test-only hooks

    /// Test-only: seeds the release-state machine directly, so a test can
    /// exercise an arrived-by-drag catch without driving a whole drag.
    package var debugReleaseState: ReleaseState {
        get { releaseState }
        set { releaseState = newValue }
    }

    /// Test-only: bumps the motion generation without cancelling any active
    /// track, to stage a stale completion. See `PerchReentry`.
    @discardableResult
    package func debugBumpGeneration() -> Int {
        bumpMotion()
    }

    /// Test-only: sets `x` directly (a plain value, cancelling whatever was
    /// running), so a test can leave `x` off the seat before an
    /// arrived-by-drag catch runs.
    package func debugSetX(_ value: Double) {
        engine.set(xTrack, value)
    }

    // MARK: - Route choice

    private enum ActiveRoute {
        case around(AroundPath)
        case resumed(ResumedRoute)
    }

    /// A route cut off on its curve or underside: the base path and the
    /// progress along it where the animal was.
    private struct InterruptedRoute {
        let path: AroundPath
        let s: Double
    }

    private enum RunChaseRoute {
        case plain
        case around(AroundPath)
        case resumed(ResumedRoute)
    }

    /// TS: `resolveRunChaseRoute`. An interrupt of the curve or underside
    /// resumes first; only lacking that does a fresh end-to-end tap route around.
    private func routeChoice(
        interrupted: InterruptedRoute?,
        pill: PillFrame?,
        plan: FocusPlan,
        fromSlot: Int,
        reduceMotionOn: Bool
    ) -> RunChaseRoute {
        // The path is planned against the pill, but the perch is drawn
        // bottomExtra higher: a route from a raised seat would cross the pill.
        guard let pill, plan.runSeatY == 0, bottomExtra == 0 else { return .plain }
        if let interrupted, !reduceMotionOn,
           let route = PerchAround.resumeAroundRoute(base: interrupted.path, s: interrupted.s, targetX: plan.targetX) {
            return .resumed(route)
        }
        guard PerchAround.shouldRouteAround(
            fromSlot: fromSlot,
            toSlot: anchor.slotIndex,
            slotCount: anchor.slotCount,
            aroundRoute: profile.aroundRoute,
            flightLift: profile.flightLift,
            pill: pill,
            reduceMotion: reduceMotionOn
        ) else { return .plain }
        let path = PerchAround.planAroundPath(
            fromX: plan.fromX,
            targetX: plan.targetX,
            pill: pill,
            windowWidth: screenWidth,
            spriteScale: profile.scale,
            footPad: profile.resolvedFootPad,
            headPad: profile.resolvedHeadPad,
            seatOffset: profile.resolvedSeatLift - PerchGeometry.seatedFootPad(footPad: profile.resolvedFootPad, scale: profile.scale)
        )
        return .around(path)
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

    /// TS: `runAroundRoute`. One progress clock drives x, seatY and rotation
    /// together through `applyRoutePose`.
    private func runAroundRoute(_ path: AroundPath, targetX: Double, generation: Int) {
        setFacing(path.facing)
        motionSpring = profile.commitSpring
        setPose(.run)
        activeRoute = .around(path)
        engine.set(routeProgressTrack, 0)
        let timing = TimingAnimation(toValue: path.totalLen, config: TimingConfig(duration: path.totalMs, easing: { Easing.linear($0) }))
        engine.start(
            routeProgressTrack,
            DelayAnimation(Self.chaseReactionMs, timing),
            maxAgeMs: Self.chaseReactionMs + path.totalMs + Self.runLegSettleMs
        ) { [weak self] finished in
            guard finished else { return }
            self?.finishRoute(targetX: targetX, generation: generation)
        }
    }

    /// TS: `runResumedRoute`. Continues the outline from where the animal is,
    /// with no reaction pause: it is already moving.
    private func runResumedRoute(_ route: ResumedRoute, targetX: Double, generation: Int) {
        setFacing(route.facing)
        motionSpring = profile.commitSpring
        setPose(.run)
        activeRoute = .resumed(route)
        // Pose first, so no render state of this focus shows a seated animal.
        let start = PerchAround.resumedPose(route: route, u: 0)
        engine.set(xTrack, start.x)
        engine.set(seatYTrack, start.seatY)
        engine.set(rotationTrack, start.rotation)
        engine.set(routeProgressTrack, 0)
        let timing = TimingAnimation(toValue: route.totalLen, config: TimingConfig(duration: route.totalMs, easing: { Easing.linear($0) }))
        engine.start(routeProgressTrack, timing, maxAgeMs: route.totalMs + Self.runLegSettleMs) { [weak self] finished in
            guard finished else { return }
            self?.finishRoute(targetX: targetX, generation: generation)
        }
    }

    /// The route ended on the seat line: drop it, zero the turn (360 is 0)
    /// and catch on the target.
    private func finishRoute(targetX: Double, generation: Int) {
        activeRoute = nil
        engine.set(rotationTrack, 0)
        engine.set(seatYTrack, 0)
        engine.start(xTrack, SpringAnimation(toValue: targetX, config: springConfig(profile.catchSpring))) { [weak self] finished in
            guard finished else { return }
            self?.arrive(generation: generation)
        }
    }

    /// Stops a route dead: drops the path so `applyRoutePose` writes nothing
    /// more, and cancels the progress clock.
    private func cancelRoute() {
        activeRoute = nil
        engine.cancel(routeProgressTrack)
    }

    private func applyRoutePose() {
        guard let route = activeRoute else { return }
        let progress = routeProgressTrack.currentValue
        let pose: AroundPose
        switch route {
        case .around(let path):
            pose = PerchAround.aroundPose(path: path, s: progress)
        case .resumed(let resumed):
            pose = PerchAround.resumedPose(route: resumed, u: progress)
        }
        engine.set(xTrack, pose.x)
        engine.set(seatYTrack, pose.seatY)
        engine.set(rotationTrack, pose.rotation)
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

    // MARK: - Finger

    /// TS: the finger-source callback. Ignored with no active focus, on a
    /// transient slot, under Reduce Motion, and for a non-finite began or
    /// moved x. One call emits at most one render state, at its end.
    package func handleFinger(x: Double, phase: FingerPhase) {
        guard hasActiveFocus, !transientSlot, !reduceMotion() else { return }
        switch phase {
        case .began, .moved:
            guard x.isFinite else { return }
        case .ended, .cancelled:
            break
        }
        transactionDepth += 1
        var releasedOver: Int?
        switch phase {
        case .began:
            fingerBegan(x: x)
        case .moved:
            fingerMoved(x: x)
        case .ended:
            releasedOver = handleDragEnd(phase: .ended)
        case .cancelled:
            releasedOver = handleDragEnd(phase: .cancelled)
        }
        transactionDepth -= 1
        emitRenderState()
        // After the settle is recorded: a host that selects the slot from
        // inside this callback re-enters `focus`, which must find the pending
        // release already in place.
        if let releasedOver {
            onDragRelease?(releasedOver)
        }
    }

    /// The finger source went away or changed. A live drag chase that owns x
    /// is cancelled and the pose rests; a release approach, an arrival catch
    /// and the grace timer belong to the release path and are never touched.
    package func resetFinger() {
        let owned = dragEngaged || chasing
        if owned {
            stopFarApproach()
            engine.cancel(xTrack)
            cancelRoute()
        }
        resetDragState()
        stopFarApproach()
        if owned, mounted() {
            rest()
        }
    }

    private func resetDragState() {
        dragStartX = nil
        dragEngaged = false
        chasing = false
        lastGlassTarget = nil
    }

    private func fingerBegan(x: Double) {
        dragStartX = x
        dragEngaged = false
        chasing = false
        stopFarApproach()
        // The touch may turn out to be a tap: while a release is pending,
        // bumping the generation would strand the animal over the wrong slot
        // in the run pose if the touch never engages.
        let result = PerchHandoff.reduceRelease(state: releaseState, event: .began)
        releaseState = result.state
        if result.effect != .holdGeneration {
            bumpMotion()
        }
        // A bar drag mid-route must not leave the animal rotated or under the pill.
        engine.set(rotationTrack, 0)
        cancelRoute()
        if seatYTrack.currentValue > bottomExtra {
            engine.start(seatYTrack, SpringAnimation(toValue: bottomExtra, config: springConfig(profile.trackSpring)))
        }
    }

    private func fingerMoved(x: Double) {
        let glassTarget = PerchGeometry.glassTargetX(fingerX: x, screenWidth: screenWidth)
        var startedFarApproach = false
        if !dragEngaged {
            let startX = dragStartX ?? x
            guard abs(x - startX) > Self.dragEngagePt else { return }
            dragEngaged = true
            startedFarApproach = beginFarApproachIfNeeded(startX: startX, glassAtEngage: glassTarget)
            // A real drag is engaging: any release it was waiting on no longer applies.
            let result = PerchHandoff.reduceRelease(state: releaseState, event: .engage)
            releaseState = result.state
            if result.effect == .clearTimer {
                releaseTimerHandle?.cancel()
                releaseTimerHandle = nil
            }
        }
        lastGlassTarget = glassTarget
        if bottomExtra > 0 {
            // The drag happens on the glass: drop from a raised seat to bar level.
            engine.start(seatYTrack, SpringAnimation(toValue: bottomExtra, config: springConfig(profile.trackSpring)))
        }
        // The glass position, not the trailing animal, is what the next screen hands off from.
        handoffStore.writePerchHandoff(next: PerchHandoff.applyDragTrack(handoff: handoffStore.readPerchHandoff(), glassTarget: glassTarget))

        if startedFarApproach || trackFarApproachSample(glassTarget) {
            return
        }

        // Leash follower: inside the trail the animal holds its ground, and
        // it only ever runs toward the glass.
        let step = PerchGeometry.chaseStep(glassX: glassTarget, currentX: xTrack.currentValue, currentFacing: facing, chasing: chasing)
        if step.target == nil {
            chasing = false
            stopFarApproach()
            // Soft brake: a spring on x cancels the in-flight one, else a running
            // commit chase keeps sliding under the resting sprite.
            engine.start(xTrack, SpringAnimation(toValue: xTrack.currentValue, config: springConfig(profile.trackSpring)))
            rest()
            return
        }
        chasing = true
        if step.facing != facing {
            setFacing(step.facing)
        }
        motionSpring = profile.trackSpring
        setPose(.run)
        // An abrupt stop has no further sample to stand the animal down, so
        // the last track spring's completion rests it at the finger.
        let generation = bumpMotion()
        let target = PerchGeometry.chaseTargetX(glassX: glassTarget, direction: step.facing, screenWidth: screenWidth)
        engine.start(xTrack, SpringAnimation(toValue: target, config: springConfig(profile.trackSpring))) { [weak self] finished in
            guard finished else { return }
            self?.arrive(generation: generation)
        }
    }

    // MARK: - Far approach

    /// Far is judged from where the finger came down, not from this sample: a
    /// fast flick that starts on the animal keeps the spring follower. The
    /// sample that starts an approach does nothing else.
    private func beginFarApproachIfNeeded(startX: Double, glassAtEngage: Double) -> Bool {
        let liveX = xTrack.currentValue
        guard PerchHandoff.isFarGrab(gapPt: PerchGeometry.glassTargetX(fingerX: startX, screenWidth: screenWidth) - liveX) else {
            return false
        }
        // The engage sample goes through the same leash test as every later
        // one: a landing spot behind the animal falls through to the leash.
        guard case .track(let target, let planFacing) = PerchHandoff.planFarSample(glassX: glassAtEngage, currentX: liveX, screenWidth: screenWidth) else {
            return false
        }
        // The approach, not a leftover spring, owns x from here.
        engine.cancel(xTrack)
        let generation = bumpMotion()
        farApproachGeneration = generation
        if planFacing != facing {
            setFacing(planFacing)
        }
        motionSpring = profile.trackSpring
        setPose(.run)
        let speed = sanitizedRunSpeed
        let animation = FarApproachAnimation(toValue: target, speedPtS: speed)
        farApproach = animation
        farApproachOn = true
        // A whole bar at this animal's own speed, plus a settle allowance, so a
        // slow animal is never cut short by the engine's default age guard.
        let ceilingMs = (screenWidth / speed) * 1000 + Self.runLegSettleMs
        engine.start(xTrack, animation, maxAgeMs: ceilingMs.isFinite ? ceilingMs : nil) { [weak self] _ in
            self?.farApproachEnded(generation: generation)
        }
        return true
    }

    /// The approach's one end report, whether it arrived or the engine's age
    /// guard cut it: acts only while the approach is still ours and belongs to
    /// the current motion, so a still finger after a far grab rests.
    private func farApproachEnded(generation: Int) {
        guard farApproachOn, generation == motionGeneration else { return }
        stopFarApproach()
        arrive(generation: generation)
    }

    /// During an approach only the target moves; the animation steps x.
    private func trackFarApproachSample(_ glassTarget: Double) -> Bool {
        guard farApproachOn, let animation = farApproach else { return false }
        let plan = PerchHandoff.planFarSample(glassX: glassTarget, currentX: xTrack.currentValue, screenWidth: screenWidth)
        switch plan {
        case .end:
            let generation = farApproachGeneration
            stopFarApproach()
            arrive(generation: generation)
        case .track(let target, let planFacing):
            if planFacing != facing {
                setFacing(planFacing)
            }
            animation.retarget(target)
        }
        return true
    }

    /// Flag off first, so the cancel's own completion is ignored. Touches x
    /// only when an approach was running: most callers run it defensively.
    private func stopFarApproach() {
        let wasOn = farApproachOn
        farApproachOn = false
        farApproach = nil
        if wasOn {
            engine.cancel(xTrack)
        }
    }

    // MARK: - Release

    /// TS: `handleDragEnd`. Returns the slot `onDragRelease` is owed, if any.
    private func handleDragEnd(phase: DragPhase) -> Int? {
        guard dragEngaged else {
            // A tap, not a drag: leave the handoff alone, let the native
            // selection drive the commit chase.
            dragStartX = nil
            lastGlassTarget = nil
            return nil
        }
        dragEngaged = false
        chasing = false
        stopFarApproach()
        dragStartX = nil
        let releaseX = lastGlassTarget
            ?? PerchGeometry.tabCenterX(tab: anchor.slotIndex, screenWidth: screenWidth, slotCount: anchor.slotCount, slotCenters: slotCenters)
        lastGlassTarget = nil
        handoffStore.writePerchHandoff(
            next: PerchHandoff.applyDragRelease(handoff: handoffStore.readPerchHandoff(), tab: anchor.slotIndex, releaseX: releaseX, bottomExtra: bottomExtra)
        )
        let releaseSlot = PerchGeometry.nearestSlot(
            x: releaseX + PerchGeometry.PERCH_SIZE / 2,
            screenWidth: screenWidth,
            slotCount: anchor.slotCount,
            slotCenters: slotCenters
        )
        let home = PerchGeometry.tabCenterX(tab: anchor.slotIndex, screenWidth: screenWidth, slotCount: anchor.slotCount, slotCenters: slotCenters)
        // Whether the released-over slot gets selected is a property of the
        // bar, not of who supplies the touches. A pill the host passed for its
        // own bar does not count.
        let nativePill = anchor.pill == nil && measure()?.pill != nil
        let plan = PerchHandoff.planDragRelease(
            phase: phase,
            releaseSlot: releaseSlot,
            currentSlot: anchor.slotIndex,
            selectsOnRelease: PerchHandoff.selectsOnRelease(barScrub: barScrub, hasOnDragRelease: onDragRelease != nil, nativePill: nativePill)
        )
        settleAfterRelease(plan, home: home)
        // A cancelled drag must not navigate: only an ended one reports.
        guard phase == .ended, barScrub == .exclusive, releaseSlot != anchor.slotIndex else { return nil }
        return releaseSlot
    }

    /// TS: `settleAfterRelease`. Home at once, or approach the awaited slot
    /// and arm the grace timer that falls back home if no selection lands.
    private func settleAfterRelease(_ plan: DragReleasePlan, home: Double) {
        let generation = bumpMotion()
        let result = PerchHandoff.reduceRelease(
            state: releaseState,
            event: .release(plan: plan, fromSlot: anchor.slotIndex, generation: generation)
        )
        releaseState = result.state
        if result.effect == .goHome {
            approach(home, generation: generation)
            engine.start(seatYTrack, SpringAnimation(toValue: 0, config: springConfig(profile.catchSpring)))
            return
        }
        guard result.effect == .await, let pending = result.state.pending else { return }
        approach(
            PerchGeometry.tabCenterX(tab: pending.slot, screenWidth: screenWidth, slotCount: anchor.slotCount, slotCenters: slotCenters),
            generation: generation
        )
        // seatY stays at bar level: the next focus plans the rise onto its own raised seat.
        releaseTimerHandle?.cancel()
        releaseTimerHandle = clock.after(milliseconds: PerchHandoff.RELEASE_GRACE_MS) { [weak self] in
            self?.releaseGraceElapsed()
        }
    }

    private func releaseGraceElapsed() {
        let result = PerchHandoff.reduceRelease(
            state: releaseState,
            event: .timer(mounted: mounted(), generation: motionGeneration, renderedSlot: anchor.slotIndex)
        )
        releaseState = result.state
        releaseTimerHandle = nil
        if result.effect == .goHome {
            goHome()
        }
        emitRenderState()
    }

    /// Reads the anchor, width and centers at call time: the grace timer may
    /// have been armed long before it fires.
    private func goHome() {
        let home = PerchGeometry.tabCenterX(tab: anchor.slotIndex, screenWidth: screenWidth, slotCount: anchor.slotCount, slotCenters: slotCenters)
        let generation = bumpMotion()
        approach(home, generation: generation)
        engine.start(seatYTrack, SpringAnimation(toValue: 0, config: springConfig(profile.catchSpring)))
    }

    /// TS: `approach`. Distance-aware, used by every release path: a spring
    /// under one glass width, a constant-speed run otherwise. No reaction
    /// pause and no hop: the animal is already moving.
    private func approach(_ targetX: Double, generation: Int) {
        let liveX = xTrack.currentValue
        let direction = PerchGeometry.travelFacing(targetX: targetX, currentX: liveX, currentFacing: facing)
        if direction != facing {
            setFacing(direction)
        }
        let completion: (Bool) -> Void = { [weak self] finished in
            guard finished else { return }
            self?.arrive(generation: generation)
        }
        switch PerchHandoff.planApproach(distancePt: targetX - liveX, speedPtS: sanitizedRunSpeed) {
        case .spring:
            engine.start(xTrack, SpringAnimation(toValue: targetX, config: springConfig(profile.catchSpring)), completion: completion)
        case .run(let durationMs):
            setPose(.run)
            let runLeg = SequenceAnimation(
                TimingAnimation(toValue: targetX, config: TimingConfig(duration: durationMs, easing: { Easing.linear($0) })),
                SpringAnimation(toValue: targetX, config: springConfig(profile.catchSpring))
            )
            engine.start(xTrack, runLeg, maxAgeMs: durationMs + Self.runLegSettleMs, completion: completion)
        }
    }

    /// A non-finite value on a perch track while the finger owns x: recover
    /// the way a mid-drag throw does, so nothing is left wedged. The error
    /// still reaches `onError`.
    private func handleEngineError(_ error: MotionError, _ label: String) {
        onError?(error, label)
        guard label.hasPrefix("perch."), dragEngaged || chasing || farApproachOn else { return }
        resetDragState()
        stopFarApproach()
        let result = PerchHandoff.reduceRelease(state: releaseState, event: .abort)
        releaseState = result.state
        if result.effect == .clearTimer {
            releaseTimerHandle?.cancel()
            releaseTimerHandle = nil
        }
        engine.cancel(xTrack)
        cancelRoute()
        if mounted() {
            rest()
        }
    }

    // MARK: - Blur

    /// TS: the focus effect's own cleanup. A route cut off on its curve or
    /// underside is staged for the next focus, and the handoff then records
    /// bar level, since the route owns the vertical mid-flight.
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
        stageInterrupt()
        let liveSeat = PerchHandoff.liveLastSeat(bottomExtra: bottomExtra, seatY: interruptedRoute == nil ? seatYTrack.currentValue : 0)

        // Flag off before x is cancelled, so the approach's own cancel
        // completion cannot rest a pose this blur is about to set anyway.
        stopFarApproach()
        engine.cancel(xTrack)
        resetDragState()
        cancelRoute()
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

    private func stageInterrupt() {
        let progress = routeProgressTrack.currentValue
        switch activeRoute {
        case .around(let path):
            let onCurve = path.legs.count > 3 && progress > path.legs[0] && progress < path.legs[3]
            interruptedRoute = onCurve ? InterruptedRoute(path: path, s: progress) : nil
        case .resumed(let route):
            interruptedRoute = PerchAround.resumedBaseS(route: route, u: progress).map { InterruptedRoute(path: route.base, s: $0) }
        case nil:
            interruptedRoute = nil
        }
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
        // The idle sheet is the busy presentation: it never interrupts a
        // run or a drag, so the flag is stored and the pose left alone.
        if dragEngaged || chasing {
            emitRenderState()
            return
        }
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
        cancelRoute()
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
    /// did not itself start a run-chase or a drag chase, which must never be yanked.
    private func applyRemeasure(_ layout: BarLayout, generation: Int, kindAtFocus: FocusKind, commitsHandoff: Bool) {
        slotCenters = layout.centers
        if let barTopFound = measuredBarTop(for: anchor) {
            barTop = barTopFound
        }
        let pillFound = measuredPill(for: anchor)
        lastPill = pillFound ?? lastPill

        let seated = motionGeneration == generation && kindAtFocus != .runChase && !chasing && !dragEngaged && activeRoute == nil
        guard seated else { return }

        let seat = PerchGeometry.tabCenterX(tab: anchor.slotIndex, screenWidth: screenWidth, slotCount: anchor.slotCount, slotCenters: slotCenters)
        stopFarApproach()
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
        guard transactionDepth == 0 else { return }
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
