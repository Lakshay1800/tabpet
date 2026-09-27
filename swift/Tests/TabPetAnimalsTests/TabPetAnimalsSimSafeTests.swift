import CryptoKit
import Foundation
import ImageIO
import XCTest

import TabPetCore

/// Reads pixel width/height from the file header only (no full decode) - the
/// concern here is the sheet's actual pixel geometry, not what AppKit/UIKit
/// reports in points.
private func pixelSize(of url: URL) -> (width: Int, height: Int)? {
    guard
        let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
        let width = props[kCGImagePropertyPixelWidth] as? Int,
        let height = props[kCGImagePropertyPixelHeight] as? Int
    else {
        return nil
    }
    return (width, height)
}

/// Every test in this file reads no repository file - only the animal
/// targets' own bundled resources and Swift-pinned literals - so
/// tools/swift-sim-test.sh can run this whole class on the simulator, where
/// a repository-relative path is not reachable.
final class TabPetAnimalsSimSafeTests: XCTestCase {
    // MARK: - the locator (used inside each animal's own `profile`) finds a
    // real bundle with the expected name, holding exactly its own assets -
    // checked without ever touching `Bundle.module`, which can trap.

    /// Walks a resolved resource URL's ancestors up to the enclosing
    /// ".bundle" directory - macOS wraps it as a real bundle (a
    /// Contents/Resources layout), so a resource's immediate parent is not
    /// the bundle root itself.
    private func enclosingBundleURL(of url: URL) -> URL? {
        var directory = url.deletingLastPathComponent()
        while directory.pathComponents.count > 1 {
            if directory.lastPathComponent.hasSuffix(".bundle") {
                return directory
            }
            directory = directory.deletingLastPathComponent()
        }
        return nil
    }

    func testLocatorResolvesTheExpectedBundleForEachAnimal() throws {
        for animal in animalsUnderTest {
            guard let sheets = animal.profile.sheets else {
                XCTFail("\(animal.id): sheets is nil - the locator could not resolve one of its sprite URLs")
                continue
            }
            guard let bundleURL = enclosingBundleURL(of: sheets.idle) else {
                XCTFail("\(animal.id): no enclosing .bundle directory above \(sheets.idle)")
                continue
            }
            XCTAssertEqual(
                bundleURL.lastPathComponent, animal.expectedBundleName,
                "\(animal.id): located a bundle other than the one SwiftPM names for this target"
            )
        }
    }

    // MARK: - the bundle's resource directory holds exactly its own three
    // sheets and the license - nothing else, so a target that also copies an
    // extra file (a stray notes.json, a second .md, another animal's sheet)
    // fails here even though the loose `paths(forResourcesOfType:)` check
    // above would have passed it.

    /// What the platform itself places at the resource root, beside whatever
    /// the target's own `resources:` list copies - observed directly on both
    /// a macOS `swift build` and an iOS simulator `xcodebuild` build, not
    /// guessed: `Info.plist` (both) and `_CodeSignature`, a directory (both).
    /// Nothing outside this list is allowed through.
    private let platformOwnedResourceEntries: Set<String> = ["Info.plist", "_CodeSignature"]

    func testBundleResourceDirectoryHoldsExactlyItsOwnThreeSheetsAndTheLicense() throws {
        for animal in animalsUnderTest {
            guard let sheets = animal.profile.sheets else {
                XCTFail("\(animal.id): sheets is nil - the locator could not resolve one of its sprite URLs")
                continue
            }
            guard let bundleURL = enclosingBundleURL(of: sheets.idle), let bundle = Bundle(url: bundleURL) else {
                XCTFail("\(animal.id): could not resolve the enclosing bundle")
                continue
            }
            guard let resourceURL = bundle.resourceURL else {
                XCTFail("\(animal.id): bundle has no resourceURL")
                continue
            }
            let entries = try FileManager.default.contentsOfDirectory(at: resourceURL, includingPropertiesForKeys: nil)
            let names = Set(entries.map(\.lastPathComponent)).subtracting(platformOwnedResourceEntries)
            let expected: Set<String> = [
                "\(animal.id)-idle-sprite.png", "\(animal.id)-run-sprite.png", "\(animal.id)-sit-sprite.png",
                "LICENSE-ART.md",
            ]
            XCTAssertEqual(
                names, expected,
                "\(animal.id): bundle resource directory holds more than its own three sheets and the license"
            )
        }
    }

    // MARK: - sheets load and are the right pixel geometry (sim-safe: no
    // repository file read, only Swift-pinned grid constants and the bundled
    // sheets themselves)

    func testAllThreeSheetsLoadAndHaveExactPixelGeometry() throws {
        for animal in animalsUnderTest {
            guard let sheets = animal.profile.sheets else {
                XCTFail("\(animal.id): sheets is nil - the locator could not resolve one of its sprite URLs")
                continue
            }
            guard let idleSize = pixelSize(of: sheets.idle) else {
                XCTFail("\(animal.id) idle: could not read pixel size from \(sheets.idle)")
                continue
            }
            let idleGrid = CompanionProfile.IDLE_SHEET_GRID
            XCTAssertEqual(
                idleSize.width % idleGrid.cols, 0, "\(animal.id) idle width is not a multiple of its cols"
            )
            let cellPx = idleSize.width / idleGrid.cols
            XCTAssertEqual(idleSize.height, cellPx * idleGrid.rows, "\(animal.id) idle height")

            let runGrid = CompanionProfile.RUN_SHEET_GRID
            try assertPixelSize(sheets.run, cols: runGrid.cols, rows: runGrid.rows, cellPx: cellPx, label: "\(animal.id) run")

            let sitGrid = animal.profile.resolvedSitSheet
            try assertPixelSize(sheets.sit, cols: sitGrid.cols, rows: sitGrid.rows, cellPx: cellPx, label: "\(animal.id) sit")
        }
    }

    private func assertPixelSize(_ url: URL, cols: Int, rows: Int, cellPx: Int, label: String) throws {
        guard let size = pixelSize(of: url) else {
            XCTFail("\(label): could not read pixel size from \(url)")
            return
        }
        XCTAssertEqual(size.width, cellPx * cols, "\(label) width")
        XCTAssertEqual(size.height, cellPx * rows, "\(label) height")
    }

    // MARK: - license present in every bundle

    func testLicenseFilePresentInEveryBundle() {
        for animal in animalsUnderTest {
            XCTAssertFalse(animal.licenseText.isEmpty, "\(animal.id): licenseText was empty - LICENSE-ART.md did not read")
        }
    }

    // MARK: - attribution / licenseText

    /// The two decided attribution phrases both live in the bundled license
    /// text itself, so the constants can't drift from LICENSE-ART.md.
    func testAttributionPhrasesAppearInTheBundledLicenseFile() {
        for animal in animalsUnderTest {
            XCTAssertTrue(
                animal.licenseText.contains("tabpet, CC BY 4.0"),
                "\(animal.id): bundled license is missing the base credit phrase"
            )
            XCTAssertTrue(
                animal.licenseText.contains("Created with Grok"),
                "\(animal.id): bundled license is missing the squirrel-designated phrase"
            )
        }
    }

    /// Exact match, not merely a substring check - a wrong-but-plausible
    /// attribution (a different license name, a missing animal's clause)
    /// must fail here even though it would still contain "tabpet".
    func testAttributionIsTheExactDecidedStringForEachAnimal() {
        for animal in animalsUnderTest {
            let expected = animal.id == "squirrel" ? "tabpet, CC BY 4.0. Created with Grok" : "tabpet, CC BY 4.0"
            XCTAssertEqual(animal.attribution, expected, "\(animal.id).attribution")
        }
    }

    func testOnlySquirrelAttributionCarriesTheGrokClause() {
        for animal in animalsUnderTest {
            if animal.id == "squirrel" {
                XCTAssertTrue(animal.attribution.contains("Created with Grok"))
            } else {
                XCTAssertFalse(animal.attribution.contains("Created with Grok"), "\(animal.id) should not carry the squirrel clause")
            }
        }
    }

    // MARK: - bundled sheets and license hash to their pinned digests
    // (sim-safe: no repository file read, only bundled files + Swift literals)

    func testBundledAssetsMatchThePinnedSHA256Digests() throws {
        for animal in animalsUnderTest {
            guard let sheets = animal.profile.sheets else {
                XCTFail("\(animal.id): sheets is nil")
                continue
            }
            guard let expected = pinnedSheetSHA256[animal.id] else {
                XCTFail("\(animal.id): no pinned sheet hashes")
                continue
            }
            try assertHash(of: sheets.idle, equals: expected.idle, label: "\(animal.id) idle")
            try assertHash(of: sheets.run, equals: expected.run, label: "\(animal.id) run")
            try assertHash(of: sheets.sit, equals: expected.sit, label: "\(animal.id) sit")

            // licenseText is decoded from the bundled file as UTF-8, and
            // re-encoding well-formed UTF-8 text is a byte-for-byte inverse
            // of decoding it, so hashing its .utf8 view is equivalent to
            // hashing the file - no Bundle lookup needed here.
            let digest = SHA256.hash(data: Data(animal.licenseText.utf8))
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(hex, pinnedLicenseSHA256, "\(animal.id) LICENSE-ART.md: SHA-256 does not match the pinned digest")
        }
    }

    private func assertHash(of url: URL, equals expectedHex: String, label: String) throws {
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(hex, expectedHex, "\(label): SHA-256 does not match the pinned digest - a .process build step would show up here")
    }
}
