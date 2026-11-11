/// Identifiable keyed by the stable settings key so Devices-tab sheets can
/// present identities with `.sheet(item:)` (Phase 4). Two entries for the
/// same VID/PID share an id by design — they are the same physical device.
extension HIDDeviceIdentity: Identifiable {
    public var id: String { settingsKey }
}

public struct HIDDeviceIdentity: Equatable, Hashable {
    public var vendorID: Int
    public var productID: Int
    public var name: String
    public var transport: String

    /// Stable settings key ("vid_pid") used for enable/disable sets and
    /// device profiles.
    public var settingsKey: String { Self.settingsKey(vendorID: vendorID, productID: productID) }

    /// Static form used by settings-code that only has VID/PID (not an
    /// identity struct); the instance property delegates here.
    public static func settingsKey(vendorID: Int, productID: Int) -> String {
        "\(vendorID)_\(productID)"
    }

    public init(vendorID: Int, productID: Int, name: String, transport: String) {
        self.vendorID = vendorID
        self.productID = productID
        self.name = name
        self.transport = transport
    }
}
