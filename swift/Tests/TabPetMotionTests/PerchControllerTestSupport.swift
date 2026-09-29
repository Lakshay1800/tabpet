import TabPetCore
import XCTest

@testable import TabPetMotion

/// Bundles a fresh `ManualClock`/`MotionEngine`/`PerchHandoffStore`/
/// `CompanionState` and controllable `mounted`/`measure`/`reduceMotion`
/// closures, so each test only states what it changes from the defaults.
@MainActor
final class Harness {
    let clock = ManualClock()
    let engine: MotionEngine
    let handoff = PerchHandoffStore()
    let busy = CompanionState()

    var mountedFlag = true
    var reduceMotionFlag = false
    var measureResult: BarLayout?

    private(set) var renderStates: [PerchRenderState] = []
    private(set) var errors: [(MotionError, String)] = []
    var renderStateCount: Int { renderStates.count }

    init() {
        engine = MotionEngine(clock: clock)
    }

    func makeController(
        profile: CompanionProfile,
        anchor: PerchAnchor,
        screenWidth: Double = 402,
        transientSlot: Bool = false,
        bottomExtra: Double = 0
    ) -> PerchController {
        let controller = PerchController(
            profile: profile,
            anchor: anchor,
            transientSlot: transientSlot,
            bottomExtra: bottomExtra,
            screenWidth: screenWidth,
            mounted: { [weak self] in self?.mountedFlag ?? false },
            measure: { [weak self] in self?.measureResult },
            reduceMotion: { [weak self] in self?.reduceMotionFlag ?? false },
            clock: clock,
            engine: engine,
            handoff: handoff,
            busy: busy,
            onError: { [weak self] error, site in self?.errors.append((error, site)) }
        )
        controller.onRenderState = { [weak self] state in self?.renderStates.append(state) }
        // The harness stands in for an always-mounted host: real callers
        // activate this on window entry.
        controller.activateBusyTracking()
        return controller
    }
}

@MainActor
func makeProfile(
    hopHeight: Double = -6,
    flightLift: Double = 0,
    runSpeed: Double? = nil,
    scale: Double = 1,
    footPad: Double? = nil,
    seatLift: Double? = nil,
    aroundRoute: Bool = false,
    commitSpring: TabPetCore.SpringConfig = TabPetCore.SpringConfig(duration: 560, dampingRatio: 0.86),
    trackSpring: TabPetCore.SpringConfig = TabPetCore.SpringConfig(duration: 300, dampingRatio: 0.9),
    catchSpring: TabPetCore.SpringConfig = TabPetCore.SpringConfig(duration: 260, dampingRatio: 0.9)
) -> CompanionProfile {
    CompanionProfile(
        id: "testAnimal",
        label: "test animal",
        runFps: 12,
        commitSpring: commitSpring,
        trackSpring: trackSpring,
        catchSpring: catchSpring,
        hopHeight: hopHeight,
        flightLift: flightLift,
        scale: scale,
        aroundRoute: aroundRoute,
        footPad: footPad,
        seatLift: seatLift,
        runSpeed: runSpeed
    )
}
