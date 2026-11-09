import XCTest
@testable import ArtMouseCore

final class AppWatcherTests: XCTestCase {
    func testHandleActivationUpdatesFrontmost() {
        let watcher = AppWatcher(notificationCenter: NotificationCenter())
        XCTAssertNil(watcher.frontmostBundleID)
        watcher.handleActivation("com.apple.Safari")
        XCTAssertEqual(watcher.frontmostBundleID, "com.apple.Safari")
        watcher.handleActivation("com.apple.TextEdit")
        XCTAssertEqual(watcher.frontmostBundleID, "com.apple.TextEdit")
    }

    func testHandleActivationNilKeepsPrevious() {
        let watcher = AppWatcher(notificationCenter: NotificationCenter())
        watcher.handleActivation("com.apple.Safari")
        watcher.handleActivation(nil)   // activation notifications always carry an app; nil input tolerated
        XCTAssertEqual(watcher.frontmostBundleID, "com.apple.Safari")
    }

    func testBundleIDExtractionWithoutAppReturnsNil() {
        XCTAssertNil(AppWatcher.bundleID(fromActivation: [:]))
        XCTAssertNil(AppWatcher.bundleID(fromActivation: ["unrelated": 1]))
    }
}
