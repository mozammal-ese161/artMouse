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

public final class EventRouter: EventRouting {
    private let settings: SettingsStore
    private let executor: ActionExecuting
    private let clickLock: ClickLockCoordinating
    private let cursor: CursorControlling
    /// Buttons currently held, mapped to the hold action that began them.
    /// Keyed independently of the current bindings so a mid-hold unbind
    /// (live settings) still delivers endedHold on button-up.
    private var heldButtons: [ButtonID: Action] = [:]
    /// Buttons whose press started a click-lock interaction, recorded from the
    /// bindings at down time. Mirrors `heldButtons`: tracked independently of
    /// the current bindings so a mid-press unbind/rebind still delivers noteUp
    /// on button-up instead of stranding the coordinator in sticky-down.
    private var clickLockButtons: Set<ButtonID> = []

    public init(settings: SettingsStore, executor: ActionExecuting,
                clickLock: ClickLockCoordinating, cursor: CursorControlling) {
        self.settings = settings
        self.executor = executor
        self.clickLock = clickLock
        self.cursor = cursor
    }

    public func handle(_ event: InputEvent) -> RouterOutcome {
        switch event {
        case .buttonDown(let button): return handleDown(button)
        case .buttonUp(let button): return handleUp(button)
        case .moved, .dragged:
            return cursor.outcome(forMove: event)
        case .scrolled, .other:
            return .passThrough
        }
    }

    /// A matched binding with no actions behaves like no binding at all: both
    /// directions pass through with stock behavior. This is the defensive half
    /// of the unbind fix (AppModel removes the binding outright; an empty
    /// binding that survives elsewhere must never swallow a dead button).
    private func binding(for button: ButtonID) -> ButtonBinding? {
        settings.settings.buttonBindings.first { $0.button == button && !$0.actions.isEmpty }
    }

    private func handleDown(_ button: ButtonID) -> RouterOutcome {
        guard let binding = binding(for: button) else { return .passThrough }

        if binding.actions.contains(where: { $0.isClickLock }) {
            if clickLock.shouldSwallowDown(button) { return .consume }   // releasing a lock
            clickLockButtons.insert(button)
            clickLock.noteDown(button, now: Date().timeIntervalSince1970)
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

    private func handleUp(_ button: ButtonID) -> RouterOutcome {
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

        return .consume
    }
}
