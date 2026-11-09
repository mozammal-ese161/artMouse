import AppKit
import CoreGraphics

/// NX system-defined media key constants (classic SPMediaKeyTap table).
public enum NXMediaKey {
    public static let soundUp: Int64 = 0
    public static let soundDown: Int64 = 1
    public static let mute: Int64 = 7
    public static let eject: Int64 = 14
    public static let rewind: Int64 = 18
    public static let fast: Int64 = 19
    public static let play: Int64 = 20
}

public enum MediaKeySynthesizer {
    /// NSSystemDefinedEventSubtypeMedia = 8; 0x0A key-down, 0x0B key-up.
    public static func makeEvent(keyCode: Int64, keyDown: Bool) -> CGEvent {
        let event = CGEvent(source: nil)!
        event.type = CGEventType(rawValue: UInt32(NSEvent.EventType.systemDefined.rawValue))!
        let data1 = (Int64(8) << 16) | (keyCode << 8) | (keyDown ? 0x0A : 0x0B)
        // SDK adaptation: CGEventField(rawValue:) is failable on this SDK and fields 41/42
        // (system-defined data1/data2) have no named members, so the constant lookup is
        // force-unwrapped; both raw values are always valid.
        event.setIntegerValueField(CGEventField(rawValue: 41)!, value: data1)
        event.setIntegerValueField(CGEventField(rawValue: 42)!, value: keyDown ? -1 : 0)
        return event
    }
}
