/// Late-spring re-entry gate, ported from perch-reentry.ts: Reanimated 4 physical
/// configs can fire `finished` up to ~5s after visual settle, so a stale arrive()
/// would sit the pup mid-air on a newer chase. Generation bumps on every re-entry
/// (focus, blur, new drag/catch); a late arrive applies only when its captured
/// generation is still current.
public enum PerchReentry {
    public static func shouldApplyArrive(callbackGeneration: Int, currentGeneration: Int, mounted: Bool) -> Bool {
        mounted && callbackGeneration == currentGeneration
    }
}
