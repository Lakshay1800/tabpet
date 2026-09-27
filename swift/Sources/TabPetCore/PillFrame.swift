/// Window-space frame of the floating pill. Pure data - no UIKit - so a
/// later geometry pass can take it without pulling in TabPetUIKit.
public struct PillFrame: Equatable, Hashable, Codable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}
