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
        // the spawned Task itself only posts events and sleeps.
        tasks[button] = Task { [weak self] in
            await self?.runLoop(program: program)
            Task { @MainActor [weak self] in
                self?.finishTask(for: button)
            }
        }
    }

    public func stop(for button: ButtonID) {
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

    private func finishTask(for button: ButtonID) {
        releaseHeldKey(for: button)
        // Only clear if this task is still the registered one (a newer run
        // may have replaced it).
        if tasks[button] != nil { tasks[button] = nil }
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

private extension Int {
    func clamped(_ range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
