import XCTest
import CoreGraphics
import Foundation
@testable import ArtMouseCore

final class ActionExecutorTests: XCTestCase {
    // SDK adaptation: this SDK omits the deprecated CGEvent.integerValueField(_:) accessor;
    // the read-only getIntegerValueField(_:) form is used everywhere below.

    func testLeftClickPostsDownUpPairWithFlags() {
        let poster = RecordingPoster()
        let executor = ActionExecutor(poster: poster)
        executor.perform(.click(.left, [.command]))
        XCTAssertEqual(poster.events.count, 2)
        XCTAssertEqual(poster.events[0].type, .leftMouseDown)
        XCTAssertEqual(poster.events[0].getIntegerValueField(.mouseEventClickState), 1)
        XCTAssertTrue(poster.events[0].flags.contains(.maskCommand))
        XCTAssertEqual(poster.events[1].type, .leftMouseUp)
    }

    func testDoubleLeftClickPostsFourEvents() {
        let poster = RecordingPoster()
        let executor = ActionExecutor(poster: poster)
        executor.perform(.click(.doubleLeft, []))
        XCTAssertEqual(poster.events.count, 4)
        XCTAssertEqual(poster.events[0].type, .leftMouseDown)
        XCTAssertEqual(poster.events[1].type, .leftMouseUp)
        XCTAssertEqual(poster.events[2].type, .leftMouseDown)
        XCTAssertEqual(poster.events[2].getIntegerValueField(.mouseEventClickState), 2)
        XCTAssertEqual(poster.events[3].type, .leftMouseUp)
    }

    func testMiddleClickUsesOtherMouseEvents() {
        let poster = RecordingPoster()
        let executor = ActionExecutor(poster: poster)
        executor.perform(.click(.middle, []))
        XCTAssertEqual(poster.events.count, 2)
        XCTAssertEqual(poster.events[0].type, .otherMouseDown)
        XCTAssertEqual(poster.events[0].getIntegerValueField(.mouseEventButtonNumber), 2)
    }

    func testFourthAndFifthClicks() {
        let poster = RecordingPoster()
        let executor = ActionExecutor(poster: poster)
        executor.perform(.click(.fourth, []))
        executor.perform(.click(.fifth, []))
        XCTAssertEqual(poster.events[0].getIntegerValueField(.mouseEventButtonNumber), 3)
        XCTAssertEqual(poster.events[2].getIntegerValueField(.mouseEventButtonNumber), 4)
    }

    func testClickLockPostsNothingImmediately() {
        let poster = RecordingPoster()
        let executor = ActionExecutor(poster: poster)
        executor.perform(.click(.clickLock, []))
        XCTAssertTrue(poster.events.isEmpty)
    }

    func testClickCarriesCurrentCursorPosition() {
        let poster = RecordingPoster()
        let executor = ActionExecutor(poster: poster, cursorLocation: { CGPoint(x: 123, y: 456) })
        executor.perform(.click(.left, []))
        XCTAssertEqual(poster.events.count, 2)
        XCTAssertEqual(poster.events[0].location, CGPoint(x: 123, y: 456))
        XCTAssertEqual(poster.events[1].location, CGPoint(x: 123, y: 456))
    }

    func testRightClickPostsRightMouseDownThenUp() {
        let poster = RecordingPoster()
        let executor = ActionExecutor(poster: poster)
        executor.perform(.click(.right, []))
        XCTAssertEqual(poster.events.count, 2)
        XCTAssertEqual(poster.events[0].type, .rightMouseDown)
        XCTAssertEqual(poster.events[1].type, .rightMouseUp)
    }

    // SDK adaptation: CGEventGetSource is not exposed to Swift; sources are
    // read back from an event with CGEventSource(event:) (CGEventCreateSourceFromEvent).
    // No event is actually posted here — tag() is the exact tagging post()
    // performs, invoked directly so the test injects no real HID events.
    func testPosterTagsOwnEventsAndOwnsDetectsThem() {
        let poster = CGEventPoster()
        let click = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                            mouseCursorPosition: .zero, mouseButton: .left)!
        poster.tag(click)
        XCTAssertTrue(poster.owns(click))
        let key = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!
        poster.tag(key)
        XCTAssertTrue(poster.owns(key))
        XCTAssertFalse(poster.owns(CGEvent(source: nil)!))
    }

    func testKeyCodesANSIValues() {
        XCTAssertEqual(KeyCodes.digit(1), 18)
        XCTAssertEqual(KeyCodes.digit(5), 23)
        XCTAssertEqual(KeyCodes.upArrow, 126)
        XCTAssertEqual(KeyCodes.f4, 130)
    }

    func testArrowCodesDistinct() {
        XCTAssertNotEqual(KeyCodes.leftArrow, KeyCodes.rightArrow)
        XCTAssertEqual(KeyCodes.leftArrow, 124)
        XCTAssertEqual(KeyCodes.rightArrow, 123)
        XCTAssertEqual(KeyCodes.downArrow, 125)
    }

    func testFlagConversion() {
        XCTAssertEqual(CGFlagConversion.cgFlags([.command, .shift]), CGEventFlags.maskCommand.union(.maskShift))
    }

    // DPI arms (Task 7): a nil coordinator or a failed report send degrades to
    // cursor-speed profile switching (spec §3); a successful apply must not
    // touch the cursor; dpiShift is a hold (beganHold/endedHold) action.
    func testDPICycleDegradesToCursorCycleWhenUnavailable() {
        let cursor = RecordingCursor()
        let executor = ActionExecutor(poster: RecordingPoster(), cursor: cursor)
        executor.perform(.device(.dpiCycle))
        XCTAssertEqual(cursor.activatedNextCalls, 1)
    }

    func testDPIDegradationWhenReportSendFails() {
        let cursor = RecordingCursor()
        let failingDPI = StubDPI(applies: false)
        let executor = ActionExecutor(poster: RecordingPoster(), cursor: cursor, dpi: failingDPI)
        executor.perform(.device(.dpiUp))
        XCTAssertEqual(cursor.activatedNextCalls, 1)
    }

    func testRestoreDefaultDegradesToDefaultProfile() {
        let cursor = RecordingCursor()
        let executor = ActionExecutor(poster: RecordingPoster(), cursor: cursor)
        executor.perform(.device(.defaultDPI))
        XCTAssertEqual(cursor.activatedDefaultCalls, 1)
    }

    func testDPISuccessfulApplyDoesNotTouchCursor() {
        let cursor = RecordingCursor()
        let dpi = StubDPI(applies: true)
        let executor = ActionExecutor(poster: RecordingPoster(), cursor: cursor, dpi: dpi)
        executor.perform(.device(.dpiCycle))
        XCTAssertEqual(cursor.activatedNextCalls, 0)
    }

    func testDPIShiftHoldLifecycleCallsBeginAndEnd() {
        let dpi = StubDPI()
        let executor = ActionExecutor(poster: RecordingPoster(), dpi: dpi)
        executor.beganHold(.device(.dpiShift))
        executor.endedHold(.device(.dpiShift))
        XCTAssertEqual(dpi.beginCalls, 1)
        XCTAssertEqual(dpi.endCalls, 1)
    }
}

/// Recording CursorCoordinating fake for the DPI-degradation tests. The suite
/// previously had no fake for this protocol (EventRouterTests' StubCursor
/// conforms to the separate CursorControlling transform API), so this is the
/// first; counters cover the cycle/default arms the degradation engages.
final class RecordingCursor: CursorCoordinating {
    private(set) var activatedNextCalls = 0
    private(set) var activatedDefaultCalls = 0
    private(set) var beganPrecisionCalls = 0
    private(set) var endedPrecisionCalls = 0

    func activateNext(source: ProfileSwitchSource) { activatedNextCalls += 1 }
    func activateDefault() { activatedDefaultCalls += 1 }
    func beginPrecision() { beganPrecisionCalls += 1 }
    func endPrecision() { endedPrecisionCalls += 1 }
}

/// Tiny DPICoordinating fake: `applies` is the Bool that apply() returns
/// (false drives the spec §3 degradation); beginShift/endShift are counted for
/// the Shift hold-lifecycle test.
final class StubDPI: DPICoordinating {
    private let applies: Bool
    private(set) var beginCalls = 0
    private(set) var endCalls = 0

    init(applies: Bool = true) { self.applies = applies }

    func apply(_ operation: DPIOperation) -> Bool { applies }
    func beginShift() -> Bool {
        beginCalls += 1
        return applies
    }
    func endShift() { endCalls += 1 }
}

/// Thread-safe: MacroEngine tests spawn real Tasks that append concurrently
/// (unsynchronized Array.append is a SIGSEGV-grade race). `events` returns a
/// snapshot under the lock; reading a stale copy is fine for every caller.
final class RecordingPoster: EventPosting {
    internal let lock = NSLock()
    private var storedEvents: [CGEvent] = []
    var events: [CGEvent] {
        lock.lock()
        defer { lock.unlock() }
        return storedEvents
    }
    func post(_ event: CGEvent) {
        lock.lock()
        storedEvents.append(event)
        lock.unlock()
    }
    func clear() {
        lock.lock()
        storedEvents.removeAll()
        lock.unlock()
    }
}
