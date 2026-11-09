public protocol HIDDeviceEnumerating {
    func currentPointingDevices() -> [HIDDeviceIdentity]
}
