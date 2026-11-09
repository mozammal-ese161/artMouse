import Foundation
import IOKit
import IOKit.hid

/// Enumerates pointing devices via IOHIDManager (public API). Raw report
/// observation arrives in Phase 4 (HIDObserver); this only lists devices.
public final class IOKitDeviceEnumerator: HIDDeviceEnumerating {
    public init() {}

    public func currentPointingDevices() -> [HIDDeviceIdentity] {
        // kIOHIDManagerOptionNone: Swift imports the options enum as
        // IOHIDManagerOptions; an empty instance is the zero option set.
        let options = IOHIDManagerOptions().rawValue

        // IOHIDManagerCreate is imported as non-optional on this toolchain;
        // a failed creation surfaces as an empty set from IOHIDManagerCopyDevices.
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, options)
        defer { IOHIDManagerClose(manager, options) }

        let page = kHIDPage_GenericDesktop
        let usage = kHIDUsage_GD_Mouse
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDDeviceUsagePageKey as String: page,
            kIOHIDDeviceUsageKey as String: usage,
        ] as CFDictionary)

        guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            return []
        }

        return deviceSet.compactMap { device in
            guard
                let vendor = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int,
                let product = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int
            else { return nil }
            let name = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String) ?? "Mouse"
            let transport = (IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String) ?? ""
            return HIDDeviceIdentity(vendorID: vendor, productID: product, name: name, transport: transport)
        }
        .sorted { ($0.vendorID, $0.productID) < ($1.vendorID, $1.productID) }
    }
}
