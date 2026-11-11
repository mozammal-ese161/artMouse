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
/// logging/analyzer capture. Consumed on the main queue only. `poster` is the
/// shared tagged event poster (nil in legacy/tests call sites): it lets the
/// pump materialize `.scrollTransform` outcomes, which have no real CGEvent
/// on the HID path to mutate (see materializeScrollTransform).
public final class HIDEventPump {
    private let observer: HIDValueObserving
    private let resolve: (_ vendorID: Int, _ productID: Int) -> HIDObserveDecision
    private let router: EventRouting
    private let log: HIDEventLog?
    private let analyzer: HIDAnalyzerStore?
    private let poster: EventPosting?
    private var running = false

    public init(observer: HIDValueObserving,
                resolve: @escaping (Int, Int) -> HIDObserveDecision,
                router: EventRouting,
                log: HIDEventLog? = nil,
                analyzer: HIDAnalyzerStore? = nil,
                poster: EventPosting? = nil) {
        self.observer = observer
        self.resolve = resolve
        self.router = router
        self.log = log
        self.analyzer = analyzer
        self.poster = poster
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
            let outcome = router.handle(event)
            materializeScrollTransform(outcome, for: event)
        }
    }

    /// The HID path has no real CGEvent for the router's scroll outcome to
    /// mutate — the tap path scales the native scrollWheel delta fields, but
    /// a profile wheel part produces only a translated InputEvent. Without
    /// materialization the `.scrollTransform` outcome (acceleration mode, the
    /// DEFAULT wheel mode) is discarded and vendor wheel parts never scroll.
    /// The synthetic wheel event is posted through the SAME tagged poster as
    /// every other synthetic event: the tag makes the engine tap pass it
    /// through unrouted, so it cannot re-fire the binding — the wheel binding
    /// fires once, from the original HID tick. `.passThrough` stays a drop
    /// (there is no native event to release) and `.consume` stays
    /// pump-silent (a binding's executor or the scroll emitter already
    /// posted its own synthetics).
    private func materializeScrollTransform(_ outcome: RouterOutcome, for event: InputEvent) {
        guard let poster,
              case .scrolled(let axis, let ticks) = event,
              case .scrollTransform(let verticalFactor, let horizontalFactor) = outcome
        else { return }
        // The factors scale DELTAS (tap-path semantics: native delta ×
        // factor), so the tick rides the ticked axis only — the unticked
        // axis carries no native delta (the controller leaves its factor at
        // the untouched 1.0), and posting ticks × 1.0 there would scroll
        // diagonally on every tick.
        switch axis {
        case .vertical:
            poster.post(WheelEventFactory.lineEvent(
                vertical: Self.clampedScroll(ticks * verticalFactor), horizontal: 0))
        case .horizontal:
            poster.post(WheelEventFactory.lineEvent(
                vertical: 0, horizontal: Self.clampedScroll(ticks * horizontalFactor)))
        }
    }

    /// Engine-boundary clamp for the materialized tick (same discipline as
    /// ActionExecutor's scroll clamp): HID element values are untrusted
    /// device data, and WheelEventFactory converts the line deltas through
    /// Int32, which TRAPS on out-of-range doubles — a runaway reported delta
    /// must never crash the main-run-loop sink. ±10 000 lines sits far above
    /// any physical scroll burst (the executor clamps user settings to 100)
    /// yet far below the conversion limit.
    private static func clampedScroll(_ lines: Double) -> Double {
        guard lines.isFinite else { return 0 }
        return Swift.min(Swift.max(lines, -10_000), 10_000)
    }
}
