#if canImport(UIKit)
import XCTest

import TabPetMotion
@testable import TabPetUIKit
@testable import TabPetCore

/// A finger feed the test drives by hand.
@MainActor
private final class ManualFingerSource: FingerSource {
    private(set) var listener: (@MainActor (PanEvent) -> Void)?
    private(set) var subscribeCount = 0
    private(set) var cancelCount = 0

    func subscribe(_ listener: @escaping @MainActor (PanEvent) -> Void) -> FingerSubscription {
        subscribeCount += 1
        self.listener = listener
        return FingerSubscription { [weak self] in
            self?.cancelCount += 1
            self?.listener = nil
        }
    }

    func send(_ x: Double, _ phase: PanPhase) {
        listener?(PanEvent(x: x, phase: phase))
    }
}

@MainActor
final class CompanionPerchFingerTests: XCTestCase {
    private func makeHost() -> (window: UIWindow, tbc: UITabBarController) {
        let tbc = UITabBarController()
        tbc.viewControllers = (0..<5).map { index in
            let vc = UIViewController()
            vc.tabBarItem = UITabBarItem(title: "Tab \(index)", image: UIImage(systemName: "circle"), tag: index)
            return vc
        }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = tbc
        window.makeKeyAndVisible()
        tbc.view.layoutIfNeeded()
        spin(0.3)
        return (window, tbc)
    }

    private func makePerch(slotIndex: Int) -> CompanionPerchView {
        let registry = CompanionRegistry()
        let profile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        registry.register(profile)
        return CompanionPerchView(
            companionID: profile.id,
            registry: registry,
            anchor: CompanionAnchor(slotCount: 5, slotIndex: slotIndex),
            handoff: PerchHandoffStore()
        )
    }

    private func waitUntil(timeout: TimeInterval = 10, _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
    }

    private func spin(_ seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
    }

    private func spriteCenterX(_ perch: CompanionPerchView) -> Double {
        Double(perch.debugSpriteView.center.x + perch.debugSpriteView.transform.tx)
    }

    /// Moves the finger from `from` to `to` in small steps, letting frames run between them.
    private func drag(_ source: ManualFingerSource, from: Double, to: Double, step: Double = 4) {
        var x = from
        let direction: Double = to >= from ? 1 : -1
        while (to - x) * direction > 0 {
            x += direction * min(step, abs(to - x))
            source.send(x, .moved)
            spin(0.016)
        }
    }

    private func centers(_ window: UIWindow) -> [Double]? {
        guard let layout = TabBarMeasurer.measure(in: window), layout.centers.count == 5 else { return nil }
        return layout.centers
    }

    func testDragMovesTheSpriteInRunPoseAndReleaseSeatsItOnItsOwnSlot() throws {
        let (window, tbc) = makeHost()
        let perch = makePerch(slotIndex: 2)
        let source = ManualFingerSource()
        perch.fingerSource = .custom(source)
        perch.attach(to: tbc)
        tbc.view.layoutIfNeeded()
        waitUntil { perch.debugCurrentPerchState.pose == .sit }
        let start = try XCTUnwrap(centers(window))[2]
        let seatedX = spriteCenterX(perch)

        source.send(start, .began)
        drag(source, from: start, to: start + 60)
        waitUntil { perch.debugCurrentPerchState.pose == .run }
        XCTAssertEqual(perch.debugCurrentPerchState.pose, .run)
        waitUntil { abs(spriteCenterX(perch) - seatedX) > 10 }
        XCTAssertGreaterThan(abs(spriteCenterX(perch) - seatedX), 10, "the sprite chases the finger")

        source.send(start + 60, .ended)
        waitUntil { perch.debugCurrentPerchState.pose == .sit && abs(spriteCenterX(perch) - start) < 1.5 }
        let measured = try XCTUnwrap(centers(window))[2]
        XCTAssertEqual(perch.debugCurrentPerchState.pose, .sit)
        XCTAssertEqual(spriteCenterX(perch), measured, accuracy: 1.5)
    }

    func testExclusiveReleaseOverAnotherSlotReportsThatSlotOnce() throws {
        let (window, tbc) = makeHost()
        let perch = makePerch(slotIndex: 0)
        let source = ManualFingerSource()
        var released: [Int] = []
        perch.barScrub = .exclusive
        perch.onDragRelease = { released.append($0) }
        perch.fingerSource = .custom(source)
        perch.attach(to: tbc)
        tbc.view.layoutIfNeeded()
        waitUntil { perch.debugCurrentPerchState.pose == .sit }
        let cs = try XCTUnwrap(centers(window))

        source.send(cs[0], .began)
        drag(source, from: cs[0], to: cs[3])
        source.send(cs[3], .ended)
        XCTAssertEqual(released, [3])

        waitUntil { perch.debugCurrentPerchState.pose == .sit }
        spin(1.2)
        XCTAssertEqual(released, [3], "a later settle never reports again")
    }

    func testNativeBarCarriesOneObserverRecognizerAndDetachRemovesIt() throws {
        let (_, tbc) = makeHost()
        let perch = makePerch(slotIndex: 0)
        perch.attach(to: tbc)
        tbc.view.layoutIfNeeded()
        spin(0.1)

        func ownedRecognizers() -> [UIGestureRecognizer] {
            (tbc.tabBar.gestureRecognizers ?? []).filter { $0.delegate is TabBarPanObserver }
        }
        let owned = ownedRecognizers()
        XCTAssertEqual(owned.count, 1)
        XCTAssertFalse(owned.first?.cancelsTouchesInView ?? true)

        perch.barScrub = .exclusive
        XCTAssertEqual(ownedRecognizers().first?.cancelsTouchesInView, true)

        perch.detach()
        XCTAssertEqual(ownedRecognizers().count, 0)
    }

    func testChangingTheSourceMidDragReturnsTheAnimalToRest() throws {
        let (window, tbc) = makeHost()
        let perch = makePerch(slotIndex: 2)
        let source = ManualFingerSource()
        perch.fingerSource = .custom(source)
        perch.attach(to: tbc)
        tbc.view.layoutIfNeeded()
        waitUntil { perch.debugCurrentPerchState.pose == .sit }
        let start = try XCTUnwrap(centers(window))[2]

        source.send(start, .began)
        drag(source, from: start, to: start + 60)
        waitUntil { perch.debugCurrentPerchState.pose == .run }
        XCTAssertEqual(perch.debugCurrentPerchState.pose, .run)

        perch.fingerSource = .none
        XCTAssertEqual(source.cancelCount, 1)
        waitUntil { perch.debugCurrentPerchState.pose == .sit }
        XCTAssertEqual(perch.debugCurrentPerchState.pose, .sit)
    }

    func testNonFiniteSamplesAreDroppedAtTheView() throws {
        let (window, tbc) = makeHost()
        let perch = makePerch(slotIndex: 2)
        let source = ManualFingerSource()
        perch.fingerSource = .custom(source)
        perch.attach(to: tbc)
        tbc.view.layoutIfNeeded()
        waitUntil { perch.debugCurrentPerchState.pose == .sit }
        let start = try XCTUnwrap(centers(window))[2]

        source.send(start, .began)
        source.send(.nan, .moved)
        source.send(.infinity, .moved)
        spin(0.2)
        XCTAssertEqual(perch.debugCurrentPerchState.pose, .sit)
        source.send(start, .ended)
    }

    func testLeavingTheWindowCancelsTheCustomSubscription() {
        let (_, tbc) = makeHost()
        let perch = makePerch(slotIndex: 0)
        let source = ManualFingerSource()
        perch.fingerSource = .custom(source)
        perch.attach(to: tbc)
        tbc.view.layoutIfNeeded()
        XCTAssertEqual(source.subscribeCount, 1)
        perch.detach()
        XCTAssertEqual(source.cancelCount, 1)
    }
}
#endif
