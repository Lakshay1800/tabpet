#if canImport(UIKit)
import QuartzCore
import UIKit

import TabPetCore
import TabPetMotion

/// Haptic kind a successful tap asks the host to play - mirrors the TS
/// `'selection' | 'impact'` literal. Host-owned: this view never calls
/// `UIImpactFeedbackGenerator` itself, only `onHaptic`.
public enum HapticKind: Sendable, Equatable {
    case selection
    case impact
}

/// Reported through `onError` for the states that are not a loading or a
/// sheet-decode failure. Public so a host can pattern-match on it rather
/// than only ever seeing an opaque `Error`.
public enum CompanionSpriteError: Error, Sendable, Equatable {
    /// No profile is registered anywhere. Reported once per `companionID`
    /// change, and again the first time the view enters a window if still
    /// unresolved then.
    case noProfileRegistered
    /// The resolved profile has no `sheets` (its resource bundle could not be
    /// found) - see `CompanionProfile.sheets`.
    case sheetUnavailable(pose: PupPose)
    /// `size` was not finite or not greater than zero, at init or from a
    /// later set - the view falls back to 88 and reports this once per bad
    /// value.
    case invalidSize(CGFloat)
}

/// A UIKit view for one companion's idle/run/sit sprite sheets, on top of
/// `SpritePlayer`. Five states (loading, empty, error, normal, Reduce
/// Motion) never throw - a broken configuration draws nothing and reports through `onError`.
@MainActor
public final class CompanionSpriteView: UIView, SpriteRenderer {
    // Internal, not private: TabPetUIKitTests reads this via @testable
    // import to assert which state a fixture landed in, mirroring the
    // convention `handlePan` already uses elsewhere in this target.
    enum VisualState: Equatable {
        case loading
        case empty
        case error
        case ready
    }

    private struct PoseGeometry {
        let cols: Int
        let rows: Int
    }

    // MARK: - Public API

    /// Changing this rebuilds the sprite player from scratch: the mount
    /// greeting replays and every layer is blank until the new sheets
    /// decode (companion-sprite.tsx keeps its shared values across a change).
    public var companionID: String {
        didSet {
            guard companionID != oldValue else { return }
            reloadProfile()
        }
    }

    public var pose: PupPose = .idle {
        didSet {
            guard pose != oldValue, !isApplyingBatch else { return }
            commit()
        }
    }

    public var isBusy: Bool = false {
        didSet {
            guard isBusy != oldValue, !isApplyingBatch else { return }
            commit()
        }
    }

    public var facing: Facing = .right {
        didSet {
            guard facing != oldValue, !isApplyingBatch else { return }
            commit()
        }
    }

    /// Sets pose, busy and facing together and commits once - a perch
    /// driving all three off one render state must not commit per property.
    package func apply(pose: PupPose, busy: Bool, facing: Facing) {
        guard pose != self.pose || busy != isBusy || facing != self.facing else { return }
        isApplyingBatch = true
        self.pose = pose
        isBusy = busy
        self.facing = facing
        isApplyingBatch = false
        commit()
    }

    public var onPress: (() -> Void)?
    public var onSitDone: (() -> Void)?
    public var onHaptic: ((HapticKind) -> Void)?
    public var onError: ((Error, String) -> Void)?

    public var pressAccessibilityLabel: String? {
        didSet {
            guard pressAccessibilityLabel != oldValue else { return }
            updateAccessibility()
        }
    }

    /// The cell is always drawn at `size x size`, pinned to the view's own
    /// top-left, never stretched to a larger `bounds`. Settable: relayouts
    /// and redraws at the new size.
    public var size: CGFloat {
        get { _size }
        set {
            let sanitized = sanitizeSizeFromSetter(newValue)
            guard sanitized != _size else { return }
            _size = sanitized
            invalidateIntrinsicContentSize()
            setNeedsLayout()
        }
    }

    public override var intrinsicContentSize: CGSize {
        CGSize(width: size, height: size)
    }

    /// TS's sprite wrapper carries a 4pt top margin this view does not add
    /// (companion-sprite.tsx:457) - a later seat-math change needs to place it.
    package static let referenceTopMarginPt: CGFloat = 4

    // MARK: - Init

    private let registry: CompanionRegistry
    private var _size: CGFloat
    private let clock: MotionClock
    private let ownsClock: Bool
    /// Suppresses the per-property `commit()` inside `apply(pose:busy:facing:)`
    /// so the three writes there land as one commit, not up to three.
    private var isApplyingBatch = false
    /// Non-nil only in shared-engine mode: the engine `reloadProfile()`
    /// builds `SpritePlayer` against, rather than the one `SpritePlayer`'s
    /// own owned-mode initializer would otherwise create from `clock`.
    private let sharedEngine: MotionEngine?
    /// The raw bit pattern of the last refused `size`, so a repeat of the
    /// same bad value (NaN included) reports only once, not on every set.
    private var lastReportedInvalidSizeBits: UInt64?

    /// A host never passes its own clock: `DisplayLinkClock` is `package`,
    /// and one engine per clock means two views sharing one would fight
    /// over its `frameHandler`. Only this package reaches the inits below.
    public convenience init(
        companionID: String = CompanionId.DEFAULT_COMPANION_ID,
        registry: CompanionRegistry = .shared,
        size: CGFloat = 88,
        onError: ((Error, String) -> Void)? = nil
    ) {
        self.init(companionID: companionID, registry: registry, size: size, clock: nil, onError: onError)
    }

    /// `clock` nil builds and owns a real `DisplayLinkClock`; a non-nil
    /// clock is injected (for deterministic tests), but this view still
    /// builds its own `SpritePlayer`-owned engine against it, not a shared one.
    package convenience init(
        companionID: String = CompanionId.DEFAULT_COMPANION_ID,
        registry: CompanionRegistry = .shared,
        size: CGFloat = 88,
        clock: MotionClock?,
        onError: ((Error, String) -> Void)? = nil
    ) {
        if let clock {
            self.init(companionID: companionID, registry: registry, size: size, clock: clock, ownsClock: false, sharedEngine: nil, onError: onError)
        } else {
            self.init(companionID: companionID, registry: registry, size: size, clock: DisplayLinkClock(), ownsClock: true, sharedEngine: nil, onError: onError)
        }
    }

    /// Shared-engine mode: `engine` and `clock` are owned elsewhere (a
    /// perch view driving one clock for its own motion and this sprite).
    /// This view never suspends, resumes or sets `clock`'s frame rate hint.
    package convenience init(
        companionID: String = CompanionId.DEFAULT_COMPANION_ID,
        registry: CompanionRegistry = .shared,
        size: CGFloat = 88,
        engine: MotionEngine,
        clock: MotionClock,
        onError: ((Error, String) -> Void)? = nil
    ) {
        self.init(companionID: companionID, registry: registry, size: size, clock: clock, ownsClock: false, sharedEngine: engine, onError: onError)
    }

    private init(
        companionID: String,
        registry: CompanionRegistry,
        size: CGFloat,
        clock: MotionClock,
        ownsClock: Bool,
        sharedEngine: MotionEngine?,
        onError: ((Error, String) -> Void)?
    ) {
        self.companionID = companionID
        self.registry = registry
        self.onError = onError
        self._size = Self.sanitizedSize(size, onError: onError)
        if !size.isFinite || size <= 0 {
            // Seeds the memoized bits with the report just above, so an
            // immediate re-set of the same bad value (the SwiftUI wrapper's
            // own applyState) does not report it again.
            self.lastReportedInvalidSizeBits = Double(size).bitPattern
        }
        self.clock = clock
        self.ownsClock = ownsClock
        self.sharedEngine = sharedEngine
        super.init(frame: CGRect(x: 0, y: 0, width: _size, height: _size))

        if ownsClock, let ownClock = self.clock as? DisplayLinkClock {
            // Pre-suspended: a fresh view has no window yet, and the TS
            // mount greeting only fires post-mount. The real link starts
            // at the first `didMoveToWindow`, not at this init.
            ownClock.suspend()
            ownClock.frameRateHint = .sprite(fps: 24)
        }

        backgroundColor = .clear
        // A size x size view never stretches to fill a SwiftUI stack or an
        // Auto Layout container offering it more space (companion-sprite.tsx
        // wraps at exactly size x size).
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)
        setupLayers()
        setupGesture()
        setupReduceMotionObserver()
        reloadProfile()
    }

    @available(*, unavailable, message: "use init(companionID:registry:size:onError:) - CompanionSpriteView is never loaded from a nib")
    public required init?(coder: NSCoder) {
        return nil
    }

    deinit {
        // Never touches `clock` here - no isolated deinit in Swift 5.9.
        // DisplayLinkClock's weak proxy needs no cooperation from this
        // deinit; only the plain NSObject notification token does.
        NotificationCenter.default.removeObserver(self)
    }

    private static func sanitizedSize(_ size: CGFloat, onError: ((Error, String) -> Void)?) -> CGFloat {
        guard size.isFinite, size > 0 else {
            onError?(CompanionSpriteError.invalidSize(size), "CompanionSpriteView.size")
            return 88
        }
        return size
    }

    /// Same fallback as `sanitizedSize`, but for the settable property after
    /// init: a refused value reports only when it differs (by bit pattern,
    /// so a repeated NaN counts as the same value) from the last one refused.
    private func sanitizeSizeFromSetter(_ size: CGFloat) -> CGFloat {
        guard size.isFinite, size > 0 else {
            let bits = Double(size).bitPattern
            if lastReportedInvalidSizeBits != bits {
                lastReportedInvalidSizeBits = bits
                onError?(CompanionSpriteError.invalidSize(size), "CompanionSpriteView.size")
            }
            return 88
        }
        lastReportedInvalidSizeBits = nil
        return size
    }

    // MARK: - Layers

    // Groups the three pose layers so the press scale (below) can be
    // applied to this one container, never to the view's own backing layer
    // - matches TS's viewportSizer wrapping the three PoseLayers.
    private let viewportLayer = CALayer()
    private let idleLayer = CALayer()
    private let runLayer = CALayer()
    private let sitLayer = CALayer()

    private func setupLayers() {
        layer.addSublayer(viewportLayer)
        for poseLayer in [idleLayer, runLayer, sitLayer] {
            poseLayer.magnificationFilter = .linear
            poseLayer.minificationFilter = .linear
            poseLayer.contentsGravity = .resize
            poseLayer.isHidden = true
            viewportLayer.addSublayer(poseLayer)
        }
    }

    // Internal, not private: test-only accessor to the sublayer for one
    // pose, mirroring the "internal, not private" convention this target
    // already uses for direct test access (e.g. `TabBarPanObserver.handlePan`).
    func debugLayer(for pose: PupPose) -> CALayer {
        switch pose {
        case .idle: return idleLayer
        case .run: return runLayer
        case .sit: return sitLayer
        }
    }

    /// Test-only: the frame index `SpritePlayer` currently holds for one
    /// pose, read fresh (not from whatever was last rendered).
    func debugCurrentFrame(for pose: PupPose) -> Int {
        spritePlayer?.currentState[pose].frame ?? 0
    }

    /// Test-only: the view's own display-link clock, when it owns one (the
    /// default for every real host - nil passed at construction).
    var debugOwnedClock: DisplayLinkClock? {
        clock as? DisplayLinkClock
    }

    /// Test-only: the container layer the press scale is applied to.
    var debugViewportLayer: CALayer { viewportLayer }

    /// Test-only: the view's own press gesture recognizer.
    var debugPressGesture: UILongPressGestureRecognizer? { pressGesture }

    /// Test-only: how many times `commit()` has run, so a batched
    /// `apply(pose:busy:facing:)` can be proven to commit exactly once.
    private(set) var debugCommitCount = 0

    /// Shared-engine mode only: the owner calls this once, right after
    /// ticking the shared engine, standing in for the `frameHandler` this
    /// view never installs in that mode. A no-op before a profile resolves.
    package func renderTick() {
        spritePlayer?.renderTick()
    }

    /// Shared-engine mode: called once by the owning perch's own teardown -
    /// removes this view's sprite tracks from the shared engine. A no-op
    /// in owned mode, harmless to call either way.
    package func teardown() {
        spritePlayer?.teardown()
    }

    /// Shared-engine mode only: lets the owner fold `needsFullFrameRate`
    /// into its own frame rate hint for the one clock both share. `nil`
    /// before a profile resolves.
    package var currentRenderState: SpriteRenderState? {
        spritePlayer?.currentState
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let scale = window?.screen.scale ?? UIScreen.main.scale
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Pinned to size x size regardless of the view's own bounds
        // (companion-sprite.tsx:444 does the same). Bounds/position, never
        // `frame` - a scaled layer (raccoon, squirrel) would read its own scale back into `bounds`.
        let cell = CGRect(x: 0, y: 0, width: size, height: size)
        let center = CGPoint(x: cell.midX, y: cell.midY)
        viewportLayer.bounds = cell
        viewportLayer.position = center
        for poseLayer in [idleLayer, runLayer, sitLayer] {
            poseLayer.bounds = cell
            poseLayer.position = center
            poseLayer.contentsScale = scale
        }
        CATransaction.commit()
    }

    private var hasAttemptedWindowReresolve = false

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if ownsClock, let ownClock = clock as? DisplayLinkClock {
            if window == nil {
                ownClock.suspend()
            } else {
                ownClock.resume()
            }
        }
        // A host that constructs this view before registering companions
        // gets one more resolution attempt on window entry - unless onError
        // was already set at construction and already got this report.
        guard window != nil, !hasAttemptedWindowReresolve else { return }
        hasAttemptedWindowReresolve = true
        guard !didReportFirstResolveFailureToHandler else { return }
        if visualState == .empty || visualState == .error {
            reloadProfile()
        }
    }

    // MARK: - Gesture

    private var pressGesture: UILongPressGestureRecognizer?
    private var pressBeganAt: Date?
    private var pressStartLocation: CGPoint?
    private var pressExceededTapBounds = false
    private var hasEndedPressForThisGesture = false

    // TS: `Gesture.Tap().maxDistance(12)`, RNGH's default tap maxDuration.
    private static let tapMaxDistance: CGFloat = 12
    private static let tapMaxDuration: TimeInterval = 0.5

    private func setupGesture() {
        isUserInteractionEnabled = true
        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(handlePressGesture(_:)))
        gesture.minimumPressDuration = 0
        // Never blocks a parent: a finger that lands on the pet and then
        // drags still scrolls an ancestor scroll view.
        gesture.cancelsTouchesInView = false
        gesture.delegate = self
        addGestureRecognizer(gesture)
        pressGesture = gesture
    }

    // internal, not private: TabPetUIKitTests drives this directly via
    // @testable import with a fake UILongPressGestureRecognizer, mirroring
    // TabBarPanObserver's own `handlePan` convention.
    @objc func handlePressGesture(_ gesture: UILongPressGestureRecognizer) {
        guard let spritePlayer else { return }
        switch gesture.state {
        case .began:
            pressBeganAt = Date()
            pressStartLocation = gesture.location(in: self)
            pressExceededTapBounds = false
            hasEndedPressForThisGesture = false
            spritePlayer.pressBegin()
        case .changed:
            failTapIfNeeded(gesture: gesture, spritePlayer: spritePlayer)
        case .ended:
            failTapIfNeeded(gesture: gesture, spritePlayer: spritePlayer)
            endPressOnce(spritePlayer)
            // TS `onEnd(_, success)`: haptic and onPress only on a real tap.
            if !pressExceededTapBounds {
                onHaptic?(.selection)
                _ = spritePlayer.tap()
                onPress?()
            }
            pressBeganAt = nil
            pressStartLocation = nil
        case .cancelled, .failed:
            endPressOnce(spritePlayer)
            pressBeganAt = nil
            pressStartLocation = nil
        default:
            break
        }
    }

    /// TS: a drag past 12pt, a hold past 500ms, or the finger leaving the
    /// view's bounds each fail the tap. The press scale returns at once,
    /// at the moment of failure, never twice for one gesture.
    private func failTapIfNeeded(gesture: UILongPressGestureRecognizer, spritePlayer: SpritePlayer) {
        guard !pressExceededTapBounds, let pressStartLocation else { return }
        let location = gesture.location(in: self)
        let distance = hypot(location.x - pressStartLocation.x, location.y - pressStartLocation.y)
        let elapsed = pressBeganAt.map { Date().timeIntervalSince($0) } ?? 0
        guard distance > Self.tapMaxDistance || elapsed > Self.tapMaxDuration || !bounds.contains(location) else {
            return
        }
        pressExceededTapBounds = true
        endPressOnce(spritePlayer)
    }

    /// TS `onFinalize`: the press scale always returns, paired with every
    /// `pressBegin()`, but never more than once per gesture.
    private func endPressOnce(_ spritePlayer: SpritePlayer) {
        guard !hasEndedPressForThisGesture else { return }
        hasEndedPressForThisGesture = true
        spritePlayer.pressEnd()
    }

    /// A VoiceOver activation is a real tap, not a gesture - it skips the
    /// distance and duration checks above entirely.
    public override func accessibilityActivate() -> Bool {
        guard let spritePlayer else { return false }
        onHaptic?(.selection)
        _ = spritePlayer.tap()
        onPress?()
        return true
    }

    // MARK: - Reduce Motion

    private func setupReduceMotionObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reduceMotionStatusDidChange),
            name: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil
        )
    }

    @objc private func reduceMotionStatusDidChange() {
        commit()
    }

    // MARK: - Profile / sheet loading

    private var profile: CompanionProfile?
    private var spritePlayer: SpritePlayer?
    private(set) var visualState: VisualState = .loading
    private var poseGeometry: [PupPose: PoseGeometry] = [:]
    private var loadedImages: [PupPose: CGImage] = [:]
    private var pendingPoses: Set<PupPose> = []
    private var reportedErrorPoses: Set<PupPose> = []
    /// Bumped on every reload; a sheet-load completion for a stale generation
    /// (the companionID changed again before it landed) is dropped.
    private var loadGeneration = 0
    /// Set once, by the very first `reloadProfile()` (the one init runs):
    /// whether it ended in `.empty`/`.error` with a non-nil `onError` that
    /// already received the report. Gates the window-entry re-resolve.
    private var didReportFirstResolveFailureToHandler = false
    private var hasCompletedFirstReload = false
    /// The rate to fall back to once no track needs the fuller one -
    /// computed once per profile from its own sheet fps. Picked between
    /// this and `.motion` on every render, by `needsFullFrameRate`.
    private var spriteFrameRateHint: DisplayLinkClock.FrameRateHint = .sprite(fps: 24)

    /// The requested id, else the default id, else the first registered
    /// profile - identical to the perch's own resolution. Never throws.
    private func resolveProfile() -> CompanionProfile? {
        registry.get(companionID) ?? registry.get(CompanionId.DEFAULT_COMPANION_ID) ?? registry.list().first
    }

    private func reloadProfile() {
        let isFirstReload = !hasCompletedFirstReload
        hasCompletedFirstReload = true
        loadGeneration += 1
        let generation = loadGeneration
        loadedImages = [:]
        pendingPoses = []
        reportedErrorPoses = []
        poseGeometry = [:]
        visualState = .loading
        hideAllLayers()

        guard let profile = resolveProfile() else {
            self.profile = nil
            spritePlayer = nil
            visualState = .empty
            updateAccessibility()
            // Reported once per landing here: `reloadProfile` only runs
            // once per init, per real `companionID` change, or once from
            // the first `didMoveToWindow` - never twice for one attempt.
            if isFirstReload, onError != nil {
                didReportFirstResolveFailureToHandler = true
            }
            onError?(CompanionSpriteError.noProfileRegistered, "CompanionSpriteView.resolveProfile")
            return
        }
        self.profile = profile
        updateAccessibility()
        poseGeometry = [
            .idle: PoseGeometry(cols: CompanionProfile.IDLE_SHEET_GRID.cols, rows: CompanionProfile.IDLE_SHEET_GRID.rows),
            .run: PoseGeometry(cols: CompanionProfile.RUN_SHEET_GRID.cols, rows: CompanionProfile.RUN_SHEET_GRID.rows),
            .sit: PoseGeometry(cols: profile.resolvedSitSheet.cols, rows: profile.resolvedSitSheet.rows),
        ]

        if ownsClock, let ownClock = clock as? DisplayLinkClock {
            let spriteFps = max(CompanionProfile.IDLE_SHEET_GRID.fps, profile.runFps, profile.resolvedSitSheet.fps)
            spriteFrameRateHint = .sprite(fps: spriteFps.isFinite && spriteFps > 0 ? spriteFps : 24)
            ownClock.frameRateHint = spriteFrameRateHint
        }

        // Removes the outgoing player's tracks before it is dropped - in
        // shared-engine mode a loop track (a held run, the busy idle loop)
        // would otherwise keep the shared clock awake forever.
        spritePlayer?.teardown()

        let player: SpritePlayer
        if let sharedEngine {
            player = SpritePlayer(
                profile: profile,
                engine: sharedEngine,
                clock: clock,
                initialFacing: facing,
                initialReduceMotion: UIAccessibility.isReduceMotionEnabled,
                onError: { [weak self] error, site in self?.onError?(error, site) }
            )
        } else {
            player = SpritePlayer(
                profile: profile,
                clock: clock,
                initialFacing: facing,
                initialReduceMotion: UIAccessibility.isReduceMotionEnabled,
                onError: { [weak self] error, site in self?.onError?(error, site) }
            )
        }
        player.renderer = self
        player.onSitDone = { [weak self] in self?.onSitDone?() }
        spritePlayer = player
        commit()

        guard let sheets = profile.sheets else {
            visualState = .error
            if isFirstReload, onError != nil {
                didReportFirstResolveFailureToHandler = true
            }
            for pose in PupPose.allCases {
                reportErrorOnce(for: pose, error: CompanionSpriteError.sheetUnavailable(pose: pose))
            }
            return
        }

        for pose in PupPose.allCases {
            pendingPoses.insert(pose)
            let geometry = poseGeometry[pose] ?? PoseGeometry(cols: 1, rows: 1)
            let url = sheetURL(for: pose, sheets: sheets)
            SpriteSheetCache.shared.loadSheet(url: url, cols: geometry.cols, rows: geometry.rows) { [weak self] result in
                guard let self, generation == self.loadGeneration else { return }
                self.pendingPoses.remove(pose)
                switch result {
                case .success(let image):
                    self.loadedImages[pose] = image
                case .failure(let error):
                    self.reportErrorOnce(for: pose, error: error)
                    self.visualState = .error
                }
                self.finishLoadIfReady()
            }
        }
    }

    private func sheetURL(for pose: PupPose, sheets: CompanionSheets) -> URL {
        switch pose {
        case .idle: return sheets.idle
        case .run: return sheets.run
        case .sit: return sheets.sit
        }
    }

    private func reportErrorOnce(for pose: PupPose, error: Error) {
        guard !reportedErrorPoses.contains(pose) else { return }
        reportedErrorPoses.insert(pose)
        onError?(error, "CompanionSpriteView.loadSheet.\(pose.rawValue)")
    }

    private func finishLoadIfReady() {
        guard visualState != .empty else { return }
        if visualState == .error {
            hideAllLayers()
            return
        }
        guard pendingPoses.isEmpty, loadedImages.count == PupPose.allCases.count else { return }
        visualState = .ready
        assignLayerContents()
        if let state = spritePlayer?.currentState {
            render(state)
        }
    }

    private func hideAllLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for poseLayer in [idleLayer, runLayer, sitLayer] {
            poseLayer.isHidden = true
            poseLayer.contents = nil
        }
        CATransaction.commit()
    }

    private func assignLayerContents() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        idleLayer.contents = loadedImages[.idle]
        runLayer.contents = loadedImages[.run]
        sitLayer.contents = loadedImages[.sit]
        for poseLayer in [idleLayer, runLayer, sitLayer] {
            poseLayer.isHidden = false
        }
        CATransaction.commit()
    }

    private func updateAccessibility() {
        guard let profile else {
            isAccessibilityElement = false
            accessibilityLabel = nil
            accessibilityTraits = []
            pressGesture?.isEnabled = false
            return
        }
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = pressAccessibilityLabel ?? "Your companion \(profile.label). Tap to say hi."
        pressGesture?.isEnabled = true
    }

    private func commit() {
        debugCommitCount += 1
        spritePlayer?.commit(
            SpriteCommit(pose: pose, busy: isBusy, facing: facing, reduceMotion: UIAccessibility.isReduceMotionEnabled)
        )
    }

    // MARK: - SpriteRenderer

    // `package`, not `public`: SpriteRenderer/SpritePlayer/SpriteRenderState
    // are all `package`-visible only, so this conformance method can't be
    // any more public than the protocol it satisfies.
    package func spritePlayer(_ player: SpritePlayer, didRender state: SpriteRenderState) {
        guard visualState == .ready else { return }
        if ownsClock, let ownClock = clock as? DisplayLinkClock {
            ownClock.frameRateHint = state.needsFullFrameRate ? .motion : spriteFrameRateHint
        }
        render(state)
    }

    private func render(_ state: SpriteRenderState) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        apply(state.idle, to: idleLayer, pose: .idle)
        apply(state.run, to: runLayer, pose: .run)
        apply(state.sit, to: sitLayer, pose: .sit)
        viewportLayer.transform = CATransform3DMakeScale(CGFloat(state.pressScale), CGFloat(state.pressScale), 1)
        CATransaction.commit()
    }

    private func apply(_ layerState: SpriteLayerState, to poseLayer: CALayer, pose: PupPose) {
        guard let geometry = poseGeometry[pose], let image = loadedImages[pose] else { return }
        poseLayer.opacity = Float(layerState.opacity)
        poseLayer.zPosition = CGFloat(layerState.z)
        poseLayer.contentsRect = Self.contentsRect(
            frame: layerState.frame,
            cols: geometry.cols,
            rows: geometry.rows,
            pixelWidth: image.width,
            pixelHeight: image.height
        )
        let flip: CGFloat = layerState.facing == .left ? -1 : 1
        poseLayer.transform = CATransform3DMakeScale(flip * CGFloat(layerState.scale), CGFloat(layerState.scale), 1)
    }

    /// Cell `frame` (0-based, row-major) mapped to a `contentsRect` in the
    /// sheet's own unit space, inset half a texel on every side so linear
    /// filtering at the cell's edge never blends in the next cell's texel.
    static func contentsRect(frame: Int, cols: Int, rows: Int, pixelWidth: Int, pixelHeight: Int) -> CGRect {
        guard cols > 0, rows > 0, pixelWidth > 0, pixelHeight > 0 else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        let col = frame % cols
        let row = frame / cols
        let cellWidthPx = CGFloat(pixelWidth) / CGFloat(cols)
        let cellHeightPx = CGFloat(pixelHeight) / CGFloat(rows)
        let insetX = 0.5 / CGFloat(pixelWidth)
        let insetY = 0.5 / CGFloat(pixelHeight)
        let x = (CGFloat(col) * cellWidthPx) / CGFloat(pixelWidth) + insetX
        let y = (CGFloat(row) * cellHeightPx) / CGFloat(pixelHeight) + insetY
        let width = Swift.max(0, cellWidthPx / CGFloat(pixelWidth) - 2 * insetX)
        let height = Swift.max(0, cellHeightPx / CGFloat(pixelHeight) - 2 * insetY)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

extension CompanionSpriteView: UIGestureRecognizerDelegate {
    // Recognizes alongside every other recognizer - a scroll view's own pan
    // is never blocked by a finger landing on the pet first.
    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
#endif
