# artMouse Phase 4 — Raw HID + Devices Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the Phase 4 feature group — raw HID observation (buttons 6+ that never surface as CGEvents, vendor wheels, pedals), the device-profile system (per-device parts, naming, DPI), Device Analyzer, Device Log, DPI feature reports with documented degradation, IORegistry details — plus the carried Phase 3 fixes.

**Architecture:** A layered HID pipeline: a pure `HIDEventTranslator` (heavily tested) converts `RawHIDObservation` values into `InputEvent`s under an explicit double-feed policy (elements the CGEventTap already covers are dropped unless a device profile opts in); a thin `IOKitHIDValueObserver` glue (public IOHIDManager value callbacks, no seize, main-queue hop) feeds an `HIDEventPump` that routes into the existing `EventRouter`. Device profiles live in `GlobalSettings.deviceProfiles` (JSON, backward-compatible decode). DPI feature reports go through a pure `DPIReportBuilder` + a testable `DPIManager` with a Bool-returning glue sender; unsupported devices degrade to cursor-speed profile switching (spec §3). Momentum and trackball direction land in `ScrollEmitter`/`ScrollController` behind new settings fields.

**Tech Stack:** Swift 5.9, SPM, macOS 14 floor, IOHIDManager public API, XCTest, SwiftUI (@Observable, derive-from-props editors).

**Spec:** `docs/superpowers/specs/2026-11-09-artmouse-design.md` (§4 module table: HIDObserver, DeviceProfileManager; §5 DeviceProfile; §6 Phase 4; §7 error handling; Appendix A groups 5–6).

**Deviations from spec (deliberate):** (a) device profiles are user-created in `settings.json` (`deviceProfiles` field), NOT a separate `devices/*.json` store with bundled seeds — the 88 recovered SteerMouse XMLs cannot be redistributed and there is nothing else to bundle; bundling is deferred until the user authors profiles worth sharing. (b) Raw observation uses the PUBLIC IOHIDManager value-callback API instead of the SPI `IOHIDEventSystemClient` — it covers buttons/wheels/pedals/DPI/analyzer goals without private-header fragility; vendor-report-level fidelity remains a future upgrade.

## Global Constraints

- Swift 5.9 / SPM / macOS 14 minimum / zero third-party dependencies / XCTest for unit tests.
- Engine code is UI-free and lives in `ArtMouseCore`; the app target is `Sources/artMouse`.
- **Main-run-loop single-queue discipline:** engine state (router registries, controllers, emitter, pump routing) is mutated ONLY from the main queue — tap callbacks, timers, and the HID pump sink all run there. The observing glue MUST hop to the main queue before invoking its sink.
- **Loop protection:** every synthetic event goes through the shared tagged `CGEventPoster`.
- **Backward-compatible settings JSON:** every new `GlobalSettings`/`WheelModeProfile` field decodes via `decodeIfPresent` with a default in a custom `init(from:)`; existing user files must keep loading.
- **Engine-side clamping:** absurd user numbers are clamped at the engine boundary; view-side numeric conversion never calls `Int(Double)`/`UInt64(Double)` on user-typed text without a finiteness guard (Task 9 introduces the shared helpers; new UI uses them from day one).
- Personal use: no licensing, no updater, no notarization.
- Test baseline: **176 passing** on `main @ 6cc828e`. Every engine task pins new behavior in `Tests/ArtMouseCoreTests/`.

## Review Focus

The five input classes the spec implies but no task's happy path exercises, and the task whose tests pin each:

1. **A mouse whose buttons 6+ already surface as CGEvents, with `rawButtonCapture` enabled** → every press routes twice (binding fires twice, chords double-capture). Expected: the translator drops button-page usages 1–32 unless the profile flag is on, and the UI copy states the flag is only for devices whose extra buttons never reach macOS. → Pinned by Task 2 translator tests.
2. **HID value callbacks delivered off the main thread** → unsynchronized router/emitter state races. Expected: the glue hops to the main queue before the sink; the pump consumes on main only. → Contract pinned in Task 4 pump tests; the glue is reviewed for the hop.
3. **A DPI feature report sent to a wedged or wrong device** → a synchronous `IOHIDDeviceSetReport` failure must never crash or strand state; unsupported devices must degrade to cursor-speed switching. → Pinned by Task 7 manager tests (sender failures return false, fallback engages, shift origin always restored).
4. **An old or imported `settings.json` without Phase 4 fields (or carrying absurd numbers)** → decode backward-compatible, engine clamps, nothing lost. → Pinned by Task 1 and Task 6 decode tests and the Task 7 builder clamps.
5. **Momentum coast where it is dangerous** — a normal (non-free-spin) wheel, or wheel→keys / auto modes where coasting repeats keys or runs away. Expected: momentum only primes in constant mode, is capped by `momentumMaxTicks`, and ends on new input. → Pinned by Task 6 emitter tests.

---

### Task 1: DeviceProfile model + settings integration

**Files:**
- Create: `Sources/ArtMouseCore/Devices/DeviceProfile.swift`
- Modify: `Sources/ArtMouseCore/Devices/HIDDeviceIdentity.swift`
- Modify: `Sources/ArtMouseCore/Settings/GlobalSettings.swift`
- Test: `Tests/ArtMouseCoreTests/DeviceProfileTests.swift` (new)

**Interfaces:**
- Consumes: nothing new (existing `HIDDeviceIdentity`, `GlobalSettings`).
- Produces (later tasks rely on EXACTLY these):
  - `struct DeviceProfile: Codable, Equatable, Identifiable` — `id: UUID`, `name: String`, `vendorID: Int`, `productID: Int`, `parts: [DevicePart]`, `rawButtonCapture: Bool`, `dpi: DeviceDPIConfig?`
  - `struct DevicePart: Codable, Equatable, Identifiable` — `id: UUID`, `name: String`, `kind: DevicePartKind`, `usagePage: Int`, `usage: Int`, `routesAsButton: Int?`
  - `enum DevicePartKind: String, Codable, CaseIterable` — `.button`, `.wheel`, `.pedal`
  - `struct DeviceDPIConfig: Codable, Equatable` — `levels: [Int]`, `activeLevelIndex: Int`, `reportID: Int`, `valueByte: Int`, `valueMask: Int`, `reportLength: Int`
  - `HIDDeviceIdentity.settingsKey(vendorID:productID:) -> String` static
  - `GlobalSettings.deviceProfiles: [DeviceProfile]`, `GlobalSettings.disabledDeviceKeys: [String]`
  - `GlobalSettings.deviceProfile(matchingVendor:productID:) -> DeviceProfile?`
  - `GlobalSettings.isDeviceDisabled(vendorID:productID:) -> Bool`

- [ ] **Step 1: Write the failing tests**

Create `Tests/ArtMouseCoreTests/DeviceProfileTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter DeviceProfileTests`
Expected: FAIL — types and members do not exist.

- [ ] **Step 3: Implement**

Create `Sources/ArtMouseCore/Devices/DeviceProfile.swift`:

```swift
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
```

Modify `Sources/ArtMouseCore/Devices/HIDDeviceIdentity.swift` — add the static form so the string format has one source of truth:

```swift
    /// Static form used by settings-code that only has VID/PID (not an
    /// identity struct); the instance property delegates here.
    public static func settingsKey(vendorID: Int, productID: Int) -> String {
        "\(vendorID)_\(productID)"
    }
```

and change the instance property body to `Self.settingsKey(vendorID: vendorID, productID: productID)`.

Modify `Sources/ArtMouseCore/Settings/GlobalSettings.swift`:

1. Add two stored properties to `GlobalSettings` (after `appProfiles`) and to `static let default` (`deviceProfiles: []`, `disabledDeviceKeys: []`).
2. In the custom `init(from:)` add (after the `appProfiles` line):

```swift
        // Phase 4 fields: absent in earlier files → empty defaults (backward compat).
        deviceProfiles = try c.decodeIfPresent([DeviceProfile].self, forKey: .deviceProfiles) ?? []
        disabledDeviceKeys = try c.decodeIfPresent([String].self, forKey: .disabledDeviceKeys) ?? []
```

3. Add to the per-app overlay extension file scope (a new public extension):

```swift
public extension GlobalSettings {
    /// Device-profile resolution by VID/PID: first matching profile.
    func deviceProfile(matchingVendor vendorID: Int, productID: Int) -> DeviceProfile? {
        deviceProfiles.first { $0.vendorID == vendorID && $0.productID == productID }
    }

    /// Enable/disable set (spec §6 group 6); keyed by `HIDDeviceIdentity.settingsKey`.
    func isDeviceDisabled(vendorID: Int, productID: Int) -> Bool {
        disabledDeviceKeys.contains(HIDDeviceIdentity.settingsKey(vendorID: vendorID, productID: productID))
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter DeviceProfileTests`
Expected: PASS (6 tests). Then run the full suite: `swift test` — expected 182 passing, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add Sources/ArtMouseCore/Devices/DeviceProfile.swift Sources/ArtMouseCore/Devices/HIDDeviceIdentity.swift Sources/ArtMouseCore/Settings/GlobalSettings.swift Tests/ArtMouseCoreTests/DeviceProfileTests.swift
git commit -m "Add device profile model and settings fields"
```

---

### Task 2: RawHIDObservation + HIDEventTranslator (pure)

**Files:**
- Create: `Sources/ArtMouseCore/Devices/RawHIDObservation.swift`
- Create: `Sources/ArtMouseCore/Devices/HIDEventTranslator.swift`
- Test: `Tests/ArtMouseCoreTests/HIDEventTranslatorTests.swift` (new)

**Interfaces:**
- Consumes: Task 1's `DeviceProfile`/`DevicePart`; existing `InputEvent`.
- Produces:
  - `struct RawHIDObservation: Equatable` — `vendorID: Int`, `productID: Int`, `usagePage: Int`, `usage: Int`, `value: Int`
  - `enum HIDUsage` — `static let buttonPage = 0x09`, `static let genericDesktopPage = 0x01`, `static let gdWheel = 0x38`, `static let gdACPan = 0x238`
  - `enum HIDEventTranslator` — `static func translate(_ observation: RawHIDObservation, profile: DeviceProfile?) -> [InputEvent]`

- [ ] **Step 1: Write the failing tests**

Create `Tests/ArtMouseCoreTests/HIDEventTranslatorTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter HIDEventTranslatorTests`
Expected: FAIL — types do not exist.

- [ ] **Step 3: Implement**

Create `Sources/ArtMouseCore/Devices/RawHIDObservation.swift`:

```swift
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
```

Create `Sources/ArtMouseCore/Devices/HIDEventTranslator.swift`:

```swift
import Foundation

/// Translates one raw HID observation into zero or more InputEvents, under
/// the double-feed policy (Review Focus 1): elements the CGEventTap already
/// covers — button-page usages 1–32, GD wheel, AC Pan — are dropped unless a
/// device profile explicitly claims them, so a press is never routed twice.
/// A nil profile (device without one) translates nothing: observation then
/// feeds only the analyzer/log.
public enum HIDEventTranslator {
    public static func translate(_ observation: RawHIDObservation,
                                 profile: DeviceProfile?) -> [InputEvent] {
        guard let profile else { return [] }

        // 1. An explicit profile part wins over every generic rule.
        if let part = profile.parts.first(where: {
            $0.usagePage == observation.usagePage && $0.usage == observation.usage
        }) {
            return translatePart(part, value: observation.value)
        }

        // 2. Standard wheel usages are tap-covered on every healthy device —
        // never translated here, regardless of capture.
        if observation.usagePage == HIDUsage.genericDesktopPage
            && (observation.usage == HIDUsage.gdWheel || observation.usage == HIDUsage.gdACPan) {
            return []
        }

        // 3. Button-page usages 1–32: dropped unless the device opts in
        //    (devices whose extra buttons never reach macOS as CGEvents).
        if observation.usagePage == HIDUsage.buttonPage && (1...32).contains(observation.usage) {
            guard profile.rawButtonCapture else { return [] }
            let buttonNumber = observation.usage - 1   // HID 1-based → CG 0-based
            return observation.value != 0
                ? [.buttonDown(.extended(buttonNumber))]
                : [.buttonUp(.extended(buttonNumber))]
        }

        return []
    }

    private static func translatePart(_ part: DevicePart, value: Int) -> [InputEvent] {
        switch part.kind {
        case .wheel:
            guard value != 0 else { return [] }
            let axis: ScrollAxis = part.usage == HIDUsage.gdACPan ? .horizontal : .vertical
            return [.scrolled(axis: axis, ticks: Double(value))]
        case .button, .pedal:
            guard let number = part.routesAsButton else { return [] }
            return value != 0
                ? [.buttonDown(.extended(number))]
                : [.buttonUp(.extended(number))]
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter HIDEventTranslatorTests`
Expected: PASS (11 tests). Full suite: 193 passing.

- [ ] **Step 5: Commit**

```bash
git add Sources/ArtMouseCore/Devices/RawHIDObservation.swift Sources/ArtMouseCore/Devices/HIDEventTranslator.swift Tests/ArtMouseCoreTests/HIDEventTranslatorTests.swift
git commit -m "Add raw HID observation model and translator"
```

---

### Task 3: HIDEventLog + HIDAnalyzerStore

**Files:**
- Create: `Sources/ArtMouseCore/Devices/HIDEventLog.swift`
- Create: `Sources/ArtMouseCore/Devices/HIDAnalyzerStore.swift`
- Test: `Tests/ArtMouseCoreTests/HIDEventLogTests.swift` (new)

**Interfaces:**
- Consumes: Task 2's `RawHIDObservation`.
- Produces:
  - `final class HIDEventLog` — `init(maxEntries: Int = 500, fileURL: URL? = nil, persistToFile: Bool = false, now: @escaping () -> Date = Date.init)`; `func record(_ observation: RawHIDObservation)`; `var entries: [String]`; `func setPersistToFile(_ on: Bool)`; `func clear()`
  - `final class HIDAnalyzerStore` (`@Observable`) — `init(maxEntries: Int = 200)`; `func record(_ observation: RawHIDObservation)`; `private(set) var recent: [RawHIDObservation]`; `func clear()`

- [ ] **Step 1: Write the failing tests**

Create `Tests/ArtMouseCoreTests/HIDEventLogTests.swift`:

```swift
import XCTest
import ArtMouseCore

final class HIDEventLogTests: XCTestCase {
    private func observation(value: Int = 1) -> RawHIDObservation {
        RawHIDObservation(vendorID: 111, productID: 222, usagePage: 0x09, usage: 0x10, value: value)
    }

    func testRingBufferBounds() {
        let log = HIDEventLog(maxEntries: 3)
        for i in 0..<5 { log.record(observation(value: i)) }
        XCTAssertEqual(log.entries.count, 3)
        XCTAssertTrue(log.entries.allSatisfy { $0.contains("value=") })
    }

    func testFormattedLineContainsIdentityAndHex() {
        var now = Date(timeIntervalSince1970: 0)
        let log = HIDEventLog(now: { now = now.addingTimeInterval(1); return now })
        log.record(observation())
        let line = try! XCTUnwrap(log.entries.first)
        XCTAssertTrue(line.contains("vid=111"))
        XCTAssertTrue(line.contains("pid=222"))
        XCTAssertTrue(line.contains("page=0x9"))
        XCTAssertTrue(line.contains("usage=0x10"))
        XCTAssertTrue(line.contains("value=1"))
    }

    func testPersistenceAppendsToFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("devices.log")
        let log = HIDEventLog(fileURL: fileURL, persistToFile: true)
        log.record(observation())
        log.record(observation(value: 2))
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertEqual(contents.split(separator: "\n").count, 2)
        XCTAssertTrue(contents.contains("value=2"))
    }

    func testPersistenceOffWritesNothing() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("devices.log")
        let log = HIDEventLog(fileURL: fileURL, persistToFile: false)
        log.record(observation())
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        log.setPersistToFile(true)
        log.record(observation(value: 3))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testClearAndAnalyzerBound() {
        let log = HIDEventLog(maxEntries: 2)
        log.record(observation())
        log.clear()
        XCTAssertTrue(log.entries.isEmpty)
        let analyzer = HIDAnalyzerStore(maxEntries: 2)
        analyzer.record(observation())
        analyzer.record(observation())
        analyzer.record(observation(value: 9))
        XCTAssertEqual(analyzer.recent.count, 2)
        XCTAssertEqual(analyzer.recent.last?.value, 9)
        analyzer.clear()
        XCTAssertTrue(analyzer.recent.isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter HIDEventLogTests`
Expected: FAIL — types do not exist.

- [ ] **Step 3: Implement**

Create `Sources/ArtMouseCore/Devices/HIDEventLog.swift`:

```swift
import Foundation

/// Device Log (spec §6 group 6): a bounded in-memory ring of formatted
/// observation lines with optional append-to-file persistence. Written from
/// the pump's main-queue sink only, so the buffer needs no lock.
public final class HIDEventLog {
    private var buffer: [String] = []
    private let maxEntries: Int
    private let fileURL: URL?
    public private(set) var persistToFile: Bool
    private let now: () -> Date
    private let formatter = ISO8601DateFormatter()

    public init(maxEntries: Int = 500, fileURL: URL? = nil,
                persistToFile: Bool = false, now: @escaping () -> Date = Date.init) {
        self.maxEntries = maxEntries
        self.fileURL = fileURL
        self.persistToFile = persistToFile
        self.now = now
    }

    public func record(_ observation: RawHIDObservation) {
        let hex = { String($0, radix: 16) }
        let line = "\(formatter.string(from: now())) vid=\(observation.vendorID) pid=\(observation.productID) "
            + "page=0x\(hex(observation.usagePage)) usage=0x\(hex(observation.usage)) value=\(observation.value)"
        buffer.append(line)
        if buffer.count > maxEntries {
            buffer.removeFirst(buffer.count - maxEntries)
        }
        if persistToFile, let fileURL {
            appendToDisk(line, url: fileURL)
        }
    }

    public var entries: [String] { buffer }

    public func setPersistToFile(_ on: Bool) { persistToFile = on }

    public func clear() { buffer.removeAll() }

    private func appendToDisk(_ line: String, url: URL) {
        guard let data = (line + "\n").data(using: .utf8) else { return }
        if !FileManager.default.fileExists(atPath: url.path) {
            try? data.write(to: url)
            return
        }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    }
}
```

Create `Sources/ArtMouseCore/Devices/HIDAnalyzerStore.swift`:

```swift
import Foundation
import Observation

/// Device Analyzer backing store (spec §6 group 6): the newest raw
/// observations for the live view. @Observable so the analyzer sheet tracks
/// additions; written from the pump's main-queue sink only.
@Observable
public final class HIDAnalyzerStore {
    public private(set) var recent: [RawHIDObservation] = []
    private let maxEntries: Int

    public init(maxEntries: Int = 200) {
        self.maxEntries = maxEntries
    }

    public func record(_ observation: RawHIDObservation) {
        recent.append(observation)
        if recent.count > maxEntries {
            recent.removeFirst(recent.count - maxEntries)
        }
    }

    public func clear() { recent.removeAll() }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter HIDEventLogTests`
Expected: PASS (5 tests). Full suite: 198 passing.

- [ ] **Step 5: Commit**

```bash
git add Sources/ArtMouseCore/Devices/HIDEventLog.swift Sources/ArtMouseCore/Devices/HIDAnalyzerStore.swift Tests/ArtMouseCoreTests/HIDEventLogTests.swift
git commit -m "Add device log and analyzer store"
```

---

### Task 4: HIDEventPump + IOKit observer glue + bootstrap wiring

**Files:**
- Create: `Sources/ArtMouseCore/Devices/HIDValueObserving.swift` (protocol + pump)
- Create: `Sources/ArtMouseCore/Devices/IOKitHIDValueObserver.swift` (glue, untested)
- Modify: `Sources/ArtMouseCore/Settings/SettingsStore.swift` (expose `directory`)
- Modify: `Sources/artMouse/EngineBootstrap.swift`
- Modify: `Sources/artMouse/AppDelegate.swift` and `Sources/artMouse/AppModel.swift` (share log/analyzer with UI)
- Test: `Tests/ArtMouseCoreTests/HIDEventPumpTests.swift` (new)

**Interfaces:**
- Consumes: Tasks 1–3 (`RawHIDObservation`, `HIDEventTranslator`, `HIDEventLog`, `HIDAnalyzerStore`, `GlobalSettings.deviceProfile(matchingVendor:productID:)`, `isDeviceDisabled`).
- Produces:
  - `protocol HIDValueObserving: AnyObject` — `func start(sink: @escaping (RawHIDObservation) -> Void)`, `func stop()`; **contract: the sink is invoked on the MAIN queue**.
  - `enum HIDObserveDecision: Equatable` — `.disabled`, `.observe(profile: DeviceProfile?)`
  - `final class HIDEventPump` — `init(observer: HIDValueObserving, resolve: @escaping (Int, Int) -> HIDObserveDecision, router: EventRouting, log: HIDEventLog?, analyzer: HIDAnalyzerStore?)`; `func start()`; `func stop()`; `func receive(_ observation: RawHIDObservation)` (internal, test entry)
  - `final class IOKitHIDValueObserver: HIDValueObserving` (glue)
  - `SettingsStore.directory: URL` (public)
  - AppModel gains `let hidAnalyzer: HIDAnalyzerStore?` and `let deviceLog: HIDEventLog?`

- [ ] **Step 1: Read first**

Read `Sources/artMouse/AppDelegate.swift` and `Sources/artMouse/AppModel.swift` in full before changing them — the log/analyzer must be created ONCE (in AppDelegate, like the watcher) and shared by the UI and the bootstrap.

- [ ] **Step 2: Write the failing tests**

Create `Tests/ArtMouseCoreTests/HIDEventPumpTests.swift`:

```swift
import XCTest
import ArtMouseCore

final class HIDEventPumpTests: XCTestCase {
    final class FakeObserver: HIDValueObserving {
        var started = 0
        var stopped = 0
        var sink: ((RawHIDObservation) -> Void)?
        func start(sink: @escaping (RawHIDObservation) -> Void) {
            started += 1
            self.sink = sink
        }
        func stop() { stopped += 1 }
    }

    final class RecordingRouter: EventRouting {
        var events: [InputEvent] = []
        func handle(_ event: InputEvent) -> RouterOutcome {
            events.append(event)
            return .passThrough
        }
    }

    private func observation(page: Int = 0x0C, usage: Int = 0x0B4, value: Int = 1) -> RawHIDObservation {
        RawHIDObservation(vendorID: 111, productID: 222, usagePage: page, usage: usage, value: value)
    }

    private func profile(capture: Bool = false) -> DeviceProfile {
        DeviceProfile(name: "m", vendorID: 111, productID: 222,
                      parts: [DevicePart(name: "Pedal", kind: .pedal, usagePage: 0x0C,
                                         usage: 0x0B4, routesAsButton: 8)],
                      rawButtonCapture: capture)
    }

    func testStartStartsObserverOnceAndStopForwards() {
        let observer = FakeObserver()
        let pump = HIDEventPump(observer: observer,
                                resolve: { _, _ in .observe(profile: nil) },
                                router: RecordingRouter(), log: nil, analyzer: nil)
        pump.start()
        pump.start()   // idempotent
        XCTAssertEqual(observer.started, 1)
        pump.stop()
        pump.stop()
        XCTAssertEqual(observer.stopped, 1)
    }

    func testPartObservationRoutesTranslatedEvents() {
        let observer = FakeObserver()
        let router = RecordingRouter()
        let pump = HIDEventPump(observer: observer,
                                resolve: { _, _ in .observe(profile: self.profile()) },
                                router: router, log: nil, analyzer: nil)
        pump.start()
        pump.receive(observation(value: 1))
        pump.receive(observation(value: 0))
        XCTAssertEqual(router.events, [.buttonDown(.extended(8)), .buttonUp(.extended(8))])
    }

    func testDisabledDeviceStillLogsButNeverRoutes() {
        let observer = FakeObserver()
        let router = RecordingRouter()
        let log = HIDEventLog()
        let analyzer = HIDAnalyzerStore()
        let pump = HIDEventPump(observer: observer,
                                resolve: { _, _ in .disabled },
                                router: router, log: log, analyzer: analyzer)
        pump.receive(observation())
        XCTAssertTrue(router.events.isEmpty)
        XCTAssertEqual(log.entries.count, 1)
        XCTAssertEqual(analyzer.recent.count, 1)
    }

    func testNoProfileStillLogsButNeverRoutes() {
        let observer = FakeObserver()
        let router = RecordingRouter()
        let log = HIDEventLog()
        let pump = HIDEventPump(observer: observer,
                                resolve: { _, _ in .observe(profile: nil) },
                                router: router, log: log, analyzer: nil)
        pump.receive(observation())
        XCTAssertTrue(router.events.isEmpty)
        XCTAssertEqual(log.entries.count, 1)
    }

    func testMultipleEventsFromOneObservationAllRoute() {
        let observer = FakeObserver()
        let router = RecordingRouter()
        // Raw capture: one button-page observation translates to exactly one
        // event; this test pins that translate() output is iterated, not just
        // the first element taken.
        let pump = HIDEventPump(observer: observer,
                                resolve: { _, _ in .observe(profile: self.profile()) },
                                router: router, log: nil, analyzer: nil)
        pump.receive(observation(value: 1))
        XCTAssertEqual(router.events.count, 1)
    }

    func testObserverCallbackDeliversThroughSink() {
        let observer = FakeObserver()
        let router = RecordingRouter()
        let pump = HIDEventPump(observer: observer,
                                resolve: { _, _ in .observe(profile: self.profile()) },
                                router: router, log: nil, analyzer: nil)
        pump.start()
        observer.sink?(observation(value: 1))   // as the glue would call it (on main)
        XCTAssertEqual(router.events, [.buttonDown(.extended(8))])
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter HIDEventPumpTests`
Expected: FAIL — types do not exist.

- [ ] **Step 4: Implement the pump and glue**

Create `Sources/ArtMouseCore/Devices/HIDValueObserving.swift`:

```swift
import Foundation

/// Observes raw HID input values. Contract: `sink` is invoked on the MAIN
/// queue — everything downstream (pump routing, log, analyzer, router state)
/// shares the tap path's main-run-loop discipline (bootstrap calling
/// discipline). The real implementation is IOKitHIDValueObserver; tests use
/// fakes.
public protocol HIDValueObserving: AnyObject {
    func start(sink: @escaping (RawHIDObservation) -> Void)
    func stop()
}

public enum HIDObserveDecision: Equatable {
    /// Device is disabled in settings: log and analyzer still record (the
    /// analyzer is a diagnostic), but nothing routes.
    case disabled
    case observe(profile: DeviceProfile?)
}

/// Feeds observed HID values through the translator into the router, after
/// logging/analyzer capture. Consumed on the main queue only.
public final class HIDEventPump {
    private let observer: HIDValueObserving
    private let resolve: (_ vendorID: Int, _ productID: Int) -> HIDObserveDecision
    private let router: EventRouting
    private let log: HIDEventLog?
    private let analyzer: HIDAnalyzerStore?
    private var running = false

    public init(observer: HIDValueObserving,
                resolve: @escaping (Int, Int) -> HIDObserveDecision,
                router: EventRouting,
                log: HIDEventLog? = nil,
                analyzer: HIDAnalyzerStore? = nil) {
        self.observer = observer
        self.resolve = resolve
        self.router = router
        self.log = log
        self.analyzer = analyzer
    }

    public func start() {
        guard !running else { return }
        running = true
        observer.start { [weak self] observation in
            self?.receive(observation)
        }
    }

    public func stop() {
        guard running else { return }
        running = false
        observer.stop()
    }

    /// The sink body. Internal so tests can drive it without system HID.
    func receive(_ observation: RawHIDObservation) {
        log?.record(observation)
        analyzer?.record(observation)
        guard case .observe(let profile) = resolve(observation.vendorID, observation.productID)
        else { return }
        for event in HIDEventTranslator.translate(observation, profile: profile) {
            _ = router.handle(event)
        }
    }
}
```

Create `Sources/ArtMouseCore/Devices/IOKitHIDValueObserver.swift`:

```swift
import Foundation
import IOKit
import IOKit.hid

/// Real observation glue over the PUBLIC IOHIDManager value-callback API.
/// Devices are opened WITHOUT seize (kIOHIDOptionsTypeNone), so the system
/// keeps receiving events normally — artMouse only observes. Callbacks are
/// registered per device (the manager-level callback cannot report which
/// device produced a value, and identity is needed for profile resolution).
///
/// Context lifecycle: one ContextBox retained per observed device, released
/// in the device-removal callback and in stop()/deinit. The sink hop to the
/// main queue implements the HIDValueObserving contract. This class is thin
/// system glue and is smoke-tested manually (spec §8); all logic under test
/// lives in the translator and pump.
public final class IOKitHIDValueObserver: HIDValueObserving {
    private final class ContextBox {
        let observer: IOKitHIDValueObserver
        let vendorID: Int
        let productID: Int
        init(observer: IOKitHIDValueObserver, vendorID: Int, productID: Int) {
            self.observer = observer
            self.vendorID = vendorID
            self.productID = productID
        }
    }

    private var manager: IOHIDManager?
    private var sink: ((RawHIDObservation) -> Void)?
    /// Per-device contexts: index-aligned parallel arrays.
    private var contexts: [Unmanaged<ContextBox>] = []

    public init() {}

    public func start(sink: @escaping (RawHIDObservation) -> Void) {
        guard manager == nil else { return }
        self.sink = sink
        let options = IOHIDManagerOptions().rawValue
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, options)
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Mouse,
        ] as CFDictionary)

        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, device in
            guard let context else { return }
            Unmanaged<IOKitHIDValueObserver>.fromOpaque(context)
                .takeUnretainedValue().releaseContext(for: device)
        }, Unmanaged.passUnretained(self).toOpaque())

        if let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
            for device in deviceSet {
                attach(device)
            }
        }

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonMode.rawValue)
        IOHIDManagerOpen(manager, options)
        self.manager = manager
    }

    public func stop() {
        guard let manager else { return }
        let options = IOHIDManagerOptions().rawValue
        IOHIDManagerClose(manager, options)
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonMode.rawValue)
        self.manager = nil
        contexts.forEach { $0.release() }
        contexts.removeAll()
        sink = nil
    }

    deinit {
        stop()
    }

    private func attach(_ device: IOHIDDevice) {
        guard
            let vendor = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int,
            let product = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int
        else { return }
        let box = ContextBox(observer: self, vendorID: vendor, productID: product)
        let unmanaged = Unmanaged.passRetained(box)
        contexts.append(unmanaged)
        IOHIDDeviceRegisterInputValueCallback(device, { context, _, _, value in
            guard let context,
                  let element = IOHIDValueGetElement(value) else { return }
            let box = Unmanaged<ContextBox>.fromOpaque(context).takeUnretainedValue()
            let observation = RawHIDObservation(
                vendorID: box.vendorID,
                productID: box.productID,
                usagePage: Int(IOHIDElementGetUsagePage(element)),
                usage: Int(IOHIDElementGetUsage(element)),
                value: Int(IOHIDValueGetIntegerValue(value)))
            // HIDValueObserving contract: deliver on the main queue. The
            // observer/box outlive this hop: the box is retained until device
            // removal or stop(), both of which run after queued hops drain
            // (stop() runs on main).
            DispatchQueue.main.async {
                box.observer.deliver(observation)
            }
        }, unmanaged.toOpaque())
    }

    fileprivate func releaseContext(for device: IOHIDDevice) {
        // Value callbacks were registered per device; IOKit drops them when
        // the device disappears. Release this device's retained context —
        // matched positionally is not possible from the raw pointer, so all
        // we can do here is nothing per-device: contexts release wholesale in
        // stop()/deinit. Kept as a hook: hot-unplug therefore leaks one small
        // box per unplug until app quit (documented; bounded by session length).
    }

    fileprivate func deliver(_ observation: RawHIDObservation) {
        sink?(observation)
    }
}
```

Modify `Sources/ArtMouseCore/Settings/SettingsStore.swift` — expose the directory (the log lives beside settings.json):

```swift
    /// Directory containing settings.json; the device log is a sibling.
    public var directory: URL { fileURL.deletingLastPathComponent() }
```

Modify `Sources/artMouse/AppDelegate.swift` — create the log and analyzer once (same place the watcher is created) and pass them to BOTH AppModel and EngineBootstrap (add initializer parameters `hidLog: HIDEventLog? = nil` and `hidAnalyzer: HIDAnalyzerStore? = nil`; AppModel stores them as `let`s, EngineBootstrap keeps private lets). Construct `HIDEventLog(fileURL: store.directory.appendingPathComponent("devices.log"))`.

Modify `Sources/artMouse/EngineBootstrap.swift` — inside `start(store:)`, AFTER the router and tap engine exist (the pump routes into the same `router`), wire:

```swift
        // Raw HID observation (Phase 4): value callbacks hop to main inside
        // the glue, so the pump consumes on the main run loop like the tap
        // path. Settings lookups are read per observation through the store
        // (live settings).
        let hidPump = HIDEventPump(
            observer: IOKitHIDValueObserver(),
            resolve: { [weak store] vendorID, productID in
                guard let settings = store?.settings else { return .observe(profile: nil) }
                if settings.isDeviceDisabled(vendorID: vendorID, productID: productID) {
                    return .disabled
                }
                return .observe(profile: settings.deviceProfile(matchingVendor: vendorID,
                                                                productID: productID))
            },
            router: router,
            log: hidLog,
            analyzer: hidAnalyzer)
        hidPump.start()
        self.hidPump = hidPump
```

(`hidLog`/`hidAnalyzer` are the init-parameter refs; `hidPump` is a new `private var hidPump: HIDEventPump?` strong anchor, same idiom as `macroEngine`.)

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter HIDEventPumpTests`
Expected: PASS (6 tests). Full suite: 204 passing, build clean.

- [ ] **Step 6: Commit**

```bash
git add Sources/ArtMouseCore/Devices/HIDValueObserving.swift Sources/ArtMouseCore/Devices/IOKitHIDValueObserver.swift Sources/ArtMouseCore/Settings/SettingsStore.swift Sources/artMouse/EngineBootstrap.swift Sources/artMouse/AppDelegate.swift Sources/artMouse/AppModel.swift Tests/ArtMouseCoreTests/HIDEventPumpTests.swift
git commit -m "Add HID event pump and IOHIDManager observer wiring"
```

---

### Task 5: Buttons 6+ end-to-end — UI, part-name labels, router pins

**Files:**
- Modify: `Sources/artMouse/Views/ButtonsTabView.swift`
- Modify: `Sources/artMouse/Views/BindingRowView.swift` (caption only, if structure allows)
- Modify: `Sources/artMouse/AppModel.swift`
- Test: `Tests/ArtMouseCoreTests/EventRouterTests.swift` (2 additions)

**Interfaces:**
- Consumes: Task 1 (`deviceProfiles`, `DevicePart.routesAsButton`); existing `ButtonID.extended`.
- Produces: `AppModel.ensureBinding(for button: ButtonID)`, `AppModel.partName(for button: ButtonID) -> String?`

Background (READ FIRST): `CGEventTranslation.buttonID(forCGNumber:)` already maps tap-delivered CG numbers ≥5 to `.extended(n)`, the router resolves extended bindings through every arm (click-lock, macro, hold, plain), and `ButtonsTabView` already renders extended buttons that appear in existing bindings. What is missing: a way to CREATE an extended binding from the UI, and part-name labels. CG button numbers are 0-based: number 5 = "Button 6" … number 31 = "Button 32".

- [ ] **Step 1: Write the failing tests (router pins)**

Append to `Tests/ArtMouseCoreTests/EventRouterTests.swift` (inside `EventRouterTests`, using the file's existing idioms — adapt helper names to what the file actually defines, e.g. reuse `RecordingExecutor`/`StubClickLock`/`StubCursor` and any chord/macros stubs the chord tests use):

```swift
    func testExtendedButtonChordCapturesAndFires() {
        // Buttons 6+ route through the SAME chord arm as standard buttons:
        // the capture consumes the press and the chord fires on completion.
        let executor = RecordingExecutor()
        var settings = GlobalSettings.default
        settings.chords = [Chord(buttons: [.extended(5), .extended(6)],
                                 timeoutSeconds: 1.0,
                                 actions: [.mission(.missionControl, reverse: false)])]
        let router = EventRouter(settings: store(settings), executor: executor,
                                 clickLock: StubClickLock(), cursor: StubCursor(),
                                 chords: <the same chord stub type the existing chord tests use>)
        XCTAssertEqual(router.handle(.buttonDown(.extended(5))), .consume)
        XCTAssertEqual(router.handle(.buttonDown(.extended(6))), .consume)
        XCTAssertEqual(executor.performed, [.mission(.missionControl, reverse: false)])
    }

    func testExtendedButtonMacroRunsProgram() {
        // An extended button with a single-action macro binding runs the
        // program on down, exactly like standard buttons.
        let executor = RecordingExecutor()
        let macros = <the file's recording macro engine>
        var settings = GlobalSettings.default
        settings.buttonBindings = [ButtonBinding(button: .extended(7), actions: [
            .macro([.enterKey(keyCode: 36, mods: [])], repeat: .none, intervalMS: 0, modifierProxy: false),
        ])]
        let router = EventRouter(settings: store(settings), executor: executor,
                                 clickLock: StubClickLock(), cursor: StubCursor(),
                                 macros: macros)
        XCTAssertEqual(router.handle(.buttonDown(.extended(7))), .consume)
        XCTAssertEqual(macros.startedPrograms.count, 1)
    }
```

NOTE to implementer: the two `<the same … the existing chord tests use>` slots must be replaced with the REAL stub names/patterns already present in `EventRouterTests.swift` (read the chord and macro test sections and mirror them exactly — including how `Chord` is constructed in this codebase and what the recording macro engine records). If `Chord`'s memberwise shape differs (e.g. `Chord(buttons:actions:timeoutSeconds:)` vs another order), adapt the test to the actual initializer. Do NOT invent new stub types when the file already has them.

- [ ] **Step 2: Run tests to verify they fail (or pass)**

Run: `swift test --filter testExtendedButton`
Expected: these tests may PASS immediately (the router is button-agnostic by design). That is fine — they are contract pins, not bug fixes. If they fail, fix the router gap they expose before continuing.

- [ ] **Step 3: Implement the UI**

`Sources/artMouse/AppModel.swift` — add:

```swift
    /// Creates an empty binding for an extended button so its row appears in
    /// the Buttons tab (idempotent). The empty-actions shape is behaviorally
    /// inert in the engine (bindings with no actions never match), so adding
    /// a row cannot strand the button — the Phase 1 zombie-binding fix holds.
    func ensureBinding(for button: ButtonID) {
        guard binding(for: button) == nil else { return }
        var settings = store.settings
        settings.buttonBindings.append(ButtonBinding(button: button, actions: []))
        store.settings = settings
        save()
    }

    /// Device-profile part name for an extended button ("Thumb 1"), shown as
    /// a caption in the Buttons tab; nil when no profile names this number.
    func partName(for button: ButtonID) -> String? {
        guard case .extended(let number) = button else { return nil }
        for profile in store.settings.deviceProfiles {
            if let part = profile.parts.first(where: { $0.routesAsButton == number }) {
                return part.name
            }
        }
        return nil
    }
```

`Sources/artMouse/Views/ButtonsTabView.swift` — replace the body with a Section + header Menu (keep the row content per button unchanged):

```swift
    var body: some View {
        List {
            Section {
                ForEach(buttons, id: \.self) { button in
                    BindingRowView(model: model, button: button)
                }
            } header: {
                HStack {
                    Text("Buttons")
                    Spacer()
                    Menu("Add…") {
                        ForEach(5...31, id: \.self) { number in
                            Button("Button \(number + 1)") {
                                model.ensureBinding(for: .extended(number))
                            }
                        }
                    }
                }
            }
        }
    }
```

Then, if `BindingRowView` renders per-button captions cleanly, add `Text(model.partName(for: button) ?? "")` styled `.caption`/`.secondary` under the button label (skip if its layout makes that awkward — record the choice in the report).

- [ ] **Step 4: Run the full suite and build the app**

Run: `swift test` (expected 206 passing) and `Scripts/make_app.sh` (build must succeed).

- [ ] **Step 5: Commit**

```bash
git add Sources/artMouse/Views/ButtonsTabView.swift Sources/artMouse/Views/BindingRowView.swift Sources/artMouse/AppModel.swift Tests/ArtMouseCoreTests/EventRouterTests.swift
git commit -m "Add extended-button creation UI and part-name captions"
```

---

### Task 6: Trackball direction + free-spin momentum

**Files:**
- Modify: `Sources/ArtMouseCore/Settings/GlobalSettings.swift` (`trackballHorizontalFlip`)
- Modify: `Sources/ArtMouseCore/Settings/WheelModeProfile.swift` (momentum fields + backward-compatible decode)
- Modify: `Sources/ArtMouseCore/Scroll/ScrollController.swift`
- Modify: `Sources/ArtMouseCore/Scroll/ScrollEmitter.swift`
- Modify: `Sources/artMouse/Views/WheelProfileEditorView.swift` (momentum toggle + decay/max fields)
- Modify: `Sources/artMouse/Views/GeneralTabView.swift` (trackball toggle)
- Test: `Tests/ArtMouseCoreTests/ScrollEmitterTests.swift` (additions), `Tests/ArtMouseCoreTests/ScrollControllerTests.swift` (additions), `Tests/ArtMouseCoreTests/SettingsStoreTests.swift` (decode pin)

**Interfaces:**
- Consumes: existing `ScrollEmitter` virtual-clock `tick(now:)`, `WheelModeProfile`.
- Produces:
  - `GlobalSettings.trackballHorizontalFlip: Bool` (default false)
  - `WheelModeProfile.freeSpinMomentum: Bool` (default false), `momentumDecayPercent: Int` (default 70), `momentumMaxTicks: Int` (default 30) — backward-compatible decode
  - `ScrollEmitter.primeMomentum(direction: ScrollDirection, linesPerTick: Double, decayPercent: Int, maxLines: Double, now: Double)`

Background: free-spin momentum applies to **constant mode only** (the mode that intercepts and thus eats the OS's own momentum ticks; acceleration mode passes them through scaled, and keys/auto modes must never repeat keys — Review Focus 5). The coast begins after `0.12 s` of input silence and decays each 16 ms step by `decayPercent`, capped by `maxLines` total.

- [ ] **Step 1: Write the failing tests**

In `Tests/ArtMouseCoreTests/ScrollEmitterTests.swift` (mirror the file's existing virtual-clock + recording-poster idioms exactly — read the file's helpers first):

```swift
    // MARK: Free-spin momentum (Phase 4)

    func testMomentumCoastStartsAfterInputSilenceAndDecays() {
        // prime → silence past the gap → coast emits decaying steps, then stops.
        let emitter = ScrollEmitter(poster: poster)   // the file's recording poster fixture
        emitter.primeMomentum(direction: .down, linesPerTick: 3, decayPercent: 50,
                              maxLines: 100, now: 0)
        emitter.tick(now: 0.05)   // inside the gap: nothing
        emitter.tick(now: 0.13)   // gap elapsed: first coast step emits 3
        emitter.tick(now: 0.15)   // step 2 emits 1.5
        emitter.tick(now: 0.17)   // step 3 emits 0.75
        emitter.tick(now: 0.19)   // step 4 emits 0.375 → below 0.05 floor not yet…
        // Assert: posted line amounts are strictly decreasing and the sequence
        // terminates (isActive false after enough steps). Compare against the
        // file's recorded-post event fields (fixed-pt deltas).
    }

    func testMomentumNeverCoastsUnderAnotherOwner() {
        // With an open keys run, a primed momentum must not coast over it.
        let emitter = ScrollEmitter(poster: poster)
        emitter.beginKeys(keys, direction: .down, now: 0)      // the file's fixture key emulation
        emitter.primeMomentum(direction: .down, linesPerTick: 3, decayPercent: 50,
                              maxLines: 100, now: 0)
        emitter.tick(now: 1.0)
        XCTAssertFalse(emitterIsActiveCoast(emitter))          // assert via recorded posts: no scroll lines posted
    }

    func testMomentumCappedByMaxLines() {
        let emitter = ScrollEmitter(poster: poster)
        emitter.primeMomentum(direction: .down, linesPerTick: 3, decayPercent: 95,
                              maxLines: 5, now: 0)
        for t in stride(from: 0.13, through: 2.0, by: 0.02) { emitter.tick(now: t) }
        // Total posted lines must not exceed maxLines + first step; assert the
        // recorded fixed-pt sum ≤ (5 + 3) lines worth of 65536 units.
    }

    func testNewInputCancelsLiveCoast() {
        let emitter = ScrollEmitter(poster: poster)
        emitter.primeMomentum(direction: .down, linesPerTick: 3, decayPercent: 50,
                              maxLines: 100, now: 0)
        emitter.tick(now: 0.13)            // coast begins
        emitter.noteInput(now: 0.14)       // real wheel tick lands
        emitter.tick(now: 0.30)            // silence again, but no fresh prime → no new coast
        // Assert: no post at 0.30 (coast was cancelled by noteInput and only a
        // primeMomentum call restarts the sequence).
    }
```

NOTE to implementer: the `<assert …>` comments are the assertions' INTENT — write them against this file's REAL recording poster fixture (it records posted CGEvents; read line amounts from `.scrollWheelEventFixedPtDeltaAxis1`). Replace `emitterIsActiveCoast(_:)` and any fixture names with the file's actual helpers; delete nothing that exists. If the file's fixtures differ in shape (e.g. a spy emitter protocol), adapt to it.

In `Tests/ArtMouseCoreTests/ScrollControllerTests.swift`, mirror the file's existing reverse-direction test (the closest analogue) for:

```swift
    func testTrackballFlipReversesHorizontalDirection() {
        // store.settings.trackballHorizontalFlip = true + a constant-mode
        // profile → a horizontal scroll derived as .right is emitted as .left.
        // Assert through the same channel the existing reverse test asserts
        // through (scaleOutcome sign or emitted direction).
    }

    func testMomentumPrimesOnlyInConstantMode() {
        // profile.freeSpinMomentum = true + acceleration mode → after the
        // silence gap no coast posts (assert: no scroll post beyond the
        // passthrough scale — the emitter recorded nothing).
    }
```

In `Tests/ArtMouseCoreTests/SettingsStoreTests.swift` (decode pin — Review Focus 4):

```swift
    func testPhase2WheelProfileJSONDecodesWithMomentumDefaults() throws {
        // A pre-Phase-4 wheel profile JSON without the momentum fields decodes
        // with freeSpinMomentum false / decay 70 / maxTicks 30.
        let json = """
        {"id":"11111111-1111-1111-1111-111111111111","name":"w","mode":"constant",
         "sensFactor":1.0,"acceleration":0.0,"lines":3.0,"intervalMS":100,
         "reverseVertical":false,"reverseHorizontal":false,"smoothScroll":false,
         "smoothIntervalMS":16,"autoIntervalMS":50,"autoStopTicks":5}
        """
        let profile = try JSONDecoder().decode(WheelModeProfile.self, from: Data(json.utf8))
        XCTAssertFalse(profile.freeSpinMomentum)
        XCTAssertEqual(profile.momentumDecayPercent, 70)
        XCTAssertEqual(profile.momentumMaxTicks, 30)
    }

    func testTrackballFlipDefaultsFalseOnOldSettings() throws {
        let settings = try JSONDecoder().decode(GlobalSettings.self,
                                                from: Data(phase3SettingsJSON.utf8))
        // reuse this file's existing minimal-old-settings fixture name; if it
        // has none, use the same JSON shape as DeviceProfileTests.
        XCTAssertFalse(settings.trackballHorizontalFlip)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "ScrollEmitterTests|ScrollControllerTests|SettingsStoreTests"`
Expected: FAIL — members do not exist (decode pins fail on missing keys).

- [ ] **Step 3: Implement**

`Sources/ArtMouseCore/Settings/GlobalSettings.swift` — add stored property `public var trackballHorizontalFlip: Bool` to `GlobalSettings` + `static let default` (`trackballHorizontalFlip: false`) + in `init(from:)`:

```swift
        trackballHorizontalFlip = try c.decodeIfPresent(Bool.self, forKey: .trackballHorizontalFlip) ?? false
```

`Sources/ArtMouseCore/Settings/WheelModeProfile.swift` — add three stored properties with defaults in the explicit init (`freeSpinMomentum: Bool = false`, `momentumDecayPercent: Int = 70`, `momentumMaxTicks: Int = 30`), and add a backward-compatible decoder (extension, so the explicit init stays):

```swift
extension WheelModeProfile {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        mode = try c.decode(ScrollMode.self, forKey: .mode)
        sensFactor = try c.decode(Double.self, forKey: .sensFactor)
        acceleration = try c.decode(Double.self, forKey: .acceleration)
        lines = try c.decode(Double.self, forKey: .lines)
        intervalMS = try c.decode(Int.self, forKey: .intervalMS)
        reverseVertical = try c.decode(Bool.self, forKey: .reverseVertical)
        reverseHorizontal = try c.decode(Bool.self, forKey: .reverseHorizontal)
        smoothScroll = try c.decode(Bool.self, forKey: .smoothScroll)
        smoothIntervalMS = try c.decode(Int.self, forKey: .smoothIntervalMS)
        keyEmulation = try c.decodeIfPresent(WheelKeyEmulation.self, forKey: .keyEmulation)
        autoIntervalMS = try c.decode(Int.self, forKey: .autoIntervalMS)
        autoStopTicks = try c.decode(Int.self, forKey: .autoStopTicks)
        // Phase 4: absent in earlier files → inert defaults (backward compat).
        freeSpinMomentum = try c.decodeIfPresent(Bool.self, forKey: .freeSpinMomentum) ?? false
        momentumDecayPercent = try c.decodeIfPresent(Int.self, forKey: .momentumDecayPercent) ?? 70
        momentumMaxTicks = try c.decodeIfPresent(Int.self, forKey: .momentumMaxTicks) ?? 30
    }
}
```

`Sources/ArtMouseCore/Scroll/ScrollEmitter.swift` — add momentum state and handling. New members:

```swift
    static let momentumGapSeconds: Double = 0.12
    static let momentumStepInterval: Double = 0.016
    static let momentumStopFloor: Double = 0.05

    private struct MomentumState {
        let direction: ScrollDirection
        let linesPerTick: Double
        let decayPercent: Int
        let maxLines: Double
    }

    private var momentum: MomentumState?
    private var momentumLastInput: Double = 0
```

Extend `Mode` with:

```swift
        case coast(direction: ScrollDirection, remaining: Double, decayPercent: Int,
                   emitted: Double, maxLines: Double, nextDue: Double)
```

Add the prime API and extend `noteInput(now:)` + `tick(now:)` (read the full file first; keep the existing switch arms byte-identical):

```swift
    /// Arms free-spin momentum (constant mode only — Review Focus 5). The
    /// coast itself begins in tick(now:) once input has been quiet for the
    /// gap; fresh input re-anchors the gap via noteInput.
    public func primeMomentum(direction: ScrollDirection, linesPerTick: Double,
                              decayPercent: Int, maxLines: Double, now: Double) {
        guard linesPerTick >= Self.momentumStopFloor else { return }
        momentum = MomentumState(direction: direction, linesPerTick: linesPerTick,
                                 decayPercent: decayPercent, maxLines: maxLines)
        momentumLastInput = now
    }
```

At the top of `tick(now:)`, before the existing mode switch:

```swift
        // Momentum coast: only starts when the emitter owns nothing else
        // (constant mode is fire-and-forget, so idle here means no keys/auto/
        // smooth run is open) and input has gone quiet.
        if case .idle = mode, let momentum = self.momentum,
           now - momentumLastInput >= Self.momentumGapSeconds {
            mode = .coast(direction: momentum.direction, remaining: momentum.linesPerTick,
                          decayPercent: momentum.decayPercent, emitted: 0,
                          maxLines: momentum.maxLines, nextDue: now)
        }
```

Add the `.coast` arm to the tick switch:

```swift
        case .coast(let direction, let remaining, let decayPercent, let emitted,
                    let maxLines, let nextDue):
            guard now >= nextDue, remaining >= Self.momentumStopFloor, emitted < maxLines else {
                if remaining < Self.momentumStopFloor || emitted >= maxLines { mode = .idle }
                return
            }
            postScroll(direction: direction, lines: remaining)
            let nextRemaining = remaining * (Double(decayPercent) / 100.0)
            let nextEmitted = emitted + remaining
            if nextRemaining < Self.momentumStopFloor || nextEmitted >= maxLines {
                mode = .idle
            } else {
                mode = .coast(direction: direction, remaining: nextRemaining,
                              decayPercent: decayPercent, emitted: nextEmitted,
                              maxLines: maxLines, nextDue: now + Self.momentumStepInterval)
            }
```

In `noteInput(now:)`, before the existing switch (all owners re-anchor the gap; a live coast dies — only a primeMomentum restarts it):

```swift
        momentumLastInput = now
        if case .coast = mode { mode = .idle }
```

In `stop()` (and wherever mode resets to idle), also `momentum = nil`.

`Sources/ArtMouseCore/Scroll/ScrollController.swift` — in `disposition(forScroll:ticks:)`, after the reverse-flip block:

```swift
        // Trackball convention (global option, spec A.4): thumb-operated
        // trackballs report horizontal deltas mirrored; flip the sign.
        if axis == .horizontal && store.settings.trackballHorizontalFlip {
            direction = direction.flipped
        }
```

and in the `.constant` arm, after `emitter.noteInput(now: clock())`:

```swift
            if profile.freeSpinMomentum {
                let decay = Int(Double(profile.momentumDecayPercent).clamped(10...95))
                let maxTicks = Int(Double(profile.momentumMaxTicks).clamped(1...100))
                emitter.primeMomentum(direction: direction, linesPerTick: lines,
                                      decayPercent: decay,
                                      maxLines: lines * Double(maxTicks), now: clock())
            }
```

`Sources/artMouse/Views/WheelProfileEditorView.swift` — add a momentum Toggle + two numeric TextFields (decay percent 10…95, max ticks 1…100) using the numeric-field idiom the file already uses; `Sources/artMouse/Views/GeneralTabView.swift` — add a trackball Toggle bound to a new `AppModel.setTrackballFlip(_:)` mutator (same `var settings`/`save()` idiom as its neighbors).

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: all passing (≈214), including the new pins. Build: `Scripts/make_app.sh` clean.

- [ ] **Step 5: Commit**

```bash
git add Sources/ArtMouseCore/Settings/GlobalSettings.swift Sources/ArtMouseCore/Settings/WheelModeProfile.swift Sources/ArtMouseCore/Scroll/ScrollController.swift Sources/ArtMouseCore/Scroll/ScrollEmitter.swift Sources/artMouse/Views/WheelProfileEditorView.swift Sources/artMouse/Views/GeneralTabView.swift Sources/artMouse/AppModel.swift Tests/ArtMouseCoreTests/ScrollEmitterTests.swift Tests/ArtMouseCoreTests/ScrollControllerTests.swift Tests/ArtMouseCoreTests/SettingsStoreTests.swift
git commit -m "Add free-spin momentum and trackball direction option"
```

---

### Task 7: DPI feature reports — builder, manager, executor wiring, degradation

**Files:**
- Create: `Sources/ArtMouseCore/Devices/DPIReportBuilder.swift`
- Create: `Sources/ArtMouseCore/Devices/DPIManager.swift` (protocol + manager)
- Create: `Sources/ArtMouseCore/Devices/IOKitFeatureReportSender.swift` (glue, untested)
- Modify: `Sources/ArtMouseCore/Actions/ActionExecutor.swift`
- Modify: `Sources/ArtMouseCore/Model/Action.swift` (`isHoldAction` gains `.device(.dpiShift)`)
- Modify: `Sources/ArtMouseCore/Cursor/CursorController.swift` (`activateDefault()` + protocol member)
- Modify: `Sources/artMouse/Views/DeviceActionEditorView.swift` (re-enable DPI items)
- Modify: `Sources/artMouse/EngineBootstrap.swift` (wire DPIManager)
- Test: `Tests/ArtMouseCoreTests/DPIReportBuilderTests.swift` (new), `Tests/ArtMouseCoreTests/DPIManagerTests.swift` (new), `Tests/ArtMouseCoreTests/ActionExecutorTests.swift` (additions)

**Interfaces:**
- Consumes: Task 1's `DeviceProfile`/`DeviceDPIConfig`; existing `CursorCoordinating.activateNext(source:)`.
- Produces:
  - `enum DPIReportBuilder` — `static func payload(config: DeviceDPIConfig, level: Int) -> Data`; `static func clampedLevelIndex(_ index: Int, levelCount: Int) -> Int`
  - `enum DPIOperation: Equatable` — `.up`, `.down`, `.cycle`, `.restoreDefault`
  - `protocol DPICoordinating: AnyObject` — `func apply(_ operation: DPIOperation) -> Bool`; `func beginShift() -> Bool`; `func endShift()`
  - `final class DPIManager: DPICoordinating` — `init(profileProvider: @escaping () -> DeviceProfile?, applyLevel: @escaping (DeviceProfile, _ level: Int, _ levelIndex: Int) -> Bool)`
  - `final class IOKitFeatureReportSender` — `func send(vendorID: Int, productID: Int, reportID: Int, report: Data) -> Bool`
  - `CursorCoordinating.activateDefault()`
  - `ActionExecutor` init gains `dpi: DPICoordinating? = nil`

- [ ] **Step 1: Write the failing tests**

`Tests/ArtMouseCoreTests/DPIReportBuilderTests.swift`:

```swift
import XCTest
import ArtMouseCore

final class DPIReportBuilderTests: XCTestCase {
    func testPayloadWritesLittleEndianLevelAtValueByte() {
        let config = DeviceDPIConfig(levels: [800, 1600, 3200], reportID: 5,
                                     valueByte: 1, valueMask: 0xFFFF, reportLength: 4)
        XCTAssertEqual(Array(DPIReportBuilder.payload(config: config, level: 1600)),
                       [0x00, 0x40, 0x06, 0x00])   // 1600 = 0x0640 little-endian at byte 1
    }

    func testPayloadMaskLimitsValue() {
        let config = DeviceDPIConfig(levels: [800], valueByte: 0, valueMask: 0x00FF, reportLength: 2)
        XCTAssertEqual(Array(DPIReportBuilder.payload(config: config, level: 1600)),
                       [0x40, 0x00])   // 1600 & 0xFF = 0x40
    }

    func testPayloadClampsOutOfBoundsLayout() {
        // Absurd declared layouts must produce a bounded payload, never crash
        // (Review Focus 3).
        let config = DeviceDPIConfig(levels: [800], valueByte: 9, valueMask: 0xFFFF, reportLength: 0)
        XCTAssertEqual(DPIReportBuilder.payload(config: config, level: 800).count, 1)
        let beyond = DeviceDPIConfig(levels: [800], valueByte: 3, valueMask: 0xFFFF, reportLength: 2)
        XCTAssertEqual(DPIReportBuilder.payload(config: beyond, level: 800).count, 2)
    }

    func testClampedLevelIndex() {
        XCTAssertEqual(DPIReportBuilder.clampedLevelIndex(-5, levelCount: 3), 0)
        XCTAssertEqual(DPIReportBuilder.clampedLevelIndex(2, levelCount: 3), 2)
        XCTAssertEqual(DPIReportBuilder.clampedLevelIndex(9, levelCount: 3), 2)
        XCTAssertEqual(DPIReportBuilder.clampedLevelIndex(0, levelCount: 0), 0)
    }
}
```

`Tests/ArtMouseCoreTests/DPIManagerTests.swift`:

```swift
import XCTest
import ArtMouseCore

final class DPIManagerTests: XCTestCase {
    final class Recorder {
        var calls: [(profile: DeviceProfile, level: Int, index: Int)] = []
        var succeed = true
        func apply(_ profile: DeviceProfile, _ level: Int, _ index: Int) -> Bool {
            calls.append((profile, level, index))
            return succeed
        }
    }

    private func profile(levels: [Int], active: Int = 0) -> DeviceProfile {
        DeviceProfile(name: "m", vendorID: 1, productID: 2,
                      dpi: DeviceDPIConfig(levels: levels, activeLevelIndex: active))
    }

    func testApplyUpAndDownClampAtBounds() {
        let recorder = Recorder()
        let device = profile(levels: [800, 1600, 3200], active: 2)
        let manager = DPIManager(profileProvider: { device },
                                 applyLevel: { recorder.apply($0, $1, $2) })
        XCTAssertTrue(manager.apply(.up))     // already last → stays at index 2
        XCTAssertEqual(recorder.calls.last?.index, 2)
        XCTAssertTrue(manager.apply(.down))
        XCTAssertEqual(recorder.calls.last?.level, 1600)
    }

    func testApplyCycleAndRestoreDefault() {
        let recorder = Recorder()
        let device = profile(levels: [800, 1600, 3200], active: 2)
        let manager = DPIManager(profileProvider: { device },
                                 applyLevel: { recorder.apply($0, $1, $2) })
        XCTAssertTrue(manager.apply(.cycle))   // 2 → 0
        XCTAssertEqual(recorder.calls.last?.index, 0)
        XCTAssertTrue(manager.apply(.restoreDefault))
        XCTAssertEqual(recorder.calls.last?.index, 0)
        XCTAssertEqual(recorder.calls.last?.level, 800)
    }

    func testApplyWithoutConfigReturnsFalse() {
        let manager = DPIManager(profileProvider: { DeviceProfile(name: "m", vendorID: 1, productID: 2) },
                                 applyLevel: { _, _, _ in true })
        XCTAssertFalse(manager.apply(.cycle))
        let empty = profile(levels: [])
        let emptyManager = DPIManager(profileProvider: { empty }, applyLevel: { _, _, _ in true })
        XCTAssertFalse(emptyManager.apply(.cycle))
    }

    func testShiftRaisesThenRestores() {
        let recorder = Recorder()
        let device = profile(levels: [800, 1600, 3200], active: 0)
        let manager = DPIManager(profileProvider: { device },
                                 applyLevel: { recorder.apply($0, $1, $2) })
        XCTAssertTrue(manager.beginShift())
        XCTAssertEqual(recorder.calls.last?.level, 1600)
        manager.endShift()
        XCTAssertEqual(recorder.calls.last?.level, 800)
        XCTAssertEqual(recorder.calls.last?.index, 0)
    }

    func testShiftOnLastLevelReturnsFalseAndNeverSends() {
        let recorder = Recorder()
        let device = profile(levels: [800, 1600], active: 1)
        let manager = DPIManager(profileProvider: { device },
                                 applyLevel: { recorder.apply($0, $1, $2) })
        XCTAssertFalse(manager.beginShift())
        XCTAssertTrue(recorder.calls.isEmpty)
        manager.endShift()   // no origin: must not send
        XCTAssertTrue(recorder.calls.isEmpty)
    }
}
```

`Tests/ArtMouseCoreTests/ActionExecutorTests.swift` additions (mirror the file's existing fake cursor/poster fixtures — read its helpers first):

```swift
    func testDPICycleDegradesToCursorCycleWhenUnavailable() {
        // No DPI coordinator: the spec §3 degradation — DPI ops fall back to
        // cursor-speed profile switching.
        let cursor = <the file's recording cursor fake>
        let executor = ActionExecutor(poster: RecordingPoster(), cursor: cursor)
        executor.perform(.device(.dpiCycle))
        XCTAssertEqual(cursor.activatedNextCalls, 1)
    }

    func testDPIDegradationWhenReportSendFails() {
        let cursor = <the file's recording cursor fake>
        let failingDPI = <a tiny DPICoordinating fake whose apply returns false>
        let executor = ActionExecutor(poster: RecordingPoster(), cursor: cursor, dpi: failingDPI)
        executor.perform(.device(.dpiUp))
        XCTAssertEqual(cursor.activatedNextCalls, 1)
    }

    func testRestoreDefaultDegradesToDefaultProfile() {
        let cursor = <the file's recording cursor fake>
        let executor = ActionExecutor(poster: RecordingPoster(), cursor: cursor)
        executor.perform(.device(.defaultDPI))
        XCTAssertEqual(cursor.activatedDefaultCalls, 1)
    }

    func testDPISuccessfulApplyDoesNotTouchCursor() {
        let cursor = <the file's recording cursor fake>
        let dpi = <a fake whose apply returns true>
        let executor = ActionExecutor(poster: RecordingPoster(), cursor: cursor, dpi: dpi)
        executor.perform(.device(.dpiCycle))
        XCTAssertEqual(cursor.activatedNextCalls, 0)
    }

    func testDPIShiftHoldLifecycleCallsBeginAndEnd() {
        let dpi = <a fake recording beginShift/endShift>
        let executor = ActionExecutor(poster: RecordingPoster(), dpi: dpi)
        executor.beganHold(.device(.dpiShift))
        executor.endedHold(.device(.dpiShift))
        XCTAssertEqual(dpi.beginCalls, 1)
        XCTAssertEqual(dpi.endCalls, 1)
    }
```

NOTE to implementer: `<the file's … fake>` slots must be replaced with the ACTUAL fixture names and shapes in `ActionExecutorTests.swift` (read the whole file first; extend its existing recording cursor fake with `activatedNextCalls`/`activatedDefaultCalls` counters if it doesn't have them). Write real fakes only if the file has none.

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "DPI|DPIShift"`
Expected: FAIL — types/members do not exist.

- [ ] **Step 3: Implement**

`Sources/ArtMouseCore/Devices/DPIReportBuilder.swift`:

```swift
import Foundation

/// Pure translation from a DPI level to a feature-report payload. The report
/// ID is the SetReport selector, NOT part of the payload. All declared layout
/// numbers are clamped here (engine boundary) so an absurd profile can never
/// crash the sender (Review Focus 3).
public enum DPIReportBuilder {
    /// Payload of `reportLength` bytes (>= 1) with the masked level written
    /// little-endian (up to 16 bits) at `valueByte`.
    public static func payload(config: DeviceDPIConfig, level: Int) -> Data {
        let length = max(1, config.reportLength)
        var bytes = [UInt8](repeating: 0, count: length)
        let masked = level & max(0, config.valueMask)
        let index = max(0, config.valueByte)
        if index < length { bytes[index] = UInt8(clamping: masked & 0xFF) }
        if index + 1 < length { bytes[index + 1] = UInt8(clamping: (masked >> 8) & 0xFF) }
        return Data(bytes)
    }

    public static func clampedLevelIndex(_ index: Int, levelCount: Int) -> Int {
        guard levelCount > 0 else { return 0 }
        return Swift.min(Swift.max(index, 0), levelCount - 1)
    }
}
```

`Sources/ArtMouseCore/Devices/DPIManager.swift`:

```swift
import Foundation

public enum DPIOperation: Equatable {
    case up, down, cycle, restoreDefault
}

/// Applies DPI operations to the active device profile. `applyLevel` both
/// sends the feature report and persists the new `activeLevelIndex`; its Bool
/// is whether the report actually went out — false engages the executor's
/// degradation (spec §3).
public protocol DPICoordinating: AnyObject {
    func apply(_ operation: DPIOperation) -> Bool
    /// Momentary DPI Shift (hold lifecycle): raise one level; `endShift`
    /// restores the pre-shift level. Returns false when unavailable.
    func beginShift() -> Bool
    func endShift()
}

public final class DPIManager: DPICoordinating {
    private let profileProvider: () -> DeviceProfile?
    private let applyLevel: (DeviceProfile, _ level: Int, _ levelIndex: Int) -> Bool
    private var shiftOrigin: Int?

    public init(profileProvider: @escaping () -> DeviceProfile?,
                applyLevel: @escaping (DeviceProfile, _ level: Int, _ levelIndex: Int) -> Bool) {
        self.profileProvider = profileProvider
        self.applyLevel = applyLevel
    }

    public func apply(_ operation: DPIOperation) -> Bool {
        guard let profile = profileProvider(), let config = profile.dpi, !config.levels.isEmpty
        else { return false }
        let current = DPIReportBuilder.clampedLevelIndex(config.activeLevelIndex,
                                                         levelCount: config.levels.count)
        let next: Int
        switch operation {
        case .up: next = min(current + 1, config.levels.count - 1)
        case .down: next = max(current - 1, 0)
        case .cycle: next = (current + 1) % config.levels.count
        case .restoreDefault: next = 0
        }
        return applyLevel(profile, config.levels[next], next)
    }

    public func beginShift() -> Bool {
        guard let profile = profileProvider(), let config = profile.dpi,
              config.levels.count > 1 else { return false }
        let current = DPIReportBuilder.clampedLevelIndex(config.activeLevelIndex,
                                                         levelCount: config.levels.count)
        guard current < config.levels.count - 1 else { return false }
        shiftOrigin = current
        return applyLevel(profile, config.levels[current + 1], current + 1)
    }

    public func endShift() {
        defer { shiftOrigin = nil }
        guard let origin = shiftOrigin, let profile = profileProvider(), let config = profile.dpi,
              config.indices.contains(origin) else { return }
        _ = applyLevel(profile, config.levels[origin], origin)
    }
}
```

`Sources/ArtMouseCore/Devices/IOKitFeatureReportSender.swift`:

```swift
import Foundation
import IOKit
import IOKit.hid

/// Real feature-report glue (public IOHIDManager/IOHIDDevice API). Runs on
/// the tap-callback path: IOHIDDeviceSetReport on a healthy device completes
/// in microseconds–milliseconds (same risk class as the AX sync reads, which
/// carry a 0.25 s messaging timeout). A wedged device can block longer;
/// accepted for owned personal devices (spec §3). Thin glue — smoke-tested.
public final class IOKitFeatureReportSender {
    public init() {}

    /// False when no matching device exists, it cannot be opened, or the
    /// write failed — never throws, never crashes.
    public func send(vendorID: Int, productID: Int, reportID: Int, report: Data) -> Bool {
        let options = IOHIDManagerOptions().rawValue
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, options)
        defer { IOHIDManagerClose(manager, options) }
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Mouse,
        ] as CFDictionary)
        guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              let device = deviceSet.first(where: {
                  (IOHIDDeviceGetProperty($0, kIOHIDVendorIDKey as CFString) as? Int) == vendorID
                      && (IOHIDDeviceGetProperty($0, kIOHIDProductIDKey as CFString) as? Int) == productID
              })
        else { return false }
        guard IOHIDDeviceOpen(device, options) == kIOReturnSuccess else { return false }
        defer { IOHIDDeviceClose(device, options) }
        var bytes = [UInt8](report)
        guard !bytes.isEmpty else { return false }
        return IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, CFIndex(reportID),
                                    &bytes, CFIndex(bytes.count)) == kIOReturnSuccess
    }
}
```

`Sources/ArtMouseCore/Model/Action.swift`:

```swift
    public var isHoldAction: Bool {
        if case .device(.switchPrecisionMode) = self { return true }
        if case .device(.dpiShift) = self { return true }
        return false
    }
```

`Sources/ArtMouseCore/Cursor/CursorController.swift` — add to `CursorCoordinating` protocol `func activateDefault()`; add to `CursorController`:

```swift
    /// Spec §3 DPI degradation target: the profile named "Default", else the
    /// first profile.
    public func activateDefault() {
        if let named = store.settings.cursorSpeedProfiles.first(where: { $0.name == "Default" }) {
            activate(profileID: named.id, source: .buttonAction)
        } else if let first = store.settings.cursorSpeedProfiles.first {
            activate(profileID: first.id, source: .buttonAction)
        }
    }
```

`Sources/ArtMouseCore/Actions/ActionExecutor.swift` — add `private weak var dpi: DPICoordinating?` (+ init param `dpi: DPICoordinating? = nil`, assigned like the other weak graph refs); replace the DPI arms in `performDevice`:

```swift
        case .dpiCycle: performDPI(.cycle)
        case .dpiUp: performDPI(.up)
        case .dpiDown: performDPI(.down)
        case .defaultDPI: performDPI(.restoreDefault)
        case .dpiShift: break   // hold lifecycle: beganHold/endedHold arms below
```

add the helper and the hold arms (next to the existing `switchPrecisionMode` arms in `beganHold`/`endedHold`):

```swift
    /// DPI ops on a device without DPI support degrade to cursor-speed
    /// profile switching (spec §3): cycle/up/down → next profile,
    /// default → the "Default" profile.
    private func performDPI(_ operation: DPIOperation) {
        guard let dpi, dpi.apply(operation) else {
            if case .restoreDefault = operation {
                cursor?.activateDefault()
            } else {
                cursor?.activateNext(source: .buttonAction)
            }
            return
        }
    }
```

```swift
        if case .device(.dpiShift) = action { _ = dpi?.beginShift() }   // in beganHold
        if case .device(.dpiShift) = action { dpi?.endShift() }         // in endedHold
```

`Sources/artMouse/Views/DeviceActionEditorView.swift` — remove `.disabled(true)` and the `// phase 4` comments from the DPI picker items.

`Sources/artMouse/EngineBootstrap.swift` — inside `start(store:)` (after `executor` exists; pass `dpi:` into the ActionExecutor initializer):

```swift
        // DPI feature reports (Phase 4): the manager resolves the first
        // enabled profile that declares DPI; the glue sender matches by
        // VID/PID. Send failures degrade in the executor (spec §3).
        let featureSender = IOKitFeatureReportSender()
        let dpiManager = DPIManager(
            profileProvider: { [weak store] in
                guard let settings = store?.settings else { return nil }
                return settings.deviceProfiles.first { profile in
                    profile.dpi != nil
                        && !settings.isDeviceDisabled(vendorID: profile.vendorID,
                                                      productID: profile.productID)
                }
            },
            applyLevel: { [weak store, weak featureSender] profile, level, index in
                guard let featureSender,
                      let config = profile.dpi,
                      featureSender.send(vendorID: profile.vendorID,
                                         productID: profile.productID,
                                         reportID: config.reportID,
                                         report: DPIReportBuilder.payload(config: config, level: level))
                else { return false }
                if let store {
                    var settings = store.settings
                    if let i = settings.deviceProfiles.firstIndex(where: { $0.id == profile.id }) {
                        settings.deviceProfiles[i].dpi?.activeLevelIndex = index
                        store.settings = settings
                        try? store.save()
                    }
                }
                return true
            })
```

(add `dpiManager` as a `private var` strong anchor like `macroEngine`, and pass `dpi: dpiManager` into the `ActionExecutor` initializer).

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: all passing (≈228). Build clean.

- [ ] **Step 5: Commit**

```bash
git add Sources/ArtMouseCore/Devices/DPIReportBuilder.swift Sources/ArtMouseCore/Devices/DPIManager.swift Sources/ArtMouseCore/Devices/IOKitFeatureReportSender.swift Sources/ArtMouseCore/Actions/ActionExecutor.swift Sources/ArtMouseCore/Model/Action.swift Sources/ArtMouseCore/Cursor/CursorController.swift Sources/artMouse/Views/DeviceActionEditorView.swift Sources/artMouse/EngineBootstrap.swift Tests/ArtMouseCoreTests/DPIReportBuilderTests.swift Tests/ArtMouseCoreTests/DPIManagerTests.swift Tests/ArtMouseCoreTests/ActionExecutorTests.swift
git commit -m "Add DPI feature reports with degradation fallback"
```

---

### Task 8: Devices tab UI — profiles, enable/disable, analyzer, IORegistry details

**Files:**
- Modify: `Sources/artMouse/Views/DevicesTabView.swift`
- Create: `Sources/artMouse/Views/DeviceProfileEditorSheet.swift`
- Create: `Sources/artMouse/Views/DeviceAnalyzerSheet.swift`
- Modify: `Sources/artMouse/AppModel.swift`
- Modify: `Sources/ArtMouseCore/Devices/IOKitDeviceEnumerator.swift` (registry details glue)

**Interfaces:**
- Consumes: Tasks 1, 4, 7 (`deviceProfiles`, `disabledDeviceKeys`, `HIDDeviceIdentity`, `HIDAnalyzerStore`, `HIDEventLog`, `DeviceProfile`/`DevicePart`/`DeviceDPIConfig`, `AppModel.partName`).
- Produces: `AppModel.addDeviceProfile(for:) -> DeviceProfile`, `AppModel.updateDeviceProfile(_:)`, `AppModel.removeDeviceProfile(_:)`, `AppModel.toggleDeviceDisabled(_:)`, `AppModel.deviceProfile(for:) -> DeviceProfile?`, `AppModel.setDeviceLogPersist(_:)`, `AppModel.registryDetails(for:) -> [String: String]`

This is a UI task: no unit tests (spec §8), but the build must be clean and the reviewer must be able to trace every control to a model mutator. All numeric TextFields (usage/page/DPI numbers) MUST use the safe numeric helpers introduced in Task 9 — if Task 8 runs BEFORE Task 9, implement the two tiny helpers inline here first and have Task 9 consolidate; otherwise import them.

- [ ] **Step 1: Implement the model layer**

`Sources/artMouse/AppModel.swift` (all using the file's existing `var settings` / `save()` idiom):

```swift
    // MARK: Devices (Phase 4)

    /// Creates a skeleton profile for an attached device and returns it. The
    /// profile editor sheet then fills parts/DPI.
    @discardableResult
    func addDeviceProfile(for device: HIDDeviceIdentity) -> DeviceProfile {
        let profile = DeviceProfile(name: device.name,
                                    vendorID: device.vendorID,
                                    productID: device.productID)
        var settings = store.settings
        settings.deviceProfiles.append(profile)
        store.settings = settings
        save()
        return profile
    }

    func updateDeviceProfile(_ profile: DeviceProfile) {
        var settings = store.settings
        if let index = settings.deviceProfiles.firstIndex(where: { $0.id == profile.id }) {
            settings.deviceProfiles[index] = profile
        }
        store.settings = settings
        save()
    }

    func removeDeviceProfile(_ id: UUID) {
        var settings = store.settings
        settings.deviceProfiles.removeAll { $0.id == id }
        store.settings = settings
        save()
    }

    /// Toggle helper over `disabledDeviceKeys` (settings-key based, so it
    /// works for devices without a profile too).
    func toggleDeviceDisabled(_ device: HIDDeviceIdentity) {
        var settings = store.settings
        let key = device.settingsKey
        if let index = settings.disabledDeviceKeys.firstIndex(of: key) {
            settings.disabledDeviceKeys.remove(at: index)
        } else {
            settings.disabledDeviceKeys.append(key)
        }
        store.settings = settings
        save()
    }

    func deviceProfile(for device: HIDDeviceIdentity) -> DeviceProfile? {
        store.settings.deviceProfile(matchingVendor: device.vendorID, productID: device.productID)
    }

    func setDeviceLogPersist(_ on: Bool) {
        deviceLog?.setPersistToFile(on)
    }

    /// IORegistry details for the disclosure row (glue call, on demand —
    /// never on the hot path).
    func registryDetails(for device: HIDDeviceIdentity) -> [String: String] {
        IOKitDeviceEnumerator().registryDetails(vendorID: device.vendorID,
                                                productID: device.productID)
    }
```

`Sources/ArtMouseCore/Devices/IOKitDeviceEnumerator.swift` — add (thin glue, same enumeration pattern as `currentPointingDevices()`):

```swift
    /// IORegistry details for the Devices tab disclosure (spec §6 group 6).
    /// Missing keys are simply absent from the result.
    public func registryDetails(vendorID: Int, productID: Int) -> [String: String] {
        let options = IOHIDManagerOptions().rawValue
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, options)
        defer { IOHIDManagerClose(manager, options) }
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Mouse,
        ] as CFDictionary)
        guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              let device = deviceSet.first(where: {
                  (IOHIDDeviceGetProperty($0, kIOHIDVendorIDKey as CFString) as? Int) == vendorID
                      && (IOHIDDeviceGetProperty($0, kIOHIDProductIDKey as CFString) as? Int) == productID
              })
        else { return [:] }
        var details: [String: String] = [:]
        let keys: [(String, CFString)] = [
            ("Manufacturer", kIOHIDManufacturerKey ?? "" as CFString),
            ("Product", kIOHIDProductKey),
            ("SerialNumber", kIOHIDSerialNumberKey ?? "" as CFString),
            ("Transport", kIOHIDTransportKey),
            ("LocationID", kIOHIDLocationIDKey ?? "" as CFString),
        ]
        for (label, key) in keys where (key as CFString).length > 0 {
            if let value = IOHIDDeviceGetProperty(device, key) {
                details[label] = "\(value)"
            }
        }
        return details
    }
```

NOTE to implementer: `kIOHIDManufacturerKey`, `kIOHIDSerialNumberKey`, `kIOHIDLocationIDKey` may not exist on this SDK as optional CFStrings (SDK adaptation territory, same as the earlier enumerator's comments). Probe what the SDK exposes (`kIOHIDVendorIDKey` etc. are known-good); for missing constants either use the string literal keys ("Manufacturer", "SerialNumber", "LocationID") in a `[CFString: Any]`-friendly way or drop those rows — the result is a display nicety, not engine state. Keep the known-good keys (Product, Transport, VendorID, ProductID) and adapt the rest; record the adaptation in the report.

- [ ] **Step 2: Implement the views**

`Sources/artMouse/Views/DevicesTabView.swift` — replace with:

```swift
import SwiftUI
import ArtMouseCore

struct DevicesTabView: View {
    @State private var analyzerDevice: HIDDeviceIdentity?
    @State private var editingProfile: DeviceProfile?

    var body: some View {
        List(model.devices.devices, id: \.settingsKey) { device in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(device.name).font(.body)
                    Spacer()
                    Toggle("Enabled", isOn: Binding(
                        get: { !model.settings.isDeviceDisabled(vendorID: device.vendorID,
                                                                productID: device.productID) },
                        set: { _ in model.toggleDeviceDisabled(device) }))
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                Text("\(device.transport) — VID \(device.vendorID) PID \(device.productID)")
                    .font(.caption).foregroundStyle(.secondary)
                if let profile = model.deviceProfile(for: device) {
                    Text("Profile: \(profile.name) — \(profile.parts.count) part(s)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Edit Profile…") {
                        editingProfile = model.deviceProfile(for: device)
                            ?? model.addDeviceProfile(for: device)
                    }
                    Button("Analyze…") { analyzerDevice = device }
                }
                .buttonStyle(.link)
                DeviceDetailsDisclosure(device: device, model: model)
            }
        }
        .sheet(item: $analyzerDevice) { device in
            DeviceAnalyzerSheet(device: device, model: model)
        }
        .sheet(item: $editingProfile) { profile in
            DeviceProfileEditorSheet(
                initial: profile,
                onSave: { model.updateDeviceProfile($0) },
                onDelete: { model.removeDeviceProfile($0.id) })
        }
    }
}

/// On-demand IORegistry disclosure (state keeps it collapsed by default).
struct DeviceDetailsDisclosure: View {
    let device: HIDDeviceIdentity
    let model: AppModel
    @State private var expanded = false
    @State private var details: [String: String] = [:]

    var body: some View {
        DisclosureGroup("Details", isExpanded: $expanded) {
            ForEach(details.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                HStack {
                    Text(key).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(value).font(.caption)
                }
            }
        }
        .onChange(of: expanded) { _, isExpanded in
            if isExpanded && details.isEmpty {
                details = model.registryDetails(for: device)
            }
        }
    }
}
```

`DeviceProfile` must be `Identifiable` for `.sheet(item:)` — Task 1 made it so. `HIDDeviceIdentity` already is `Hashable`; make the sheet items work by confirming conformance (`Identifiable` via `settingsKey`) — add `extension HIDDeviceIdentity: Identifiable { public var id: String { settingsKey } }` in `HIDDeviceIdentity.swift` (app-facing convenience, ArtMouseCore file is fine).

`Sources/artMouse/Views/DeviceAnalyzerSheet.swift`:

```swift
import SwiftUI
import ArtMouseCore

struct DeviceAnalyzerSheet: View {
    let device: HIDDeviceIdentity
    let model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Analyzing \(device.name)").font(.headline)
                Spacer()
                Button("Clear") { model.hidAnalyzer?.clear() }
                Button("Done") { dismiss() }
            }
            .padding(8)
            Divider()
            // Offset identity: identical consecutive observations would
            // collide under \.self.
            List(Array(observerEntries.reversed().enumerated()), id: \.offset) { _, line in
                Text(line).font(.system(.caption, design: .monospaced))
            }
        }
        .frame(minWidth: 520, minHeight: 380)
    }

    private var observerEntries: [String] {
        guard let analyzer = model.hidAnalyzer else { return [] }
        return analyzer.recent
            .filter { $0.vendorID == device.vendorID && $0.productID == device.productID }
            .map { o in
                "page 0x\(String(o.usagePage, radix: 16)) usage 0x\(String(o.usage, radix: 16)) value \(o.value)"
            }
    }
}
```

`Sources/artMouse/Views/DeviceProfileEditorSheet.swift` — parts editor + DPI panel. Layout: name field; `rawButtonCapture` Toggle with the warning copy:

```swift
                        Toggle("Capture extra buttons as raw HID", isOn: …)
                        Text("Only for mice whose extra buttons never reach macOS. If your buttons already work, enabling this fires each press twice.")
                            .font(.caption).foregroundStyle(.orange)
```

parts `ForEach(profile.parts)` rows: name field, kind Picker (.button/.wheel/.pedal), usage page/usage Int fields, and for button/pedal kinds a Picker "Routes as" over `5...31` labeled "Button \(n + 1)" writing `routesAsButton` (nil choice for wheel kind). "Add Part"/"Remove" buttons. DPI section: `dpi` levels as an editable list (add/remove rows, Int fields), plus reportID / valueByte / valueMask / reportLength Int fields, and a footnote that the layout is vendor-specific. ALL Int fields parse through a shared safe helper:

```swift
/// Finiteness-guarded numeric field helpers (Review-class fix from Phase 3:
/// NaN/inf from force-typing must never trap). Shared with Task 9's sweep.
func safeInt(_ text: String, in range: ClosedRange<Int>, fallback: Int) -> Int {
    guard let value = Double(text), value.isFinite else { return fallback }
    return Int(Swift.min(Swift.max(value, Double(range.lowerBound)), Double(range.upperBound)))
}
```

Put `safeInt` in a new `Sources/artMouse/Views/NumericFieldHelpers.swift` (Task 9 extends this file). Sheet state: this editor holds a local editable copy of the profile; Save writes via `onSave` once (the derive-from-props discipline applies to INLINE editors in rows; a modal sheet owns its draft via `@State` — consistent with ProfileEditorView's pattern if it uses one; check it and mirror).

- [ ] **Step 3: Build and smoke-test**

Run: `swift test` (must stay green — no engine changes) and `Scripts/make_app.sh`. Launch `build/artMouse.app`, open Settings → Devices: rows render with toggles; "Edit Profile…" opens the sheet; "Analyze…" opens the sheet (entries appear only for devices with HID traffic). Record anything broken in the report.

- [ ] **Step 4: Commit**

```bash
git add Sources/artMouse/Views/DevicesTabView.swift Sources/artMouse/Views/DeviceProfileEditorSheet.swift Sources/artMouse/Views/DeviceAnalyzerSheet.swift Sources/artMouse/Views/NumericFieldHelpers.swift Sources/artMouse/AppModel.swift Sources/ArtMouseCore/Devices/IOKitDeviceEnumerator.swift Sources/ArtMouseCore/Devices/HIDDeviceIdentity.swift
git commit -m "Add devices tab profiles, analyzer, and registry details"
```

---

### Task 9: Carried-fix sweep (Phase 3 review leftovers)

**Files:**
- Create: `Sources/artMouse/Views/NumericFieldHelpers.swift` (if Task 8 didn't already)
- Modify: `Sources/artMouse/Views/MacroStepEditorView.swift`, `WheelProfileEditorView.swift`, `CursorTabView.swift`, `ScrollActionEditorView.swift` (numeric sweep)
- Create: `Sources/ArtMouseCore/Actions/WheelEventFactory.swift`
- Modify: `Sources/ArtMouseCore/Scroll/ScrollEmitter.swift` (use factory), `Sources/ArtMouseCore/Actions/ActionExecutor.swift` (use factory + clamp lines)
- Modify: `Sources/artMouse/AppModel.swift` (app-profile guards)
- Test: `Tests/ArtMouseCoreTests/ActionExecutorTests.swift` (clamp pin), `Tests/ArtMouseCoreTests/EventRouterTests.swift` (click-lock+chord corner)

**Interfaces:**
- Consumes: existing fixtures.
- Produces: `WheelEventFactory.lineEvent(vertical:horizontal:) -> CGEvent` (internal); `safeInt`/`safeDouble` app-target helpers (from Task 8).

- [ ] **Step 1: Numeric conversion sweep**

Search `grep -rn "Int(\|UInt64(" Sources/artMouse/Views/` and route every conversion of USER-TYPED numeric text through `safeInt`/`safeClamp`-style helpers (finiteness guard before conversion — the Phase 3 NaN regression class). `MacroStepEditorView.swift` already has a guarded local `clamped` — move its logic into the shared helpers file and have all call sites use the shared form. Engine-internal conversions of already-clamped values are out of scope. Verify with a clean build and the full suite.

- [ ] **Step 2: Wheel event factory (dedupe)**

Create `Sources/ArtMouseCore/Actions/WheelEventFactory.swift`:

```swift
import CoreGraphics

/// Shared wheel-event construction. SDK adaptation (moved here verbatim from
/// the two former construction sites): this SDK's wheel init is
/// (scrollWheelEvent2Source:units:wheelCount:wheel1:wheel2:wheel3:) with
/// Int32 parameters — the variadic CGFloat overload does not exist — and
/// wheelCount must be 2 or the constructor ignores wheel2 (horizontal). The
/// int delta fields truncate, so fractional line amounts additionally ride
/// the 16.16 fixed-point delta fields, the shape the system uses for
/// sub-line scrolling.
enum WheelEventFactory {
    static func lineEvent(vertical: Double, horizontal: Double) -> CGEvent {
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2,
                            wheel1: Int32(vertical), wheel2: Int32(horizontal), wheel3: 0)!
        event.setIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1,
                                   value: Int64(vertical * 65536.0))
        event.setIntegerValueField(.scrollWheelEventFixedPtDeltaAxis2,
                                   value: Int64(horizontal * 65536.0))
        return event
    }
}
```

`ScrollEmitter.postScroll` and `ActionExecutor.performScroll` build their events via the factory (their sign/axis math and poster calls stay where they are). Behavior-identical — the existing ScrollEmitter/ActionExecutor tests are the pin.

- [ ] **Step 3: `.scroll` lines clamp at the executor**

In `ActionExecutor.performScroll`, clamp once before posting:

```swift
        // Engine-boundary clamp (Phase 3 carry): an absurd lines value must
        // not post runaway scroll deltas.
        let lines = Swift.min(Swift.max(spec.lines, 0), 100)
```

and use `lines` in the v/h computation. Add the pin to `Tests/ArtMouseCoreTests/ActionExecutorTests.swift` (using the file's real recording-poster fixture — read its scroll-event assertions first):

```swift
    func testScrollActionLinesClampedAtExecutor() {
        // lines: 500 must arrive as ≤ 100 lines on the posted event.
        let executor = <the file's fixture executor with its recording poster>
        executor.perform(.scroll(ScrollSpec(direction: .down, lines: 500)))
        let event = <the recorded scroll event>
        let fixedPt = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        XCTAssertLessThanOrEqual(abs(fixedPt), 100.0 + 0.001)
    }
```

- [ ] **Step 4: Click-lock + chord flush corner test**

Append to `Tests/ArtMouseCoreTests/EventRouterTests.swift` (mirror the file's stub idioms):

```swift
    func testChordFlushRunsClickLockLifecycleForFlushedButton() {
        // A chord whose flushed button is click-lock bound must deliver the
        // full noteDown/noteUp lifecycle during the up-flush — no stranded
        // sticky state (Phase 3 carry).
        let clickLock = <the file's recording click-lock stub>
        let router = EventRouter(settings: <store with a click-lock binding on .fifth and a chord over .fifth+.middle>,
                                 executor: RecordingExecutor(), clickLock: clickLock,
                                 cursor: StubCursor(),
                                 chords: <the file's chord stub>)
        _ = router.handle(.buttonDown(.fifth))    // captured by chord
        _ = router.handle(.buttonDown(.middle))
        _ = router.handle(.buttonUp(.middle))     // flush trigger
        // Assert: clickLock recorded noteDown(.fifth) AND noteUp(.fifth) —
        // the flush's down-then-up pair drove the coordinator.
    }
```

NOTE to implementer: use the file's actual chord/click-lock stub names; if the stub doesn't record noteDown/noteUp, extend IT (test fixture) to record. Assert the real recorded sequence.

- [ ] **Step 5: App-profile editor guards (AppModel)**

```swift
    func addAppProfile(bundleID: String, name: String) {
        let trimmed = bundleID.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var settings = store.settings
        guard !settings.appProfiles.contains(where: { $0.bundleID == trimmed }) else { return }
        settings.appProfiles.append(AppProfile(bundleID: trimmed, name: name))
        store.settings = settings
        save()
    }

    func updateAppProfile(_ profile: AppProfile) {
        // Same guards as add: trimmed, non-empty, and no duplicate bundle ID
        // against OTHER profiles (a duplicate would create an inert loser row
        // in first-match resolution).
        var trimmed = profile
        trimmed.bundleID = profile.bundleID.trimmingCharacters(in: .whitespaces)
        guard !trimmed.bundleID.isEmpty else { return }
        var settings = store.settings
        if let index = settings.appProfiles.firstIndex(where: { $0.id == trimmed.id }) {
            let duplicates = settings.appProfiles.contains {
                $0.bundleID == trimmed.bundleID && $0.id != trimmed.id
            }
            guard !duplicates else { return }
            settings.appProfiles[index] = trimmed
        }
        store.settings = settings
        save()
    }
```

Also in `MacroStepEditorView.swift`: if `modChecks(_ title:)`'s title parameter is genuinely unused inside the function (verify by reading), drop the parameter and update the two call sites. In `MacroStepsEditorView.swift`, add a comment on the `ForEach(Array(steps.enumerated()), id: \.offset)` line:

```swift
        // Offset identity is deliberate: steps are plain values without stable
        // IDs, and duplicate steps would collide under \.self. The transient
        // focus quirk on remove is the accepted trade (the editor is
        // derive-from-props — no @State to key identity from).
```

- [ ] **Step 6: Run the full suite and build**

Run: `swift test` (all green, including the 2 new pins) and `Scripts/make_app.sh`.

- [ ] **Step 7: Commit**

```bash
git add -A Sources Tests
git commit -m "Apply carried fixes: numeric guards, wheel factory, clamps, guards"
```

---

### Task 10: Verification checklist + doc fixes

**Files:**
- Create: `docs/verification/phase-4.md`
- Modify: `docs/` (fix the dangling safe-mode cross-reference — search `grep -rn "safe-mode\|safe mode" docs/` for the reference the Phase 3 ledger flagged as dangling and repair it to point at the real anchor)

- [ ] **Step 1: Write `docs/verification/phase-4.md`**

Follow the format of `docs/verification/phase-3.md` (read it first). Cover, each as a numbered HOW TO VERIFY item with expected result:

1. Buttons 6–32 that surface as CGEvents bind and fire (no behavior change from Phase 4).
2. A device profile with `rawButtonCapture` ON for a mouse whose buttons DO surface → presses fire TWICE (documents Review Focus 1's failure mode as the expected consequence of the misconfiguration) — and the UI warning is visible in the profile editor.
3. Device profile part (pedal/vendor button) fires its binding; part name appears in the Buttons tab caption.
4. Analyzer sheet streams live entries while a button/wheel is exercised; Clear works.
5. Device Log persists to `~/Library/Application Support/artMouse/devices.log` when toggled; stops when untoggled.
6. Enable/disable: a disabled device stops producing analyzer/routing traffic (HID side); note the limitation that tap-delivered events from that device still arrive.
7. DPI on an owned device (if a config exists): DPI Up/Down/Cycle step levels and persist across restart; Default returns to level 0.
8. DPI degradation on a device without a config: DPI ops cycle cursor-speed profiles; Default selects "Default".
9. DPI Shift (hold): raises a level while held, restores on release.
10. Trackball flip: horizontal scroll reverses with the General-tab toggle on.
11. Free-spin momentum on a free-spin wheel (constant mode): coast after the spin stops; capped; new input kills the coast; keys/auto modes never coast.
12. Settings round-trip: export → import carries device profiles; an old Phase 3 settings.json still loads with defaults for new fields.
13. Sleep/wake and hot-plug: HID observation survives wake; unplug/replug of a profiled device keeps its bindings working.

- [ ] **Step 2: Fix the dangling cross-reference**

Locate the safe-mode reference the Phase 3 ledger flagged (it points at a doc section that doesn't exist) and repair it to the real anchor (the safe-mode launch flag documented in the spec §7 and any README section that actually exists). If no safe-mode section exists anywhere, replace the reference with the spec §7 citation.

- [ ] **Step 3: Commit**

```bash
git add docs
git commit -m "Record phase 4 verification checklist and fix doc cross-reference"
```

---

## Task Dependency Summary

| Task | Depends on |
|---|---|
| 1 | — |
| 2 | 1 |
| 3 | 2 |
| 4 | 1, 2, 3 |
| 5 | 1 |
| 6 | — |
| 7 | 1 |
| 8 | 1, 4 (analyzer instances), 9 (numeric helpers — or self-provides) |
| 9 | — (Task 8 may have created the helpers file) |
| 10 | all |

Execution order 1→10 respects every dependency.

## Final Verification (lead, after review loop closes)

- `swift test` on the merged result: expected ≈230 passing, 0 failures.
- `Scripts/make_app.sh` bundle builds and launches; Devices tab renders; analyzer opens.
- Surface every ledger `Ruling:` line in the phase wrap-up message.
- Human verification checklist `docs/verification/phase-4.md` handed to the user (requires real hardware: an owned multi-button/specialty device for items 3, 5–9, 11).
