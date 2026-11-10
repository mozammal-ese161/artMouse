import Foundation

/// Resolves native scroll events against the active WheelModeProfile.
/// All user-facing numbers are clamped HERE (the engine boundary) so absurd
/// settings can never run away.
public final class ScrollController: ScrollControlling {
    static let accelerationReferenceTicks = 3.0

    private let store: SettingsStore
    private let emitter: ScrollEmitter
    private let clock: () -> Double
    /// The direction currently auto-scrolling (nil = not in auto).
    private var autoDirection: ScrollDirection?

    public init(store: SettingsStore, emitter: ScrollEmitter,
                clock: @escaping () -> Double = { Date().timeIntervalSince1970 }) {
        self.store = store
        self.emitter = emitter
        self.clock = clock
    }

    /// Cadence pump for smooth drain and auto emissions — Task 8 wires an
    /// 8 ms timer on the main run loop (.common mode) that calls this.
    public func pumpEmitter() {
        emitter.tick(now: clock())
        if !emitter.isActive { autoDirection = nil }
    }

    public func activateNextWheelMode() {
        let profiles = store.settings.wheelModeProfiles
        guard let current = store.settings.activeWheelProfile,
              let index = profiles.firstIndex(where: { $0.id == current.id }) else { return }
        store.settings.activeWheelModeProfileID = profiles[(index + 1) % profiles.count].id
    }

    public func disposition(forScroll axis: ScrollAxis, ticks: Double) -> ScrollDisposition {
        guard let profile = store.settings.activeWheelProfile else { return .passThrough }
        let sens = profile.sensFactor.clamped(0.1...10.0)
        let accel = profile.acceleration.clamped(0...10.0)
        let lines = profile.lines.clamped(0...100.0)
        let autoInterval = Int(Double(profile.autoIntervalMS).clamped(8...1000))
        let stopTicks = Int(Double(profile.autoStopTicks).clamped(1...100))

        let direction = Self.direction(axis: axis, ticks: ticks)

        // 1. Wheel→keys takes absolute precedence.
        if let keys = profile.keyEmulation {
            emitter.beginKeys(keys, direction: direction, now: clock())
            return .intercept
        }
        // 2. Smooth scroll overlay.
        if profile.smoothScroll {
            let magnitude = Double(abs(ticks))
            let total = magnitude * sens * (1 + accel * (magnitude / Self.accelerationReferenceTicks))
            emitter.beginSmooth(direction: direction, lines: total,
                                intervalMS: Int(Double(profile.smoothIntervalMS).clamped(8...1000)),
                                now: clock())
            return .intercept
        }
        // 3. Modes.
        switch profile.mode {
        case .acceleration:
            return Self.scaleOutcome(axis: axis, ticks: ticks, sens: sens, accel: accel,
                                     reverseVertical: profile.reverseVertical,
                                     reverseHorizontal: profile.reverseHorizontal)
        case .constant:
            emitter.emitOnce(direction: direction, lines: lines)
            emitter.noteInput(now: clock())
            return .intercept
        case .auto:
            if autoDirection != direction || !emitter.isActive {
                emitter.beginAuto(direction: direction, lines: lines, intervalMS: autoInterval,
                                  stopAfterTicks: stopTicks, now: clock())
            } else {
                emitter.noteInput(now: clock())
            }
            autoDirection = direction
            return .intercept
        }
    }

    static func direction(axis: ScrollAxis, ticks: Double) -> ScrollDirection {
        switch axis {
        case .vertical: return ticks > 0 ? .up : .down
        case .horizontal: return ticks > 0 ? .right : .left
        }
    }

    static func scaleOutcome(axis: ScrollAxis, ticks: Double, sens: Double, accel: Double,
                             reverseVertical: Bool, reverseHorizontal: Bool) -> ScrollDisposition {
        let magnitude = Double(abs(ticks))
        let accelFactor = 1 + accel * (magnitude / accelerationReferenceTicks)
        var factor = sens * accelFactor
        if ticks < 0 { factor = -factor }
        var vertical = 1.0
        var horizontal = 1.0
        switch axis {
        case .vertical:
            if reverseVertical { factor = -factor }
            vertical = factor
        case .horizontal:
            if reverseHorizontal { factor = -factor }
            horizontal = factor
        }
        return .scale(vertical: vertical, horizontal: horizontal)
    }
}

private extension Double {
    func clamped(_ range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
