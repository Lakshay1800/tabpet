import Foundation
import TabPetCore

/// Anchors ResourceBundleLocator's search at this target's own compiled
/// location - never used for anything else.
private final class ResourceBundleToken {}

/// Ported from packages/tabpet/src/animals/squirrel.ts - every number here must
/// equal the TypeScript profile; conformance/animals.json checks this in CI.
public enum TabPetAnimalSquirrel {
    public static let profile: CompanionProfile = CompanionProfile(
        id: "squirrel",
        label: "squirrel",
        runFps: 24,
        commitSpring: SpringConfig(duration: 400, dampingRatio: 0.78),
        trackSpring: SpringConfig(duration: 220, dampingRatio: 0.82),
        catchSpring: SpringConfig(duration: 240, dampingRatio: 0.9),
        hopHeight: -14,
        flightLift: 0,
        scale: 0.85,
        aroundRoute: true,
        headPad: 9,
        sheets: sheets()
    )

    /// The credit line a host shows; LICENSE-ART.md's squirrel clause
    /// designates "Created with Grok" for attribution alongside "tabpet" -
    /// the only animal that carries it.
    public static let attribution: String = "tabpet, CC BY 4.0. Created with Grok"

    /// Full bundled LICENSE-ART.md text; "" if it can't be read.
    public static let licenseText: String = readLicenseText()

    @MainActor
    public static func register(in registry: CompanionRegistry = .shared) {
        registry.register(profile)
    }

    private static let bundleName = "TabPet_TabPetAnimalSquirrel.bundle"

    /// nil (never traps) if this target's resource bundle can't be found.
    private static let resourceBundle: Bundle? = ResourceBundleLocator.find(
        bundleName: bundleName, tokenType: ResourceBundleToken.self
    )

    /// nil (never traps) if a sheet URL cannot be resolved from the bundle.
    private static func sheets() -> CompanionSheets? {
        guard
            let bundle = resourceBundle,
            let idle = bundle.url(forResource: "squirrel-idle-sprite", withExtension: "png"),
            let run = bundle.url(forResource: "squirrel-run-sprite", withExtension: "png"),
            let sit = bundle.url(forResource: "squirrel-sit-sprite", withExtension: "png")
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
