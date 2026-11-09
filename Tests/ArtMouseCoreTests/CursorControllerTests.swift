import XCTest
@testable import ArtMouseCore

final class CursorControllerTests: XCTestCase {
    private var now = 0.0

    private func makeStore() -> SettingsStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return SettingsStore(directory: dir)
    }

    private func makeController(_ store: SettingsStore) -> CursorController {
        CursorController(store: store, clock: { [weak self] in self?.now ?? 0 })
    }

    // Default profile: sensitivity 1600 (factor 1.0), acceleration 1.0.
    // .moved(dx: 4) → speed = 4 → accel factor = 1 + 1×(4/8) = 1.5 → total 1.5.
    func testOutcomeUsesActiveProfileTransform() {
        let store = makeStore()
        let controller = makeController(store)
        XCTAssertEqual(controller.outcome(forMove: .moved(dx: 4, dy: 0)),
                       .cursorTransform(dxFactor: 1.5, dyFactor: 1.5))
    }

    func testUserSwitchPersistsAndCancelsRestore() {
        let store = makeStore()
        let controller = makeController(store)
        let slow = store.settings.cursorSpeedProfiles[0]
        controller.activate(profileID: slow.id, source: .user)
        XCTAssertEqual(controller.activeProfile, slow)
        now += 10
        controller.tick()
        XCTAssertEqual(controller.activeProfile, slow)      // no auto-restore for user switches
        XCTAssertNil(controller.safetyRestoreWarning)
    }

    func testButtonSwitchRestoresAfterFiveSeconds() {
        let store = makeStore()
        let controller = makeController(store)
        let profiles = store.settings.cursorSpeedProfiles
        let fast = profiles[2]                              // Fast

        controller.activate(profileID: fast.id, source: .buttonAction)
        XCTAssertEqual(controller.activeProfile, fast)
        XCTAssertNotNil(controller.safetyRestoreWarning)    // visible warning (Review Focus #1)

        now += 4
        controller.tick()
        XCTAssertEqual(controller.activeProfile, fast)      // not yet

        now += 1.5                                          // 5.5 s total
        controller.tick()
        XCTAssertEqual(controller.activeProfile, profiles[1])   // restored to Default
        XCTAssertNil(controller.safetyRestoreWarning)
    }

    func testSecondButtonSwitchReArmsTimer() {
        let store = makeStore()
        let controller = makeController(store)
        let profiles = store.settings.cursorSpeedProfiles

        controller.activate(profileID: profiles[0].id, source: .buttonAction)   // Slow
        now += 4
        controller.tick()
        controller.activate(profileID: profiles[2].id, source: .buttonAction)   // Fast, re-arm
        now += 4
        controller.tick()
        XCTAssertEqual(controller.activeProfile, profiles[2])   // still Fast (timer re-armed 4 s ago)
        now += 1.5
        controller.tick()
        XCTAssertEqual(controller.activeProfile, profiles[1])   // restored
    }

    // Slow: sensitivity 800 (0.5), acceleration 0 (1.0) → 0.5.
    // Fast: sensitivity 3200 (2.0), acceleration 2.0 → at speed 8: 1 + 2×1 = 3.0 → 6.0.
    func testPrecisionHoldOverridesActiveProfile() {
        let store = makeStore()
        var settings = store.settings
        settings.precisionProfileID = settings.cursorSpeedProfiles[0].id   // Slow
        settings.activeCursorSpeedProfileID = settings.cursorSpeedProfiles[2].id   // Fast
        store.settings = settings
        let controller = makeController(store)

        controller.beginPrecision()
        XCTAssertEqual(controller.outcome(forMove: .moved(dx: 8, dy: 0)),
                       .cursorTransform(dxFactor: 0.5, dyFactor: 0.5))
        controller.endPrecision()
        XCTAssertEqual(controller.outcome(forMove: .moved(dx: 8, dy: 0)),
                       .cursorTransform(dxFactor: 6.0, dyFactor: 6.0))
    }
}
