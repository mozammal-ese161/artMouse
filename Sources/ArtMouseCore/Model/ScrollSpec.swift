/// Button→scroll action payload. Wheel reparametrization (sensFactor,
/// acceleration, modes) lives in WheelModeProfile — see plan header note.
public struct ScrollSpec: Codable, Equatable, Hashable {
    public var direction: ScrollDirection
    public var mods: ModKeys
    public var lines: Double
    public var intervalMS: Int
    public var continuous: Bool

    public init(direction: ScrollDirection, mods: ModKeys = [], lines: Double = 3,
                intervalMS: Int = 100, continuous: Bool = false) {
        self.direction = direction
        self.mods = mods
        self.lines = lines
        self.intervalMS = intervalMS
        self.continuous = continuous
    }
}
