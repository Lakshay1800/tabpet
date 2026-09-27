/// Result of a leash-follower step: `target` is nil while holding ground inside the leash.
public struct ChaseStep: Equatable, Hashable, Codable, Sendable {
    public let target: Double?
    public let facing: Facing

    public init(target: Double?, facing: Facing) {
        self.target = target
        self.facing = facing
    }
}

/// Pure geometry for the companion perch, ported from perch-geometry.ts.
/// Clamps follow JavaScript Math.min and Math.max, NaN and signed zero included.
public enum PerchGeometry {
    public static let PERCH_SIZE: Double = 54
    /// horizontal inset of the floating liquid-glass bar from screen edges - visually tuned against the real bar
    public static let BAR_MARGIN_H: Double = 16
    /// how far the companion intentionally trails a moving glass target, like chasing a tossed ball
    public static let CHASE_TRAIL: Double = 18
    /// deadband under which travelFacing holds facing; must stay well under
    /// CHASE_TRAIL or steady tracking would oscillate the mirror
    public static let FACING_DEADBAND: Double = 3
    /// hysteresis half-band around CHASE_TRAIL: start chasing only past
    /// TRAIL+SLACK, stand down only inside TRAIL-SLACK, so a gap hovering at the
    /// bare threshold doesn't flip run/idle on every pan sample
    public static let CHASE_SLACK: Double = 4
    /// Tab-tap traverse speed: a committed tap runs the full distance at this
    /// constant speed (not a fixed-duration spring) so a full-width tap reads as
    /// a run, not a teleport - tuned for ~0.9s on a 402pt/5-slot reference screen.
    public static let TRAVERSE_SPEED_PT_S: Double = 340
    /// floor: clamps a short adjacent-tab hop to the old commitSpring's ~430ms feel instead of reading sped-up
    public static let MIN_TRAVERSE_MS: Double = 400
    /// ceiling: a very wide screen still reads as a run, not an endless slog
    public static let MAX_TRAVERSE_MS: Double = 2200

    /// left edge for the perch frame, centered over a tab slot. Prefers measured
    /// item centers, falls back to an even split minus BAR_MARGIN_H.
    public static func tabCenterX(
        tab: Int,
        screenWidth: Double,
        slotCount: Int,
        slotCenters: [Double]? = nil
    ) -> Double {
        if let slotCenters, tab >= 0, tab < slotCenters.count {
            return slotCenters[tab] - PERCH_SIZE / 2
        }
        let evenSplit = BAR_MARGIN_H + (screenWidth - 2 * BAR_MARGIN_H) * ((Double(tab) + 0.5) / Double(slotCount))
        return evenSplit - PERCH_SIZE / 2
    }

    /// slot whose center is nearest a window-space x (a drag's release point);
    /// same center source as tabCenterX so measured and even-split bars agree
    public static func nearestSlot(
        x: Double,
        screenWidth: Double,
        slotCount: Int,
        slotCenters: [Double]? = nil
    ) -> Int {
        if slotCount <= 0 {
            return 0
        }
        var best = 0
        var bestDistance = Double.infinity
        for slot in 0..<slotCount {
            let center = tabCenterX(tab: slot, screenWidth: screenWidth, slotCount: slotCount, slotCenters: slotCenters) + PERCH_SIZE / 2
            let distance = abs(x - center)
            if distance < bestDistance {
                best = slot
                bestDistance = distance
            }
        }
        return best
    }

    /// translateX that centers the perch under a raw finger x, clamped to screen
    public static func glassTargetX(fingerX: Double, screenWidth: Double) -> Double {
        let target = fingerX - PERCH_SIZE / 2
        return JSMath.jsMin(JSMath.jsMax(target, 0), screenWidth - PERCH_SIZE)
    }

    /// A moving glass target leads the companion rather than carrying him directly
    /// underneath; trail flips with direction, clamped to the screen.
    public static func chaseTargetX(glassX: Double, direction: Facing, screenWidth: Double) -> Double {
        let target = glassX - Double(direction.rawValue) * CHASE_TRAIL
        return JSMath.jsMin(JSMath.jsMax(target, 0), screenWidth - PERCH_SIZE)
    }

    /// Leash-follower step for live drags. Within the leash the companion holds his
    /// ground (target nil) - chasing from a standstill would command retrograde
    /// motion (the "floating backward" bug). Beyond it he closes back to trailing
    /// distance, always toward the glass. `chasing` selects the hysteresis edge.
    public static func chaseStep(
        glassX: Double,
        currentX: Double,
        currentFacing: Facing,
        chasing: Bool
    ) -> ChaseStep {
        let gap = glassX - currentX
        let threshold = chasing ? CHASE_TRAIL - CHASE_SLACK : CHASE_TRAIL + CHASE_SLACK
        if abs(gap) <= threshold {
            return ChaseStep(target: nil, facing: currentFacing)
        }
        let facing: Facing = gap >= 0 ? .right : .left
        return ChaseStep(target: glassX - Double(facing.rawValue) * CHASE_TRAIL, facing: facing)
    }

    /// Face where the companion is actually traveling (sign of target - current), not
    /// the finger's own movement - else grabbing far from the companion turns him
    /// toward small finger wiggles (the "running backwards" bug).
    public static func travelFacing(targetX: Double, currentX: Double, currentFacing: Facing) -> Facing {
        let delta = targetX - currentX
        if abs(delta) <= FACING_DEADBAND {
            return currentFacing
        }
        return delta >= 0 ? .right : .left
    }

    /// a handoff under one glass width reads as a catch, not a run - snap straight to seat
    public static func shouldSnapToSeat(distancePt: Double) -> Bool {
        return distancePt < PERCH_SIZE
    }

    /// Linear run duration for a tab-tap traverse of the given distance;
    /// sign-independent. The floor/ceiling stretch with a profile speed override,
    /// else the floor would clamp a slow animal's short hop back to the shared
    /// pace and erase the slowness where it's most visible.
    public static func traverseDurationMs(
        distancePt: Double,
        speedPtS: Double = PerchGeometry.TRAVERSE_SPEED_PT_S
    ) -> Double {
        let stretch = TRAVERSE_SPEED_PT_S / speedPtS
        let raw = (abs(distancePt) / speedPtS) * 1000
        return JSMath.jsMin(MAX_TRAVERSE_MS * stretch, JSMath.jsMax(MIN_TRAVERSE_MS * stretch, raw))
    }

    /// Pose layers scale about the cell center, so a scaled sprite's drawn feet
    /// sit (PERCH_SIZE / 2 - footPad) * scale below it: the pad the perch seats
    /// on. A cell-measured footPad passes through unchanged at scale 1.
    public static func seatedFootPad(footPad: Double, scale: Double) -> Double {
        return PERCH_SIZE / 2 - (PERCH_SIZE / 2 - footPad) * scale
    }
}
