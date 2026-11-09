import CoreGraphics
import AppKit

public protocol EventRouting {
    func handle(_ event: InputEvent) -> RouterOutcome
}

/// Owns the CGEventTap, translates events to InputEvents, consults the
/// router, and applies the outcome to the real CGEvent. Re-enables the tap
/// after system wake (spec §7).
public final class EventTapEngine {
    private let router: EventRouting
    private let tapFactory: EventTapCreating
    private let notificationCenter: NotificationCenter
    private var tap: EventTapHandle?
    private var wakeObserver: NSObjectProtocol?

    /// Standard mouse event mask; raw-HID buttons beyond these arrive in
    /// phase 4 via HIDObserver.
    public static let eventMask: CGEventMask =
        (1 << CGEventType.leftMouseDown.rawValue)
        | (1 << CGEventType.leftMouseUp.rawValue)
        | (1 << CGEventType.rightMouseDown.rawValue)
        | (1 << CGEventType.rightMouseUp.rawValue)
        | (1 << CGEventType.otherMouseDown.rawValue)
        | (1 << CGEventType.otherMouseUp.rawValue)
        | (1 << CGEventType.mouseMoved.rawValue)
        | (1 << CGEventType.leftMouseDragged.rawValue)
        | (1 << CGEventType.rightMouseDragged.rawValue)
        | (1 << CGEventType.otherMouseDragged.rawValue)
        | (1 << CGEventType.scrollWheel.rawValue)

    public init(router: EventRouting, tapFactory: EventTapCreating,
                workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        self.router = router
        self.tapFactory = tapFactory
        self.notificationCenter = workspaceNotificationCenter
    }

    /// Returns false when the tap could not be created (missing permission).
    @discardableResult
    public func start() -> Bool {
        guard tap == nil else { return true }
        guard let handle = tapFactory.createTap(mask: Self.eventMask, callback: { [weak self] event, type in
            self?.process(event: event, type: type)
        }) else { return false }
        tap = handle
        registerWakeHandler()
        return true
    }

    public func stop() {
        tap?.disable()
        tap = nil
        if let observer = wakeObserver {
            notificationCenter.removeObserver(observer)
            wakeObserver = nil
        }
    }

    private func registerWakeHandler() {
        wakeObserver = notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.tap?.enable()
        }
    }

    func process(event: CGEvent, type: CGEventType) -> CGEvent? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            tap?.enable()
            return event
        }
        let input = CGEventTranslation.inputEvent(from: type, event)
        switch router.handle(input) {
        case .passThrough:
            return event
        case .consume:
            return nil
        case .cursorTransform(let dxFactor, let dyFactor):
            let dx = event.getIntegerValueField(.mouseEventDeltaX)
            let dy = event.getIntegerValueField(.mouseEventDeltaY)
            event.setIntegerValueField(.mouseEventDeltaX, value: Int64((Double(dx) * dxFactor).rounded()))
            event.setIntegerValueField(.mouseEventDeltaY, value: Int64((Double(dy) * dyFactor).rounded()))
            return event
        }
    }
}
