import Foundation

/// Pure translation from a DPI level to a feature-report payload. The report
/// ID is the SetReport selector, NOT part of the payload. All declared layout
/// numbers are clamped here (engine boundary) so an absurd profile can never
/// crash the sender (Review Focus 3).
public enum DPIReportBuilder {
    /// Payload of `reportLength` bytes (>= 1) with the masked level written
    /// little-endian (up to 16 bits) at `valueByte`.
    public static func payload(config: DeviceDPIConfig, level: Int) -> Data {
        let length = max(1, config.reportLength)
        var bytes = [UInt8](repeating: 0, count: length)
        let masked = level & max(0, config.valueMask)
        let index = max(0, config.valueByte)
        if index < length { bytes[index] = UInt8(clamping: masked & 0xFF) }
        if index + 1 < length { bytes[index + 1] = UInt8(clamping: (masked >> 8) & 0xFF) }
        return Data(bytes)
    }

    public static func clampedLevelIndex(_ index: Int, levelCount: Int) -> Int {
        guard levelCount > 0 else { return 0 }
        return Swift.min(Swift.max(index, 0), levelCount - 1)
    }
}
