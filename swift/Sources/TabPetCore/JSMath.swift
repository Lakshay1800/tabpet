/// JavaScript Math.min/Math.max semantics: stdlib min/max are comparison based,
/// so they drop a NaN operand and order signed zeros differently from JavaScript.
enum JSMath {
    static func jsMin(_ a: Double, _ b: Double) -> Double {
        if a.isNaN || b.isNaN {
            return .nan
        }
        if a == 0, b == 0 {
            return (a.sign == .minus || b.sign == .minus) ? -0.0 : 0.0
        }
        return a < b ? a : b
    }

    static func jsMax(_ a: Double, _ b: Double) -> Double {
        if a.isNaN || b.isNaN {
            return .nan
        }
        if a == 0, b == 0 {
            return (a.sign == .plus || b.sign == .plus) ? 0.0 : -0.0
        }
        return a > b ? a : b
    }
}
