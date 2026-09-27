import Foundation

/// Plain data for one leg-by-leg trip around the pill's outline: the near cap,
/// a half-ellipse over one end, the flat hang along the underside, the other
/// half-ellipse, the far cap. `arcCum`/`legs` let `aroundPose` walk it at one
/// constant speed. Ported from perch-around.ts's AroundPath.
/// a hand-built or decoded path can carry non-finite fields (a NaN input propagates
/// through the math below), so a value may be unequal to itself and the default
/// JSON encoder rejects it.
public struct AroundPath: Equatable, Hashable, Codable, Sendable {
    public let exitSide: Facing
    public let enterSide: Facing
    public let facing: Facing
    public let spin: Facing
    public let pivot: Double
    public let seatFeetY: Double
    public let underY: Double
    public let cxExit: Double
    public let cxEnter: Double
    public let cy: Double
    public let a: Double
    public let b: Double
    public let feetX0: Double
    public let targetFeetX: Double
    public let arcCum: [Double]
    public let arcLen: Double
    public let legs: [Double]
    public let totalLen: Double
    public let totalMs: Double

    public init(
        exitSide: Facing,
        enterSide: Facing,
        facing: Facing,
        spin: Facing,
        pivot: Double,
        seatFeetY: Double,
        underY: Double,
        cxExit: Double,
        cxEnter: Double,
        cy: Double,
        a: Double,
        b: Double,
        feetX0: Double,
        targetFeetX: Double,
        arcCum: [Double],
        arcLen: Double,
        legs: [Double],
        totalLen: Double,
        totalMs: Double
    ) {
        self.exitSide = exitSide
        self.enterSide = enterSide
        self.facing = facing
        self.spin = spin
        self.pivot = pivot
        self.seatFeetY = seatFeetY
        self.underY = underY
        self.cxExit = cxExit
        self.cxEnter = cxEnter
        self.cy = cy
        self.a = a
        self.b = b
        self.feetX0 = feetX0
        self.targetFeetX = targetFeetX
        self.arcCum = arcCum
        self.arcLen = arcLen
        self.legs = legs
        self.totalLen = totalLen
        self.totalMs = totalMs
    }
}

/// Plain data for a mid-route interrupt resumed from wherever the companion
/// actually is: the outline segment back to the base path's near cap, then a
/// straight run to the new target. Ported from perch-around.ts's ResumedRoute.
/// fields can be NaN for a non-finite input, so a value may be unequal to itself
/// and the default JSON encoder rejects it.
public struct ResumedRoute: Equatable, Hashable, Codable, Sendable {
    public let base: AroundPath
    public let startS: Double
    public let endS: Double
    public let dir: Facing
    public let curveLen: Double
    public let tailFromFeetX: Double
    public let tailToFeetX: Double
    public let tailLen: Double
    public let totalLen: Double
    public let totalMs: Double
    public let facing: Facing
    public let endRotation: Double

    public init(
        base: AroundPath,
        startS: Double,
        endS: Double,
        dir: Facing,
        curveLen: Double,
        tailFromFeetX: Double,
        tailToFeetX: Double,
        tailLen: Double,
        totalLen: Double,
        totalMs: Double,
        facing: Facing,
        endRotation: Double
    ) {
        self.base = base
        self.startS = startS
        self.endS = endS
        self.dir = dir
        self.curveLen = curveLen
        self.tailFromFeetX = tailFromFeetX
        self.tailToFeetX = tailToFeetX
        self.tailLen = tailLen
        self.totalLen = totalLen
        self.totalMs = totalMs
        self.facing = facing
        self.endRotation = endRotation
    }
}

/// Pose along an around/resumed route: window-space feet position and the
/// rotation about `routePivot`. Ported from perch-around.ts's aroundPose and
/// resumedPose return shape (an inline object type on the TypeScript side).
public struct AroundPose: Equatable, Hashable, Codable, Sendable {
    public let x: Double
    public let seatY: Double
    /// degrees, not radians - UIKit transforms take radians
    public let rotation: Double

    public init(x: Double, seatY: Double, rotation: Double) {
        self.x = x
        self.seatY = seatY
        self.rotation = rotation
    }
}

/// Around route (tier 1): the scenic path for an end-to-end tab tap, ported
/// from perch-around.ts. Clamps follow JavaScript Math.min and Math.max, NaN
/// and signed zero included.
public enum PerchAround {
    /// bars with fewer slots than this never route around (2 tabs = an adjacent hop)
    public static let AROUND_MIN_SLOT_COUNT: Int = 3
    /// one constant speed for the whole route - straight legs and arcs alike
    public static let AROUND_SPEED_PT_S: Double = 300
    /// arc-length samples per half-ellipse; phi/psi step by pi/K between them
    private static let ARC_SAMPLES: Int = 32

    /// only a first-slot <-> last-slot tap takes the scenic route; a stop two
    /// or three slots in stays on the pill. fromSlot/toSlot/slotCount are
    /// always finite integers, so stdlib min/max already matches Math.min/max here.
    public static func isEndToEnd(fromSlot: Int, toSlot: Int, slotCount: Int) -> Bool {
        return slotCount >= AROUND_MIN_SLOT_COUNT
            && min(fromSlot, toSlot) == 0
            && max(fromSlot, toSlot) == slotCount - 1
    }

    public static func shouldRouteAround(
        fromSlot: Int,
        toSlot: Int,
        slotCount: Int,
        aroundRoute: Bool,
        flightLift: Double,
        pill: PillFrame?,
        reduceMotion: Bool
    ) -> Bool {
        return isEndToEnd(fromSlot: fromSlot, toSlot: toSlot, slotCount: slotCount)
            && aroundRoute
            && flightLift == 0
            && pill != nil
            && !reduceMotion
    }

    /// distance from the perch box center down to the drawn feet; the around
    /// route rotates about this point so the feet stay on the pill's outline
    public static func routePivot(spriteScale: Double, footPad: Double) -> Double {
        return (PerchGeometry.PERCH_SIZE / 2 - footPad) * spriteScale
    }

    /// element at index, or NaN when out of range - mirrors JS reading a missing
    /// array element as undefined, which arithmetic and comparisons then treat as NaN
    private static func arrayValue(_ array: [Double], _ index: Int) -> Double {
        guard index >= 0, index < array.count else {
            return .nan
        }
        return array[index]
    }

    private static func signOrFallback(delta: Double, fallback: Facing) -> Facing {
        if delta > 0 {
            return .right
        }
        if delta < 0 {
            return .left
        }
        return fallback
    }

    /// cumulative chord length of the canonical half-ellipse (a*sin t, b*cos t),
    /// t = 0..pi in K steps; both arcs are reflections of this, so share it
    private static func computeArcCum(a: Double, b: Double, k: Int) -> [Double] {
        var cum: [Double] = [0]
        var prevX = 0.0
        var prevY = b
        for i in 1...k {
            let t = Double(i) * Double.pi / Double(k)
            let x = a * sin(t)
            let y = b * cos(t)
            cum.append(cum[i - 1] + hypot(x - prevX, y - prevY))
            prevX = x
            prevY = y
        }
        return cum
    }

    public static func planAroundPath(
        fromX: Double,
        targetX: Double,
        pill: PillFrame,
        windowWidth: Double,
        spriteScale: Double,
        footPad: Double,
        headPad: Double,
        seatOffset: Double
    ) -> AroundPath {
        // windowWidth and headPad are part of the caller's args object but
        // unused here too, matching perch-around.ts's planAroundPath
        _ = windowWidth
        _ = headPad

        let travel = signOrFallback(delta: targetX - fromX, fallback: .right)
        let exitSide: Facing = travel == .right ? .left : .right
        let enterSide = travel
        let facing = exitSide
        let spin = exitSide

        let pivot = routePivot(spriteScale: spriteScale, footPad: footPad)
        let boxCenterY0 = pill.y - seatOffset - PerchGeometry.PERCH_SIZE / 2
        let seatFeetY = boxCenterY0 + pivot
        let d = pill.y - seatFeetY // feet sit d above the pill top
        let R = pill.height / 2
        let a = R
        let b = R + d
        let cy = pill.y + R
        let cxExit = exitSide == .left ? pill.x + R : pill.x + pill.width - R
        let cxEnter = enterSide == .left ? pill.x + R : pill.x + pill.width - R
        let hangFeetY = cy + b // == pillBottom + d
        let underY = hangFeetY - seatFeetY
        let feetX0 = fromX + PerchGeometry.PERCH_SIZE / 2
        let targetFeetX = targetX + PerchGeometry.PERCH_SIZE / 2

        let arcCum = computeArcCum(a: a, b: b, k: ARC_SAMPLES)
        let arcLen = arcCum[ARC_SAMPLES]

        // no special case if feetX0 is already past cxExit (seat inside the cap):
        // exitRun is still the distance travelled toward cxExit
        let s1 = abs(cxExit - feetX0)
        let s2 = s1 + arcLen
        let s3 = s2 + abs(cxEnter - cxExit)
        let s4 = s3 + arcLen
        let s5 = s4 + abs(targetFeetX - cxEnter)
        let legs = [s1, s2, s3, s4, s5]
        let totalLen = s5
        let totalMs = (totalLen / AROUND_SPEED_PT_S) * 1000

        return AroundPath(
            exitSide: exitSide,
            enterSide: enterSide,
            facing: facing,
            spin: spin,
            pivot: pivot,
            seatFeetY: seatFeetY,
            underY: underY,
            cxExit: cxExit,
            cxEnter: cxEnter,
            cy: cy,
            a: a,
            b: b,
            feetX0: feetX0,
            targetFeetX: targetFeetX,
            arcCum: arcCum,
            arcLen: arcLen,
            legs: legs,
            totalLen: totalLen,
            totalMs: totalMs
        )
    }

    /// invert arc length -> phi by linear interpolation in arcCum
    private static func phiFromArcLength(arcCum: [Double], u: Double) -> Double {
        let k = arcCum.count - 1
        let uc = JSMath.jsMin(JSMath.jsMax(u, 0), arrayValue(arcCum, k))
        var i = 0
        while i < k - 1 && arrayValue(arcCum, i + 1) < uc {
            i += 1
        }
        let segLen = arrayValue(arcCum, i + 1) - arrayValue(arcCum, i)
        let frac = segLen > 0 ? (uc - arrayValue(arcCum, i)) / segLen : 0
        return (Double(i) + frac) * Double.pi / Double(k)
    }

    /// the ellipse's surface-normal angle at t, in degrees: 0 at t=0, 180 at t=pi
    private static func normalAngleDeg(t: Double, a: Double, b: Double) -> Double {
        return atan2(sin(t) / a, cos(t) / b) * 180 / Double.pi
    }

    /// pose along the path at arc length s (0 = departure, totalLen = arrival)
    public static func aroundPose(path: AroundPath, s: Double) -> AroundPose {
        let sc = JSMath.jsMin(JSMath.jsMax(s, 0), path.totalLen)
        let s1 = arrayValue(path.legs, 0)
        let s2 = arrayValue(path.legs, 1)
        let s3 = arrayValue(path.legs, 2)
        let s4 = arrayValue(path.legs, 3)
        let s5 = arrayValue(path.legs, 4)
        let hangFeetY = path.seatFeetY + path.underY

        let feetX: Double
        let feetY: Double
        let rotation: Double

        if sc <= s1 {
            let t = s1 > 0 ? sc / s1 : 1
            feetX = path.feetX0 + (path.cxExit - path.feetX0) * t
            feetY = path.seatFeetY
            rotation = 0
        } else if sc <= s2 {
            let phi = phiFromArcLength(arcCum: path.arcCum, u: sc - s1)
            feetX = path.cxExit + Double(path.exitSide.rawValue) * path.a * sin(phi)
            feetY = path.cy - path.b * cos(phi)
            rotation = Double(path.spin.rawValue) * normalAngleDeg(t: phi, a: path.a, b: path.b)
        } else if sc <= s3 {
            let legLen = s3 - s2
            let t = legLen > 0 ? (sc - s2) / legLen : 1
            feetX = path.cxExit + (path.cxEnter - path.cxExit) * t
            feetY = hangFeetY
            rotation = Double(path.spin.rawValue) * 180
        } else if sc <= s4 {
            let psi = phiFromArcLength(arcCum: path.arcCum, u: sc - s3)
            feetX = path.cxEnter + Double(path.enterSide.rawValue) * path.a * sin(psi)
            feetY = path.cy + path.b * cos(psi)
            rotation = Double(path.spin.rawValue) * (180 + normalAngleDeg(t: psi, a: path.a, b: path.b))
        } else {
            let legLen = s5 - s4
            let t = legLen > 0 ? (sc - s4) / legLen : 1
            feetX = path.cxEnter + (path.targetFeetX - path.cxEnter) * t
            feetY = path.seatFeetY
            rotation = Double(path.spin.rawValue) * 360
        }

        return AroundPose(
            x: feetX - PerchGeometry.PERCH_SIZE / 2,
            seatY: feetY - path.seatFeetY,
            rotation: rotation
        )
    }

    /// null when s is on a seat-line leg (1 or 5) - the caller falls back to
    /// the plain run-chase there, since seatY/rotation are already at rest.
    public static func resumeAroundRoute(base: AroundPath, s: Double, targetX: Double) -> ResumedRoute? {
        let s1 = arrayValue(base.legs, 0)
        let s4 = arrayValue(base.legs, 3)
        if s <= s1 || s >= s4 {
            return nil
        }
        let targetFeetX = targetX + PerchGeometry.PERCH_SIZE / 2
        let forwardLen = s4 - s + abs(targetFeetX - base.cxEnter)
        let backwardLen = s - s1 + abs(targetFeetX - base.cxExit)
        let dir: Facing = backwardLen < forwardLen ? .left : .right
        let endS = dir == .right ? s4 : s1
        let curveLen = abs(endS - s)
        let tailFromFeetX = dir == .right ? base.cxEnter : base.cxExit
        let tailToFeetX = targetFeetX
        let tailLen = abs(tailToFeetX - tailFromFeetX)
        let totalLen = curveLen + tailLen
        let flippedFacing: Facing = base.facing == .right ? .left : .right
        let facing: Facing = dir == .right ? base.facing : flippedFacing
        let endRotation = dir == .right ? Double(base.spin.rawValue) * 360 : 0

        return ResumedRoute(
            base: base,
            startS: s,
            endS: endS,
            dir: dir,
            curveLen: curveLen,
            tailFromFeetX: tailFromFeetX,
            tailToFeetX: tailToFeetX,
            tailLen: tailLen,
            totalLen: totalLen,
            totalMs: (totalLen / AROUND_SPEED_PT_S) * 1000,
            facing: facing,
            endRotation: endRotation
        )
    }

    /// pose along a resumed route at progress u (0 = interrupt point, totalLen =
    /// new target); u <= curveLen retraces the base outline, past that is the
    /// straight tail to the target at rest height/rotation
    public static func resumedPose(route: ResumedRoute, u: Double) -> AroundPose {
        let uc = JSMath.jsMin(JSMath.jsMax(u, 0), route.totalLen)
        if uc <= route.curveLen {
            return aroundPose(path: route.base, s: route.startS + Double(route.dir.rawValue) * uc)
        }
        let t = route.tailLen > 0 ? (uc - route.curveLen) / route.tailLen : 1
        let feetX = route.tailFromFeetX + (route.tailToFeetX - route.tailFromFeetX) * t
        return AroundPose(x: feetX - PerchGeometry.PERCH_SIZE / 2, seatY: 0, rotation: route.endRotation)
    }

    /// maps resumed-route progress u back to the base path's s while still on
    /// the curve; nil once u is on the straight tail (a second interrupt there
    /// is a plain run, not a second resume)
    public static func resumedBaseS(route: ResumedRoute, u: Double) -> Double? {
        if u < route.curveLen {
            return route.startS + Double(route.dir.rawValue) * u
        }
        return nil
    }
}
