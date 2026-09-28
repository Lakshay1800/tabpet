import TabPetCore

/// Ported from `companion-sprite.tsx`: the idle/run/sit sheets, the pose
/// cross-dissolve, the busy-idle loop, the mount/tap greeting and the
/// tap-press scale. Input is one coalesced `SpriteCommit` via `commit(_:)`; output goes to `renderer`, never drawn here.
@MainActor
package final class SpritePlayer {
    /// TS: BUSY_SLOWDOWN - idle loops at this multiple of its plain duration while busy.
    package static let busySlowdown: Double = 1.6
    /// TS: PRESS_SCALE / PRESS_IN_MS / PRESS_OUT_MS.
    package static let pressScaleFactor: Double = 0.98
    package static let pressInMs: Double = 120
    package static let pressOutMs: Double = 160
    /// TS: `useEffect(() => playGreeting(600), [])` - the mount greeting's delay.
    package static let mountGreetingDelayMs: Double = 600

    package var onSitDone: (() -> Void)?
    package var onError: ((MotionError, String) -> Void)?
    package weak var renderer: SpriteRenderer?

    private let engine: MotionEngine
    private let clock: MotionClock
    private let sanitizedScale: Double

    private let idleGeometry = CompanionProfile.IDLE_SHEET_GRID
    private let runGeometry: SheetGeometry
    private let sitGeometry: SheetGeometry

    /// One track per pose, looked up by a switch so a lookup cannot miss.
    private struct PoseTracks {
        let idle: MotionTrack
        let run: MotionTrack
        let sit: MotionTrack

        subscript(pose: PupPose) -> MotionTrack {
            switch pose {
            case .idle: return idle
            case .run: return run
            case .sit: return sit
            }
        }
    }

    private let frameTrack: PoseTracks
    private let opacityTrack: PoseTracks
    private var layerZ: [PupPose: Int] = [.idle: 1, .run: 0, .sit: 0]
    private var layerFacing: [PupPose: Facing]
    private let pressTrack: MotionTrack

    /// `previousPose.current` - the dissolve's transition source, hardcoded
    /// to `.idle` until the first real transition updates it.
    private var dissolveTransitionSource: PupPose = .idle
    private var lastCommit: SpriteCommit?

    /// The most recently applied commit, or nil before the first `commit(_:)` call.
    package var lastAppliedCommit: SpriteCommit? { lastCommit }

    /// Test-only: the engine this player owns, so a test can hold a weak
    /// reference to it and assert it deallocates with the player.
    package var debugEngine: MotionEngine { engine }

    package init(
        profile: CompanionProfile,
        clock: MotionClock,
        initialFacing: Facing = .right,
        initialReduceMotion: Bool = false,
        onError: ((MotionError, String) -> Void)? = nil
    ) {
        let engine = MotionEngine(clock: clock)
        self.engine = engine
        self.clock = clock
        // Assigned before the boundary checks below run: a construction-time
        // refusal has no later moment to install `self.onError`, so it is an
        // initializer argument, not only a settable property.
        self.onError = onError

        // A non-finite profile number is refused here and reported, rather
        // than reaching the engine and poisoning a duration or a transform.
        let (runFps, runFpsRefused) = Self.sanitizeFinite(profile.runFps, fallback: CompanionProfile.IDLE_SHEET_GRID.fps)
        let (scale, scaleRefused) = Self.sanitizeFinite(profile.scale, fallback: 1)
        let resolvedSit = profile.resolvedSitSheet
        let (sitFps, sitFpsRefused) = Self.sanitizeFinite(resolvedSit.fps, fallback: CompanionProfile.IDLE_SHEET_GRID.fps)

        self.sanitizedScale = scale
        self.runGeometry = SheetGeometry(
            cols: CompanionProfile.RUN_SHEET_GRID.cols,
            rows: CompanionProfile.RUN_SHEET_GRID.rows,
            frames: CompanionProfile.RUN_SHEET_GRID.frames,
            fps: runFps
        )
        self.sitGeometry = SheetGeometry(cols: resolvedSit.cols, rows: resolvedSit.rows, frames: resolvedSit.frames, fps: sitFps)

        self.frameTrack = PoseTracks(
            idle: engine.makeTrack(label: "sprite.\(PupPose.idle.rawValue).frame", initialValue: 0),
            run: engine.makeTrack(label: "sprite.\(PupPose.run.rawValue).frame", initialValue: 0),
            sit: engine.makeTrack(label: "sprite.\(PupPose.sit.rawValue).frame", initialValue: 0)
        )
        self.opacityTrack = PoseTracks(
            idle: engine.makeTrack(label: "sprite.idle.opacity", initialValue: 1),
            run: engine.makeTrack(label: "sprite.run.opacity", initialValue: 0),
            sit: engine.makeTrack(label: "sprite.sit.opacity", initialValue: 0)
        )
        self.pressTrack = engine.makeTrack(label: "sprite.press", initialValue: 0)
        self.layerFacing = [.idle: initialFacing, .run: initialFacing, .sit: initialFacing]

        engine.onError = { [weak self] error, label in self?.onError?(error, label) }
        // Weak on all three - a strong `engine` capture would chain clock
        // -> closure -> engine -> clock into a cycle nothing ever breaks.
        // A clock that outlives the player or engine is told to stop asking.
        clock.frameHandler = { [weak self, weak engine, weak clock] now in
            guard let self, let engine else {
                clock?.setWantsFrames(false)
                return
            }
            engine.tick(now: now)
            self.renderCurrentState()
        }

        if runFpsRefused {
            onError?(.nonFiniteValue, "profile.runFps")
        }
        if scaleRefused {
            onError?(.nonFiniteValue, "profile.scale")
        }
        if sitFpsRefused {
            onError?(.nonFiniteValue, "profile.sitSheet.fps")
        }

        playGreeting(delayMs: Self.mountGreetingDelayMs, reduceMotion: initialReduceMotion)
    }

    // MARK: - Commit

    /// One coalesced input: pose, busy, facing, reduceMotion. Each effect
    /// below runs only when its own fields changed since the last commit
    /// (mirrors companion-sprite.tsx); the first commit forces all three.
    package func commit(_ next: SpriteCommit) {
        let prior = lastCommit
        // Against a nil `prior` every comparison differs, so the first commit runs all three.
        let poseChanged = prior?.pose != next.pose
        let reduceMotionChanged = prior?.reduceMotion != next.reduceMotion
        if prior?.facing != next.facing || poseChanged {
            applyFacing(next.facing, toLayer: next.pose)
        }
        if poseChanged || reduceMotionChanged {
            applyPoseDissolve(previous: dissolveTransitionSource, next: next.pose, reduceMotion: next.reduceMotion)
        }
        if prior?.busy != next.busy || poseChanged || reduceMotionChanged {
            applyBusyLoop(busy: next.busy, pose: next.pose, reduceMotion: next.reduceMotion, isFirst: prior == nil)
        }
        lastCommit = next
        renderCurrentState()
    }

    /// TS: `useEffect(() => { layers[pose].facing.set(facing) }, [facing, pose])`
    /// - only the current pose's layer takes the new facing; an outgoing
    /// (fading) layer keeps whatever it already had.
    private func applyFacing(_ facing: Facing, toLayer pose: PupPose) {
        layerFacing[pose] = facing
    }

    /// TS: the pose-dissolve effect (companion-sprite.tsx:255-351). Cancels
    /// every opacity animation, applies hidden/opaque/fade-out, then resets
    /// or holds the incoming frame and cancels the outgoing one.
    private func applyPoseDissolve(previous: PupPose, next: PupPose, reduceMotion: Bool) {
        let plan = PoseDissolve.planPoseDissolve(previous: previous, next: next, reduceMotion: reduceMotion)

        for pose in PupPose.allCases {
            engine.cancel(opacityTrack[pose])
        }

        for name in PoseDissolve.poseDissolveApplyOrder(plan: plan) {
            let assignment = plan[name]
            layerZ[name] = assignment.z
            switch assignment.opacity {
            case .hidden:
                engine.set(opacityTrack[name], 0)
                if name == .idle {
                    // idle is invisible here: rest at idle[0] now, covering a
                    // run -> sit hop landing inside the 110ms idle fade
                    // (finished=false otherwise).
                    engine.cancel(frameTrack[.idle])
                    engine.set(frameTrack[.idle], 0)
                }
            case .opaque:
                engine.set(opacityTrack[name], 1)
            case .fadeOut(let durationMs):
                let fadingIdle = name == .idle
                engine.start(opacityTrack[name], TimingAnimation(toValue: 0, config: TimingConfig(duration: durationMs))) { [weak self] finished in
                    // busy cleanup freezes idle while it's the outgoing
                    // layer; once the fade completes, restore idle[0] for
                    // the next sit -> idle seam. Only on a finished fade.
                    guard finished, fadingIdle, let self else { return }
                    self.engine.set(self.frameTrack[.idle], 0)
                }
            }
        }

        if reduceMotion {
            for pose in PupPose.allCases {
                engine.cancel(frameTrack[pose])
            }
            let restFrame: Double = next == .sit ? Double(sitGeometry.frames - 1) : 0
            engine.set(frameTrack[next], restFrame)
            dissolveTransitionSource = next
            return
        }

        if previous == next {
            // Same-pose re-run (a re-commit, or a reduceMotion flip back to
            // false): leave frames alone so a greeting or the busy loop
            // survives this call.
            dissolveTransitionSource = next
            return
        }

        engine.cancel(frameTrack[next])
        switch next {
        case .run:
            engine.set(frameTrack[.run], 0)
            let timing = TimingAnimation(
                toValue: Double(runGeometry.frames - 1),
                config: TimingConfig(duration: Self.sheetDurationMs(runGeometry), easing: { Easing.linear($0) })
            )
            // isLoop: a host can hold `.run` indefinitely (the demo's pose
            // buttons) - exempt from the engine's 10s force-complete guard,
            // same reasoning as the busy loop below.
            engine.start(frameTrack[.run], RepeatAnimation(timing, numberOfReps: -1, reverse: false), isLoop: true)
        case .sit:
            engine.set(frameTrack[.sit], 0)
            let timing = TimingAnimation(
                toValue: Double(sitGeometry.frames - 1),
                config: TimingConfig(duration: Self.sheetDurationMs(sitGeometry), easing: { Easing.linear($0) })
            )
            engine.start(frameTrack[.sit], timing) { [weak self] finished in
                guard finished else { return }
                self?.scheduleOnSitDone()
            }
        case .idle:
            // sit -> idle holds the seam only because idle[0] matches sit's
            // last frame; every other incoming pose (or an idle frozen
            // elsewhere) resets to the rest cell instead.
            if PoseDissolve.shouldResetIncomingFrame(previous: previous, next: next) || frameTrack[.idle].currentValue != 0 {
                engine.set(frameTrack[.idle], 0)
            }
        }

        engine.cancel(frameTrack[previous])
        dissolveTransitionSource = next
    }

    /// TS: the busy-loop effect (companion-sprite.tsx:355-379), after the
    /// pose effect so a frame reset can't stomp it. `isFirst` skips cleanup
    /// on the first commit, when idle may be mid-flight from the greeting.
    private func applyBusyLoop(busy: Bool, pose: PupPose, reduceMotion: Bool, isFirst: Bool) {
        if !isFirst {
            engine.cancel(frameTrack[.idle])
            if PoseDissolve.shouldSnapBusyIdleFrameToRest(currentPose: pose) {
                engine.set(frameTrack[.idle], 0)
            }
        }
        guard busy, !reduceMotion, pose == .idle else {
            return
        }
        engine.set(frameTrack[.idle], 0)
        let timing = TimingAnimation(
            toValue: Double(idleGeometry.frames - 1),
            config: TimingConfig(duration: Self.sheetDurationMs(idleGeometry) * Self.busySlowdown, easing: { Easing.linear($0) })
        )
        engine.start(frameTrack[.idle], RepeatAnimation(timing, numberOfReps: -1, reverse: false), isLoop: true)
    }

    /// TS: `playGreeting` - idle plays once, from frame 0, `delayMs` after
    /// being asked. Used both by the mount effect (600ms) and a qualifying
    /// tap (0ms). Reduce Motion suppresses it entirely.
    private func playGreeting(delayMs: Double, reduceMotion: Bool) {
        guard !reduceMotion else {
            return
        }
        engine.cancel(frameTrack[.idle])
        engine.set(frameTrack[.idle], 0)
        let timing = TimingAnimation(
            toValue: Double(idleGeometry.frames - 1),
            config: TimingConfig(duration: Self.sheetDurationMs(idleGeometry), easing: { Easing.linear($0) })
        )
        engine.start(frameTrack[.idle], DelayAnimation(delayMs, timing))
    }

    // MARK: - Press

    /// TS: `Gesture.Tap().onBegin` - `pressed.set(reduceMotion ? 0 : withTiming(1, {duration: PRESS_IN_MS}))`.
    package func pressBegin() {
        let reduceMotion = lastCommit?.reduceMotion ?? false
        if reduceMotion {
            engine.set(pressTrack, 0)
        } else {
            engine.start(pressTrack, TimingAnimation(toValue: 1, config: TimingConfig(duration: Self.pressInMs)))
        }
        renderCurrentState()
    }

    /// TS: `Gesture.Tap().onFinalize` - always runs, paired with every `pressBegin()`.
    package func pressEnd() {
        let reduceMotion = lastCommit?.reduceMotion ?? false
        if reduceMotion {
            engine.set(pressTrack, 0)
        } else {
            engine.start(pressTrack, TimingAnimation(toValue: 0, config: TimingConfig(duration: Self.pressOutMs)))
        }
        renderCurrentState()
    }

    /// TS: `handleTap` - plays the greeting only while idle and not busy.
    /// The caller fires its own haptic and `onPress` regardless of this
    /// method's return value, which reports only whether it greeted.
    @discardableResult
    package func tap() -> Bool {
        guard let last = lastCommit, last.pose == .idle, !last.busy else {
            return false
        }
        playGreeting(delayMs: 0, reduceMotion: last.reduceMotion)
        renderCurrentState()
        return true
    }

    // MARK: - Render

    /// The current drawable state, computed on demand - equivalent to
    /// whatever the last `renderer` call carried, for a caller that has no
    /// renderer installed (or wants a synchronous read outside one).
    package var currentState: SpriteRenderState { buildState() }

    private func renderCurrentState() {
        guard let renderer else {
            return
        }
        renderer.spritePlayer(self, didRender: buildState())
    }

    private func buildState() -> SpriteRenderState {
        let reduceMotion = lastCommit?.reduceMotion ?? false
        let pressed = pressTrack.currentValue
        let pressScale = reduceMotion ? 1.0 : 1.0 + pressed * (Self.pressScaleFactor - 1.0)
        let needsFullFrameRate = pressTrack.isActive || PupPose.allCases.contains { opacityTrack[$0].isActive }
        return SpriteRenderState(
            idle: layerState(for: .idle, geometry: idleGeometry),
            run: layerState(for: .run, geometry: runGeometry),
            sit: layerState(for: .sit, geometry: sitGeometry),
            pressScale: pressScale,
            needsFullFrameRate: needsFullFrameRate
        )
    }

    private func layerState(for pose: PupPose, geometry: SheetGeometry) -> SpriteLayerState {
        SpriteLayerState(
            frame: Self.frameIndex(rawValue: frameTrack[pose].currentValue, frameCount: geometry.frames),
            opacity: opacityTrack[pose].currentValue,
            z: layerZ[pose] ?? 0,
            facing: layerFacing[pose] ?? .right,
            scale: sanitizedScale
        )
    }

    /// Delivered one main-queue turn later, never from inside `commit` -
    /// a one-frame sit finishes synchronously inside `applyPoseDissolve`,
    /// and a host re-entering `commit` there would corrupt the outer call.
    private func scheduleOnSitDone() {
        _ = clock.after(milliseconds: 0) { [weak self] in
            self?.onSitDone?()
        }
    }

    // MARK: - Pure helpers

    /// `clamp(round(progress * (frames - 1)))`, never `floor(t * fps)`.
    /// `rawValue` is a track's raw `Double` (linear over `frames/fps`
    /// seconds); this rounds and clamps it into a valid cell index.
    package static func frameIndex(rawValue: Double, frameCount: Int) -> Int {
        guard frameCount > 0, rawValue.isFinite else {
            return 0
        }
        let rounded = rawValue.rounded()
        let clampedLow = Swift.max(0.0, rounded)
        let clampedHigh = Swift.min(Double(frameCount - 1), clampedLow)
        return Int(clampedHigh)
    }

    private static func sheetDurationMs(_ geometry: SheetGeometry) -> Double {
        (Double(geometry.frames) / geometry.fps) * 1000
    }

    private static func sanitizeFinite(_ value: Double, fallback: Double) -> (value: Double, wasRefused: Bool) {
        value.isFinite ? (value, false) : (fallback, true)
    }
}
