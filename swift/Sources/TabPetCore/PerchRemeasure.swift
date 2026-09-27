/// Bounded retry for a measurement that can be momentarily unavailable (the
/// native tab bar hasn't laid out yet on first focus), ported from
/// perch-remeasure.ts. TabPetCore has no frame clock, so unlike the TypeScript
/// (which defaults to `requestAnimationFrame`/`cancelAnimationFrame`), `schedule`
/// and `cancel` are required here; a later milestone supplies a display-link
/// scheduler from the UIKit target.
public enum PerchRemeasure {
    /// Holds the retry loop's mutable state in one MainActor-confined object so
    /// the recursive tick closure can capture it strongly without a "mutated
    /// after capture by sendable closure" warning - a local `var` self-referenced
    /// by a `@Sendable` closure can't express that safely, a class property can.
    @MainActor
    private final class Retry<T: Sendable, Handle: Sendable> {
        let measure: @MainActor @Sendable () -> T?
        let onMeasured: @MainActor @Sendable (T) -> Void
        let maxTries: Int
        let schedule: @MainActor @Sendable (@escaping @MainActor @Sendable () -> Void) -> Handle
        let cancel: @MainActor @Sendable (Handle) -> Void

        var tries = 0
        var cancelled = false
        var handle: Handle?

        init(
            measure: @escaping @MainActor @Sendable () -> T?,
            onMeasured: @escaping @MainActor @Sendable (T) -> Void,
            maxTries: Int,
            schedule: @escaping @MainActor @Sendable (@escaping @MainActor @Sendable () -> Void) -> Handle,
            cancel: @escaping @MainActor @Sendable (Handle) -> Void
        ) {
            self.measure = measure
            self.onMeasured = onMeasured
            self.maxTries = maxTries
            self.schedule = schedule
            self.cancel = cancel
        }

        func tick() {
            if cancelled {
                return
            }
            if let value = measure() {
                onMeasured(value)
                return
            }
            tries += 1
            if tries >= maxTries {
                return
            }
            handle = schedule { [self] in tick() }
        }

        func stop() {
            cancelled = true
            if let handle {
                cancel(handle)
            }
        }
    }

    /// Calls `measure()` once per tick until it returns non-nil, then calls
    /// `onMeasured` exactly once and stops. Gives up silently after `maxTries`
    /// nil results. Returns a cancel function that stops the retry and
    /// guarantees `onMeasured` is never called after it runs.
    @MainActor
    public static func retryMeasure<T: Sendable, Handle: Sendable>(
        measure: @escaping @MainActor @Sendable () -> T?,
        onMeasured: @escaping @MainActor @Sendable (T) -> Void,
        maxTries: Int = 60,
        schedule: @escaping @MainActor @Sendable (@escaping @MainActor @Sendable () -> Void) -> Handle,
        cancel: @escaping @MainActor @Sendable (Handle) -> Void
    ) -> @MainActor @Sendable () -> Void {
        let retry = Retry(measure: measure, onMeasured: onMeasured, maxTries: maxTries, schedule: schedule, cancel: cancel)
        retry.handle = retry.schedule { [retry] in retry.tick() }
        return { [retry] in retry.stop() }
    }
}
