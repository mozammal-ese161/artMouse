import CoreGraphics
import Foundation

public struct MacroProgram {
    public var steps: [MacroStep]
    public var repeatMode: RepeatMode
    public var repeatIntervalMS: Int
    public var modifierProxy: Bool

    public init(steps: [MacroStep], repeatMode: RepeatMode,
                repeatIntervalMS: Int, modifierProxy: Bool) {
        self.steps = steps
        self.repeatMode = repeatMode
        self.repeatIntervalMS = repeatIntervalMS
        self.modifierProxy = modifierProxy
    }
}

/// Executes macro step sequences as cancellable Tasks. All task-dictionary
/// mutation happens on the caller's (main run loop) thread; spawned Tasks
/// only post events (CGEvent.post is thread-safe) and sleep. All posts go
/// through the shared tagged poster.
public final class MacroEngine {
    static let waitClamp = 1...60_000
    static let repeatIntervalClamp = 10...5_000

    private let poster: EventPosting
    private let cursorLocation: () -> CGPoint
    private let sleep: (Int) async throws -> Void
    private let flagReader: () -> ModKeys
    private var tasks: [ButtonID: Task<Void, Never>] = [:]
    /// Bumped on every lifecycle transition (run and stop) for a button. A
    /// task's hopped finishTask carries its generation and must not mutate the
    /// registry once a newer task owns the button — without this, the OLD
    /// task's finishTask nils the NEW run's registration and the new loop
    /// keeps running but unregistered (stop no-ops on it forever).
    private var generations: [ButtonID: Int] = [:]
    private var keysDown: [ButtonID: UInt64] = [:]   // button → currently-held macro key

    public init(poster: EventPosting,
                cursorLocation: @escaping () -> CGPoint = { CGEvent(source: nil)?.location ?? .zero },
                sleep: @escaping (Int) async throws -> Void = { ms in
                    try await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
                },
                flagReader: @escaping () -> ModKeys = { BootstrapDecision.currentFlags() }) {
        self.poster = poster
        self.cursorLocation = cursorLocation
        self.sleep = sleep
        self.flagReader = flagReader
    }

    public func isRunning(for button: ButtonID) -> Bool {
        tasks[button] != nil
    }

    /// Cancels any running program for the button and starts a new one.
    public func run(program: MacroProgram, for button: ButtonID) {
        stop(for: button)
        // finishTask mutates the task dictionaries, so it hops back to the
        // main queue where run/stop live (the calling-discipline contract);
        // the spawned Task itself only posts events and sleeps. The hop
        // carries this run's generation so a superseded task's finishTask
        // cannot clear a newer run's registration (the generation guard).
        generations[button, default: 0] += 1
        let generation = generations[button]!
        tasks[button] = Task { [weak self] in
            await self?.runLoop(program: program)
            Task { @MainActor [weak self] in
                self?.finishTask(for: button, generation: generation)
            }
        }
    }

    public func stop(for button: ButtonID) {
        // Invalidate older generations first: a late hopped finishTask from
        // the task being stopped must not clear a task re-registered after
        // this stop (same race as in run, from the other direction).
        generations[button, default: 0] += 1
        tasks[button]?.cancel()
        tasks[button] = nil
        releaseHeldKey(for: button)
    }

    public func stopAll() {
        for button in tasks.keys { stop(for: button) }
    }

    /// Task body: one pass for .none; loop for .hold until cancelled.
    private func runLoop(program: MacroProgram) async {
        let interval = program.repeatIntervalMS.clamped(Self.repeatIntervalClamp)
        repeat {
            await execute(program: program)
            guard program.repeatMode == .hold else { return }
            try? await sleep(interval)
        } while !Task.isCancelled
    }

    /// The sequence itself. Cancellation lands BETWEEN steps and between the
    /// two halves of a key pair is prevented by checking before each pair.
    func execute(program: MacroProgram) async {
        let flagBase: CGEventFlags = program.modifierProxy ? CGFlagConversion.cgFlags(flagReader()) : []
        for step in program.steps {
            if Task.isCancelled { return }
            switch step {
            case .enterKey(let keyCode, let mods):
                var flags = CGFlagConversion.cgFlags(mods)
                if program.modifierProxy { flags.formUnion(flagBase) }
                postKey(keyCode: keyCode, flags: flags, down: true)
                postKey(keyCode: keyCode, flags: flags, down: false)
            case .click(let op, let mods):
                var flags = CGFlagConversion.cgFlags(mods)
                if program.modifierProxy { flags.formUnion(flagBase) }
                postClick(op: op, mods: mods, extraFlags: flags)
            case .wait(let ms):
                try? await sleep(ms.clamped(Self.waitClamp))
            }
        }
    }

    private func finishTask(for button: ButtonID, generation: Int) {
        // The held key belongs to the finishing task, so release it even when
        // a newer generation has already taken the button.
        releaseHeldKey(for: button)
        // Only clear if this task is still the registered one: any run or
        // stop since it started bumped the generation (a newer run may have
        // replaced it, or a stop already cleaned up).
        guard generations[button] == generation else { return }
        tasks[button] = nil
    }

    // Kept for hold-modes that hold a key across steps in later phases;
    // currently every key pair posts back-to-back so this is a no-op guard.
    private func releaseHeldKey(for button: ButtonID) {
        guard let keyCode = keysDown.removeValue(forKey: button) else { return }
        postKey(keyCode: keyCode, flags: [], down: false)
    }

    // SDK adaptation (same ruling as ActionExecutor.keyPress): the keyboard
    // CGEvent initializer takes no flags argument; the flags are assigned to
    // each event before it is posted.
    private func postKey(keyCode: UInt64, flags: CGEventFlags, down: Bool) {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode),
                            keyDown: down)!
        event.flags = flags
        poster.post(event)
    }

    /// Same construction as ActionExecutor's standard click (clickState 1,
    /// cursor location), plus merged proxy flags. A `.doubleLeft` step posts
    /// ONE pair here — double-click semantics inside macros land in Phase 4.
    private func postClick(op: ClickOp, mods: ModKeys, extraFlags: CGEventFlags) {
        var flags = CGFlagConversion.cgFlags(mods)
        flags.formUnion(extraFlags)
        let location = cursorLocation()
        let number = clickNumber(op)
        let down = CGEvent(mouseEventSource: nil, mouseType: downType(op, number: number),
                           mouseCursorPosition: location, mouseButton: .center)!
        down.setIntegerValueField(.mouseEventButtonNumber, value: Int64(number))
        down.setIntegerValueField(.mouseEventClickState, value: 1)
        down.flags = flags
        let up = CGEvent(mouseEventSource: nil, mouseType: upType(op, number: number),
                         mouseCursorPosition: location, mouseButton: .center)!
        up.setIntegerValueField(.mouseEventButtonNumber, value: Int64(number))
        up.setIntegerValueField(.mouseEventClickState, value: 1)
        up.flags = flags
        poster.post(down)
        poster.post(up)
    }

    private func clickNumber(_ op: ClickOp) -> Int {
        switch op {
        case .left: return 0
        case .right: return 1
        case .middle: return 2
        case .doubleLeft: return 0
        case .fourth: return 3
        case .fifth: return 4
        case .clickLock: return 0
        }
    }

    private func downType(_ op: ClickOp, number: Int) -> CGEventType {
        switch (op, number) {
        case (.left, 0), (.doubleLeft, 0): return .leftMouseDown
        case (.right, 1): return .rightMouseDown
        default: return .otherMouseDown
        }
    }

    private func upType(_ op: ClickOp, number: Int) -> CGEventType {
        switch (op, number) {
        case (.left, 0), (.doubleLeft, 0): return .leftMouseUp
        case (.right, 1): return .rightMouseUp
        default: return .otherMouseUp
        }
    }
}

/// The router-facing surface of the macro engine (Task 3): a button-down runs
/// the button's program, a button-up stops a hold-mode loop. Same main-run
/// loop calling discipline as every other coordinator (only run/stop mutate
/// the registries; the spawned Tasks only post events and sleep).
extension MacroEngine: MacroCoordinating {}

private extension Int {
    func clamped(_ range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
