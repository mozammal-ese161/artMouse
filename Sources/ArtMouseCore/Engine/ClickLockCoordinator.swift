import Foundation

public final class ClickLockCoordinator: ClickLockCoordinating {
    private enum State {
        case idle
        case pressed(downTime: Double)
        case locked
    }

    private let executor: ActionExecuting
    private let clock: () -> Double
    private let threshold: Double
    private var states: [ButtonID: State] = [:]

    public init(executor: ActionExecuting,
                clock: @escaping () -> Double = { Date().timeIntervalSince1970 },
                threshold: Double = 0.5) {
        self.executor = executor
        self.clock = clock
        self.threshold = threshold
    }

    public func noteDown(_ button: ButtonID, now: Double) {
        if case .locked = state(for: button) {
            // Defensive: a caller that bypasses shouldSwallowDown must not
            // stack a second down on a sticky one. The router always checks
            // shouldSwallowDown first, which releases and clears before this.
            executor.postButton(button, down: false, mods: [])
            states[button] = .idle
            return
        }
        executor.postButton(button, down: true, mods: [])
        states[button] = .pressed(downTime: now)
    }

    public func noteUp(_ button: ButtonID, now: Double) -> Bool {
        switch state(for: button) {
        case .pressed(let downTime):
            if now - downTime >= threshold {
                states[button] = .locked          // swallow physical release
                return true
            }
            executor.postButton(button, down: false, mods: [])
            states[button] = .idle
            return false
        default:
            return false
        }
    }

    public func isLocked(_ button: ButtonID) -> Bool {
        if case .locked = state(for: button) { return true }
        return false
    }

    /// Called by the router on button-down. When locked, this releases the
    /// sticky down (posts the synthetic up, back to idle) so the router can
    /// swallow the physical press; a false answer leaves all state untouched.
    public func shouldSwallowDown(_ button: ButtonID) -> Bool {
        guard isLocked(button) else { return false }
        executor.postButton(button, down: false, mods: [])   // release sticky down
        states[button] = .idle
        return true
    }

    private func state(for button: ButtonID) -> State {
        states[button] ?? .idle
    }
}
