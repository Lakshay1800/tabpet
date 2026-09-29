import TabPetCore

/// A constant-speed follower of a target that can move while it runs. Each
/// frame steps `PerchHandoff.stepToward` with dt from its own previous frame;
/// the first frame has none and stands still. A retarget restarts nothing.
@MainActor
package final class FarApproachAnimation: MotionTargetedAnimation {
    package private(set) var toValue: Double
    package private(set) var current: Double
    package var hasBeenStepped = false
    /// True on purpose: the track's start short circuit (target already equal
    /// to the value) must not end a follower whose target can still move.
    package let isHigherOrder = true
    package var cancelled = false

    private let speedPtS: Double
    private var lastFrameMs: Double?

    package init(toValue: Double, speedPtS: Double) {
        self.toValue = toValue
        self.speedPtS = speedPtS
        self.current = toValue
    }

    /// A non-finite target is ignored, so the follower never chases NaN.
    package func retarget(_ target: Double) {
        guard target.isFinite else { return }
        toValue = target
    }

    package func onStart(value: Double, now: Double, previous: ReplacedAnimation) {
        current = value
        lastFrameMs = nil
    }

    package func onFrame(now: Double) -> Bool {
        let dtMs = lastFrameMs.map { now - $0 } ?? 0
        lastFrameMs = now
        let result = PerchHandoff.stepToward(current: current, target: toValue, speedPtS: speedPtS, dtMs: dtMs)
        current = result.x
        return result.arrived
    }
}
