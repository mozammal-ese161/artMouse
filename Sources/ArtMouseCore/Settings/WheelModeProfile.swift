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
    /// Free-spin momentum (Phase 4): after the wheel goes quiet in constant
    /// mode, the emitter coasts with decaying steps. Constant mode only —
    /// it is the one mode that eats the OS's own momentum ticks.
    public var freeSpinMomentum: Bool
    public var momentumDecayPercent: Int
    public var momentumMaxTicks: Int

    public init(id: UUID = UUID(), name: String, mode: ScrollMode = .acceleration,
                sensFactor: Double = 1.0, acceleration: Double = 0.0, lines: Double = 3.0,
                intervalMS: Int = 100, reverseVertical: Bool = false, reverseHorizontal: Bool = false,
                smoothScroll: Bool = false, smoothIntervalMS: Int = 16,
                keyEmulation: WheelKeyEmulation? = nil, autoIntervalMS: Int = 50,
                autoStopTicks: Int = 5, freeSpinMomentum: Bool = false,
                momentumDecayPercent: Int = 70, momentumMaxTicks: Int = 30) {
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
        self.freeSpinMomentum = freeSpinMomentum
        self.momentumDecayPercent = momentumDecayPercent
        self.momentumMaxTicks = momentumMaxTicks
    }
}

/// Backward-compatible decoding (Phase 4): a pre-Phase-4 wheel profile JSON
/// lacks the momentum keys, so absent keys default to the inert values
/// (momentum off) instead of failing the whole decode. Lives in an extension
/// so the explicit initializer above stays untouched.
extension WheelModeProfile {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        mode = try c.decode(ScrollMode.self, forKey: .mode)
        sensFactor = try c.decode(Double.self, forKey: .sensFactor)
        acceleration = try c.decode(Double.self, forKey: .acceleration)
        lines = try c.decode(Double.self, forKey: .lines)
        intervalMS = try c.decode(Int.self, forKey: .intervalMS)
        reverseVertical = try c.decode(Bool.self, forKey: .reverseVertical)
        reverseHorizontal = try c.decode(Bool.self, forKey: .reverseHorizontal)
        smoothScroll = try c.decode(Bool.self, forKey: .smoothScroll)
        smoothIntervalMS = try c.decode(Int.self, forKey: .smoothIntervalMS)
        keyEmulation = try c.decodeIfPresent(WheelKeyEmulation.self, forKey: .keyEmulation)
        autoIntervalMS = try c.decode(Int.self, forKey: .autoIntervalMS)
        autoStopTicks = try c.decode(Int.self, forKey: .autoStopTicks)
        // Phase 4: absent in earlier files → inert defaults (backward compat).
        freeSpinMomentum = try c.decodeIfPresent(Bool.self, forKey: .freeSpinMomentum) ?? false
        momentumDecayPercent = try c.decodeIfPresent(Int.self, forKey: .momentumDecayPercent) ?? 70
        momentumMaxTicks = try c.decodeIfPresent(Int.self, forKey: .momentumMaxTicks) ?? 30
    }
}
