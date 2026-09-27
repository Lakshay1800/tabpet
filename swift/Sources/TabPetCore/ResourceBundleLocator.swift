import Foundation

/// Never public API (`package` access - visible to every target in this
/// package, never to a host app): SwiftPM's generated resource-bundle
/// accessor calls fatalError when it can't find its resource bundle next to
/// the running executable - library code must never risk that trap. This is
/// a non-trapping stand-in: it tries the same locations that generated
/// accessor itself tries, plus the layout `swift test` uses (the resource
/// bundle sits beside the test bundle, not inside Bundle.main), and returns
/// nil instead of aborting when none of them resolve.
package enum ResourceBundleLocator {
    /// `tokenType` must be a type compiled into the same target whose
    /// resource bundle `bundleName` names, so its own enclosing bundle
    /// anchors the search - Bundle.main is not where resources land under
    /// `swift test`.
    package static func find(bundleName: String, tokenType: AnyObject.Type) -> Bundle? {
        let token = Bundle(for: tokenType)
        let candidateDirectories: [URL?] = [
            Bundle.main.resourceURL,
            token.resourceURL,
            Bundle.main.bundleURL,
            token.bundleURL.deletingLastPathComponent(),
            // Xcode Previews run from another package: the resource bundle can
            // sit two or three directories above the token bundle's resources.
            // Not every toolchain's generated accessor looks there.
            token.resourceURL?.deletingLastPathComponent().deletingLastPathComponent(),
            token.resourceURL?.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent(),
        ]
        for directory in candidateDirectories {
            guard let directory else { continue }
            let candidate = directory.appendingPathComponent(bundleName)
            if let bundle = Bundle(url: candidate) {
                return bundle
            }
        }
        return nil
    }
}
