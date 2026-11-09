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
}
