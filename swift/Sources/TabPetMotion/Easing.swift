/// Ported from react-native-reanimated@4.5.0 src/Easing.ts (MIT, Software
/// Mansion) - see THIRD-PARTY-NOTICES.md. Only the two easings the
/// perch/sprite motion this module drives actually uses: `linear` (the run
/// and route legs) and `inOutQuad` (withTiming's own default - see
/// TimingAnimation.swift).
package enum Easing {
    package static func linear(_ t: Double) -> Double {
        t
    }

    private static func quad(_ t: Double) -> Double {
        t * t
    }

    /// `Easing.ts`'s generic `inOut(easing)` specialized to `quad`, since
    /// that is the only `inOut` curve this module ships: runs `quad`
    /// forwards for the first half of the duration, backwards for the rest.
    package static func inOutQuad(_ t: Double) -> Double {
        if t < 0.5 {
            return quad(t * 2) / 2
        }
        return 1 - quad((1 - t) * 2) / 2
    }
}
