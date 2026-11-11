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
import Foundation

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
        if event.type == .keyDown || event.type == .keyUp {
            postKeyboardAsChord(event)
            return
        }
        tag(event)
        event.post(tap: .cghidEventTap)
    }

    /// Source for keyboard posts: system shortcuts (Mission Control, Spaces
    /// switching) ignore synthetic keys from transient/private sources on
    /// this macOS build — they accept keys only from a persistent
    /// combined-session-state source (live-verified).
    private let keyboardSource = CGEventSource(stateID: .combinedSessionState)
    /// Modifier keys currently held by an in-flight keyboard chord.
    private var heldModifiers: [(CGEventFlags, CGKeyCode)] = []
    private let keyboardLock = NSLock()

    /// Expands a flag-carrying keyboard post into a REAL modifier chord:
    /// modifier key(s) down → key down → key up → modifier key(s) up, all
    /// from the combined-session source and untagged. A single event with
    /// pre-set flags — from a transient or private source — is silently
    /// ignored by system shortcuts on this macOS build. Keyboard events
    /// cannot loop: no binding triggers on keyboard events (they translate
    /// to `.other`), so the private-source tag is neither needed nor wanted
    /// here. The chord runs on the posting thread (~50 ms with the inter-
    /// event delays); the lock serializes the rare concurrent post.
    private func postKeyboardAsChord(_ event: CGEvent) {
        keyboardLock.lock()
        defer { keyboardLock.unlock() }
        let keyCode = CGKeyCode(clamping: max(0, event.getIntegerValueField(.keyboardEventKeycode)))
        let flags = event.flags
        let mods = CGFlagConversion.modifierKeyCodes(for: flags)
        if event.type == .keyDown {
            for (f, mk) in mods {
                if let d = CGEvent(keyboardEventSource: keyboardSource, virtualKey: mk, keyDown: true) {
                    d.post(tap: .cghidEventTap)
                    usleep(15_000)
                }
            }
            heldModifiers = mods
            if let d = CGEvent(keyboardEventSource: keyboardSource, virtualKey: keyCode, keyDown: true) {
                d.flags = flags
                d.post(tap: .cghidEventTap)
            }
        } else {
            if let u = CGEvent(keyboardEventSource: keyboardSource, virtualKey: keyCode, keyDown: false) {
                u.flags = flags
                u.post(tap: .cghidEventTap)
            }
            for (f, mk) in heldModifiers.reversed() {
                if let u = CGEvent(keyboardEventSource: keyboardSource, virtualKey: mk, keyDown: false) {
                    u.post(tap: .cghidEventTap)
                    usleep(15_000)
                }
            }
            heldModifiers = []
        }
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
