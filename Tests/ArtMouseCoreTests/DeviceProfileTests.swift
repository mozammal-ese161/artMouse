import XCTest
import ArtMouseCore

final class DeviceProfileTests: XCTestCase {
    private let phase3JSON = """
    {"schemaVersion":1,"cursorSpeedProfiles":[],"activeCursorSpeedProfileID":null,
     "precisionProfileID":null,"buttonBindings":[],"scrollBindings":[],"chords":[],
     "appProfiles":[]}
    """

    func testPhase3SettingsDecodeWithEmptyDeviceFields() throws {
        // Review Focus 4: a Phase 1–3 settings.json has no deviceProfiles or
        // disabledDeviceKeys; decode must default both, not fail.
        let settings = try JSONDecoder().decode(GlobalSettings.self, from: Data(phase3JSON.utf8))
        XCTAssertTrue(settings.deviceProfiles.isEmpty)
        XCTAssertTrue(settings.disabledDeviceKeys.isEmpty)
    }

    func testDeviceProfileRoundTrip() throws {
        var profile = DeviceProfile(name: "Trackball", vendorID: 0x046D, productID: 0xB010)
        profile.parts = [DevicePart(name: "Ball", kind: .wheel, usagePage: 0x01, usage: 0x38),
                         DevicePart(name: "Pedal 1", kind: .pedal, usagePage: 0x09, usage: 0x11,
                                    routesAsButton: 5)]
        profile.rawButtonCapture = true
        profile.dpi = DeviceDPIConfig(levels: [800, 1600, 3200], activeLevelIndex: 1,
                                      reportID: 5, valueByte: 2, valueMask: 0xFFFF, reportLength: 8)
        var settings = GlobalSettings.default
        settings.deviceProfiles = [profile]
        settings.disabledDeviceKeys = ["1_2"]
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(GlobalSettings.self, from: data)
        XCTAssertEqual(decoded.deviceProfiles, [profile])
        XCTAssertEqual(decoded.disabledDeviceKeys, ["1_2"])
    }

    func testProfileMatchingByVendorProduct() {
        var settings = GlobalSettings.default
        let profile = DeviceProfile(name: "Mouse", vendorID: 111, productID: 222)
        settings.deviceProfiles = [profile]
        XCTAssertEqual(settings.deviceProfile(matchingVendor: 111, productID: 222), profile)
        XCTAssertNil(settings.deviceProfile(matchingVendor: 111, productID: 223))
    }

    func testDisabledDeviceKeyCheck() {
        var settings = GlobalSettings.default
        settings.disabledDeviceKeys = ["111_222"]
        XCTAssertTrue(settings.isDeviceDisabled(vendorID: 111, productID: 222))
        XCTAssertFalse(settings.isDeviceDisabled(vendorID: 111, productID: 223))
    }

    func testSettingsKeyStaticMatchesInstanceFormat() {
        XCTAssertEqual(HIDDeviceIdentity.settingsKey(vendorID: 12, productID: 34), "12_34")
        let identity = HIDDeviceIdentity(vendorID: 12, productID: 34, name: "m", transport: "USB")
        XCTAssertEqual(identity.settingsKey, HIDDeviceIdentity.settingsKey(vendorID: 12, productID: 34))
    }

    func testPartDefaultsAreInert() {
        // A part with no routesAsButton routes as nothing; defaults exist so the
        // profile editor can create rows cheaply.
        let part = DevicePart(name: "Extra", kind: .button, usagePage: 0x09, usage: 0x10)
        XCTAssertNil(part.routesAsButton)
        let dpi = DeviceDPIConfig(levels: [800])
        XCTAssertEqual(dpi.activeLevelIndex, 0)
        XCTAssertEqual(dpi.reportLength, 8)
    }
}
