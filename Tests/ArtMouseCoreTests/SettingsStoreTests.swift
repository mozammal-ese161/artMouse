import XCTest
import Combine
import Observation
@testable import ArtMouseCore

final class SettingsStoreTests: XCTestCase {
    private func tempDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testFirstLoadCreatesDefaults() throws {
        let store = SettingsStore(directory: tempDirectory())
        XCTAssertEqual(store.settings, .default)
        XCTAssertTrue(store.lastLoadWarnings.isEmpty)
    }

    func testSaveThenReloadRoundTrip() throws {
        let dir = tempDirectory()
        var settings = GlobalSettings.default
        settings.buttonBindings = [
            ButtonBinding(id: UUID(), button: .fourth, actions: [.mission(.missionControl, reverse: false)])
        ]
        let store = SettingsStore(directory: dir)
        store.settings = settings
        try store.save()

        let reloaded = SettingsStore(directory: dir)
        XCTAssertEqual(reloaded.settings, settings)
    }

    func testMalformedJSONFallsBackToDefaultsWithWarning() throws {
        let dir = tempDirectory()
        try Data("not json at all".utf8).write(to: dir.appendingPathComponent("settings.json"))
        let store = SettingsStore(directory: dir)
        XCTAssertEqual(store.settings, .default)
        XCTAssertEqual(store.lastLoadWarnings.count, 1)
        XCTAssertTrue(store.lastLoadWarnings[0].contains("settings.json"))
    }

    func testDecodeThrowsOnGarbage() {
        XCTAssertThrowsError(try SettingsStore.decode(Data("nope".utf8)))
    }

    /// Task 16 fix round 1: the Settings UI reads `store.settings` through the
    /// `@Observable` AppModel, so mutating the store must fire observation
    /// callbacks — that is what re-renders the Buttons tab. Regression for the
    /// retired ObservableObject version, whose writes no view could observe.
    func testSettingsMutationIsObservable() throws {
        let store = SettingsStore(directory: tempDirectory())
        let observed = expectation(description: "settings change observed")
        withObservationTracking {
            _ = store.settings
        } onChange: {
            observed.fulfill()
        }

        var other = GlobalSettings.default
        other.buttonBindings = [
            ButtonBinding(id: UUID(), button: .middle, actions: [.mission(.missionControl, reverse: false)])
        ]
        store.settings = other

        wait(for: [observed], timeout: 2.0)
    }

    func testUnreadableFileFallsBackToDefaultsWithWarning() throws {
        let dir = tempDirectory()
        let store = SettingsStore(directory: dir)
        var nonDefault = GlobalSettings.default
        nonDefault.buttonBindings = [
            ButtonBinding(id: UUID(), button: .fourth, actions: [.mission(.missionControl, reverse: false)])
        ]
        store.settings = nonDefault
        try store.save()

        let fileURL = dir.appendingPathComponent("settings.json")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: fileURL.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fileURL.path)
        }

        store.reload()

        XCTAssertEqual(store.settings, .default)
        XCTAssertEqual(store.lastLoadWarnings.count, 1)
    }

    func testPhase1SettingsJSONStillDecodes() throws {
        // Exact shape a Phase 1 save produced: no wheel/chord/scroll fields.
        let phase1JSON = """
        {"activeCursorSpeedProfileID":null,"buttonBindings":[],
         "cursorSpeedProfiles":[{"acceleration":1,"id":"11111111-1111-1111-1111-111111111111","name":"Default","sensitivity":1600}],
         "precisionProfileID":null,"schemaVersion":1}
        """
        let settings = try SettingsStore.decode(Data(phase1JSON.utf8))
        XCTAssertEqual(settings.buttonBindings, [])
        XCTAssertEqual(settings.wheelModeProfiles.count, 0)   // defaulted, file not rewritten until next save
        XCTAssertEqual(settings.chords, [])
        XCTAssertEqual(settings.scrollBindings, [])
    }

    func testWheelModeProfileFallbackChain() {
        var settings = GlobalSettings.default
        XCTAssertNil(settings.activeWheelProfile)   // empty list

        settings.wheelModeProfiles = [WheelModeProfile(name: "Fast")]
        XCTAssertEqual(settings.activeWheelProfile?.name, "Fast")   // no named "Default" → first profile
    }

    func testActiveWheelProfilePrefersExplicitIDThenNamedDefaultThenFirst() {
        var settings = GlobalSettings.default
        let first = WheelModeProfile(name: "One")
        let named = WheelModeProfile(name: "Default")
        let other = WheelModeProfile(name: "Three")
        settings.wheelModeProfiles = [first, named, other]

        settings.activeWheelModeProfileID = other.id
        XCTAssertEqual(settings.activeWheelProfile, other)

        settings.activeWheelModeProfileID = UUID()          // dangling
        XCTAssertEqual(settings.activeWheelProfile, named)  // named Default

        settings.wheelModeProfiles = [first]                // named gone
        XCTAssertEqual(settings.activeWheelProfile, first)  // first
    }

    // A Phase 2 settings file (no appProfiles key) must decode with an empty
    // profile list — per-app overrides are additive, never breaking.
    func testAppProfilesDecodeDefaultEmpty() throws {
        let phase2JSON = """
        {"activeCursorSpeedProfileID":null,"buttonBindings":[],
         "chords":[],"cursorSpeedProfiles":[{"acceleration":1,"id":"11111111-1111-1111-1111-111111111111","name":"Default","sensitivity":1600}],
         "precisionProfileID":null,"schemaVersion":1,"scrollBindings":[],
         "wheelModeProfiles":[]}
        """
        let settings = try SettingsStore.decode(Data(phase2JSON.utf8))
        XCTAssertEqual(settings.appProfiles, [])
    }

    func testEffectiveResolutionFallsBackToGlobal() {
        var settings = GlobalSettings.default
        let binding = ButtonBinding(button: .fourth, actions: [.none])
        settings.buttonBindings = [binding]
        XCTAssertEqual(settings.effectiveButtonBindings(for: "com.apple.Safari"), [binding])   // no app profile
        XCTAssertEqual(settings.effectiveButtonBindings(for: nil), [binding])                  // nil watcher
    }

    func testEffectiveResolutionPrefersAppProfile() {
        var settings = GlobalSettings.default
        let globalBinding = ButtonBinding(button: .fourth, actions: [.none])
        let appBinding = ButtonBinding(button: .middle, actions: [.mission(.launchpad, reverse: false)])
        let appProfile = AppProfile(bundleID: "com.apple.Safari", name: "Safari",
                                    buttonBindings: [appBinding], scrollBindings: nil,
                                    cursorSpeedProfileID: nil, wheelModeProfileID: nil)
        settings.appProfiles = [appProfile]
        settings.buttonBindings = [globalBinding]

        XCTAssertEqual(settings.effectiveButtonBindings(for: "com.apple.Safari"), [appBinding])
        XCTAssertEqual(settings.effectiveButtonBindings(for: "com.apple.TextEdit"), [globalBinding])

        let fast = WheelModeProfile(name: "Fast")
        settings.wheelModeProfiles = [WheelModeProfile(name: "Slow"), fast]
        settings.appProfiles[0].wheelModeProfileID = fast.id
        XCTAssertEqual(settings.effectiveWheelProfile(for: "com.apple.Safari"), fast)
        // cursor override nil → global chain applies (the Default profile)
        XCTAssertEqual(settings.effectiveCursorProfile(for: "com.apple.Safari"), settings.activeProfile)
    }

    func testEffectiveCursorAndWheelOverrides() {
        var settings = GlobalSettings.default
        let slow = settings.cursorSpeedProfiles[0]
        let fast = WheelModeProfile(name: "Fast")
        // Asserted while wheelModeProfiles is still the default empty list:
        // with no bundle ID the fallback is activeWheelProfile, and once the
        // list holds `fast` that fallback resolves to `fast`, not nil (brief
        // fix: the list assignment moved below this line so the stated
        // precondition holds).
        XCTAssertEqual(settings.effectiveWheelProfile(for: nil), nil)   // default empty list → nil
        settings.wheelModeProfiles = [fast]
        let appProfile = AppProfile(bundleID: "com.apple.Safari", name: "Safari",
                                    buttonBindings: nil, scrollBindings: nil,
                                    cursorSpeedProfileID: slow.id, wheelModeProfileID: fast.id)
        settings.appProfiles = [appProfile]

        XCTAssertEqual(settings.effectiveCursorProfile(for: "com.apple.Safari"), slow)
        XCTAssertEqual(settings.effectiveWheelProfile(for: "com.apple.Safari"), fast)
    }
}
