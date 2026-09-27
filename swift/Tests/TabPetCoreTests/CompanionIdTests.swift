import XCTest

import TabPetCore

/// Mirrors companion-id.test.ts. TypeScript's `value: unknown` accepts both
/// `null` and `undefined` for the nullish case; Swift's `Any?` has one nil,
/// so testNullishFallsBackToFallback exercises it once instead of twice.
final class CompanionIdTests: XCTestCase {
    private let known = ["panda", "cat", "turtle", "raccoon", "bird", "squirrel"]

    func testValidIdPassesThrough() {
        for id in known {
            XCTAssertEqual(CompanionId.resolveCompanionId(value: id, known: known, fallback: "panda"), id, "\(id) passes through unchanged")
        }
    }

    func testUnknownStringFallsBackToFallback() {
        XCTAssertEqual(CompanionId.resolveCompanionId(value: "wolf", known: known, fallback: "panda"), "panda", "unrecognized id falls back")
        XCTAssertEqual(CompanionId.resolveCompanionId(value: "", known: known, fallback: "panda"), "panda", "empty string falls back")
    }

    func testNullishFallsBackToFallback() {
        XCTAssertEqual(CompanionId.resolveCompanionId(value: nil, known: known, fallback: "panda"), "panda", "null falls back")
    }

    /// Not in companion-id.test.ts. Swift's `==` treats these canonically
    /// equivalent; JavaScript's `Array.includes` (SameValueZero over UTF-16
    /// code units) does not - a decomposed id must not pass as its precomposed twin.
    func testCanonicallyEquivalentStringsAreDifferentIds() {
        let precomposed = "caf\u{00E9}" // é as a single code point
        let decomposed = "cafe\u{0301}" // e + combining acute accent
        XCTAssertEqual(precomposed, decomposed, "sanity: Swift's == treats these as canonically equivalent")
        XCTAssertNotEqual(Array(precomposed.utf16), Array(decomposed.utf16), "sanity: their UTF-16 code units differ")
        XCTAssertEqual(
            CompanionId.resolveCompanionId(value: decomposed, known: [precomposed], fallback: "panda"),
            "panda",
            "a decomposed id does not match its precomposed twin in the known list"
        )
    }
}
