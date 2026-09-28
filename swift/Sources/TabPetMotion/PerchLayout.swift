/// Pure layout for the perch container and the sprite inside it, ported
/// from the RN styles plus the sprite's own 4pt top margin
/// (`CompanionSpriteView.referenceTopMarginPt`, which that view omits).
package enum PerchLayout {
    /// TS: `bottom: (barTop === undefined ? insets.bottom : windowHeight - barTop)
    /// + perchBottomOffset + bottomExtra`. `barTop` nil mirrors TS `undefined`
    /// (no measured bar - the bottom safe-area inset stands in for it).
    package static func containerBottom(
        barTop: Double?,
        windowHeight: Double,
        insetsBottom: Double,
        perchBottomOffset: Double,
        bottomExtra: Double
    ) -> Double {
        let barDerived = barTop.map { windowHeight - $0 } ?? insetsBottom
        return barDerived + perchBottomOffset + bottomExtra
    }

    /// The perch container's window-space frame at rest: `left: 0`, `width`/
    /// `height` both `perchSize` (TS: `PERCH_SIZE`), `bottom` per
    /// `containerBottom`, top-down `y` derived from it.
    package static func containerFrame(
        barTop: Double?,
        windowHeight: Double,
        insetsBottom: Double,
        perchBottomOffset: Double,
        bottomExtra: Double,
        perchSize: Double
    ) -> (x: Double, y: Double, width: Double, height: Double) {
        let bottom = containerBottom(
            barTop: barTop,
            windowHeight: windowHeight,
            insetsBottom: insetsBottom,
            perchBottomOffset: perchBottomOffset,
            bottomExtra: bottomExtra
        )
        return (x: 0, y: windowHeight - bottom - perchSize, width: perchSize, height: perchSize)
    }

    /// The sprite's own frame inside the perch container, offset down by
    /// `referenceTopMarginPt` - the 4pt top margin `CompanionSprite` (TS)
    /// draws itself with but `CompanionSpriteView` does not add on its own.
    package static func spriteFrame(
        barTop: Double?,
        windowHeight: Double,
        insetsBottom: Double,
        perchBottomOffset: Double,
        bottomExtra: Double,
        perchSize: Double,
        spriteSize: Double,
        referenceTopMarginPt: Double
    ) -> (x: Double, y: Double, width: Double, height: Double) {
        let container = containerFrame(
            barTop: barTop,
            windowHeight: windowHeight,
            insetsBottom: insetsBottom,
            perchBottomOffset: perchBottomOffset,
            bottomExtra: bottomExtra,
            perchSize: perchSize
        )
        return (x: container.x, y: container.y + referenceTopMarginPt, width: spriteSize, height: spriteSize)
    }
}
