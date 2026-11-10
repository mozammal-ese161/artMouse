import XCTest
import ArtMouseCore

final class HIDEventTranslatorTests: XCTestCase {
    private func observation(page: Int, usage: Int, value: Int,
                             vendorID: Int = 111, productID: Int = 222) -> RawHIDObservation {
        RawHIDObservation(vendorID: vendorID, productID: productID,
                          usagePage: page, usage: usage, value: value)
    }

    // MARK: Review Focus 1 — double-feed protection

    func testNoProfileTranslatesNothing() {
        XCTAssertEqual(HIDEventTranslator.translate(observation(page: 0x09, usage: 0x10, value: 1),
                                                    profile: nil), [])
    }

    func testButtonPageDroppedWithoutCapture() {
        let profile = DeviceProfile(name: "m", vendorID: 111, productID: 222)
        XCTAssertEqual(HIDEventTranslator.translate(observation(page: 0x09, usage: 6, value: 1),
                                                    profile: profile), [])
    }

    func testButtonPageTranslatedWithCapture() {
        var profile = DeviceProfile(name: "m", vendorID: 111, productID: 222)
        profile.rawButtonCapture = true
        // HID button usages are 1-based; CGEvent button numbers are 0-based, so
        // physical button 7 routes as extended(6) — the same number the tap
        // would use for a device that surfaced it (never both: the flag is for
        // devices where the tap does NOT see it).
        XCTAssertEqual(HIDEventTranslator.translate(observation(page: 0x09, usage: 7, value: 1),
                                                    profile: profile),
                       [.buttonDown(.extended(6))])
        XCTAssertEqual(HIDEventTranslator.translate(observation(page: 0x09, usage: 7, value: 0),
                                                    profile: profile),
                       [.buttonUp(.extended(6))])
    }

    func testStandardWheelUsagesAlwaysDropped() {
        var profile = DeviceProfile(name: "m", vendorID: 111, productID: 222)
        profile.rawButtonCapture = true   // capture must NOT reach wheel usages either
        XCTAssertEqual(HIDEventTranslator.translate(observation(page: 0x01, usage: HIDUsage.gdWheel, value: -1),
                                                    profile: profile), [])
        XCTAssertEqual(HIDEventTranslator.translate(observation(page: 0x01, usage: HIDUsage.gdACPan, value: 5),
                                                    profile: profile), [])
    }

    // MARK: Profile parts

    func testButtonPartRoutesAsConfigured() {
        let profile = DeviceProfile(name: "m", vendorID: 111, productID: 222, parts: [
            DevicePart(name: "Pedal 1", kind: .pedal, usagePage: 0x0C, usage: 0x0B4, routesAsButton: 9),
        ])
        XCTAssertEqual(HIDEventTranslator.translate(observation(page: 0x0C, usage: 0x0B4, value: 1),
                                                    profile: profile),
                       [.buttonDown(.extended(9))])
        XCTAssertEqual(HIDEventTranslator.translate(observation(page: 0x0C, usage: 0x0B4, value: 0),
                                                    profile: profile),
                       [.buttonUp(.extended(9))])
    }

    func testButtonPartWithoutRoutingTranslatesNothing() {
        let profile = DeviceProfile(name: "m", vendorID: 111, productID: 222, parts: [
            DevicePart(name: "Extra", kind: .button, usagePage: 0x0C, usage: 0x0B4),
        ])
        XCTAssertEqual(HIDEventTranslator.translate(observation(page: 0x0C, usage: 0x0B4, value: 1),
                                                    profile: profile), [])
    }

    func testWheelPartTranslatesScrolledVertical() {
        let profile = DeviceProfile(name: "m", vendorID: 111, productID: 222, parts: [
            DevicePart(name: "Thumb wheel", kind: .wheel, usagePage: 0xFF00, usage: 0x1),
        ])
        XCTAssertEqual(HIDEventTranslator.translate(observation(page: 0xFF00, usage: 0x1, value: -3),
                                                    profile: profile),
                       [.scrolled(axis: .vertical, ticks: -3)])
    }

    func testACPanPartTranslatesHorizontal() {
        let profile = DeviceProfile(name: "m", vendorID: 111, productID: 222, parts: [
            DevicePart(name: "Tilt", kind: .wheel, usagePage: 0x01, usage: HIDUsage.gdACPan),
        ])
        XCTAssertEqual(HIDEventTranslator.translate(observation(page: 0x01, usage: HIDUsage.gdACPan, value: 2),
                                                    profile: profile),
                       [.scrolled(axis: .horizontal, ticks: 2)])
    }

    func testWheelPartZeroValueTranslatesNothing() {
        let profile = DeviceProfile(name: "m", vendorID: 111, productID: 222, parts: [
            DevicePart(name: "Thumb wheel", kind: .wheel, usagePage: 0xFF00, usage: 0x1),
        ])
        XCTAssertEqual(HIDEventTranslator.translate(observation(page: 0xFF00, usage: 0x1, value: 0),
                                                    profile: profile), [])
    }

    func testExplicitPartWinsOverRawCapture() {
        // A part mapped to a button-page usage is authoritative: even with
        // capture on, the part's mapping (not the raw usage-1 rule) applies.
        var profile = DeviceProfile(name: "m", vendorID: 111, productID: 222, parts: [
            DevicePart(name: "Thumb 1", kind: .button, usagePage: 0x09, usage: 0x10, routesAsButton: 7),
        ])
        profile.rawButtonCapture = true
        XCTAssertEqual(HIDEventTranslator.translate(observation(page: 0x09, usage: 0x10, value: 1),
                                                    profile: profile),
                       [.buttonDown(.extended(7))])
    }

    func testUnmappedVendorElementsTranslateNothing() {
        let profile = DeviceProfile(name: "m", vendorID: 111, productID: 222)
        XCTAssertEqual(HIDEventTranslator.translate(observation(page: 0xFF00, usage: 0x42, value: 1),
                                                    profile: profile), [])
    }
}
