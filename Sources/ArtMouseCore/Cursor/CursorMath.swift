import Foundation

public enum CursorMath {
    /// Sensitivity value that produces a 1.0 scale (macOS default behavior).
    public static let systemNeutralSensitivity = 1600.0
    /// Speed (points/event) at which acceleration contributes +1.0 × acceleration.
    public static let accelerationReferenceSpeed = 8.0

    public static func sensitivityFactor(_ sensitivity: Double) -> Double {
        sensitivity / systemNeutralSensitivity
    }

    /// Linear acceleration curve: exactly 1 at rest, grows with speed.
    /// (v1 curve; reference-exact curves are a later tuning pass.)
    public static func accelerationFactor(acceleration: Double, speed: Double) -> Double {
        1 + acceleration * (speed / accelerationReferenceSpeed)
    }

    public static func deltaFactor(profile: CursorSpeedProfile, speed: Double) -> (dxFactor: Double, dyFactor: Double) {
        let factor = sensitivityFactor(profile.sensitivity) * accelerationFactor(acceleration: profile.acceleration, speed: speed)
        return (factor, factor)
    }
}
