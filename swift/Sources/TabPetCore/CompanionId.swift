/// Companion id allowlist helper, ported from companion-id.ts. Pure, asset-free
/// (the registry needs the sprite sheets) so hydration logic stays testable
/// without pulling images into the test target. TypeScript's `CompanionId`
/// (`type CompanionId = string`) is a plain alias with no shape of its own, so
/// it is not carried over as a separate Swift type - callers use `String`
/// directly, and this enum keeps the module's name.
public enum CompanionId {
    /// the companion the provider starts on when nothing is stored
    public static let DEFAULT_COMPANION_ID: String = "panda"

    /// allowlist-validates a saved setting value, defaulting to `fallback` for anything unrecognized.
    /// Compares by UTF-16 code unit exactly, as JavaScript's `Array.includes` does - Swift's `==`
    /// treats canonically equivalent strings (e.g. precomposed vs. decomposed "café") as equal,
    /// which would accept an id the TypeScript allowlist would reject.
    public static func resolveCompanionId(value: Any?, known: [String], fallback: String) -> String {
        if let stringValue = value as? String, known.contains(where: { $0.utf16.elementsEqual(stringValue.utf16) }) {
            return stringValue
        }
        return fallback
    }
}
