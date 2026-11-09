import Foundation

public enum ProfileSwitchSource: Equatable {
    case user
    case buttonAction
}

/// Cursor operations the executor forwards button-assigned device ops to
/// (Task 13); kept separate from the router's `CursorControlling` transform API.
public protocol CursorCoordinating: AnyObject {
    func activateNext(source: ProfileSwitchSource)
    func beginPrecision()
    func endPrecision()
}

/// Resolves cursor speed profiles into event transforms; owns profile
/// switching, precision hold, and the 5 s safety restore (spec §7).
public final class CursorController: CursorControlling, CursorCoordinating {
    static let safetyRestoreDelay: Double = 5.0
    static let restoreWarningText = "Cursor speed was switched by a button. Restoring the previous speed in 5 seconds."

    private let store: SettingsStore
    private let clock: () -> Double

    private var pendingRestore: (target: UUID, at: Double)?
    private var precisionActive = false
    private(set) public var safetyRestoreWarning: String?

    public init(store: SettingsStore, clock: @escaping () -> Double = { Date().timeIntervalSince1970 }) {
        self.store = store
        self.clock = clock
    }

    public var activeProfile: CursorSpeedProfile? {
        store.settings.activeProfile
    }

    public func outcome(forMove event: InputEvent) -> RouterOutcome {
        let (dx, dy): (Double, Double)
        switch event {
        case .moved(let x, let y), .dragged(let x, let y): (dx, dy) = (x, y)
        default: return .passThrough
        }
        guard let resolved = effectiveProfile() else { return .passThrough }
        let profile = clampedProfile(resolved)
        let speed = (dx * dx + dy * dy).squareRoot()
        let factor = CursorMath.deltaFactor(profile: profile, speed: speed)
        return .cursorTransform(dxFactor: factor.dxFactor, dyFactor: factor.dyFactor)
    }

    public func activate(profileID: UUID, source: ProfileSwitchSource) {
        switch source {
        case .user:
            pendingRestore = nil
            safetyRestoreWarning = nil
        case .buttonAction:
            if pendingRestore == nil, let current = store.settings.activeProfile?.id {
                pendingRestore = (target: current, at: clock() + Self.safetyRestoreDelay)
                safetyRestoreWarning = Self.restoreWarningText
            } else if pendingRestore != nil {
                pendingRestore?.at = clock() + Self.safetyRestoreDelay   // re-arm
            }
        }
        store.settings.activeCursorSpeedProfileID = profileID
    }

    public func activateNext(source: ProfileSwitchSource) {
        let profiles = store.settings.cursorSpeedProfiles
        guard let current = activeProfile,
              let index = profiles.firstIndex(where: { $0.id == current.id }) else { return }
        let next = profiles[(index + 1) % profiles.count]
        activate(profileID: next.id, source: source)
    }

    public func beginPrecision() { precisionActive = true }
    public func endPrecision() { precisionActive = false }

    /// Called on a timer (engine wiring, Task 15) to fire due restores.
    public func tick() {
        guard let restore = pendingRestore, clock() >= restore.at else { return }
        store.settings.activeCursorSpeedProfileID = restore.target
        pendingRestore = nil
        safetyRestoreWarning = nil
    }

    private func effectiveProfile() -> CursorSpeedProfile? {
        if precisionActive, let id = store.settings.precisionProfileID,
           let match = store.settings.cursorSpeedProfiles.first(where: { $0.id == id }) {
            return match
        }
        return store.settings.activeProfile
    }

    /// UI may transiently hold out-of-range values while editing; the engine
    /// clamps at consumption so absurd input can never cause lockout.
    private func clampedProfile(_ p: CursorSpeedProfile) -> CursorSpeedProfile {
        var copy = p
        copy.sensitivity = Swift.min(Swift.max(copy.sensitivity, 200.0), 6400.0)
        copy.acceleration = Swift.min(Swift.max(copy.acceleration, 0.0), 10.0)
        return copy
    }
}
