import CoreGraphics

public enum CGEventTranslation {
    public static func inputEvent(from type: CGEventType, _ event: CGEvent) -> InputEvent {
        switch type {
        case .leftMouseDown: return .buttonDown(.left)
        case .leftMouseUp: return .buttonUp(.left)
        case .rightMouseDown: return .buttonDown(.right)
        case .rightMouseUp: return .buttonUp(.right)
        case .otherMouseDown: return .buttonDown(buttonID(forCGNumber: cgButton(event)))
        case .otherMouseUp: return .buttonUp(buttonID(forCGNumber: cgButton(event)))
        case .mouseMoved:
            return .moved(dx: event.getDoubleValueField(.mouseEventDeltaX),
                          dy: event.getDoubleValueField(.mouseEventDeltaY))
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            return .dragged(dx: event.getDoubleValueField(.mouseEventDeltaX),
                            dy: event.getDoubleValueField(.mouseEventDeltaY))
        case .scrollWheel:
            // Vertical scroll events carry a nonzero Axis1 delta; horizontal
            // events a nonzero Axis2 delta.
            let axis: ScrollAxis = event.getDoubleValueField(.scrollWheelEventDeltaAxis1) != 0 ? .vertical : .horizontal
            let ticks = axis == .vertical
                ? event.getDoubleValueField(.scrollWheelEventDeltaAxis1)
                : event.getDoubleValueField(.scrollWheelEventDeltaAxis2)
            return .scrolled(axis: axis, ticks: ticks)
        default:
            return .other
        }
    }

    private static func cgButton(_ event: CGEvent) -> Int {
        Int(event.getIntegerValueField(.mouseEventButtonNumber))
    }

    public static func buttonID(forCGNumber number: Int) -> ButtonID {
        switch number {
        case 0: return .left
        case 1: return .right
        case 2: return .middle
        case 3: return .fourth
        case 4: return .fifth
        default: return .extended(number)
        }
    }
}
