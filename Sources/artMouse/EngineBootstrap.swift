import AppKit
// SDK adaptation: the @MainActor annotation (Task 16 carried requirement) makes
// the Timer closures below cross a @Sendable boundary while carrying
// non-Sendable ArtMouseCore types. Every capture still lives and fires on the
// main run loop, so the pre-concurrency API assumption is safe here.
@preconcurrency import ArtMouseCore
import Combine

/// Assembles the engine stack and owns its timers. The SettingsStore and
/// DeviceManager are created by AppDelegate and shared with the UI (Task 16).
/// Main-thread confined: start() must only ever be called from the main queue
/// (see the calling discipline below), and PermissionsController is
/// @MainActor since Task 16's UI observes it.
@MainActor
final class EngineBootstrap {
    private let permissions: PermissionsController
    private let devices: DeviceManager
    private var cursor: CursorController?
    private var engine: EventTapEngine?
    private var tickTimer: Timer?
    private var deviceTimer: Timer?
    private var appWatcher: AppWatcher?
    private var cancellable: AnyCancellable?

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

        // Tap-loss watch (spec §7): when the system disables the tap mid-run
        // and the engine cannot recover it, `tapActive` flips false and the
        // permission banner is re-surfaced. Subscribed AFTER start() so the
        // replayed current value is the post-start `true` and the sink never
        // reports a loss that never happened. `receive(on:)` hops the emitted
        // values onto the main run loop, where PermissionsController is used.
        cancellable = tapEngine.$tapActive
            .receive(on: RunLoop.main)
            .sink { [weak permissions] active in
                if !active {
                    permissions?.refresh()
                    permissions?.reportTapCreation(false)
                }
            }

        // Calling discipline: CursorController state (pendingRestore,
        // precisionActive, safetyRestoreWarning) is unsynchronized, so the tick
        // timer, the event-tap callback path, and any UI calls touching it must
        // run on ONE queue. Both timers are scheduled on the current (main) run
        // loop, matching Timer.scheduledTimer(on: .main, ...) semantics; CGEvent
        // tap callbacks are delivered on that same main run loop, and start()
        // must therefore only ever be called from the main queue. Each timer is
        // additionally registered in .commonModes so it keeps firing while a
        // menu is tracked or a drag is in progress — the tap's own run-loop
        // source lives in .commonModes, so cursor ticks and device refreshes
        // must not pause while tap callbacks keep flowing.
        let tick = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak cursorController] _ in
            cursorController?.tick()
        }
        RunLoop.main.add(tick, forMode: .common)
        tickTimer = tick
        let deviceRefresh = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak devices] _ in
            devices?.refresh()
        }
        RunLoop.main.add(deviceRefresh, forMode: .common)
        deviceTimer = deviceRefresh

        // Frontmost-app tracking (Task 18): NSWorkspace activation
        // notifications record which bundle ID is frontmost. Phase 1 only
        // stores the value; Phase 3's per-app profiles consume it. The
        // notification block hops to the main queue (see the calling
        // discipline above), so the unsynchronized `frontmostBundleID` write
        // stays on the same thread as everything else here.
        let appWatcher = AppWatcher()
        self.appWatcher = appWatcher
        appWatcher.start()
    }
}
