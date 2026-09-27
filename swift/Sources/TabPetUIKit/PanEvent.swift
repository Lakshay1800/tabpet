#if canImport(UIKit)
/// Whether the bar's own scrub rides along (`native`) or is cancelled and
/// the observer alone chases (`exclusive`).
public enum BarScrubMode: Sendable {
    case native
    case exclusive
}

/// Mirrors UIGestureRecognizer.State, collapsed to what callers act on:
/// `.changed` becomes `moved`, `.cancelled`/`.failed` become `cancelled`,
/// every other state emits nothing.
public enum PanPhase: String, Sendable, Codable {
    case began
    case moved
    case ended
    case cancelled
}

/// Window-space finger x and the pan phase at that sample.
public struct PanEvent: Equatable, Sendable {
    public let x: Double
    public let phase: PanPhase

    public init(x: Double, phase: PanPhase) {
        self.x = x
        self.phase = phase
    }
}
#endif
