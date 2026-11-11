import XCTest
import CoreGraphics
import AppKit
@testable import ArtMouseCore

final class EventTapEngineTests: XCTestCase {
    func testStartReturnsFalseWhenTapCreationFails() {
        let engine = EventTapEngine(router: PassThroughRouter(), tapFactory: FailingTapFactory())
        XCTAssertFalse(engine.start())
    }

    func testFailedCreationLeavesTapAbsentForRetry() {
        // Tap self-heal contract (permission granted mid-run): a failed
        // creation leaves hasTap false — the bootstrap tick retries start()
        // while that holds — and a later successful start() attaches the tap.
        let tap = MockTap()
        let engine = EventTapEngine(router: PassThroughRouter(),
                                    tapFactory: RecoveryTapFactory(tap: tap))
        XCTAssertFalse(engine.start())   // permission not yet granted
        XCTAssertFalse(engine.hasTap)
        XCTAssertFalse(engine.tapActive)
        XCTAssertTrue(engine.start())    // permission appeared: the retry attaches
        XCTAssertTrue(engine.hasTap)
        XCTAssertTrue(engine.tapActive)
    }

    func testStartAfterAttachIsNoOp() {
        // start() must never re-create an attached tap (the retry calls it
        // every tick; re-creation would stack duplicate taps).
        let tap = MockTap()
        let factory = MockTapFactory(tap: tap)
        let engine = EventTapEngine(router: PassThroughRouter(), tapFactory: factory)
        XCTAssertTrue(engine.start())
        XCTAssertTrue(engine.start())
        XCTAssertTrue(engine.hasTap)
        XCTAssertTrue(engine.tapActive)
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

    func testTapActiveTracksLifecycle() {
        let tap = MockTap()
        let engine = EventTapEngine(router: PassThroughRouter(), tapFactory: MockTapFactory(tap: tap))
        XCTAssertFalse(engine.tapActive)
        XCTAssertTrue(engine.start())
        XCTAssertTrue(engine.tapActive)
        tap.disable()
        tap.refusesEnable = true
        // The engine re-enables on the disabled event; the mock refuses, so the
        // tap stays disabled and the loss must surface through tapActive.
        tap.emit(CGEvent(source: nil)!, type: .tapDisabledByTimeout)
        XCTAssertFalse(engine.tapActive)
        tap.refusesEnable = false
        tap.enable()                                                   // simulated recovery
        tap.emit(CGEvent(source: nil)!, type: .leftMouseDown)
        XCTAssertTrue(engine.tapActive)
    }

    func testStopResetsTapActive() {
        let tap = MockTap()
        let engine = EventTapEngine(router: PassThroughRouter(), tapFactory: MockTapFactory(tap: tap))
        engine.start()
        engine.stop()
        XCTAssertFalse(engine.tapActive)
    }

    func testSelfPostedEventsBypassRouting() {
        let tap = MockTap()
        let router = RecordingRouter()
        let engine = EventTapEngine(router: router, tapFactory: MockTapFactory(tap: tap),
                                    isSelfPosted: { _ in true })
        XCTAssertTrue(engine.start())
        let event = CGEvent(source: nil)!
        XCTAssertTrue(tap.emit(event, type: .leftMouseDown) === event)
        XCTAssertTrue(router.received.isEmpty)
    }

    func testNonSelfPostedEventsStillRoute() {
        let tap = MockTap()
        let router = RecordingRouter()
        let engine = EventTapEngine(router: router, tapFactory: MockTapFactory(tap: tap),
                                    isSelfPosted: { _ in false })
        XCTAssertTrue(engine.start())
        tap.emit(CGEvent(source: nil)!, type: .leftMouseDown)
        XCTAssertEqual(router.received.count, 1)
    }

    // $tapActive re-publishes on every assignment, so without the
    // unchanged-value guard in syncTapActive ordinary traffic would emit.
    func testSyncTapActiveDoesNotEmitWhenUnchanged() {
        let tap = MockTap()
        let engine = EventTapEngine(router: PassThroughRouter(), tapFactory: MockTapFactory(tap: tap))
        XCTAssertTrue(engine.start())
        var received: [Bool] = []
        let cancellable = engine.tapActivePublisher.sink { received.append($0) }
        let baseline = received.count
        tap.emit(CGEvent(source: nil)!, type: .leftMouseDown)
        tap.emit(CGEvent(source: nil)!, type: .mouseMoved)
        XCTAssertEqual(received.count, baseline)
        XCTAssertEqual(received.last, true)
        // A real flip must still publish.
        tap.disable()
        tap.refusesEnable = true
        tap.emit(CGEvent(source: nil)!, type: .tapDisabledByTimeout)
        XCTAssertEqual(received.last, false)
        _ = cancellable
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
final class RecordingRouter: EventRouting {
    private(set) var received: [InputEvent] = []
    func handle(_ event: InputEvent) -> RouterOutcome { received.append(event); return .passThrough }
}
final class MockTap: EventTapHandle {
    private(set) var isEnabled = true
    // When true, enable() is refused — models a tap the system keeps disabled
    // (permission revoked mid-run), mirroring CGEventTapHandleImp, which
    // re-reads tapIsEnabled after CGEvent.tapEnable and may stay disabled.
    var refusesEnable = false
    var callback: ((CGEvent, CGEventType) -> CGEvent?)?
    func enable() { if !refusesEnable { isEnabled = true } }
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

/// Fails the first creation (permission not yet granted), then attaches —
/// models the retry-after-grant flow the bootstrap tick drives.
final class RecoveryTapFactory: EventTapCreating {
    let tap: MockTap
    private var firstCall = true
    init(tap: MockTap) { self.tap = tap }
    func createTap(mask: CGEventMask, callback: @escaping (CGEvent, CGEventType) -> CGEvent?) -> EventTapHandle? {
        if firstCall {
            firstCall = false
            return nil
        }
        tap.callback = callback
        return tap
    }
}

struct ScrollScalingRouter: EventRouting {
    func handle(_ event: InputEvent) -> RouterOutcome {
        if case .scrolled = event { return .scrollTransform(verticalFactor: 2, horizontalFactor: -1) }
        return .passThrough
    }
}

final class EventTapEngineScrollTests: XCTestCase {
    func testScrollTransformScalesAxisDeltas() {
        let tap = MockTap()
        let engine = EventTapEngine(router: ScrollScalingRouter(), tapFactory: MockTapFactory(tap: tap))
        XCTAssertTrue(engine.start())
        // SDK adaptation: this SDK's init is (scrollWheelEvent2Source:units:wheelCount:wheel1:wheel2:wheel3:);
        // Axis1 carries the wheel ticks (3), Axis2 is set explicitly to 1.
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 3, wheel2: 0, wheel3: 0)!
        event.setDoubleValueField(.scrollWheelEventDeltaAxis2, value: 1)
        let result = tap.emit(event, type: .scrollWheel)
        XCTAssertTrue(result === event)
        XCTAssertEqual(event.getDoubleValueField(.scrollWheelEventDeltaAxis1), 6, accuracy: 1e-9)
        XCTAssertEqual(event.getDoubleValueField(.scrollWheelEventDeltaAxis2), -1, accuracy: 1e-9)
    }
}
