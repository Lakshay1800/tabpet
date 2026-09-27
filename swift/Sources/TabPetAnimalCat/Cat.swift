import Foundation
import TabPetCore

/// Anchors ResourceBundleLocator's search at this target's own compiled
/// location - never used for anything else.
private final class ResourceBundleToken {}

/// Ported from packages/tabpet/src/animals/cat.ts - every number here must
/// equal the TypeScript profile; conformance/animals.json checks this in CI.
public enum TabPetAnimalCat {
    public static let profile: CompanionProfile = CompanionProfile(
        id: "cat",
        label: "cat",
        runFps: 24,
        commitSpring: SpringConfig(duration: 380, dampingRatio: 0.8),
        trackSpring: SpringConfig(duration: 240, dampingRatio: 0.86),
        catchSpring: SpringConfig(duration: 260, dampingRatio: 0.9),
        hopHeight: -8,
        flightLift: 0,
        scale: 1,
        aroundRoute: false,
        headPad: 12,
        footPad: 6.5,
        sheets: sheets()
    )

    /// The credit line a host shows; see LICENSE-ART.md - only the squirrel
    /// carries the extra "Created with Grok" clause.
    public static let attribution: String = "tabpet, CC BY 4.0"

    /// Full bundled LICENSE-ART.md text; "" if it can't be read.
    public static let licenseText: String = readLicenseText()

    @MainActor
    public static func register(in registry: CompanionRegistry = .shared) {
        registry.register(profile)
    }

    private static let bundleName = "TabPet_TabPetAnimalCat.bundle"

    /// nil (never traps) if this target's resource bundle can't be found.
    private static let resourceBundle: Bundle? = ResourceBundleLocator.find(
        bundleName: bundleName, tokenType: ResourceBundleToken.self
    )

    /// nil (never traps) if a sheet URL cannot be resolved from the bundle.
    private static func sheets() -> CompanionSheets? {
        guard
            let bundle = resourceBundle,
            let idle = bundle.url(forResource: "cat-idle-sprite", withExtension: "png"),
            let run = bundle.url(forResource: "cat-run-sprite", withExtension: "png"),
            let sit = bundle.url(forResource: "cat-sit-sprite", withExtension: "png")
        else {
            return nil
        }
        return CompanionSheets(idle: idle, run: run, sit: sit)
    }

    /// "" (never throws) if the bundled license file can't be read.
    private static func readLicenseText() -> String {
        guard
            let bundle = resourceBundle,
            let url = bundle.url(forResource: "LICENSE-ART", withExtension: "md"),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            return ""
        }
        return text
    }
}
