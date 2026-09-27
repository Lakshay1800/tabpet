#if canImport(UIKit)
import UIKit
import TabPetCore

/// Measures a native `UITabBar`'s item layout in window space.
///
/// Depends on four private UIKit class-name substrings that Apple can rename
/// or drop in any release: `Platter` (the iOS 26 floating pill,
/// `_UITabBarPlatterView`), `Lens` (the selection lens that carries its own
/// copy of the selected button, `_UILiquidLensView`), `TabBarButton`
/// (classic bar items, `UITabBarButton`), and `TabButton` (iOS 26 floating-
/// bar items, `_UITabButton`). When none of these names are found,
/// `measure` falls back to the bar's plain `UIControl` descendants rather
/// than crash or guess at indices. Verified against iOS 26.5 (simulator,
/// Xcode 27.0 build 27A266a).
@MainActor
public enum TabBarMeasurer {
    /// `nil` window resolves to the key window of the first connected window scene.
    public static func findTabBar(in window: UIWindow?) -> UITabBar? {
        guard let window = window ?? keyWindow() else { return nil }
        return findTabBar(in: window as UIView)
    }

    public static func measure(_ bar: UITabBar) -> TabBarLayout {
        var named: [UIView] = []
        collectItemButtons(in: bar, into: &named)
        let buttons = named.isEmpty ? fallbackButtons(in: bar) : named

        let frames = buttons.map(windowFrame)
        // Seat on the icon, not the button: end buttons stretch to the
        // pill's edge, so their midpoint drifts outward from the glyph.
        let centers = buttons
            .sorted { windowFrame($0).minX < windowFrame($1).minX }
            .map { button -> Double in
                let anchor = glyphView(in: button) ?? button
                return Double(windowFrame(anchor).midX)
            }

        // The pill is the platter view around the buttons; seat on its edge.
        // A bar that hasn't been laid out yet already owns a platter view
        // with a zero frame - treat width or height <= 0 as no platter at
        // all. Unlike the Expo module (which reports this phantom 0x0 pill
        // as-is), this is a deliberate difference.
        let platterFrame = platterView(in: bar).map(windowFrame).flatMap { $0.width > 0 && $0.height > 0 ? $0 : nil }
        let top = platterFrame.map { Double($0.minY) }
            ?? frames.map { Double($0.minY) }.min()
            ?? Double(windowFrame(bar).minY)
        let pill = platterFrame.map {
            PillFrame(x: Double($0.minX), y: Double($0.minY), width: Double($0.width), height: Double($0.height))
        }

        return TabBarLayout(centers: centers, top: top, pill: pill)
    }

    /// `nil` when no bar is found; `centers` empty when the bar itself has no items or buttons.
    public static func measure(in window: UIWindow? = nil) -> TabBarLayout? {
        guard let bar = findTabBar(in: window) else { return nil }
        return measure(bar)
    }

    private static func keyWindow() -> UIWindow? {
        guard
            let scene = UIApplication.shared.connectedScenes
                .first(where: { $0 is UIWindowScene }) as? UIWindowScene
        else {
            return nil
        }
        return scene.keyWindow ?? scene.windows.first
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

    private static func windowFrame(_ view: UIView) -> CGRect {
        view.superview?.convert(view.frame, to: nil) ?? view.frame
    }

    // iOS 26 floating bar: _UITabBarPlatterView is the visible pill. Classic
    // bars have none.
    private static func platterView(in view: UIView) -> UIView? {
        for subview in view.subviews {
            if subview.isHidden { continue }
            if String(describing: type(of: subview)).contains("Platter") { return subview }
            if let found = platterView(in: subview) { return found }
        }
        return nil
    }

    // UITabBarButton (classic) or _UITabButton (iOS 26 floating bar); skips
    // _UILiquidLensView, which carries its own copy of the selected button.
    private static func collectItemButtons(in view: UIView, into out: inout [UIView]) {
        for subview in view.subviews {
            let name = String(describing: type(of: subview))
            if name.contains("Lens") { continue }
            if name.contains("TabBarButton") || name.contains("TabButton") {
                let midX = windowFrame(subview).midX
                let duplicate = out.contains { abs(windowFrame($0).midX - midX) < 2 }
                if !duplicate { out.append(subview) }
            } else {
                collectItemButtons(in: subview, into: &out)
            }
        }
    }

    // No private class names found: fall back to the bar's own UIControls,
    // only when their count matches the item count - an unrelated count
    // means this isn't the item row, so centers stay empty rather than
    // guess. collectControls' own dedupe already keeps every pair of
    // collected controls at least 2 points apart, so the resulting centers
    // are always strictly increasing once sorted; no separate check needed.
    private static func fallbackButtons(in bar: UITabBar) -> [UIView] {
        var controls: [UIView] = []
        collectControls(in: bar, into: &controls)
        guard let itemCount = bar.items?.count, controls.count == itemCount else {
            return []
        }
        return controls
    }

    // Same dedupe and skip rules as collectItemButtons: a control within 2
    // points of one already collected is a duplicate, "Lens" names are the
    // selection lens's own copy, and a control's own subviews are never
    // descended into once it's collected.
    private static func collectControls(in view: UIView, into out: inout [UIView]) {
        for subview in view.subviews {
            if subview.isHidden || subview.bounds.width <= 0 { continue }
            if String(describing: type(of: subview)).contains("Lens") { continue }
            if subview is UIControl {
                let midX = windowFrame(subview).midX
                let duplicate = out.contains { abs(windowFrame($0).midX - midX) < 2 }
                if !duplicate { out.append(subview) }
                continue
            }
            collectControls(in: subview, into: &out)
        }
    }

    // narrowest visible image view: the selection highlight is also a
    // UIImageView and stretches with the button. Falls back to the title label.
    private static func glyphView(in button: UIView) -> UIView? {
        var images: [UIView] = []
        var labels: [UIView] = []
        collectGlyphViews(in: button, images: &images, labels: &labels)
        if let glyph = images.min(by: { $0.bounds.width < $1.bounds.width }) {
            return glyph
        }
        return labels.first
    }

    private static func collectGlyphViews(in view: UIView, images: inout [UIView], labels: inout [UIView]) {
        for subview in view.subviews {
            if subview.isHidden || subview.bounds.width <= 0 { continue }
            if subview is UIImageView {
                images.append(subview)
            } else if subview is UILabel {
                labels.append(subview)
            }
            collectGlyphViews(in: subview, images: &images, labels: &labels)
        }
    }
}
#endif
