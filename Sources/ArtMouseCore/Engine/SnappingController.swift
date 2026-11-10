import ApplicationServices
import CoreGraphics
import Foundation

public struct AXFrame: Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var center: CGPoint {
        CGPoint(x: x + width / 2, y: y + height / 2)
    }
}

public protocol AXButtonFinding: AnyObject {
    func defaultButtonFrame() -> AXFrame?
}

public protocol SnappingPerforming: AnyObject {
    func perform(_ op: SnappingOp)
}

/// Reads the focused window's default button via Accessibility and moves the
/// cursor there (optionally clicking, optionally returning to the origin).
public final class SnappingController: SnappingPerforming {
    private let finder: AXButtonFinding
    private let poster: EventPosting
    private let cursorLocation: () -> CGPoint

    public init(finder: AXButtonFinding, poster: EventPosting,
                cursorLocation: @escaping () -> CGPoint = { CGEvent(source: nil)?.location ?? .zero }) {
        self.finder = finder
        self.poster = poster
        self.cursorLocation = cursorLocation
    }

    public func perform(_ op: SnappingOp) {
        guard case .snap(let click, let bounce) = op else { return }
        guard let frame = finder.defaultButtonFrame() else { return }   // Review Focus 3: no-op
        let origin = cursorLocation()
        let center = frame.center

        moveTo(center)
        if click {
            postClick(at: center)
        }
        if bounce {
            moveTo(origin)
        }
    }

    // MARK: - Primitives

    private func moveTo(_ point: CGPoint) {
        CGWarpMouseCursorPosition(point)
        let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                            mouseCursorPosition: point, mouseButton: .left)!
        poster.post(event)
    }

    private func postClick(at point: CGPoint) {
        let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                           mouseCursorPosition: point, mouseButton: .left)!
        down.setIntegerValueField(.mouseEventClickState, value: 1)
        let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                         mouseCursorPosition: point, mouseButton: .left)!
        up.setIntegerValueField(.mouseEventClickState, value: 1)
        poster.post(down)
        poster.post(up)
    }
}

/// Real AX reader: system-wide element → focused window → default button.
public final class AXDefaultButtonFinder: AXButtonFinding {
    public init() {}

    public func defaultButtonFrame() -> AXFrame? {
        let systemWide = AXUIElementCreateSystemWide()
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let windowElement = window else { return nil }
        var button: CFTypeRef?
        guard AXUIElementCopyAttributeValue(windowElement as! AXUIElement, kAXDefaultButtonAttribute as CFString, &button) == .success,
              let buttonElement = button else { return nil }
        return frame(of: buttonElement as! AXUIElement)
    }

    private func frame(of element: AXUIElement) -> AXFrame? {
        var position: CFTypeRef?
        var size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let positionValue = position, let sizeValue = size else { return nil }
        var point = CGPoint.zero
        var sizeStruct = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &sizeStruct) else { return nil }
        return AXFrame(x: point.x, y: point.y, width: sizeStruct.width, height: sizeStruct.height)
    }
}
