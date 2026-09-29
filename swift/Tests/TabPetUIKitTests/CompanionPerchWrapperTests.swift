#if canImport(UIKit) && canImport(SwiftUI)
import SwiftUI
import XCTest

import TabPetCore
@testable import TabPetUIKit

@MainActor
final class CompanionPerchWrapperTests: XCTestCase {
    private final class Model: ObservableObject {
        @Published var tab = 0
        @Published var revision = 0
        var taps = 0
        var seenRevision = -1
    }

    private struct Host: View {
        let companionID: String
        @ObservedObject var model: Model
        var body: some View {
            let revision = model.revision
            TabView(selection: $model.tab) {
                ForEach(0..<5, id: \.self) { index in
                    Text("Page \(index) r\(revision)")
                        .tabItem { Label("Tab \(index)", systemImage: "circle") }
                        .tag(index)
                }
            }
            .overlay {
                CompanionPerch(
                    selection: model.tab,
                    slotCount: 5,
                    companionID: companionID,
                    onAction: {
                        model.taps += 1
                        model.seenRevision = revision
                    }
                )
                .ignoresSafeArea()
            }
        }
    }

    private final class FakeLongPressGestureRecognizer: UILongPressGestureRecognizer {
        var fakeLocation: CGPoint = .zero
        private var fakeState: UIGestureRecognizer.State = .possible

        override var state: UIGestureRecognizer.State {
            get { fakeState }
            set { }
        }

        override func location(in view: UIView?) -> CGPoint { fakeLocation }

        func fakeSetState(_ newState: UIGestureRecognizer.State) {
            fakeState = newState
        }
    }

    private struct Hosted {
        let window: UIWindow
        let hosting: UIHostingController<Host>
        let perch: CompanionPerchView
        let model: Model
    }

    private func waitUntil(timeout: TimeInterval = 10, _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
    }

    private func spinRunLoop(seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
    }

    private func findPerch(in view: UIView) -> CompanionPerchView? {
        if let perch = view as? CompanionPerchView { return perch }
        for subview in view.subviews {
            if let found = findPerch(in: subview) { return found }
        }
        return nil
    }

    private func makeHosted() -> Hosted? {
        let profile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        CompanionRegistry.shared.register(profile)
        let model = Model()
        let hosting = UIHostingController(rootView: Host(companionID: profile.id, model: model))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = hosting
        window.makeKeyAndVisible()
        hosting.view.layoutIfNeeded()
        spinRunLoop(seconds: 0.3)
        var perch: CompanionPerchView?
        waitUntil {
            perch = findPerch(in: window)
            return perch != nil
        }
        guard let perch else { return nil }
        waitUntil { perch.debugCurrentPerchState.pose == .sit }
        spinRunLoop(seconds: 0.3)
        return Hosted(window: window, hosting: hosting, perch: perch, model: model)
    }

    private func spriteFrame(_ hosted: Hosted) -> CGRect {
        let sprite = hosted.perch.debugSpriteView
        guard let parent = sprite.superview else { return .zero }
        return parent.convert(sprite.frame, to: hosted.window)
    }

    private func isInside(_ view: UIView?, of container: UIView) -> Bool {
        var current = view
        while let candidate = current {
            if candidate === container { return true }
            current = candidate.superview
        }
        return false
    }

    // MARK: - Placement

    func testThePetIsDrawnOnTheBarTopAtTheSelectedSlotCenter() throws {
        let hosted = try XCTUnwrap(makeHosted(), "no perch view found in the hosted hierarchy")
        let layout = try XCTUnwrap(TabBarMeasurer.measure(in: hosted.window))
        XCTAssertEqual(layout.centers.count, 5)
        let barTop = try XCTUnwrap(layout.top)
        let frame = spriteFrame(hosted)

        XCTAssertEqual(Double(frame.midX), layout.centers[0], accuracy: 1.5, "the pet sits on the selected slot's measured center")
        XCTAssertLessThan(Double(frame.minY), barTop, "the pet's box starts above the bar top")
        XCTAssertGreaterThan(Double(frame.maxY), barTop, "the pet's box reaches down to the bar top")
        XCTAssertLessThan(Double(frame.maxY), barTop + Double(frame.height) / 2, "the pet's box rests near the bar top, not deep in the bar")
    }

    func testTouchesPassThroughEverywhereExceptOnThePet() throws {
        let hosted = try XCTUnwrap(makeHosted(), "no perch view found in the hosted hierarchy")
        let bar = try XCTUnwrap(TabBarMeasurer.findTabBar(in: hosted.window))
        let layout = TabBarMeasurer.measure(bar)
        let barFrame = bar.convert(bar.bounds, to: hosted.window)

        for center in layout.centers {
            let point = CGPoint(x: CGFloat(center), y: barFrame.midY)
            let hit = hosted.window.hitTest(point, with: nil)
            XCTAssertTrue(isInside(hit, of: bar), "a touch at a tab item's center reaches the bar, got \(String(describing: hit))")
        }

        let frame = spriteFrame(hosted)
        let petPoint = CGPoint(x: frame.midX, y: frame.midY)
        let petHit = hosted.window.hitTest(petPoint, with: nil)
        XCTAssertTrue(
            petHit === hosted.perch.debugSpriteView || isInside(petHit, of: hosted.perch),
            "a touch at the pet's center reaches the pet, got \(String(describing: petHit))"
        )

        let content = CGPoint(x: 195, y: 300)
        let contentHit = hosted.window.hitTest(content, with: nil)
        XCTAssertFalse(isInside(contentHit, of: hosted.perch), "a touch on the page content passes through the overlay")
    }

    // MARK: - Selection

    func testAChangeOfSelectionRunsThePetAndSeatsItOnTheNewSlot() throws {
        let hosted = try XCTUnwrap(makeHosted(), "no perch view found in the hosted hierarchy")
        let passesBefore = hosted.perch.debugFocusPassCount

        hosted.model.tab = 3
        waitUntil { hosted.perch.debugFocusPassCount > passesBefore }
        waitUntil { hosted.perch.debugCurrentPerchState.pose == .sit }
        spinRunLoop(seconds: 0.3)

        let layout = try XCTUnwrap(TabBarMeasurer.measure(in: hosted.window))
        XCTAssertGreaterThan(hosted.perch.debugFocusPassCount, passesBefore, "a new selection runs a focus pass")
        XCTAssertEqual(hosted.perch.debugCurrentPerchState.pose, .sit, "the pet ends in the rest pose")
        XCTAssertEqual(Double(spriteFrame(hosted).midX), layout.centers[3], accuracy: 1.5, "the pet ends seated on the new slot's measured center")
    }

    // MARK: - Updates

    func testAnUpdateWithTheSameValuesRunsNoFocusPass() throws {
        let hosted = try XCTUnwrap(makeHosted(), "no perch view found in the hosted hierarchy")
        let passesBefore = hosted.perch.debugFocusPassCount

        hosted.model.revision = 1
        waitUntil {
            hosted.perch.onAction?()
            return hosted.model.seenRevision == 1
        }
        spinRunLoop(seconds: 0.3)

        XCTAssertEqual(hosted.model.seenRevision, 1, "setup: the update reached the view with the new closure")
        XCTAssertEqual(hosted.perch.debugFocusPassCount, passesBefore, "an update that changes nothing runs no focus pass")
    }

    // MARK: - Tap

    func testATapOnThePetCallsOnActionOnce() throws {
        let hosted = try XCTUnwrap(makeHosted(), "no perch view found in the hosted hierarchy")
        let sprite = hosted.perch.debugSpriteView

        let gesture = FakeLongPressGestureRecognizer(target: nil, action: nil)
        gesture.fakeLocation = CGPoint(x: 4, y: 4)
        gesture.fakeSetState(.began)
        sprite.handlePressGesture(gesture)
        gesture.fakeSetState(.ended)
        sprite.handlePressGesture(gesture)

        XCTAssertEqual(hosted.model.taps, 1)
    }

    // MARK: - Teardown

    func testReleasingTheHostingControllerTearsThePerchDown() throws {
        var perch: CompanionPerchView?
        weak var weakHosting: UIViewController?
        try autoreleasepool {
            let hosted = try XCTUnwrap(makeHosted(), "no perch view found in the hosted hierarchy")
            perch = hosted.perch
            weakHosting = hosted.hosting
            XCTAssertFalse(hosted.perch.debugIsTornDown)
            hosted.window.rootViewController = nil
            hosted.window.isHidden = true
        }
        let held = try XCTUnwrap(perch)
        waitUntil { held.debugIsTornDown }

        XCTAssertNil(weakHosting, "the hosting controller is released")
        XCTAssertTrue(held.debugIsTornDown, "the perch tears down once its hosting controller is gone")
    }
}
#endif
