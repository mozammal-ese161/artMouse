public struct HIDDeviceIdentity: Equatable, Hashable {
    public var vendorID: Int
    public var productID: Int
    public var name: String
    public var transport: String

    /// Stable settings key ("vid_pid") used for enable/disable sets and
    /// future device profiles.
    public var settingsKey: String { "\(vendorID)_\(productID)" }

    public init(vendorID: Int, productID: Int, name: String, transport: String) {
        self.vendorID = vendorID
        self.productID = productID
        self.name = name
        self.transport = transport
    }
}
