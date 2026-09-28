#if canImport(UIKit)
import QuartzCore
import UIKit

import TabPetMotion

/// `MotionClock` backed by a real `CADisplayLink`, driven by the actual
/// screen refresh rather than `ManualClock.advance`. `package`: only
/// `CompanionSpriteView` and this package's own tests construct one.
@MainActor
package final class DisplayLinkClock: MotionClock {
    /// Up to 120Hz for a live animation; a sprite-only sheet (busy loop, a
    /// sit settle) only needs its own fps, so a long busy claim wakes the
    /// display a dozen or so times a second, not 120.
    package enum FrameRateHint: Equatable, Sendable {
        case motion
        case sprite(fps: Double)
    }

    /// `CADisplayLink` retains its target strongly - this is that target,
    /// holding its owner weakly instead. A tick that finds the owner gone
    /// invalidates the link right there rather than firing forever.
    @MainActor
    private final class Proxy: NSObject {
        weak var owner: DisplayLinkClock?

        init(owner: DisplayLinkClock) {
            self.owner = owner
        }

        @objc func tick(_ link: CADisplayLink) {
            guard let owner else {
                link.invalidate()
                return
            }
            owner.handleTick(link)
        }
    }

    /// Observes app background/foreground, since a backgrounded app stops
    /// delivering ticks. Plain NSObject so `removeObserver` runs from its
    /// own deinit, unconstrained by the owner's main-actor isolation.
    @MainActor
    private final class LifecycleObserver: NSObject {
        weak var owner: DisplayLinkClock?

        init(owner: DisplayLinkClock) {
            self.owner = owner
            super.init()
            let center = NotificationCenter.default
            center.addObserver(self, selector: #selector(didEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
            center.addObserver(self, selector: #selector(willEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        @objc func didEnterBackground() {
            owner?.setSuspended(background: true)
        }

        @objc func willEnterForeground() {
            owner?.setSuspended(background: false)
        }
    }

    /// The current time, on one continuous line: the tick's own timestamp
    /// while ticking, the live media clock between ticks, or the value
    /// frozen at the moment a suspension began. Never goes backwards.
    package var now: Double {
        let computed: Double
        if let tickRawMs {
            computed = tickRawMs - offsetMs
        } else if suspendStartRawMs != nil {
            computed = frozenNowMs
        } else {
            computed = rawNowMs() - offsetMs
        }
        let result = Swift.max(lastReturnedNowMs, computed)
        lastReturnedNowMs = result
        return result
    }

    package var frameHandler: (@MainActor (Double) -> Void)?

    package var frameRateHint: FrameRateHint = .motion {
        didSet {
            guard frameRateHint != oldValue else { return }
            applyFrameRateHint()
        }
    }

    private var displayLink: CADisplayLink?
    private var proxy: Proxy?
    private var lifecycleObserver: LifecycleObserver?
    private var wantsFramesFlag = false

    /// The tick currently in progress, in the same raw units as
    /// `CACurrentMediaTime()`; `nil` outside one.
    private var tickRawMs: Double?
    /// Non-nil while suspended: the raw time the current suspension began.
    private var suspendStartRawMs: Double?
    /// What `now` reads while suspended.
    private var frozenNowMs: Double = 0
    /// Total time already subtracted for past suspensions, so a resume never
    /// jumps `now` forward by the length of the gap it just closed.
    private var offsetMs: Double = 0
    /// The largest value `now` has ever handed out, so a later read can
    /// never go backwards.
    private var lastReturnedNowMs: Double = -Double.infinity

    /// A view has no window reason to keep a link alive; the app itself can
    /// also be backgrounded. Either alone suspends the clock; it only runs
    /// again once neither holds.
    private var isWindowSuspended = false
    private var isBackgroundSuspended = false

    /// `startsBackgroundSuspended` defaults to the real app state so every
    /// real call site needs nothing special; a test overrides it directly
    /// rather than forcing `UIApplication.shared` into a state it can't reach.
    package init(startsBackgroundSuspended: Bool = UIApplication.shared.applicationState == .background) {
        lifecycleObserver = LifecycleObserver(owner: self)
        // Seeded directly, since `setSuspended` needs a real edge to fire on.
        if startsBackgroundSuspended {
            isBackgroundSuspended = true
            let raw = rawNowMs()
            frozenNowMs = raw - offsetMs
            suspendStartRawMs = raw
        }
    }

    // deinit deliberately touches nothing here (no isolated deinit in Swift
    // 5.9) - the weak proxy above is what tears the link down once this
    // instance is gone, and `lifecycleObserver`'s own deinit unregisters it.

    package func setWantsFrames(_ wantsFrames: Bool) {
        wantsFramesFlag = wantsFrames
        guard suspendStartRawMs == nil else { return }
        applyRunningState()
    }

    package func after(milliseconds: Double, _ action: @escaping @MainActor () -> Void) -> MotionCancellable {
        // ClockUnits is the only conversion boundary - never `milliseconds`
        // handed to `asyncAfter` unconverted, which would schedule 1000x late.
        let seconds = ClockUnits.seconds(fromMs: milliseconds)
        let workItem = DispatchWorkItem(block: action)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: workItem)
        return WorkItemCancellable(workItem: workItem)
    }

    /// Call from `didMoveToWindow()` when the window becomes nil.
    package func suspend() {
        setSuspended(window: true)
    }

    /// Call from `didMoveToWindow()` when a window is (re)acquired.
    package func resume() {
        setSuspended(window: false)
    }

    /// Applies a window or background suspension reason, freezing or
    /// rebasing `now` only on the edge where the combined state actually
    /// flips (so overlapping reasons never double-count a gap).
    private func setSuspended(window: Bool? = nil, background: Bool? = nil) {
        if let window { isWindowSuspended = window }
        if let background { isBackgroundSuspended = background }
        let shouldSuspend = isWindowSuspended || isBackgroundSuspended
        let wasSuspended = suspendStartRawMs != nil
        guard shouldSuspend != wasSuspended else { return }
        if shouldSuspend {
            let raw = rawNowMs()
            frozenNowMs = Swift.max(lastReturnedNowMs, raw - offsetMs)
            suspendStartRawMs = raw
            teardownLink()
        } else {
            if let startedAt = suspendStartRawMs {
                offsetMs += rawNowMs() - startedAt
            }
            suspendStartRawMs = nil
            applyRunningState()
        }
    }

    private func applyRunningState() {
        if wantsFramesFlag {
            ensureLinkExists()
            displayLink?.isPaused = false
        } else {
            // Paused in the same tick frames are no longer wanted.
            displayLink?.isPaused = true
        }
    }

    private func ensureLinkExists() {
        guard displayLink == nil else { return }
        let proxy = Proxy(owner: self)
        self.proxy = proxy
        let link = CADisplayLink(target: proxy, selector: #selector(Proxy.tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        applyFrameRateHint()
    }

    /// Test-only: `nil` while no link exists (never created yet, or torn
    /// down by `suspend()`), else whether it is currently paused.
    var debugIsLinkPaused: Bool? {
        displayLink?.isPaused
    }

    private func teardownLink() {
        displayLink?.invalidate()
        displayLink = nil
        proxy = nil
    }

    private func handleTick(_ link: CADisplayLink) {
        tickRawMs = ClockUnits.ms(fromSeconds: link.targetTimestamp)
        defer { tickRawMs = nil }
        frameHandler?(now)
    }

    private func rawNowMs() -> Double {
        ClockUnits.ms(fromSeconds: CACurrentMediaTime())
    }

    /// `preferred` is clamped into 1...120 and `minimum` never exceeds it -
    /// `CAFrameRateRange` throws otherwise, and a custom profile's fps is
    /// never validated upstream of here.
    private func applyFrameRateHint() {
        guard let link = displayLink else { return }
        var minimum: Float
        var preferred: Float
        switch frameRateHint {
        case .motion:
            minimum = 30
            preferred = 120
        case .sprite(let fps):
            preferred = (fps.isFinite && fps > 0) ? Float(fps) : 24
            minimum = Swift.min(30, preferred)
        }
        preferred = Swift.min(120, Swift.max(1, preferred))
        minimum = Swift.min(minimum, preferred)
        link.preferredFrameRateRange = CAFrameRateRange(minimum: minimum, maximum: 120, preferred: preferred)
    }
}

/// `after(milliseconds:)`'s handle - cancelling a not-yet-fired `DispatchWorkItem` is a no-op if it already ran.
private final class WorkItemCancellable: MotionCancellable {
    private let workItem: DispatchWorkItem

    init(workItem: DispatchWorkItem) {
        self.workItem = workItem
    }

    func cancel() {
        workItem.cancel()
    }
}
#endif
