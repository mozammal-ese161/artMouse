import CoreGraphics
import AppKit
import Combine

public protocol EventRouting {
    func handle(_ event: InputEvent) -> RouterOutcome
}

/// Owns the CGEventTap, translates events to InputEvents, consults the
/// router, and applies the outcome to the real CGEvent. Re-enables the tap
/// after system wake (spec §7) and publishes `tapActive` so the app can
/// re-surface the permission banner when the system disables the tap mid-run.
public final class EventTapEngine {
    private let router: EventRouting
    private let tapFactory: EventTapCreating
    private let notificationCenter: NotificationCenter
    private let isSelfPosted: (CGEvent) -> Bool
    private var tap: EventTapHandle?
    private var wakeObserver: NSObjectProtocol?

    /// False while no tap is running; true once `start()` succeeds, after any
    /// successful re-enable, and while events keep flowing through a live tap.
    /// Flips false when the tap reports disabled and re-enabling it failed —
    /// the bootstrap surfaces the permission banner from this.
    @Published public private(set) var tapActive: Bool = false

    /// Combine view of `tapActive` for observers (task-15 interface).
    public var tapActivePublisher: Published<Bool>.Publisher { $tapActive }

    /// True while no tap exists — i.e. creation failed (permission not yet
    /// granted) and a retry can succeed. Distinct from `tapActive`: a tap
    /// that exists but is disabled re-enables itself; an absent tap needs a
    /// fresh `start()`.
    public var hasTap: Bool { tap != nil }

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
                workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
                isSelfPosted: @escaping (CGEvent) -> Bool = { _ in false }) {
        self.router = router
        self.tapFactory = tapFactory
        self.notificationCenter = workspaceNotificationCenter
        self.isSelfPosted = isSelfPosted
    }

    /// Returns false when the tap could not be created (missing permission).
    @discardableResult
    public func start() -> Bool {
        guard tap == nil else { return true }
        guard let handle = tapFactory.createTap(mask: Self.eventMask, callback: { [weak self] event, type in
            self?.process(event: event, type: type)
        }) else { return false }
        tap = handle
        tapActive = true
        registerWakeHandler()
        return true
    }

    public func stop() {
        tap?.disable()
        tap = nil
        tapActive = false
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
            self?.syncTapActive()   // wake re-enable is a re-enable: reflect its result
        }
    }

    /// Mirrors the tap's real enabled state into `tapActive`. After a disabled
    /// event this reports whether the re-enable took; on ordinary events it
    /// marks recovery the moment traffic flows through a live tap again.
    /// The write is guarded: @Published re-publishes on every assignment, and
    /// this runs on every event, so an unchanged value must not emit.
    private func syncTapActive() {
        let active = tap?.isEnabled ?? false
        if tapActive != active { tapActive = active }
    }

    /// Diagnostic (--debug-buttons): when the launch flag is present, every
    /// button event reaching the tap is appended to
    /// ~/Library/Application Support/artMouse/button-debug.log — hardware
    /// truth for "my physical button does nothing" reports. Static so the
    /// tap callback can reach it without touching the instance graph.
    static let debugButtonLog: FileHandle? = {
        guard CommandLine.arguments.contains("--debug-buttons") else { return nil }
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("artMouse", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("button-debug.log")
        if !FileManager.default.fileExists(atPath: url.path) {
            try? Data().write(to: url)
        }
        return try? FileHandle(forWritingTo: url)
    }()

    func process(event: CGEvent, type: CGEventType) -> CGEvent? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            tap?.enable()
            syncTapActive()   // re-enable failed -> false (banner); recovered -> true
            return event
        }
        syncTapActive()
        // --debug-buttons: record hardware button events BEFORE routing so a
        // pressed-but-unrouted button is visible in the log.
        if Self.debugButtonLog != nil,
           type == .leftMouseDown || type == .leftMouseUp || type == .rightMouseDown
           || type == .rightMouseUp || type == .otherMouseDown || type == .otherMouseUp {
            let line = "\(Date()) type=\(type.rawValue) button=\(event.getIntegerValueField(.mouseEventButtonNumber))\n"
            try? Self.debugButtonLog?.write(contentsOf: line.data(using: .utf8)!)
        }
        // Loop protection: the app's own synthetic events (button remaps,
        // click-lock replay) must reach the system but never be routed again —
        // routing them would re-trigger the binding that posted them, looping
        // unbounded. Pass the event through unchanged (no consume, no transform).
        if isSelfPosted(event) { return event }
        let input = CGEventTranslation.inputEvent(from: type, event)
        let outcome = router.handle(input)
        // --debug-buttons (continued): the routing outcome shows whether a
        // binding matched (consume) or the event fell through (passThrough).
        // Scroll events are included: tilt-direction matching is exactly the
        // kind of sign/direction assumption this log exists to verify.
        if Self.debugButtonLog != nil,
           type == .leftMouseDown || type == .leftMouseUp || type == .rightMouseDown
           || type == .rightMouseUp || type == .otherMouseDown || type == .otherMouseUp {
            let line = "  -> outcome=\(outcome)\n"
            try? Self.debugButtonLog?.write(contentsOf: line.data(using: .utf8)!)
        }
        if Self.debugButtonLog != nil, type == .scrollWheel,
           case .scrolled(let axis, let ticks) = input {
            let line = "  SCROLL axis=\(axis == .vertical ? "v" : "h") ticks=\(ticks) outcome=\(outcome)\n"
            try? Self.debugButtonLog?.write(contentsOf: line.data(using: .utf8)!)
        }
        switch outcome {
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
        case .scrollTransform(let vFactor, let hFactor):
            let v = event.getDoubleValueField(.scrollWheelEventDeltaAxis1)
            let h = event.getDoubleValueField(.scrollWheelEventDeltaAxis2)
            event.setDoubleValueField(.scrollWheelEventDeltaAxis1, value: v * vFactor)
            event.setDoubleValueField(.scrollWheelEventDeltaAxis2, value: h * hFactor)
            return event
        }
    }
}
