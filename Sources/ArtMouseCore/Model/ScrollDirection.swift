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

extension ScrollDirection {
    /// The direction a wheel tick represents: positive ticks scroll up
    /// (vertical) / right (horizontal), negative ticks the opposite. Shared
    /// derivation for the router's binding lookup and ScrollController's
    /// disposition (Task 6 review consolidation ruling). Zero ticks derive
    /// .down/.left — both callers guard zero before deriving.
    static func derived(axis: ScrollAxis, ticks: Double) -> ScrollDirection {
        switch axis {
        case .vertical: return ticks > 0 ? .up : .down
        case .horizontal: return ticks > 0 ? .right : .left
        }
    }
}
