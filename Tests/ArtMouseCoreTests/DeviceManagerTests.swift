import XCTest
@testable import ArtMouseCore

final class DeviceManagerTests: XCTestCase {
    func testRefreshPopulatesDevices() {
        let fixture = [
            HIDDeviceIdentity(vendorID: 0x046D, productID: 0xB019, name: "MX Master", transport: "Bluetooth"),
            HIDDeviceIdentity(vendorID: 0x05AC, productID: 0x030D, name: "Mighty Mouse", transport: "USB"),
        ]
        let manager = DeviceManager(enumerator: MockEnumerator(result: fixture))
        manager.refresh()
        XCTAssertEqual(manager.devices, fixture)
    }

    func testSettingsKeyFormat() {
        let id = HIDDeviceIdentity(vendorID: 1133, productID: 45081, name: "x", transport: "USB")
        XCTAssertEqual(id.settingsKey, "1133_45081")
    }
}

private struct MockEnumerator: HIDDeviceEnumerating {
    let result: [HIDDeviceIdentity]
    func currentPointingDevices() -> [HIDDeviceIdentity] { result }
}
