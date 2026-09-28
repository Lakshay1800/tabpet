import XCTest

@testable import TabPetMotion

/// Expected values computed here from the same primitives the RN styles use
/// (companion-perch.tsx's `bottom` style and `PERCH_SIZE`, companion-sprite.tsx's
/// 4pt top margin), never copied out of `PerchLayout` itself.
final class PerchLayoutTests: XCTestCase {
    private let perchSize = 54.0 // TS: PERCH_SIZE
    private let referenceTopMargin = 4.0 // TS: companion-sprite.tsx's marginTop

    func testContainerBottomFallsBackToInsetsBottomWhenBarTopIsUnmeasured() {
        let bottom = PerchLayout.containerBottom(
            barTop: nil,
            windowHeight: 844,
            insetsBottom: 34,
            perchBottomOffset: -5,
            bottomExtra: 0
        )
        // TS: `(barTop === undefined ? insets.bottom : ...) + perchBottomOffset + bottomExtra`
        XCTAssertEqual(bottom, 34 + -5 + 0, accuracy: 1e-9)
    }

    func testContainerBottomUsesWindowHeightMinusBarTopWhenMeasured() {
        let bottom = PerchLayout.containerBottom(
            barTop: 780,
            windowHeight: 844,
            insetsBottom: 34,
            perchBottomOffset: 2,
            bottomExtra: 24
        )
        XCTAssertEqual(bottom, (844 - 780) + 2 + 24, accuracy: 1e-9)
    }

    func testContainerFrameIsLeftZeroAndPerchSizeSquare() {
        let frame = PerchLayout.containerFrame(
            barTop: 780,
            windowHeight: 844,
            insetsBottom: 34,
            perchBottomOffset: 0,
            bottomExtra: 0,
            perchSize: perchSize
        )
        let expectedBottom = 844.0 - 780.0
        XCTAssertEqual(frame.x, 0, accuracy: 1e-9)
        XCTAssertEqual(frame.width, perchSize, accuracy: 1e-9)
        XCTAssertEqual(frame.height, perchSize, accuracy: 1e-9)
        // top-down y = windowHeight - bottom - height
        XCTAssertEqual(frame.y, 844 - expectedBottom - perchSize, accuracy: 1e-9)
    }

    /// The sprite's own frame sits `referenceTopMarginPt` below the
    /// container's top - `CompanionSpriteView` does not add this margin on
    /// its own (see its own doc comment), so the perch places it here.
    func testSpriteFrameAddsTheReferenceTopMargin() {
        let container = PerchLayout.containerFrame(
            barTop: 780,
            windowHeight: 844,
            insetsBottom: 34,
            perchBottomOffset: 1,
            bottomExtra: 0,
            perchSize: perchSize
        )
        let sprite = PerchLayout.spriteFrame(
            barTop: 780,
            windowHeight: 844,
            insetsBottom: 34,
            perchBottomOffset: 1,
            bottomExtra: 0,
            perchSize: perchSize,
            spriteSize: perchSize,
            referenceTopMarginPt: referenceTopMargin
        )
        XCTAssertEqual(sprite.x, container.x, accuracy: 1e-9)
        XCTAssertEqual(sprite.y, container.y + referenceTopMargin, accuracy: 1e-9)
        XCTAssertEqual(sprite.width, perchSize, accuracy: 1e-9)
        XCTAssertEqual(sprite.height, perchSize, accuracy: 1e-9)
    }

    func testBottomExtraRaisesTheContainerByExactlyItsOwnValue() {
        let low = PerchLayout.containerFrame(barTop: nil, windowHeight: 844, insetsBottom: 34, perchBottomOffset: 0, bottomExtra: 0, perchSize: perchSize)
        let raised = PerchLayout.containerFrame(barTop: nil, windowHeight: 844, insetsBottom: 34, perchBottomOffset: 0, bottomExtra: 24, perchSize: perchSize)
        XCTAssertEqual(low.y - raised.y, 24, accuracy: 1e-9, "a raised bottomExtra moves the container up (smaller y) by exactly its own value")
    }
}
