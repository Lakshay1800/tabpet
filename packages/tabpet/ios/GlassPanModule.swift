import ExpoModulesCore
import UIKit

/// Owns the UIPanGestureRecognizer attached to the native tab bar. A separate
/// object because Module subclasses shouldn't double as gesture delegates.
final class GlassPanObserver: NSObject, UIGestureRecognizerDelegate {
  private weak var tabBar: UITabBar?
  private var recognizer: UIPanGestureRecognizer?
  private var lastSentX: Double?
  private let onEvent: (Double, String) -> Void
  /// `true`: once this pan recognises, the bar's own scrub (the iOS 26 pill
  /// inflating under the finger, the bar sliding with it) is cancelled and
  /// the companion alone chases; the host selects on release from JS.
  /// `false` (default): the pan only observes, the bar's scrub runs and
  /// selects the tab on release as it would without the companion.
  var exclusive = false {
    didSet { recognizer?.cancelsTouchesInView = exclusive }
  }

  init(onEvent: @escaping (Double, String) -> Void) {
    self.onEvent = onEvent
  }

  var isAttached: Bool {
    recognizer != nil
  }

  // Never attach twice: OnStartObserving can fire again after a retry loop
  // already succeeded (e.g. a second JS listener).
  func attach(to bar: UITabBar) {
    guard recognizer == nil else { return }
    let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
    // See `exclusive`. A tap never travels far enough to recognise, so item
    // selection keeps its touch-up path in either mode.
    pan.cancelsTouchesInView = exclusive
    pan.delaysTouchesBegan = false
    pan.delaysTouchesEnded = false
    pan.delegate = self
    bar.addGestureRecognizer(pan)
    recognizer = pan
    tabBar = bar
  }

  func detach() {
    if let pan = recognizer {
      tabBar?.removeGestureRecognizer(pan)
    }
    recognizer = nil
    tabBar = nil
    lastSentX = nil
  }

  // In exclusive mode the bar's own recognisers (and its controller view's)
  // yield to this pan; anything outside the bar - RN's root touch handler, a
  // screen-level pan - is left alone. In native mode nothing yields.
  private func isBarRecognizer(_ other: UIGestureRecognizer) -> Bool {
    guard let bar = tabBar, let view = other.view else { return false }
    return view.isDescendant(of: bar) || view === bar.superview
  }

  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
  ) -> Bool {
    !(exclusive && isBarRecognizer(otherGestureRecognizer))
  }

  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
  ) -> Bool {
    exclusive && isBarRecognizer(otherGestureRecognizer)
  }

  @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
    // Window coords: same space as RN's window width on the JS side.
    let x = Double(gesture.location(in: nil).x)

    let phase: String
    switch gesture.state {
    case .began:
      phase = "began"
    case .changed:
      phase = "moved"
    case .ended:
      phase = "ended"
    case .cancelled, .failed:
      phase = "cancelled"
    default:
      return
    }

    if phase == "moved", let last = lastSentX, abs(x - last) < 1 {
      return // throttle: only send once the finger has moved a full point
    }
    lastSentX = x
    onEvent(x, phase)
  }
}

/// Streams finger x from a UIPanGestureRecognizer attached to the native
/// tab bar; rides the bar's own scrub by default, or cancels it (exclusive).
public class GlassPanModule: Module {
  private var observer: GlassPanObserver?
  private var exclusive = false
  private var attachAttempts = 0
  // 20s window: a slow Release cold start (migrations, HealthKit sync) must
  // never strand the recognizer unattached - retries stop early on success.
  private let maxAttachAttempts = 40
  private let attachRetryInterval: TimeInterval = 0.5

  public func definition() -> ModuleDefinition {
    Name("GlassPan")

    Events("onGlassPan")

    OnStartObserving {
      attach()
    }

    OnStopObserving {
      detach()
    }

    // Applies live to an attached recognizer and to any later attach.
    Function("setBarScrub") { (exclusive: Bool) in
      self.exclusive = exclusive
      DispatchQueue.main.async { [weak self] in
        self?.observer?.exclusive = exclusive
      }
    }

    // window-space x centers of the item buttons, in bar order (a floating
    // bar's width varies with item count); empty when no bar is mounted yet
    Function("tabBarLayout") { () -> [String: Any] in
      if Thread.isMainThread {
        return Self.measureLayout()
      }
      return DispatchQueue.main.sync { Self.measureLayout() }
    }
  }

  // top: y of the visible bar (the floating pill on iOS 26, else the buttons'
  // top edge, never the full-width UITabBar frame)
  private static func measureLayout() -> [String: Any] {
    guard let bar = findTabBar() else {
      return ["centers": [Double](), "top": NSNull(), "pill": NSNull()]
    }
    var buttons: [UIView] = []
    collectItemButtons(in: bar, into: &buttons)
    let frames = buttons.map { $0.superview?.convert($0.frame, to: nil) ?? $0.frame }
    // Seat on the icon, not the button: end buttons stretch to the pill's
    // edge, so their midpoint drifts outward from the glyph.
    let centers = buttons
      .sorted { ($0.superview?.convert($0.frame, to: nil) ?? $0.frame).minX < ($1.superview?.convert($1.frame, to: nil) ?? $1.frame).minX }
      .map { button -> Double in
        let anchor = glyphView(in: button) ?? button
        let frame = anchor.superview?.convert(anchor.frame, to: nil) ?? anchor.frame
        return Double(frame.midX)
      }
    // The pill is the platter view around the buttons; the buttons sit inset
    // inside it, level with the selection bubble. Seat on the pill's edge.
    let platter = platterView(in: bar)
    let platterFrame = platter.map { $0.superview?.convert($0.frame, to: nil) ?? $0.frame }
    let top = platterFrame.map { Double($0.minY) }
      ?? frames.map { Double($0.minY) }.min()
      ?? Double(bar.superview?.convert(bar.frame, to: nil).minY ?? bar.frame.minY)
    let pill: Any = platterFrame.map {
      ["x": Double($0.minX), "y": Double($0.minY), "width": Double($0.width), "height": Double($0.height)]
    } ?? NSNull()
    return ["centers": centers, "top": top, "pill": pill]
  }

  // iOS 26 floating bar: _UITabBarPlatterView is the visible pill. Classic
  // bars have none; the buttons' top edge is the bar's top there.
  private static func platterView(in view: UIView) -> UIView? {
    for subview in view.subviews {
      if subview.isHidden { continue }
      if String(describing: type(of: subview)).contains("Platter") { return subview }
      if let found = platterView(in: subview) { return found }
    }
    return nil
  }

  // narrowest visible image view: the selection highlight is also a
  // UIImageView and stretches with the button. Falls back to the title label.
  private static func glyphView(in button: UIView) -> UIView? {
    var images: [UIView] = []
    var labels: [UIView] = []
    collectViews(in: button, images: &images, labels: &labels)
    if let glyph = images.min(by: { $0.bounds.width < $1.bounds.width }) {
      return glyph
    }
    return labels.first
  }

  private static func collectViews(in view: UIView, images: inout [UIView], labels: inout [UIView]) {
    for subview in view.subviews {
      if subview.isHidden || subview.bounds.width <= 0 { continue }
      if subview is UIImageView {
        images.append(subview)
      } else if subview is UILabel {
        labels.append(subview)
      }
      collectViews(in: subview, images: &images, labels: &labels)
    }
  }

  private static func collectItemButtons(in view: UIView, into out: inout [UIView]) {
    for subview in view.subviews {
      let name = String(describing: type(of: subview))
      // The iOS 26 selection lens carries its own copies of the selected
      // button; counting them shifts every index past the previous tab.
      if name.contains("Lens") { continue }
      // UITabBarButton on classic bars, _UITabButton on the iOS 26 floating bar
      if name.contains("TabBarButton") || name.contains("TabButton") {
        let midX = (subview.superview?.convert(subview.frame, to: nil) ?? subview.frame).midX
        let duplicate = out.contains { existing in
          abs((existing.superview?.convert(existing.frame, to: nil) ?? existing.frame).midX - midX) < 2
        }
        if !duplicate { out.append(subview) }
      } else {
        collectItemButtons(in: subview, into: &out)
      }
    }
  }

  private func attach() {
    attachAttempts = 0
    DispatchQueue.main.async { [weak self] in
      self?.attachAttempt()
    }
  }

  // The bar may not exist yet on first listener (view hierarchy still
  // mounting) - retry a bounded number of times before giving up.
  private func attachAttempt() {
    if observer?.isAttached == true {
      return
    }
    if let bar = Self.findTabBar() {
      let obs = observer ?? GlassPanObserver { [weak self] x, phase in
        self?.sendEvent("onGlassPan", ["x": x, "phase": phase])
      }
      obs.exclusive = exclusive
      obs.attach(to: bar)
      observer = obs
      return
    }
    attachAttempts += 1
    guard attachAttempts < maxAttachAttempts else {
      return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + attachRetryInterval) { [weak self] in
      self?.attachAttempt()
    }
  }

  private func detach() {
    DispatchQueue.main.async { [weak self] in
      self?.observer?.detach()
      self?.observer = nil
      self?.attachAttempts = 0
    }
  }

  private static func findTabBar() -> UITabBar? {
    guard let window = keyWindow() else { return nil }
    return findTabBar(in: window)
  }

  private static func keyWindow() -> UIWindow? {
    guard
      let windowScene = UIApplication.shared.connectedScenes
        .first(where: { $0 is UIWindowScene }) as? UIWindowScene
    else {
      return nil
    }
    return windowScene.keyWindow ?? windowScene.windows.first
  }

  private static func findTabBar(in view: UIView) -> UITabBar? {
    if let bar = view as? UITabBar {
      return bar
    }
    for subview in view.subviews {
      if let bar = findTabBar(in: subview) {
        return bar
      }
    }
    return nil
  }
}
