#if canImport(UIKit)
import QuartzCore
import UIKit

import TabPetCore
import TabPetMotion

/// Host-supplied tab bar anchor: window-space slot centers, the bar's top
/// edge and the floating pill, nil meaning "measure it natively instead".
/// Public mirror of TabPetMotion's package-only `PerchAnchor`.
public struct CompanionAnchor: Equatable, Sendable {
    public var slotCount: Int
    public var slotIndex: Int
    public var slotCenters: [Double]?
    public var barTop: Double?
    public var pill: PillFrame?

    public init(slotCount: Int, slotIndex: Int, slotCenters: [Double]? = nil, barTop: Double? = nil, pill: PillFrame? = nil) {
        self.slotCount = slotCount
        self.slotIndex = slotIndex
        self.slotCenters = slotCenters
        self.barTop = barTop
        self.pill = pill
    }
}

/// Reported through `onError` for a host-supplied number this view refused
/// at its own boundary, before it could reach the controller.
public enum CompanionPerchError: Error, Sendable, Equatable {
    case invalidNumber(Double)
    /// A host-supplied `anchor.slotCount` below 1 - reported separately
    /// from `invalidNumber`, since it's an `Int`, not a bad `Double`.
    case invalidSlotCount(Int)
    case noProfileRegistered
}

/// Handle for one `FingerSource` subscription. `cancel()` is idempotent.
@MainActor
public final class FingerSubscription {
    private var onCancel: (@MainActor () -> Void)?

    public init(onCancel: @escaping @MainActor () -> Void) {
        self.onCancel = onCancel
    }

    /// Stops the events. Safe to call more than once.
    public func cancel() {
        let handler = onCancel
        onCancel = nil
        handler?()
    }
}

/// A feed of finger samples in window space, the counterpart of a native
/// tab bar recognizer for a bar the library cannot attach to.
public protocol FingerSource: AnyObject {
    /// Starts delivering events to `listener` until the subscription is cancelled.
    @MainActor func subscribe(_ listener: @escaping @MainActor (PanEvent) -> Void) -> FingerSubscription
}

/// Where the perch reads the finger from.
public enum FingerSourceChoice {
    /// A pan recognizer this view adds to the tab bar.
    case nativeTabBar
    /// A host-supplied feed, for a custom bar.
    case custom(FingerSource)
    /// No finger events at all.
    case none
}

/// Holds a weak reference to the owning view, so closures built before
/// `self` finishes initializing can still reach it afterward - the same
/// weak-target indirection `DisplayLinkClock`'s own proxy uses.
@MainActor
private final class PerchViewBox {
    weak var view: CompanionPerchView?
}

/// A companion sitting on a real tab bar. It runs when the tab changes and
/// chases a finger that drags along the bar. Owns one clock and engine,
/// shared with its embedded sprite view, and installs their frame handler.
@MainActor
public final class CompanionPerchView: UIView {
    // MARK: - Public API

    public var companionID: String {
        didSet {
            guard !isTornDown, companionID != oldValue else { return }
            spriteView.companionID = companionID
            applyProfile(Self.resolveProfile(companionID: companionID, registry: registry))
            controller.updateProfile(profile)
            applyRenderState()
        }
    }

    public var anchor: CompanionAnchor {
        didSet {
            guard !isTornDown, anchor != oldValue else { return }
            let (sanitized, error) = Self.sanitizeAnchor(anchor)
            sanitizedAnchor = sanitized
            reportAnchorErrorIfNeeded(error)
            runFocusPass()
        }
    }

    /// Named `isPerchFocused`, not plain `isFocused`: `UIView` already
    /// declares a read-only `isFocused` for the tvOS focus engine, an
    /// unrelated system this library's own sense of it must not join.
    public var isPerchFocused: Bool = true {
        didSet {
            guard !isTornDown, isPerchFocused != oldValue else { return }
            runFocusPass()
        }
    }

    public var transientSlot: Bool = false {
        didSet {
            guard !isTornDown, transientSlot != oldValue else { return }
            runFocusPass()
        }
    }

    /// Non-finite input is refused outright (left at its prior value) and
    /// reported through `onError` - it never reaches the controller.
    public var bottomExtra: Double {
        get { _bottomExtra }
        set {
            guard !isTornDown else { return }
            guard newValue.isFinite else {
                onError?(CompanionPerchError.invalidNumber(newValue), "CompanionPerchView.bottomExtra")
                return
            }
            guard newValue != _bottomExtra else { return }
            _bottomExtra = newValue
            runFocusPass()
        }
    }

    /// Whether the bar's own scrub rides along (`.native`) or the host
    /// selects the tab on release through `onDragRelease` (`.exclusive`).
    /// Applies live.
    public var barScrub: BarScrubMode = .native {
        didSet {
            panObserver?.scrubMode = barScrub
            controller.barScrub = Self.coreScrub(barScrub)
        }
    }

    /// Called once with the slot when a drag ends over another slot in
    /// `.exclusive` mode. Never for a cancelled drag.
    public var onDragRelease: ((Int) -> Void)? {
        didSet { controller.onDragRelease = onDragRelease }
    }

    /// Where finger samples come from. Changing it drops any drag in
    /// progress, so the animal cannot be left running.
    public var fingerSource: FingerSourceChoice = .nativeTabBar {
        didSet {
            guard !isTornDown else { return }
            stopFingerSources()
            controller.resetFinger()
            applyRenderState()
            syncFingerSource()
        }
    }

    public var onAction: (() -> Void)?

    public var actionLabel: String? {
        didSet { spriteView.pressAccessibilityLabel = actionLabel }
    }

    public var onHaptic: ((HapticKind) -> Void)?
    public var onError: ((Error, String) -> Void)?

    // MARK: - Init

    private let registry: CompanionRegistry
    private let handoffStore: PerchHandoffStore
    private let busyState: CompanionState
    private let clock: DisplayLinkClock
    private let engine: MotionEngine
    private let controller: PerchController
    private let spriteView: CompanionSpriteView
    private let box: PerchViewBox

    private var profile: CompanionProfile
    private var spriteFrameRateFallback: Double = 24
    private var _bottomExtra: Double = 0
    private var hasEnteredWindowOnce = false
    /// Set once teardown has run (`willMove(toSuperview: nil)` or
    /// `detach()`, never deinit - no isolated deinit in Swift 5.9) - every
    /// setter is inert on a torn-down view.
    private var isTornDown = false
    private var lastKnownScreenWidth: Double
    private var lastKnownScreenHeight: Double
    /// The sanitized form of `anchor`, recomputed only when `anchor` itself
    /// changes - `runFocusPass` reads this rather than re-sanitizing.
    private var sanitizedAnchor: PerchAnchor
    /// True while the current anchor is invalid - `onError` fires only on
    /// the transition into this state, not on every distinct invalid anchor
    /// (a host at slotCount 0 changes `anchor.slotIndex` on every tab change).
    private var isAnchorInvalid = false
    private var panObserver: TabBarPanObserver?
    private var customSubscription: FingerSubscription?
    private weak var hostTabBar: UITabBar?

    public init(
        companionID: String = CompanionId.DEFAULT_COMPANION_ID,
        registry: CompanionRegistry = .shared,
        anchor: CompanionAnchor,
        handoff: PerchHandoffStore = PerchHandoffStore(),
        busy: CompanionState = .shared,
        onError: ((Error, String) -> Void)? = nil
    ) {
        let resolvedProfile = Self.resolveProfile(companionID: companionID, registry: registry)
        let clock = DisplayLinkClock()
        // Suspended before anything touches the engine below: a fresh view
        // has no window yet, and this keeps the link from ever starting on
        // whatever handler happens to be installed mid-construction.
        clock.suspend()
        let engine = MotionEngine(clock: clock)
        let box = PerchViewBox()

        self.companionID = companionID
        self.registry = registry
        self.anchor = anchor
        self.handoffStore = handoff
        self.busyState = busy
        self.onError = onError
        self.clock = clock
        self.engine = engine
        self.box = box
        self.profile = resolvedProfile
        self.lastKnownScreenWidth = Double(UIScreen.main.bounds.width)
        self.lastKnownScreenHeight = Double(UIScreen.main.bounds.height)
        let (sanitizedAnchor, initialAnchorError) = Self.sanitizeAnchor(anchor)
        self.sanitizedAnchor = sanitizedAnchor
        self.isAnchorInvalid = initialAnchorError != nil
        if let initialAnchorError {
            onError?(initialAnchorError, "CompanionPerchView.anchor")
        }

        self.controller = PerchController(
            profile: resolvedProfile,
            anchor: sanitizedAnchor,
            transientSlot: false,
            bottomExtra: 0,
            screenWidth: lastKnownScreenWidth,
            mounted: { box.view?.window != nil },
            measure: {
                guard let window = box.view?.window, let layout = TabBarMeasurer.measure(in: window) else { return nil }
                return BarLayout(centers: layout.centers, top: layout.top, pill: layout.pill)
            },
            reduceMotion: { UIAccessibility.isReduceMotionEnabled },
            clock: clock,
            engine: engine,
            handoff: handoff,
            busy: busy,
            onError: nil
        )
        self.spriteView = CompanionSpriteView(
            companionID: companionID,
            registry: registry,
            size: CGFloat(PerchGeometry.PERCH_SIZE),
            engine: engine,
            clock: clock,
            onError: { error, site in box.view?.onError?(error, site) }
        )

        super.init(frame: .zero)
        box.view = self
        applyProfile(resolvedProfile)

        backgroundColor = .clear
        addSubview(spriteView)
        spriteView.pressAccessibilityLabel = actionLabel
        spriteView.onPress = { [weak self] in self?.onAction?() }
        spriteView.onHaptic = { [weak self] kind in self?.onHaptic?(kind) }

        controller.onError = { [weak self] error, label in self?.onError?(error, label) }
        clock.frameHandler = { [weak self] now in self?.handleFrame(now: now) }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reduceMotionStatusDidChange),
            name: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil
        )

        applyRenderState()
    }

    @available(*, unavailable, message: "use init(companionID:registry:anchor:handoff:busy:onError:) - CompanionPerchView is never loaded from a nib")
    public required init?(coder: NSCoder) {
        return nil
    }

    // No deinit: Swift 5.9 has no isolated deinit, and a plain one can't
    // reach this actor-isolated teardown. Busy tracking activates once, on
    // the first window entry, and deactivates only in teardownIfNeeded().

    private static func resolveProfile(companionID: String, registry: CompanionRegistry) -> CompanionProfile {
        registry.get(companionID) ?? registry.get(CompanionId.DEFAULT_COMPANION_ID) ?? registry.list().first ?? fallbackProfile
    }

    /// Clamps `slotCount` to at least 1 and drops a non-finite pill, bar top
    /// or slot center. Returns the error to report, if any, rather than
    /// reporting it directly - the caller decides whether this is a new one.
    private static func sanitizeAnchor(_ anchor: CompanionAnchor) -> (PerchAnchor, CompanionPerchError?) {
        var sawInvalidNumber = false

        let rawSlotCount = anchor.slotCount
        let slotCount = max(1, rawSlotCount)
        let slotCountInvalid = slotCount != rawSlotCount

        var slotCenters = anchor.slotCenters
        if let centers = slotCenters, !centers.allSatisfy(\.isFinite) {
            slotCenters = nil
            sawInvalidNumber = true
        }

        var barTop = anchor.barTop
        if let top = barTop, !top.isFinite {
            barTop = nil
            sawInvalidNumber = true
        }

        var pill = anchor.pill
        if let p = pill, !(p.x.isFinite && p.y.isFinite && p.width.isFinite && p.height.isFinite) {
            pill = nil
            sawInvalidNumber = true
        }

        // Slot count wins when both are bad in the same anchor - one
        // report, not two, and the more fundamental of the two problems.
        let error: CompanionPerchError?
        if slotCountInvalid {
            error = .invalidSlotCount(rawSlotCount)
        } else if sawInvalidNumber {
            error = .invalidNumber(.nan)
        } else {
            error = nil
        }
        let sanitized = PerchAnchor(slotCount: slotCount, slotIndex: anchor.slotIndex, slotCenters: slotCenters, barTop: barTop, pill: pill)
        return (sanitized, error)
    }

    /// Reports `error` through `onError` only on the transition from a valid
    /// anchor into an invalid one - repeated invalid anchors (e.g. `selectTab`
    /// while `slotCount` is still 0) report nothing further until a valid one arrives.
    private func reportAnchorErrorIfNeeded(_ error: CompanionPerchError?) {
        guard let error else {
            isAnchorInvalid = false
            return
        }
        guard !isAnchorInvalid else { return }
        isAnchorInvalid = true
        onError?(error, "CompanionPerchView.anchor")
    }

    /// Drawn nowhere (`sheets` is nil, same as a resource bundle that
    /// failed to resolve) - used only when the registry has nothing
    /// registered at all, so the controller always has a real profile to run.
    private static let fallbackProfile = CompanionProfile(
        id: "unresolved",
        label: "",
        runFps: CompanionProfile.IDLE_SHEET_GRID.fps,
        commitSpring: TabPetCore.SpringConfig(duration: 200, dampingRatio: 1),
        trackSpring: TabPetCore.SpringConfig(duration: 200, dampingRatio: 1),
        catchSpring: TabPetCore.SpringConfig(duration: 200, dampingRatio: 1),
        hopHeight: 0,
        flightLift: 0,
        scale: 1,
        aroundRoute: false
    )

    private func applyProfile(_ newProfile: CompanionProfile) {
        profile = newProfile
        let fps = max(CompanionProfile.IDLE_SHEET_GRID.fps, newProfile.runFps, newProfile.resolvedSitSheet.fps)
        spriteFrameRateFallback = fps.isFinite && fps > 0 ? fps : 24
        if profile.sheets == nil {
            onError?(CompanionPerchError.noProfileRegistered, "CompanionPerchView.resolveProfile")
        }
    }

    // MARK: - Attaching to a host

    /// Adds this view above `tabBarController`'s tab bar, pinned to its
    /// bounds, window space throughout. One mounted perch is the default; a
    /// pushed screen adds a second on `transientSlot` and calls `detach()`.
    public func attach(to tabBarController: UITabBarController) {
        translatesAutoresizingMaskIntoConstraints = false
        tabBarController.view.addSubview(self)
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: tabBarController.view.leadingAnchor),
            trailingAnchor.constraint(equalTo: tabBarController.view.trailingAnchor),
            topAnchor.constraint(equalTo: tabBarController.view.topAnchor),
            bottomAnchor.constraint(equalTo: tabBarController.view.bottomAnchor),
        ])
        tabBarController.view.bringSubviewToFront(self)
        hostTabBar = tabBarController.tabBar
        syncFingerSource()
    }

    /// Removes this view from its superview and tears its controller and
    /// sprite tracks down for good - the counterpart of `attach(to:)`.
    /// Idempotent: safe to call more than once, or on a view never attached.
    public func detach() {
        removeFromSuperview()
        teardownIfNeeded()
    }

    /// Sets the slot index and re-asserts z order - the host calls this
    /// from its own tab bar controller delegate. A re-tap of the current
    /// tab still re-asserts z order, but never re-triggers a focus pass.
    public func selectTab(_ index: Int) {
        guard !isTornDown else { return }
        guard anchor.slotIndex != index else {
            superview?.bringSubviewToFront(self)
            return
        }
        anchor.slotIndex = index
        superview?.bringSubviewToFront(self)
    }

    public override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard spriteView.alpha >= 0.01, !spriteView.isHidden else { return false }
        let localPoint = spriteView.convert(point, from: self)
        return spriteView.bounds.contains(localPoint)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        guard !isTornDown else { return }
        let width = Double(window?.bounds.width ?? bounds.width)
        let height = Double(window?.bounds.height ?? bounds.height)
        if hasEnteredWindowOnce {
            var sizeChanged = false
            if width.isFinite, width != lastKnownScreenWidth {
                lastKnownScreenWidth = width
                sizeChanged = true
            }
            if height.isFinite, height != lastKnownScreenHeight {
                lastKnownScreenHeight = height
                sizeChanged = true
            }
            if sizeChanged { runFocusPass() }
        }
        applyRenderState()
        syncFingerSource()
    }

    public override func willMove(toSuperview newSuperview: UIView?) {
        super.willMove(toSuperview: newSuperview)
        guard newSuperview == nil else { return }
        teardownIfNeeded()
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        guard !isTornDown else { return }
        guard window != nil else {
            // A screen presented over this view's window (a full screen
            // modal, say) suspends the clock and blurs - it does not tear
            // the controller down, and the busy listener stays subscribed.
            clock.suspend()
            stopFingerSources()
            runFocusPass(isFocused: false)
            return
        }
        controller.activateBusyTracking()
        clock.resume()
        hasEnteredWindowOnce = true
        let width = Double(window?.bounds.width ?? bounds.width)
        let height = Double(window?.bounds.height ?? bounds.height)
        lastKnownScreenWidth = width.isFinite ? width : Double(UIScreen.main.bounds.width)
        lastKnownScreenHeight = height.isFinite ? height : Double(UIScreen.main.bounds.height)
        runFocusPass()
        syncFingerSource()
    }

    @objc private func reduceMotionStatusDidChange() {
        guard !isTornDown else { return }
        runFocusPass()
    }

    // MARK: - Focus pass

    /// `isFocused` defaults to `isPerchFocused`, unless off window (a
    /// covering full screen modal) - a pass while off window must never
    /// undo an earlier blur. Pass `false` for a blur-only pass on its own.
    private func runFocusPass(isFocused: Bool? = nil) {
        guard hasEnteredWindowOnce, !isTornDown else { return }
        debugFocusPassCount += 1
        controller.focus(
            anchor: sanitizedAnchor,
            isFocused: isFocused ?? (window == nil ? false : isPerchFocused),
            transientSlot: transientSlot,
            bottomExtra: bottomExtra,
            screenWidth: lastKnownScreenWidth
        )
        applyRenderState()
    }

    /// Idempotent, first caller wins between `willMove(toSuperview:)` and
    /// `detach()` (never deinit - no isolated deinit in Swift 5.9): suspends
    /// the clock, tears the controller and sprite view down, drops the observer.
    private func teardownIfNeeded() {
        guard !isTornDown else { return }
        isTornDown = true
        clock.suspend()
        stopFingerSources()
        controller.teardown()
        spriteView.teardown()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Finger

    private static func coreScrub(_ mode: BarScrubMode) -> BarScrub {
        switch mode {
        case .native: return .native
        case .exclusive: return .exclusive
        }
    }

    /// Brings the live source in line with `fingerSource`. Runs on every
    /// layout pass, so a bar that was not there yet is picked up later.
    private func syncFingerSource() {
        guard !isTornDown, let window else { return }
        switch fingerSource {
        case .nativeTabBar:
            customSubscription?.cancel()
            customSubscription = nil
            let observer = panObserver ?? makePanObserver()
            guard !observer.isAttached else { return }
            if let bar = hostTabBar ?? TabBarMeasurer.findTabBar(in: window) {
                observer.attach(to: bar)
            }
        case .custom(let source):
            panObserver?.detach()
            panObserver = nil
            guard customSubscription == nil else { return }
            customSubscription = source.subscribe { [weak self] event in self?.handleFingerEvent(event) }
        case .none:
            stopFingerSources()
        }
    }

    private func makePanObserver() -> TabBarPanObserver {
        let observer = TabBarPanObserver(scrubMode: barScrub) { [weak self] event in
            self?.handleFingerEvent(event)
        }
        panObserver = observer
        return observer
    }

    private func stopFingerSources() {
        panObserver?.detach()
        panObserver = nil
        customSubscription?.cancel()
        customSubscription = nil
    }

    private func handleFingerEvent(_ event: PanEvent) {
        guard !isTornDown else { return }
        let phase: FingerPhase
        switch event.phase {
        case .began: phase = .began
        case .moved: phase = .moved
        case .ended: phase = .ended
        case .cancelled: phase = .cancelled
        }
        if phase == .began || phase == .moved, !event.x.isFinite { return }
        controller.handleFinger(x: event.x, phase: phase)
        applyRenderState()
    }

    // MARK: - Frame handler

    private func handleFrame(now: Double) {
        engine.tick(now: now)
        controller.renderTick()
        spriteView.renderTick()
        applyRenderState()
    }

    private func applyRenderState() {
        let state = controller.currentState
        updateFrameRateHint()

        let windowHeight = Double(window?.bounds.height ?? bounds.height)
        let rest = PerchLayout.spriteFrame(
            barTop: state.barTop,
            windowHeight: windowHeight,
            insetsBottom: Double(safeAreaInsets.bottom),
            perchBottomOffset: profile.resolvedSeatLift - PerchGeometry.seatedFootPad(footPad: profile.resolvedFootPad, scale: profile.scale),
            bottomExtra: bottomExtra,
            perchSize: PerchGeometry.PERCH_SIZE,
            spriteSize: PerchGeometry.PERCH_SIZE,
            referenceTopMarginPt: Double(CompanionSpriteView.referenceTopMarginPt)
        )
        spriteView.bounds = CGRect(x: 0, y: 0, width: CGFloat(rest.width), height: CGFloat(rest.height))
        spriteView.center = CGPoint(x: CGFloat(rest.x + rest.width / 2), y: CGFloat(rest.y + rest.height / 2))

        // The rotation pivots about the drawn feet, not the box center -
        // `PerchTransform.affine` already bakes that translate-before/after
        // dance in, relative to the view's own (center) anchor point.
        let pivot = PerchAround.routePivot(spriteScale: profile.scale, footPad: profile.resolvedFootPad)
        let affine = PerchTransform.affine(
            x: state.x,
            hop: state.hop,
            seatY: state.seatY,
            flightLift: state.flightLift,
            rotationDegrees: state.rotationDegrees,
            pivot: pivot,
            referenceTopMarginPt: Double(CompanionSpriteView.referenceTopMarginPt)
        )
        spriteView.transform = CGAffineTransform(a: affine.a, b: affine.b, c: affine.c, d: affine.d, tx: affine.tx, ty: affine.ty)

        spriteView.alpha = CGFloat(state.visible)
        spriteView.apply(pose: state.pose, busy: state.busy, facing: state.facing)
    }

    /// Display rate while any perch or sprite opacity/press track is
    /// active, the sprite's own sheet fps otherwise - a long busy claim
    /// need not wake the display 120 times a second.
    private func updateFrameRateHint() {
        let perchActive = engine.isAnyTrackActive(labelPrefix: "perch.")
        let spriteActive = spriteView.currentRenderState?.needsFullFrameRate ?? false
        clock.frameRateHint = (perchActive || spriteActive) ? .motion : .sprite(fps: spriteFrameRateFallback)
    }

    // MARK: - Test-only hooks

    // Internal, not private: TabPetUIKitTests reads these via @testable
    // import, mirroring the "internal, not private" convention this
    // target already uses (CompanionSpriteView.debugLayer and friends).
    var debugCurrentPerchState: PerchRenderState { controller.currentState }
    var debugSpriteView: CompanionSpriteView { spriteView }
    var debugClock: DisplayLinkClock { clock }
    var debugIsTornDown: Bool { isTornDown }
    var debugEngine: MotionEngine { engine }
    var debugPanObserver: TabBarPanObserver? { panObserver }
    private(set) var debugFocusPassCount = 0
}

private extension CGAffineTransform {
    init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        self.init(a: CGFloat(a), b: CGFloat(b), c: CGFloat(c), d: CGFloat(d), tx: CGFloat(tx), ty: CGFloat(ty))
    }
}
#endif
