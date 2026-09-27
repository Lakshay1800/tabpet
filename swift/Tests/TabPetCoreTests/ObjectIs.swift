import XCTest

/// Object.is semantics for Double: -0 and 0 differ, any NaN equals any NaN.
/// Swift's == treats -0 == 0 and NaN != NaN, so it can't stand in for the
/// TypeScript test's strictEqual on a number.
func objectIs(_ a: Double, _ b: Double) -> Bool {
    if a.isNaN, b.isNaN {
        return true
    }
    return a.bitPattern == b.bitPattern
}

func XCTAssertObjectIs(
    _ actual: Double,
    _ expected: Double,
    _ message: String,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertTrue(
        objectIs(actual, expected),
        "\(message) (was \(actual), expected \(expected))",
        file: file,
        line: line
    )
}
