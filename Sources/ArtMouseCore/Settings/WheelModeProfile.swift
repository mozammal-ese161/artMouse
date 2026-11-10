import Foundation

public enum ScrollMode: String, Codable, CaseIterable {
    case acceleration, constant, auto
}

/// Wheel→keyboard emulation: while the wheel rolls, hold/repeat a key.
public struct WheelKeyEmulation: Codable, Equatable {
    public var keyCode: UInt64
    public var mods: ModKeys
    public var repeatWhileRolling: Bool

    public init(keyCode: UInt64, mods: ModKeys = [], repeatWhileRolling: Bool = true) {
        self.keyCode = keyCode
        self.mods = mods
        self.repeatWhileRolling = repeatWhileRolling
    }
}

public struct WheelModeProfile: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var mode: ScrollMode
    public var sensFactor: Double
    public var acceleration: Double
    public var lines: Double
    public var intervalMS: Int
    public var reverseVertical: Bool
    public var reverseHorizontal: Bool
    public var smoothScroll: Bool
    public var smoothIntervalMS: Int
    public var keyEmulation: WheelKeyEmulation?
    public var autoIntervalMS: Int
    public var autoStopTicks: Int

    public init(id: UUID = UUID(), name: String, mode: ScrollMode = .acceleration,
                sensFactor: Double = 1.0, acceleration: Double = 0.0, lines: Double = 3.0,
                intervalMS: Int = 100, reverseVertical: Bool = false, reverseHorizontal: Bool = false,
                smoothScroll: Bool = false, smoothIntervalMS: Int = 16,
                keyEmulation: WheelKeyEmulation? = nil, autoIntervalMS: Int = 50,
                autoStopTicks: Int = 5) {
        self.id = id
        self.name = name
        self.mode = mode
        self.sensFactor = sensFactor
        self.acceleration = acceleration
        self.lines = lines
        self.intervalMS = intervalMS
        self.reverseVertical = reverseVertical
        self.reverseHorizontal = reverseHorizontal
        self.smoothScroll = smoothScroll
        self.smoothIntervalMS = smoothIntervalMS
        self.keyEmulation = keyEmulation
        self.autoIntervalMS = autoIntervalMS
        self.autoStopTicks = autoStopTicks
    }
}
