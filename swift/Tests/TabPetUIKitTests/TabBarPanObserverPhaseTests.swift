#if canImport(UIKit)
import UIKit
import XCTest

@testable import TabPetUIKit

// Test double: a real UIPanGestureRecognizer never reaches most states
// outside a live touch sequence, and setting `.state` directly on one that
// isn't attached to a recognized touch is not what `handlePan` reads back -
// every state read stays `.possible`. Overriding `state` and `location` to
// return stored fakes lets the tests drive every phase deterministically.
private final class FakePanGestureRecognizer: UIPanGestureRecognizer {
    var fakeLocation: CGPoint = .zero
    private var fakeState: UIGestureRecognizer.State = .possible

    override var state: UIGestureRecognizer.State {
        get { fakeState }
        set { } // real transitions require an attached, recognized touch; ignored here
    }

    override func location(in view: UIView?) -> CGPoint {
        fakeLocation
    }

    func setFakeState(_ newState: UIGestureRecognizer.State) {
        fakeState = newState
    }
}

@MainActor
final class TabBarPanObserverPhaseTests: XCTestCase {
    // handlePan's throttle carries lastSentX on the observer instance, so
    // throttle assertions drive one observer across a sequence of calls.
    private func driveSequence(_ events: [(x: Double, state: UIGestureRecognizer.State)]) -> [PanEvent] {
        let gesture = FakePanGestureRecognizer(target: nil, action: nil)
        var captured: [PanEvent] = []
        let observer = TabBarPanObserver { captured.append($0) }
        for event in events {
            gesture.fakeLocation = CGPoint(x: event.x, y: 0)
            gesture.setFakeState(event.state)
            observer.handlePan(gesture)
        }
        return captured
    }

    func testBeganEmits() {
        let events = driveSequence([(x: 10, state: .began)])
        XCTAssertEqual(events.map(\.phase), [.began])
        XCTAssertEqual(events.map(\.x), [10])
    }

    func testMovedAfterOnePointExactlyEmits() {
        let events = driveSequence([
            (x: 10, state: .began),
            (x: 11, state: .changed),
        ])
        XCTAssertEqual(events.map(\.phase), [.began, .moved])
        XCTAssertEqual(events.map(\.x), [10, 11])
    }

    func testMovedUnderOnePointIsThrottled() {
        let events = driveSequence([
            (x: 10, state: .began),
            (x: 10.5, state: .changed),
        ])
        XCTAssertEqual(events.map(\.phase), [.began], "sub-point move is throttled")
        XCTAssertEqual(events.map(\.x), [10])
    }

    func testMovedAfterFurtherMoveTotalingOnePointFromLastSentEmits() {
        let events = driveSequence([
            (x: 10, state: .began),      // sent, lastSentX = 10
            (x: 10.5, state: .changed),  // 0.5 from last sent - throttled, lastSentX unchanged
            (x: 11, state: .changed),    // 1.0 from last sent (10) - emits
        ])
        XCTAssertEqual(events.map(\.phase), [.began, .moved])
        XCTAssertEqual(events.map(\.x), [10, 11])
    }

    func testEndedEmits() {
        let events = driveSequence([(x: 5, state: .ended)])
        XCTAssertEqual(events.map(\.phase), [.ended])
        XCTAssertEqual(events.map(\.x), [5])
    }

    func testCancelledAndFailedBothEmitCancelled() {
        let cancelled = driveSequence([(x: 5, state: .cancelled)])
        XCTAssertEqual(cancelled.map(\.phase), [.cancelled])
        XCTAssertEqual(cancelled.map(\.x), [5])

        let failed = driveSequence([(x: 7, state: .failed)])
        XCTAssertEqual(failed.map(\.phase), [.cancelled])
        XCTAssertEqual(failed.map(\.x), [7])
    }

    func testPossibleEmitsNothing() {
        XCTAssertTrue(driveSequence([(x: 5, state: .possible)]).isEmpty)
    }
}
#endif
