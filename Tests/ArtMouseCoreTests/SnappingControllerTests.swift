import XCTest
import CoreGraphics
@testable import ArtMouseCore

final class SnappingControllerTests: XCTestCase {
    private let poster = RecordingPoster()

    final class MockFinder: AXButtonFinding {
        let frame: AXFrame?
        init(frame: AXFrame?) { self.frame = frame }
        func defaultButtonFrame() -> AXFrame? { frame }
    }

    private func makeController(frame: AXFrame?) -> SnappingController {
        SnappingController(finder: MockFinder(frame: frame), poster: poster,
                           cursorLocation: { CGPoint(x: 500, y: 300) })
    }

    func testNilFrameIsNoOp() {
        let controller = makeController(frame: nil)
        controller.perform(.snap(click: true, bounce: true))
        XCTAssertTrue(poster.events.isEmpty)
    }

    func testJumpMovesToCenter() {
        let controller = makeController(frame: AXFrame(x: 100, y: 200, width: 60, height: 40))
        controller.perform(.snap(click: false, bounce: false))
        XCTAssertEqual(poster.events.count, 1)
        XCTAssertEqual(poster.events[0].type, .mouseMoved)
        XCTAssertEqual(poster.events[0].location.x, 130, accuracy: 1e-9)   // 100 + 60/2
        XCTAssertEqual(poster.events[0].location.y, 220, accuracy: 1e-9)   // 200 + 40/2
    }

    func testClickSnapPostsMoveAndClickPair() {
        let controller = makeController(frame: AXFrame(x: 100, y: 200, width: 60, height: 40))
        controller.perform(.snap(click: true, bounce: false))
        XCTAssertEqual(poster.events.count, 3)                              // move, down, up
        XCTAssertEqual(poster.events[1].type, .leftMouseDown)
        XCTAssertEqual(poster.events[2].type, .leftMouseUp)
        XCTAssertEqual(poster.events[1].location.y, 220, accuracy: 1e-9)
    }

    func testBounceReturnsToOrigin() {
        let controller = makeController(frame: AXFrame(x: 100, y: 200, width: 60, height: 40))
        controller.perform(.snap(click: true, bounce: true))
        XCTAssertEqual(poster.events.count, 4)                              // move, down, up, move-back
        let last = poster.events[3]
        XCTAssertEqual(last.type, .mouseMoved)
        XCTAssertEqual(last.location.x, 500, accuracy: 1e-9)
        XCTAssertEqual(last.location.y, 300, accuracy: 1e-9)
    }

    func testClickEventsCarryTargetLocation() {
        let controller = makeController(frame: AXFrame(x: 0, y: 0, width: 200, height: 100))
        controller.perform(.snap(click: true, bounce: false))
        XCTAssertEqual(poster.events[1].location.x, 100, accuracy: 1e-9)
        XCTAssertEqual(poster.events[1].location.y, 50, accuracy: 1e-9)
    }
}
