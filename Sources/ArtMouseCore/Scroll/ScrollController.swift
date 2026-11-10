import Foundation

/// Resolves native scroll events against the active WheelModeProfile.
/// All user-facing numbers are clamped HERE (the engine boundary) so absurd
/// settings can never run away.
public final class ScrollController: ScrollControlling, WheelModeSwitching {
    static let accelerationReferenceTicks = 3.0

    private let store: SettingsStore
    private let emitter: ScrollEmitter
    private let clock: () -> Double
    /// Frontmost-app source for per-app wheel-profile resolution (Phase 3
    /// Task 5); nil means every scroll uses the global chain.
    private let watcher: FrontmostProviding?
    /// The direction currently auto-scrolling (nil = not in auto).
    private var autoDirection: ScrollDirection?

    public init(store: SettingsStore, emitter: ScrollEmitter,
                clock: @escaping () -> Double = { Date().timeIntervalSince1970 },
                watcher: FrontmostProviding? = nil) {
        self.store = store
        self.emitter = emitter
        self.clock = clock
        self.watcher = watcher
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
        // Fix round 1: a live auto must not survive the profile switch.
        emitter.stop()
        autoDirection = nil
    }

    public func disposition(forScroll axis: ScrollAxis, ticks: Double) -> ScrollDisposition {
        guard ticks != 0 else { return .passThrough }   // native momentum events can carry zero deltas
        guard let profile = store.settings.effectiveWheelProfile(for: watcher?.frontmostBundleID) else { return .passThrough }
        let sens = profile.sensFactor.clamped(0.1...10.0)
        let accel = profile.acceleration.clamped(0...10.0)
        let lines = profile.lines.clamped(0...100.0)
        let autoInterval = Int(Double(profile.autoIntervalMS).clamped(8...1000))
        let stopTicks = Int(Double(profile.autoStopTicks).clamped(1...100))

        var direction = Self.direction(axis: axis, ticks: ticks)
        // Reverse applies to EVERY mode: flipping the derived direction up
        // front means keys/smooth/constant/auto intercepts and the
        // acceleration scale all travel the reversed way (fix round: reverse
        // used to be consulted only in scaleOutcome).
        if (axis == .vertical && profile.reverseVertical)
            || (axis == .horizontal && profile.reverseHorizontal) {
            direction = direction.flipped
        }

        // Trackball convention (global option, spec A.4): thumb-operated
        // trackballs report horizontal deltas mirrored; flip the sign.
        if axis == .horizontal && store.settings.trackballHorizontalFlip {
            direction = direction.flipped
        }

        // 1. Wheel→keys takes absolute precedence.
        if let keys = profile.keyEmulation {
            if autoDirection != nil { emitter.stop(); autoDirection = nil }   // fix round 1: end a live auto
            emitter.beginKeys(keys, direction: direction, now: clock())
            return .intercept
        }
        // 2. Smooth scroll overlay.
        if profile.smoothScroll {
            if autoDirection != nil { emitter.stop(); autoDirection = nil }   // fix round 1: end a live auto
            // Notch distance matches Constant mode: lines per notch × sens ×
            // accel factor × rolled ticks (fix round: the total used to ignore
            // lines, so Smooth moved 1 line where Constant moved 3).
            let magnitude = Double(abs(ticks))
            let total = lines * sens * (1 + accel * (magnitude / Self.accelerationReferenceTicks)) * magnitude
            emitter.beginSmooth(direction: direction, lines: total,
                                intervalMS: Int(Double(profile.smoothIntervalMS).clamped(8...1000)),
                                now: clock())
            return .intercept
        }
        // 3. Modes.
        switch profile.mode {
        case .acceleration:
            if autoDirection != nil { emitter.stop(); autoDirection = nil }   // fix round 2: end a live auto
            return Self.scaleOutcome(axis: direction, magnitude: Double(abs(ticks)),
                                     sens: sens, accel: accel)
        case .constant:
            if autoDirection != nil { emitter.stop(); autoDirection = nil }   // fix round 1: end a live auto
            emitter.emitOnce(direction: direction, lines: lines)
            emitter.noteInput(now: clock())
            // Free-spin momentum arms here only: constant mode is the one
            // mode that intercepts and thus eats the OS's own momentum ticks
            // (Review Focus 5), so its coast can never double with one.
            if profile.freeSpinMomentum {
                let decay = Int(Double(profile.momentumDecayPercent).clamped(10...95))
                let maxTicks = Int(Double(profile.momentumMaxTicks).clamped(1...100))
                emitter.primeMomentum(direction: direction, linesPerTick: lines,
                                      decayPercent: decay,
                                      maxLines: lines * Double(maxTicks), now: clock())
            }
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

    /// Thin wrapper over the shared derivation (ScrollDirection.derived) —
    /// kept as the controller-local name for its call sites above.
    static func direction(axis: ScrollAxis, ticks: Double) -> ScrollDirection {
        ScrollDirection.derived(axis: axis, ticks: ticks)
    }

    /// Sign and magnitude of the acceleration scale for one tick. `axis` is
    /// the (already reverse-flipped) direction, so the sign comes from the
    /// direction itself and the non-ticked axis stays at 1.0.
    static func scaleOutcome(axis: ScrollDirection, magnitude: Double, sens: Double,
                             accel: Double) -> ScrollDisposition {
        let accelFactor = 1 + accel * (magnitude / accelerationReferenceTicks)
        let factor = sens * accelFactor * axis.sign
        var vertical = 1.0
        var horizontal = 1.0
        switch axis.axis {
        case .vertical: vertical = factor
        case .horizontal: horizontal = factor
        }
        return .scale(vertical: vertical, horizontal: horizontal)
    }
}

private extension Double {
    func clamped(_ range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
