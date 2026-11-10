import Foundation

public enum DPIOperation: Equatable {
    case up, down, cycle, restoreDefault
}

/// Applies DPI operations to the active device profile. `applyLevel` both
/// sends the feature report and persists the new `activeLevelIndex`; its Bool
/// is whether the report actually went out — false engages the executor's
/// degradation (spec §3).
public protocol DPICoordinating: AnyObject {
    func apply(_ operation: DPIOperation) -> Bool
    /// Momentary DPI Shift (hold lifecycle): raise one level; `endShift`
    /// restores the pre-shift level. Returns false when unavailable.
    func beginShift() -> Bool
    func endShift()
}

public final class DPIManager: DPICoordinating {
    private let profileProvider: () -> DeviceProfile?
    private let applyLevel: (DeviceProfile, _ level: Int, _ levelIndex: Int) -> Bool
    private var shiftOrigin: Int?

    public init(profileProvider: @escaping () -> DeviceProfile?,
                applyLevel: @escaping (DeviceProfile, _ level: Int, _ levelIndex: Int) -> Bool) {
        self.profileProvider = profileProvider
        self.applyLevel = applyLevel
    }

    public func apply(_ operation: DPIOperation) -> Bool {
        guard let profile = profileProvider(), let config = profile.dpi, !config.levels.isEmpty
        else { return false }
        let current = DPIReportBuilder.clampedLevelIndex(config.activeLevelIndex,
                                                         levelCount: config.levels.count)
        let next: Int
        switch operation {
        case .up: next = min(current + 1, config.levels.count - 1)
        case .down: next = max(current - 1, 0)
        case .cycle: next = (current + 1) % config.levels.count
        case .restoreDefault: next = 0
        }
        return applyLevel(profile, config.levels[next], next)
    }

    public func beginShift() -> Bool {
        guard let profile = profileProvider(), let config = profile.dpi,
              config.levels.count > 1 else { return false }
        let current = DPIReportBuilder.clampedLevelIndex(config.activeLevelIndex,
                                                         levelCount: config.levels.count)
        guard current < config.levels.count - 1 else { return false }
        shiftOrigin = current
        return applyLevel(profile, config.levels[current + 1], current + 1)
    }

    public func endShift() {
        defer { shiftOrigin = nil }
        guard let origin = shiftOrigin, let profile = profileProvider(), let config = profile.dpi,
              config.levels.indices.contains(origin) else { return }
        _ = applyLevel(profile, config.levels[origin], origin)
    }
}
