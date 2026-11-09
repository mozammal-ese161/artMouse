import AppKit
import ArtMouseCore

/// Assembles the engine stack and owns its timers. The SettingsStore and
/// DeviceManager are created by AppDelegate and shared with the UI (Task 16).
final class EngineBootstrap {
    private let permissions: PermissionsController
    private let devices: DeviceManager
    private var cursor: CursorController?
    private var engine: EventTapEngine?
    private var tickTimer: Timer?
    private var deviceTimer: Timer?

    init(devices: DeviceManager, permissions: PermissionsController) {
        self.permissions = permissions
        self.devices = devices
    }

    func start(store: SettingsStore) {
        let cursorController = CursorController(store: store)
        self.cursor = cursorController

        let executor = ActionExecutor(poster: CGEventPoster(), cursor: cursorController)
        let clickLock = ClickLockCoordinator(executor: executor)
        let router = EventRouter(settings: store, executor: executor,
                                 clickLock: clickLock, cursor: cursorController)
        let tapEngine = EventTapEngine(router: router, tapFactory: CGEventTapFactory())
        self.engine = tapEngine

        let started = tapEngine.start()
        permissions.reportTapCreation(started)
        permissions.refresh()

        // Calling discipline: CursorController state (pendingRestore,
        // precisionActive, safetyRestoreWarning) is unsynchronized, so the tick
        // timer, the event-tap callback path, and any UI calls touching it must
        // run on ONE queue. Both timers are scheduled on the current (main) run
        // loop, matching Timer.scheduledTimer(on: .main, ...) semantics; CGEvent
        // tap callbacks are delivered on that same main run loop, and start()
        // must therefore only ever be called from the main queue.
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak cursorController] _ in
            cursorController?.tick()
        }
        deviceTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak devices] _ in
            devices?.refresh()
        }
    }
    // Tap-loss observation (`tapActive`) is added to this class in Task 15.
}
