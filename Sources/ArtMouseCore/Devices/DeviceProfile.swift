import Foundation

public enum DevicePartKind: String, Codable, CaseIterable {
    case button, wheel, pedal
}

/// One physical input element of a device, described in HID terms. The part
/// name is user-facing ("Thumb 1", "Pedal 2"). `routesAsButton` carries the
/// CGEvent button NUMBER the element routes as (5...31 = "Button 6"..."Button
/// 32"); it must be nil for wheel parts. Wheel parts translate their element
/// deltas into scrolled events (AC Pan parts map to the horizontal axis).
public struct DevicePart: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var kind: DevicePartKind
    public var usagePage: Int
    public var usage: Int
    public var routesAsButton: Int?

    public init(id: UUID = UUID(), name: String, kind: DevicePartKind,
                usagePage: Int, usage: Int, routesAsButton: Int? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.usagePage = usagePage
        self.usage = usage
        self.routesAsButton = routesAsButton
    }
}

/// Vendor-proprietary DPI feature-report description (spec §3: DPI is only
/// implemented for devices the user owns and can test). The payload layout is
/// declared by the user in the profile editor; `valueByte` is relative to the
/// payload AFTER the report ID byte.
public struct DeviceDPIConfig: Codable, Equatable {
    public var levels: [Int]
    public var activeLevelIndex: Int
    public var reportID: Int
    public var valueByte: Int
    /// AND mask applied to the level value before it is written.
    public var valueMask: Int
    public var reportLength: Int

    public init(levels: [Int], activeLevelIndex: Int = 0, reportID: Int = 0,
                valueByte: Int = 0, valueMask: Int = 0xFFFF, reportLength: Int = 8) {
        self.levels = levels
        self.activeLevelIndex = activeLevelIndex
        self.reportID = reportID
        self.valueByte = valueByte
        self.valueMask = valueMask
        self.reportLength = reportLength
    }
}

/// A user-authored description of one physical device, matched by VID/PID.
/// `rawButtonCapture` opts the WHOLE device into translating HID button-page
/// elements (usages 1–32) as buttons — only for devices whose extra buttons
/// never surface as CGEvents (double-feed protection, Review Focus 1).
public struct DeviceProfile: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var vendorID: Int
    public var productID: Int
    public var parts: [DevicePart]
    public var rawButtonCapture: Bool
    public var dpi: DeviceDPIConfig?

    public init(id: UUID = UUID(), name: String, vendorID: Int, productID: Int,
                parts: [DevicePart] = [], rawButtonCapture: Bool = false,
                dpi: DeviceDPIConfig? = nil) {
        self.id = id
        self.name = name
        self.vendorID = vendorID
        self.productID = productID
        self.parts = parts
        self.rawButtonCapture = rawButtonCapture
        self.dpi = dpi
    }
}
