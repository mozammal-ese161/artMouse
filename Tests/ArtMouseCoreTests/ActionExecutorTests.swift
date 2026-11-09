import XCTest
import CoreGraphics
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

final class RecordingPoster: EventPosting {
    private(set) var events: [CGEvent] = []
    func post(_ event: CGEvent) { events.append(event) }
    func clear() { events.removeAll() }
}
