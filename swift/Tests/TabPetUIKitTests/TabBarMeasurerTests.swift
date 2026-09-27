#if canImport(UIKit)
import UIKit
import XCTest

import TabPetUIKit

@MainActor
final class TabBarMeasurerTests: XCTestCase {
    private func makeWindow(itemCount: Int) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let controller = UITabBarController()
        let symbols = ["house.fill", "magnifyingglass", "bell.fill", "person.fill", "gearshape.fill"]
        controller.viewControllers = (0..<itemCount).map { index in
            let child = UIViewController()
            child.tabBarItem = UITabBarItem(
                title: "Tab \(index)",
                image: UIImage(systemName: symbols[index % symbols.count]),
                tag: index
            )
            return child
        }
        window.rootViewController = controller
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        controller.view.layoutIfNeeded()
        return window
    }

    private func layoutTabBar(itemCount: Int) -> (window: UIWindow, layout: TabBarLayout) {
        let window = makeWindow(itemCount: itemCount)
        guard let layout = TabBarMeasurer.measure(in: window) else {
            XCTFail("expected a tab bar in the window")
            return (window, TabBarLayout(centers: [], top: nil, pill: nil))
        }
        return (window, layout)
    }

    func testThreeFourFiveItemBars() {
        for itemCount in [3, 4, 5] {
            let (window, layout) = layoutTabBar(itemCount: itemCount)
            // plain print, quoted verbatim in the delivery report
            print("TabBarMeasurerTests: itemCount=\(itemCount) centers=\(layout.centers) top=\(String(describing: layout.top)) pill=\(String(describing: layout.pill))")

            XCTAssertEqual(layout.centers.count, itemCount)
            for (a, b) in zip(layout.centers, layout.centers.dropFirst()) {
                XCTAssertLessThan(a, b, "centers strictly increase")
            }
            for center in layout.centers {
                XCTAssertGreaterThanOrEqual(center, 0)
                XCTAssertLessThanOrEqual(center, Double(window.bounds.width))
            }
            guard let top = layout.top else {
                XCTFail("expected a top edge")
                continue
            }
            XCTAssertGreaterThanOrEqual(top, 0)
            XCTAssertLessThanOrEqual(top, Double(window.bounds.height))

            // A laid-out bar on iOS 26+ always has a platter; assert non-nil
            // rather than letting the conditional checks below pass vacuously.
            if #available(iOS 26, *) {
                XCTAssertNotNil(layout.pill, "a laid-out bar on iOS 26+ has a platter")
            } else {
                XCTAssertNil(layout.pill)
            }

            if let pill = layout.pill {
                for center in layout.centers {
                    XCTAssertGreaterThanOrEqual(center, pill.x)
                    XCTAssertLessThanOrEqual(center, pill.x + pill.width)
                }
                XCTAssertEqual(top, pill.y)
            }
        }
    }

    func testEmptyTabBarReturnsEmptyLayoutWithoutCrashing() {
        let bar = UITabBar()
        let layout = TabBarMeasurer.measure(bar)
        XCTAssertTrue(layout.centers.isEmpty)
        XCTAssertNil(layout.pill)
    }

    private final class FakePlatterView: UIView {}

    func testZeroSizePlatterIsTreatedAsAbsent() {
        let bar = UITabBar()
        bar.frame = CGRect(x: 0, y: 700, width: 390, height: 90)
        let zeroPlatter = FakePlatterView(frame: CGRect(x: 20, y: 705, width: 0, height: 0))
        bar.addSubview(zeroPlatter)

        let layout = TabBarMeasurer.measure(bar)
        XCTAssertNil(layout.pill, "a platter with zero width or height is treated as absent")
        XCTAssertNotEqual(layout.top, 705, "top must not be read from a zero-size platter")
        XCTAssertEqual(layout.top, 700, "falls through to the bar's own frame with no buttons or real platter")
    }

    private final class PlainControlSubview: UIControl {}
    private final class FakeLensControl: UIControl {}

    // Strips UIKit's own item buttons (and any real platter) after layout so
    // only the plain controls the test adds remain - lets a fallback test
    // actually reach the fallback path instead of finding native buttons.
    // `items` stays real: the measurer reads that same public property.
    private final class FallbackOnlyTabBar: UITabBar {
        override func layoutSubviews() {
            super.layoutSubviews()
            for subview in subviews where isNativeItemView(subview) {
                subview.removeFromSuperview()
            }
        }

        private func isNativeItemView(_ view: UIView) -> Bool {
            let name = String(describing: type(of: view))
            return name.contains("TabBarButton") || name.contains("TabButton") || name.contains("Platter")
        }
    }

    private func makeFallbackBar(itemCount: Int) -> FallbackOnlyTabBar {
        let bar = FallbackOnlyTabBar()
        bar.frame = CGRect(x: 0, y: 0, width: 300, height: 60)
        bar.items = (0..<itemCount).map { UITabBarItem(title: "Tab \($0)", image: nil, tag: $0) }
        return bar
    }

    private func layoutFallbackBar(_ bar: FallbackOnlyTabBar) {
        bar.setNeedsLayout()
        bar.layoutIfNeeded()
    }

    func testFallbackReachesPlainControlsPathWithExactCenters() {
        let bar = makeFallbackBar(itemCount: 3)
        for x in [0, 100, 200] {
            bar.addSubview(PlainControlSubview(frame: CGRect(x: x, y: 0, width: 100, height: 60)))
        }
        layoutFallbackBar(bar)

        let namedPathFoundNothing = !bar.subviews.contains {
            let name = String(describing: type(of: $0))
            return name.contains("TabBarButton") || name.contains("TabButton")
        }
        XCTAssertTrue(namedPathFoundNothing, "the named path must find nothing for this test to reach the fallback")

        let layout = TabBarMeasurer.measure(bar)
        XCTAssertEqual(layout.centers, [50, 150, 250])
    }

    func testFallbackReturnsEmptyWhenCountMismatched() {
        let bar = makeFallbackBar(itemCount: 3)
        for x in [0, 100] {
            bar.addSubview(PlainControlSubview(frame: CGRect(x: x, y: 0, width: 100, height: 60)))
        }
        layoutFallbackBar(bar)

        let layout = TabBarMeasurer.measure(bar)
        XCTAssertTrue(layout.centers.isEmpty)
    }

    func testFallbackDedupesControlsAtSameMidX() {
        let bar = makeFallbackBar(itemCount: 2)
        bar.addSubview(PlainControlSubview(frame: CGRect(x: 0, y: 0, width: 100, height: 60))) // midX 50
        bar.addSubview(PlainControlSubview(frame: CGRect(x: 1, y: 0, width: 100, height: 60))) // midX 51, duplicate
        bar.addSubview(PlainControlSubview(frame: CGRect(x: 200, y: 0, width: 100, height: 60))) // midX 250
        layoutFallbackBar(bar)

        let layout = TabBarMeasurer.measure(bar)
        XCTAssertEqual(layout.centers.count, 2, "a control within 2 points of one already collected is a duplicate")
    }

    func testFallbackDoesNotDescendIntoAnAlreadyCollectedControl() {
        let bar = makeFallbackBar(itemCount: 2)
        let outer = PlainControlSubview(frame: CGRect(x: 0, y: 0, width: 100, height: 60))
        outer.addSubview(PlainControlSubview(frame: CGRect(x: 10, y: 10, width: 20, height: 20)))
        bar.addSubview(outer)
        bar.addSubview(PlainControlSubview(frame: CGRect(x: 200, y: 0, width: 100, height: 60)))
        layoutFallbackBar(bar)

        let layout = TabBarMeasurer.measure(bar)
        XCTAssertEqual(layout.centers.count, 2, "a control nested inside an already-collected control must not itself be collected")
    }

    func testFallbackSkipsViewsNamedLikeTheSelectionLens() {
        let bar = makeFallbackBar(itemCount: 2)
        bar.addSubview(PlainControlSubview(frame: CGRect(x: 0, y: 0, width: 100, height: 60)))
        bar.addSubview(FakeLensControl(frame: CGRect(x: 100, y: 0, width: 100, height: 60)))
        bar.addSubview(PlainControlSubview(frame: CGRect(x: 200, y: 0, width: 100, height: 60)))
        layoutFallbackBar(bar)

        let layout = TabBarMeasurer.measure(bar)
        XCTAssertEqual(layout.centers.count, 2, "a view named like the selection lens is skipped even in the fallback")
    }

    // Named-path fakes: the type name is what String(describing: type(of:))
    // reports, and that's what collectItemButtons matches against.
    private final class FakeTabButtonView: UIView {}
    private final class FakeLensContainerView: UIView {}

    func testNamedPathSkipsButtonsInsideTheSelectionLens() {
        let bar = UITabBar()
        bar.frame = CGRect(x: 0, y: 0, width: 500, height: 60)
        bar.addSubview(FakeTabButtonView(frame: CGRect(x: 0, y: 0, width: 100, height: 60)))
        bar.addSubview(FakeTabButtonView(frame: CGRect(x: 100, y: 0, width: 100, height: 60)))
        bar.addSubview(FakeTabButtonView(frame: CGRect(x: 200, y: 0, width: 100, height: 60)))

        // Off-window views convert in local coordinates: the lens sits at the
        // origin so its button's center is 380 either way, clear of the dedupe.
        let lens = FakeLensContainerView(frame: CGRect(x: 0, y: 0, width: 500, height: 60))
        lens.addSubview(FakeTabButtonView(frame: CGRect(x: 330, y: 0, width: 100, height: 60)))
        bar.addSubview(lens)

        let layout = TabBarMeasurer.measure(bar)
        XCTAssertEqual(layout.centers.count, 3, "the button inside the lens must not be counted")
        XCTAssertEqual(layout.centers, [50, 150, 250])
    }

    func testNamedPathCentersAreSortedByPositionNotSubviewOrder() {
        let bar = UITabBar()
        bar.frame = CGRect(x: 0, y: 0, width: 300, height: 60)
        let right = FakeTabButtonView(frame: CGRect(x: 200, y: 0, width: 100, height: 60))
        let left = FakeTabButtonView(frame: CGRect(x: 0, y: 0, width: 100, height: 60))
        let middle = FakeTabButtonView(frame: CGRect(x: 100, y: 0, width: 100, height: 60))
        bar.addSubview(right)
        bar.addSubview(left)
        bar.addSubview(middle)

        let layout = TabBarMeasurer.measure(bar)
        XCTAssertEqual(layout.centers, [50, 150, 250], "centers must sort left to right regardless of add order")
    }

    func testMeasureInWindowReturnsNilWithoutTabBar() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 600))
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        XCTAssertNil(TabBarMeasurer.measure(in: window))
    }
}
#endif
