import XCTest

@testable import TabPetMotion

final class PerchTransformTests: XCTestCase {
    // MARK: - The feet point is fixed under rotation

    /// The local point `(0, pivot)` - the drawn feet - must land at the same
    /// world point for every rotation: `(x, pivot + hop + seatY + flightLift)`.
    func testFeetPointIsFixedUnderRotation() {
        let x = 120.0
        let hop = -4.0
        let seatY = 6.0
        let flightLift = -14.0
        let pivot = 21.5
        let expectedFeet = (x: x, y: pivot + hop + seatY + flightLift)

        for degrees: Double in [0, 15, 90, -37.5, 180, 359, -720] {
            let transform = PerchTransform.affine(x: x, hop: hop, seatY: seatY, flightLift: flightLift, rotationDegrees: degrees, pivot: pivot)
            let feet = transform.apply(toX: 0, y: pivot)
            XCTAssertEqual(feet.x, expectedFeet.x, accuracy: 1e-9, "degrees=\(degrees)")
            XCTAssertEqual(feet.y, expectedFeet.y, accuracy: 1e-9, "degrees=\(degrees)")
        }
    }

    // MARK: - referenceTopMarginPt keeps the feet point aligned with the container

    /// A caller applying this to the sprite view (whose center sits
    /// `referenceTopMarginPt` below the container's) must pass that margin,
    /// or the rotation pivots 4pt off - proven by comparing feet points.
    func testReferenceTopMarginKeepsTheFeetPointAlignedWithTheContainerAt90Degrees() {
        let x = 80.0
        let hop = -3.0
        let seatY = 5.0
        let flightLift = -10.0
        let pivot = 21.5
        let margin = 4.0
        // The sprite's own center sits `margin` below the container's -
        // both frames share the same window-space origin otherwise.
        let containerCenter = (x: 0.0, y: 0.0)
        let spriteCenter = (x: 0.0, y: margin)

        // TS: the transform's own local origin is the container's center.
        let tsTransform = PerchTransform.affine(x: x, hop: hop, seatY: seatY, flightLift: flightLift, rotationDegrees: 90, pivot: pivot)
        let tsFeetLocal = tsTransform.apply(toX: 0, y: pivot)
        let tsFeetWorld = (x: containerCenter.x + tsFeetLocal.x, y: containerCenter.y + tsFeetLocal.y)

        // This port: the transform's own local origin is the sprite's own
        // center instead - the margin correction is what keeps it aligned.
        let spriteTransform = PerchTransform.affine(
            x: x, hop: hop, seatY: seatY, flightLift: flightLift, rotationDegrees: 90, pivot: pivot, referenceTopMarginPt: margin
        )
        let spriteFeetLocal = spriteTransform.apply(toX: 0, y: pivot - margin)
        let spriteFeetWorld = (x: spriteCenter.x + spriteFeetLocal.x, y: spriteCenter.y + spriteFeetLocal.y)

        XCTAssertEqual(spriteFeetWorld.x, tsFeetWorld.x, accuracy: 1e-9)
        XCTAssertEqual(spriteFeetWorld.y, tsFeetWorld.y, accuracy: 1e-9)
    }

    /// `referenceTopMarginPt` defaults to 0 - every existing caller (no
    /// margin passed) is unchanged.
    func testReferenceTopMarginDefaultsToZero() {
        let transform = PerchTransform.affine(x: 12, hop: 1, seatY: 2, flightLift: 3, rotationDegrees: 45, pivot: 10)
        let withExplicitZero = PerchTransform.affine(x: 12, hop: 1, seatY: 2, flightLift: 3, rotationDegrees: 45, pivot: 10, referenceTopMarginPt: 0)
        XCTAssertEqual(transform, withExplicitZero)
    }

    func testZeroRotationAndZeroPivotIsAPlainTranslation() {
        let transform = PerchTransform.affine(x: 30, hop: 1, seatY: 2, flightLift: 3, rotationDegrees: 0, pivot: 0)
        let point = transform.apply(toX: 5, y: 7)
        XCTAssertEqual(point.x, 35, accuracy: 1e-9)
        XCTAssertEqual(point.y, 13, accuracy: 1e-9)
    }

    // MARK: - 90 degrees maps to pi/2

    func testNinetyDegreesMapsToPiOverTwo() {
        XCTAssertEqual(PerchTransform.radians(fromDegrees: 90), .pi / 2, accuracy: 1e-12)
        XCTAssertEqual(PerchTransform.radians(fromDegrees: 180), .pi, accuracy: 1e-12)
        XCTAssertEqual(PerchTransform.radians(fromDegrees: 0), 0, accuracy: 1e-12)
    }

    /// Mutation: dropping the degree-to-radian conversion (treating degrees
    /// as radians directly) rotates by roughly 5157 degrees instead of 90,
    /// landing a point off the pivot somewhere unrelated to this exact value.
    func testDroppingTheDegreeToRadianConversionIsCaught() {
        let pivot = 10.0
        let transform = PerchTransform.affine(x: 0, hop: 0, seatY: 0, flightLift: 0, rotationDegrees: 90, pivot: pivot)
        // (0, 0) in local space is `pivot` away from the rotation center - a
        // real pi/2 turn (never 90 raw radians) carries it to exactly (pivot, pivot).
        let point = transform.apply(toX: 0, y: 0)
        XCTAssertEqual(point.x, pivot, accuracy: 1e-9)
        XCTAssertEqual(point.y, pivot, accuracy: 1e-9)
    }

    // MARK: - Affine2D composition sanity (used by the transform above)

    func testConcatenatingWithIdentityIsANoOp() {
        let t = Affine2D.translation(x: 3, y: 4).concatenating(.rotation(radians: 0.4))
        XCTAssertEqual(t.concatenating(.identity), t)
        XCTAssertEqual(Affine2D.identity.concatenating(t), t)
    }

    func testRotationByPiIsPointSymmetricAboutTheOrigin() {
        let rotation = Affine2D.rotation(radians: .pi)
        let point = rotation.apply(toX: 3, y: -2)
        XCTAssertEqual(point.x, -3, accuracy: 1e-9)
        XCTAssertEqual(point.y, 2, accuracy: 1e-9)
    }
}
