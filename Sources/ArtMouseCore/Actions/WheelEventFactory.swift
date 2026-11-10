import CoreGraphics

/// Shared wheel-event construction. SDK adaptation (moved here verbatim from
/// the two former construction sites): this SDK's wheel init is
/// (scrollWheelEvent2Source:units:wheelCount:wheel1:wheel2:wheel3:) with
/// Int32 parameters — the variadic CGFloat overload does not exist — and
/// wheelCount must be 2 or the constructor ignores wheel2 (horizontal). The
/// int delta fields truncate, so fractional line amounts additionally ride
/// the 16.16 fixed-point delta fields, the shape the system uses for
/// sub-line scrolling.
enum WheelEventFactory {
    static func lineEvent(vertical: Double, horizontal: Double) -> CGEvent {
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2,
                            wheel1: Int32(vertical), wheel2: Int32(horizontal), wheel3: 0)!
        event.setIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1,
                                   value: Int64(vertical * 65536.0))
        event.setIntegerValueField(.scrollWheelEventFixedPtDeltaAxis2,
                                   value: Int64(horizontal * 65536.0))
        return event
    }
}
