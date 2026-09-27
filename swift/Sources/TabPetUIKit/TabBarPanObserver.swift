#if canImport(UIKit)
import UIKit

/// Attaches a `UIPanGestureRecognizer` to a native tab bar and reports its
/// phase and window-space x. Behavior parity with the Expo module this was
/// extracted from: same recognizer settings, same delegate rules, same
/// phase mapping and one-point throttle. The retry loop that finds a bar
/// mounted late, and turning events into an emitter callback, are the
/// caller's business - not part of this type.
///
/// Callers own `detach()`: call it before releasing the observer rather
/// than relying on deinit to tear the recognizer down.
@MainActor
public final class TabBarPanObserver: NSObject, UIGestureRecognizerDelegate {
    private weak var tabBar: UITabBar?
    private var recognizer: UIPanGestureRecognizer?
    private var lastSentX: Double?
    private let onEvent: @MainActor (PanEvent) -> Void

    /// Applies live to an attached recognizer, and to any later attach.
    public var scrubMode: BarScrubMode {
        didSet { recognizer?.cancelsTouchesInView = scrubMode == .exclusive }
    }

    public init(scrubMode: BarScrubMode = .native, onEvent: @escaping @MainActor (PanEvent) -> Void) {
        self.scrubMode = scrubMode
        self.onEvent = onEvent
    }

    /// `false` once the recognizer's bar has been deallocated, even though
    /// `detach()` was never called.
    public var isAttached: Bool {
        recognizer != nil && tabBar != nil
    }

    /// Attaching to the bar already attached to is a no-op. Attaching to a
    /// different bar, or to any bar once the previously stored one has been
    /// deallocated, detaches the stale recognizer first.
    public func attach(to bar: UITabBar) {
        if let current = tabBar, current === bar, recognizer != nil { return }
        if recognizer != nil { detach() }
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        // See `scrubMode`. A tap never travels far enough to recognise, so
        // item selection keeps its touch-up path in either mode.
        pan.cancelsTouchesInView = scrubMode == .exclusive
        pan.delaysTouchesBegan = false
        pan.delaysTouchesEnded = false
        pan.delegate = self
        bar.addGestureRecognizer(pan)
        recognizer = pan
        tabBar = bar
    }

    public func detach() {
        if let pan = recognizer {
            tabBar?.removeGestureRecognizer(pan)
        }
        recognizer = nil
        tabBar = nil
        lastSentX = nil
    }

    // In exclusive mode the bar's own recognisers (and its controller
    // view's) yield to this pan; anything outside the bar is left alone. In
    // native mode nothing yields.
    private func isBarRecognizer(_ other: UIGestureRecognizer) -> Bool {
        guard let bar = tabBar, let view = other.view else { return false }
        return view.isDescendant(of: bar) || view === bar.superview
    }

    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        !(scrubMode == .exclusive && isBarRecognizer(otherGestureRecognizer))
    }

    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        scrubMode == .exclusive && isBarRecognizer(otherGestureRecognizer)
    }

    // internal, not private: TabPetUIKitTests drives this directly via
    // @testable import with a fake UIPanGestureRecognizer.
    @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
        // Window coords: same space as the layout centers.
        let x = Double(gesture.location(in: nil).x)

        let phase: PanPhase
        switch gesture.state {
        case .began:
            phase = .began
        case .changed:
            phase = .moved
        case .ended:
            phase = .ended
        case .cancelled, .failed:
            phase = .cancelled
        default:
            return
        }

        if phase == .moved, let last = lastSentX, abs(x - last) < 1 {
            return // throttle: only send once the finger has moved a full point
        }
        lastSentX = x
        onEvent(PanEvent(x: x, phase: phase))
    }
}
#endif
