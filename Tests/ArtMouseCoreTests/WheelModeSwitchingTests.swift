import XCTest
import CoreGraphics
@testable import ArtMouseCore

final class WheelModeSwitchingTests: XCTestCase {
    func testDeviceOpSwitchWheelModeActivatesNext() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = SettingsStore(directory: dir)
        let a = WheelModeProfile(name: "A")
        let b = WheelModeProfile(name: "B")
        store.settings.wheelModeProfiles = [a, b]
        let controller = ScrollController(store: store, emitter: ScrollEmitter(poster: RecordingPoster()))
        let executor = ActionExecutor(poster: RecordingPoster(), cursor: nil, wheel: controller)

        XCTAssertEqual(store.settings.activeWheelProfile, a)   // first fallback
        executor.perform(.device(.switchWheelMode))
        XCTAssertEqual(store.settings.activeWheelProfile, b)
    }

    // Posting with a live CGEventPoster injects real HID input, so ownership
    // is asserted through the executor's own recording poster instead: the
    // SAME event instance must be recorded in postedScrollEvents and arrive
    // through the poster the executor was built with — the `.scroll` arm must
    // not construct events on a fresh CGEvent(source: nil) side path.
    func testScrollActionPostsThroughExecutorPoster() {
        let poster = RecordingPoster()
        let executor = ActionExecutor(poster: poster)
        executor.perform(.scroll(ScrollSpec(direction: .up, lines: 4)))
        XCTAssertEqual(executor.postedScrollEvents.count, 1)   // recorded for tests
        XCTAssertEqual(poster.events.count, 1)
        XCTAssertTrue(executor.postedScrollEvents[0] === poster.events[0])
        XCTAssertEqual(poster.events[0].type, .scrollWheel)
        XCTAssertEqual(poster.events[0].getDoubleValueField(.scrollWheelEventDeltaAxis1), 4, accuracy: 1e-9)
        XCTAssertEqual(poster.events[0].getDoubleValueField(.scrollWheelEventDeltaAxis2), 0, accuracy: 1e-9)
    }

    // Task 8 consolidation ruling (Task 6 review): the router's binding lookup
    // and ScrollController share ONE direction derivation, pinned here from
    // tick signs. Zero ticks map to .down/.left; both callers guard zero
    // before deriving, so the mapping itself is unreachable for 0.
    func testDirectionDerivationFromTickSigns() {
        XCTAssertEqual(ScrollDirection.derived(axis: .vertical, ticks: 1), .up)
        XCTAssertEqual(ScrollDirection.derived(axis: .vertical, ticks: -1), .down)
        XCTAssertEqual(ScrollDirection.derived(axis: .horizontal, ticks: 1), .right)
        XCTAssertEqual(ScrollDirection.derived(axis: .horizontal, ticks: -1), .left)
        XCTAssertEqual(ScrollDirection.derived(axis: .vertical, ticks: 0), .down)
    }
}
