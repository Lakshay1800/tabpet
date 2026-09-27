import XCTest

@testable import TabPetCore

/// Mirrors companion-state.test.ts plus the Set-iteration-order semantics of
/// companion-state.ts itself. Every order asserted below was captured by
/// running the real companion-state.ts against the same sequence (tsx,
/// packages/tabpet/src/companion-state.ts) - not derived from reading it.
/// Constructs its own CompanionState instance per test rather than sharing
/// .shared, so tests never leak state into each other.
@MainActor
final class CompanionStateTests: XCTestCase {
    func testBusyClaimsRefCountAndEdgeBroadcast() {
        let state = CompanionState()
        var seen: [Bool] = []
        let unsubscribe = state.subscribeCompanionBusy { busy in seen.append(busy) }

        XCTAssertFalse(state.isCompanionBusy(), "baseline: no claims, not busy")
        let release1 = state.beginCompanionBusy()
        let release2 = state.beginCompanionBusy()
        XCTAssertTrue(state.isCompanionBusy(), "busy while any claim is held")
        release1()
        XCTAssertTrue(state.isCompanionBusy(), "still busy with one claim outstanding")
        release2()
        XCTAssertFalse(state.isCompanionBusy(), "idle again after the last release")
        release2() // idempotent: a finally-block re-release must not underflow
        XCTAssertFalse(state.isCompanionBusy(), "double release does not underflow the count")
        let release3 = state.beginCompanionBusy()
        XCTAssertTrue(state.isCompanionBusy(), "a fresh claim after a double release still works")
        release3()

        // only idle<->busy EDGES broadcast: the overlapping claim and first release are silent
        XCTAssertEqual(
            seen,
            [true, false, true, false],
            "edge-only broadcasts expected [true, false, true, false] got \(seen)"
        )

        unsubscribe()
        let release4 = state.beginCompanionBusy()
        release4()
        XCTAssertEqual(seen.count, 4, "unsubscribed listener observes nothing further")
        state.resetForTest()
        XCTAssertFalse(state.isCompanionBusy(), "test reset clears outstanding claims")
    }

    func testBusyClaimNoOpsWhenNothingSubscribed() {
        let state = CompanionState()
        let release = state.beginCompanionBusy()
        XCTAssertTrue(state.isCompanionBusy(), "busy state tracks with zero subscribers")
        release()
        XCTAssertFalse(state.isCompanionBusy(), "release works with zero subscribers")
    }

    /// TS-verified order: L1:true, L2:true, L3:true, L1:false, L2:false, L3:false.
    func testPlainClaimAndReleaseThreeListeners() {
        let state = CompanionState()
        var order: [String] = []
        _ = state.subscribeCompanionBusy { busy in order.append("L1:\(busy)") }
        _ = state.subscribeCompanionBusy { busy in order.append("L2:\(busy)") }
        _ = state.subscribeCompanionBusy { busy in order.append("L3:\(busy)") }

        let release = state.beginCompanionBusy()
        release()

        XCTAssertEqual(order, ["L1:true", "L2:true", "L3:true", "L1:false", "L2:false", "L3:false"])
    }

    /// TS-verified order: true broadcast is L1:true, L2:true - L3 is skipped,
    /// unsubscribed by L1 before its own turn arrived. Release then only visits
    /// the two that remain.
    func testListenerUnsubscribingAnotherBeforeItsTurnSkipsIt() {
        let state = CompanionState()
        var order: [String] = []
        var unsubscribeL3: (@MainActor @Sendable () -> Void)?
        _ = state.subscribeCompanionBusy { busy in
            order.append("L1:\(busy)")
            unsubscribeL3?()
        }
        _ = state.subscribeCompanionBusy { busy in order.append("L2:\(busy)") }
        unsubscribeL3 = state.subscribeCompanionBusy { busy in order.append("L3:\(busy)") }

        let release = state.beginCompanionBusy()
        release()

        XCTAssertEqual(order, ["L1:true", "L2:true", "L1:false", "L2:false"])
    }

    /// TS-verified order: a listener subscribed during the broadcast (L4) is
    /// visited once the walk reaches it, same edge, same call - both true and false.
    func testListenerSubscribingDuringTheBroadcastVisitsTheNewOne() {
        let state = CompanionState()
        var order: [String] = []
        _ = state.subscribeCompanionBusy { busy in
            order.append("L1:\(busy)")
            if busy {
                _ = state.subscribeCompanionBusy { busy2 in order.append("L4:\(busy2)") }
            }
        }
        _ = state.subscribeCompanionBusy { busy in order.append("L2:\(busy)") }
        _ = state.subscribeCompanionBusy { busy in order.append("L3:\(busy)") }

        let release = state.beginCompanionBusy()
        release()

        XCTAssertEqual(
            order,
            ["L1:true", "L2:true", "L3:true", "L4:true", "L1:false", "L2:false", "L3:false", "L4:false"]
        )
    }

    /// TS-verified order: L2 fires once for the edge it unsubscribed itself
    /// during, then is simply absent from every later broadcast.
    func testListenerUnsubscribingItselfIsNotCalledAgain() {
        let state = CompanionState()
        var order: [String] = []
        _ = state.subscribeCompanionBusy { busy in order.append("L1:\(busy)") }
        var unsubscribeL2: (@MainActor @Sendable () -> Void)?
        unsubscribeL2 = state.subscribeCompanionBusy { busy in
            order.append("L2:\(busy)")
            unsubscribeL2?()
        }
        _ = state.subscribeCompanionBusy { busy in order.append("L3:\(busy)") }

        let release1 = state.beginCompanionBusy()
        release1()
        let release2 = state.beginCompanionBusy()
        release2()

        XCTAssertEqual(order, [
            "L1:true", "L2:true", "L3:true",
            "L1:false", "L3:false",
            "L1:true", "L3:true",
            "L1:false", "L3:false",
        ])
    }

    /// TS-verified order: releasing the only claim inside a false callback
    /// begins a brand new claim, which broadcasts true to everyone - including
    /// the listener still mid-callback - before the outer false broadcast
    /// resumes to whoever is left.
    func testReentrantClaimInsideAFalseCallbackStartsANestedBroadcastAtOnce() {
        let state = CompanionState()
        var order: [String] = []
        var nestedRelease: (@MainActor @Sendable () -> Void)?
        _ = state.subscribeCompanionBusy { busy in
            order.append("L1:\(busy)")
            if !busy {
                nestedRelease = state.beginCompanionBusy()
            }
        }
        _ = state.subscribeCompanionBusy { busy in order.append("L2:\(busy)") }
        _ = state.subscribeCompanionBusy { busy in order.append("L3:\(busy)") }

        let release = state.beginCompanionBusy()
        release()

        XCTAssertEqual(order, [
            "L1:true", "L2:true", "L3:true",
            "L1:false", "L1:true", "L2:true", "L3:true", "L2:false", "L3:false",
        ])
        nestedRelease?()
    }

    /// TS-verified: `beginCompanionBusy`'s release closure is only constructed
    /// AFTER `notify(true)` returns, so a listener cannot call its own claim's
    /// not-yet-returned handle synchronously inside the true callback that
    /// creation triggered - the call is unavailable, a no-op, and the
    /// broadcast completes normally with the claim still held.
    func testReleasingAClaimsOwnHandleInsideItsTriggeringTrueCallbackIsANoOp() {
        let state = CompanionState()
        var order: [String] = []
        var outerRelease: (@MainActor @Sendable () -> Void)?
        _ = state.subscribeCompanionBusy { busy in
            order.append("L1:\(busy)")
            if busy {
                outerRelease?()
            }
        }
        _ = state.subscribeCompanionBusy { busy in order.append("L2:\(busy)") }
        _ = state.subscribeCompanionBusy { busy in order.append("L3:\(busy)") }

        outerRelease = state.beginCompanionBusy()

        XCTAssertEqual(order, ["L1:true", "L2:true", "L3:true"])
        XCTAssertTrue(state.isCompanionBusy(), "the claim is still held - the release call inside L1 was a no-op")
        outerRelease?()
    }

    /// The id counter must survive resetForTest(): if it didn't, a listener
    /// registered after the reset could reuse the id of one registered before
    /// it, and a stale pre-reset handle would remove the wrong listener.
    func testResetForTestDoesNotResetTheIdCounter() {
        let state = CompanionState()
        let unsubscribeOld = state.subscribeCompanionBusy { _ in }
        unsubscribeOld()
        state.resetForTest()

        var newSeen: [Bool] = []
        _ = state.subscribeCompanionBusy { busy in newSeen.append(busy) }
        unsubscribeOld() // stale handle from before the reset

        let release = state.beginCompanionBusy()
        release()

        XCTAssertEqual(newSeen, [true, false], "the stale pre-reset handle did not remove the post-reset listener")
    }
}
