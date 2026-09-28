import Foundation

/// Pure 2D affine transform, mirroring CGAffineTransform's own field layout
/// and row-vector convention without depending on CoreGraphics - a caller
/// in TabPetUIKit builds a real one with `CGAffineTransform(a:b:c:d:tx:ty:)`.
package struct Affine2D: Equatable, Sendable {
    package var a: Double
    package var b: Double
    package var c: Double
    package var d: Double
    package var tx: Double
    package var ty: Double

    package static let identity = Affine2D(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)

    package init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
        self.tx = tx
        self.ty = ty
    }

    package static func translation(x: Double, y: Double) -> Affine2D {
        Affine2D(a: 1, b: 0, c: 0, d: 1, tx: x, ty: y)
    }

    package static func rotation(radians: Double) -> Affine2D {
        Affine2D(a: cos(radians), b: sin(radians), c: -sin(radians), d: cos(radians), tx: 0, ty: 0)
    }

    /// `self` applied first, then `other` - matches CGAffineTransform's own
    /// `concatenating` semantics exactly (row-vector: `p' = p * self * other`),
    /// so a chain built here composes identically to one built with the real type.
    package func concatenating(_ other: Affine2D) -> Affine2D {
        Affine2D(
            a: a * other.a + b * other.c,
            b: a * other.b + b * other.d,
            c: c * other.a + d * other.c,
            d: c * other.b + d * other.d,
            tx: tx * other.a + ty * other.c + other.tx,
            ty: tx * other.b + ty * other.d + other.ty
        )
    }

    package func apply(toX x: Double, y: Double) -> (x: Double, y: Double) {
        (x: x * a + y * c + tx, y: x * b + y * d + ty)
    }
}

/// The perch's own affine transform, ported from companion-perch.tsx's
/// transform array: rotates about the drawn feet, not the box center,
/// built right-to-left so `concatenating` matches that array's order.
package enum PerchTransform {
    /// `x, hop, seatY, flightLift` pt; `rotationDegrees` degrees; `pivot`
    /// (TS's own container-center-relative value) fixes `(0, pivot)` at
    /// `(x, pivot + hop + seatY + flightLift)` for every rotation.
    package static func affine(
        x: Double,
        hop: Double,
        seatY: Double,
        flightLift: Double,
        rotationDegrees: Double,
        pivot: Double,
        referenceTopMarginPt: Double = 0
    ) -> Affine2D {
        let effectivePivot = pivot - referenceTopMarginPt
        let radians = Self.radians(fromDegrees: rotationDegrees)
        var transform = Affine2D.translation(x: 0, y: -effectivePivot)
        transform = transform.concatenating(.rotation(radians: radians))
        transform = transform.concatenating(.translation(x: 0, y: effectivePivot))
        transform = transform.concatenating(.translation(x: x, y: hop + seatY + flightLift))
        return transform
    }

    /// The one place degrees becomes radians for this transform - never
    /// inline in `affine`, so a test can pin the conversion on its own.
    package static func radians(fromDegrees degrees: Double) -> Double {
        degrees * Double.pi / 180
    }
}
