import Foundation
import Combine

public final class DeviceManager: ObservableObject {
    @Published public private(set) var devices: [HIDDeviceIdentity] = []
    private let enumerator: HIDDeviceEnumerating

    public init(enumerator: HIDDeviceEnumerating) {
        self.enumerator = enumerator
    }

    public func refresh() {
        devices = enumerator.currentPointingDevices()
    }
}
