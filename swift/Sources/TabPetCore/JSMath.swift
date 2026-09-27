/// JavaScript Math.min/Math.max semantics: stdlib min/max are comparison based,
/// so they drop a NaN operand and order signed zeros differently from JavaScript.
package enum JSMath {
    package static func jsMin(_ a: Double, _ b: Double) -> Double {
        if a.isNaN || b.isNaN {
            return .nan
        }
        if a == 0, b == 0 {
            return (a.sign == .minus || b.sign == .minus) ? -0.0 : 0.0
        }
        return a < b ? a : b
    }

    package static func jsMax(_ a: Double, _ b: Double) -> Double {
        if a.isNaN || b.isNaN {
            return .nan
        }
        if a == 0, b == 0 {
            return (a.sign == .plus || b.sign == .plus) ? 0.0 : -0.0
        }
        return a > b ? a : b
    }

    /// JavaScript truthiness for a number: only `0`, `-0` and `NaN` are
    /// falsy - matches `!!x` exactly, unlike `x != 0` (which treats NaN as
    /// truthy, since every `!=` comparison with NaN is true).
    package static func isTruthy(_ value: Double) -> Bool {
        value != 0 && !value.isNaN
    }

    /// `x || 0` for a JS number: keeps `x` unless it is falsy (0, -0 or NaN).
    package static func orZero(_ value: Double) -> Double {
        isTruthy(value) ? value : 0
    }
}
