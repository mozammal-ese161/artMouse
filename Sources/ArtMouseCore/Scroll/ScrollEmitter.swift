import CoreGraphics
import Foundation

/// Synthesizes scroll/keyboard events on a virtual-clock schedule. The owner
/// drives tick(now:) from a main-run-loop timer (.common mode, Phase-1
/// discipline); all posts go through the shared tagged poster.
public final class ScrollEmitter {
    private enum Mode {
        case idle
        case smooth(direction: ScrollDirection, pendingLines: Double, chunkLines: Double,
                    interval: Double, nextDue: Double)
        case auto(direction: ScrollDirection, lines: Double, interval: Double, due: Double,
                  emissionsSinceInput: Int, stopAfterTicks: Int)
        case keys(keys: WheelKeyEmulation, lastInput: Double, nextRepeat: Double)
    }

    static let keyRepeatInterval: Double = 0.1
    static let keyReleaseGap: Double = 0.25

    private let poster: EventPosting
    private var mode: Mode = .idle
    private var keysDown = false

    public init(poster: EventPosting) {
        self.poster = poster
    }

    public var isActive: Bool {
        if case .idle = mode { return false }
        return true
    }

    public func emitOnce(direction: ScrollDirection, lines: Double) {
        postScroll(direction: direction, lines: lines)
    }

    public func beginSmooth(direction: ScrollDirection, lines: Double, intervalMS: Int, now: Double) {
        releaseKeysIfHeld()
        let interval = Double(intervalMS) / 1000.0
        let emissions = max(1, Int(80.0 / Double(intervalMS)))
        mode = .smooth(direction: direction, pendingLines: lines,
                       chunkLines: lines / Double(emissions), interval: interval, nextDue: now)
        tick(now: now)   // first chunk immediately
    }

    public func beginAuto(direction: ScrollDirection, lines: Double, intervalMS: Int,
                          stopAfterTicks: Int, now: Double) {
        releaseKeysIfHeld()
        mode = .auto(direction: direction, lines: lines, interval: Double(intervalMS) / 1000.0,
                     due: now + Double(intervalMS) / 1000.0,
                     emissionsSinceInput: 0, stopAfterTicks: stopAfterTicks)
    }

    /// A real wheel tick arrived: resets the auto-stop counter and anchors
    /// the keys release-gap to this moment.
    public func noteInput(now: Double) {
        switch mode {
        case .auto(let direction, let lines, let interval, let due, _, let stop):
            mode = .auto(direction: direction, lines: lines, interval: interval, due: due,
                         emissionsSinceInput: 0, stopAfterTicks: stop)
        case .keys(let keys, _, let nextRepeat):
            mode = .keys(keys: keys, lastInput: now, nextRepeat: nextRepeat)
        case .idle, .smooth:
            break
        }
    }

    public func beginKeys(_ keys: WheelKeyEmulation, direction: ScrollDirection, now: Double) {
        releaseKeysIfHeld()
        mode = .keys(keys: keys, lastInput: now, nextRepeat: now + Self.keyRepeatInterval)
        postKey(keys, down: true)
        keysDown = true
    }

    public func tick(now: Double) {
        switch mode {
        case .idle:
            break
        case .smooth(let direction, var pending, let chunk, let interval, var nextDue):
            while nextDue <= now && pending > 0 {
                let emitted = min(chunk, pending)
                postScroll(direction: direction, lines: emitted)
                pending -= emitted
                nextDue += interval
            }
            mode = pending > 0
                ? .smooth(direction: direction, pendingLines: pending, chunkLines: chunk,
                          interval: interval, nextDue: nextDue)
                : .idle
        case .auto(let direction, let lines, let interval, _, var emissions, let stopAfter):
            if emissions >= stopAfter { mode = .idle; return }
            // Auto cadence is driven by the CALLER: the controller pairs auto
            // mode with an emitter-driver timer at autoIntervalMS and calls
            // tick at that cadence (contract documented in Task 4). Each tick
            // emits once; noteInput resets the counter.
            postScroll(direction: direction, lines: lines)
            emissions += 1
            mode = .auto(direction: direction, lines: lines, interval: interval,
                         due: now + interval,
                         emissionsSinceInput: emissions, stopAfterTicks: stopAfter)
        case .keys(let keys, let lastInput, let nextRepeat):
            if now - lastInput >= Self.keyReleaseGap {
                if keysDown { postKey(keys, down: false); keysDown = false }
                mode = .idle
            } else if keys.repeatWhileRolling && now >= nextRepeat {
                postKey(keys, down: true)
                postKey(keys, down: false)
                mode = .keys(keys: keys, lastInput: lastInput, nextRepeat: now + Self.keyRepeatInterval)
            }
        }
    }

    /// A begin* call that replaces a live `.keys` mode must not strand a held
    /// key with no UP ever posted (fix round 1 review finding). The emitter
    /// owns keysDown, so it releases the held key here — with the OLD keys
    /// payload, before the caller rewrites `mode`.
    private func releaseKeysIfHeld() {
        guard keysDown, case .keys(let keys, _, _) = mode else { return }
        postKey(keys, down: false)
        keysDown = false
    }

    private func postScroll(direction: ScrollDirection, lines: Double) {
        let v = direction.axis == .vertical ? direction.sign * lines : 0
        let h = direction.axis == .horizontal ? direction.sign * lines : 0
        // SDK adaptation: this SDK's wheel init is (scrollWheelEvent2Source:
        // units:wheelCount:wheel1:wheel2:wheel3:) with Int32 wheel parameters
        // — the plan's variadic CGFloat wheel:h:0:or:[] overload does not
        // exist here. The int delta fields truncate, so fractional smooth
        // chunks (e.g. lines 3.0 in 5 chunks → 0.6) would scroll as 0 lines;
        // the true value is therefore also carried on the 16.16 fixed-point
        // delta fields, the same shape the system uses for sub-line scrolling.
        // wheelCount must be 2 or the constructor ignores wheel2 (horizontal).
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2,
                            wheel1: Int32(v), wheel2: Int32(h), wheel3: 0)!
        event.setIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1, value: Int64(v * 65536.0))
        event.setIntegerValueField(.scrollWheelEventFixedPtDeltaAxis2, value: Int64(h * 65536.0))
        poster.post(event)
    }

    private func postKey(_ keys: WheelKeyEmulation, down: Bool) {
        // SDK adaptation: this SDK's keyboard CGEvent initializer takes no
        // flags argument; flags are assigned before posting (same form as
        // ActionExecutor.keyPress, Phase 1).
        let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keys.keyCode),
                            keyDown: down)!
        event.flags = CGFlagConversion.cgFlags(keys.mods)
        poster.post(event)
    }
}
