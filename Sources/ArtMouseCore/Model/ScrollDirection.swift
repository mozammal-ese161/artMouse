public enum ScrollDirection: String, Codable, CaseIterable, Equatable {
    case up, down, left, right

    public var axis: ScrollAxis {
        switch self {
        case .up, .down: return .vertical
        case .left, .right: return .horizontal
        }
    }

    /// Emission sign on the wheel axis for this direction.
    public var sign: Double {
        switch self {
        case .up, .right: return 1
        case .down, .left: return -1
        }
    }
}
