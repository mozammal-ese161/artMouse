/// Physical button identity. Standard buttons map to CGEvent button numbers
/// (left=0, right=1, middle=2, fourth=3, fifth=4); extended buttons carry
/// their raw number (phase 4 binds them via raw HID).
public enum ButtonID: Hashable, Codable, CaseIterable {
    case left, right, middle, fourth, fifth
    case extended(Int)

    /// Manual synthesis is required because `extended` carries an associated value.
    public static var allCases: [ButtonID] {
        [.left, .right, .middle, .fourth, .fifth]
    }

    /// CGEvent mouse button number used when posting events.
    public var cgButtonNumber: Int {
        switch self {
        case .left: return 0
        case .right: return 1
        case .middle: return 2
        case .fourth: return 3
        case .fifth: return 4
        case .extended(let n): return n
        }
    }
}
