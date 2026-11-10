import CoreGraphics
import Foundation

/// Synthesizes scroll/keyboard events on a virtual-clock schedule. The owner
/// drives tick(now:) from a main-run-loop timer (.common mode, Phase-1
/// discipline); all posts go through the shared tagged poster.
public final class ScrollEmitter {
    private enum Mode {
        case idle
        case smooth(direction: ScrollDirection, remainingLines: Double, chunkLines: Double,
                    interval: Double, nextDue: Double, carry: Double)
        case auto(direction: ScrollDirection, lines: Double, interval: Double, due: Double,
                  emissionsSinceInput: Int, stopAfterTicks: Int)
        case keys(keys: WheelKeyEmulation, lastInput: Double, nextRepeat: Double)
        case coast(direction: ScrollDirection, remaining: Double, decayPercent: Int,
                   emitted: Double, maxLines: Double, nextDue: Double)
    }

    static let keyRepeatInterval: Double = 0.1
    static let keyReleaseGap: Double = 0.25
    static let momentumGapSeconds: Double = 0.12
    static let momentumStepInterval: Double = 0.016
    static let momentumStopFloor: Double = 0.05

    /// Armed free-spin momentum (constant mode only — Review Focus 5). Inert
    /// until tick(now:) sees an idle emitter and gap-quiet input; any stop
    /// or stop-equivalent idle transition discards it, so a coast can never
    /// survive a profile switch or outlive its own decay.
    private struct MomentumState {
        let direction: ScrollDirection
        let linesPerTick: Double
        let decayPercent: Int
        let maxLines: Double
    }

    private let poster: EventPosting
    private var mode: Mode = .idle
    private var keysDown = false
    private var momentum: MomentumState?
    private var momentumLastInput: Double = 0

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
        mode = .smooth(direction: direction, remainingLines: lines,
                       chunkLines: lines / Double(emissions), interval: interval, nextDue: now,
                       carry: 0)
        tick(now: now)   // first chunk immediately
    }

    public func beginAuto(direction: ScrollDirection, lines: Double, intervalMS: Int,
                          stopAfterTicks: Int, now: Double) {
        releaseKeysIfHeld()
        mode = .auto(direction: direction, lines: lines, interval: Double(intervalMS) / 1000.0,
                     due: now + Double(intervalMS) / 1000.0,
                     emissionsSinceInput: 0, stopAfterTicks: stopAfterTicks)
    }

    /// Arms free-spin momentum (constant mode only — Review Focus 5). The
    /// coast itself begins in tick(now:) once input has been quiet for the
    /// gap; fresh input re-anchors the gap via noteInput.
    public func primeMomentum(direction: ScrollDirection, linesPerTick: Double,
                              decayPercent: Int, maxLines: Double, now: Double) {
        guard linesPerTick >= Self.momentumStopFloor else { return }
        momentum = MomentumState(direction: direction, linesPerTick: linesPerTick,
                                 decayPercent: decayPercent, maxLines: maxLines)
        momentumLastInput = now
    }

    /// A real wheel tick arrived: resets the auto-stop counter and anchors
    /// the keys release-gap to this moment.
    public func noteInput(now: Double) {
        momentumLastInput = now
        if case .coast = mode {
            // All owners re-anchor the gap; a live coast dies here AND its
            // primed state with it — only a fresh primeMomentum restarts
            // the sequence.
            mode = .idle
            momentum = nil
        }
        switch mode {
        case .auto(let direction, let lines, let interval, let due, _, let stop):
            mode = .auto(direction: direction, lines: lines, interval: interval, due: due,
                         emissionsSinceInput: 0, stopAfterTicks: stop)
        case .keys(let keys, _, let nextRepeat):
            mode = .keys(keys: keys, lastInput: now, nextRepeat: nextRepeat)
        case .idle, .smooth, .coast:
            // .coast is unreachable here (the if above already killed it) but
            // required for exhaustiveness.
            break
        }
    }

    public func beginKeys(_ keys: WheelKeyEmulation, direction: ScrollDirection, now: Double) {
        releaseKeysIfHeld()
        mode = .keys(keys: keys, lastInput: now, nextRepeat: now + Self.keyRepeatInterval)
        postKey(keys, down: true)
        keysDown = true
    }

    /// Ends the active mode immediately (profile switch / wheel-mode
    /// rotation), releasing any held key first.
    public func stop() {
        releaseKeysIfHeld()
        mode = .idle
        momentum = nil
    }

    public func tick(now: Double) {
        // Momentum coast: only starts when the emitter owns nothing else
        // (constant mode is fire-and-forget, so idle here means no keys/auto/
        // smooth run is open) and input has gone quiet.
        if case .idle = mode, let momentum = self.momentum,
           now - momentumLastInput >= Self.momentumGapSeconds {
            mode = .coast(direction: momentum.direction, remaining: momentum.linesPerTick,
                          decayPercent: momentum.decayPercent, emitted: 0,
                          maxLines: momentum.maxLines, nextDue: now)
        }
        switch mode {
        case .idle:
            break
        case .coast(let direction, let remaining, let decayPercent, let emitted,
                    let maxLines, let nextDue):
            guard now >= nextDue, remaining >= Self.momentumStopFloor, emitted < maxLines else {
                if remaining < Self.momentumStopFloor || emitted >= maxLines {
                    mode = .idle
                    momentum = nil   // a spent coast must never restart itself
                }
                return
            }
            postScroll(direction: direction, lines: remaining)
            let nextRemaining = remaining * (Double(decayPercent) / 100.0)
            let nextEmitted = emitted + remaining
            if nextRemaining < Self.momentumStopFloor || nextEmitted >= maxLines {
                mode = .idle
                momentum = nil   // a spent coast must never restart itself
            } else {
                mode = .coast(direction: direction, remaining: nextRemaining,
                              decayPercent: decayPercent, emitted: nextEmitted,
                              maxLines: maxLines, nextDue: now + Self.momentumStepInterval)
            }
        case .smooth(let direction, var remaining, let chunk, let interval, var nextDue, var carry):
            // Integral emission with a fractional carry: chunks (e.g. 3 lines
            // / 5 = 0.6) accumulate until they cross a whole line, because the
            // line delta fields truncate and an integer-line consumer would
            // otherwise see 0 on every tick.
            while nextDue <= now && remaining > 0 {
                carry += min(chunk, remaining)
                // The 1e-9 epsilon absorbs the drift of accumulating a
                // non-binary chunk (0.2 + 1.2 × 4 lands at 1.9999999999999998
                // and would otherwise floor to 1, dropping the final line).
                let emit = floor(carry + 1e-9)
                carry -= emit
                if carry < 0 { carry = 0 }
                if emit >= 1 { postScroll(direction: direction, lines: emit) }
                remaining -= min(chunk, remaining)
                nextDue += interval
            }
            // Drain to idle only when the distance is spent AND no sub-line
            // remainder is pending; a final sub-line chunk (< 1 line) is
            // dropped — it cannot be expressed as a whole line delta.
            if remaining <= 0 && carry < 1 {
                mode = .idle
                momentum = nil   // a smooth drain belongs to another owner: momentum is stale
            } else {
                mode = .smooth(direction: direction, remainingLines: remaining, chunkLines: chunk,
                               interval: interval, nextDue: nextDue, carry: carry)
            }
        case .auto(let direction, let lines, let interval, let due, var emissions, let stopAfter):
            if emissions >= stopAfter {
                mode = .idle
                momentum = nil   // an auto stop belongs to another owner: momentum is stale
                return
            }
            // Fix round 1: auto cadence is gated by `due` (armed at beginAuto,
            // advanced by the interval on each emission), so a fast cadence
            // pump (Task 8's 8 ms timer) cannot outrun autoIntervalMS. Each
            // emission fires once; noteInput resets the stop counter only.
            guard now >= due else { return }
            postScroll(direction: direction, lines: lines)
            emissions += 1
            mode = .auto(direction: direction, lines: lines, interval: interval,
                         due: now + interval,
                         emissionsSinceInput: emissions, stopAfterTicks: stopAfter)
        case .keys(let keys, let lastInput, let nextRepeat):
            if now - lastInput >= Self.keyReleaseGap {
                if keysDown { postKey(keys, down: false); keysDown = false }
                mode = .idle
                momentum = nil   // a keys release belongs to another owner: momentum is stale
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
        // exist here. The int delta fields truncate, so smooth scrolling
        // emits whole lines (carry scheme in tick(now:)) and any fractional
        // lines setting (e.g. Constant at 3.5 lines) still carries its true
        // value on the 16.16 fixed-point delta fields, the same shape the
        // system uses for sub-line scrolling.
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
