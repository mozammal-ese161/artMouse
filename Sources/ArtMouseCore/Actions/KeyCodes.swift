import CoreGraphics

/// ANSI US keycodes used by posted shortcuts (mission, zoom).
public enum KeyCodes {
    public static let upArrow: UInt64 = 126
    public static let downArrow: UInt64 = 125
    public static let leftArrow: UInt64 = 124
    public static let rightArrow: UInt64 = 123
    public static let space: UInt64 = 49
    public static let f4: UInt64 = 130
    public static let f11: UInt64 = 103
    public static let equals: UInt64 = 24
    public static let minus: UInt64 = 27
    public static let f: UInt64 = 3

    public static func digit(_ n: Int) -> UInt64 {
        // ANSI: 1=0x12(18), 2=0x13(19), 3=0x14(20), 4=0x15(21), 5=0x17(23)
        switch n {
        case 1: return 18
        case 2: return 19
        case 3: return 20
        case 4: return 21
        case 5: return 23
        default: return 18
        }
    }
}

public enum CGFlagConversion {
    public static func cgFlags(_ modKeys: ModKeys) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modKeys.contains(.command) { flags.insert(.maskCommand) }
        if modKeys.contains(.control) { flags.insert(.maskControl) }
        if modKeys.contains(.option) { flags.insert(.maskAlternate) }
        if modKeys.contains(.shift) { flags.insert(.maskShift) }
        return flags
    }
}
