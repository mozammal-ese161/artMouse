import CoreGraphics

public protocol EventTapHandle: AnyObject {
    func enable()
    func disable()
    var isEnabled: Bool { get }
}

public protocol EventTapCreating {
    /// Returns nil when the tap cannot be created (missing permission).
    func createTap(mask: CGEventMask, callback: @escaping (CGEvent, CGEventType) -> CGEvent?) -> EventTapHandle?
}

/// Box so the C callback can reach the Swift closure (CGEventTapCreate's
/// Swift binding takes no userInfo; we pass a retained pointer ourselves).
final class EventTapCallbackBox {
    var handler: ((CGEvent, CGEventType) -> CGEvent?)?
    func handle(type: CGEventType, event: CGEvent) -> CGEvent? {
        handler?(event, type)
    }
}

public final class CGEventTapFactory: EventTapCreating {
    public init() {}

    public func createTap(mask: CGEventMask, callback: @escaping (CGEvent, CGEventType) -> CGEvent?) -> EventTapHandle? {
        let box = EventTapCallbackBox()
        box.handler = callback
        // One +1 retain whose opaque pointer travels to the C callback as
        // userInfo; CGEventTapHandleImp owns it and releases it in deinit.
        let boxPointer = Unmanaged.passRetained(box).toOpaque()
        // SDK adaptation: this SDK renames CGEventTapCreate to the static
        // CGEvent.tapCreate(tap:place:options:eventsOfInterest:callback:userInfo:)
        // and kCGSessionEventTap to CGEventTapLocation.cgSessionEventTap; the
        // C callback returns Unmanaged<CGEvent>?, so handler results are wrapped
        // with passUnretained.
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let box = Unmanaged<EventTapCallbackBox>.fromOpaque(userInfo).takeUnretainedValue()
                return box.handle(type: type, event: event).map { Unmanaged.passUnretained($0) }
            },
            userInfo: boxPointer) as CFMachPort?
        else {
            Unmanaged<EventTapCallbackBox>.fromOpaque(boxPointer).release()   // balance the +1 above
            return nil
        }

        return CGEventTapHandleImp(tap: tap, box: box, boxPointer: boxPointer)
    }
}

final class CGEventTapHandleImp: EventTapHandle {
    private let tap: CFMachPort
    private let runLoopSource: CFRunLoopSource?
    private let box: EventTapCallbackBox
    private let boxPointer: UnsafeMutableRawPointer
    private(set) var isEnabled: Bool

    init(tap: CFMachPort, box: EventTapCallbackBox, boxPointer: UnsafeMutableRawPointer) {
        self.tap = tap
        self.box = box
        self.boxPointer = boxPointer
        self.isEnabled = CGEvent.tapIsEnabled(tap: tap)
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }

    // SDK adaptation: this SDK renames CGEventTapEnable/CGEventTapIsEnabled to
    // CGEvent.tapEnable(tap:enable:)/CGEvent.tapIsEnabled(tap:).
    func enable() { CGEvent.tapEnable(tap: tap, enable: true); isEnabled = CGEvent.tapIsEnabled(tap: tap) }
    func disable() { CGEvent.tapEnable(tap: tap, enable: false); isEnabled = CGEvent.tapIsEnabled(tap: tap) }

    deinit {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        Unmanaged<EventTapCallbackBox>.fromOpaque(boxPointer).release()
    }
}
