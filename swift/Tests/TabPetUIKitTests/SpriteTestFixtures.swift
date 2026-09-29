#if canImport(UIKit)
import CoreGraphics
import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

import TabPetCore

/// The simulator's sandboxed test process cannot open a host repository
/// path by absolute location, so every fixture here is generated at test
/// time into `FileManager.default.temporaryDirectory` instead.
enum SpriteTestFixtures {
    /// Writes a solid-color PNG of the exact pixel size requested and
    /// returns its file URL. Content is irrelevant to every test that uses
    /// this - only the pixel geometry and the ability to decode matter.
    static func makeSolidColorPNG(pixelWidth: Int, pixelHeight: Int, color: (UInt8, UInt8, UInt8, UInt8) = (200, 120, 60, 255)) -> URL {
        var pixels = [UInt8](repeating: 0, count: pixelWidth * pixelHeight * 4)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            pixels[i] = color.0
            pixels[i + 1] = color.1
            pixels[i + 2] = color.2
            pixels[i + 3] = color.3
        }
        // `&pixels` is only valid for the single call it's passed to, but
        // CGContext draws into this buffer for its whole life - the pointer
        // must come from a scope that outlives the call.
        let image: CGImage = pixels.withUnsafeMutableBytes { buffer in
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let context = CGContext(
                data: buffer.baseAddress,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: pixelWidth * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            return context.makeImage()!
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        precondition(CGImageDestinationFinalize(destination), "test fixture PNG failed to write")
        return url
    }

    /// A file that exists and ends in `.png` but decodes as nothing.
    static func makeUndecodablePNG() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
        try! Data("not a png".utf8).write(to: url)
        return url
    }

    /// One companion profile whose three sheets are freshly generated,
    /// grid-valid PNGs at a tiny cell size - fast to decode, real enough
    /// to exercise the whole `CompanionSpriteView` pipeline end to end.
    static func makeFixtureProfile(id: String = "fixture-\(UUID().uuidString)", cellSize: Int = 20, runSpeed: Double? = nil, aroundRoute: Bool = false) -> CompanionProfile {
        let idleGrid = CompanionProfile.IDLE_SHEET_GRID
        let runGrid = CompanionProfile.RUN_SHEET_GRID
        let idleURL = makeSolidColorPNG(pixelWidth: cellSize * idleGrid.cols, pixelHeight: cellSize * idleGrid.rows)
        let runURL = makeSolidColorPNG(pixelWidth: cellSize * runGrid.cols, pixelHeight: cellSize * runGrid.rows)
        let sitURL = makeSolidColorPNG(pixelWidth: cellSize * idleGrid.cols, pixelHeight: cellSize * idleGrid.rows)
        return CompanionProfile(
            id: id,
            label: id,
            runFps: 18,
            commitSpring: SpringConfig(duration: 560, dampingRatio: 0.86),
            trackSpring: SpringConfig(duration: 300, dampingRatio: 0.9),
            catchSpring: SpringConfig(duration: 260, dampingRatio: 0.9),
            hopHeight: -6,
            flightLift: 0,
            scale: 1,
            aroundRoute: aroundRoute,
            runSpeed: runSpeed,
            sheets: CompanionSheets(idle: idleURL, run: runURL, sit: sitURL)
        )
    }
}
#endif
