#if canImport(UIKit)
import XCTest

import TabPetMotion
@testable import TabPetUIKit
import TabPetCore

@MainActor
final class CompanionSpriteViewTests: XCTestCase {
    private func makeWindow() -> UIWindow {
        UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
    }

    private func waitUntilReady(_ view: CompanionSpriteView, timeout: TimeInterval = 5) {
        let deadline = Date().addingTimeInterval(timeout)
        while view.visualState != .ready && view.visualState != .error && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        XCTAssertEqual(view.visualState, .ready, "sheets never finished loading")
    }

    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
    }

    // MARK: - contentsRect (pure geometry)

    func testContentsRectMapsFrameZeroToTheTopLeftCell() {
        let rect = CompanionSpriteView.contentsRect(frame: 0, cols: 5, rows: 5, pixelWidth: 250, pixelHeight: 250)
        // A half-texel inset on every side (0.5 / 250 = 0.002) keeps linear
        // filtering from blending in the next cell, so the un-inset cell
        // (0, 0, 0.2, 0.2) comes back slightly smaller and shifted inward.
        let halfTexel: CGFloat = 0.002
        XCTAssertEqual(rect.origin.x, halfTexel, accuracy: 0.0005)
        XCTAssertEqual(rect.origin.y, halfTexel, accuracy: 0.0005)
        XCTAssertEqual(rect.width, 0.2 - 2 * halfTexel, accuracy: 0.0005)
        XCTAssertEqual(rect.height, 0.2 - 2 * halfTexel, accuracy: 0.0005)
    }

    func testContentsRectMapsFrameToItsRowMajorCell() {
        // 4 cols: frame 6 -> col 2, row 1.
        let rect = CompanionSpriteView.contentsRect(frame: 6, cols: 4, rows: 3, pixelWidth: 400, pixelHeight: 300)
        XCTAssertEqual(rect.origin.x, 2.0 / 4.0, accuracy: 0.01)
        XCTAssertEqual(rect.origin.y, 1.0 / 3.0, accuracy: 0.01)
    }

    func testContentsRectInsetsAHalfTexelSoItNeverTouchesTheNextCell() {
        let full = CompanionSpriteView.contentsRect(frame: 0, cols: 5, rows: 5, pixelWidth: 250, pixelHeight: 250)
        let uninsetWidth: CGFloat = 0.2
        XCTAssertLessThan(full.width, uninsetWidth, "the inset must shrink the rect, never leave it exactly on the cell edge")
        XCTAssertGreaterThan(full.origin.x, 0, "frame 0's rect must not start exactly at 0 once inset")
    }

    // MARK: - Rendering (after a commit)

    func testAfterACommitTheLayerHasNoAnimationKeysAndContentsRectMatchesTheExpectedCell() {
        let registry = CompanionRegistry()
        let profile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        registry.register(profile)
        let clock = ManualClock()
        let view = CompanionSpriteView(companionID: profile.id, registry: registry, clock: clock)
        let window = makeWindow()
        window.addSubview(view)
        window.makeKeyAndVisible()
        view.layoutIfNeeded()
        waitUntilReady(view)

        view.pose = .sit
        // Same-pose settle: advance to a known point mid-timing and read the
        // frame the engine actually landed on, rather than assuming a value.
        clock.advance(ms: 500, frameMs: 1000.0 / 60)

        let sitLayer = view.debugLayer(for: .sit)
        // Written inside CATransaction.setDisableActions(true) in render()
        // (the same pattern hideAllLayers/assignLayerContents/layoutSubviews
        // already use). Removing that call is caught by this assertion.
        XCTAssertNil(sitLayer.animationKeys(), "every layer write happens with implicit actions disabled")

        let expectedFrame = view.debugCurrentFrame(for: .sit)
        let expectedRect = CompanionSpriteView.contentsRect(
            frame: expectedFrame,
            cols: CompanionProfile.IDLE_SHEET_GRID.cols,
            rows: CompanionProfile.IDLE_SHEET_GRID.rows,
            pixelWidth: 20 * CompanionProfile.IDLE_SHEET_GRID.cols,
            pixelHeight: 20 * CompanionProfile.IDLE_SHEET_GRID.rows
        )
        XCTAssertEqual(sitLayer.contentsRect.origin.x, expectedRect.origin.x, accuracy: 0.0001)
        XCTAssertEqual(sitLayer.contentsRect.origin.y, expectedRect.origin.y, accuracy: 0.0001)
    }

    // MARK: - apply(pose:busy:facing:) batches into one commit

    func testApplyingPoseAndFacingTogetherProducesExactlyOneCommit() {
        let registry = CompanionRegistry()
        let profile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        registry.register(profile)
        let clock = ManualClock()
        let view = CompanionSpriteView(companionID: profile.id, registry: registry, clock: clock)
        let window = makeWindow()
        window.addSubview(view)
        window.makeKeyAndVisible()
        waitUntilReady(view)

        let commitsBefore = view.debugCommitCount
        view.apply(pose: .run, busy: true, facing: .left)

        XCTAssertEqual(view.debugCommitCount - commitsBefore, 1, "a pose, busy and facing change together must commit exactly once")
        XCTAssertEqual(view.pose, .run)
        XCTAssertTrue(view.isBusy)
        XCTAssertEqual(view.facing, .left)
    }

    func testApplyingTheSameStateAgainCommitsNothing() {
        let registry = CompanionRegistry()
        let profile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        registry.register(profile)
        let clock = ManualClock()
        let view = CompanionSpriteView(companionID: profile.id, registry: registry, clock: clock)
        let window = makeWindow()
        window.addSubview(view)
        window.makeKeyAndVisible()
        waitUntilReady(view)
        view.apply(pose: .run, busy: true, facing: .left)

        let commitsBefore = view.debugCommitCount
        view.apply(pose: .run, busy: true, facing: .left)

        XCTAssertEqual(view.debugCommitCount, commitsBefore, "an apply matching the current state must not commit again")
    }

    // MARK: - A shared-engine companion swap tears the outgoing player down

    func testChangingCompanionIDTearsDownTheOutgoingPlayersSharedTracks() {
        let registry = CompanionRegistry()
        let profileA = SpriteTestFixtures.makeFixtureProfile(id: "swap-a", cellSize: 20)
        let profileB = SpriteTestFixtures.makeFixtureProfile(id: "swap-b", cellSize: 20)
        registry.register(profileA)
        registry.register(profileB)
        let clock = ManualClock()
        let engine = MotionEngine(clock: clock)
        let view = CompanionSpriteView(companionID: profileA.id, registry: registry, engine: engine, clock: clock)
        let window = makeWindow()
        window.addSubview(view)
        window.makeKeyAndVisible()
        waitUntilReady(view)

        view.pose = .idle
        view.isBusy = true
        clock.advance(ms: 50, frameMs: 1000.0 / 60)
        XCTAssertTrue(engine.isAnyTrackActive(labelPrefix: "sprite."), "setup: a busy idle loop must be active on the shared engine")

        // The swap lands mid busy-idle-loop, the bug's exact shape - the
        // incoming player commits the same busy state next, so only
        // turning busy off afterward isolates a leftover outgoing loop.
        view.companionID = profileB.id
        waitUntilReady(view)
        view.isBusy = false
        view.pose = .sit
        clock.advance(ms: 20_000, frameMs: 1000.0 / 60)

        XCTAssertFalse(engine.isAnyTrackActive(labelPrefix: "sprite."), "the outgoing player's own loop track must not survive a companion swap")
    }

    func testFacingLeftFlipsTheCurrentLayersTransform() {
        let registry = CompanionRegistry()
        let profile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        registry.register(profile)
        let clock = ManualClock()
        let view = CompanionSpriteView(companionID: profile.id, registry: registry, clock: clock)
        let window = makeWindow()
        window.addSubview(view)
        window.makeKeyAndVisible()
        waitUntilReady(view)

        view.facing = .left
        let idleLayer = view.debugLayer(for: .idle)
        XCTAssertLessThan(idleLayer.transform.m11, 0, "facing left must mirror the current pose layer's transform")
    }

    // MARK: - Five states

    func testLoadingStateDrawsNothingBeforeSheetsFinish() {
        let registry = CompanionRegistry()
        let profile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        registry.register(profile)
        let view = CompanionSpriteView(companionID: profile.id, registry: registry)
        // Right after construction, the async decode has not had a chance
        // to run yet - still loading, drawing nothing.
        XCTAssertEqual(view.visualState, .loading)
        for pose in PupPose.allCases {
            XCTAssertTrue(view.debugLayer(for: pose).isHidden)
        }
    }

    func testEmptyStateWhenNoProfileIsRegisteredReportsOnceAndDrawsNothing() {
        let emptyRegistry = CompanionRegistry()
        var errors: [(Error, String)] = []
        let view = CompanionSpriteView(companionID: "nothing-registered", registry: emptyRegistry)
        view.onError = { error, site in errors.append((error, site)) }
        // onError is set after init, so re-trigger the same empty resolution
        // deterministically rather than relying on init's own timing.
        view.companionID = "still-nothing-registered"

        XCTAssertEqual(view.visualState, .empty)
        for pose in PupPose.allCases {
            XCTAssertTrue(view.debugLayer(for: pose).isHidden)
        }
        XCTAssertEqual(errors.count, 1, "the empty state reports onError exactly once")
        XCTAssertTrue(errors.first?.0 is CompanionSpriteError)
    }

    func testEmptyStateHasNoAccessibleElement() {
        let emptyRegistry = CompanionRegistry()
        let view = CompanionSpriteView(companionID: "nothing", registry: emptyRegistry)
        XCTAssertFalse(view.isAccessibilityElement, "TS renders null with no profile - no accessible tap target either")
    }

    func testARefusedSheetReportsAndDrawsNothing() {
        let registry = CompanionRegistry()
        let idleGrid = CompanionProfile.IDLE_SHEET_GRID
        let runGrid = CompanionProfile.RUN_SHEET_GRID
        // idle sheet deliberately not a multiple of its 5x5 grid.
        let badIdle = SpriteTestFixtures.makeSolidColorPNG(pixelWidth: 253, pixelHeight: 250)
        let run = SpriteTestFixtures.makeSolidColorPNG(pixelWidth: 20 * runGrid.cols, pixelHeight: 20 * runGrid.rows)
        let sit = SpriteTestFixtures.makeSolidColorPNG(pixelWidth: 20 * idleGrid.cols, pixelHeight: 20 * idleGrid.rows)
        let profile = CompanionProfile(
            id: "refused-\(UUID().uuidString)",
            label: "refused",
            runFps: 18,
            commitSpring: SpringConfig(duration: 560, dampingRatio: 0.86),
            trackSpring: SpringConfig(duration: 300, dampingRatio: 0.9),
            catchSpring: SpringConfig(duration: 260, dampingRatio: 0.9),
            hopHeight: -6,
            flightLift: 0,
            scale: 1,
            aroundRoute: false,
            sheets: CompanionSheets(idle: badIdle, run: run, sit: sit)
        )
        registry.register(profile)
        var reportedSites: [String] = []
        let view = CompanionSpriteView(companionID: profile.id, registry: registry)
        view.onError = { _, site in reportedSites.append(site) }

        waitUntil { view.visualState == .error }
        XCTAssertEqual(view.visualState, .error)
        for pose in PupPose.allCases {
            XCTAssertTrue(view.debugLayer(for: pose).isHidden, "a refused sheet must draw nothing for every layer, not only the refused pose")
        }
        XCTAssertTrue(reportedSites.contains("CompanionSpriteView.loadSheet.idle"))
    }

    // MARK: - Accessibility

    func testAccessibilityLabelMatchesTheSourceSentence() {
        let registry = CompanionRegistry()
        let profile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        registry.register(profile)
        let view = CompanionSpriteView(companionID: profile.id, registry: registry)
        XCTAssertTrue(view.isAccessibilityElement)
        XCTAssertEqual(view.accessibilityLabel, "Your companion \(profile.label). Tap to say hi.")
        XCTAssertEqual(view.accessibilityTraits, .button)
    }

    func testPressAccessibilityLabelOverridesTheGeneratedOne() {
        let registry = CompanionRegistry()
        let profile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        registry.register(profile)
        let view = CompanionSpriteView(companionID: profile.id, registry: registry)
        view.pressAccessibilityLabel = "custom label"
        XCTAssertEqual(view.accessibilityLabel, "custom label")
    }

    // MARK: - Deallocation while the link is live

    func testViewAndItsOwnedClockDeallocateTogetherWhileTheDisplayLinkIsStillLive() {
        weak var weakView: CompanionSpriteView?
        weak var weakClock: DisplayLinkClock?
        autoreleasepool {
            let registry = CompanionRegistry()
            let profile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
            registry.register(profile)
            let view = CompanionSpriteView(companionID: profile.id, registry: registry)
            weakView = view
            weakClock = view.debugOwnedClock
            let window = makeWindow()
            window.addSubview(view)
            window.makeKeyAndVisible()
            waitUntilReady(view)
            view.isBusy = true
            view.pose = .idle
            XCTAssertNotNil(weakView)
            XCTAssertNotNil(weakClock)
            // window and view both go out of scope right here, together -
            // no removeFromSuperview first, so the link is still live right
            // up to deallocation, not torn down early by suspend().
        }
        XCTAssertNil(weakView, "the view must deallocate even while its own display link is still live (busy loop running)")
        XCTAssertNil(weakClock, "the view's owned clock must not be kept alive by anything downstream of it")
    }

    // MARK: - Something animates -> the clock's wantsFrames is paused after

    func testWantsFramesIsTrueWhileAnimatingAndFalseOnceEverythingSettles() {
        let registry = CompanionRegistry()
        let profile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        registry.register(profile)
        let clock = ManualClock()
        let view = CompanionSpriteView(companionID: profile.id, registry: registry, clock: clock)
        let window = makeWindow()
        window.addSubview(view)
        window.makeKeyAndVisible()
        waitUntilReady(view)

        view.pose = .sit
        XCTAssertTrue(clock.wantsFrames, "a running sit-settle animation must keep the clock's wantsFrames true")

        clock.advance(ms: 10_000, frameMs: 1000.0 / 60)
        XCTAssertFalse(clock.wantsFrames, "once every animation (including the mount greeting) finishes, nothing should still want frames")
    }

    // MARK: - Tap semantics: distance, duration, VoiceOver

    // Test double, same shape as TabBarPanObserverPhaseTests' own fake: a
    // real recognizer only reaches most states through a live touch, so
    // `state` is overridden to return a stored fake instead.
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

    func testATapWithinDistanceAndDurationFiresHapticTapAndOnPress() {
        let registry = CompanionRegistry()
        let profile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        registry.register(profile)
        let view = CompanionSpriteView(companionID: profile.id, registry: registry)
        waitUntilReady(view)
        var haptics: [HapticKind] = []
        var pressed = 0
        view.onHaptic = { haptics.append($0) }
        view.onPress = { pressed += 1 }

        let gesture = FakeLongPressGestureRecognizer(target: nil, action: nil)
        gesture.fakeLocation = CGPoint(x: 4, y: 4)
        gesture.fakeSetState(.began)
        view.handlePressGesture(gesture)
        gesture.fakeSetState(.ended)
        view.handlePressGesture(gesture)

        XCTAssertEqual(haptics, [.selection])
        XCTAssertEqual(pressed, 1)
    }

    func testADragPastTwelvePointsCancelsTheTapWithNoHapticAndNoOnPress() {
        let registry = CompanionRegistry()
        let profile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        registry.register(profile)
        let view = CompanionSpriteView(companionID: profile.id, registry: registry)
        waitUntilReady(view)
        var haptics: [HapticKind] = []
        var pressed = 0
        view.onHaptic = { haptics.append($0) }
        view.onPress = { pressed += 1 }

        let gesture = FakeLongPressGestureRecognizer(target: nil, action: nil)
        gesture.fakeLocation = .zero
        gesture.fakeSetState(.began)
        view.handlePressGesture(gesture)
        gesture.fakeLocation = CGPoint(x: 20, y: 0)
        gesture.fakeSetState(.changed)
        view.handlePressGesture(gesture)
        gesture.fakeSetState(.ended)
        view.handlePressGesture(gesture)

        XCTAssertTrue(haptics.isEmpty, "a drag past 12pt must not fire the haptic")
        XCTAssertEqual(pressed, 0, "a drag past 12pt must not fire onPress")
    }

    func testAHoldPastFiveHundredMillisecondsCancelsTheTapWithNoOnPress() {
        let registry = CompanionRegistry()
        let profile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        registry.register(profile)
        let view = CompanionSpriteView(companionID: profile.id, registry: registry)
        waitUntilReady(view)
        var pressed = 0
        view.onPress = { pressed += 1 }

        let gesture = FakeLongPressGestureRecognizer(target: nil, action: nil)
        gesture.fakeLocation = .zero
        gesture.fakeSetState(.began)
        view.handlePressGesture(gesture)
        Thread.sleep(forTimeInterval: 0.6)
        gesture.fakeSetState(.ended)
        view.handlePressGesture(gesture)

        XCTAssertEqual(pressed, 0, "a hold past 500ms must not fire onPress")
    }

    func testLeavingTheViewsBoundsDuringChangedCancelsTheTapWithNoHapticAndNoOnPress() {
        let registry = CompanionRegistry()
        let profile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        registry.register(profile)
        let view = CompanionSpriteView(companionID: profile.id, registry: registry, size: 20)
        waitUntilReady(view)
        var haptics: [HapticKind] = []
        var pressed = 0
        view.onHaptic = { haptics.append($0) }
        view.onPress = { pressed += 1 }

        let gesture = FakeLongPressGestureRecognizer(target: nil, action: nil)
        // Touch down 2pt inside the view's own 20x20 bounds.
        gesture.fakeLocation = CGPoint(x: 18, y: 10)
        gesture.fakeSetState(.began)
        view.handlePressGesture(gesture)
        // 4pt away (well under the 12pt distance limit) but now outside bounds.
        gesture.fakeLocation = CGPoint(x: 22, y: 10)
        gesture.fakeSetState(.changed)
        view.handlePressGesture(gesture)
        gesture.fakeSetState(.ended)
        view.handlePressGesture(gesture)

        XCTAssertTrue(haptics.isEmpty, "leaving the view's bounds must cancel the tap even within the distance limit")
        XCTAssertEqual(pressed, 0, "leaving the view's bounds must not fire onPress")
    }

    func testLeavingTheViewsBoundsDetectedOnlyAtEndedStillCancelsTheTap() {
        let registry = CompanionRegistry()
        let profile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        registry.register(profile)
        let view = CompanionSpriteView(companionID: profile.id, registry: registry, size: 20)
        waitUntilReady(view)
        var pressed = 0
        view.onPress = { pressed += 1 }

        let gesture = FakeLongPressGestureRecognizer(target: nil, action: nil)
        gesture.fakeLocation = CGPoint(x: 18, y: 10)
        gesture.fakeSetState(.began)
        view.handlePressGesture(gesture)
        // No `.changed` in between - the bounds check at `.ended` itself
        // must still catch this.
        gesture.fakeLocation = CGPoint(x: 22, y: 10)
        gesture.fakeSetState(.ended)
        view.handlePressGesture(gesture)

        XCTAssertEqual(pressed, 0, "the bounds check at .ended must also cancel the tap")
    }

    func testAFailureDuringChangedReturnsThePressScaleAtOnceNotOnlyAtEnded() {
        let registry = CompanionRegistry()
        let profile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        registry.register(profile)
        let clock = ManualClock()
        let view = CompanionSpriteView(companionID: profile.id, registry: registry, clock: clock)
        waitUntilReady(view)

        let gesture = FakeLongPressGestureRecognizer(target: nil, action: nil)
        gesture.fakeLocation = CGPoint(x: 4, y: 4)
        gesture.fakeSetState(.began)
        view.handlePressGesture(gesture)
        clock.advance(ms: 60, frameMs: 1) // halfway through the 120ms press-in
        let midPressScale = view.debugViewportLayer.transform.m11
        XCTAssertLessThan(midPressScale, 1, "sanity: the press-in animation is under way")

        gesture.fakeLocation = CGPoint(x: 20, y: 4) // past the 12pt distance limit
        gesture.fakeSetState(.changed)
        view.handlePressGesture(gesture)
        clock.advance(ms: 1, frameMs: 1)

        let justAfterFailure = view.debugViewportLayer.transform.m11
        XCTAssertGreaterThan(justAfterFailure, midPressScale, "the press scale must start returning at once, before the finger ever lifts")
    }

    func testPressGestureNeverCancelsTouchesInTheViewAndRecognizesSimultaneously() {
        let registry = CompanionRegistry()
        let profile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        registry.register(profile)
        let view = CompanionSpriteView(companionID: profile.id, registry: registry)
        guard let gesture = view.debugPressGesture else {
            return XCTFail("the view must install its own press gesture")
        }
        XCTAssertFalse(gesture.cancelsTouchesInView, "a finger dragging off the pet must still be free to scroll a parent")
        let other = UIPanGestureRecognizer()
        XCTAssertTrue(
            gesture.delegate?.gestureRecognizer?(gesture, shouldRecognizeSimultaneouslyWith: other) ?? false,
            "must recognize simultaneously with a parent's own recognizer"
        )
    }

    func testPressScaleAppliesToTheContainerLayerNotTheViewsOwnTransform() {
        let registry = CompanionRegistry()
        let profile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        registry.register(profile)
        let clock = ManualClock()
        let view = CompanionSpriteView(companionID: profile.id, registry: registry, clock: clock)
        waitUntilReady(view)

        view.transform = CGAffineTransform(rotationAngle: .pi / 4)
        view.layer.transform = CATransform3DMakeRotation(.pi / 6, 0, 0, 1)
        let hostTransform = view.transform
        let hostLayerTransform = view.layer.transform

        let gesture = FakeLongPressGestureRecognizer(target: nil, action: nil)
        gesture.fakeLocation = CGPoint(x: 4, y: 4)
        gesture.fakeSetState(.began)
        view.handlePressGesture(gesture)
        clock.advance(ms: 60, frameMs: 1)

        XCTAssertNotEqual(view.debugViewportLayer.transform.m11, 1, "the container layer must carry the press scale")
        XCTAssertEqual(view.transform, hostTransform, "the view's own transform must be untouched by the press scale")
        XCTAssertTrue(
            CATransform3DEqualToTransform(view.layer.transform, hostLayerTransform),
            "the view's own backing layer transform must be untouched by the press scale"
        )
    }

    func testNonFiniteZeroAndNegativeSizesAllFallBackTo88AndReportOnce() {
        let registry = CompanionRegistry()
        let profile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        registry.register(profile)
        for badValue: CGFloat in [.infinity, -CGFloat.infinity, .nan, 0, -10] {
            var errors: [(Error, String)] = []
            let view = CompanionSpriteView(companionID: profile.id, registry: registry, size: badValue) { error, site in
                errors.append((error, site))
            }
            XCTAssertEqual(view.size, 88, "\(badValue) must fall back to 88")
            XCTAssertEqual(errors.count, 1, "\(badValue) must report exactly once at construction")
        }
    }

    func testARefusedSizeReportsOncePerDistinctValueNotOnEverySet() {
        let registry = CompanionRegistry()
        let profile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        registry.register(profile)
        var errors: [(Error, String)] = []
        let view = CompanionSpriteView(companionID: profile.id, registry: registry, size: .infinity) { error, site in
            errors.append((error, site))
        }
        XCTAssertEqual(errors.count, 1, "sanity: the initial bad size reports once")

        // Exactly what the SwiftUI wrapper's own applyState does on every
        // update: re-push the same computed (still bad) value.
        view.size = .infinity
        XCTAssertEqual(errors.count, 1, "the same refused value must not report a second time")

        view.size = -5
        XCTAssertEqual(errors.count, 2, "a distinct refused value must report again")

        view.size = .nan
        XCTAssertEqual(errors.count, 3, "a further distinct refused value must report again")
        view.size = .nan
        XCTAssertEqual(errors.count, 3, "NaN compared by bit pattern must equal itself, not report again")
    }

    // MARK: - The three other places implicit layer actions must be disabled

    func testLayoutSubviewsDisablesImplicitActionsOnTheContainerAndPoseLayers() {
        let registry = CompanionRegistry()
        let profile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        registry.register(profile)
        let view = CompanionSpriteView(companionID: profile.id, registry: registry)
        let window = makeWindow()
        window.addSubview(view)
        window.makeKeyAndVisible()
        view.layoutIfNeeded()
        waitUntilReady(view)

        view.size = 54
        view.layoutIfNeeded()

        XCTAssertNil(view.debugViewportLayer.animationKeys(), "a relayout must not implicitly animate the container layer")
        for pose in PupPose.allCases {
            XCTAssertNil(view.debugLayer(for: pose).animationKeys(), "a relayout must not implicitly animate pose layer \(pose)")
        }
    }

    func testHideAllLayersDisablesImplicitActions() {
        let registry = CompanionRegistry()
        let firstProfile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        let secondProfile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        registry.register(firstProfile)
        registry.register(secondProfile)
        let view = CompanionSpriteView(companionID: firstProfile.id, registry: registry)
        // Implicit actions are only observable once the layer is part of a
        // window's live tree - a detached layer never animates.
        let window = makeWindow()
        window.addSubview(view)
        window.makeKeyAndVisible()
        waitUntilReady(view)

        // A real companionID change calls hideAllLayers() synchronously,
        // right before the new sheets start loading.
        view.companionID = secondProfile.id
        for pose in PupPose.allCases {
            XCTAssertNil(view.debugLayer(for: pose).animationKeys(), "hideAllLayers must not implicitly animate pose layer \(pose)")
        }
    }

    func testAssignLayerContentsDisablesImplicitActions() {
        let registry = CompanionRegistry()
        let profile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        registry.register(profile)
        let view = CompanionSpriteView(companionID: profile.id, registry: registry)
        let window = makeWindow()
        window.addSubview(view)
        window.makeKeyAndVisible()
        waitUntilReady(view) // the loading -> ready transition runs assignLayerContents()
        for pose in PupPose.allCases {
            XCTAssertNil(view.debugLayer(for: pose).animationKeys(), "assignLayerContents must not implicitly animate pose layer \(pose)")
        }
    }

    func testAccessibilityActivateFiresRegardlessOfDistanceOrDuration() {
        let registry = CompanionRegistry()
        let profile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        registry.register(profile)
        let view = CompanionSpriteView(companionID: profile.id, registry: registry)
        waitUntilReady(view)
        var pressed = 0
        view.onPress = { pressed += 1 }

        XCTAssertTrue(view.accessibilityActivate())
        XCTAssertEqual(pressed, 1, "a VoiceOver activation is a real tap, not gated by the gesture's own distance/duration checks")
    }

    // MARK: - Layer geometry survives a view larger than size x size

    func testALayoutLargerThanSizeStillDrawsASizeBySizeCellAndKeepsTheProfileScale() {
        let idleGrid = CompanionProfile.IDLE_SHEET_GRID
        let runGrid = CompanionProfile.RUN_SHEET_GRID
        let idle = SpriteTestFixtures.makeSolidColorPNG(pixelWidth: 20 * idleGrid.cols, pixelHeight: 20 * idleGrid.rows)
        let run = SpriteTestFixtures.makeSolidColorPNG(pixelWidth: 20 * runGrid.cols, pixelHeight: 20 * runGrid.rows)
        let sit = SpriteTestFixtures.makeSolidColorPNG(pixelWidth: 20 * idleGrid.cols, pixelHeight: 20 * idleGrid.rows)
        let profile = CompanionProfile(
            id: "scaled-\(UUID().uuidString)",
            label: "scaled",
            runFps: 18,
            commitSpring: SpringConfig(duration: 560, dampingRatio: 0.86),
            trackSpring: SpringConfig(duration: 300, dampingRatio: 0.9),
            catchSpring: SpringConfig(duration: 260, dampingRatio: 0.9),
            hopHeight: -6,
            flightLift: 0,
            scale: 0.72,
            aroundRoute: false,
            sheets: CompanionSheets(idle: idle, run: run, sit: sit)
        )
        let registry = CompanionRegistry()
        registry.register(profile)
        let view = CompanionSpriteView(companionID: profile.id, registry: registry)
        view.frame = CGRect(x: 0, y: 0, width: 200, height: 120)
        let window = makeWindow()
        window.addSubview(view)
        window.makeKeyAndVisible()
        view.layoutIfNeeded()
        waitUntilReady(view)

        let idleLayer = view.debugLayer(for: .idle)
        XCTAssertEqual(idleLayer.bounds.size, CGSize(width: 88, height: 88))
        XCTAssertEqual(idleLayer.transform.m11, 0.72, accuracy: 0.001)

        // A second layout pass (a host re-laying-out the same view) must
        // not lose the size x size pin or the profile's own scale.
        view.setNeedsLayout()
        view.layoutIfNeeded()
        XCTAssertEqual(idleLayer.bounds.size, CGSize(width: 88, height: 88), "the cell must stay size x size after a second layout pass")
        XCTAssertEqual(idleLayer.transform.m11, 0.72, accuracy: 0.001, "the profile's scale transform must survive a second layout pass")
    }

    // MARK: - Content hugging / compression resistance

    func testContentHuggingAndCompressionResistanceAreRequiredOnBothAxes() {
        let registry = CompanionRegistry()
        let profile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        registry.register(profile)
        let view = CompanionSpriteView(companionID: profile.id, registry: registry)
        for axis: NSLayoutConstraint.Axis in [.horizontal, .vertical] {
            XCTAssertEqual(view.contentHuggingPriority(for: axis), .required)
            XCTAssertEqual(view.contentCompressionResistancePriority(for: axis), .required)
        }
    }

    // MARK: - onError set after init, empty/error state re-resolved on window entry

    func testOnErrorSetAfterInitStillReceivesTheEmptyStateReportOnceTheViewEntersAWindow() {
        let emptyRegistry = CompanionRegistry()
        let view = CompanionSpriteView(companionID: "still-nothing-registered", registry: emptyRegistry)
        var errors: [(Error, String)] = []
        view.onError = { error, site in errors.append((error, site)) }
        XCTAssertTrue(errors.isEmpty, "sanity: nothing has reported yet before the view has ever had a window")

        let window = makeWindow()
        window.addSubview(view)
        window.makeKeyAndVisible()

        XCTAssertEqual(errors.count, 1, "entering a window for the first time must re-resolve and report to the now-set onError")
        XCTAssertTrue(errors.first?.0 is CompanionSpriteError)
    }

    func testOnErrorSetAtInitDoesNotReportASecondTimeOnWindowEntry() {
        let emptyRegistry = CompanionRegistry()
        var errors: [(Error, String)] = []
        let view = CompanionSpriteView(companionID: "still-nothing-registered", registry: emptyRegistry) { error, site in
            errors.append((error, site))
        }
        XCTAssertEqual(errors.count, 1, "sanity: onError set at init already received the report")

        let window = makeWindow()
        window.addSubview(view)
        window.makeKeyAndVisible()

        XCTAssertEqual(errors.count, 1, "entering a window must not re-resolve and report a second time to a handler that already got it")
    }

    // MARK: - Frame rate hint follows needsFullFrameRate

    func testFrameRateHintSwitchesToMotionWhileAFadeIsLiveAndBackAtRest() {
        let registry = CompanionRegistry()
        let profile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        registry.register(profile)
        let view = CompanionSpriteView(companionID: profile.id, registry: registry)
        let window = makeWindow()
        window.addSubview(view)
        window.makeKeyAndVisible()
        waitUntilReady(view)
        guard let ownedClock = view.debugOwnedClock else {
            return XCTFail("the view must own its clock when none is injected")
        }

        view.pose = .run
        XCTAssertEqual(ownedClock.frameRateHint, .motion, "a pose change starts the cross-dissolve right away")

        let deadline = Date().addingTimeInterval(2)
        while ownedClock.frameRateHint == .motion && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        XCTAssertNotEqual(ownedClock.frameRateHint, .motion, "once the fade finishes and only the run loop remains, the hint must drop back to the sprite rate")
    }

    // MARK: - A stale decode for a companion no longer selected

    func testASheetThatFinishesDecodingForACompanionNoLongerSelectedIsNeverDrawn() {
        let registry = CompanionRegistry()
        let firstProfile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        let secondProfile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        registry.register(firstProfile)
        registry.register(secondProfile)
        guard let firstIdleURL = firstProfile.sheets?.idle else {
            return XCTFail("the fixture profile must have sheets")
        }

        let releaseFirstDecode = DispatchSemaphore(value: 0)
        SpriteSheetCache.shared.debugDecodeHook = { url, _ in
            if url == firstIdleURL {
                releaseFirstDecode.wait()
            }
        }
        defer { SpriteSheetCache.shared.debugDecodeHook = nil }

        let view = CompanionSpriteView(companionID: firstProfile.id, registry: registry)
        let window = makeWindow()
        window.addSubview(view)
        window.makeKeyAndVisible()

        // Switch away before the first companion's idle sheet can finish -
        // its decode is parked on the semaphore above until this test
        // releases it, well after the second companion is already ready.
        view.companionID = secondProfile.id
        waitUntilReady(view)

        let readyContents = view.debugLayer(for: .idle).contents as AnyObject?
        releaseFirstDecode.signal()

        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        XCTAssertEqual(view.visualState, .ready)
        XCTAssertTrue(view.debugLayer(for: .idle).contents as AnyObject? === readyContents, "a stale decode for a companion no longer selected must never replace the current one's contents")
    }

    // MARK: - Shared-engine mode

    func testSharedEngineModeRendersOnlyThroughRenderTickNotAFrameHandler() {
        let registry = CompanionRegistry()
        let profile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        registry.register(profile)
        let clock = ManualClock()
        let engine = MotionEngine(clock: clock)
        let view = CompanionSpriteView(companionID: profile.id, registry: registry, engine: engine, clock: clock)
        let window = makeWindow()
        window.addSubview(view)
        window.makeKeyAndVisible()
        waitUntilReady(view)

        view.pose = .run
        let rectAfterCommit = view.debugLayer(for: .run).contentsRect

        // Advancing the shared clock ticks the engine (the engine's own
        // init installed that handler, and shared mode never replaces it)
        // but must not by itself repaint this view - only `renderTick()` does.
        clock.advance(ms: 500, frameMs: 1000.0 / 60)
        let rectAfterAdvanceOnly = view.debugLayer(for: .run).contentsRect
        XCTAssertEqual(rectAfterAdvanceOnly, rectAfterCommit, "advancing the shared clock alone must not repaint this view's layers")

        view.renderTick()
        let rectAfterRenderTick = view.debugLayer(for: .run).contentsRect
        XCTAssertNotEqual(rectAfterRenderTick, rectAfterCommit, "renderTick must repaint the layer with whatever the shared engine already advanced the frame track to")
    }

    func testSharedEngineModeNeverSuspendsResumesOrSetsFrameRateHint() {
        let registry = CompanionRegistry()
        let profile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        registry.register(profile)
        let clock = DisplayLinkClock()
        let engine = MotionEngine(clock: clock)
        XCTAssertEqual(clock.frameRateHint, .motion, "setup: a fresh clock starts at its own default")

        let view = CompanionSpriteView(companionID: profile.id, registry: registry, engine: engine, clock: clock)
        XCTAssertEqual(clock.frameRateHint, .motion, "shared mode must never set the frame rate hint - the owner does")

        // Not asserted against nil/paused here: the mount greeting alone
        // can legitimately start the link running, in either mode. What
        // shared mode must never do is layer its own suspend/resume on top.
        let pausedBeforeWindow = clock.debugIsLinkPaused
        let window = makeWindow()
        window.addSubview(view)
        window.makeKeyAndVisible()
        XCTAssertEqual(clock.debugIsLinkPaused, pausedBeforeWindow, "entering a window in shared mode must not resume (or suspend) anything - the owner does")

        let pausedBeforeRemoval = clock.debugIsLinkPaused
        view.removeFromSuperview()
        XCTAssertEqual(clock.debugIsLinkPaused, pausedBeforeRemoval, "leaving a window in shared mode must not suspend (or resume) anything either")
    }
}
#endif
