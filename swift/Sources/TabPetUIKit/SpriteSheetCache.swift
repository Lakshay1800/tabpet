#if canImport(UIKit)
import Foundation
import ImageIO
import UIKit

/// Decodes a sprite sheet PNG off the main thread and validates its
/// geometry, keyed by file URL. Refused, never thrown: a non-file URL, a
/// sheet not an exact multiple of its grid, or one over 4096px on a side.
@MainActor
final class SpriteSheetCache {
    static let shared = SpriteSheetCache()

    enum LoadError: Error, Sendable, Equatable {
        case notFileURL
        case decodeFailed
        case sheetNotGridMultiple
        case sheetTooLarge
    }

    /// Cost is the decoded byte count, so NSCache evicts in proportion to
    /// what's resident. The limit is about two animals' worth of sheets -
    /// a host cycling through more just re-decodes an evicted one.
    private let cache = NSCache<NSURL, CGImage>()
    private static let totalCostLimitBytes = 32_000_000

    private init() {
        cache.totalCostLimit = Self.totalCostLimitBytes
    }

    /// Test-only: called from inside the decode itself with the URL and
    /// `Thread.isMainThread`. `shared` is the only instance, so this is
    /// effectively process-global: a test that sets it must clear it again.
    var debugDecodeHook: (@Sendable (URL, Bool) -> Void)?

    /// Test-only: the cache's own configured limit.
    var debugTotalCostLimit: Int { cache.totalCostLimit }

    /// Waiters for a URL whose decode is already in flight - the first miss
    /// starts it, every later request for the same URL joins this list
    /// instead of starting a second decode.
    private var pendingCompletions: [URL: [Waiter]] = [:]

    /// One request waiting on a decode. The image is cached by URL alone,
    /// but the grid belongs to the request: the same sheet asked for with
    /// two grids is checked against each.
    private struct Waiter {
        let cols: Int
        let rows: Int
        let completion: @MainActor (Result<CGImage, LoadError>) -> Void
    }

    /// `completion` always runs on the main actor, exactly once, synchronously
    /// for a cache hit or a rejected URL, asynchronously after an off-main
    /// decode otherwise (shared with every other waiter on the same URL).
    func loadSheet(
        url: URL,
        cols: Int,
        rows: Int,
        completion: @escaping @MainActor (Result<CGImage, LoadError>) -> Void
    ) {
        guard url.isFileURL else {
            completion(.failure(.notFileURL))
            return
        }
        if let cached = cache.object(forKey: url as NSURL) {
            completion(Self.checkGrid(cached, cols: cols, rows: rows))
            return
        }
        let waiter = Waiter(cols: cols, rows: rows, completion: completion)
        if pendingCompletions[url] != nil {
            pendingCompletions[url]?.append(waiter)
            return
        }
        pendingCompletions[url] = [waiter]
        let hook = debugDecodeHook
        // The outer task stays on the main actor, so it can capture `self`
        // directly - only the inner detached task, over plain Sendable
        // values, actually runs the decode off-main.
        Task { @MainActor [weak self] in
            let boxed = await Task.detached(priority: .userInitiated) {
                DecodeResult(outcome: Self.decode(url: url, debugHook: hook))
            }.value
            guard let self else { return }
            if case .success(let image) = boxed.outcome {
                self.store(image, for: url)
            }
            let waiters = self.pendingCompletions.removeValue(forKey: url) ?? []
            for waiter in waiters {
                waiter.completion(boxed.outcome.flatMap { Self.checkGrid($0, cols: waiter.cols, rows: waiter.rows) })
            }
        }
    }

    /// The pixel size must be an exact multiple of the grid, never rounded
    /// or floored. Checked per request, on cache hits too.
    private static func checkGrid(_ image: CGImage, cols: Int, rows: Int) -> Result<CGImage, LoadError> {
        guard cols > 0, rows > 0, image.width % cols == 0, image.height % rows == 0 else {
            return .failure(.sheetNotGridMultiple)
        }
        return .success(image)
    }

    private func store(_ image: CGImage, for url: URL) {
        let cost = image.bytesPerRow * image.height
        cache.setObject(image, forKey: url as NSURL, cost: cost)
    }

    /// Runs entirely off the main actor (`nonisolated`, called only from
    /// inside `Task.detached` above) - this is the decode itself, the one
    /// piece of work in this whole target that must never run on main.
    nonisolated private static func decode(
        url: URL,
        debugHook: (@Sendable (URL, Bool) -> Void)?
    ) -> Result<CGImage, LoadError> {
        debugHook?(url, Thread.isMainThread)
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            CGImageSourceGetCount(source) > 0,
            CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
            let rawImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return .failure(.decodeFailed)
        }
        let width = rawImage.width
        let height = rawImage.height
        guard width > 0, height > 0, width <= 4096, height <= 4096 else {
            return .failure(.sheetTooLarge)
        }
        // Drawing into a premultiplied context forces the real pixel decode
        // to happen right here, off-main - Core Animation never converts or
        // decodes this image later, on the main thread, at commit time.
        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            )
        else {
            return .failure(.decodeFailed)
        }
        context.draw(rawImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let decodedImage = context.makeImage() else {
            return .failure(.decodeFailed)
        }
        return .success(decodedImage)
    }
}

/// `CGImage` predates `Sendable` in the SDK; it is immutable once decoded, so
/// this box is a deliberate, narrow `@unchecked Sendable` to cross the
/// `Task.detached` -> main-actor boundary once, holding nothing else.
private struct DecodeResult: @unchecked Sendable {
    let outcome: Result<CGImage, SpriteSheetCache.LoadError>
}
#endif
