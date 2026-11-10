import Foundation

public protocol ClickLockCoordinating: AnyObject {
    /// A button-down for a click-lock bound button. `now` is seconds.
    func noteDown(_ button: ButtonID, now: Double)
    /// A button-up for a click-lock bound button. Returns true when the up
    /// should be swallowed (locked, or release after lock threshold).
    func noteUp(_ button: ButtonID, now: Double) -> Bool
    /// True while the lock is stuck down for this button.
    func isLocked(_ button: ButtonID) -> Bool
    /// A down arriving while locked releases the lock: swallow it.
    func shouldSwallowDown(_ button: ButtonID) -> Bool
}

public protocol CursorControlling: AnyObject {
    func outcome(forMove event: InputEvent) -> RouterOutcome
}

/// Runs and stops button-bound macro programs (Task 3). The router hands a
/// `.macro` binding's program to `run` on button-down and asks for a stop on
/// the matching button-up when the program repeats for the duration of the
/// hold; MacroEngine is the real implementation.
public protocol MacroCoordinating: AnyObject {
    func run(program: MacroProgram, for button: ButtonID)
    func stop(for button: ButtonID)
}

public final class EventRouter: EventRouting {
    private let settings: SettingsStore
    private let executor: ActionExecuting
    private let clickLock: ClickLockCoordinating
    private let cursor: CursorControlling
    /// Two-way scroll controller (Task 8 wires it); nil means stock scroll.
    private let scroll: ScrollControlling?
    /// Multi-button chord coordinator (Task 8 wires it); nil disables chords.
    /// Every button down and up passes through its intercept BEFORE binding
    /// resolution, so a chord capture can defer or swallow presses.
    private let chords: ChordCoordinating?
    /// Button-bound macro coordinator (Task 3 wires it); nil leaves `.macro`
    /// bindings inert (the executor's `.macro` arm is a no-op). Unlike holds
    /// and click-lock, macros are a distinct arm: the whole program runs on
    /// button-down, and only hold-mode programs register for an up-time stop.
    private let macros: MacroCoordinating?
    /// Frontmost-app source for per-app profile resolution (Phase 3 Task 5);
    /// nil (tests, pre-wiring) means every lookup uses the global settings.
    private let watcher: FrontmostProviding?
    /// Buttons currently held, mapped to the hold action that began them.
    /// Keyed independently of the current bindings so a mid-hold unbind
    /// (live settings) still delivers endedHold on button-up.
    private var heldButtons: [ButtonID: Action] = [:]
    /// Buttons whose press started a click-lock interaction, recorded from the
    /// bindings at down time. Mirrors `heldButtons`: tracked independently of
    /// the current bindings so a mid-press unbind/rebind still delivers noteUp
    /// on button-up instead of stranding the coordinator in sticky-down.
    private var clickLockButtons: Set<ButtonID> = []
    /// Buttons whose press started a hold-mode macro program, recorded from
    /// the bindings at down time. Mirrors `heldButtons`/`clickLockButtons`:
    /// tracked independently of the current bindings so a mid-hold unbind
    /// (live settings) still stops the program on button-up.
    private var macroHeldButtons: Set<ButtonID> = []

    public init(settings: SettingsStore, executor: ActionExecuting,
                clickLock: ClickLockCoordinating, cursor: CursorControlling,
                scroll: ScrollControlling? = nil, chords: ChordCoordinating? = nil,
                macros: MacroCoordinating? = nil, watcher: FrontmostProviding? = nil) {
        self.settings = settings
        self.executor = executor
        self.clickLock = clickLock
        self.cursor = cursor
        self.scroll = scroll
        self.chords = chords
        self.macros = macros
        self.watcher = watcher
    }

    public func handle(_ event: InputEvent) -> RouterOutcome {
        switch event {
        case .buttonDown(let button): return handleButtonDown(button)
        case .buttonUp(let button): return handleButtonUp(button)
        case .moved, .dragged:
            return cursor.outcome(forMove: event)
        case .scrolled(let axis, let ticks):
            return handleScroll(axis: axis, ticks: ticks)
        case .other:
            return .passThrough
        }
    }

    /// A wheel tick resolves its (axis, direction) binding and fires each of
    /// its actions once per tick — never amplified across a dense tick burst.
    /// Zero-tick events pass through BEFORE binding lookup (Task 6 review
    /// ruling): native momentum events can carry zero deltas, and a tick of 0
    /// would otherwise derive .down/.left and fire a binding for that
    /// direction. Unmatched ticks fall through to the scroll controller; nil
    /// controller (Task 8 wires it) means stock scroll behavior. The
    /// controller's disposition maps onto a routing outcome: intercepts
    /// consume the event (the emitter owns posting), scales become delta
    /// transforms.
    private func handleScroll(axis: ScrollAxis, ticks: Double) -> RouterOutcome {
        guard ticks != 0 else { return .passThrough }
        if let binding = scrollBinding(axis: axis, ticks: ticks) {
            for action in binding.actions { executor.perform(action) }
            return .consume
        }
        switch scroll?.disposition(forScroll: axis, ticks: ticks) ?? .passThrough {
        case .passThrough: return .passThrough
        case .scale(let vertical, let horizontal):
            return .scrollTransform(verticalFactor: vertical, horizontalFactor: horizontal)
        case .intercept: return .consume
        }
    }

    private func scrollBinding(axis: ScrollAxis, ticks: Double) -> ScrollBinding? {
        let direction = ScrollDirection.derived(axis: axis, ticks: ticks)
        return settings.settings.effectiveScrollBindings(for: watcher?.frontmostBundleID)
            .first { $0.axis == axis && $0.direction == direction && !$0.actions.isEmpty }
    }

    /// A matched binding with no actions behaves like no binding at all: both
    /// directions pass through with stock behavior. This is the defensive half
    /// of the unbind fix (AppModel removes the binding outright; an empty
    /// binding that survives elsewhere must never swallow a dead button).
    private func binding(for button: ButtonID) -> ButtonBinding? {
        settings.settings.effectiveButtonBindings(for: watcher?.frontmostBundleID)
            .first { $0.button == button && !$0.actions.isEmpty }
    }

    /// Chord intercept FIRST: a capture consumes or defers the press before
    /// any binding resolution (Task 7 contract). `.route` continues to normal
    /// resolution below; a `.flush` performs the held buttons' bindings, then
    /// re-sends the triggering event through intercept exactly once.
    private func handleButtonDown(_ button: ButtonID) -> RouterOutcome {
        guard let chords = chords else { return performNormalDown(button) }
        switch chords.intercept(.buttonDown(button), now: Date().timeIntervalSince1970) {
        case .route:
            return performNormalDown(button)
        case .consume:
            return .consume
        case .fire(let actions):
            for action in actions { executor.perform(action) }
            return .consume
        case .flush(let flushed):
            for flushedButton in flushed { performNormalDown(flushedButton) }
            // Re-send the triggering event through intercept exactly once —
            // safe: the flush cleared the capture, so this pass evaluates
            // fresh and cannot re-flush. Its side effects apply, but the
            // triggering press stays consumed: the capture swallowed it, and
            // only the flushed buttons' bindings leak through (pinned by
            // testChordFlushPerformsNormalBindingsThenReSends).
            switch chords.intercept(.buttonDown(button), now: Date().timeIntervalSince1970) {
            case .route:
                performNormalDown(button)
            case .consume:
                break
            case .fire(let actions):
                for action in actions { executor.perform(action) }
            case .flush:
                break   // nested flush: drop (one flush per event)
            }
            return .consume
        }
    }

    /// Mirror of the down path: chord intercept first. Chord ups during a
    /// capture consume (Task 7 contract), so a capture button's normal up
    /// never runs mid-capture; a `.flush` delivers the held buttons' ups, then
    /// re-sends the triggering up once through the cleared capture.
    private func handleButtonUp(_ button: ButtonID) -> RouterOutcome {
        guard let chords = chords else { return performNormalUp(button) }
        switch chords.intercept(.buttonUp(button), now: Date().timeIntervalSince1970) {
        case .route:
            return performNormalUp(button)
        case .consume:
            return .consume
        case .fire(let actions):
            for action in actions { executor.perform(action) }
            return .consume
        case .flush(let flushed):
            // Each flushed button delivers the binding its captured down
            // deferred: down-then-up per button. A deferred tap fires here
            // (the up path alone never performs taps); a deferred hold runs
            // beganHold and endedHold back to back (pinned by
            // testChordSoloReleaseRunsHoldLifecycle).
            for flushedButton in flushed {
                performNormalDown(flushedButton)
                performNormalUp(flushedButton)
            }
            switch chords.intercept(.buttonUp(button), now: Date().timeIntervalSince1970) {
            case .route:
                performNormalUp(button)
            case .consume:
                break
            case .fire(let actions):
                for action in actions { executor.perform(action) }
            case .flush:
                break   // nested flush: drop (one flush per event)
            }
            return .consume
        }
    }

    /// Normal binding resolution — the Phase 1 down path, chords stripped.
    private func performNormalDown(_ button: ButtonID) -> RouterOutcome {
        guard let binding = binding(for: button) else { return .passThrough }

        if binding.actions.contains(where: { $0.isClickLock }) {
            if clickLock.shouldSwallowDown(button) { return .consume }   // releasing a lock
            clickLockButtons.insert(button)
            clickLock.noteDown(button, now: Date().timeIntervalSince1970)
            return .consume
        }

        // Macro arm (Task 3): the whole program runs on the down, before the
        // hold-action loop — a macro is not an `isHoldAction`; it is a
        // distinct arm. A single-action binding is the macro shape: in any
        // other composition the executor's inert `.macro` arm applies. Hold
        // mode registers for the up-time stop; `.none` fires once per press.
        if case .macro(let steps, let repeatMode, let intervalMS, let proxy) = binding.actions.first,
           binding.actions.count == 1, let macros = macros {
            macros.run(program: MacroProgram(steps: steps, repeatMode: repeatMode,
                                             repeatIntervalMS: intervalMS, modifierProxy: proxy),
                       for: button)
            if repeatMode == .hold { macroHeldButtons.insert(button) }
            return .consume
        }

        for action in binding.actions where action.isHoldAction {
            heldButtons[button] = action
            executor.beganHold(action)
            return .consume
        }
        for action in binding.actions {
            executor.perform(action)
        }
        return .consume
    }

    /// Normal binding resolution — the Phase 1 up path (heldButtons and
    /// click-lock bookkeeping), chords stripped.
    private func performNormalUp(_ button: ButtonID) -> RouterOutcome {
        // Checked first, before the binding guard: macro membership is
        // recorded at down time, so a hold-mode macro whose binding was
        // unbound or rebound mid-press still stops its program on release.
        if macroHeldButtons.contains(button) {
            macroHeldButtons.remove(button)
            macros?.stop(for: button)
            return .consume
        }

        // Checked before the binding guard: bindings are live, and a button
        // unbound mid-hold must still end its hold.
        if let action = heldButtons.removeValue(forKey: button) {
            executor.endedHold(action)
            return .consume
        }

        // Checked before the binding guard too: click-lock membership is
        // recorded at down time, so a press whose binding was unbound or
        // rebound mid-press still releases the coordinator's sticky state.
        if clickLockButtons.contains(button) {
            clickLockButtons.remove(button)
            _ = clickLock.noteUp(button, now: Date().timeIntervalSince1970)
            return .consume   // coordinator decides posting (Task 9)
        }

        guard let binding = binding(for: button) else { return .passThrough }

        if binding.actions.contains(where: { $0.isClickLock }) {
            _ = clickLock.noteUp(button, now: Date().timeIntervalSince1970)
            return .consume   // coordinator decides posting (Task 9)
        }

        // A macro binding owns only the press: the program ran on down, and
        // the physical release routes natively so the OS sees a clean
        // button-up (pinned by testMacroHoldUpWithoutDownRoutes). Registered
        // hold releases were consumed by the macro arm above, so this tail is
        // only the unregistered cases: once-mode ups and ups with no
        // preceding down.
        if case .macro = binding.actions.first, binding.actions.count == 1 {
            return .passThrough
        }

        return .consume
    }
}
