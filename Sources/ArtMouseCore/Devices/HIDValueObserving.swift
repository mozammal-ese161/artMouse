import Foundation

/// Observes raw HID input values. Contract: `sink` is invoked on the MAIN
/// queue — everything downstream (pump routing, log, analyzer, router state)
/// shares the tap path's main-run-loop discipline (bootstrap calling
/// discipline). The real implementation is IOKitHIDValueObserver; tests use
/// fakes.
public protocol HIDValueObserving: AnyObject {
    func start(sink: @escaping (RawHIDObservation) -> Void)
    func stop()
}

public enum HIDObserveDecision: Equatable {
    /// Device is disabled in settings: log and analyzer still record (the
    /// analyzer is a diagnostic), but nothing routes.
    case disabled
    case observe(profile: DeviceProfile?)
}

/// Feeds observed HID values through the translator into the router, after
/// logging/analyzer capture. Consumed on the main queue only.
public final class HIDEventPump {
    private let observer: HIDValueObserving
    private let resolve: (_ vendorID: Int, _ productID: Int) -> HIDObserveDecision
    private let router: EventRouting
    private let log: HIDEventLog?
    private let analyzer: HIDAnalyzerStore?
    private var running = false

    public init(observer: HIDValueObserving,
                resolve: @escaping (Int, Int) -> HIDObserveDecision,
                router: EventRouting,
                log: HIDEventLog? = nil,
                analyzer: HIDAnalyzerStore? = nil) {
        self.observer = observer
        self.resolve = resolve
        self.router = router
        self.log = log
        self.analyzer = analyzer
    }

    public func start() {
        guard !running else { return }
        running = true
        observer.start { [weak self] observation in
            self?.receive(observation)
        }
    }

    public func stop() {
        guard running else { return }
        running = false
        observer.stop()
    }

    /// The sink body. Internal so tests can drive it without system HID.
    func receive(_ observation: RawHIDObservation) {
        log?.record(observation)
        analyzer?.record(observation)
        guard case .observe(let profile) = resolve(observation.vendorID, observation.productID)
        else { return }
        for event in HIDEventTranslator.translate(observation, profile: profile) {
            _ = router.handle(event)
        }
    }
}
