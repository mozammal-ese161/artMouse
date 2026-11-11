import Foundation
import IOKit
import IOKit.hid

/// Real observation glue over the PUBLIC IOHIDManager value-callback API.
/// Devices are opened WITHOUT seize (kIOHIDOptionsTypeNone), so the system
/// keeps receiving events normally — artMouse only observes. Callbacks are
/// registered per device (the manager-level callback cannot report which
/// device produced a value, and identity is needed for profile resolution).
///
/// Context lifecycle: one ContextBox retained per observed device, released
/// in stop()/deinit (a removed device's box is intentionally not released
/// early — see releaseContext). The sink hop to the main queue implements the
/// HIDValueObserving contract. This class is thin system glue and is
/// smoke-tested manually (spec §8); all logic under test lives in the
/// translator and pump.
public final class IOKitHIDValueObserver: HIDValueObserving {
    private final class ContextBox {
        let observer: IOKitHIDValueObserver
        let vendorID: Int
        let productID: Int
        init(observer: IOKitHIDValueObserver, vendorID: Int, productID: Int) {
            self.observer = observer
            self.vendorID = vendorID
            self.productID = productID
        }
    }

    private var manager: IOHIDManager?
    private var sink: ((RawHIDObservation) -> Void)?
    /// Per-device contexts: index-aligned parallel arrays.
    private var contexts: [Unmanaged<ContextBox>] = []
    /// Devices whose value callback is registered. The manager also reports
    /// ALREADY-attached devices through the matching callback (in addition to
    /// the start() enumeration below), so attach() must be idempotent — a
    /// second registration would deliver every observation of that device
    /// twice. Identifiers are dropped again in the removal callback so a
    /// replug/reconnect attaches a fresh callback. Mutated only from the main
    /// run loop (start() and both manager callbacks run there).
    private var attachedDevices: Set<ObjectIdentifier> = []

    public init() {}

    public func start(sink: @escaping (RawHIDObservation) -> Void) {
        guard manager == nil else { return }
        self.sink = sink
        let options = IOHIDManagerOptions().rawValue
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, options)
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Mouse,
        ] as CFDictionary)

        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<IOKitHIDValueObserver>.fromOpaque(context)
                .takeUnretainedValue().releaseContext(for: device)
        }, Unmanaged.passUnretained(self).toOpaque())

        // Hot-plug arrival (Final Review Issue 1): without this callback a
        // replugged or Bluetooth-reconnected mouse never registers a value
        // callback and stays dead until relaunch. attach()'s guard absorbs
        // the manager re-reporting devices attached in the enumeration below.
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<IOKitHIDValueObserver>.fromOpaque(context)
                .takeUnretainedValue().attach(device)
        }, Unmanaged.passUnretained(self).toOpaque())

        if let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
            for device in deviceSet {
                attach(device)
            }
        }

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerOpen(manager, options)
        self.manager = manager
    }

    public func stop() {
        guard let manager else { return }
        let options = IOHIDManagerOptions().rawValue
        IOHIDManagerClose(manager, options)
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        self.manager = nil
        contexts.forEach { $0.release() }
        contexts.removeAll()
        attachedDevices.removeAll()
        sink = nil
    }

    deinit {
        stop()
    }

    private func attach(_ device: IOHIDDevice) {
        guard
            let vendor = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int,
            let product = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int
        else { return }
        // Double-attach guard (see attachedDevices): the matching callback can
        // fire for a device this observer already attached from the start()
        // enumeration. Without it the device would carry two value callbacks
        // and every observation would route (and log) twice.
        let deviceID = ObjectIdentifier(device)
        guard !attachedDevices.contains(deviceID) else { return }
        attachedDevices.insert(deviceID)
        let box = ContextBox(observer: self, vendorID: vendor, productID: product)
        let unmanaged = Unmanaged.passRetained(box)
        contexts.append(unmanaged)
        IOHIDDeviceRegisterInputValueCallback(device, { context, _, _, value in
            guard let context else { return }
            // SDK adaptation: IOHIDValueGetElement is imported as non-optional
            // on this toolchain, same as IOHIDManagerCreate (see
            // IOKitDeviceEnumerator). A failed element lookup is not modeled.
            let element = IOHIDValueGetElement(value)
            let box = Unmanaged<ContextBox>.fromOpaque(context).takeUnretainedValue()
            let observation = RawHIDObservation(
                vendorID: box.vendorID,
                productID: box.productID,
                usagePage: Int(IOHIDElementGetUsagePage(element)),
                usage: Int(IOHIDElementGetUsage(element)),
                value: Int(IOHIDValueGetIntegerValue(value)))
            // HIDValueObserving contract: deliver on the main queue. The
            // observer/box outlive this hop: the box is retained until device
            // removal or stop(), both of which run after queued hops drain
            // (stop() runs on main).
            DispatchQueue.main.async {
                box.observer.deliver(observation)
            }
        }, unmanaged.toOpaque())
    }

    fileprivate func releaseContext(for device: IOHIDDevice) {
        // Drop the attach-guard entry so a replug/reconnect of this device
        // registers a fresh value callback (Final Review Issue 1). Value
        // callbacks were registered per device; IOKit drops them when the
        // device disappears. The retained ContextBox is NOT released here —
        // matched positionally is not possible from the raw pointer, so
        // contexts release wholesale in stop()/deinit: hot-unplug therefore
        // leaks one small box per unplug until app quit (documented; bounded
        // by session length).
        attachedDevices.remove(ObjectIdentifier(device))
    }

    fileprivate func deliver(_ observation: RawHIDObservation) {
        sink?(observation)
    }
}
