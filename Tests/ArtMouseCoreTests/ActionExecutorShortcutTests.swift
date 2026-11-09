import XCTest
import CoreGraphics
import AppKit
@testable import ArtMouseCore

// SDK adaptation: this SDK omits the deprecated CGEvent.integerValueField(_:) accessor;
// the read-only getIntegerValueField(_:) form is used for every field read below.

final class ActionExecutorShortcutTests: XCTestCase {
    func testMissionControlPostsCtrlUp() {
        let poster = RecordingPoster()
        let executor = ActionExecutor(poster: poster)
        executor.perform(.mission(.missionControl, reverse: false))
        XCTAssertEqual(poster.events.count, 2)   // down + up
        XCTAssertEqual(poster.events[0].type, .keyDown)
        XCTAssertEqual(UInt64(poster.events[0].getIntegerValueField(.keyboardEventKeycode)), KeyCodes.upArrow)
        XCTAssertTrue(poster.events[0].flags.contains(.maskControl))
        XCTAssertEqual(poster.events[1].type, .keyUp)
    }

    func testDesktopThreePostsCtrlDigit3() {
        let poster = RecordingPoster()
        let executor = ActionExecutor(poster: poster)
        executor.perform(.mission(.desktop(3), reverse: false))
        XCTAssertEqual(UInt64(poster.events[0].getIntegerValueField(.keyboardEventKeycode)), KeyCodes.digit(3))
        XCTAssertTrue(poster.events[0].flags.contains(.maskControl))
    }

    func testMoveSpaceReverseFlipsDirection() {
        let poster = RecordingPoster()
        let executor = ActionExecutor(poster: poster)
        executor.perform(.mission(.moveSpaceLeft, reverse: true))
        XCTAssertEqual(UInt64(poster.events[0].getIntegerValueField(.keyboardEventKeycode)), KeyCodes.rightArrow)
    }

    func testSpotlightUsesCommandSpace() {
        let poster = RecordingPoster()
        let executor = ActionExecutor(poster: poster)
        executor.perform(.mission(.spotlight, reverse: false))
        XCTAssertEqual(UInt64(poster.events[0].getIntegerValueField(.keyboardEventKeycode)), KeyCodes.space)
        XCTAssertTrue(poster.events[0].flags.contains(.maskCommand))
    }

    func testNextAppPostsCommandTab() {
        let poster = RecordingPoster()
        let executor = ActionExecutor(poster: poster)
        executor.perform(.switcher(.nextApp))
        XCTAssertEqual(UInt64(poster.events[0].getIntegerValueField(.keyboardEventKeycode)), 48)
        XCTAssertTrue(poster.events[0].flags.contains(.maskCommand))
    }

    func testPreviousAppAddsShift() {
        let poster = RecordingPoster()
        let executor = ActionExecutor(poster: poster)
        executor.perform(.switcher(.previousApp))
        XCTAssertTrue(poster.events[0].flags.contains(.maskCommand))
        XCTAssertTrue(poster.events[0].flags.contains(.maskShift))
    }

    func testAppZoomPostsCommandEquals() {
        let poster = RecordingPoster()
        let executor = ActionExecutor(poster: poster)
        executor.perform(.zoom(.appZoomIn, reverse: false))
        XCTAssertEqual(UInt64(poster.events[0].getIntegerValueField(.keyboardEventKeycode)), KeyCodes.equals)
        XCTAssertTrue(poster.events[0].flags.contains(.maskCommand))
    }

    func testScreenZoomPostsOptionCommandEquals() {
        let poster = RecordingPoster()
        let executor = ActionExecutor(poster: poster)
        executor.perform(.zoom(.screenZoomIn, reverse: false))
        XCTAssertTrue(poster.events[0].flags.contains(.maskAlternate))
        XCTAssertTrue(poster.events[0].flags.contains(.maskCommand))
        XCTAssertEqual(UInt64(poster.events[0].getIntegerValueField(.keyboardEventKeycode)), KeyCodes.equals)
    }

    func testDeferredOpsPostNothing() {
        let poster = RecordingPoster()
        let executor = ActionExecutor(poster: poster)
        executor.perform(.mission(.notificationCenter, reverse: false))
        executor.perform(.mission(.siri, reverse: false))
        executor.perform(.zoom(.pinchIn, reverse: false))
        executor.perform(.zoom(.smartZoom, reverse: false))
        executor.perform(.switcher(.showSwitcher))
        executor.perform(.device(.dpiCycle))
        executor.perform(.device(.switchWheelMode))
        XCTAssertTrue(poster.events.isEmpty)
    }
}

final class StubOpener: WorkspaceOpening {
    private(set) var launched: [String] = []
    private(set) var openedURLs: [URL] = []
    private(set) var openedFiles: [String] = []
    func launchApp(bundleID: String) { launched.append(bundleID) }
    func openURL(_ url: URL) { openedURLs.append(url) }
    func openFile(path: String) { openedFiles.append(path) }
}

final class ActionExecutorSwitcherTests: XCTestCase {
    func testSwitchToAppByBundleID() {
        let poster = RecordingPoster()
        let opener = StubOpener()
        let executor = ActionExecutor(poster: poster, workspace: opener)
        executor.perform(.switcher(.app(.bundleID("com.apple.Safari"))))
        XCTAssertEqual(opener.launched, ["com.apple.Safari"])
    }

    func testOpenPathAndURL() {
        let opener = StubOpener()
        let executor = ActionExecutor(poster: RecordingPoster(), workspace: opener)
        executor.perform(.open(.path("/tmp")))
        executor.perform(.open(.url("https://example.com")))
        XCTAssertEqual(opener.openedFiles, ["/tmp"])
        XCTAssertEqual(opener.openedURLs.map(\.absoluteString), ["https://example.com"])
    }

    func testOpenInvalidURLOnlyMarksOneEvent() {
        let opener = StubOpener()
        let executor = ActionExecutor(poster: RecordingPoster(), workspace: opener)
        executor.perform(.open(.url("::::not-a-url")))
        XCTAssertTrue(opener.openedURLs.isEmpty)   // invalid URL is a no-op, not a crash
    }
}
