import XCTest
@testable import ArtMouseCore

final class DeviceOpTests: XCTestCase {
    private func makeStore() -> SettingsStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return SettingsStore(directory: dir)
    }

    func testActivateCursorSpeedAdvancesProfile() {
        let store = makeStore()
        let controller = CursorController(store: store)
        let executor = ActionExecutor(poster: RecordingPoster(), cursor: controller)
        XCTAssertEqual(controller.activeProfile?.name, "Default")
        executor.perform(.device(.activateCursorSpeed(nil)))
        XCTAssertEqual(controller.activeProfile?.name, "Fast")     // next in default order
    }

    func testPrecisionHoldLifecycle() {
        let store = makeStore()
        var settings = store.settings
        settings.precisionProfileID = settings.cursorSpeedProfiles[0].id
        store.settings = settings
        let controller = CursorController(store: store)
        let executor = ActionExecutor(poster: RecordingPoster(), cursor: controller)

        executor.beganHold(.device(.switchPrecisionMode))
        XCTAssertEqual(controller.outcome(forMove: .moved(dx: 8, dy: 0)),
                       .cursorTransform(dxFactor: 0.5, dyFactor: 0.5))   // Slow active while held
        executor.endedHold(.device(.switchPrecisionMode))
        XCTAssertNotEqual(controller.outcome(forMove: .moved(dx: 8, dy: 0)),
                          .cursorTransform(dxFactor: 0.5, dyFactor: 0.5))
    }

    func testDPIAndWheelOpsAreNoOps() {
        let executor = ActionExecutor(poster: RecordingPoster(), cursor: nil)
        executor.perform(.device(.dpiCycle))
        executor.perform(.device(.dpiUp))
        executor.perform(.device(.dpiDown))
        executor.perform(.device(.dpiShift))
        executor.perform(.device(.defaultDPI))
        executor.perform(.device(.switchWheelMode))
        // no crash, no state change; UI disables these (Task 16)
    }
}
