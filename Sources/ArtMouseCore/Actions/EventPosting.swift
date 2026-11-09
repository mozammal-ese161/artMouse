/// Anything that can perform actions. ActionExecutor (Task 8) is the real
/// implementation; tests use recording doubles.
public protocol ActionExecuting: AnyObject {
    func perform(_ action: Action)
    func beganHold(_ action: Action)
    func endedHold(_ action: Action)
    /// Posts a raw button event. ClickLockCoordinator uses it to replay the
    /// physical press while locked and to release the lock with a synthetic up.
    func postButton(_ id: ButtonID, down: Bool, mods: ModKeys)
}

import CoreGraphics

public protocol EventPosting: AnyObject {
    func post(_ event: CGEvent)
}

/// Posts synthetic events to the HID-level tap. Every posted event is tagged
/// with the poster's private event source so the engine tap can recognize
/// (and pass through without routing) the app's own events — without this,
/// a self-posted event would re-enter the tap and re-trigger its own binding
/// in an unbounded loop.
public final class CGEventPoster: EventPosting {
    private let source: CGEventSource?
    /// SDK adaptation: the state ID of a private source is a unique per-source
    /// table ID, not the `kCGEventSourceStatePrivate` constant itself, and
    /// Swift has no CGEventGetSource — the source is read back from an event
    /// with `CGEventSource(event:)` (CGEventCreateSourceFromEvent). Ownership
    /// is therefore detected by comparing against this poster's own ID.
    private let privateStateID: CGEventSourceStateID?

    public init(sourceFactory: () -> CGEventSource? = { CGEventSource(stateID: .privateState) }) {
        let created = sourceFactory()
        source = created
        privateStateID = created?.sourceStateID
    }

    public func post(_ event: CGEvent) {
        tag(event)
        event.post(tap: .cghidEventTap)
    }

    /// Marks the event as this poster's own. Internal so tests can tag events
    /// without posting real HID input into the running session.
    func tag(_ event: CGEvent) {
        if let source { event.setSource(source) }
    }

    /// True when the event was tagged by this poster.
    public func owns(_ event: CGEvent) -> Bool {
        guard let privateStateID, let eventSource = CGEventSource(event: event) else { return false }
        return eventSource.sourceStateID == privateStateID
    }
}
