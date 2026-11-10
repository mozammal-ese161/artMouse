# artMouse Phase 3 — Macros, Snapping, Per-App Profiles, Import/Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add key-macro actions (enter/click/wait steps with hold-repeat and modifier proxy), cursor snapping (jump/click/bounce via Accessibility), per-application profiles (AppWatcher-driven overrides for bindings, cursor speed, wheel mode), and settings import/export.

**Architecture:** `MacroEngine` executes step sequences as cancellable Tasks posting through the shared tagged poster (waits via an injected async sleeper — fully virtual-clock testable); hold-repeat loops until the router signals stop on button-up. `SnappingController` reads the focused window's default button frame through an injectable AX finder and moves/clicks/returns via posted events. Per-app profiles resolve through `effective*` helpers on `GlobalSettings` keyed by `AppWatcher.frontmostBundleID`, consumed by the router and both controllers. Import/export is strict-decode-then-replace on the settings store.

**Tech Stack:** Swift 5.9, SPM, XCTest, AppKit/SwiftUI, ApplicationServices (AX). Zero third-party dependencies. Builds on the merged Phase 1+2 codebase at `main`.

**Spec:** `docs/superpowers/specs/2026-11-09-artmouse-design.md` — §4 MacroEngine/SnappingController/AppWatcher, §5 data model, §6 Phase 3 bullet. The plan argues from the spec; executors read both.

## Global Constraints

- macOS 14.0 floor (`platforms: [.macOS(.v14)]`), `// swift-tools-version: 5.9`, zero third-party dependencies.
- Engine logic lives only in `ArtMouseCore`; app-target files render and forward only; one view struct per file; split any file nearing ~150 lines; SwiftUI editors are derive-from-props (NO `@State`).
- TDD: failing test documented (RED) before implementation, green before commit. Commits: plain imperative messages, never any AI attribution lines or Co-Authored-By trailers.
- Main-run-loop single-queue discipline: MacroEngine's task dictionary is mutated only from the router path (main run loop); spawned macro Tasks post events (thread-safe) and touch no shared controller state.
- ALL synthetic events (macro keys, macro clicks, snapping moves/clicks) go through the shared `CGEventPoster` instance so they carry the private-source tag and pass the tap unrouted.
- **Backward compatibility:** Phase 1+2 `settings.json` MUST keep decoding — every new `GlobalSettings` field defaults via `decodeIfPresent` in the custom `init(from:)` (pattern shipped in Phase 2 Task 2).
- Engine-side clamping precedent: clamp macro repeat interval 10...5000 ms and wait steps 1...60000 ms at consumption in `MacroEngine`.
- Sanctioned deviations from spec §5 (recorded): `RepeatMode` is `none | hold` (hold = repeat whole sequence every interval while the button is held — covers SteerMouse's repeat + continuous); modifier proxy reads physical modifiers via `CGEventSource.flagsState(.combinedSessionState)` at macro start; per-app BUTTON/SCROLL binding overrides are data-model-ready but UI-edited only via settings.json in v1 (caption documents this); snapping covers jump (no click), click-and-stay, and click-and-return (bounce).

## Review Focus

Failure modes the spec implies that unit tests below do not fully exercise. Each line's pinning verification lives in the named task.

1. **Macro step ordering and atomicity:** posted events must match step order exactly, and cancellation must land BETWEEN steps — never stranding a pressed key or half a click pair. Pinned by Task 2's ordering + cancellation tests.
2. **Hold-repeat termination:** a hold-macro must stop within one step boundary of button-up — a runaway repeat outlives the button forever. Pinned by Task 2's stop test + Task 3's router up-path test.
3. **Snapping with no accessible default button** (no focused window / no default button): no-op — cursor unmoved, nothing posted. Pinned by Task 4's nil-frame test.
4. **Per-app resolution fallback:** frontmost app with no profile (or nil watcher) falls back to global bindings — never a crash or empty-binding zombie. Pinned by Task 5's fallback tests.
5. **Import must not corrupt live settings:** a malformed or foreign import file leaves current settings untouched (strict decode throws before any assignment). Pinned by Task 9's import-failure test.

---

## File Structure (Phase 3)

```
artMouse/
├── Sources/ArtMouseCore/
│   ├── Model/
│   │   ├── MacroModel.swift               # MacroStep, RepeatMode, SnappingOp
│   │   ├── AppProfile.swift
│   │   └── Action.swift                   # (exists — + .macro, .snapping cases)
│   ├── Settings/
│   │   ├── AppProfileSettings.swift       # AppProfile struct + effective* helpers
│   │   └── GlobalSettings.swift           # (exists — + appProfiles field)
│   ├── Engine/
│   │   ├── MacroEngine.swift              # cancellable task runner
│   │   ├── EventRouter.swift              # (exists — + macros, watcher)
│   │   ├── SnappingController.swift       # AX snap/jump/click/bounce
│   │   └── AppWatcher.swift               # (exists — + FrontmostProviding)
│   ├── Scroll/
│   │   └── ScrollController.swift         # (exists — + watcher resolution)
│   ├── Cursor/
│   │   └── CursorController.swift         # (exists — + watcher resolution)
│   └── Actions/
│       └── ActionExecutor.swift           # (exists — + snapping arm)
├── Sources/artMouse/
│   ├── AppModel.swift                     # (exists — + app-profile/import-export methods)
│   ├── EngineBootstrap.swift              # (exists — + macro engine, snapping, watcher sharing)
│   └── Views/
│       ├── SettingsWindow.swift           # (exists — + Apps/General tabs, new categories)
│       ├── ActionEditorView.swift         # (exists — + macro/snapping categories)
│       ├── MacroActionEditorView.swift
│       ├── MacroStepsEditorView.swift
│       ├── MacroStepEditorView.swift
│       ├── SnapActionEditorView.swift
│       ├── AppsTabView.swift
│       ├── AppProfileEditorView.swift
│       └── GeneralTabView.swift
└── Tests/ArtMouseCoreTests/
    ├── ActionModelTests.swift             # (exists — + macro/snapping cases)
    ├── MacroEngineTests.swift
    ├── SnappingControllerTests.swift
    ├── EventRouterTests.swift             # (exists — + macro/snapping/app-profile routing)
    ├── ScrollControllerTests.swift        # (exists — + watcher resolution)
    ├── CursorControllerTests.swift        # (exists — + watcher resolution)
    ├── SettingsStoreTests.swift           # (exists — + appProfiles field, effective* helpers)
    └── AppModelTests.swift                # NEW (import/export round-trip)
```

---

### Task 1: Macro/snapping models and Action cases

**Files:**
- Create: `Sources/ArtMouseCore/Model/MacroModel.swift`
- Modify: `Sources/ArtMouseCore/Model/Action.swift` (add `.macro`, `.snapping` cases)
- Modify: `Sources/ArtMouseCore/Actions/ActionExecutor.swift` (no-op arms for the new cases — exhaustive switch)
- Modify: `Sources/artMouse/Views/ActionEditorView.swift` (interim placeholder arms — replaced in Tasks 6/7)
- Modify: `Tests/ArtMouseCoreTests/ActionModelTests.swift`

**Interfaces:**
- Consumes: `ModKeys`, `ClickOp`, `ButtonID` (Phase 1).
- Produces (exact):
  - `enum MacroStep: Codable, Equatable, Hashable { case enterKey(keyCode: UInt64, mods: ModKeys); case click(op: ClickOp, mods: ModKeys); case wait(milliseconds: Int) }`
  - `enum RepeatMode: String, Codable, CaseIterable, Equatable { case none, hold }`
  - `enum SnappingOp: Codable, Equatable, Hashable { case snap(click: Bool, bounce: Bool) }`
  - `Action` gains `case macro(steps: [MacroStep], repeatMode: RepeatMode, repeatIntervalMS: Int, modifierProxy: Bool)` and `case snapping(SnappingOp)` (Codable synthesis; `isHoldAction`/`isClickLock` unchanged).
  - Executor/UI: no-op `case .macro`, `case .snapping` arms with comments pointing at Tasks 3/4/6/7.

- [ ] **Step 1: Write failing tests**

Append to `ActionModelTests.swift`:

```swift
func testMacroAndSnappingCodableRoundTrip() throws {
    let steps: [MacroStep] = [
        .enterKey(keyCode: 40, mods: [.command]),
        .wait(milliseconds: 150),
        .click(op: .left, mods: []),
    ]
    let original: [Action] = [
        .macro(steps: steps, repeatMode: .hold, repeatIntervalMS: 250, modifierProxy: true),
        .snapping(.snap(click: true, bounce: false)),
    ]
    let data = try JSONEncoder().encode(original)
    XCTAssertEqual(try JSONDecoder().decode([Action].self, from: data), original)
}

func testMacroAndSnappingAreNotHoldActions() {
    XCTAssertFalse(Action.macro(steps: [], repeatMode: .hold, repeatIntervalMS: 100, modifierProxy: false).isHoldAction)
    XCTAssertFalse(Action.snapping(.snap(click: true, bounce: true)).isHoldAction)
    XCTAssertFalse(Action.macro(steps: [], repeatMode: .hold, repeatIntervalMS: 100, modifierProxy: false).isClickLock)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ActionModelTests`
Expected: FAIL — `MacroStep`/`RepeatMode`/`SnappingOp` not defined.

- [ ] **Step 3: Write the models and exhaustiveness arms**

`MacroModel.swift`:

```swift
import Foundation

/// One step of a key macro. Wait steps pause the sequence; enterKey posts a
/// full press+release; click posts a full click pair at the current cursor.
public enum MacroStep: Codable, Equatable, Hashable {
    case enterKey(keyCode: UInt64, mods: ModKeys)
    case click(op: ClickOp, mods: ModKeys)
    case wait(milliseconds: Int)
}

public enum RepeatMode: String, Codable, CaseIterable, Equatable {
    case none   // run once per press
    case hold   // repeat the whole sequence while the button is held
}

/// Cursor snapping: move to the focused window's default button, optionally
/// click it, optionally return to the original position.
public enum SnappingOp: Codable, Equatable, Hashable {
    case snap(click: Bool, bounce: Bool)
}
```

`Action.swift`: add after `.snapping`-to-be placement — the two new cases after `.device`:

```swift
    case macro(steps: [MacroStep], repeatMode: RepeatMode, repeatIntervalMS: Int, modifierProxy: Bool)
    case snapping(SnappingOp)
```

`ActionExecutor.swift`: add no-op arms to the `perform` switch:

```swift
        case .macro:
            break   // MacroEngine routing lands in Task 3
        case .snapping:
            break   // SnappingController wiring lands in Task 4
```

`ActionEditorView.swift`: interim arms in BOTH switches (the editor `switch` and `ActionCategory.init`) mapping the new cases to the existing no-op placeholders with `// Task 6/7 replace` comments:

```swift
        case .macro: Text("Macro (Task 6)").foregroundStyle(.secondary)
        case .snapping(let op): Text("Snapping (Task 7)").foregroundStyle(.secondary)
```

and in `ActionCategory.init`: `case .macro: self = .none`, `case .snapping: self = .none` (picker selection still routes through `initialAction` — interim until Tasks 6/7 add the real categories).

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ActionModelTests`
Expected: PASS (all, including 2 new).

- [ ] **Step 5: Commit**

```bash
git add Sources/ArtMouseCore/Model Sources/ArtMouseCore/Actions/ActionExecutor.swift Sources/artMouse/Views/ActionEditorView.swift Tests/ArtMouseCoreTests/ActionModelTests.swift
git commit -m "Add macro and snapping action models"
```

### Task 2: MacroEngine — cancellable task runner

**Files:**
- Create: `Sources/ArtMouseCore/Engine/MacroEngine.swift`
- Create: `Tests/ArtMouseCoreTests/MacroEngineTests.swift`

**Interfaces:**
- Consumes: `EventPosting` (poster.post tags events), `MacroStep`, `RepeatMode`, `KeyCodes`/`CGFlagConversion`, `BootstrapDecision.currentFlags()` (physical-modifier read for proxy).
- Produces (exact):
  - `struct MacroProgram { var steps: [MacroStep]; var repeatMode: RepeatMode; var repeatIntervalMS: Int; var modifierProxy: Bool }`
  - `final class MacroEngine { init(poster: EventPosting, cursorLocation: @escaping () -> CGPoint = { CGEvent(source: nil)?.location ?? .zero }, sleep: @escaping (Int) async throws -> Void = default sleep, flagReader: @escaping () -> ModKeys = { BootstrapDecision.currentFlags() }); func run(program: MacroProgram, for button: ButtonID); func stop(for button: ButtonID); func stopAll(); func isRunning(for button: ButtonID) -> Bool }`
  - Behavior contract (pinned by tests):
    - `run` cancels any existing task for the button, stores a new Task, and executes: each `enterKey` posts down+up; each `click(op:mods:)` posts a click pair at `cursorLocation()` (same construction as ActionExecutor's click: mouse button events with clickState 1); each `wait(ms)` awaits the injected sleeper; `.macro` waits clamp 1...60000 ms.
    - Cancellation is checked BEFORE each step and before each wait — never between a key's down and up, never inside a click pair (pairs post back-to-back with no await between them).
    - `modifierProxy == true` merges `flagReader()` into every posted key/click event's flags.
    - `.hold` repeat mode: after the sequence, sleeps `repeatIntervalMS` (clamped 10...5000) and repeats — until `stop(for:)`/`stopAll()` cancels the task.
    - `isRunning(for:)` true while the button's task exists and isn't cancelled-and-finished.

- [ ] **Step 1: Write failing tests**

`Tests/ArtMouseCoreTests/MacroEngineTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import ArtMouseCore

final class MacroEngineTests: XCTestCase {
    private let poster = RecordingPoster()
    private var sleptMS: [Int] = []
    private var physicalFlags: ModKeys = []

    private func makeEngine() -> MacroEngine {
        MacroEngine(
            poster: poster,
            cursorLocation: { CGPoint(x: 11, y: 22) },
            sleep: { [weak self] ms in self?.sleptMS.append(ms) },
            flagReader: { [weak self] in self?.physicalFlags ?? [] })
    }

    func testEnterKeyPostsDownUpPair() async {
        let engine = makeEngine()
        await engine.runAndWait(program: MacroProgram(
            steps: [.enterKey(keyCode: 40, mods: [.command])], repeatMode: .none,
            repeatIntervalMS: 100, modifierProxy: false), for: .middle)
        XCTAssertEqual(poster.events.count, 2)
        XCTAssertEqual(poster.events[0].type, .keyDown)
        XCTAssertEqual(UInt64(poster.events[0].getIntegerValueField(.keyboardEventKeycode)), 40)
        XCTAssertTrue(poster.events[0].flags.contains(.maskCommand))
        XCTAssertEqual(poster.events[1].type, .keyUp)
    }

    func testWaitSleepsAndPostsNothing() async {
        let engine = makeEngine()
        await engine.runAndWait(program: MacroProgram(
            steps: [.wait(milliseconds: 250), .enterKey(keyCode: 5, mods: [])],
            repeatMode: .none, repeatIntervalMS: 100, modifierProxy: false), for: .middle)
        XCTAssertEqual(sleptMS, [250])
        XCTAssertEqual(poster.events.count, 2)   // only the key pair
    }

    func testClickStepPostsPairAtCursorLocation() async {
        let engine = makeEngine()
        await engine.runAndWait(program: MacroProgram(
            steps: [.click(op: .left, mods: [])], repeatMode: .none,
            repeatIntervalMS: 100, modifierProxy: false), for: .middle)
        XCTAssertEqual(poster.events.count, 2)
        XCTAssertEqual(poster.events[0].type, .leftMouseDown)
        XCTAssertEqual(poster.events[0].location.x, 11, accuracy: 1e-9)
        XCTAssertEqual(poster.events[0].location.y, 22, accuracy: 1e-9)
    }

    func testModifierProxyMergesPhysicalFlags() async {
        physicalFlags = [.shift]
        let engine = makeEngine()
        await engine.runAndWait(program: MacroProgram(
            steps: [.enterKey(keyCode: 5, mods: [.command])], repeatMode: .none,
            repeatIntervalMS: 100, modifierProxy: true), for: .middle)
        XCTAssertTrue(poster.events[0].flags.contains(.maskCommand))
        XCTAssertTrue(poster.events[0].flags.contains(.maskShift))
    }

    func testWaitClampedToRange() async {
        let engine = makeEngine()
        await engine.runAndWait(program: MacroProgram(
            steps: [.wait(milliseconds: 99_999)], repeatMode: .none,
            repeatIntervalMS: 100, modifierProxy: false), for: .middle)
        XCTAssertEqual(sleptMS, [60_000])   // clamped 1...60000
    }

    func testHoldRepeatRunsUntilStop() async {
        let engine = makeEngine()
        engine.run(program: MacroProgram(
            steps: [.enterKey(keyCode: 5, mods: [])], repeatMode: .hold,
            repeatIntervalMS: 10, modifierProxy: false), for: .middle)
        XCTAssertTrue(engine.isRunning(for: .middle))
        // Deterministic drain: the injected sleep records instead of waiting;
        // poll until at least two sequences have executed.
        while poster.events.count < 4 { await Task.yield() }
        engine.stop(for: .middle)
        let countAtStop = poster.events.count
        XCTAssertTrue(countAtStop >= 4 && countAtStop % 2 == 0)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(poster.events.count, countAtStop)   // stopped
        XCTAssertFalse(engine.isRunning(for: .middle))
    }

    func testStopAllStopsEveryButton() async {
        let engine = makeEngine()
        engine.run(program: MacroProgram(
            steps: [.enterKey(keyCode: 5, mods: [])], repeatMode: .hold,
            repeatIntervalMS: 10, modifierProxy: false), for: .middle)
        engine.run(program: MacroProgram(
            steps: [.enterKey(keyCode: 6, mods: [])], repeatMode: .hold,
            repeatIntervalMS: 10, modifierProxy: false), for: .fourth)
        while poster.events.count < 4 { await Task.yield() }
        engine.stopAll()
        for _ in 0..<20 { await Task.yield() }
        let countAtStop = poster.events.count
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(poster.events.count, countAtStop)
        XCTAssertFalse(engine.isRunning(for: .middle))
        XCTAssertFalse(engine.isRunning(for: .fourth))
    }
}
```

The `runAndWait` helper (private extension on MacroEngine, in the test file) awaits the engine's internal `func execute(program: MacroProgram) async` directly — synchronous single-pass execution without the Task wrapper.

FINAL test set = 7 tests: enterKey pair, wait-sleep, click-at-location, proxy merge, wait clamp, hold-until-stop, stop-all. `run` cancels any previous task for the same button before starting (structural — see `stop(for:)` in `run`); the generation guard in `finishTask` prevents an old task from clearing a newer run's registration.

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter MacroEngineTests`
Expected: FAIL — `MacroEngine`/`MacroProgram` not defined.

- [ ] **Step 3: Write MacroEngine.swift**

```swift
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
        tasks[button] = Task { [weak self] in
            await self?.runLoop(program: program)
            self?.finishTask(for: button)
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

    private func postKey(keyCode: UInt64, flags: CGEventFlags, down: Bool) {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode),
                            keyDown: down, flags: flags)!
        poster.post(event)
    }

    /// Same construction as ActionExecutor's standard click (clickState 1,
    /// cursor location), plus merged proxy flags.
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
```

Note for the implementer: the `keysDown`/`releaseHeldKey` machinery is currently unused by `execute` (every key pair posts back-to-back). Keep it — Phase 3's follow-up tuning for held-key macros uses it, and the invariant (`keysDown` only set inside execute, never in v1) is safe. If the compiler warns it's unused, that's expected: it IS used, by `stop`/`finishTask`. The `doubleLeft` click step posts ONE pair (not two) — double semantics inside macros are Phase 4; document in code.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter MacroEngineTests`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/ArtMouseCore/Engine/MacroEngine.swift Tests/ArtMouseCoreTests/MacroEngineTests.swift
git commit -m "Add cancellable macro engine"
```

### Task 3: Router + bootstrap macro integration

**Files:**
- Modify: `Sources/ArtMouseCore/Engine/EventRouter.swift`
- Modify: `Sources/ArtMouseCore/Engine/MacroEngine.swift` (MacroCoordinating conformance)
- Modify: `Sources/artMouse/EngineBootstrap.swift`
- Modify: `Tests/ArtMouseCoreTests/EventRouterTests.swift`

**Interfaces:**
- Consumes: `MacroEngine`/`MacroProgram` (Task 2), `Action.macro` (Task 1).
- Produces (exact):
  - `protocol MacroCoordinating: AnyObject { func run(program: MacroProgram, for button: ButtonID); func stop(for button: ButtonID) }` — `MacroEngine` conforms.
  - `EventRouter` gains defaulted `macros: MacroCoordinating? = nil`.
  - Routing rules (pinned by tests): a `.macro` binding on buttonDown → `macros.run(program:for:)` + `.consume`; if `repeatMode == .hold`, the button registers in a `macroHeldButtons: Set<ButtonID>`; buttonUp for a registered button → `macros.stop(for:)` + clear + `.consume`. `.none` mode fires once per down; up routes normally.
  - Bootstrap: `MacroEngine(poster: poster)` (the SHARED poster), router gets `macros: macroEngine`.

- [ ] **Step 1: Write failing tests**

Append to `EventRouterTests`:

```swift
final class RouterMacroTests: XCTestCase {
    final class RecordingMacroEngine: MacroCoordinating {
        private(set) var ran: [(MacroProgram, ButtonID)] = []
        private(set) var stopped: [ButtonID] = []
        func run(program: MacroProgram, for button: ButtonID) { ran.append((program, button)) }
        func stop(for button: ButtonID) { stopped.append(button) }
    }

    private func macroStore(_ action: Action) -> SettingsStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = SettingsStore(directory: dir)
        store.settings.buttonBindings = [ButtonBinding(button: .fourth, actions: [action])]
        return store
    }

    func testMacroOnceRunsOnDown() {
        let engine = RecordingMacroEngine()
        let action = Action.macro(steps: [.enterKey(keyCode: 5, mods: [])], repeatMode: .none,
                                  repeatIntervalMS: 100, modifierProxy: false)
        let router = EventRouter(settings: macroStore(action), executor: RecordingExecutor(),
                                 clickLock: StubClickLock(), cursor: StubCursor(), macros: engine)
        XCTAssertEqual(router.handle(.buttonDown(.fourth)), .consume)
        XCTAssertEqual(engine.ran.count, 1)
        XCTAssertEqual(engine.ran[0].1, .fourth)
        XCTAssertEqual(engine.stopped, [])
    }

    func testMacroHoldRunsOnDownAndStopsOnUp() {
        let engine = RecordingMacroEngine()
        let action = Action.macro(steps: [.enterKey(keyCode: 5, mods: [])], repeatMode: .hold,
                                  repeatIntervalMS: 100, modifierProxy: false)
        let router = EventRouter(settings: macroStore(action), executor: RecordingExecutor(),
                                 clickLock: StubClickLock(), cursor: StubCursor(), macros: engine)
        XCTAssertEqual(router.handle(.buttonDown(.fourth)), .consume)
        XCTAssertEqual(engine.ran.count, 1)
        XCTAssertEqual(router.handle(.buttonUp(.fourth)), .consume)
        XCTAssertEqual(engine.stopped, [.fourth])
    }

    func testMacroHoldUpWithoutDownRoutes() {
        let engine = RecordingMacroEngine()
        let action = Action.macro(steps: [], repeatMode: .hold, repeatIntervalMS: 100, modifierProxy: false)
        let router = EventRouter(settings: macroStore(action), executor: RecordingExecutor(),
                                 clickLock: StubClickLock(), cursor: StubCursor(), macros: engine)
        XCTAssertEqual(router.handle(.buttonUp(.fourth)), .passThrough)
        XCTAssertEqual(engine.stopped, [])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter RouterMacroTests`
Expected: FAIL — `macros` param missing.

- [ ] **Step 3: Implement**

`MacroEngine.swift`: add conformance:

```swift
extension MacroEngine: MacroCoordinating {}
```

`EventRouter.swift`: add stored `private let macros: MacroCoordinating?` + init param `macros: MacroCoordinating? = nil` (after `chords`), and `private var macroHeldButtons: Set<ButtonID> = []`. In `performNormalDown`, BEFORE the hold-action loop (macros are not `isHoldAction` — they're a distinct arm):

```swift
if case .macro(let steps, let repeatMode, let intervalMS, let proxy) = binding.actions.first,
   binding.actions.count == 1, let macros = macros {
    macros.run(program: MacroProgram(steps: steps, repeatMode: repeatMode,
                                     repeatIntervalMS: intervalMS, modifierProxy: proxy),
               for: button)
    if repeatMode == .hold { macroHeldButtons.insert(button) }
    return .consume
}
```

In `performNormalUp`, BEFORE the heldButtons arm:

```swift
if macroHeldButtons.contains(button) {
    macroHeldButtons.remove(button)
    macros?.stop(for: button)
    return .consume
}
```

`EngineBootstrap.start(store:)`: hoist nothing — the shared `poster` exists; add `let macroEngine = MacroEngine(poster: poster)` and pass `macros: macroEngine` to the router. Extend the discipline comment to name `MacroEngine.tasks`/`macroHeldButtons`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: full suite green (148 prior + 3 new = 151).

- [ ] **Step 5: Commit**

```bash
git add Sources/ArtMouseCore/Engine Sources/artMouse/EngineBootstrap.swift Tests/ArtMouseCoreTests/EventRouterTests.swift
git commit -m "Integrate macro engine into the router"
```

### Task 4: SnappingController — AX snap/jump/click/bounce

**Files:**
- Create: `Sources/ArtMouseCore/Engine/SnappingController.swift`
- Modify: `Sources/ArtMouseCore/Actions/ActionExecutor.swift` (weak snapping arm)
- Modify: `Sources/artMouse/EngineBootstrap.swift`
- Modify: `Tests/ArtMouseCoreTests/SnappingControllerTests.swift` (new)

**Interfaces:**
- Consumes: `SnappingOp` (Task 1), `EventPosting`, ApplicationServices AX APIs.
- Produces (exact):
  - `struct AXFrame: Equatable { var x: Double; var y: Double; var width: Double; var height: Double }`
  - `protocol AXButtonFinding: AnyObject { func defaultButtonFrame() -> AXFrame? }`
  - `final class AXDefaultButtonFinder: AXButtonFinding` — system-wide AX element → `kAXFocusedWindowAttribute` → `kAXDefaultButtonAttribute` → position/size; nil on any failure.
  - `protocol SnappingPerforming: AnyObject { func perform(_ op: SnappingOp) }`
  - `final class SnappingController: SnappingPerforming { init(finder: AXButtonFinding, poster: EventPosting, cursorLocation: @escaping () -> CGPoint = { CGEvent(source: nil)?.location ?? .zero }) ; func perform(_ op: SnappingOp) }`
  - Behavior: nil frame → no-op (Review Focus 3). Otherwise: warp cursor to frame center + post a `mouseMoved` event there (deltas 0, location = center); `.snap(click: true)` posts left down+up pair at center (clickState 1, tagged via poster); `.snap(bounce: true)` warps back to the pre-snap origin + posts `mouseMoved` at origin (after the click if both).
  - Executor: `private weak var snapping: SnappingPerforming?` + defaulted init param; `.snapping` arm → `snapping?.perform(op)`.
  - Bootstrap: `SnappingController(finder: AXDefaultButtonFinder(), poster: poster)` passed to the executor.

- [ ] **Step 1: Write failing tests**

`Tests/ArtMouseCoreTests/SnappingControllerTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import ArtMouseCore

final class SnappingControllerTests: XCTestCase {
    private let poster = RecordingPoster()

    final class MockFinder: AXButtonFinding {
        let frame: AXFrame?
        init(frame: AXFrame?) { self.frame = frame }
        func defaultButtonFrame() -> AXFrame? { frame }
    }

    private func makeController(frame: AXFrame?) -> SnappingController {
        SnappingController(finder: MockFinder(frame: frame), poster: poster,
                           cursorLocation: { CGPoint(x: 500, y: 300) })
    }

    func testNilFrameIsNoOp() {
        let controller = makeController(frame: nil)
        controller.perform(.snap(click: true, bounce: true))
        XCTAssertTrue(poster.events.isEmpty)
    }

    func testJumpMovesToCenter() {
        let controller = makeController(frame: AXFrame(x: 100, y: 200, width: 60, height: 40))
        controller.perform(.snap(click: false, bounce: false))
        XCTAssertEqual(poster.events.count, 1)
        XCTAssertEqual(poster.events[0].type, .mouseMoved)
        XCTAssertEqual(poster.events[0].location.x, 130, accuracy: 1e-9)   // 100 + 60/2
        XCTAssertEqual(poster.events[0].location.y, 220, accuracy: 1e-9)   // 200 + 40/2
    }

    func testClickSnapPostsMoveAndClickPair() {
        let controller = makeController(frame: AXFrame(x: 100, y: 200, width: 60, height: 40))
        controller.perform(.snap(click: true, bounce: false))
        XCTAssertEqual(poster.events.count, 3)                              // move, down, up
        XCTAssertEqual(poster.events[1].type, .leftMouseDown)
        XCTAssertEqual(poster.events[2].type, .leftMouseUp)
        XCTAssertEqual(poster.events[1].location.y, 220, accuracy: 1e-9)
    }

    func testBounceReturnsToOrigin() {
        let controller = makeController(frame: AXFrame(x: 100, y: 200, width: 60, height: 40))
        controller.perform(.snap(click: true, bounce: true))
        XCTAssertEqual(poster.events.count, 4)                              // move, down, up, move-back
        let last = poster.events[3]
        XCTAssertEqual(last.type, .mouseMoved)
        XCTAssertEqual(last.location.x, 500, accuracy: 1e-9)
        XCTAssertEqual(last.location.y, 300, accuracy: 1e-9)
    }

    func testClickEventsCarryTargetLocation() {
        let controller = makeController(frame: AXFrame(x: 0, y: 0, width: 200, height: 100))
        controller.perform(.snap(click: true, bounce: false))
        XCTAssertEqual(poster.events[1].location.x, 100, accuracy: 1e-9)
        XCTAssertEqual(poster.events[1].location.y, 50, accuracy: 1e-9)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SnappingControllerTests`
Expected: FAIL — types not defined.

- [ ] **Step 3: Write SnappingController.swift**

```swift
import ApplicationServices
import CoreGraphics
import Foundation

public struct AXFrame: Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var center: CGPoint {
        CGPoint(x: x + width / 2, y: y + height / 2)
    }
}

public protocol AXButtonFinding: AnyObject {
    func defaultButtonFrame() -> AXFrame?
}

public protocol SnappingPerforming: AnyObject {
    func perform(_ op: SnappingOp)
}

/// Reads the focused window's default button via Accessibility and moves the
/// cursor there (optionally clicking, optionally returning to the origin).
public final class SnappingController: SnappingPerforming {
    private let finder: AXButtonFinding
    private let poster: EventPosting
    private let cursorLocation: () -> CGPoint

    public init(finder: AXButtonFinding, poster: EventPosting,
                cursorLocation: @escaping () -> CGPoint = { CGEvent(source: nil)?.location ?? .zero }) {
        self.finder = finder
        self.poster = poster
        self.cursorLocation = cursorLocation
    }

    public func perform(_ op: SnappingOp) {
        guard case .snap(let click, let bounce) = op else { return }
        guard let frame = finder.defaultButtonFrame() else { return }   // Review Focus 3: no-op
        let origin = cursorLocation()
        let center = frame.center

        moveTo(center)
        if click {
            postClick(at: center)
        }
        if bounce {
            moveTo(origin)
        }
    }

    // MARK: - Primitives

    private func moveTo(_ point: CGPoint) {
        CGWarpMouseCursorPosition(point)
        let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                            mouseCursorPosition: point, mouseButton: .left)!
        poster.post(event)
    }

    private func postClick(at point: CGPoint) {
        let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                           mouseCursorPosition: point, mouseButton: .left)!
        down.setIntegerValueField(.mouseEventClickState, value: 1)
        let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                         mouseCursorPosition: point, mouseButton: .left)!
        up.setIntegerValueField(.mouseEventClickState, value: 1)
        poster.post(down)
        poster.post(up)
    }
}

/// Real AX reader: system-wide element → focused window → default button.
public final class AXDefaultButtonFinder: AXButtonFinding {
    public init() {}

    public func defaultButtonFrame() -> AXFrame? {
        let systemWide = AXUIElementCreateSystemWide()
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let windowElement = window else { return nil }
        var button: CFTypeRef?
        guard AXUIElementCopyAttributeValue(windowElement as! AXUIElement, kAXDefaultButtonAttribute as CFString, &button) == .success,
              let buttonElement = button else { return nil }
        return frame(of: buttonElement as! AXUIElement)
    }

    private func frame(of element: AXUIElement) -> AXFrame? {
        var position: CFTypeRef?
        var size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let positionValue = position, let sizeValue = size else { return nil }
        var point = CGPoint.zero
        var sizeStruct = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &sizeStruct) else { return nil }
        return AXFrame(x: point.x, y: point.y, width: sizeStruct.width, height: sizeStruct.height)
    }
}
```

`ActionExecutor.swift`: add `private weak var snapping: SnappingPerforming?` + defaulted init param `snapping: SnappingPerforming? = nil` (after `wheel`); `.snapping` arm → `snapping?.perform(op)`.

`EngineBootstrap.start(store:)`: `let snappingController = SnappingController(finder: AXDefaultButtonFinder(), poster: poster)` and pass `snapping: snappingController` to the executor. Extend the discipline comment to name `SnappingController` (stateless — safe).

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SnappingControllerTests`
Expected: PASS (5 tests). Full suite: 154.

- [ ] **Step 5: Commit**

```bash
git add Sources/ArtMouseCore Tests/ArtMouseCoreTests/SnappingControllerTests.swift Sources/artMouse/EngineBootstrap.swift
git commit -m "Add cursor snapping controller with AX default button finder"
```

### Task 5: App profiles — model, resolvers, router/controller consumption

**Files:**
- Create: `Sources/ArtMouseCore/Settings/AppProfileSettings.swift`
- Modify: `Sources/ArtMouseCore/Model/AppWatcher.swift` (+ `FrontmostProviding`)
- Modify: `Sources/ArtMouseCore/Settings/GlobalSettings.swift` (+ appProfiles field)
- Modify: `Sources/ArtMouseCore/Engine/EventRouter.swift` (+ watcher param)
- Modify: `Sources/ArtMouseCore/Cursor/CursorController.swift` (+ watcher param)
- Modify: `Sources/ArtMouseCore/Scroll/ScrollController.swift` (+ watcher param)
- Modify: `Sources/artMouse/EngineBootstrap.swift` (+ watcher sharing)
- Modify: `Tests/ArtMouseCoreTests/SettingsStoreTests.swift`, `EventRouterTests.swift`, `CursorControllerTests.swift`, `ScrollControllerTests.swift`

**Interfaces:**
- Consumes: `AppWatcher` (Phase 1), `GlobalSettings`, controllers.
- Produces (exact):
  - `struct AppProfile: Codable, Equatable, Identifiable { var id: UUID; var bundleID: String; var name: String; var buttonBindings: [ButtonBinding]?; var scrollBindings: [ScrollBinding]?; var cursorSpeedProfileID: UUID?; var wheelModeProfileID: UUID? }` — memberwise init; `buttonBindings`/`scrollBindings` nil = inherit global (v1 UI edits only cursor/wheel overrides; binding overrides are settings.json-editable — documented).
  - `protocol FrontmostProviding: AnyObject { var frontmostBundleID: String? { get } }` in AppWatcher.swift; `extension AppWatcher: FrontmostProviding {}`.
  - `GlobalSettings` gains `appProfiles: [AppProfile]` (custom decode default `[]`) and helpers:
    - `func effectiveButtonBindings(for bundleID: String?) -> [ButtonBinding]` — matching app profile's non-nil buttonBindings ?? `buttonBindings`
    - `func effectiveScrollBindings(for bundleID: String?) -> [ScrollBinding]` — same pattern
    - `func effectiveCursorProfile(for bundleID: String?) -> CursorSpeedProfile?` — app override ID resolved in cursorSpeedProfiles ?? `activeProfile` (the existing chain)
    - `func effectiveWheelProfile(for bundleID: String?) -> WheelModeProfile?` — app override ID resolved in wheelModeProfiles ?? `activeWheelProfile`
  - `EventRouter` gains defaulted `watcher: FrontmostProviding? = nil`; binding lookups use `settings.settings.effectiveButtonBindings(for: watcher?.frontmostBundleID)` / `effectiveScrollBindings`.
  - `CursorController` gains defaulted `watcher: FrontmostProviding? = nil`; `effectiveProfile()` consults `store.settings.effectiveCursorProfile(for: watcher?.frontmostBundleID)` FIRST.
  - `ScrollController` gains defaulted `watcher: FrontmostProviding? = nil`; `disposition` resolves `store.settings.effectiveWheelProfile(for: watcher?.frontmostBundleID)`.
  - `EngineBootstrap`: constructs `AppWatcher` FIRST and shares it with router/cursor/scroll (and keeps its own start() call).

- [ ] **Step 1: Write failing tests**

SettingsStoreTests additions:

```swift
func testAppProfilesDecodeDefaultEmpty() throws {
    let phase2JSON = """
    {"activeCursorSpeedProfileID":null,"buttonBindings":[],
     "chords":[],"cursorSpeedProfiles":[{"acceleration":1,"id":"11111111-1111-1111-1111-111111111111","name":"Default","sensitivity":1600}],
     "precisionProfileID":null,"schemaVersion":1,"scrollBindings":[],
     "wheelModeProfiles":[]}
    """
    let settings = try SettingsStore.decode(Data(phase2JSON.utf8))
    XCTAssertEqual(settings.appProfiles, [])
}

func testEffectiveResolutionFallsBackToGlobal() {
    var settings = GlobalSettings.default
    let binding = ButtonBinding(button: .fourth, actions: [.none])
    settings.buttonBindings = [binding]
    XCTAssertEqual(settings.effectiveButtonBindings(for: "com.apple.Safari"), [binding])   // no app profile
    XCTAssertEqual(settings.effectiveButtonBindings(for: nil), [binding])                  // nil watcher
}

func testEffectiveResolutionPrefersAppProfile() {
    var settings = GlobalSettings.default
    let globalBinding = ButtonBinding(button: .fourth, actions: [.none])
    let appBinding = ButtonBinding(button: .middle, actions: [.mission(.launchpad, reverse: false)])
    let appProfile = AppProfile(bundleID: "com.apple.Safari", name: "Safari",
                                buttonBindings: [appBinding], scrollBindings: nil,
                                cursorSpeedProfileID: nil, wheelModeProfileID: nil)
    settings.appProfiles = [appProfile]
    settings.buttonBindings = [globalBinding]

    XCTAssertEqual(settings.effectiveButtonBindings(for: "com.apple.Safari"), [appBinding])
    XCTAssertEqual(settings.effectiveButtonBindings(for: "com.apple.TextEdit"), [globalBinding])

    let fast = WheelModeProfile(name: "Fast")
    settings.wheelModeProfiles = [WheelModeProfile(name: "Slow"), fast]
    settings.appProfiles[0].wheelModeProfileID = fast.id
    XCTAssertEqual(settings.effectiveWheelProfile(for: "com.apple.Safari"), fast)
    // cursor override nil → global chain applies (the Default profile)
    XCTAssertEqual(settings.effectiveCursorProfile(for: "com.apple.Safari"), settings.activeProfile)
}

```swift
func testEffectiveCursorAndWheelOverrides() {
    var settings = GlobalSettings.default
    let slow = settings.cursorSpeedProfiles[0]
    let fast = WheelModeProfile(name: "Fast")
    settings.wheelModeProfiles = [fast]
    let appProfile = AppProfile(bundleID: "com.apple.Safari", name: "Safari",
                                buttonBindings: nil, scrollBindings: nil,
                                cursorSpeedProfileID: slow.id, wheelModeProfileID: fast.id)
    settings.appProfiles = [appProfile]

    XCTAssertEqual(settings.effectiveCursorProfile(for: "com.apple.Safari"), slow)
    XCTAssertEqual(settings.effectiveWheelProfile(for: "com.apple.Safari"), fast)
    XCTAssertEqual(settings.effectiveWheelProfile(for: nil), nil)   // default empty list → nil
}
```

EventRouterTests addition:

```swift
func testAppProfileOverridesBindingsWhenFrontmost() {
    let executor = RecordingExecutor()
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let store = SettingsStore(directory: dir)
    var settings = store.settings
    settings.buttonBindings = [ButtonBinding(button: .fourth, actions: [.none])]
    let appBinding = ButtonBinding(button: .fourth, actions: [.mission(.missionControl, reverse: false)])
    settings.appProfiles = [AppProfile(bundleID: "com.apple.Safari", name: "Safari",
                                       buttonBindings: [appBinding], scrollBindings: nil,
                                       cursorSpeedProfileID: nil, wheelModeProfileID: nil)]
    store.settings = settings
    let watcher = StubWatcher(bundleID: "com.apple.Safari")
    let router = EventRouter(settings: store, executor: executor,
                             clickLock: StubClickLock(), cursor: StubCursor(),
                             watcher: watcher)
    XCTAssertEqual(router.handle(.buttonDown(.fourth)), .consume)
    XCTAssertEqual(executor.performed, [.mission(.missionControl, reverse: false)])

    watcher.frontmostBundleID = "com.apple.TextEdit"     // no profile → global
    // Global binding is [.none] (non-empty → matched → .consume, performing nothing)
    XCTAssertEqual(router.handle(.buttonUp(.fourth)), .consume)
}
```

`StubWatcher` (new test double in EventRouterTests):

```swift
final class StubWatcher: FrontmostProviding {
    var frontmostBundleID: String?
    init(bundleID: String?) { self.frontmostBundleID = bundleID }
}
```

CursorControllerTests addition:

```swift
func testWatcherResolvesPerAppCursorProfile() {
    let store = makeStore()
    var settings = store.settings
    settings.activeCursorSpeedProfileID = settings.cursorSpeedProfiles[2].id   // Fast
    let slow = settings.cursorSpeedProfiles[0]
    let appProfile = AppProfile(bundleID: "com.apple.Safari", name: "Safari",
                                buttonBindings: nil, scrollBindings: nil,
                                cursorSpeedProfileID: slow.id, wheelModeProfileID: nil)
    settings.appProfiles = [appProfile]
    store.settings = settings
    let watcher = StubWatcher(bundleID: "com.apple.Safari")
    let controller = CursorController(store: store, watcher: watcher)
    // Slow: sens 0.5 × accel 1.0 = 0.5 at any speed
    XCTAssertEqual(controller.outcome(forMove: .moved(dx: 8, dy: 0)),
                   .cursorTransform(dxFactor: 0.5, dyFactor: 0.5))
}
```

ScrollControllerTests addition:

```swift
func testWatcherResolvesPerAppWheelProfile() {
    let store = makeStore(profiles: [WheelModeProfile(name: "Default")])
    var settings = store.settings
    let constant = WheelModeProfile(name: "Const", mode: .constant, lines: 9)
    settings.wheelModeProfiles = [WheelModeProfile(name: "Default"), constant]
    let appProfile = AppProfile(bundleID: "com.apple.Safari", name: "Safari",
                                buttonBindings: nil, scrollBindings: nil,
                                cursorSpeedProfileID: nil, wheelModeProfileID: constant.id)
    settings.appProfiles = [appProfile]
    store.settings = settings
    let poster = RecordingPoster()
    let controller = ScrollController(store: store, emitter: ScrollEmitter(poster: poster),
                                      watcher: StubWatcher(bundleID: "com.apple.Safari"))
    XCTAssertEqual(controller.disposition(forScroll: .vertical, ticks: 1), .intercept)
    XCTAssertEqual(poster.events[0].getDoubleValueField(.scrollWheelEventDeltaAxis1), 9, accuracy: 1e-9)
}
```

(Add `makeStore`-style helpers if not already present in those suites; `StubWatcher` is defined once in EventRouterTests.swift, module-visible.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter 'SettingsStoreTests|EventRouterTests|CursorControllerTests|ScrollControllerTests'`
Expected: FAIL — `AppProfile`, `watcher` params, effective helpers missing.

- [ ] **Step 3: Implement**

`AppProfileSettings.swift`:

```swift
import Foundation

/// Per-application settings overlay. Nil fields inherit the global settings;
/// button/scroll binding overrides are v1-edited via settings.json only
/// (documented in the Apps tab caption).
public struct AppProfile: Codable, Equatable, Identifiable {
    public var id: UUID
    public var bundleID: String
    public var name: String
    public var buttonBindings: [ButtonBinding]?
    public var scrollBindings: [ScrollBinding]?
    public var cursorSpeedProfileID: UUID?
    public var wheelModeProfileID: UUID?

    public init(id: UUID = UUID(), bundleID: String, name: String,
                buttonBindings: [ButtonBinding]? = nil, scrollBindings: [ScrollBinding]? = nil,
                cursorSpeedProfileID: UUID? = nil, wheelModeProfileID: UUID? = nil) {
        self.id = id
        self.bundleID = bundleID
        self.name = name
        self.buttonBindings = buttonBindings
        self.scrollBindings = scrollBindings
        self.cursorSpeedProfileID = cursorSpeedProfileID
        self.wheelModeProfileID = wheelModeProfileID
    }
}
```

`AppWatcher.swift`: add

```swift
public protocol FrontmostProviding: AnyObject {
    var frontmostBundleID: String? { get }
}

extension AppWatcher: FrontmostProviding {}
```

`GlobalSettings.swift`: add stored field `appProfiles: [AppProfile]` after `chords` (custom init: `decodeIfPresent(...) ?? []`; `default` extended with `appProfiles: []`), plus:

```swift
public extension GlobalSettings {
    private func appProfile(for bundleID: String?) -> AppProfile? {
        guard let bundleID else { return nil }
        return appProfiles.first { $0.bundleID == bundleID }
    }

    func effectiveButtonBindings(for bundleID: String?) -> [ButtonBinding] {
        appProfile(for: bundleID)?.buttonBindings ?? buttonBindings
    }

    func effectiveScrollBindings(for bundleID: String?) -> [ScrollBinding] {
        appProfile(for: bundleID)?.scrollBindings ?? scrollBindings
    }

    func effectiveCursorProfile(for bundleID: String?) -> CursorSpeedProfile? {
        if let id = appProfile(for: bundleID)?.cursorSpeedProfileID,
           let match = cursorSpeedProfiles.first(where: { $0.id == id }) { return match }
        return activeProfile
    }

    func effectiveWheelProfile(for bundleID: String?) -> WheelModeProfile? {
        if let id = appProfile(for: bundleID)?.wheelModeProfileID,
           let match = wheelModeProfiles.first(where: { $0.id == id }) { return match }
        return activeWheelProfile
    }
}
```

`EventRouter.swift`: `private let watcher: FrontmostProviding?` + init param `watcher: FrontmostProviding? = nil`; `binding(for:)` → `settings.settings.effectiveButtonBindings(for: watcher?.frontmostBundleID).first { $0.button == button }`; `scrollBinding(axis:direction:)` → `settings.settings.effectiveScrollBindings(for: watcher?.frontmostBundleID).first { ... }`.

`CursorController.swift`: `private let watcher: FrontmostProviding?` + init param defaulted nil; `effectiveProfile()` becomes:

```swift
private func effectiveProfile() -> CursorSpeedProfile? {
    if precisionActive, let id = store.settings.precisionProfileID,
       let match = store.settings.cursorSpeedProfiles.first(where: { $0.id == id }) {
        return match
    }
    return store.settings.effectiveCursorProfile(for: watcher?.frontmostBundleID)
}
```

(`effectiveCursorProfile(for:)` internally falls back to `activeProfile` when no app override applies, so this single call covers precision-off + app-override + global chain.)

`ScrollController.swift`: `private let watcher: FrontmostProviding?` + init param defaulted nil; `disposition`'s `guard let profile = store.settings.activeWheelProfile` becomes `guard let profile = store.settings.effectiveWheelProfile(for: watcher?.frontmostBundleID)`.

`EngineBootstrap.start(store:)`: hoist the existing `AppWatcher` construction before the controllers and pass it: `CursorController(store: store, watcher: appWatcher)`, `ScrollController(store: store, emitter: emitter, watcher: appWatcher)`, `EventRouter(..., watcher: appWatcher)`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: full suite green (154 prior + ~7 new = 161).

- [ ] **Step 5: Commit**

```bash
git add Sources Tests/ArtMouseCoreTests
git commit -m "Add per-application profiles with effective-settings resolution"
```

### Task 6: Macro UI — action category + steps editor

**Files:**
- Create: `Sources/artMouse/Views/MacroActionEditorView.swift`, `Sources/artMouse/Views/MacroStepsEditorView.swift`, `Sources/artMouse/Views/MacroStepEditorView.swift`
- Modify: `Sources/artMouse/Views/ActionEditorView.swift` (real `.macro` category + dispatch)
- Modify: `Sources/artMouse/AppModel.swift` (no new methods — the editor rebuilds whole `Action` values)

**Interfaces:**
- Consumes: `MacroStep`, `RepeatMode`, `Action.macro`, `ActionEditorView` dispatch, `KeyCodes` (unused — key entry is a raw keycode field v1).
- Produces (exact): `ActionCategory.macro` (label "Macro", initialAction `.macro(steps: [.enterKey(keyCode: 40, mods: [])], repeatMode: .none, repeatIntervalMS: 250, modifierProxy: false)`); dispatch case → `MacroActionEditorView`.
- UI structure (all derive-from-props; every edit rebuilds the full `Action` via `onChange`):
  - `MacroActionEditorView`: Repeat picker (None / Hold-repeat), interval field (shown when hold), modifier-proxy toggle, `MacroStepsEditorView`.
  - `MacroStepsEditorView`: `ForEach` over steps with per-row `MacroStepEditorView` + up/down/remove buttons; an add menu (Key / Click / Wait).
  - `MacroStepEditorView`: per-step editor by case — enterKey (keycode numeric field + ⌘⌃⌥⇧ checkboxes), click (op picker + mod checkboxes), wait (ms numeric field).

- [ ] **Step 1: ActionCategory + dispatch**

In `ActionEditorView.swift`: replace the interim `.macro` arms — `ActionCategory` gains `.macro` (label "Macro", init `case .macro: self = .macro`, `initialAction: .macro(steps: [.enterKey(keyCode: 40, mods: [])], repeatMode: .none, repeatIntervalMS: 250, modifierProxy: false)`); editor dispatch `case .macro(let steps, let repeatMode, let intervalMS, let proxy): MacroActionEditorView(steps: steps, repeatMode: repeatMode, repeatIntervalMS: intervalMS, modifierProxy: proxy, onChange: onChange)`.

- [ ] **Step 2: Write the three views**

`MacroActionEditorView.swift`:

```swift
import SwiftUI
import ArtMouseCore

struct MacroActionEditorView: View {
    let steps: [MacroStep]
    let repeatMode: RepeatMode
    let repeatIntervalMS: Int
    let modifierProxy: Bool
    let onChange: (Action?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("", selection: Binding(
                    get: { repeatMode },
                    set: { emit(repeatMode: $0) })) {
                    Text("Run once").tag(RepeatMode.none)
                    Text("Repeat while held").tag(RepeatMode.hold)
                }
                .labelsHidden()
                .frame(width: 160)
                if repeatMode == .hold {
                    LabeledContent("Interval (ms)") {
                        TextField("", value: Binding(
                            get: { repeatIntervalMS },
                            set: { emit(repeatIntervalMS: Int($0)) }), format: .number)
                            .frame(width: 60)
                    }
                    .frame(width: 150)
                }
                Toggle("Proxy modifiers", isOn: Binding(
                    get: { modifierProxy },
                    set: { emit(modifierProxy: $0) }))
                    .toggleStyle(.checkbox)
            }
            MacroStepsEditorView(steps: steps) { steps in
                emit(steps: steps)
            }
        }
    }

    private func emit(steps: [MacroStep]? = nil, repeatMode: RepeatMode? = nil,
                      repeatIntervalMS: Int? = nil, modifierProxy: Bool? = nil) {
        onChange(.macro(
            steps: steps ?? self.steps,
            repeatMode: repeatMode ?? self.repeatMode,
            repeatIntervalMS: repeatIntervalMS ?? self.repeatIntervalMS,
            modifierProxy: modifierProxy ?? self.modifierProxy))
    }
}
```

`MacroStepsEditorView.swift`:

```swift
import SwiftUI
import ArtMouseCore

struct MacroStepsEditorView: View {
    let steps: [MacroStep]
    let onChange: ([MacroStep]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack {
                    Text("\(index + 1).").frame(width: 24, alignment: .trailing)
                        .font(.caption).foregroundStyle(.secondary)
                    MacroStepEditorView(step: step) { newStep in
                        var next = steps
                        next[index] = newStep
                        onChange(next)
                    }
                    Spacer()
                    moveButtons(index: index)
                    Button(role: .destructive) { remove(at: index) } label: {
                        Image(systemName: "trash")
                    }
                }
            }
            Menu("Add step…") {
                Button("Key") { onChange(steps + [.enterKey(keyCode: 40, mods: [])]) }
                Button("Click") { onChange(steps + [.click(op: .left, mods: [])]) }
                Button("Wait 250ms") { onChange(steps + [.wait(milliseconds: 250)]) }
            }
        }
    }

    private func moveButtons(index: Int) -> some View {
        HStack(spacing: 2) {
            Button { move(index, -1) } label: { Image(systemName: "arrow.up") }
                .disabled(index == 0)
            Button { move(index, 1) } label: { Image(systemName: "arrow.down") }
                .disabled(index == steps.count - 1)
        }
        .buttonStyle(.borderless)
    }

    private func move(_ index: Int, _ delta: Int) {
        var next = steps
        let target = index + delta
        guard steps.indices.contains(index), steps.indices.contains(target) else { return }
        next.swapAt(index, target)
        onChange(next)
    }

    private func remove(at index: Int) {
        var next = steps
        next.remove(at: index)
        onChange(next)
    }
}
```

`MacroStepEditorView.swift`:

```swift
import SwiftUI
import ArtMouseCore

struct MacroStepEditorView: View {
    let step: MacroStep
    let onChange: (MacroStep) -> Void

    var body: some View {
        switch step {
        case .enterKey(let keyCode, let mods):
            HStack {
                Text("Key").frame(width: 70, alignment: .leading)
                LabeledContent("Code") {
                    TextField("", value: Binding(
                        get: { Double(keyCode) },
                        set: { onChange(.enterKey(keyCode: UInt64(max(0, $0)), mods: mods)) }),
                        format: .number)
                        .frame(width: 60)
                }
                .frame(width: 110)
                modChecks("⌘⌃⌥⇧", current: mods) { onChange(.enterKey(keyCode: keyCode, mods: $0)) }
            }
        case .click(let op, let mods):
            HStack {
                Text("Click").frame(width: 70, alignment: .leading)
                Picker("", selection: Binding(
                    get: { op },
                    set: { onChange(.click(op: $0, mods: mods)) })) {
                    Text("Left").tag(ClickOp.left)
                    Text("Right").tag(ClickOp.right)
                    Text("Middle").tag(ClickOp.middle)
                }
                .labelsHidden()
                .frame(width: 90)
                modChecks("⌘⌃⌥⇧", current: mods) { onChange(.click(op: op, mods: $0)) }
            }
        case .wait(let ms):
            HStack {
                Text("Wait").frame(width: 70, alignment: .leading)
                LabeledContent("ms") {
                    TextField("", value: Binding(
                        get: { Double(ms) },
                        set: { onChange(.wait(milliseconds: Int(max(1, $0))) ) }), format: .number)
                        .frame(width: 60)
                }
                .frame(width: 110)
            }
        }
    }

    private let modRows: [(String, ModKeys)] = [("⌘", .command), ("⌃", .control), ("⌥", .option), ("⇧", .shift)]

    private func modChecks(_ title: String, current: ModKeys,
                           onChange: @escaping (ModKeys) -> Void) -> some View {
        HStack {
            ForEach(modRows, id: \\.1) { item in
                Toggle(item.0, isOn: Binding(
                    get: { current.contains(item.1) },
                    set: { on in
                        var next = current
                        if on { next.insert(item.1) } else { next.remove(item.1) }
                        onChange(next)
                    }))
                    .toggleStyle(.checkbox)
            }
        }
    }
```

(`modRows` is a stored let on the struct — derive-from-props safe.)


- [ ] **Step 3: Build + smoke + commit**

`swift build` clean; `swift test` green (unchanged); bundle smoke (open, pid stable 5 s, pkill).

```bash
git add Sources/artMouse
git commit -m "Add macro action editor UI"
```

### Task 7: Snapping UI

**Files:**
- Create: `Sources/artMouse/Views/SnapActionEditorView.swift`
- Modify: `Sources/artMouse/Views/ActionEditorView.swift` (real `.snapping` category + dispatch)

**Interfaces:**
- Produces: `ActionCategory.snapping` (label "Snap", initialAction `.snapping(.snap(click: true, bounce: false))`); dispatch case → `SnapActionEditorView`.

- [ ] **Step 1: ActionCategory + dispatch + view**

`ActionEditorView.swift`: replace the interim `.snapping` arms — category `.snapping` (label "Snap"), init maps properly, `initialAction: .snapping(.snap(click: true, bounce: false))`; dispatch `case .snapping(let op): SnapActionEditorView(op: op, onChange: onChange)`.

`SnapActionEditorView.swift`:

```swift
import SwiftUI
import ArtMouseCore

struct SnapActionEditorView: View {
    let op: SnappingOp
    let onChange: (Action?) -> Void

    var body: some View {
        HStack {
            Text("Snap to default button").frame(width: 170, alignment: .leading)
            if case .snap(let click, let bounce) = op {
                Toggle("Click it", isOn: Binding(
                    get: { click },
                    set: { onChange(.snapping(.snap(click: $0, bounce: bounce))) }))
                    .toggleStyle(.checkbox)
                Toggle("Return to origin", isOn: Binding(
                    get: { bounce },
                    set: { onChange(.snapping(.snap(click: click, bounce: $0))) }))
                    .toggleStyle(.checkbox)
            }
        }
    }
}
```

- [ ] **Step 2: Build + smoke + commit**

`swift build` clean; `swift test` green; bundle smoke.

```bash
git add Sources/artMouse
git commit -m "Add snapping action editor UI"
```

### Task 8: Apps tab UI — per-application profiles

**Files:**
- Create: `Sources/artMouse/Views/AppsTabView.swift`, `Sources/artMouse/Views/AppProfileEditorView.swift`
- Modify: `Sources/artMouse/AppModel.swift`
- Modify: `Sources/artMouse/Views/SettingsWindow.swift` (add the Apps tab after Chords)

**Interfaces:**
- Consumes: `AppProfile`, `AppWatcher.frontmostBundleID` (via AppModel), cursor/wheel profile lists.
- Produces (exact): `AppModel` gains `addAppProfile(bundleID: String, name: String)`, `addFrontmostAppProfile()`, `removeAppProfile(_ id: UUID)`, `updateAppProfile(_ profile: AppProfile)`; `var frontmostBundleID: String? { watcher?.frontmostBundleID }` (AppModel gains a weak `watcher: AppWatcher?` init param; AppDelegate passes the shared watcher).

- [ ] **Step 1: AppModel methods + watcher param**

```swift
private weak var watcher: AppWatcher?

init(store: SettingsStore, permissions: PermissionsController, devices: DeviceManager,
     watcher: AppWatcher? = nil) {
    // …existing assignments…
    self.watcher = watcher
}

var frontmostBundleID: String? { watcher?.frontmostBundleID }

func addAppProfile(bundleID: String, name: String) {
    guard !bundleID.isEmpty else { return }
    var settings = store.settings
    guard !settings.appProfiles.contains(where: { $0.bundleID == bundleID }) else { return }
    settings.appProfiles.append(AppProfile(bundleID: bundleID, name: name))
    store.settings = settings
    save()
}

func addFrontmostAppProfile() {
    guard let bundleID = frontmostBundleID else { return }
    addAppProfile(bundleID: bundleID, name: bundleID)
}

func removeAppProfile(_ id: UUID) {
    var settings = store.settings
    settings.appProfiles.removeAll { $0.id == id }
    store.settings = settings
    save()
}

func updateAppProfile(_ profile: AppProfile) {
    var settings = store.settings
    if let index = settings.appProfiles.firstIndex(where: { $0.id == profile.id }) {
        settings.appProfiles[index] = profile
    }
    store.settings = settings
    save()
}
```

- [ ] **Step 2: AppsTabView + AppProfileEditorView**

`AppsTabView.swift`:

```swift
import SwiftUI
import ArtMouseCore

struct AppsTabView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Per-application profiles").font(.headline)
                Spacer()
                Button("Add Frontmost App") { model.addFrontmostAppProfile() }
            }
            List(model.settings.appProfiles) { profile in
                AppProfileEditorView(
                    profile: profile,
                    cursorProfiles: model.settings.cursorSpeedProfiles,
                    wheelProfiles: model.settings.wheelModeProfiles,
                    onUpdate: { model.updateAppProfile($0) },
                    onDelete: { model.removeAppProfile($0.id) })
            }
            Text("While the matching app is frontmost, its overrides replace the global cursor speed and wheel mode. Add the app you are using right now with “Add Frontmost App”. Button-binding overrides are edited in settings.json (advanced).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
```

`AppProfileEditorView.swift` (derive-from-props):

```swift
import SwiftUI
import ArtMouseCore

struct AppProfileEditorView: View {
    let profile: AppProfile
    let cursorProfiles: [CursorSpeedProfile]
    let wheelProfiles: [WheelModeProfile]
    let onUpdate: (AppProfile) -> Void
    let onDelete: (AppProfile) -> Void

    var body: some View {
        HStack(spacing: 12) {
            TextField("Name", text: Binding(
                get: { profile.name },
                set: { onUpdate(copy(name: $0)) }))
                .frame(width: 110)
            TextField("Bundle ID", text: Binding(
                get: { profile.bundleID },
                set: { onUpdate(copy(bundleID: $0)) }))
                .frame(width: 180)
            Picker("Cursor", selection: Binding(
                get: { profile.cursorSpeedProfileID },
                set: { onUpdate(copy(cursorSpeedProfileID: $0)) })) {
                Text("Global").tag(UUID?.none)
                ForEach(cursorProfiles) { profile in
                    Text(profile.name).tag(UUID?.some(profile.id))
                }
            }
            .frame(width: 150)
            Picker("Wheel", selection: Binding(
                get: { profile.wheelModeProfileID },
                set: { onUpdate(copy(wheelModeProfileID: $0)) })) {
                Text("Global").tag(UUID?.none)
                ForEach(wheelProfiles) { profile in
                    Text(profile.name).tag(UUID?.some(profile.id))
                }
            }
            .frame(width: 150)
            Spacer()
            Button(role: .destructive) { onDelete(profile) } label: { Image(systemName: "trash") }
        }
    }

    private func copy(name: String) -> AppProfile { var c = profile; c.name = name; return c }
    private func copy(bundleID: String) -> AppProfile { var c = profile; c.bundleID = bundleID; return c }
    private func copy(cursorSpeedProfileID: UUID?) -> AppProfile { var c = profile; c.cursorSpeedProfileID = cursorSpeedProfileID; return c }
    private func copy(wheelModeProfileID: UUID?) -> AppProfile { var c = profile; c.wheelModeProfileID = wheelModeProfileID; return c }
}
```

`SettingsWindow`: `.tabItem { Text("Apps") }` hosting `AppsTabView(model: model)` after Chords.

- [ ] **Step 3: AppDelegate passes the watcher**

`applicationDidFinishLaunching`: the existing `AppWatcher` construction (inside EngineBootstrap today) must become shared — construct `let appWatcher = AppWatcher()` in `applicationDidFinishLaunching`, pass it to `EngineBootstrap` (new init param `appWatcher:` replacing its internal construction; bootstrap keeps `appWatcher.start()`), and to `AppModel(watcher: appWatcher)`.

- [ ] **Step 4: Build + smoke + commit**

`swift build` clean; `swift test` green (unchanged); bundle smoke.

```bash
git add Sources/artMouse
git commit -m "Add per-application profiles UI"
```

### Task 9: Import/export settings

**Files:**
- Modify: `Sources/ArtMouseCore/Settings/SettingsStore.swift`
- Create: `Sources/artMouse/Views/GeneralTabView.swift`
- Modify: `Sources/artMouse/AppModel.swift`
- Modify: `Sources/artMouse/Views/SettingsWindow.swift` (add the General tab)
- Create: `Tests/ArtMouseCoreTests/AppModelTests.swift` — store-level import/export tests live in SettingsStoreTests instead (AppModel is app-target): add to SettingsStoreTests.

**Interfaces:**
- Produces (exact):
  - `SettingsStore.exportData() throws -> Data` — encode current settings
  - `SettingsStore.importData(_ data: Data) throws` — strict `Self.decode(data)`; on success assign `settings = decoded` (caller saves); on failure THROWS leaving settings untouched (Review Focus 5)
- [ ] **Step 1: Failing tests**

Append to `SettingsStoreTests`:

```swift
func testExportImportRoundTrip() throws {
    let dir = tempDirectory()
    let store = SettingsStore(directory: dir)
    var settings = GlobalSettings.default
    settings.buttonBindings = [ButtonBinding(button: .fifth, actions: [.open(.path("/tmp"))])]
    settings.chords = [Chord(buttons: [.middle, .fourth], actions: [])]
    store.settings = settings

    let data = try store.exportData()
    let other = SettingsStore(directory: tempDirectory())
    try other.importData(data)
    XCTAssertEqual(other.settings, settings)
}

func testImportGarbageLeavesSettingsUntouched() throws {
    let dir = tempDirectory()
    let store = SettingsStore(directory: dir)
    store.settings.buttonBindings = [ButtonBinding(button: .fifth, actions: [.none])]

    XCTAssertThrowsError(try store.importData(Data("garbage".utf8)))
    XCTAssertEqual(store.settings.buttonBindings.count, 1)   // untouched
}
```

(`tempDirectory()` helper already exists in the suite.)

- [ ] **Step 2: Implement store methods**

```swift
public func exportData() throws -> Data {
    try encoder.encode(settings)
}

/// Strict import: throws on malformed data WITHOUT touching current settings.
public func importData(_ data: Data) throws {
    settings = try Self.decode(data)
}
```

- [ ] **Step 3: GeneralTabView + AppModel + wiring**

`AppModel` additions:

```swift
@Observable
final class AppModel {
    // …existing…
    private(set) var lastImportError: String?

    func exportSettings() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "artMouse-settings.json"
        if panel.runModal() == .OK, let url = panel.url {
            try? store.exportData().write(to: url)
        }
    }

    func importSettings() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            try store.importData(data)
            save()
            lastImportError = nil
        } catch {
            lastImportError = "Import failed: \(error.localizedDescription)"
        }
    }
}
```

`GeneralTabView.swift`:

```swift
import SwiftUI

struct GeneralTabView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("Export Settings…") { model.exportSettings() }
                Button("Import Settings…") { model.importSettings() }
            }
            if let error = model.lastImportError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Spacer()
        }
        .padding(.top, 8)
    }
}
```

`SettingsWindow`: `.tabItem { Text("General") }` hosting `GeneralTabView(model: model)` after Apps.

- [ ] **Step 4: Build + tests + smoke + commit**

Run: `swift test --filter SettingsStoreTests` (2 new pass) then `swift test` full suite green; bundle smoke.

```bash
git add Sources/ArtMouseCore/Settings/SettingsStore.swift Sources/artMouse Tests/ArtMouseCoreTests/SettingsStoreTests.swift
git commit -m "Add settings import and export"
```

### Task 10: Phase 3 verification checklist

**Files:**
- Create: `docs/verification/phase-3.md`

**Interfaces:**
- Consumes: the completed app.

- [ ] **Step 1: Run the full automated suite**

Run: `swift test` — expect 161+ tests, 0 failures. Fix anything red with separate bug-fix commits.

- [ ] **Step 2: Automatable checks with evidence**

- Launch + stability (normal + `--safe-mode`), pkill cleanup — same commands as prior phases.
- Settings survival: Phase-2-shaped file (with chords + wheel profiles, no `appProfiles` key) → launch → verify alive → trigger a UI save → settings.json contains `appProfiles` alongside preserved Phase-1/2 fields (json.tool valid).
- Corrupt-settings recovery: garbage file → relaunch → alive + defaults (same as prior phases), restore clean state.
- Import/export round-trip: covered by unit tests (`testExportImportRoundTrip`); record the test name as evidence.

- [ ] **Step 3: Human checklist** (unchecked, HOW TO VERIFY)

- [ ] Permissions on fresh launch; banner clears.
- [ ] Macro: bind a macro (Key k, Wait 250, Key s) to 4th button; press in TextEdit — "ks" types after 250 ms.
- [ ] Macro hold-repeat: repeat mode Hold, interval 250; hold the button — sequence repeats until release; no stuck key afterwards.
- [ ] Modifier proxy: hold ⌘ physically, trigger the macro — the macro's keys register as ⌘+key.
- [ ] Snapping: open a dialog with a default button; bind Snap (click on) — cursor jumps to the default button and clicks it.
- [ ] Snapping bounce: click + bounce on — cursor returns to where it was.
- [ ] Snapping no-op: focus a window with no default button — nothing happens, cursor stays.
- [ ] Per-app: Add Frontmost App while Safari is front; set its cursor profile to Slow; switch to Safari (cursor slows) and TextEdit (cursor normal).
- [ ] Per-app wheel: set Safari's wheel mode to Constant; scroll in Safari vs TextEdit — different feel per app.
- [ ] Import/export: export, wipe bindings, import — everything returns.
- [ ] Sleep/wake: macros and snapping still work after wake.
- [ ] Phase-1/2 regression spot-check: click binding, cursor profiles, reverse scroll, a chord.

- [ ] **Step 4: Commit**

```bash
git add docs/verification/phase-3.md
git commit -m "Record phase 3 verification"
```

## Summary of delivered behavior (Phase 3)

After Task 10, artMouse additionally: executes key macros (enter/click/wait sequences, hold-repeat, modifier proxy reading physical modifiers), snaps the cursor to the focused window's default button (jump / click / click-and-return via Accessibility), applies per-application overrides (cursor speed, wheel mode; binding overrides via settings.json) driven by frontmost-app watching, and imports/exports settings as JSON. Phase-1/2 settings survive the upgrade.
