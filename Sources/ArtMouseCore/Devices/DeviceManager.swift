import Foundation

/// @Observable so the Devices tab live-updates: the tab reads `devices`
/// through the shared AppModel instance and SwiftUI tracks it on every
/// `refresh()` (the previous ObservableObject/@Published form was observed
/// by nothing — the tab showed a launch-time snapshot forever).
@Observable
public final class DeviceManager {
    public private(set) var devices: [HIDDeviceIdentity] = []
    private let enumerator: HIDDeviceEnumerating

    public init(enumerator: HIDDeviceEnumerating) {
        self.enumerator = enumerator
    }

    public func refresh() {
        devices = enumerator.currentPointingDevices()
    }
}
