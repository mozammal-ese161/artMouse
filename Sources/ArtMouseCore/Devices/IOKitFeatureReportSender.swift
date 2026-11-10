import Foundation
import IOKit
import IOKit.hid

/// Real feature-report glue (public IOHIDManager/IOHIDDevice API). Runs on
/// the tap-callback path: IOHIDDeviceSetReport on a healthy device completes
/// in microseconds–milliseconds (same risk class as the AX sync reads, which
/// carry a 0.25 s messaging timeout). A wedged device can block longer;
/// accepted for owned personal devices (spec §3). Thin glue — smoke-tested.
public final class IOKitFeatureReportSender {
    public init() {}

    /// False when no matching device exists, it cannot be opened, or the
    /// write failed — never throws, never crashes.
    public func send(vendorID: Int, productID: Int, reportID: Int, report: Data) -> Bool {
        // kIOHIDManagerOptionNone: Swift imports the options enum as
        // IOHIDManagerOptions; an empty instance is the zero option set
        // (same idiom as IOKitDeviceEnumerator).
        let options = IOHIDManagerOptions().rawValue
        // IOHIDManagerCreate is imported as non-optional on this toolchain;
        // a failed creation surfaces as an empty set from IOHIDManagerCopyDevices.
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, options)
        defer { IOHIDManagerClose(manager, options) }
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Mouse,
        ] as CFDictionary)
        guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              let device = deviceSet.first(where: {
                  (IOHIDDeviceGetProperty($0, kIOHIDVendorIDKey as CFString) as? Int) == vendorID
                      && (IOHIDDeviceGetProperty($0, kIOHIDProductIDKey as CFString) as? Int) == productID
              })
        else { return false }
        guard IOHIDDeviceOpen(device, options) == kIOReturnSuccess else { return false }
        defer { IOHIDDeviceClose(device, options) }
        var bytes = [UInt8](report)
        guard !bytes.isEmpty else { return false }
        return IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, CFIndex(reportID),
                                    &bytes, CFIndex(bytes.count)) == kIOReturnSuccess
    }
}
