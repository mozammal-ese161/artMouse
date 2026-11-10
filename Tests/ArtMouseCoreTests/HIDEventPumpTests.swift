import XCTest
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
        func handle(_ event: InputEvent) -> RouterOutcome {
            events.append(event)
            return .passThrough
        }
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
}
