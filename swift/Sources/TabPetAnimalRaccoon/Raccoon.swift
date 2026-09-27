import Foundation
import TabPetCore

/// Anchors ResourceBundleLocator's search at this target's own compiled
/// location - never used for anything else.
private final class ResourceBundleToken {}

/// Ported from packages/tabpet/src/animals/raccoon.ts - every number here must
/// equal the TypeScript profile; conformance/animals.json checks this in CI.
public enum TabPetAnimalRaccoon {
    public static let profile: CompanionProfile = CompanionProfile(
        id: "raccoon",
        label: "raccoon",
        runFps: 24,
        commitSpring: SpringConfig(duration: 430, dampingRatio: 0.82),
        trackSpring: SpringConfig(duration: 240, dampingRatio: 0.86),
        catchSpring: SpringConfig(duration: 260, dampingRatio: 0.9),
        hopHeight: -8,
        flightLift: 0,
        scale: 0.72,
        aroundRoute: true,
        headPad: 21,
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

    private static let bundleName = "TabPet_TabPetAnimalRaccoon.bundle"

    /// nil (never traps) if this target's resource bundle can't be found.
    private static let resourceBundle: Bundle? = ResourceBundleLocator.find(
        bundleName: bundleName, tokenType: ResourceBundleToken.self
    )

    /// nil (never traps) if a sheet URL cannot be resolved from the bundle.
    private static func sheets() -> CompanionSheets? {
        guard
            let bundle = resourceBundle,
            let idle = bundle.url(forResource: "raccoon-idle-sprite", withExtension: "png"),
            let run = bundle.url(forResource: "raccoon-run-sprite", withExtension: "png"),
            let sit = bundle.url(forResource: "raccoon-sit-sprite", withExtension: "png")
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
