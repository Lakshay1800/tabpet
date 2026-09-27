/// Direction sign, matching the TypeScript literal type `1 | -1`.
public enum Facing: Int, Sendable, Codable, Hashable, CaseIterable {
    case left = -1
    case right = 1
}
