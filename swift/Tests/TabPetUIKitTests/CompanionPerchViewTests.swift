#if canImport(UIKit)
import XCTest

import TabPetMotion
@testable import TabPetUIKit
@testable import TabPetCore

@MainActor
final class CompanionPerchViewTests: XCTestCase {
    private func makeHostedTabBarController(tabCount: Int = 5, width: CGFloat = 390, height: CGFloat = 844) -> (window: UIWindow, tbc: UITabBarController) {
        let tbc = UITabBarController()
        tbc.viewControllers = (0..<tabCount).map { index in
            let vc = UIViewController()
            vc.tabBarItem = UITabBarItem(title: "Tab \(index)", image: UIImage(systemName: "circle"), tag: index)
            return vc
        }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
        window.rootViewController = tbc
        window.makeKeyAndVisible()
        tbc.view.layoutIfNeeded()
        // The icon-driven floating bar keeps settling for a couple of run
        // loop turns after layoutIfNeeded() returns - settled here so a
        // perch attached afterward sees the bar's final geometry.
        spinRunLoop(seconds: 0.3)
        return (window, tbc)
    }

    private func makePerchView(registry: CompanionRegistry, companionID: String, slotCount: Int, slotIndex: Int) -> CompanionPerchView {
        CompanionPerchView(
            companionID: companionID,
            registry: registry,
            anchor: CompanionAnchor(slotCount: slotCount, slotIndex: slotIndex),
            handoff: PerchHandoffStore()
        )
    }

    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) {
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

    /// The sprite's true rendered position: `center` alone is the
    /// pre-transform rest anchor - the transform's own translation carries
    /// the model's `x` (itself a left edge, per `tabCenterX`) on top of it.
    private func onScreenSpriteCenter(_ perch: CompanionPerchView) -> (x: Double, y: Double) {
        let center = perch.debugSpriteView.center
        let transform = perch.debugSpriteView.transform
        return (x: Double(center.x + transform.tx), y: Double(center.y + transform.ty))
    }

    // MARK: - Tab change

    func testTabChangeRunsToTheMeasuredCenterEndsInSitAndPausesTheLink() {
        let registry = CompanionRegistry()
        let profile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        registry.register(profile)
        let (window, tbc) = makeHostedTabBarController()
        let perch = makePerchView(registry: registry, companionID: profile.id, slotCount: 5, slotIndex: 0)
        perch.attach(to: tbc)
        tbc.view.layoutIfNeeded()
        waitUntil { perch.debugCurrentPerchState.pose == .sit }

        perch.selectTab(2)
        // Wide bounds: a loaded machine must still pass. The run leg, the
        // reaction pause and the catch spring together are well under 3s
        // for any bundled profile at this distance.
        waitUntil(timeout: 5) { perch.debugCurrentPerchState.pose == .sit }

        // Measured last, at the same moment as the assertion below: the
        // reference value must reflect the bar's final settled layout,
        // the same one the controller's own remeasure converges on.
        guard let layout = TabBarMeasurer.measure(in: window), layout.centers.count == 5 else {
            return XCTFail("expected a real measured tab bar layout")
        }
        XCTAssertEqual(perch.debugCurrentPerchState.pose, .sit, "the chase must settle back to sit")
        XCTAssertEqual(onScreenSpriteCenter(perch).x, layout.centers[2], accuracy: 1.5, "the seat lands on the measured center, not an even split")

        // The link stops once nothing is left to animate - a wide poll
        // window tolerates the catch spring's own settle time.
        waitUntil(timeout: 5) { perch.debugClock.debugIsLinkPaused == true }
        XCTAssertEqual(perch.debugClock.debugIsLinkPaused, true, "the link must pause once the chase settles")

        _ = window
    }

    func testMeasuredCentersAreWhatTheControllerSees() {
        let registry = CompanionRegistry()
        let profile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        registry.register(profile)
        let (window, tbc) = makeHostedTabBarController(tabCount: 5, width: 402)
        let perch = makePerchView(registry: registry, companionID: profile.id, slotCount: 5, slotIndex: 3)
        perch.attach(to: tbc)
        tbc.view.layoutIfNeeded()
        waitUntil { perch.debugCurrentPerchState.pose == .sit }
        // The icon-driven floating bar can keep settling for a couple of
        // run loop turns after layoutIfNeeded() returns - give it room
        // before taking the reference measurement below.
        spinRunLoop(seconds: 0.3)

        guard let layout = TabBarMeasurer.measure(in: window), layout.centers.count == 5 else {
            return XCTFail("expected a real measured tab bar layout")
        }
        // Only what the controller itself must see - not an assumption about
        // the floating pill's own spacing, which a pre-26 runner's classic
        // (evenly spread) bar would not satisfy.
        XCTAssertEqual(onScreenSpriteCenter(perch).x, layout.centers[3], accuracy: 1.5, "the mount seat must use the measured center")
    }

    // MARK: - Hit testing

    func testTouchOffTheSpriteReachesTheBarButTheSpriteCenterIsHit() {
        let registry = CompanionRegistry()
        let profile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        registry.register(profile)
        let (_, tbc) = makeHostedTabBarController()
        let perch = makePerchView(registry: registry, companionID: profile.id, slotCount: 5, slotIndex: 0)
        perch.attach(to: tbc)
        tbc.view.layoutIfNeeded()
        waitUntil { perch.debugCurrentPerchState.pose == .sit }

        let onScreenCenter = onScreenSpriteCenter(perch)
        let spriteCenter = CGPoint(x: onScreenCenter.x, y: onScreenCenter.y)
        XCTAssertTrue(perch.point(inside: spriteCenter, with: nil), "the sprite's own center must be hit")

        let farAway = CGPoint(x: 4, y: 4)
        XCTAssertFalse(perch.point(inside: farAway, with: nil), "a touch away from the sprite must reach whatever is underneath (the bar)")
    }

    // MARK: - Z order

    func testZOrderHoldsAfterSelectTab() {
        let registry = CompanionRegistry()
        let profile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        registry.register(profile)
        let (_, tbc) = makeHostedTabBarController()
        let perch = makePerchView(registry: registry, companionID: profile.id, slotCount: 5, slotIndex: 0)
        perch.attach(to: tbc)
        tbc.view.layoutIfNeeded()
        waitUntil { perch.debugCurrentPerchState.pose == .sit }

        let intruder = UIView()
        tbc.view.insertSubview(intruder, aboveSubview: perch)
        XCTAssertTrue(tbc.view.subviews.last === intruder, "setup: the intruder must be above the perch")

        perch.selectTab(1)
        XCTAssertTrue(tbc.view.subviews.last === perch, "selectTab must re-assert the perch above anything else added since attach")
    }

    // MARK: - Deallocation

    func testViewAndItsClockDeallocateWithTheWindow() {
        let registry = CompanionRegistry()
        let profile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        registry.register(profile)
        weak var weakPerch: CompanionPerchView?
        weak var weakClock: DisplayLinkClock?

        autoreleasepool {
            var window: UIWindow? = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            let tbc = UITabBarController()
            tbc.viewControllers = (0..<3).map { _ in UIViewController() }
            window?.rootViewController = tbc
            window?.makeKeyAndVisible()
            tbc.view.layoutIfNeeded()

            let perch = makePerchView(registry: registry, companionID: profile.id, slotCount: 3, slotIndex: 0)
            perch.attach(to: tbc)
            tbc.view.layoutIfNeeded()
            weakPerch = perch
            weakClock = perch.debugClock
            waitUntil { perch.debugCurrentPerchState.pose == .sit }

            window?.rootViewController = nil
            window = nil
        }

        waitUntil { weakPerch == nil }
        XCTAssertNil(weakPerch, "the perch view must deallocate once nothing outside this scope holds it")
        XCTAssertNil(weakClock, "the perch's own clock must deallocate with it")
    }

    // MARK: - Window size change

    func testWindowSizeChangeReSeatsThroughSameTabSnap() {
        let registry = CompanionRegistry()
        let profile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        registry.register(profile)
        let (window, tbc) = makeHostedTabBarController(tabCount: 5, width: 390)
        let perch = makePerchView(registry: registry, companionID: profile.id, slotCount: 5, slotIndex: 2)
        perch.attach(to: tbc)
        tbc.view.layoutIfNeeded()
        waitUntil { perch.debugCurrentPerchState.pose == .sit }
        let passesBeforeResize = perch.debugFocusPassCount

        window.frame = CGRect(x: 0, y: 0, width: 700, height: 844)
        tbc.view.layoutIfNeeded()
        spinRunLoop(seconds: 0.3)
        perch.layoutIfNeeded()

        XCTAssertGreaterThan(perch.debugFocusPassCount, passesBeforeResize, "a width change must run a new focus pass")
        XCTAssertEqual(perch.debugCurrentPerchState.pose, .sit, "the same tab re-seats through a snap, never a fresh run")

        guard let layout = TabBarMeasurer.measure(in: window), layout.centers.count == 5 else {
            return XCTFail("expected a real measured tab bar layout at the new width")
        }
        XCTAssertEqual(onScreenSpriteCenter(perch).x, layout.centers[2], accuracy: 1.5, "the seat follows the bar to its new, wider centers")
    }

    // MARK: - Reduce Motion wiring

    func testReduceMotionNotificationRunsAFocusPass() {
        let registry = CompanionRegistry()
        let profile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        registry.register(profile)
        let (_, tbc) = makeHostedTabBarController()
        let perch = makePerchView(registry: registry, companionID: profile.id, slotCount: 5, slotIndex: 0)
        perch.attach(to: tbc)
        tbc.view.layoutIfNeeded()
        waitUntil { perch.debugCurrentPerchState.pose == .sit }
        let passesBefore = perch.debugFocusPassCount

        NotificationCenter.default.post(name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)

        XCTAssertGreaterThan(perch.debugFocusPassCount, passesBefore, "the Reduce Motion notification must run a focus pass")
    }

    // MARK: - Removal from the superview tears the controller down

    func testRemovingFromSuperviewTearsDownAndIgnoresFurtherPropertyChanges() {
        let registry = CompanionRegistry()
        let profile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        registry.register(profile)
        let (window, tbc) = makeHostedTabBarController()
        let perch = makePerchView(registry: registry, companionID: profile.id, slotCount: 5, slotIndex: 0)
        perch.attach(to: tbc)
        tbc.view.layoutIfNeeded()
        waitUntil { perch.debugCurrentPerchState.pose == .sit }
        XCTAssertFalse(perch.debugIsTornDown)

        perch.removeFromSuperview()

        XCTAssertTrue(perch.debugIsTornDown, "removal from the superview must tear the controller down")
        XCTAssertNotEqual(perch.debugClock.debugIsLinkPaused, false, "the clock's link must never be left running once torn down")

        let stateBefore = perch.debugCurrentPerchState
        perch.selectTab(3)
        spinRunLoop(seconds: 0.2)
        XCTAssertEqual(perch.debugCurrentPerchState, stateBefore, "a property change after teardown must reach nothing")

        _ = window
    }

    // MARK: - Leaving the window alone (no removal) suspends and resumes

    func testFullScreenPresentationSuspendsAndResumesOnDismiss() {
        let registry = CompanionRegistry()
        let profile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        registry.register(profile)
        let (window, tbc) = makeHostedTabBarController()
        let perch = makePerchView(registry: registry, companionID: profile.id, slotCount: 5, slotIndex: 0)
        perch.attach(to: tbc)
        tbc.view.layoutIfNeeded()
        waitUntil { perch.debugCurrentPerchState.pose == .sit }

        // A real .fullScreen presentation drops the presenter's view from
        // the window via a live transition coordinator this host has none
        // of - swapping the root controller reproduces the same loss.
        let cover = UIViewController()
        window.rootViewController = cover
        waitUntil { tbc.view.window == nil }
        XCTAssertNil(tbc.view.window, "setup: the tab bar controller's view must be out of its window")
        XCTAssertFalse(perch.debugIsTornDown, "a screen covering it must never tear the controller down")

        window.rootViewController = tbc
        waitUntil { tbc.view.window != nil }
        tbc.view.layoutIfNeeded()
        waitUntil { perch.debugCurrentPerchState.visible >= 0.99 }

        // Before any tab change: the round trip alone must already have
        // reseated and shown the pet again.
        XCTAssertEqual(perch.debugSpriteView.alpha, 1, accuracy: 0.01, "the pet must be visible once the window returns")
        XCTAssertEqual(perch.debugCurrentPerchState.pose, .sit, "the pet must already be seated once the window returns")

        perch.selectTab(2)
        waitUntil(timeout: 5) { perch.debugCurrentPerchState.pose == .sit }

        guard let layout = TabBarMeasurer.measure(in: window), layout.centers.count == 5 else {
            return XCTFail("expected a real measured tab bar layout")
        }
        XCTAssertEqual(onScreenSpriteCenter(perch).x, layout.centers[2], accuracy: 1.5, "a tab change after a full screen round trip must still reach the measured center")
        XCTAssertEqual(perch.debugCurrentPerchState.pose, .sit, "the chase must settle back to sit")
    }

    // MARK: - Detach

    func testDetachRemovesTheViewAndLeavesExactlyOnePerchAttached() {
        let registry = CompanionRegistry()
        let profile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        registry.register(profile)
        let (_, tbc) = makeHostedTabBarController()
        let root = makePerchView(registry: registry, companionID: profile.id, slotCount: 5, slotIndex: 0)
        root.attach(to: tbc)
        tbc.view.layoutIfNeeded()
        waitUntil { root.debugCurrentPerchState.pose == .sit }

        weak var weakPushed: CompanionPerchView?
        autoreleasepool {
            var pushed: CompanionPerchView? = makePerchView(registry: registry, companionID: profile.id, slotCount: 5, slotIndex: 4)
            pushed?.transientSlot = true
            pushed?.attach(to: tbc)
            tbc.view.layoutIfNeeded()
            weakPushed = pushed
            waitUntil { pushed?.debugCurrentPerchState.pose == .sit }

            pushed?.detach()
            pushed = nil
        }
        waitUntil { weakPushed == nil }

        let perchViews = tbc.view.subviews.filter { $0 is CompanionPerchView }
        XCTAssertEqual(perchViews.count, 1, "exactly one perch must remain attached after the pushed one detaches")
        XCTAssertNil(weakPushed, "the detached perch must deallocate")
    }

    // MARK: - A re-tap of the current tab

    func testReTappingTheCurrentTabDuringARunDoesNotSnap() {
        let registry = CompanionRegistry()
        // The slowest profile: real-clock margins stay wide however long
        // the spins below actually take on a loaded machine.
        let profile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20, runSpeed: 20)
        registry.register(profile)
        let (_, tbc) = makeHostedTabBarController()
        let perch = makePerchView(registry: registry, companionID: profile.id, slotCount: 5, slotIndex: 0)
        perch.attach(to: tbc)
        tbc.view.layoutIfNeeded()
        waitUntil { perch.debugCurrentPerchState.pose == .sit }
        let startX = onScreenSpriteCenter(perch).x

        perch.selectTab(3)
        waitUntil(timeout: 5) { perch.debugCurrentPerchState.pose == .run }
        spinRunLoop(seconds: 0.15)
        let targetX = TabBarMeasurer.measure(in: perch.window ?? UIWindow())?.centers[3] ?? startX

        perch.selectTab(3)
        // Read after the re-tap, not before it: a snap would show up right here.
        spinRunLoop(seconds: 0.1)
        let xAfterReTap = onScreenSpriteCenter(perch).x

        XCTAssertEqual(perch.debugCurrentPerchState.pose, .run, "a re-tap of the running tab must not snap the chase")
        let lower = Swift.min(startX, targetX)
        let upper = Swift.max(startX, targetX)
        XCTAssertGreaterThan(xAfterReTap, lower + 1.5, "the sprite must be strictly past its start, not snapped back to it")
        XCTAssertLessThan(xAfterReTap, upper - 1.5, "the sprite must be strictly short of its target, not snapped ahead to it")
    }

    // MARK: - Hit testing over an invisible pet

    func testPointInsideReturnsFalseOverAnInvisibleSprite() {
        let registry = CompanionRegistry()
        let profile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        registry.register(profile)
        let (_, tbc) = makeHostedTabBarController()
        let perch = makePerchView(registry: registry, companionID: profile.id, slotCount: 5, slotIndex: 0)
        perch.attach(to: tbc)
        tbc.view.layoutIfNeeded()
        waitUntil { perch.debugCurrentPerchState.pose == .sit }
        let onScreenCenter = onScreenSpriteCenter(perch)

        perch.isPerchFocused = false
        waitUntil { perch.debugCurrentPerchState.visible <= 0.01 }

        let point = CGPoint(x: onScreenCenter.x, y: onScreenCenter.y)
        let hit = tbc.view.hitTest(perch.convert(point, to: tbc.view), with: nil)
        XCTAssertFalse(hit === perch, "a blurred, invisible perch must not itself be hit")
        XCTAssertFalse(hit === perch.debugSpriteView, "a blurred, invisible sprite must not itself be hit")
    }

    // MARK: - A height-only resize

    func testHeightOnlyResizeRefreshesTheResolvedBarTop() {
        let registry = CompanionRegistry()
        let profile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        registry.register(profile)
        let (window, tbc) = makeHostedTabBarController(tabCount: 5, width: 390, height: 700)
        let perch = makePerchView(registry: registry, companionID: profile.id, slotCount: 5, slotIndex: 2)
        perch.attach(to: tbc)
        tbc.view.layoutIfNeeded()
        waitUntil { perch.debugCurrentPerchState.pose == .sit }

        window.frame = CGRect(x: 0, y: 0, width: 390, height: 900)
        tbc.view.layoutIfNeeded()
        spinRunLoop(seconds: 0.3)
        perch.layoutIfNeeded()

        guard let layout = TabBarMeasurer.measure(in: window), layout.centers.count == 5, let top = layout.top else {
            return XCTFail("expected a real measured tab bar layout at the new height")
        }
        XCTAssertEqual(perch.debugCurrentPerchState.barTop ?? -1, top, accuracy: 0.5, "a height-only resize must refresh the resolved bar top, not just a width change")
    }

    // MARK: - Mutation: a bad anchor sanitized at the boundary

    func testMutation_NonFinitePillAndZeroSlotCountGiveAFiniteTransformAndOneErrorReport() {
        let registry = CompanionRegistry()
        let profile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        registry.register(profile)
        let (_, tbc) = makeHostedTabBarController()
        var errors: [(Error, String)] = []
        let perch = CompanionPerchView(
            companionID: profile.id,
            registry: registry,
            anchor: CompanionAnchor(slotCount: 5, slotIndex: 0),
            handoff: PerchHandoffStore(),
            onError: { error, site in errors.append((error, site)) }
        )
        perch.attach(to: tbc)
        tbc.view.layoutIfNeeded()
        waitUntil { perch.debugCurrentPerchState.pose == .sit }

        // A non-finite pill alone, valid slot count otherwise, must still
        // report - the only way to prove that branch runs, since routing
        // never engages in this build. Each case starts from a valid anchor.
        errors.removeAll()
        perch.anchor = CompanionAnchor(slotCount: 5, slotIndex: 1, pill: PillFrame(x: .nan, y: 0, width: 10, height: 10))
        waitUntil { perch.debugCurrentPerchState.pose == .sit }
        XCTAssertEqual(errors.count, 1, "a non-finite pill alone must be reported")

        // A slot count below 1 alone, no other bad value, must also report.
        errors.removeAll()
        perch.anchor = CompanionAnchor(slotCount: 5, slotIndex: 2)
        waitUntil { perch.debugCurrentPerchState.pose == .sit }
        errors.removeAll()
        perch.anchor = CompanionAnchor(slotCount: 0, slotIndex: 2)
        waitUntil { perch.debugCurrentPerchState.pose == .sit }
        XCTAssertEqual(errors.count, 1, "a slot count below 1 alone must be reported")

        errors.removeAll()
        perch.anchor = CompanionAnchor(slotCount: 5, slotIndex: 3)
        waitUntil { perch.debugCurrentPerchState.pose == .sit }
        errors.removeAll()
        perch.anchor = CompanionAnchor(slotCount: 0, slotIndex: 3, pill: PillFrame(x: .nan, y: 0, width: 10, height: 10))
        waitUntil { perch.debugCurrentPerchState.pose == .sit }

        let state = perch.debugCurrentPerchState
        XCTAssertTrue(state.x.isFinite && state.hop.isFinite && state.seatY.isFinite, "a bad anchor must still resolve to a finite transform")
        XCTAssertEqual(errors.count, 1, "a slotCount below 1 and a non-finite pill together must report exactly once, not twice")
        XCTAssertEqual(errors.first?.0 as? CompanionPerchError, .invalidSlotCount(0), "slot count wins when both are bad in the same anchor")
    }

    // MARK: - Mutation: a non-finite center from the host

    func testMutation_NonFiniteSlotCentersFallBackToNativeMeasurement() {
        let registry = CompanionRegistry()
        let profile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        registry.register(profile)
        let (window, tbc) = makeHostedTabBarController(tabCount: 5, width: 390)
        let perch = makePerchView(registry: registry, companionID: profile.id, slotCount: 5, slotIndex: 1)
        perch.attach(to: tbc)
        tbc.view.layoutIfNeeded()
        waitUntil { perch.debugCurrentPerchState.pose == .sit }

        perch.anchor = CompanionAnchor(slotCount: 5, slotIndex: 1, slotCenters: [Double.nan, 100, 200, 300, 400])
        waitUntil { perch.debugCurrentPerchState.pose == .sit }

        guard let layout = TabBarMeasurer.measure(in: window), layout.centers.count == 5 else {
            return XCTFail("expected a real measured tab bar layout")
        }
        XCTAssertEqual(onScreenSpriteCenter(perch).x, layout.centers[1], accuracy: 1.5, "a non-finite host center must be treated as not provided, falling back to native measurement")
    }

    // MARK: - Mutation: busy listener lifecycle (no isolated deinit)

    func testMutation_ABuiltAndDroppedPerchNeverAttachedLeavesNoBusyListener() {
        let registry = CompanionRegistry()
        let profile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        registry.register(profile)
        let busyState = CompanionState()
        let before = busyState.debugListenerCount

        autoreleasepool {
            let perch = CompanionPerchView(
                companionID: profile.id,
                registry: registry,
                anchor: CompanionAnchor(slotCount: 5, slotIndex: 0),
                handoff: PerchHandoffStore(),
                busy: busyState
            )
            _ = perch
        }

        XCTAssertEqual(busyState.debugListenerCount, before, "a perch built and dropped before ever attaching must leave no busy listener")
    }

    func testMutation_DetachWhileStillInItsWindowLeavesNoBusyListener() {
        let registry = CompanionRegistry()
        let profile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        registry.register(profile)
        let busyState = CompanionState()
        let before = busyState.debugListenerCount
        let (_, tbc) = makeHostedTabBarController()

        let perch = CompanionPerchView(
            companionID: profile.id,
            registry: registry,
            anchor: CompanionAnchor(slotCount: 5, slotIndex: 0),
            handoff: PerchHandoffStore(),
            busy: busyState
        )
        perch.attach(to: tbc)
        tbc.view.layoutIfNeeded()
        waitUntil { perch.debugCurrentPerchState.pose == .sit }
        XCTAssertGreaterThan(busyState.debugListenerCount, before, "setup: attaching must have subscribed")

        // Still in its window at the moment of detach - unlike the whole-
        // hierarchy case above, didMoveToWindow's own window-loss branch
        // never gets a turn (isTornDown is already true by the time it would).
        perch.detach()

        XCTAssertEqual(busyState.debugListenerCount, before, "an explicit detach while still windowed must leave no busy listener")
    }

    func testMutation_APerchAttachedThenReleasedWithTheWholeHierarchyLeavesNoBusyListener() {
        let registry = CompanionRegistry()
        let profile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        registry.register(profile)
        let busyState = CompanionState()
        let before = busyState.debugListenerCount

        autoreleasepool {
            var window: UIWindow? = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            let tbc = UITabBarController()
            tbc.viewControllers = (0..<3).map { _ in UIViewController() }
            window?.rootViewController = tbc
            window?.makeKeyAndVisible()
            tbc.view.layoutIfNeeded()

            let perch = CompanionPerchView(
                companionID: profile.id,
                registry: registry,
                anchor: CompanionAnchor(slotCount: 3, slotIndex: 0),
                handoff: PerchHandoffStore(),
                busy: busyState
            )
            perch.attach(to: tbc)
            tbc.view.layoutIfNeeded()
            waitUntil { perch.debugCurrentPerchState.pose == .sit }
            XCTAssertGreaterThan(busyState.debugListenerCount, before, "setup: attaching must have subscribed")

            // No detach - the whole hierarchy goes down together.
            window?.rootViewController = nil
            window = nil
        }

        XCTAssertEqual(busyState.debugListenerCount, before, "a perch whose whole hierarchy is released without detach must leave no busy listener")
    }

    // MARK: - Mutation: a torn-down perch ignores everything

    func testMutation_TornDownPerchIgnoresEveryLaterPropertyChangeAndStartsNoTrack() {
        let registry = CompanionRegistry()
        let profileA = SpriteTestFixtures.makeFixtureProfile(id: "fixture-a", cellSize: 20)
        let profileB = SpriteTestFixtures.makeFixtureProfile(id: "fixture-b", cellSize: 20)
        registry.register(profileA)
        registry.register(profileB)
        let (_, tbc) = makeHostedTabBarController()
        var errors: [(Error, String)] = []
        let perch = CompanionPerchView(
            companionID: profileA.id,
            registry: registry,
            anchor: CompanionAnchor(slotCount: 5, slotIndex: 0),
            handoff: PerchHandoffStore(),
            onError: { error, site in errors.append((error, site)) }
        )
        perch.attach(to: tbc)
        tbc.view.layoutIfNeeded()
        waitUntil { perch.debugCurrentPerchState.pose == .sit }

        perch.detach()
        XCTAssertTrue(perch.debugIsTornDown, "setup: detach must tear the perch down")
        errors.removeAll()
        let passesBefore = perch.debugFocusPassCount

        perch.companionID = profileB.id
        perch.bottomExtra = .nan
        NotificationCenter.default.post(name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
        perch.selectTab(2)

        XCTAssertEqual(errors.count, 0, "a torn-down perch must report nothing")
        XCTAssertEqual(perch.debugFocusPassCount, passesBefore, "a torn-down perch must run no focus pass")
        XCTAssertFalse(perch.debugEngine.isAnyTrackActive(labelPrefix: ""), "a torn-down perch must start no new track")
    }

    // MARK: - Mutation: an equal anchor mid-run

    func testMutation_AssigningAnEqualAnchorMidRunDoesNotRestartTheChase() {
        let registry = CompanionRegistry()
        let profile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20, runSpeed: 20)
        registry.register(profile)
        let (_, tbc) = makeHostedTabBarController()
        let perch = makePerchView(registry: registry, companionID: profile.id, slotCount: 5, slotIndex: 0)
        perch.attach(to: tbc)
        tbc.view.layoutIfNeeded()
        waitUntil { perch.debugCurrentPerchState.pose == .sit }
        let startX = onScreenSpriteCenter(perch).x

        perch.selectTab(3)
        waitUntil(timeout: 5) { perch.debugCurrentPerchState.pose == .run }
        spinRunLoop(seconds: 0.15)
        let targetX = TabBarMeasurer.measure(in: perch.window ?? UIWindow())?.centers[3] ?? startX
        let passesBefore = perch.debugFocusPassCount

        perch.anchor = CompanionAnchor(slotCount: 5, slotIndex: 3)

        XCTAssertEqual(perch.debugFocusPassCount, passesBefore, "an anchor equal to the current one must run no fresh focus pass")
        XCTAssertEqual(perch.debugCurrentPerchState.pose, .run, "the chase must still be running")
        // Spun several frames past the equal-anchor assignment above, so the
        // lower bound below clears by whole frames on the real clock, not
        // half of one - a flaky margin the manual clock never had to face.
        spinRunLoop(seconds: 0.5)
        let midX = onScreenSpriteCenter(perch).x
        let lower = Swift.min(startX, targetX)
        let upper = Swift.max(startX, targetX)
        XCTAssertGreaterThan(midX, lower + 1.5, "the sprite must be strictly past its start")
        XCTAssertLessThan(midX, upper - 1.5, "the sprite must be strictly short of its target")
    }

    // MARK: - Mutation: a focus pass while off window never undoes the blur

    func testMutation_FocusPassWhileOffWindowNeverUndoesTheBlur() {
        let registry = CompanionRegistry()
        let profile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        registry.register(profile)
        let (window, tbc) = makeHostedTabBarController()
        let perch = makePerchView(registry: registry, companionID: profile.id, slotCount: 5, slotIndex: 0)
        perch.attach(to: tbc)
        tbc.view.layoutIfNeeded()
        waitUntil { perch.debugCurrentPerchState.pose == .sit }

        let cover = UIViewController()
        window.rootViewController = cover
        waitUntil { tbc.view.window == nil }
        waitUntil { perch.debugCurrentPerchState.visible <= 0.01 }

        perch.selectTab(2)
        spinRunLoop(seconds: 0.1)
        XCTAssertLessThanOrEqual(perch.debugCurrentPerchState.visible, 0.01, "a focus pass while off the window must never undo the blur")

        window.rootViewController = tbc
        waitUntil { tbc.view.window != nil }
        waitUntil { perch.debugCurrentPerchState.visible >= 0.99 }
        XCTAssertEqual(perch.debugCurrentPerchState.visible, 1, accuracy: 0.01, "the pet must be visible again once the window returns")
    }

    // MARK: - Mutation: a busy claim held while off window still arrives idle

    func testMutation_ABusyClaimBegunWhileOffWindowStillArrivesIdleAfterATabChangeAndDismiss() {
        let registry = CompanionRegistry()
        let profile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        registry.register(profile)
        let busyState = CompanionState()
        let (window, tbc) = makeHostedTabBarController()
        let perch = CompanionPerchView(
            companionID: profile.id,
            registry: registry,
            anchor: CompanionAnchor(slotCount: 5, slotIndex: 0),
            handoff: PerchHandoffStore(),
            busy: busyState
        )
        perch.attach(to: tbc)
        tbc.view.layoutIfNeeded()
        waitUntil { perch.debugCurrentPerchState.pose == .sit }

        let cover = UIViewController()
        window.rootViewController = cover
        waitUntil { tbc.view.window == nil }
        waitUntil { perch.debugCurrentPerchState.visible <= 0.01 }

        // Still subscribed off window: the claim below must reach `busy` at
        // once. A resubscribe-and-reseed on window return would also land
        // on the right answer here, so this is the real proof of the fix.
        let endBusyClaim = busyState.beginCompanionBusy()
        XCTAssertTrue(perch.debugCurrentPerchState.busy, "a claim begun off window must reach the controller immediately")
        perch.selectTab(2)

        window.rootViewController = tbc
        waitUntil { tbc.view.window != nil }
        waitUntil(timeout: 5) { perch.debugCurrentPerchState.pose == .idle }

        XCTAssertEqual(perch.debugCurrentPerchState.pose, .idle, "a busy claim held since before the window returned must still be reflected")
        endBusyClaim()
    }

    // MARK: - Mutation: an invalid anchor is sanitized once, not every pass

    func testMutation_InvalidAnchorReportsOnceAcrossFocusPassesAndOnceMoreOnReturn() {
        let registry = CompanionRegistry()
        let profile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        registry.register(profile)
        let (_, tbc) = makeHostedTabBarController()
        var errors: [(Error, String)] = []
        let invalidAnchor = CompanionAnchor(slotCount: 0, slotIndex: 0)
        let perch = CompanionPerchView(
            companionID: profile.id,
            registry: registry,
            anchor: invalidAnchor,
            handoff: PerchHandoffStore(),
            onError: { error, site in errors.append((error, site)) }
        )
        perch.attach(to: tbc)
        tbc.view.layoutIfNeeded()
        waitUntil { perch.debugCurrentPerchState.pose == .sit }

        // Two more focus passes, no anchor change - the init's own report
        // (through attach's own window-entry pass) must not repeat.
        perch.isPerchFocused = false
        perch.isPerchFocused = true
        XCTAssertEqual(errors.count, 1, "an invalid anchor at init must report exactly once through three focus passes")
        XCTAssertEqual(errors.first?.0 as? CompanionPerchError, .invalidSlotCount(0), "the reported error must be invalidSlotCount(0)")

        // Three selectTab calls, still slotCount 0 - each assigns a distinct
        // anchor (a new slotIndex), but the invalid condition never clears.
        errors.removeAll()
        perch.selectTab(1)
        perch.selectTab(2)
        perch.selectTab(3)
        XCTAssertEqual(errors.count, 0, "three selectTab calls while still invalid must report nothing more")

        errors.removeAll()
        perch.anchor = CompanionAnchor(slotCount: 5, slotIndex: 0)
        waitUntil { perch.debugCurrentPerchState.pose == .sit }
        XCTAssertEqual(errors.count, 0, "a valid anchor must not report")

        perch.anchor = invalidAnchor
        waitUntil { perch.debugCurrentPerchState.pose == .sit }
        XCTAssertEqual(errors.count, 1, "setting the same invalid anchor again must report once more")
    }

    // MARK: - Push and pop through a small host mirroring the demo's pattern

    func testPushThenPopBlursTheRootAndDetachesOnlyOnTheRealPop() {
        let registry = CompanionRegistry()
        let profile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        registry.register(profile)
        let (_, tbc) = makeHostedTabBarController()
        let root = makePerchView(registry: registry, companionID: profile.id, slotCount: 5, slotIndex: 0)
        root.attach(to: tbc)
        tbc.view.layoutIfNeeded()
        waitUntil { root.debugCurrentPerchState.pose == .sit }

        let nav = UINavigationController(rootViewController: UIViewController())
        tbc.viewControllers = [nav]
        tbc.view.layoutIfNeeded()
        spinRunLoop(seconds: 0.1)

        weak var weakPushedPerch: CompanionPerchView?
        autoreleasepool {
            var pushedPerch: CompanionPerchView? = makePerchView(registry: registry, companionID: profile.id, slotCount: 5, slotIndex: 4)
            pushedPerch?.transientSlot = true
            weakPushedPerch = pushedPerch
            let screen = TestPushedPerchScreen(perch: pushedPerch!, rootPerch: root)
            pushedPerch = nil

            nav.pushViewController(screen, animated: false)
            spinRunLoop(seconds: 0.2)

            XCTAssertEqual(root.debugSpriteView.alpha, 0, accuracy: 0.01, "the root pet must be hidden while the pushed screen is up")
            XCTAssertEqual(screen.perch.debugSpriteView.alpha, 1, accuracy: 0.01, "the pushed pet must be visible")

            nav.popViewController(animated: false)
            spinRunLoop(seconds: 0.2)

            let perchViews = tbc.view.subviews.filter { $0 is CompanionPerchView }
            XCTAssertEqual(perchViews.count, 1, "exactly one perch must remain attached after a real pop")
            XCTAssertEqual(root.debugSpriteView.alpha, 1, accuracy: 0.01, "the root pet must be visible again after the pop")
        }

        waitUntil { weakPushedPerch == nil }
        XCTAssertNil(weakPushedPerch, "the pushed perch must deallocate once the screen pops")
    }

    // MARK: - A disappearance transition that does not pop must still blur

    func testAppearanceTransitionsToggleFocusWithoutPopping() {
        let registry = CompanionRegistry()
        let profile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        registry.register(profile)
        let (_, tbc) = makeHostedTabBarController()
        let root = makePerchView(registry: registry, companionID: profile.id, slotCount: 5, slotIndex: 0)
        root.attach(to: tbc)
        tbc.view.layoutIfNeeded()
        waitUntil { root.debugCurrentPerchState.pose == .sit }

        // A container that takes manual control of child appearance: with
        // automatic forwarding left on, UIKit treats an externally-driven
        // begin/endAppearanceTransition pair as a real removal on its own.
        let container = TestManualAppearanceContainer()
        tbc.viewControllers = [container]
        tbc.view.layoutIfNeeded()
        spinRunLoop(seconds: 0.1)

        let pushedPerch = makePerchView(registry: registry, companionID: profile.id, slotCount: 5, slotIndex: 4)
        pushedPerch.transientSlot = true
        let screen = TestPushedPerchScreen(perch: pushedPerch, rootPerch: root)
        container.addChild(screen)
        container.view.addSubview(screen.view)
        screen.view.frame = container.view.bounds
        screen.beginAppearanceTransition(true, animated: false)
        screen.endAppearanceTransition()
        screen.didMove(toParent: container)
        spinRunLoop(seconds: 0.2)
        XCTAssertEqual(screen.perch.debugSpriteView.alpha, 1, accuracy: 0.01, "setup: the pushed pet must be visible")

        // A cancelled edge-swipe, or a tab switch away, drives this pair
        // without ever popping - `isMovingFromParent` is false throughout.
        screen.beginAppearanceTransition(false, animated: false)
        screen.endAppearanceTransition()
        XCTAssertEqual(screen.perch.debugSpriteView.alpha, 0, accuracy: 0.01, "the pushed pet must blur on a non-popping disappearance")
        XCTAssertEqual(root.debugSpriteView.alpha, 1, accuracy: 0.01, "the root pet must reappear on a non-popping disappearance")

        screen.beginAppearanceTransition(true, animated: false)
        screen.endAppearanceTransition()
        XCTAssertEqual(screen.perch.debugSpriteView.alpha, 1, accuracy: 0.01, "the pushed pet must refocus on the reverse transition")
        XCTAssertEqual(root.debugSpriteView.alpha, 0, accuracy: 0.01, "the root pet must blur again on the reverse transition")
    }
}

// MARK: - A container that drives child appearance itself, not the OS

/// Automatic forwarding left on treats a manually-driven begin/end pair as
/// a real removal (`isMovingFromParent` flips true on its own); this puts
/// that call under the test's own control instead.
@MainActor
private final class TestManualAppearanceContainer: UIViewController {
    override var shouldAutomaticallyForwardAppearanceMethods: Bool { false }
}

// MARK: - A small host mirroring the demo's own push/pop pattern

/// Mirrors `PushedPerchViewController`'s own lifecycle: blurs the root and
/// focuses its own perch on appear, the reverse on disappear (no
/// `isMovingFromParent` guard), and detaches only on a real pop.
@MainActor
private final class TestPushedPerchScreen: UIViewController {
    let perch: CompanionPerchView
    private weak var rootPerch: CompanionPerchView?

    init(perch: CompanionPerchView, rootPerch: CompanionPerchView?) {
        self.perch = perch
        self.rootPerch = rootPerch
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if let tabBarController {
            perch.attach(to: tabBarController)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        rootPerch?.isPerchFocused = false
        perch.isPerchFocused = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        perch.isPerchFocused = false
        rootPerch?.isPerchFocused = true
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isMovingFromParent else { return }
        perch.detach()
    }
}
#endif
