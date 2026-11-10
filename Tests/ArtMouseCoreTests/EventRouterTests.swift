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

    // A zombie binding (present with no actions) must behave like an unbound
    // button: both directions pass through and the executor stays untouched.
    func testEmptyActionsBindingPassesThrough() {
        let executor = RecordingExecutor()
        var settings = GlobalSettings.default
        settings.buttonBindings = [ButtonBinding(button: .fourth, actions: [])]
        let router = EventRouter(settings: store(settings), executor: executor,
                                 clickLock: StubClickLock(), cursor: StubCursor())
        XCTAssertEqual(router.handle(.buttonDown(.fourth)), .passThrough)
        XCTAssertEqual(router.handle(.buttonUp(.fourth)), .passThrough)
        XCTAssertTrue(executor.performed.isEmpty)
        XCTAssertTrue(executor.postedButtons.isEmpty)
    }

    // Click-lock state is tracked at down time, so an unbind (live settings)
    // mid-press must still notify the coordinator on button-up.
    func testClickLockUpAfterUnbindStillNotifies() {
        var settings = GlobalSettings.default
        settings.buttonBindings = [ButtonBinding(button: .middle, actions: [.click(.clickLock, [])])]
        let settingsStore = store(settings)
        let clickLock = StubClickLock()
        let router = EventRouter(settings: settingsStore, executor: RecordingExecutor(),
                                 clickLock: clickLock, cursor: StubCursor())
        XCTAssertEqual(router.handle(.buttonDown(.middle)), .consume)
        XCTAssertEqual(clickLock.downCalls.map(\.button), [.middle])

        settingsStore.settings = .default   // binding removed while pressed

        XCTAssertEqual(router.handle(.buttonUp(.middle)), .consume)
        XCTAssertEqual(clickLock.upCalls.map(\.button), [.middle])
    }

    func testScrollBindingFiresOncePerTick() {
        let executor = RecordingExecutor()
        var settings = GlobalSettings.default
        settings.scrollBindings = [ScrollBinding(axis: .vertical, direction: .up,
                                                 actions: [.mission(.missionControl, reverse: false)])]
        let router = EventRouter(settings: store(settings), executor: executor,
                                 clickLock: StubClickLock(), cursor: StubCursor())
        XCTAssertEqual(router.handle(.scrolled(axis: .vertical, ticks: 1)), .consume)
        XCTAssertEqual(executor.performed.count, 1)
        // Burst: dense tick stream fires once per tick, never amplified.
        for _ in 0..<10 { _ = router.handle(.scrolled(axis: .vertical, ticks: 2)) }
        XCTAssertEqual(executor.performed.count, 11)
    }

    func testScrollBindingDirectionMatching() {
        let executor = RecordingExecutor()
        var settings = GlobalSettings.default
        settings.scrollBindings = [ScrollBinding(axis: .vertical, direction: .up, actions: [.none])]
        let router = EventRouter(settings: store(settings), executor: executor,
                                 clickLock: StubClickLock(), cursor: StubCursor())
        XCTAssertEqual(router.handle(.scrolled(axis: .vertical, ticks: -1)), .passThrough)  // down ≠ up
        XCTAssertEqual(router.handle(.scrolled(axis: .horizontal, ticks: 1)), .passThrough) // axis ≠
    }

    func testUnboundScrollFallsThroughToController() {
        // No bindings, no controller (nil) → passThrough (Phase 1 behavior).
        let router = EventRouter(settings: store(.default), executor: RecordingExecutor(),
                                 clickLock: StubClickLock(), cursor: StubCursor())
        XCTAssertEqual(router.handle(.scrolled(axis: .vertical, ticks: 1)), .passThrough)
    }

    // Task 6 review ruling (landed in Task 8): the zero-tick guard sits BEFORE
    // binding lookup — otherwise a tick of 0 derives .down/.left and a binding
    // for that direction fires (and consumes) on a delta-less momentum event.
    func testZeroTickScrollPassesThroughBeforeBindings() {
        let executor = RecordingExecutor()
        var settings = GlobalSettings.default
        settings.scrollBindings = [ScrollBinding(axis: .vertical, direction: .down,
                                                 actions: [.mission(.missionControl, reverse: false)])]
        let router = EventRouter(settings: store(settings), executor: executor,
                                 clickLock: StubClickLock(), cursor: StubCursor())
        XCTAssertEqual(router.handle(.scrolled(axis: .vertical, ticks: 0)), .passThrough)
        XCTAssertTrue(executor.performed.isEmpty)
    }

    // Phase 3 Task 5: a matching app profile's button bindings replace the
    // global ones while its app is frontmost; switching the watcher to an
    // unprofiled app falls back to the global binding (here [.none], so the
    // press matches, consumes, and performs nothing).
    func testAppProfileOverridesBindingsWhenFrontmost() {
        let executor = RecordingExecutor()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = SettingsStore(directory: dir)
        var settings = store.settings
        settings.buttonBindings = [ButtonBinding(button: .fourth, actions: [.none])]
        let appBinding = ButtonBinding(button: .fourth, actions: [.mission(.missionControl, reverse: false)])
        settings.appProfiles = [AppProfile(bundleID: "com.apple.Safari", name: "Safari",
                                           buttonBindings: [appBinding], scrollBindings: nil,
                                           cursorSpeedProfileID: nil, wheelModeProfileID: nil)]
        store.settings = settings
        let watcher = StubWatcher(bundleID: "com.apple.Safari")
        let router = EventRouter(settings: store, executor: executor,
                                 clickLock: StubClickLock(), cursor: StubCursor(),
                                 watcher: watcher)
        XCTAssertEqual(router.handle(.buttonDown(.fourth)), .consume)
        XCTAssertEqual(executor.performed, [.mission(.missionControl, reverse: false)])

        watcher.frontmostBundleID = "com.apple.TextEdit"     // no profile → global
        // Global binding is [.none] (non-empty → matched → .consume, performing nothing)
        XCTAssertEqual(router.handle(.buttonUp(.fourth)), .consume)
    }

    // Task 5 pin: buttons 6+ route through the SAME chord arm as standard
    // buttons — the capture consumes the press and the chord fires on
    // completion. Pinned against the real ChordEngine (no stub exists for it).
    func testExtendedButtonChordCapturesAndFires() {
        let executor = RecordingExecutor()
        var settings = GlobalSettings.default
        settings.chords = [Chord(buttons: [.extended(5), .extended(6)],
                                 actions: [.mission(.missionControl, reverse: false)],
                                 timeout: 1.0)]
        let settingsStore = store(settings)
        let engine = ChordEngine(settings: settingsStore)
        let router = EventRouter(settings: settingsStore, executor: executor,
                                 clickLock: StubClickLock(), cursor: StubCursor(), chords: engine)
        XCTAssertEqual(router.handle(.buttonDown(.extended(5))), .consume)
        XCTAssertEqual(router.handle(.buttonDown(.extended(6))), .consume)
        XCTAssertEqual(executor.performed, [.mission(.missionControl, reverse: false)])
    }

    // Task 5 pin: an extended button with a single-action macro binding runs
    // the program on down, exactly like standard buttons.
    func testExtendedButtonMacroRunsProgram() {
        let engine = RecordingMacroEngine()
        var settings = GlobalSettings.default
        settings.buttonBindings = [ButtonBinding(button: .extended(7), actions: [
            Action.macro(steps: [.enterKey(keyCode: 36, mods: [])], repeatMode: .none,
                         repeatIntervalMS: 0, modifierProxy: false),
        ])]
        let router = EventRouter(settings: store(settings), executor: RecordingExecutor(),
                                 clickLock: StubClickLock(), cursor: StubCursor(), macros: engine)
        XCTAssertEqual(router.handle(.buttonDown(.extended(7))), .consume)
        XCTAssertEqual(engine.ran.count, 1)
        XCTAssertEqual(engine.ran[0].1, .extended(7))
    }

    // Phase 3 carry: a chord-captured press defers its binding, so a
    // click-lock button held inside a capture never reached the coordinator
    // at down time. When the initiator's release flushes the capture, the
    // flush's down-then-up pair must drive the full noteDown/noteUp
    // lifecycle — no stranded sticky state. Pinned against the real
    // ChordEngine (no chord stub exists); StubClickLock already records
    // noteDown/noteUp. The third chord button keeps [.fifth, .middle] from
    // COMPLETING on the middle press (which would fire the chord and clear
    // the capture, leaving no up-flush to observe).
    func testChordFlushRunsClickLockLifecycleForFlushedButton() {
        var settings = GlobalSettings.default
        settings.buttonBindings = [ButtonBinding(button: .fifth, actions: [.click(.clickLock, [])])]
        settings.chords = [Chord(buttons: [.fifth, .middle, .fourth],
                                 actions: [.click(.left, [])], timeout: 10.0)]
        let settingsStore = store(settings)
        let clickLock = StubClickLock()
        let router = EventRouter(settings: settingsStore, executor: RecordingExecutor(),
                                 clickLock: clickLock, cursor: StubCursor(),
                                 chords: ChordEngine(settings: settingsStore))
        XCTAssertEqual(router.handle(.buttonDown(.fifth)), .consume)   // captured
        XCTAssertTrue(clickLock.downCalls.isEmpty, "capture defers the noteDown")
        XCTAssertEqual(router.handle(.buttonDown(.middle)), .consume)  // capture extends
        XCTAssertEqual(router.handle(.buttonUp(.fifth)), .consume)     // initiator release → flush
        // The flush's down-then-up pair drove the coordinator for the flushed
        // click-lock button; middle (no click-lock binding) drove none.
        XCTAssertEqual(clickLock.downCalls.map(\.button), [.fifth])
        // The second up is the flush's re-sent initiator release re-entering
        // the click-lock arm (the flush already cleared the router's
        // membership set, so the still-live binding claims it again) —
        // benign with the real coordinator, whose idle noteUp posts nothing;
        // recorded here as the real sequence.
        XCTAssertEqual(clickLock.upCalls.map(\.button), [.fifth, .fifth])
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

/// Frontmost-app test double (Phase 3 Task 5). Defined once here, module
/// visible: the router, cursor, and scroll suites all drive watcher-driven
/// per-app resolution through the same `FrontmostProviding` seam.
final class StubWatcher: FrontmostProviding {
    var frontmostBundleID: String?
    init(bundleID: String?) { self.frontmostBundleID = bundleID }
}

/// Recording macro coordinator. Moved to file scope (Phase 4 Task 5) so the
/// extended-button pin in EventRouterTests reuses the same double instead of
/// duplicating it; behavior unchanged.
final class RecordingMacroEngine: MacroCoordinating {
    private(set) var ran: [(MacroProgram, ButtonID)] = []
    private(set) var stopped: [ButtonID] = []
    func run(program: MacroProgram, for button: ButtonID) { ran.append((program, button)) }
    func stop(for button: ButtonID) { stopped.append(button) }
}

final class RouterChordTests: XCTestCase {
    private func makeStore(_ settings: GlobalSettings) -> SettingsStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = SettingsStore(directory: dir)
        store.settings = settings
        return store
    }

    func testChordFirePerformsActionsAndConsumes() {
        let executor = RecordingExecutor()
        var settings = GlobalSettings.default
        settings.chords = [Chord(buttons: [.middle, .fourth],
                                 actions: [.mission(.missionControl, reverse: false)])]
        let settingsStore = makeStore(settings)
        let engine = ChordEngine(settings: settingsStore)
        let router = EventRouter(settings: settingsStore, executor: executor,
                                 clickLock: StubClickLock(), cursor: StubCursor(), chords: engine)
        XCTAssertEqual(router.handle(.buttonDown(.middle)), .consume)   // captured
        XCTAssertTrue(executor.performed.isEmpty)
        XCTAssertEqual(router.handle(.buttonDown(.fourth)), .consume)   // fired
        XCTAssertEqual(executor.performed, [.mission(.missionControl, reverse: false)])
    }

    func testChordFlushPerformsNormalBindingsThenReSends() {
        let executor = RecordingExecutor()
        var settings = GlobalSettings.default
        settings.buttonBindings = [ButtonBinding(button: .middle, actions: [.mission(.launchpad, reverse: false)])]
        settings.chords = [Chord(buttons: [.middle, .fourth], actions: [.click(.left, [])], timeout: 0.3)]
        let settingsStore = makeStore(settings)
        let engine = ChordEngine(settings: settingsStore)
        let router = EventRouter(settings: settingsStore, executor: executor,
                                 clickLock: StubClickLock(), cursor: StubCursor(), chords: engine)
        XCTAssertEqual(router.handle(.buttonDown(.middle)), .consume)              // captured, not performed
        XCTAssertTrue(executor.performed.isEmpty)
        // Fifth extends nothing → immediate flush of held [middle]; the router
        // performs middle's normal binding, then re-sends fifth (routed,
        // unbound → nothing extra).
        XCTAssertEqual(router.handle(.buttonDown(.fifth)), .consume)
        XCTAssertEqual(executor.performed, [.mission(.launchpad, reverse: false)])
        XCTAssertEqual(executor.performed.count, 1)
    }

    func testChordStartButtonOwnBindingDeferredNotFiredDuringCapture() {
        let executor = RecordingExecutor()
        var settings = GlobalSettings.default
        settings.buttonBindings = [ButtonBinding(button: .middle, actions: [.music(.playPause, fineTune: false)])]
        settings.chords = [Chord(buttons: [.middle, .fourth], actions: [.click(.left, [])], timeout: 10.0)]
        let settingsStore = makeStore(settings)
        let engine = ChordEngine(settings: settingsStore)
        let router = EventRouter(settings: settingsStore, executor: executor,
                                 clickLock: StubClickLock(), cursor: StubCursor(), chords: engine)
        XCTAssertEqual(router.handle(.buttonDown(.middle)), .consume)
        XCTAssertEqual(executor.performed, [Action](), "capture defers the binding")
        // Completing the chord fires the chord's actions — still not the start
        // button's own binding.
        XCTAssertEqual(router.handle(.buttonDown(.fourth)), .consume)
        XCTAssertEqual(executor.performed, [.click(.left, [])])
    }

    // Up-path mirror: chord ups pass through the same intercept as downs.
    // Releasing the initiator flushes all held buttons: each flushed button
    // runs its deferred binding down-then-up — a hold begins and ends
    // instantly — and the cleared capture lets the next press resolve its own
    // binding normally.
    func testChordUpFlushRunsDeferredDownThenUpAndClearsCapture() {
        let executor = RecordingExecutor()
        var settings = GlobalSettings.default
        settings.buttonBindings = [
            ButtonBinding(button: .middle, actions: [.device(.switchPrecisionMode)]),
            ButtonBinding(button: .fourth, actions: [.music(.playPause, fineTune: false)]),
        ]
        settings.chords = [Chord(buttons: [.middle, .fourth], actions: [.click(.left, [])], timeout: 10.0)]
        let settingsStore = makeStore(settings)
        let engine = ChordEngine(settings: settingsStore)
        let router = EventRouter(settings: settingsStore, executor: executor,
                                 clickLock: StubClickLock(), cursor: StubCursor(), chords: engine)
        XCTAssertEqual(router.handle(.buttonDown(.middle)), .consume)
        XCTAssertTrue(executor.holdsBegan.isEmpty)   // capture defers the hold
        XCTAssertEqual(router.handle(.buttonUp(.middle)), .consume)   // initiator release → flush
        XCTAssertEqual(executor.holdsBegan, [.device(.switchPrecisionMode)])
        XCTAssertEqual(executor.holdsEnded, [.device(.switchPrecisionMode)])   // flushed hold runs began+ended
        XCTAssertTrue(executor.performed.isEmpty)    // the hold binding has no tap action
        XCTAssertEqual(router.handle(.buttonDown(.fourth)), .consume)   // capture cleared
        XCTAssertEqual(executor.performed, [.music(.playPause, fineTune: false)])
    }

    // A chord initiator released alone (solo release) must not swallow its own
    // binding: the flush performs the deferred down — which fires the tap —
    // before the up.
    func testChordSoloReleaseFiresDeferredTapBinding() {
        let executor = RecordingExecutor()
        var settings = GlobalSettings.default
        settings.buttonBindings = [ButtonBinding(button: .middle, actions: [.music(.playPause, fineTune: false)])]
        settings.chords = [Chord(buttons: [.middle, .fourth], actions: [.click(.left, [])], timeout: 10.0)]
        let settingsStore = makeStore(settings)
        let engine = ChordEngine(settings: settingsStore)
        let router = EventRouter(settings: settingsStore, executor: executor,
                                 clickLock: StubClickLock(), cursor: StubCursor(), chords: engine)
        XCTAssertEqual(router.handle(.buttonDown(.middle)), .consume)
        XCTAssertTrue(executor.performed.isEmpty, "capture defers the binding")
        XCTAssertEqual(router.handle(.buttonUp(.middle)), .consume)
        XCTAssertEqual(executor.performed, [.music(.playPause, fineTune: false)])
    }

    // Hold semantics on a solo release: the deferred hold is flushed at
    // release time and runs its full lifecycle instantly (began then ended).
    func testChordSoloReleaseRunsHoldLifecycle() {
        let executor = RecordingExecutor()
        var settings = GlobalSettings.default
        settings.buttonBindings = [ButtonBinding(button: .middle, actions: [.device(.switchPrecisionMode)])]
        settings.chords = [Chord(buttons: [.middle, .fourth], actions: [.click(.left, [])], timeout: 10.0)]
        let settingsStore = makeStore(settings)
        let engine = ChordEngine(settings: settingsStore)
        let router = EventRouter(settings: settingsStore, executor: executor,
                                 clickLock: StubClickLock(), cursor: StubCursor(), chords: engine)
        XCTAssertEqual(router.handle(.buttonDown(.middle)), .consume)
        XCTAssertTrue(executor.holdsBegan.isEmpty)
        XCTAssertEqual(router.handle(.buttonUp(.middle)), .consume)
        XCTAssertEqual(executor.holdsBegan, [.device(.switchPrecisionMode)])
        XCTAssertEqual(executor.holdsEnded, [.device(.switchPrecisionMode)])
    }
}

final class RouterMacroTests: XCTestCase {
    private func macroStore(_ action: Action) -> SettingsStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = SettingsStore(directory: dir)
        store.settings.buttonBindings = [ButtonBinding(button: .fourth, actions: [action])]
        return store
    }

    func testMacroOnceRunsOnDown() {
        let engine = RecordingMacroEngine()
        let action = Action.macro(steps: [.enterKey(keyCode: 5, mods: [])], repeatMode: .none,
                                  repeatIntervalMS: 100, modifierProxy: false)
        let router = EventRouter(settings: macroStore(action), executor: RecordingExecutor(),
                                 clickLock: StubClickLock(), cursor: StubCursor(), macros: engine)
        XCTAssertEqual(router.handle(.buttonDown(.fourth)), .consume)
        XCTAssertEqual(engine.ran.count, 1)
        XCTAssertEqual(engine.ran[0].1, .fourth)
        XCTAssertEqual(engine.stopped, [])
    }

    func testMacroHoldRunsOnDownAndStopsOnUp() {
        let engine = RecordingMacroEngine()
        let action = Action.macro(steps: [.enterKey(keyCode: 5, mods: [])], repeatMode: .hold,
                                  repeatIntervalMS: 100, modifierProxy: false)
        let router = EventRouter(settings: macroStore(action), executor: RecordingExecutor(),
                                 clickLock: StubClickLock(), cursor: StubCursor(), macros: engine)
        XCTAssertEqual(router.handle(.buttonDown(.fourth)), .consume)
        XCTAssertEqual(engine.ran.count, 1)
        XCTAssertEqual(router.handle(.buttonUp(.fourth)), .consume)
        XCTAssertEqual(engine.stopped, [.fourth])
    }

    func testMacroHoldUpWithoutDownRoutes() {
        let engine = RecordingMacroEngine()
        let action = Action.macro(steps: [], repeatMode: .hold, repeatIntervalMS: 100, modifierProxy: false)
        let router = EventRouter(settings: macroStore(action), executor: RecordingExecutor(),
                                 clickLock: StubClickLock(), cursor: StubCursor(), macros: engine)
        XCTAssertEqual(router.handle(.buttonUp(.fourth)), .passThrough)
        XCTAssertEqual(engine.stopped, [])
    }

    // Tap-loss wiring (bootstrap sink): when the tap dies mid-hold, the
    // button-up that would stop a hold-mode macro never arrives. The sink
    // therefore stops the engine wholesale (stopAll — app-target code, not
    // unit-testable) AND clears the router's hold registry, so the stranded
    // button's late up routes natively instead of re-stopping an already-dead
    // program. This test pins the router half of that contract.
    func testTapLossClearsMacroHolds() {
        let engine = RecordingMacroEngine()
        let action = Action.macro(steps: [.enterKey(keyCode: 5, mods: [])], repeatMode: .hold,
                                  repeatIntervalMS: 100, modifierProxy: false)
        let router = EventRouter(settings: macroStore(action), executor: RecordingExecutor(),
                                 clickLock: StubClickLock(), cursor: StubCursor(), macros: engine)
        XCTAssertEqual(router.handle(.buttonDown(.fourth)), .consume)
        router.clearMacroHolds()
        XCTAssertEqual(router.handle(.buttonUp(.fourth)), .passThrough)
        XCTAssertEqual(engine.stopped, [], "engine side is handled by stopAll at bootstrap level, not per-button")
    }
}
