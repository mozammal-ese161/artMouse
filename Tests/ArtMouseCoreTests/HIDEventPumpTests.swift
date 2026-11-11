import XCTest
import CoreGraphics
// @testable: the pump's `receive(_:)` test entry stays internal (brief), and
// this suite drives it directly.
@testable import ArtMouseCore

final class HIDEventPumpTests: XCTestCase {
    final class FakeObserver: HIDValueObserving {
        var started = 0
        var stopped = 0
        var sink: ((RawHIDObservation) -> Void)?
        func start(sink: @escaping (RawHIDObservation) -> Void) {
            started += 1
            self.sink = sink
        }
        func stop() { stopped += 1 }
    }

    final class RecordingRouter: EventRouting {
        var events: [InputEvent] = []
        /// Scripted reply; defaults to the legacy pass-through the earlier
        /// tests were written against.
        var outcome: RouterOutcome = .passThrough
        func handle(_ event: InputEvent) -> RouterOutcome {
            events.append(event)
            return outcome
        }
    }

    final class RecordingPoster: EventPosting {
        var events: [CGEvent] = []
        func post(_ event: CGEvent) { events.append(event) }
    }

    private func observation(page: Int = 0x0C, usage: Int = 0x0B4, value: Int = 1) -> RawHIDObservation {
        RawHIDObservation(vendorID: 111, productID: 222, usagePage: page, usage: usage, value: value)
    }

    private func profile(capture: Bool = false) -> DeviceProfile {
        DeviceProfile(name: "m", vendorID: 111, productID: 222,
                      parts: [DevicePart(name: "Pedal", kind: .pedal, usagePage: 0x0C,
                                         usage: 0x0B4, routesAsButton: 8)],
                      rawButtonCapture: capture)
    }

    /// A vendor-proprietary wheel element (not GD_Wheel/GD_AC_Pan, which the
    /// translator drops as tap-covered): the shape whose routed tick the
    /// scroll-transform materialization exists for.
    private func wheelObservation(value: Int = 1) -> RawHIDObservation {
        RawHIDObservation(vendorID: 111, productID: 222, usagePage: 0xFF00, usage: 0x01, value: value)
    }

    private func wheelProfile() -> DeviceProfile {
        DeviceProfile(name: "w", vendorID: 111, productID: 222,
                      parts: [DevicePart(name: "Wheel", kind: .wheel, usagePage: 0xFF00,
                                         usage: 0x01, routesAsButton: nil)],
                      rawButtonCapture: false)
    }

    func testStartStartsObserverOnceAndStopForwards() {
        let observer = FakeObserver()
        let pump = HIDEventPump(observer: observer,
                                resolve: { _, _ in .observe(profile: nil) },
                                router: RecordingRouter(), log: nil, analyzer: nil)
        pump.start()
        pump.start()   // idempotent
        XCTAssertEqual(observer.started, 1)
        pump.stop()
        pump.stop()
        XCTAssertEqual(observer.stopped, 1)
    }

    func testPartObservationRoutesTranslatedEvents() {
        let observer = FakeObserver()
        let router = RecordingRouter()
        let pump = HIDEventPump(observer: observer,
                                resolve: { _, _ in .observe(profile: self.profile()) },
                                router: router, log: nil, analyzer: nil)
        pump.start()
        pump.receive(observation(value: 1))
        pump.receive(observation(value: 0))
        XCTAssertEqual(router.events, [.buttonDown(.extended(8)), .buttonUp(.extended(8))])
    }

    func testDisabledDeviceStillLogsButNeverRoutes() {
        let observer = FakeObserver()
        let router = RecordingRouter()
        let log = HIDEventLog()
        let analyzer = HIDAnalyzerStore()
        let pump = HIDEventPump(observer: observer,
                                resolve: { _, _ in .disabled },
                                router: router, log: log, analyzer: analyzer)
        pump.receive(observation())
        XCTAssertTrue(router.events.isEmpty)
        XCTAssertEqual(log.entries.count, 1)
        XCTAssertEqual(analyzer.recent.count, 1)
    }

    func testNoProfileStillLogsButNeverRoutes() {
        let observer = FakeObserver()
        let router = RecordingRouter()
        let log = HIDEventLog()
        let pump = HIDEventPump(observer: observer,
                                resolve: { _, _ in .observe(profile: nil) },
                                router: router, log: log, analyzer: nil)
        pump.receive(observation())
        XCTAssertTrue(router.events.isEmpty)
        XCTAssertEqual(log.entries.count, 1)
    }

    func testMultipleEventsFromOneObservationAllRoute() {
        let observer = FakeObserver()
        let router = RecordingRouter()
        // Raw capture: one button-page observation translates to exactly one
        // event; this test pins that translate() output is iterated, not just
        // the first element taken.
        let pump = HIDEventPump(observer: observer,
                                resolve: { _, _ in .observe(profile: self.profile()) },
                                router: router, log: nil, analyzer: nil)
        pump.receive(observation(value: 1))
        XCTAssertEqual(router.events.count, 1)
    }

    func testObserverCallbackDeliversThroughSink() {
        let observer = FakeObserver()
        let router = RecordingRouter()
        let pump = HIDEventPump(observer: observer,
                                resolve: { _, _ in .observe(profile: self.profile()) },
                                router: router, log: nil, analyzer: nil)
        pump.start()
        observer.sink?(observation(value: 1))   // as the glue would call it (on main)
        XCTAssertEqual(router.events, [.buttonDown(.extended(8))])
    }

    // MARK: Scroll-transform materialization (Final Review Issue 2)

    func testScrollTransformOutcomePostsOneScaledWheelEvent() throws {
        let observer = FakeObserver()
        let router = RecordingRouter()
        router.outcome = .scrollTransform(verticalFactor: 2, horizontalFactor: 3)
        let poster = RecordingPoster()
        let pump = HIDEventPump(observer: observer,
                                resolve: { _, _ in .observe(profile: self.wheelProfile()) },
                                router: router, log: nil, analyzer: nil, poster: poster)
        pump.receive(wheelObservation(value: 1))   // vertical vendor wheel tick
        XCTAssertEqual(router.events, [.scrolled(axis: .vertical, ticks: 1)])
        XCTAssertEqual(poster.events.count, 1)
        let event = try XCTUnwrap(poster.events.first)
        // Scaled ticks ride the 16.16 fixed-point delta fields (ticks ×
        // factor × 65536); the unticked axis carries no delta (see the pump's
        // materialization comment — posting ticks × the untouched 1.0 factor
        // there would scroll diagonally).
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1),
                       Int64(2 * 65536))
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventFixedPtDeltaAxis2), 0)
        // Integer line deltas truncate from the same scaled amount.
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventDeltaAxis1), 2)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventDeltaAxis2), 0)
    }

    func testConsumedScrollPostsNothingFromPump() {
        let observer = FakeObserver()
        let router = RecordingRouter()
        router.outcome = .consume   // binding fired, or emitter-owned intercept
        let poster = RecordingPoster()
        let pump = HIDEventPump(observer: observer,
                                resolve: { _, _ in .observe(profile: self.wheelProfile()) },
                                router: router, log: nil, analyzer: nil, poster: poster)
        pump.receive(wheelObservation(value: 1))
        XCTAssertTrue(poster.events.isEmpty)
    }

    func testPassThroughScrollPostsNothingFromPump() {
        let observer = FakeObserver()
        let router = RecordingRouter()
        router.outcome = .passThrough   // no wheel profile: the tick stays a drop
        let poster = RecordingPoster()
        let pump = HIDEventPump(observer: observer,
                                resolve: { _, _ in .observe(profile: self.wheelProfile()) },
                                router: router, log: nil, analyzer: nil, poster: poster)
        pump.receive(wheelObservation(value: 1))
        XCTAssertTrue(poster.events.isEmpty)
    }

    func testNilPosterLeavesLegacyBehaviorUnchanged() {
        let observer = FakeObserver()
        let router = RecordingRouter()
        router.outcome = .scrollTransform(verticalFactor: 5, horizontalFactor: 5)
        let pump = HIDEventPump(observer: observer,
                                resolve: { _, _ in .observe(profile: self.wheelProfile()) },
                                router: router, log: nil, analyzer: nil)   // no poster
        pump.receive(wheelObservation(value: 1))   // must not trap or post anywhere
        XCTAssertEqual(router.events.count, 1)
    }

    func testRunawayTickMaterializesBoundedEvent() throws {
        // A device-reported runaway delta must not reach the factory's Int32
        // conversion out of range (it traps, and the sink runs on the main
        // run loop): the materialized event is clamped to the boundary bound.
        let observer = FakeObserver()
        let router = RecordingRouter()
        router.outcome = .scrollTransform(verticalFactor: 10, horizontalFactor: 1)
        let poster = RecordingPoster()
        let pump = HIDEventPump(observer: observer,
                                resolve: { _, _ in .observe(profile: self.wheelProfile()) },
                                router: router, log: nil, analyzer: nil, poster: poster)
        pump.receive(wheelObservation(value: Int(Int32.max)))
        XCTAssertEqual(poster.events.count, 1)
        let event = try XCTUnwrap(poster.events.first)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1),
                       Int64(10_000 * 65536))
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventDeltaAxis1), 10_000)
    }
}
