import Foundation

public enum ChordDecision: Equatable {
    case route
    case consume
    case fire([Action])
    case flush([ButtonID])
}

public protocol ChordCoordinating: AnyObject {
    func intercept(_ event: InputEvent, now: Double) -> ChordDecision
}

/// Multi-button chord FSM. Lazy timeout: evaluated on every intercept — no
/// timer. `.fire`/`.flush` decisions are executed by the router (Task 8):
/// fire performs the actions; flush performs the held buttons' normal
/// bindings and re-sends the triggering event through intercept once.
public final class ChordEngine: ChordCoordinating {
    private struct Capture {
        let first: ButtonID
        var held: [ButtonID]
        let start: Double
        let timeout: Double
    }

    private let settings: SettingsStore
    private let clock: () -> Double
    private var capture: Capture?

    public init(settings: SettingsStore, clock: @escaping () -> Double = { Date().timeIntervalSince1970 }) {
        self.settings = settings
        self.clock = clock
    }

    public func intercept(_ event: InputEvent, now: Double) -> ChordDecision {
        guard var active = capture else {
            guard case .buttonDown(let b) = event else { return .route }
            return startIfChordStarter(b, now: now)
        }
        if now - active.start > active.timeout {
            let flushed = active.held
            capture = nil
            return .flush(flushed)
        }
        switch event {
        case .buttonDown(let b):
            return handleDown(b, capture: &active)
        case .buttonUp(let b):
            return handleUp(b, capture: &active)
        default:
            return .route
        }
    }

    // MARK: - FSM arms

    private func startIfChordStarter(_ b: ButtonID, now: Double) -> ChordDecision {
        let candidates = settings.settings.chords.filter { $0.buttons.first == b }
        guard let first = candidates.first else { return .route }
        let timeout = candidates.map(\.timeout).max() ?? first.timeout
        capture = Capture(first: b, held: [b], start: now, timeout: timeout)
        return .consume
    }

    private func handleDown(_ b: ButtonID, capture: inout Capture) -> ChordDecision {
        if capture.held.contains(b) { return .consume }   // repeat-down of a held button

        let extended = capture.held + [b]
        // Extension outranks completion: while the extended set is a PROPER
        // subset of some longer candidate chord, that candidate remains
        // completable and its timeout governs the capture (pinned by
        // testLongestCandidateChordTimeoutGoverns), so a shorter fully-held
        // chord must not fire yet.
        if extendsSomeChord(for: extended) {
            capture.held = extended
            self.capture = capture
            return .consume
        }
        if let chord = completingChord(for: extended) {
            let actions = chord.actions
            self.capture = nil
            return .fire(actions)
        }
        // Extends nothing: flush the held buttons; Task 8's router re-sends
        // the triggering down fresh after performing the flush.
        let flushed = capture.held
        self.capture = nil
        return .flush(flushed)
    }

    private func handleUp(_ b: ButtonID, capture: inout Capture) -> ChordDecision {
        guard capture.held.contains(b) else { return .route }
        if b == capture.first && capture.held.count == 1 {
            let flushed = capture.held
            self.capture = nil
            return .flush(flushed)
        }
        capture.held.removeAll { $0 == b }
        self.capture = capture
        return .consume
    }

    // MARK: - Chord matching

    private func completingChord(for held: [ButtonID]) -> Chord? {
        let set = Set(held)
        return settings.settings.chords.first { Set($0.buttons) == set }
    }

    /// True when `held` is a proper subset of some chord's button set — the
    /// longer chord can still be completed, so the capture keeps extending.
    /// Proper (not plain) subset: an exact match must fall through to the
    /// completion arm and fire instead of extending forever.
    private func extendsSomeChord(for held: [ButtonID]) -> Bool {
        let set = Set(held)
        return settings.settings.chords.contains {
            let candidate = Set($0.buttons)
            return candidate.count > set.count && candidate.isSuperset(of: set)
        }
    }
}
