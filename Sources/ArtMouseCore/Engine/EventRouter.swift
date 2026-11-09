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
    /// Buttons currently held that were activated with hold actions.
    private var heldButtons: Set<ButtonID> = []

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

    private func binding(for button: ButtonID) -> ButtonBinding? {
        settings.settings.buttonBindings.first { $0.button == button }
    }

    private func handleDown(_ button: ButtonID) -> RouterOutcome {
        guard let binding = binding(for: button) else { return .passThrough }

        if binding.actions.contains(where: { $0.isClickLock }) {
            if clickLock.shouldSwallowDown(button) { return .consume }   // releasing a lock
            clickLock.noteDown(button, now: Date().timeIntervalSince1970)
            return .consume
        }

        for action in binding.actions where action.isHoldAction {
            executor.beganHold(action)
            heldButtons.insert(button)
            return .consume
        }
        for action in binding.actions {
            executor.perform(action)
        }
        return .consume
    }

    private func handleUp(_ button: ButtonID) -> RouterOutcome {
        guard let binding = binding(for: button) else { return .passThrough }

        if binding.actions.contains(where: { $0.isClickLock }) {
            _ = clickLock.noteUp(button, now: Date().timeIntervalSince1970)
            return .consume   // coordinator decides posting (Task 9)
        }

        if heldButtons.contains(button) {
            heldButtons.remove(button)
            for action in binding.actions where action.isHoldAction {
                executor.endedHold(action)
            }
            return .consume
        }
        return .consume
    }
}
