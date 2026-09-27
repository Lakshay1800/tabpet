import XCTest

@testable import TabPetCore

final class JSMathTests: XCTestCase {
    func testJsMinPropagatesNaN() {
        XCTAssertTrue(JSMath.jsMin(.nan, 1).isNaN, "NaN in the first position propagates")
        XCTAssertTrue(JSMath.jsMin(1, .nan).isNaN, "NaN in the second position propagates")
    }

    func testJsMaxPropagatesNaN() {
        XCTAssertTrue(JSMath.jsMax(.nan, 1).isNaN, "NaN in the first position propagates")
        XCTAssertTrue(JSMath.jsMax(1, .nan).isNaN, "NaN in the second position propagates")
    }

    func testJsMaxSignedZero() {
        XCTAssertEqual(JSMath.jsMax(0, -0.0).sign, .plus, "Math.max(+0, -0) is +0")
        XCTAssertEqual(JSMath.jsMax(-0.0, 0).sign, .plus, "Math.max(-0, +0) is +0")
    }

    func testJsMinSignedZero() {
        XCTAssertEqual(JSMath.jsMin(0, -0.0).sign, .minus, "Math.min(+0, -0) is -0")
        XCTAssertEqual(JSMath.jsMin(-0.0, 0).sign, .minus, "Math.min(-0, +0) is -0")
    }

    func testOrdinaryValues() {
        XCTAssertEqual(JSMath.jsMin(3, 5), 3)
        XCTAssertEqual(JSMath.jsMax(3, 5), 5)
        XCTAssertEqual(JSMath.jsMin(-3, -5), -5)
        XCTAssertEqual(JSMath.jsMax(-3, -5), -3)
    }

    func testInfinities() {
        XCTAssertEqual(JSMath.jsMin(.infinity, 100), 100)
        XCTAssertEqual(JSMath.jsMax(.infinity, 100), .infinity)
        XCTAssertEqual(JSMath.jsMin(-.infinity, -100), -.infinity)
        XCTAssertEqual(JSMath.jsMax(-.infinity, -100), -100)
    }
}
