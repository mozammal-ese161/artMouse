import Foundation

/// One HID input-value observation, normalized from the observer glue. The
/// glue is the only producer (main queue); the translator and the analyzer
/// consume it.
public struct RawHIDObservation: Equatable {
    public var vendorID: Int
    public var productID: Int
    public var usagePage: Int
    public var usage: Int
    /// Element value: 1/0 for button press/release, signed deltas for wheels.
    public var value: Int

    public init(vendorID: Int, productID: Int, usagePage: Int, usage: Int, value: Int) {
        self.vendorID = vendorID
        self.productID = productID
        self.usagePage = usagePage
        self.usage = usage
        self.value = value
    }
}

/// The handful of HID pages/usages the pipeline reasons about.
public enum HIDUsage {
    public static let buttonPage = 0x09
    public static let genericDesktopPage = 0x01
    /// GD_Wheel — the physical wheel; macOS already delivers it as scrollWheel.
    public static let gdWheel = 0x38
    /// GD_AC_Pan — horizontal tilt; macOS delivers tilt on most devices as a
    /// horizontal scrollWheel event.
    public static let gdACPan = 0x238
}
