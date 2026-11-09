import XCTest
import CoreGraphics
import AppKit
@testable import ArtMouseCore

final class EventTapEngineTests: XCTestCase {
    func testStartReturnsFalseWhenTapCreationFails() {
        let engine = EventTapEngine(router: PassThroughRouter(), tapFactory: FailingTapFactory())
        XCTAssertFalse(engine.start())
    }

    func testConsumedEventReturnsNilFromCallback() {
        let tap = MockTap()
        let factory = MockTapFactory(tap: tap)
        let router = ConsumingRouter()
        let engine = EventTapEngine(router: router, tapFactory: factory)
        XCTAssertTrue(engine.start())
        let event = CGEvent(source: nil)!
        XCTAssertNil(tap.emit(event, type: .leftMouseDown))
    }

    func testPassThroughReturnsOriginalEvent() {
        let tap = MockTap()
        let engine = EventTapEngine(router: PassThroughRouter(), tapFactory: MockTapFactory(tap: tap))
        XCTAssertTrue(engine.start())
        let event = CGEvent(source: nil)!
        XCTAssertTrue(tap.emit(event, type: .leftMouseDown) === event)
    }

    func testCursorTransformScalesDeltaFields() {
        let tap = MockTap()
        let engine = EventTapEngine(router: ScalingRouter(factor: 2.0), tapFactory: MockTapFactory(tap: tap))
        XCTAssertTrue(engine.start())
        // SDK adaptation: CGEvent(source: nil) is a null-type event that does
        // not retain delta fields; a synthetic .mouseMoved event round-trips them.
        let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: .zero, mouseButton: .left)!
        event.setIntegerValueField(.mouseEventDeltaX, value: 5)
        event.setIntegerValueField(.mouseEventDeltaY, value: 7)
        let result = tap.emit(event, type: .mouseMoved)
        XCTAssertTrue(result === event)
        XCTAssertEqual(event.getIntegerValueField(.mouseEventDeltaX), 10)
        XCTAssertEqual(event.getIntegerValueField(.mouseEventDeltaY), 14)
    }

    func testReenablesTapOnWake() {
        let tap = MockTap()
        let testCenter = NotificationCenter()   // isolated center: the engine must observe THIS one
        let engine = EventTapEngine(router: PassThroughRouter(), tapFactory: MockTapFactory(tap: tap),
                                    workspaceNotificationCenter: testCenter)
        XCTAssertTrue(engine.start())
        tap.disable()
        XCTAssertFalse(tap.isEnabled)
        testCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        XCTAssertTrue(tap.isEnabled)
    }
}

// Test doubles + fixture routers
struct PassThroughRouter: EventRouting {
    func handle(_ event: InputEvent) -> RouterOutcome { .passThrough }
}
struct ConsumingRouter: EventRouting {
    func handle(_ event: InputEvent) -> RouterOutcome { .consume }
}
struct ScalingRouter: EventRouting {
    let factor: Double
    func handle(_ event: InputEvent) -> RouterOutcome {
        if case .moved = event { return .cursorTransform(dxFactor: factor, dyFactor: factor) }
        return .passThrough
    }
}
final class MockTap: EventTapHandle {
    private(set) var isEnabled = true
    var callback: ((CGEvent, CGEventType) -> CGEvent?)?
    func enable() { isEnabled = true }
    func disable() { isEnabled = false }
    @discardableResult
    func emit(_ event: CGEvent, type: CGEventType) -> CGEvent? { callback?(event, type) }
}
final class MockTapFactory: EventTapCreating {
    let tap: MockTap
    init(tap: MockTap) { self.tap = tap }
    func createTap(mask: CGEventMask, callback: @escaping (CGEvent, CGEventType) -> CGEvent?) -> EventTapHandle? {
        tap.callback = callback
        return tap
    }
}
struct FailingTapFactory: EventTapCreating {
    func createTap(mask: CGEventMask, callback: @escaping (CGEvent, CGEventType) -> CGEvent?) -> EventTapHandle? { nil }
}
