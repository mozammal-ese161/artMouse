/// Anything that can perform actions. ActionExecutor (Task 8) is the real
/// implementation; tests use recording doubles.
public protocol ActionExecuting: AnyObject {
    func perform(_ action: Action)
    func beganHold(_ action: Action)
    func endedHold(_ action: Action)
}

import CoreGraphics

public protocol EventPosting: AnyObject {
    func post(_ event: CGEvent)
}

public final class CGEventPoster: EventPosting {
    public init() {}
    public func post(_ event: CGEvent) {
        event.post(tap: .cghidEventTap)
    }
}
