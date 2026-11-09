import XCTest
@testable import ArtMouseCore

final class EventRouterTests: XCTestCase {
    private func store(_ settings: GlobalSettings) -> SettingsStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = SettingsStore(directory: dir)
        store.settings = settings
        return store
    }

    func testUnboundButtonPassesThrough() {
        let executor = RecordingExecutor()
        let router = EventRouter(settings: store(.default), executor: executor,
                                 clickLock: StubClickLock(), cursor: StubCursor())
        XCTAssertEqual(router.handle(.buttonDown(.fifth)), .passThrough)
        XCTAssertTrue(executor.performed.isEmpty)
    }

    func testTapBindingPerformsAndConsumes() {
        let executor = RecordingExecutor()
        var settings = GlobalSettings.default
        settings.buttonBindings = [ButtonBinding(button: .fourth, actions: [.mission(.missionControl, reverse: false)])]
        let router = EventRouter(settings: store(settings), executor: executor,
                                 clickLock: StubClickLock(), cursor: StubCursor())
        XCTAssertEqual(router.handle(.buttonDown(.fourth)), .consume)
        XCTAssertEqual(executor.performed, [.mission(.missionControl, reverse: false)])
    }

    func testHoldBindingBeginsAndEnds() {
        let executor = RecordingExecutor()
        var settings = GlobalSettings.default
        settings.buttonBindings = [ButtonBinding(button: .middle, actions: [.device(.switchPrecisionMode)])]
        let router = EventRouter(settings: store(settings), executor: executor,
                                 clickLock: StubClickLock(), cursor: StubCursor())
        XCTAssertEqual(router.handle(.buttonDown(.middle)), .consume)
        XCTAssertEqual(router.handle(.buttonUp(.middle)), .consume)
        XCTAssertEqual(executor.holdsBegan, [.device(.switchPrecisionMode)])
        XCTAssertEqual(executor.holdsEnded, [.device(.switchPrecisionMode)])
    }

    func testMoveDelegatesToCursor() {
        let executor = RecordingExecutor()
        let cursor = StubCursor(outcome: .cursorTransform(dxFactor: 0.5, dyFactor: 0.5))
        let router = EventRouter(settings: store(.default), executor: executor,
                                 clickLock: StubClickLock(), cursor: cursor)
        XCTAssertEqual(router.handle(.moved(dx: 3, dy: 4)), .cursorTransform(dxFactor: 0.5, dyFactor: 0.5))
    }

    func testScrollPassesThroughInPhase1() {
        let router = EventRouter(settings: store(.default), executor: RecordingExecutor(),
                                 clickLock: StubClickLock(), cursor: StubCursor())
        XCTAssertEqual(router.handle(.scrolled(axis: .vertical, ticks: 1)), .passThrough)
    }

    func testExtendedUnboundButtonPassesThrough() {
        let router = EventRouter(settings: store(.default), executor: RecordingExecutor(),
                                 clickLock: StubClickLock(), cursor: StubCursor())
        XCTAssertEqual(router.handle(.buttonDown(.extended(11))), .passThrough)
        XCTAssertEqual(router.handle(.buttonUp(.extended(11))), .passThrough)
    }
}

final class RecordingExecutor: ActionExecuting {
    private(set) var performed: [Action] = []
    private(set) var holdsBegan: [Action] = []
    private(set) var holdsEnded: [Action] = []
    func perform(_ action: Action) { performed.append(action) }
    func beganHold(_ action: Action) { holdsBegan.append(action) }
    func endedHold(_ action: Action) { holdsEnded.append(action) }
}

final class StubClickLock: ClickLockCoordinating {
    func noteDown(_ button: ButtonID, now: Double) {}
    func noteUp(_ button: ButtonID, now: Double) -> Bool { false }
    func isLocked(_ button: ButtonID) -> Bool { false }
    func shouldSwallowDown(_ button: ButtonID) -> Bool { false }
}

final class StubCursor: CursorControlling {
    let outcome: RouterOutcome
    init(outcome: RouterOutcome = .passThrough) { self.outcome = outcome }
    func outcome(forMove event: InputEvent) -> RouterOutcome { outcome }
}
