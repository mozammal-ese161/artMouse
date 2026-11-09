import XCTest
import CoreGraphics
@testable import ArtMouseCore

final class CGEventTranslationTests: XCTestCase {
    private func mouseEvent(_ type: CGEventType, button: CGMouseButton) -> CGEvent {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: .zero, mouseButton: button)!
    }

    func testStandardButtons() {
        XCTAssertEqual(
            CGEventTranslation.inputEvent(from: .leftMouseDown, mouseEvent(.leftMouseDown, button: .left)),
            .buttonDown(.left))
        XCTAssertEqual(
            CGEventTranslation.inputEvent(from: .rightMouseUp, mouseEvent(.rightMouseUp, button: .right)),
            .buttonUp(.right))
    }

    func testOtherButtonsByNumber() {
        // CGMouseButton only carries 0..2; the true button number travels in
        // the mouseEventButtonNumber field, which is what translation reads.
        let down = CGEvent(mouseEventSource: nil, mouseType: .otherMouseDown, mouseCursorPosition: .zero, mouseButton: .center)!
        down.setIntegerValueField(.mouseEventButtonNumber, value: 2)
        XCTAssertEqual(CGEventTranslation.inputEvent(from: .otherMouseDown, down), .buttonDown(.middle))
        let fifth = CGEvent(mouseEventSource: nil, mouseType: .otherMouseDown, mouseCursorPosition: .zero, mouseButton: .center)!
        fifth.setIntegerValueField(.mouseEventButtonNumber, value: 4)
        XCTAssertEqual(CGEventTranslation.inputEvent(from: .otherMouseDown, fifth), .buttonDown(.fifth))
    }

    func testMoveAndDragCarryDeltas() {
        let moved = mouseEvent(.mouseMoved, button: .left)
        moved.setIntegerValueField(.mouseEventDeltaX, value: 12)
        moved.setIntegerValueField(.mouseEventDeltaY, value: -3)
        XCTAssertEqual(
            CGEventTranslation.inputEvent(from: .mouseMoved, moved),
            .moved(dx: 12, dy: -3))
    }

    func testScrollAxis() {
        // SDK adaptation: this SDK's init is (scrollWheelEvent2Source:units:wheelCount:wheel1:wheel2:wheel3:).
        let scroll = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 1, wheel2: 0, wheel3: 0)!
        XCTAssertEqual(
            CGEventTranslation.inputEvent(from: .scrollWheel, scroll),
            .scrolled(axis: .vertical, ticks: 1))
    }
}
