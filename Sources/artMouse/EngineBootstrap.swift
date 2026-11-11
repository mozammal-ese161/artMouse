import AppKit
// SDK adaptation: the @MainActor annotation (Task 16 carried requirement) makes
// the Timer closures below cross a @Sendable boundary while carrying
// non-Sendable ArtMouseCore types. Every capture still lives and fires on the
// main run loop, so the pre-concurrency API assumption is safe here.
@preconcurrency import ArtMouseCore
import Combine

/// Assembles the engine stack and owns its timers. The SettingsStore,
/// DeviceManager, and AppWatcher are created by AppDelegate and shared with
/// the UI (Tasks 16 and 8); the bootstrap starts the watcher here. Main-thread
/// confined: start() must only ever be called from the main queue
/// (see the calling discipline below), and PermissionsController is
/// @MainActor since Task 16's UI observes it.
@Observable
@MainActor
final class EngineBootstrap {
    private let permissions: PermissionsController
    private let devices: DeviceManager
    private var cursor: CursorController?
    private var engine: EventTapEngine?
    private var tickTimer: Timer?
    private var deviceTimer: Timer?
    /// 8 ms cadence pump for the scroll emitter (Task 8).
    private var emitterDriver: Timer?
    private let appWatcher: AppWatcher
    /// Strong anchor: the executor holds snapping weakly (cycle hygiene), so
    /// the bootstrap owns the controller's lifetime. A class-level `let` cannot
    /// be assigned from start(), and the poster it shares is created there —
    /// optional var matches this class's idiom for engine-owned objects.
    private var snappingController: SnappingController?
    /// Hoisted for the same reason as `snappingController`: the tap-loss sink
    /// below must stop every running macro program when the tap dies (the
    /// button-up that stops a hold-mode loop would otherwise never arrive,
    /// leaving the loop repeating at its 10 ms interval floor forever).
    private var macroEngine: MacroEngine?
    /// Raw HID observation path (Phase 4): strong anchor, same idiom as
    /// `macroEngine` — the pump routes into the router created in start(), so
    /// a class-level `let` cannot hold it.
    private var hidPump: HIDEventPump?
    /// DPI feature reports (Phase 4): strong anchors, same idiom as
    /// `macroEngine`. The manager resolves the active profile for the
    /// executor's DPI arms, and the executor holds it weakly (cycle hygiene),
    /// so the bootstrap owns its lifetime. The sender is anchored because the
    /// applyLevel closure captures it weakly — without an owner it would
    /// deallocate when start() returns and every send would silently fail
    /// (permanent degradation).
    private var featureSender: IOKitFeatureReportSender?
    private var dpiManager: DPIManager?
    /// Shared with the Settings UI (created by AppDelegate): the pump logs
    /// every observation and the Device Analyzer sheet reads the same store.
    private let hidLog: HIDEventLog?
    private let hidAnalyzer: HIDAnalyzerStore?
    private var cancellable: AnyCancellable?

    /// Safety-restore warning mirrored from the cursor controller on every
    /// tick, so the Settings window renders it with @Observable tracking
    /// (spec §7 requires a visible warning; it previously lived only on the
    /// controller where nothing read it).
    public private(set) var safetyRestoreWarning: String?

    init(devices: DeviceManager, permissions: PermissionsController, appWatcher: AppWatcher,
         hidLog: HIDEventLog? = nil, hidAnalyzer: HIDAnalyzerStore? = nil) {
        self.permissions = permissions
        self.devices = devices
        self.appWatcher = appWatcher
        self.hidLog = hidLog
        self.hidAnalyzer = hidAnalyzer
    }

    func start(store: SettingsStore) {
        // Frontmost-app tracking (Task 18): NSWorkspace activation
        // notifications record which bundle ID is frontmost. Phase 3 Task 5's
        // per-app profiles consume it, so ONE watcher — constructed by
        // AppDelegate (Task 8) and shared with the UI, the router, and both
        // controllers — is started here; they must read the same activation
        // state, not stale copies. The notification block hops to the main
        // queue (see the calling discipline below), so the unsynchronized
        // `frontmostBundleID` write stays on the same thread as everything
        // else here.
        appWatcher.start()

        let cursorController = CursorController(store: store, watcher: appWatcher)
        self.cursor = cursorController

        // One poster shared by the executor (and the click-lock coordinator
        // behind it) AND the scroll emitter, so every synthetic event — clicks,
        // keys, scroll chunks — carries the same private-source tag the engine
        // tap uses to skip self-posted events (loop protection).
        let poster = CGEventPoster()
        let emitter = ScrollEmitter(poster: poster)
        let scrollController = ScrollController(store: store, emitter: emitter, watcher: appWatcher)
        let chordEngine = ChordEngine(settings: store)
        // Button-bound macros share the same poster so their synthetic keys
        // and clicks carry the private-source tag too (loop protection).
        let macroEngine = MacroEngine(poster: poster)
        self.macroEngine = macroEngine
        // Snapping shares the poster for the same loop-protection reason: the
        // warp-and-click events it posts must carry the private-source tag.
        let snappingController = SnappingController(finder: AXDefaultButtonFinder(), poster: poster)
        self.snappingController = snappingController
        // DPI feature reports (Phase 4): the manager resolves the first
        // enabled profile that declares DPI; the glue sender matches by
        // VID/PID. Send failures degrade in the executor (spec §3). Runs on
        // the tap-callback path, which stays on the main run loop (calling
        // discipline below).
        let featureSender = IOKitFeatureReportSender()
        self.featureSender = featureSender
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
        self.dpiManager = dpiManager
        let executor = ActionExecutor(poster: poster, cursor: cursorController, wheel: scrollController,
                                      snapping: snappingController, dpi: dpiManager)
        let clickLock = ClickLockCoordinator(executor: executor)
        let router = EventRouter(settings: store, executor: executor,
                                 clickLock: clickLock, cursor: cursorController,
                                 scroll: scrollController, chords: chordEngine,
                                 macros: macroEngine, watcher: appWatcher)
        let tapEngine = EventTapEngine(router: router, tapFactory: CGEventTapFactory(),
                                       isSelfPosted: { poster.owns($0) })
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
        // The loss ALSO strands hold-mode macros: with the tap gone, the
        // button-up that stops the loop never reaches the router, so the
        // program would repeat indefinitely (interval clamped to >= 10 ms)
        // with no input path to stop it. The sink therefore kills every
        // running program and clears the router's hold registry so each
        // stranded button's late up routes natively. The router stays alive
        // through the tap engine, hence the weak capture.
        cancellable = tapEngine.$tapActive
            .receive(on: RunLoop.main)
            .sink { [weak self, weak permissions, weak router] active in
                if !active {
                    permissions?.refresh()
                    permissions?.reportTapCreation(false)
                    self?.macroEngine?.stopAll()
                    router?.clearMacroHolds()
                }
            }

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
            analyzer: hidAnalyzer,
            // Vendor wheel parts (Final Review Issue 2): the HID path has no
            // real CGEvent for the router's .scrollTransform outcome to scale,
            // so the pump materializes it as a wheel event posted here — the
            // same shared tagged poster as every other synthetic event, so the
            // tag makes the tap pass it through unrouted (no re-fire of the
            // wheel binding).
            poster: poster)
        hidPump.start()
        self.hidPump = hidPump

        // Calling discipline: CursorController state (pendingRestore,
        // precisionActive, safetyRestoreWarning) is unsynchronized, so the tick
        // timer, the event-tap callback path, and any UI calls touching it must
        // run on ONE queue. The same holds for the Phase 2 scroll and chord
        // state — ScrollController's autoDirection, ScrollEmitter's mode and
        // keysDown (fed by the 8 ms pump below), and ChordEngine's capture —
        // which the event-tap callback path, the emitter pump, and wheel-mode
        // button actions all mutate. Phase 3's macro state joins the same
        // contract: MacroEngine's tasks/generations registries and the
        // router's macroHeldButtons are mutated only by run/stop on the
        // event-tap callback path; MacroEngine's spawned Tasks only post
        // events and sleep, hopping their finishTask back to the main actor.
        // SnappingController is stateless (it reads the AX frame and posts on
        // each call), so it is safe from any of those paths.
        // Every timer is scheduled on the current
        // (main) run loop, matching Timer.scheduledTimer(on: .main, ...)
        // semantics; CGEvent tap callbacks are delivered on that same main run
        // loop, and start() must therefore only ever be called from the main
        // queue. Each timer is additionally registered in .commonModes so it
        // keeps firing while a menu is tracked or a drag is in progress — the
        // tap's own run-loop source lives in .commonModes, so cursor ticks,
        // scroll pumps and device refreshes must not pause while tap callbacks
        // keep flowing.
        let tick = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self, weak cursorController] _ in
            cursorController?.tick()
            // SDK adaptation: Timer closures are @Sendable while this class is
            // @MainActor. The timer is scheduled on the main run loop (calling
            // discipline above), so the mirrored write is main-actor isolated.
            MainActor.assumeIsolated {
                self?.safetyRestoreWarning = cursorController?.safetyRestoreWarning
                // Tap self-heal: the tap is created once in start(); when that
                // failed (permission not yet granted) it stayed nil forever, so
                // a user granting Input Monitoring mid-run left the engine dead
                // until relaunch. Retry while the tap is absent: start() is a
                // no-op once the tap exists, and reportTapCreation keeps the
                // banner in sync with each retry's real result.
                if let tapEngine = self?.engine, !tapEngine.hasTap {
                    let started = tapEngine.start()
                    self?.permissions.reportTapCreation(started)
                    self?.permissions.refresh()
                }
            }
        }
        RunLoop.main.add(tick, forMode: .common)
        tickTimer = tick
        let deviceRefresh = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak devices] _ in
            devices?.refresh()
        }
        RunLoop.main.add(deviceRefresh, forMode: .common)
        deviceTimer = deviceRefresh

        // Scroll emitter cadence pump (Task 8): drains smooth-scroll chunks,
        // emits due auto ticks, and releases wheel-held keys. 8 ms matches the
        // emitter's smallest representable interval (intervalMS clamped to
        // >= 8); calling discipline above keeps it on the main run loop in
        // .common mode alongside the tap.
        let emitterDriver = Timer.scheduledTimer(withTimeInterval: 0.008, repeats: true) { [weak scrollController] _ in
            scrollController?.pumpEmitter()
        }
        RunLoop.main.add(emitterDriver, forMode: .common)
        self.emitterDriver = emitterDriver
    }
}
