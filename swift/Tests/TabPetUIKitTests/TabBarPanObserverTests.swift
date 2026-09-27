#if canImport(UIKit)
import UIKit
import XCTest

import TabPetUIKit

@MainActor
final class TabBarPanObserverTests: XCTestCase {
    private func makeBar() -> UITabBar {
        let bar = UITabBar()
        bar.frame = CGRect(x: 0, y: 700, width: 390, height: 90)
        return bar
    }

    // A fresh UITabBar on iOS 26.5 already carries a recognizer of its own,
    // so counting "the recognizers" isn't enough - find the one this
    // observer actually owns by its delegate.
    private func observerRecognizer(on bar: UITabBar, observer: TabBarPanObserver) -> UIPanGestureRecognizer? {
        bar.gestureRecognizers?.compactMap { $0 as? UIPanGestureRecognizer }
            .first { $0.delegate === observer }
    }

    func testAttachAddsOneRecognizerAndIgnoresSecondAttach() {
        let bar = makeBar()
        let before = bar.gestureRecognizers?.count ?? 0
        let observer = TabBarPanObserver { _ in }

        observer.attach(to: bar)
        XCTAssertEqual((bar.gestureRecognizers?.count ?? 0) - before, 1)
        XCTAssertTrue(observer.isAttached)
        XCTAssertNotNil(observerRecognizer(on: bar, observer: observer))

        let afterFirstAttach = bar.gestureRecognizers?.count ?? 0
        observer.attach(to: bar)
        XCTAssertEqual(bar.gestureRecognizers?.count ?? 0, afterFirstAttach, "a second attach adds nothing")
    }

    func testSecondAttachToSameBarIsIgnoredNotReAdded() {
        let bar = makeBar()
        let observer = TabBarPanObserver { _ in }

        observer.attach(to: bar)
        guard let firstRecognizer = observerRecognizer(on: bar, observer: observer) else {
            return XCTFail("expected the observer's own recognizer after the first attach")
        }
        let countAfterFirstAttach = bar.gestureRecognizers?.count ?? 0

        observer.attach(to: bar)
        guard let secondRecognizer = observerRecognizer(on: bar, observer: observer) else {
            return XCTFail("expected the observer's own recognizer after the second attach")
        }
        XCTAssertTrue(firstRecognizer === secondRecognizer, "a second attach on the same bar keeps the same recognizer, not a detach and re-add")
        XCTAssertEqual(bar.gestureRecognizers?.count ?? 0, countAfterFirstAttach, "a second attach on the same bar must not change the recognizer count")
    }

    func testDetachRemovesTheRecognizer() {
        let bar = makeBar()
        let before = bar.gestureRecognizers?.count ?? 0
        let observer = TabBarPanObserver { _ in }
        observer.attach(to: bar)
        let afterAttach = bar.gestureRecognizers?.count ?? 0

        observer.detach()
        XCTAssertEqual((bar.gestureRecognizers?.count ?? 0), afterAttach - 1)
        XCTAssertEqual(bar.gestureRecognizers?.count ?? 0, before)
        XCTAssertFalse(observer.isAttached)
    }

    func testScrubModeSetsCancelsTouchesInViewBeforeAndAfterAttach() {
        let exclusiveBar = makeBar()
        let exclusiveObserver = TabBarPanObserver(scrubMode: .exclusive) { _ in }
        exclusiveObserver.attach(to: exclusiveBar)
        guard let exclusiveRecognizer = observerRecognizer(on: exclusiveBar, observer: exclusiveObserver) else {
            return XCTFail("expected the observer's own recognizer")
        }
        XCTAssertEqual(exclusiveRecognizer.cancelsTouchesInView, true)
        XCTAssertEqual(exclusiveRecognizer.delaysTouchesBegan, false)
        XCTAssertEqual(exclusiveRecognizer.delaysTouchesEnded, false)

        let nativeBar = makeBar()
        let nativeObserver = TabBarPanObserver(scrubMode: .native) { _ in }
        nativeObserver.attach(to: nativeBar)
        guard let nativeRecognizer = observerRecognizer(on: nativeBar, observer: nativeObserver) else {
            return XCTFail("expected the observer's own recognizer")
        }
        XCTAssertEqual(nativeRecognizer.cancelsTouchesInView, false)
        XCTAssertEqual(nativeRecognizer.delaysTouchesBegan, false)
        XCTAssertEqual(nativeRecognizer.delaysTouchesEnded, false)

        // live change after attach, both directions, read from the same recognizer
        nativeObserver.scrubMode = .exclusive
        XCTAssertEqual(nativeRecognizer.cancelsTouchesInView, true)
        nativeObserver.scrubMode = .native
        XCTAssertEqual(nativeRecognizer.cancelsTouchesInView, false)
    }

    func testAttachToADifferentBarMovesTheRecognizer() {
        let firstBar = makeBar()
        let secondBar = makeBar()
        let observer = TabBarPanObserver { _ in }

        observer.attach(to: firstBar)
        guard let firstRecognizer = observerRecognizer(on: firstBar, observer: observer) else {
            return XCTFail("expected the observer's own recognizer on the first bar")
        }

        observer.attach(to: secondBar)
        XCTAssertFalse(firstBar.gestureRecognizers?.contains(firstRecognizer) ?? false, "detaches the stale recognizer from the old bar")
        XCTAssertNotNil(observerRecognizer(on: secondBar, observer: observer))
        XCTAssertTrue(observer.isAttached)
    }

    func testIsAttachedTurnsFalseWhenTheBarIsDeallocated() {
        let observer = TabBarPanObserver { _ in }
        weak var weakBar: UITabBar?
        autoreleasepool {
            let bar = makeBar()
            weakBar = bar
            observer.attach(to: bar)
            XCTAssertTrue(observer.isAttached)
        }
        XCTAssertNil(weakBar, "the bar should have been deallocated")
        XCTAssertFalse(observer.isAttached)
    }

    private func attachedTapRecognizer(on view: UIView) -> UIGestureRecognizer {
        let tap = UITapGestureRecognizer()
        view.addGestureRecognizer(tap)
        return tap
    }

    func testShouldBeRequiredToFailByFourCombinations() {
        let bar = makeBar()
        let unrelated = UIView()
        let barRecognizer = attachedTapRecognizer(on: bar)
        let unrelatedRecognizer = attachedTapRecognizer(on: unrelated)
        let placeholder = UITapGestureRecognizer()

        let exclusiveObserver = TabBarPanObserver(scrubMode: .exclusive) { _ in }
        exclusiveObserver.attach(to: bar)
        XCTAssertEqual(exclusiveObserver.gestureRecognizer(placeholder, shouldBeRequiredToFailBy: barRecognizer), true, "exclusive mode, a recognizer belonging to the bar")
        XCTAssertEqual(exclusiveObserver.gestureRecognizer(placeholder, shouldBeRequiredToFailBy: unrelatedRecognizer), false, "exclusive mode, a recognizer on an unrelated view")
        exclusiveObserver.detach()

        let nativeObserver = TabBarPanObserver(scrubMode: .native) { _ in }
        nativeObserver.attach(to: bar)
        XCTAssertEqual(nativeObserver.gestureRecognizer(placeholder, shouldBeRequiredToFailBy: barRecognizer), false, "native mode, a recognizer belonging to the bar")
        XCTAssertEqual(nativeObserver.gestureRecognizer(placeholder, shouldBeRequiredToFailBy: unrelatedRecognizer), false, "native mode, a recognizer on an unrelated view")
        nativeObserver.detach()
    }

    func testDelegateMethodsAcrossViewsAndModes() {
        let bar = makeBar()
        let superview = UIView()
        superview.addSubview(bar)
        let unrelated = UIView()

        let barOwnRecognizer = attachedTapRecognizer(on: bar)
        let superviewRecognizer = attachedTapRecognizer(on: superview)
        let unrelatedRecognizer = attachedTapRecognizer(on: unrelated)
        let placeholder = UITapGestureRecognizer()

        for mode in [BarScrubMode.native, BarScrubMode.exclusive] {
            let observer = TabBarPanObserver(scrubMode: mode) { _ in }
            observer.attach(to: bar)
            let exclusive = mode == .exclusive

            XCTAssertEqual(
                observer.gestureRecognizer(placeholder, shouldRecognizeSimultaneouslyWith: barOwnRecognizer),
                !exclusive
            )
            XCTAssertEqual(
                observer.gestureRecognizer(placeholder, shouldRecognizeSimultaneouslyWith: superviewRecognizer),
                !exclusive
            )
            XCTAssertEqual(
                observer.gestureRecognizer(placeholder, shouldRecognizeSimultaneouslyWith: unrelatedRecognizer),
                true
            )

            XCTAssertEqual(
                observer.gestureRecognizer(placeholder, shouldBeRequiredToFailBy: barOwnRecognizer),
                exclusive
            )
            XCTAssertEqual(
                observer.gestureRecognizer(placeholder, shouldBeRequiredToFailBy: superviewRecognizer),
                exclusive
            )
            XCTAssertEqual(
                observer.gestureRecognizer(placeholder, shouldBeRequiredToFailBy: unrelatedRecognizer),
                false
            )

            observer.detach()
        }
    }
}
#endif
