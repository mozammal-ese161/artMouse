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
