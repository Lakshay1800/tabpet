import XCTest

@testable import TabPetMotion

/// A conforming type shaped the way a real display-link clock adapter
/// (a later, UIKit-facing target outside this one) will be: a `@MainActor
/// final class` implementing `MotionClock` end to end. Compiling this under
/// StrictConcurrency with no warning is the proof that MotionClock,
/// MotionCancellable and the rest of the actor-isolated surface really are
/// usable from a plain main-actor type, not just from ManualClock itself.
@MainActor
private final class FakeDisplayLinkClock: MotionClock {
    private final class Handle: MotionCancellable {
        func cancel() {}
    }

    var now: Double = 0
    var frameHandler: (@MainActor (Double) -> Void)?
    private(set) var wantsFrames = false

    func setWantsFrames(_ wantsFrames: Bool) {
        self.wantsFrames = wantsFrames
    }

    func after(milliseconds: Double, _ action: @escaping @MainActor () -> Void) -> MotionCancellable {
        Handle()
    }
}

@MainActor
final class MainActorClockTests: XCTestCase {
    func testAMainActorTypeCanConformToMotionClockEndToEnd() {
        let clock = FakeDisplayLinkClock()
        let engine = MotionEngine(clock: clock)
        let track = engine.makeTrack(label: "x")

        engine.start(track, TimingAnimation(toValue: 10, config: TimingConfig(duration: 1, easing: { Easing.linear($0) })))
        XCTAssertTrue(clock.wantsFrames)

        clock.now = 5
        clock.frameHandler?(clock.now)
        XCTAssertFalse(clock.wantsFrames, "the engine told the clock to stop once the track finished")
    }
}
