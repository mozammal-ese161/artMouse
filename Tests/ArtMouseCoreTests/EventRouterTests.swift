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

    func testMidHoldUnbindStillEndsHold() {
        let executor = RecordingExecutor()
        var settings = GlobalSettings.default
        settings.buttonBindings = [ButtonBinding(button: .middle, actions: [.device(.switchPrecisionMode)])]
        let settingsStore = store(settings)
        let router = EventRouter(settings: settingsStore, executor: executor,
                                 clickLock: StubClickLock(), cursor: StubCursor())
        XCTAssertEqual(router.handle(.buttonDown(.middle)), .consume)
        XCTAssertEqual(executor.holdsBegan, [.device(.switchPrecisionMode)])

        settingsStore.settings = .default   // binding removed while the button is held

        XCTAssertEqual(router.handle(.buttonUp(.middle)), .consume)
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

    func testClickLockDownDelegatesToCoordinator() {
        let executor = RecordingExecutor()
        var settings = GlobalSettings.default
        settings.buttonBindings = [ButtonBinding(button: .fourth, actions: [.click(.clickLock, [])])]
        let clickLock = StubClickLock()
        let router = EventRouter(settings: store(settings), executor: executor,
                                 clickLock: clickLock, cursor: StubCursor())
        XCTAssertEqual(router.handle(.buttonDown(.fourth)), .consume)
        XCTAssertEqual(clickLock.swallowDownChecked, [.fourth])
        XCTAssertEqual(clickLock.downCalls.map(\.button), [.fourth])
        XCTAssertTrue(executor.performed.isEmpty)
    }

    func testClickLockUpDelegatesToCoordinator() {
        var settings = GlobalSettings.default
        settings.buttonBindings = [ButtonBinding(button: .fourth, actions: [.click(.clickLock, [])])]
        let clickLock = StubClickLock()
        let router = EventRouter(settings: store(settings), executor: RecordingExecutor(),
                                 clickLock: clickLock, cursor: StubCursor())
        XCTAssertEqual(router.handle(.buttonUp(.fourth)), .consume)
        XCTAssertEqual(clickLock.upCalls.map(\.button), [.fourth])
    }

    func testClickLockDownWhileLockedSwallowsWithoutNotingDown() {
        var settings = GlobalSettings.default
        settings.buttonBindings = [ButtonBinding(button: .fourth, actions: [.click(.clickLock, [])])]
        let clickLock = StubClickLock()
        clickLock.swallowDownResult = true
        let router = EventRouter(settings: store(settings), executor: RecordingExecutor(),
                                 clickLock: clickLock, cursor: StubCursor())
        XCTAssertEqual(router.handle(.buttonDown(.fourth)), .consume)
        XCTAssertEqual(clickLock.swallowDownChecked, [.fourth])
        XCTAssertTrue(clickLock.downCalls.isEmpty)
    }
}

final class RecordingExecutor: ActionExecuting {
    private(set) var performed: [Action] = []
    private(set) var holdsBegan: [Action] = []
    private(set) var holdsEnded: [Action] = []
    private(set) var postedButtons: [(ButtonID, Bool)] = []
    func perform(_ action: Action) { performed.append(action) }
    func beganHold(_ action: Action) { holdsBegan.append(action) }
    func endedHold(_ action: Action) { holdsEnded.append(action) }
    func postButton(_ id: ButtonID, down: Bool, mods: ModKeys) { postedButtons.append((id, down)) }
}

final class StubClickLock: ClickLockCoordinating {
    private(set) var swallowDownChecked: [ButtonID] = []
    private(set) var downCalls: [(button: ButtonID, now: Double)] = []
    private(set) var upCalls: [(button: ButtonID, now: Double)] = []
    var swallowDownResult = false
    var upSwallowResult = false
    func shouldSwallowDown(_ button: ButtonID) -> Bool {
        swallowDownChecked.append(button)
        return swallowDownResult
    }
    func noteDown(_ button: ButtonID, now: Double) {
        downCalls.append((button, now))
    }
    func noteUp(_ button: ButtonID, now: Double) -> Bool {
        upCalls.append((button, now))
        return upSwallowResult
    }
    func isLocked(_ button: ButtonID) -> Bool { false }
}

final class StubCursor: CursorControlling {
    let outcome: RouterOutcome
    init(outcome: RouterOutcome = .passThrough) { self.outcome = outcome }
    func outcome(forMove event: InputEvent) -> RouterOutcome { outcome }
}
