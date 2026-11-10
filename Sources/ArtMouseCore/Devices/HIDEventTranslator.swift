import Foundation

/// Translates one raw HID observation into zero or more InputEvents, under
/// the double-feed policy (Review Focus 1): elements the CGEventTap already
/// covers — button-page usages 1–32, GD wheel, AC Pan — are dropped unless a
/// device profile explicitly claims them, so a press is never routed twice.
/// A nil profile (device without one) translates nothing: observation then
/// feeds only the analyzer/log.
public enum HIDEventTranslator {
    public static func translate(_ observation: RawHIDObservation,
                                 profile: DeviceProfile?) -> [InputEvent] {
        guard let profile else { return [] }

        // 1. An explicit profile part wins over every generic rule.
        if let part = profile.parts.first(where: {
            $0.usagePage == observation.usagePage && $0.usage == observation.usage
        }) {
            return translatePart(part, value: observation.value)
        }

        // 2. Standard wheel usages are tap-covered on every healthy device —
        // never translated here, regardless of capture.
        if observation.usagePage == HIDUsage.genericDesktopPage
            && (observation.usage == HIDUsage.gdWheel || observation.usage == HIDUsage.gdACPan) {
            return []
        }

        // 3. Button-page usages 1–32: dropped unless the device opts in
        //    (devices whose extra buttons never reach macOS as CGEvents).
        if observation.usagePage == HIDUsage.buttonPage && (1...32).contains(observation.usage) {
            guard profile.rawButtonCapture else { return [] }
            let buttonNumber = observation.usage - 1   // HID 1-based → CG 0-based
            return observation.value != 0
                ? [.buttonDown(.extended(buttonNumber))]
                : [.buttonUp(.extended(buttonNumber))]
        }

        return []
    }

    private static func translatePart(_ part: DevicePart, value: Int) -> [InputEvent] {
        switch part.kind {
        case .wheel:
            guard value != 0 else { return [] }
            let axis: ScrollAxis = part.usage == HIDUsage.gdACPan ? .horizontal : .vertical
            return [.scrolled(axis: axis, ticks: Double(value))]
        case .button, .pedal:
            guard let number = part.routesAsButton else { return [] }
            return value != 0
                ? [.buttonDown(.extended(number))]
                : [.buttonUp(.extended(number))]
        }
    }
}
