/// The only place seconds become milliseconds and back. Every real clock
/// adapter (a display link's `targetTimestamp` and dt, both in seconds;
/// `DispatchQueue.asyncAfter`'s seconds-based deadline) converts through
/// here rather than inline, so the conversion itself is covered once.
package enum ClockUnits {
    package static func ms(fromSeconds seconds: Double) -> Double {
        seconds * 1000
    }

    package static func seconds(fromMs ms: Double) -> Double {
        ms / 1000
    }
}
