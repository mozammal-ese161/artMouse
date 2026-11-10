import XCTest
@testable import ArtMouseCore

final class ScrollControllerTests: XCTestCase {
    private let poster = RecordingPoster()

    private func makeStore(profiles: [WheelModeProfile], activeID: UUID? = nil) -> SettingsStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = SettingsStore(directory: dir)
        var settings = store.settings
        settings.wheelModeProfiles = profiles
        settings.activeWheelModeProfileID = activeID
        store.settings = settings
        return store
    }

    func testNoProfilePassesThrough() {
        let store = makeStore(profiles: [])
        let controller = ScrollController(store: store, emitter: ScrollEmitter(poster: poster))
        XCTAssertEqual(controller.disposition(forScroll: .vertical, ticks: 3), .passThrough)
    }

    func testAccelerationModeScalesTicks() {
        // sensFactor 2.0, acceleration 1.0, ticks 3 → 2 × (1 + 1×(3/3)) = 4.0, up is +
        let store = makeStore(profiles: [WheelModeProfile(name: "Default", sensFactor: 2.0, acceleration: 1.0)])
        let controller = ScrollController(store: store, emitter: ScrollEmitter(poster: poster))
        XCTAssertEqual(controller.disposition(forScroll: .vertical, ticks: 3),
                       .scale(vertical: 4.0, horizontal: 1.0))
    }

    func testReverseFlipsSign() {
        let store = makeStore(profiles: [WheelModeProfile(name: "Default", reverseVertical: true)])
        let controller = ScrollController(store: store, emitter: ScrollEmitter(poster: poster))
        XCTAssertEqual(controller.disposition(forScroll: .vertical, ticks: 2),
                       .scale(vertical: -1.0, horizontal: 1.0))
    }

    func testHorizontalReverseOnlyAffectsHorizontal() {
        let store = makeStore(profiles: [WheelModeProfile(name: "Default", reverseHorizontal: true)])
        let controller = ScrollController(store: store, emitter: ScrollEmitter(poster: poster))
        XCTAssertEqual(controller.disposition(forScroll: .vertical, ticks: 2),
                       .scale(vertical: 1.0, horizontal: 1.0))
        XCTAssertEqual(controller.disposition(forScroll: .horizontal, ticks: 2),
                       .scale(vertical: 1.0, horizontal: -1.0))
    }

    func testConstantModeEmitsOnceAndIntercepts() {
        let store = makeStore(profiles: [WheelModeProfile(name: "Default", mode: .constant, lines: 7)])
        let emitter = ScrollEmitter(poster: poster)
        let controller = ScrollController(store: store, emitter: emitter)
        XCTAssertEqual(controller.disposition(forScroll: .vertical, ticks: 1), .intercept)
        XCTAssertEqual(poster.events.count, 1)
        XCTAssertEqual(poster.events[0].getDoubleValueField(.scrollWheelEventDeltaAxis1), 7, accuracy: 1e-9)
    }

    func testSmoothModeInterceptsAndEmits() {
        let store = makeStore(profiles: [WheelModeProfile(name: "Default", smoothScroll: true)])
        let emitter = ScrollEmitter(poster: poster)
        let controller = ScrollController(store: store, emitter: emitter)
        XCTAssertEqual(controller.disposition(forScroll: .vertical, ticks: 3), .intercept)
        XCTAssertTrue(emitter.isActive)   // smooth chunks pending
    }

    func testKeyEmulationTakesPrecedence() {
        let store = makeStore(profiles: [WheelModeProfile(name: "Default", mode: .constant,
                                                          keyEmulation: WheelKeyEmulation(keyCode: 40))])
        let emitter = ScrollEmitter(poster: poster)
        let controller = ScrollController(store: store, emitter: emitter)
        XCTAssertEqual(controller.disposition(forScroll: .vertical, ticks: 2), .intercept)
        XCTAssertEqual(poster.events.first?.type, .keyDown)   // keys, not scroll
    }

    func testAutoModeStartsAndIntercepts() {
        let store = makeStore(profiles: [WheelModeProfile(name: "Default", mode: .auto, autoStopTicks: 2)])
        let emitter = ScrollEmitter(poster: poster)
        let controller = ScrollController(store: store, emitter: emitter)
        XCTAssertEqual(controller.disposition(forScroll: .vertical, ticks: 1), .intercept)
        XCTAssertTrue(emitter.isActive)
    }

    func testClampingAtConsumption() {
        let store = makeStore(profiles: [WheelModeProfile(name: "Default", sensFactor: 99, acceleration: 99)])
        let controller = ScrollController(store: store, emitter: ScrollEmitter(poster: poster))
        // clamped: sens 10, accel 10 → 10 × (1 + 10×(3/3)) = 110
        XCTAssertEqual(controller.disposition(forScroll: .vertical, ticks: 3),
                       .scale(vertical: 110.0, horizontal: 1.0))
    }

    func testActivateNextWheelModeRotates() {
        let a = WheelModeProfile(name: "A")
        let b = WheelModeProfile(name: "B")
        let store = makeStore(profiles: [a, b])
        let controller = ScrollController(store: store, emitter: ScrollEmitter(poster: poster))
        controller.activateNextWheelMode()
        XCTAssertEqual(store.settings.activeWheelProfile, b)   // no named Default → first ("A") was active
    }

    // Fix round 1 (review finding): switching profiles mid-auto must not strand
    // the running auto emitter.
    func testSwitchToConstantStopsRunningAuto() {
        let store = makeStore(profiles: [WheelModeProfile(name: "Default", mode: .auto)])
        let emitter = ScrollEmitter(poster: poster)
        let controller = ScrollController(store: store, emitter: emitter)
        XCTAssertEqual(controller.disposition(forScroll: .vertical, ticks: 1), .intercept)
        XCTAssertTrue(emitter.isActive)                        // auto running under the auto profile
        store.settings.wheelModeProfiles = [WheelModeProfile(name: "Default", mode: .constant)]
        store.settings.activeWheelModeProfileID = nil
        XCTAssertEqual(controller.disposition(forScroll: .vertical, ticks: 1), .intercept)
        XCTAssertFalse(emitter.isActive)                       // auto stopped; emitOnce leaves no mode running
    }

    func testSwitchWheelModeStopsRunningAuto() {
        let store = makeStore(profiles: [WheelModeProfile(name: "A", mode: .auto),
                                         WheelModeProfile(name: "B")])
        let emitter = ScrollEmitter(poster: poster)
        let controller = ScrollController(store: store, emitter: emitter)
        XCTAssertEqual(controller.disposition(forScroll: .vertical, ticks: 1), .intercept)
        XCTAssertTrue(emitter.isActive)                        // auto running under profile A
        controller.activateNextWheelMode()
        XCTAssertFalse(emitter.isActive)                       // wheel-mode rotation stops the auto
    }

    // Fix round 2 (review residual): the .acceleration arm was the one branch
    // still stranding a live auto on profile switch.
    func testSwitchToAccelerationStopsRunningAuto() {
        let store = makeStore(profiles: [WheelModeProfile(name: "Default", mode: .auto)])
        let emitter = ScrollEmitter(poster: poster)
        let controller = ScrollController(store: store, emitter: emitter)
        XCTAssertEqual(controller.disposition(forScroll: .vertical, ticks: 1), .intercept)
        XCTAssertTrue(emitter.isActive)                        // auto running under the auto profile
        store.settings.wheelModeProfiles = [WheelModeProfile(name: "Default")]
        store.settings.activeWheelModeProfileID = nil
        XCTAssertEqual(controller.disposition(forScroll: .vertical, ticks: 2),
                       .scale(vertical: 1.0, horizontal: 1.0))
        XCTAssertFalse(emitter.isActive)                       // auto stopped; scaled ticks carry the motion
    }

    // Native momentum events can carry zero deltas — nothing to resolve.
    func testZeroTickPassesThrough() {
        let store = makeStore(profiles: [WheelModeProfile(name: "Default")])
        let controller = ScrollController(store: store, emitter: ScrollEmitter(poster: poster))
        XCTAssertEqual(controller.disposition(forScroll: .vertical, ticks: 0), .passThrough)
    }
}
