/// Companion sprite pose, ported from pose-dissolve.ts's `PupPose` union.
public enum PupPose: String, Sendable, Codable, Hashable, CaseIterable {
    case idle
    case run
    case sit
}

/// One pose layer's opacity state, ported from pose-dissolve.ts's (unexported) `PoseOpacityKind`.
public enum PoseOpacityKind: Equatable, Hashable, Codable, Sendable {
    case hidden
    case opaque
    case fadeOut(durationMs: Double)
}

/// One pose layer's plan, ported from pose-dissolve.ts's (unexported) `PoseLayerAssignment`.
public struct PoseLayerAssignment: Equatable, Hashable, Codable, Sendable {
    public let opacity: PoseOpacityKind
    public let z: Int

    public init(opacity: PoseOpacityKind, z: Int) {
        self.opacity = opacity
        self.z = z
    }
}

/// Ported from pose-dissolve.ts's `PoseDissolvePlan` (`Record<PupPose, PoseLayerAssignment>`).
/// A struct keeps `plan.idle`/`plan.run`/`plan.sit` field access like the TypeScript;
/// the subscript keeps `plan[pose]` access for code that loops over `PUP_POSES`.
public struct PoseDissolvePlan: Equatable, Hashable, Codable, Sendable {
    public var idle: PoseLayerAssignment
    public var run: PoseLayerAssignment
    public var sit: PoseLayerAssignment

    public init(idle: PoseLayerAssignment, run: PoseLayerAssignment, sit: PoseLayerAssignment) {
        self.idle = idle
        self.run = run
        self.sit = sit
    }

    public subscript(pose: PupPose) -> PoseLayerAssignment {
        get {
            switch pose {
            case .idle: return idle
            case .run: return run
            case .sit: return sit
            }
        }
        set {
            switch pose {
            case .idle: idle = newValue
            case .run: run = newValue
            case .sit: sit = newValue
            }
        }
    }
}

/// Pure pose-handoff planner for the companion sprite, ported from pose-dissolve.ts.
/// Ghost dissolve: incoming goes fully opaque underneath, outgoing fades on top over
/// POSE_FADE_MS, and the unused third layer hides first so a rapid idle -> run -> sit
/// can't stack three sheets.
public enum PoseDissolve {
    public static let PUP_POSES: [PupPose] = [.idle, .run, .sit]
    public static let POSE_FADE_MS: Double = 110

    /// Hard cut for reduce-motion and same-pose re-runs: one opaque layer, the
    /// other two hidden - else a mid-fade leftover can stack as a third sheet.
    private static func hardCut(_ next: PupPose) -> PoseDissolvePlan {
        PoseDissolvePlan(
            idle: PoseLayerAssignment(opacity: next == .idle ? .opaque : .hidden, z: next == .idle ? 1 : 0),
            run: PoseLayerAssignment(opacity: next == .run ? .opaque : .hidden, z: next == .run ? 1 : 0),
            sit: PoseLayerAssignment(opacity: next == .sit ? .opaque : .hidden, z: next == .sit ? 1 : 0)
        )
    }

    private static func assignmentFor(_ pose: PupPose, previous: PupPose, next: PupPose) -> PoseLayerAssignment {
        if pose == next {
            return PoseLayerAssignment(opacity: .opaque, z: 1)
        }
        if pose == previous {
            return PoseLayerAssignment(opacity: .fadeOut(durationMs: POSE_FADE_MS), z: 2)
        }
        return PoseLayerAssignment(opacity: .hidden, z: 0)
    }

    public static func planPoseDissolve(previous: PupPose, next: PupPose, reduceMotion: Bool = false) -> PoseDissolvePlan {
        if reduceMotion || previous == next {
            return hardCut(next)
        }
        return PoseDissolvePlan(
            idle: assignmentFor(.idle, previous: previous, next: next),
            run: assignmentFor(.run, previous: previous, next: next),
            sit: assignmentFor(.sit, previous: previous, next: next)
        )
    }

    /// Hidden first, then incoming opaque, then outgoing fade - never pop the
    /// incoming sheet while a leftover third layer is still non-zero.
    public static func poseDissolveApplyOrder(plan: PoseDissolvePlan) -> [PupPose] {
        var hidden: [PupPose] = []
        var opaque: [PupPose] = []
        var fadeOut: [PupPose] = []
        for pose in PUP_POSES {
            switch plan[pose].opacity {
            case .hidden: hidden.append(pose)
            case .opaque: opaque.append(pose)
            case .fadeOut: fadeOut.append(pose)
            }
        }
        return hidden + opaque + fadeOut
    }

    /// sit->idle holds the seam (idle[0] == sit last). Every other incoming pose
    /// resets to frame 0. Same-pose leaves frames alone (greeting / busy loop).
    public static func shouldResetIncomingFrame(previous: PupPose, next: PupPose) -> Bool {
        if previous == next {
            return false
        }
        return !(next == .idle && previous == .sit)
    }

    /// Only snap idle to rest while still seated at idle - snapping to idle[0]
    /// while it's the top dissolve layer is the wrong-sheet flash.
    public static func shouldSnapBusyIdleFrameToRest(currentPose: PupPose) -> Bool {
        currentPose == .idle
    }
}
