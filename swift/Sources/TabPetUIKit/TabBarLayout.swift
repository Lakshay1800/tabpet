#if canImport(UIKit)
import TabPetCore

/// Window-space tab-bar layout: item glyph centers, the visible bar's top
/// edge, and the floating pill's frame when the bar has one.
public struct TabBarLayout: Equatable, Sendable {
    /// window-space x of each item's glyph center, in bar order. Empty means
    /// the caller falls back to PerchGeometry's even split.
    public let centers: [Double]
    /// y of the visible bar's top edge: the pill's rim on iOS 26, else the
    /// buttons' top edge, else the bar's own frame.
    public let top: Double?
    /// the floating pill's frame; nil on classic bars or when none is found.
    public let pill: PillFrame?

    public init(centers: [Double], top: Double?, pill: PillFrame?) {
        self.centers = centers
        self.top = top
        self.pill = pill
    }
}
#endif
