import Foundation
import TabPetCore

/// Anchors ResourceBundleLocator's search at this target's own compiled
/// location - never used for anything else.
private final class ResourceBundleToken {}

/// Ported from packages/tabpet/src/animals/turtle.ts - every number here must
/// equal the TypeScript profile; conformance/animals.json checks this in CI.
public enum TabPetAnimalTurtle {
    public static let profile: CompanionProfile = CompanionProfile(
        id: "turtle",
        label: "turtle",
        runFps: 12,
        commitSpring: SpringConfig(duration: 1050, dampingRatio: 1),
        trackSpring: SpringConfig(duration: 700, dampingRatio: 1),
        catchSpring: SpringConfig(duration: 600, dampingRatio: 1),
        hopHeight: 0,
        flightLift: 0,
        scale: 1,
        aroundRoute: false,
        headPad: 24,
        footPad: 6.5,
        runSpeed: 200,
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

    private static let bundleName = "TabPet_TabPetAnimalTurtle.bundle"

    /// nil (never traps) if this target's resource bundle can't be found.
    private static let resourceBundle: Bundle? = ResourceBundleLocator.find(
        bundleName: bundleName, tokenType: ResourceBundleToken.self
    )

    /// nil (never traps) if a sheet URL cannot be resolved from the bundle.
    private static func sheets() -> CompanionSheets? {
        guard
            let bundle = resourceBundle,
            let idle = bundle.url(forResource: "turtle-idle-sprite", withExtension: "png"),
            let run = bundle.url(forResource: "turtle-run-sprite", withExtension: "png"),
            let sit = bundle.url(forResource: "turtle-sit-sprite", withExtension: "png")
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
