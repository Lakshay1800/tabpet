#if canImport(UIKit)
import XCTest

@testable import TabPetUIKit

@MainActor
final class SpriteSheetCacheTests: XCTestCase {
    private func load(url: URL, cols: Int = 5, rows: Int = 5) -> Result<CGImage, SpriteSheetCache.LoadError> {
        let expectation = expectation(description: "loadSheet")
        var captured: Result<CGImage, SpriteSheetCache.LoadError>!
        SpriteSheetCache.shared.loadSheet(url: url, cols: cols, rows: rows) { result in
            captured = result
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)
        return captured
    }

    /// `Result<CGImage, LoadError>` has no `Equatable` conformance (`CGImage`
    /// doesn't), so every failure case below asserts by pattern match.
    private func assertFailure(
        _ result: Result<CGImage, SpriteSheetCache.LoadError>,
        is expected: SpriteSheetCache.LoadError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failure(let error) = result else {
            return XCTFail("expected .failure(\(expected)), got \(result)", file: file, line: line)
        }
        XCTAssertEqual(error, expected, file: file, line: line)
    }

    func testRejectsANonFileURL() {
        let result = load(url: URL(string: "https://example.com/sheet.png")!)
        assertFailure(result, is: .notFileURL)
    }

    func testRejectsAFileThatDoesNotDecodeAsAnImage() {
        let result = load(url: SpriteTestFixtures.makeUndecodablePNG())
        assertFailure(result, is: .decodeFailed)
    }

    func testRejectsASheetOverFourThousandNinetySixPixelsOnASide() {
        let url = SpriteTestFixtures.makeSolidColorPNG(pixelWidth: 4097, pixelHeight: 100)
        let result = load(url: url, cols: 1, rows: 1)
        assertFailure(result, is: .sheetTooLarge)
    }

    func testAcceptsExactlyFourThousandNinetySixOnASide() {
        let url = SpriteTestFixtures.makeSolidColorPNG(pixelWidth: 4096, pixelHeight: 100)
        let result = load(url: url, cols: 1, rows: 1)
        switch result {
        case .success:
            break
        case .failure(let error):
            XCTFail("4096px exactly must be accepted, got \(error)")
        }
    }

    func testRejectsASheetThatIsNotAnExactMultipleOfItsGrid() {
        // 253 is not evenly divisible by 5 - the pixel size must be an exact
        // multiple of the grid, never rounded or floored.
        let url = SpriteTestFixtures.makeSolidColorPNG(pixelWidth: 253, pixelHeight: 250)
        let result = load(url: url, cols: 5, rows: 5)
        assertFailure(result, is: .sheetNotGridMultiple)
    }

    func testAcceptsASheetThatIsAnExactMultipleOfItsGrid() {
        let url = SpriteTestFixtures.makeSolidColorPNG(pixelWidth: 250, pixelHeight: 250)
        let result = load(url: url, cols: 5, rows: 5)
        switch result {
        case .success:
            break
        case .failure(let error):
            XCTFail("an exact multiple must be accepted, got \(error)")
        }
    }

    func testASecondLoadOfTheSameURLIsServedFromTheCache() {
        let url = SpriteTestFixtures.makeSolidColorPNG(pixelWidth: 100, pixelHeight: 100)
        guard case .success(let first) = load(url: url, cols: 2, rows: 2) else {
            return XCTFail("first load must succeed")
        }
        guard case .success(let second) = load(url: url, cols: 2, rows: 2) else {
            return XCTFail("second load must succeed")
        }
        XCTAssertTrue(first === second, "the second load must return the same cached CGImage instance, not a fresh decode")
    }

    func testDecodeRunsOffTheMainThread() {
        let url = SpriteTestFixtures.makeSolidColorPNG(pixelWidth: 40, pixelHeight: 40)
        let observed = LockedBox<Bool?>(nil)
        SpriteSheetCache.shared.debugDecodeHook = { _, isMain in
            observed.set(isMain)
        }
        defer { SpriteSheetCache.shared.debugDecodeHook = nil }
        _ = load(url: url, cols: 2, rows: 2)
        // Mutation: decoding inline on the main actor before handing off to
        // `Task.detached` (or dropping the detached task entirely) would
        // observe `true` here instead.
        XCTAssertEqual(observed.get(), false, "the decode itself must not run on the main thread")
    }

    func testTheDecodedImageIsAnEightBitPremultipliedBitmap() {
        let url = SpriteTestFixtures.makeSolidColorPNG(pixelWidth: 40, pixelHeight: 40)
        guard case .success(let image) = load(url: url, cols: 2, rows: 2) else {
            return XCTFail("load must succeed")
        }
        XCTAssertEqual(image.bitsPerComponent, 8)
        let alphaInfo = CGImageAlphaInfo(rawValue: image.bitmapInfo.rawValue & CGBitmapInfo.alphaInfoMask.rawValue)
        XCTAssertEqual(alphaInfo, .premultipliedFirst, "the decode must draw into its own premultiplied context, not rely on a lazy ImageIO decode")
    }

    func testTotalCostLimitIsSetAndBetweenSixteenAndSixtyFourMB() {
        let limit = SpriteSheetCache.shared.debugTotalCostLimit
        XCTAssertGreaterThanOrEqual(limit, 16_000_000)
        XCTAssertLessThanOrEqual(limit, 64_000_000)
    }

    func testTwoRequestsForTheSameURLBeforeTheFirstCompletesShareOneDecode() {
        let url = SpriteTestFixtures.makeSolidColorPNG(pixelWidth: 100, pixelHeight: 100)
        let decodeCount = LockedBox<Int>(0)
        SpriteSheetCache.shared.debugDecodeHook = { _, _ in
            decodeCount.set(decodeCount.get() + 1)
        }
        defer { SpriteSheetCache.shared.debugDecodeHook = nil }

        let firstDone = expectation(description: "first load")
        let secondDone = expectation(description: "second load")
        var firstImage: CGImage?
        var secondImage: CGImage?
        // Both calls happen synchronously, back to back, before either's
        // Task has had a chance to run - the second must join the first as
        // a waiter rather than starting its own decode.
        SpriteSheetCache.shared.loadSheet(url: url, cols: 2, rows: 2) { result in
            if case .success(let image) = result { firstImage = image }
            firstDone.fulfill()
        }
        SpriteSheetCache.shared.loadSheet(url: url, cols: 2, rows: 2) { result in
            if case .success(let image) = result { secondImage = image }
            secondDone.fulfill()
        }
        wait(for: [firstDone, secondDone], timeout: 5.0)

        XCTAssertEqual(decodeCount.get(), 1, "two requests for one URL made before the first completes must decode only once")
        XCTAssertNotNil(firstImage)
        XCTAssertTrue(firstImage === secondImage, "both waiters must get the identical decoded image instance")
    }

    func testTheDecodedImageSurvivesDeletionOfItsSourceFile() {
        let color: (UInt8, UInt8, UInt8, UInt8) = (10, 200, 30, 255)
        let url = SpriteTestFixtures.makeSolidColorPNG(pixelWidth: 80, pixelHeight: 80, color: color)
        guard case .success(let image) = load(url: url, cols: 1, rows: 1) else {
            return XCTFail("load must succeed")
        }
        try? FileManager.default.removeItem(at: url)

        var pixel: [UInt8] = [0, 0, 0, 0]
        let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        // Mutation: without kCGImageSourceShouldCacheImmediately the image
        // can stay bound to the file that produced it - once that file is
        // gone, a lazy decode no longer reproduces the original pixel.
        for (channel, expected) in zip(pixel, [color.0, color.1, color.2, color.3]) {
            XCTAssertLessThanOrEqual(abs(Int(channel) - Int(expected)), 2, "a decoded image must not depend on its source file still existing")
        }
    }
}

/// The debug hook runs off-main, so a plain captured `var` would trip the
/// Swift 6 concurrency checker - the value crosses through this small
/// lock-guarded box instead.
private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func set(_ newValue: Value) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func get() -> Value {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
#endif
