import Foundation

/// Spring timing for a companion motion leg, ported from registry.ts's `SpringConfig`.
public struct SpringConfig: Equatable, Hashable, Codable, Sendable {
    public let duration: Double
    public let dampingRatio: Double

    public init(duration: Double, dampingRatio: Double) {
        self.duration = duration
        self.dampingRatio = dampingRatio
    }
}

/// Sprite sheet grid and playback rate, ported from registry.ts's `SheetGeometry`.
public struct SheetGeometry: Equatable, Hashable, Codable, Sendable {
    public let cols: Int
    public let rows: Int
    /// populated cells; a grid may carry an unused trailing cell
    public let frames: Int
    public let fps: Double

    public init(cols: Int, rows: Int, frames: Int, fps: Double) {
        self.cols = cols
        self.rows = rows
        self.frames = frames
        self.fps = fps
    }
}

/// Sprite sheet grid without a playback rate, ported from sheet-geometry.ts's
/// `RUN_SHEET_GRID` shape (`Omit<SheetGeometry, 'fps'>`) - the run sheet's fps
/// is per-animal (`profile.runFps`), so this type carries no `fps` field.
public struct SheetGridWithoutFPS: Equatable, Hashable, Codable, Sendable {
    public let cols: Int
    public let rows: Int
    /// populated cells; a grid may carry an unused trailing cell
    public let frames: Int

    public init(cols: Int, rows: Int, frames: Int) {
        self.cols = cols
        self.rows = rows
        self.frames = frames
    }
}

/// Static sheet sources for a companion's idle/run/sit sprite sheets, ported
/// from registry.ts's `CompanionProfile.sheets`. Nothing in TabPetCore loads
/// an image from these URLs.
public struct CompanionSheets: Equatable, Hashable, Codable, Sendable {
    public let idle: URL
    public let run: URL
    public let sit: URL

    public init(idle: URL, run: URL, sit: URL) {
        self.idle = idle
        self.run = run
        self.sit = sit
    }
}

/// Companion catalog entry, ported from registry.ts's `CompanionProfile`.
public struct CompanionProfile: Equatable, Hashable, Codable, Sendable {
    public let id: String
    /// lowercase noun, fits "Your companion {label}" accessibility sentences
    public let label: String
    public let runFps: Double
    /// tab-change commit chase spring
    public let commitSpring: SpringConfig
    /// live glass-drag tracking spring
    public let trackSpring: SpringConfig
    /// release-to-seat catch spring
    public let catchSpring: SpringConfig
    /// hop peak in pt, negative = up; 0 = never hops
    public let hopHeight: Double
    /// pt lifted off the bar line while pose is 'run'; 0 = stays grounded
    public let flightLift: Double
    /// Render-size multiplier, applied identically to every pose layer in one
    /// transform alongside the facing mirror; 1 = reference size.
    public let scale: Double
    /// First-slot <-> last-slot taps take the scenic route around the pill;
    /// ground animals only, ignored when flightLift > 0 or there's no pill.
    public let aroundRoute: Bool
    /// Empty pt above the run-cell drawing at reference size. Default when omitted: 0.
    public let headPad: Double?
    /// Empty pt between the drawing's ground contact and the sit-cell bottom
    /// at reference size. Default when omitted: 11.
    public let footPad: Double?
    /// Pt the ground contact sits above the measured bar top. Default when omitted: 6.
    public let seatLift: Double?
    /// Ground speed in pt/s for the tab-tap run leg. Default when omitted: 340;
    /// see `resolvedRunSpeed` (PerchGeometry.TRAVERSE_SPEED_PT_S).
    public let runSpeed: Double?
    /// Sit sheet grid and playback rate. Default when omitted: 5x5x25 @ 12fps.
    public let sitSheet: SheetGeometry?
    /// Static idle/run/sit sheet sources; nil where the resource bundle
    /// cannot be found. Nothing in TabPetCore loads an image from it.
    public let sheets: CompanionSheets?

    public init(
        id: String,
        label: String,
        runFps: Double,
        commitSpring: SpringConfig,
        trackSpring: SpringConfig,
        catchSpring: SpringConfig,
        hopHeight: Double,
        flightLift: Double,
        scale: Double,
        aroundRoute: Bool,
        headPad: Double? = nil,
        footPad: Double? = nil,
        seatLift: Double? = nil,
        runSpeed: Double? = nil,
        sitSheet: SheetGeometry? = nil,
        sheets: CompanionSheets? = nil
    ) {
        self.id = id
        self.label = label
        self.runFps = runFps
        self.commitSpring = commitSpring
        self.trackSpring = trackSpring
        self.catchSpring = catchSpring
        self.hopHeight = hopHeight
        self.flightLift = flightLift
        self.scale = scale
        self.aroundRoute = aroundRoute
        self.headPad = headPad
        self.footPad = footPad
        self.seatLift = seatLift
        self.runSpeed = runSpeed
        self.sitSheet = sitSheet
        self.sheets = sheets
    }
}

extension CompanionProfile {
    /// TS: SPRITE_FOOT_PAD in companion-perch.tsx - shared default `footPad`.
    public static let SPRITE_FOOT_PAD: Double = 11
    /// TS: BAR_TOP_ABOVE_INSET in companion-perch.tsx - shared default `seatLift`.
    public static let BAR_TOP_ABOVE_INSET: Double = 6
    /// TS: DEFAULT_SIT_SHEET in sheet-geometry.ts - shared default `sitSheet`.
    public static let DEFAULT_SIT_SHEET = SheetGeometry(cols: 5, rows: 5, frames: 25, fps: 12)
    /// TS: IDLE_SHEET_GRID in sheet-geometry.ts - every animal's idle grid.
    public static let IDLE_SHEET_GRID = SheetGeometry(cols: 5, rows: 5, frames: 25, fps: 12)
    /// TS: RUN_SHEET_GRID in sheet-geometry.ts - the shared run grid (fps is
    /// per-animal, `profile.runFps`, so the TS type omits it; this mirrors
    /// that shape, not `SheetGeometry`).
    public static let RUN_SHEET_GRID = SheetGridWithoutFPS(cols: 4, rows: 3, frames: 11)

    public var resolvedFootPad: Double { footPad ?? Self.SPRITE_FOOT_PAD }
    public var resolvedSeatLift: Double { seatLift ?? Self.BAR_TOP_ABOVE_INSET }
    /// TS applies this default inline (`profile.headPad ?? 0` in companion-perch.tsx) - no named constant to mirror.
    public var resolvedHeadPad: Double { headPad ?? 0 }
    public var resolvedRunSpeed: Double { runSpeed ?? PerchGeometry.TRAVERSE_SPEED_PT_S }
    public var resolvedSitSheet: SheetGeometry { sitSheet ?? Self.DEFAULT_SIT_SHEET }
}

/// Companion catalog, ported from registry.ts: a runtime registry of animal
/// profiles, empty by default. The six built-in animals are not registered
/// here - they need their sprite sheets, which arrive with the asset targets.
@MainActor
public final class CompanionRegistry {
    public static let shared = CompanionRegistry()

    private var profiles: [String: CompanionProfile] = [:]
    /// insertion order, so `list`/`ids` match `Object.values`/`Object.keys` -
    /// re-registering an existing id overwrites in place, it does not move to the end.
    private var order: [String] = []

    public init() {}

    /// Registers (or overwrites) a profile at runtime - the extension point for
    /// a host app adding animals beyond the six shipped built-ins.
    public func register(_ profile: CompanionProfile) {
        if profiles[profile.id] == nil {
            order.append(profile.id)
        }
        profiles[profile.id] = profile
    }

    public func get(_ id: String) -> CompanionProfile? {
        profiles[id]
    }

    public func list() -> [CompanionProfile] {
        order.compactMap { profiles[$0] }
    }

    public func ids() -> [String] {
        order
    }
}
