# artMouse Phase 2 — Wheel Suite + Chords Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the wheel suite — scroll modes (acceleration/constant/auto), reverse, speed parameters, smooth scroll, wheel→keys, auto-scroll, two-way scroll bindings, wheel-mode profiles with button switching — plus the ChordEngine (multi-button combinations → actions), with settings UI for all of it.

**Architecture:** `ScrollController` resolves each native scroll event against the active `WheelModeProfile` into a `ScrollDisposition` (pass through / scale fields / intercept-and-synthesize). `ScrollEmitter` synthesizes replacement scroll/keyboard events on a virtual-clock schedule through the same tagged `CGEventPoster` Phase 1 uses (self-posted events pass the tap unrouted — no scroll loops). `ChordEngine` intercepts button events ahead of binding resolution with a lazily-timed FSM. `EventRouter` gains scroll and chord collaborators; the engine gains scroll-axis field scaling.

**Tech Stack:** Swift 5.9, SPM, XCTest, AppKit/SwiftUI. Zero third-party dependencies. Builds on the merged Phase 1 codebase at `main`.

**Spec:** `docs/superpowers/specs/2026-11-09-artmouse-design.md` — §4 ScrollController/ChordEngine, §5 data model, §6 Phase 2 bullet. The plan argues from the spec; executors read both.

## Global Constraints

- macOS 14.0 floor (`platforms: [.macOS(.v14)]`), `// swift-tools-version: 5.9`, zero third-party dependencies.
- Engine logic lives only in `ArtMouseCore`; app-target files render and forward only; one view struct per file; split any file nearing ~150 lines; SwiftUI editors are derive-from-props (NO `@State` — Phase 1 lesson, reviewer-mandated).
- TDD: failing test documented (RED) before implementation, green before commit. Commits: plain imperative messages, never any AI attribution lines or Co-Authored-By trailers.
- Main-run-loop single-queue discipline (carried): all controller/emitter state is unsynchronized; timers run on the main run loop in `.common` mode; nothing crosses queues.
- ALL synthetic events (scroll emissions, wheel→keys, chord-dispatched clicks) go through the shared `CGEventPoster` instance so they carry the private-source tag and pass the tap unrouted (Phase 1's loop protection).
- **Backward compatibility:** a Phase 1 `settings.json` (which lacks every new field) MUST decode without falling back to defaults — `GlobalSettings` gets a custom `init(from:)` defaulting the new keys (Task 2 pins it with a Phase-1 fixture).
- Engine-side clamping precedent: clamp user-facing wheel numbers at consumption in `ScrollController` — sensFactor 0.1...10.0, acceleration 0...10.0, lines 0...100.0, intervalMS 8...1000, autoStopTicks 1...100.
- Phase-2 spec deviation (sanctioned, recorded): `Action.scroll`'s ScrollSpec carries only button-relevant fields (direction, mods, lines, intervalMS, continuous) — sensFactor/acceleration/autoMode belong to `WheelModeProfile` where they actually apply; wheel `keyEmulation` replaces SteerMouse's "enter keys while rolling"; free-spin hardware momentum AND the mouse-vs-trackball scroll direction convention are deferred to Phase 4 (both depend on device-profile data); ScrollBinding drops the mods field (wheel modifiers are a Phase 4 concept).

## Review Focus

Failure modes the spec implies that unit tests below do not fully exercise. Each line's pinning verification lives in the named task.

1. **Phase-1 settings.json must survive the upgrade** — a user's existing file lacks all new fields; decode must default them, never drop the user's bindings/profiles to factory defaults. Pinned by Task 2's Phase-1 fixture test + Task 12's manual check.
2. **Synthetic scroll storm**: emitter events must be tagged and pass the tap unrouted — one untagged path is an infinite scroll loop. Pinned by Task 3's poster-ownership test + Task 12's manual smooth-scroll check.
3. **Runaway auto-scroll**: after the last real wheel input, the auto emitter must stop within autoStopTicks emissions — a stuck emitter scrolls forever. Pinned by Task 3's virtual-clock stop test.
4. **Chord capture starving a solo button**: a chord-start button pressed with no second button must still fire its own binding (flush on release, or lazily on the next event's timeout) — never swallowed into a dead capture. Pinned by Task 7's flush tests.
5. **High-rate tick streams on two-way bindings**: gaming wheels send dense tick bursts; each tick fires the bound action exactly once — no internal amplification or repeat. Pinned by Task 6's burst test.

---

## File Structure (Phase 2)

```
artMouse/
├── Sources/ArtMouseCore/
│   ├── Model/
│   │   ├── ScrollDirection.swift          # up/down/left/right
│   │   ├── ScrollSpec.swift               # button→scroll action payload
│   │   ├── ChordModel.swift               # Chord struct
│   │   └── InputEvent.swift               # (exists)
│   ├── Settings/
│   │   ├── WheelModeProfile.swift         # ScrollMode, WheelKeyEmulation, WheelModeProfile
│   │   ├── ScrollBinding.swift            # two-way wheel bindings
│   │   ├── GlobalSettings.swift           # (exists — new fields + custom decode)
│   │   └── SettingsStore.swift            # (exists — untouched)
│   ├── Engine/
│   │   ├── RouterOutcome.swift            # (exists — + scrollTransform)
│   │   ├── EventRouter.swift              # (exists — scroll + chord integration)
│   │   ├── ChordEngine.swift              # chord FSM
│   │   └── EventTapEngine.swift           # (exists — + scroll field scaling)
│   ├── Scroll/
│   │   ├── ScrollDisposition.swift
│   │   ├── ScrollController.swift         # profile → disposition, clamping, mode logic
│   │   └── ScrollEmitter.swift            # virtual-clock synthesizer (smooth/auto/keys/once)
│   └── Actions/
│       └── ActionExecutor.swift           # (exists — + wheel-mode switching, Action.scroll emission)
├── Sources/artMouse/
│   ├── AppModel.swift                     # (exists — wheel/chord/scroll-binding CRUD)
│   ├── EngineBootstrap.swift              # (exists — new collaborators)
│   └── Views/
│       ├── SettingsWindow.swift           # (exists — + Wheel/Chords tabs)
│       ├── WheelTabView.swift
│       ├── WheelProfileEditorView.swift
│       ├── WheelKeysEditorView.swift
│       ├── ChordsTabView.swift
│       ├── ChordEditorView.swift
│       ├── ScrollBindingsTabView.swift
│       ├── ScrollBindingRowView.swift
│       ├── ActionEditorView.swift         # (exists — + .scroll category)
│       └── ScrollActionEditorView.swift
└── Tests/ArtMouseCoreTests/
    ├── ActionModelTests.swift             # (exists — + .scroll cases)
    ├── SettingsStoreTests.swift           # (exists — + Phase-1 fixture, wheel fallbacks)
    ├── ScrollEmitterTests.swift
    ├── ScrollControllerTests.swift
    ├── EventTapEngineTests.swift          # (exists — + scroll scaling)
    ├── EventRouterTests.swift             # (exists — + scroll bindings, chords)
    ├── ChordEngineTests.swift
    └── ActionExecutorTests.swift          # (exists — + Action.scroll, switchWheelMode)
```

---

### Task 1: Scroll/chord/wheel data models and `Action.scroll`

**Files:**
- Create: `Sources/ArtMouseCore/Model/ScrollDirection.swift`, `Sources/ArtMouseCore/Model/ScrollSpec.swift`, `Sources/ArtMouseCore/Model/ChordModel.swift`
- Modify: `Sources/ArtMouseCore/Model/Action.swift` (add `.scroll` case)
- Modify: `Tests/ArtMouseCoreTests/ActionModelTests.swift`

**Interfaces:**
- Consumes: `ModKeys` (Phase 1).
- Produces (exact):
  - `enum ScrollDirection: String, Codable, CaseIterable, Equatable { case up, down, left, right }` with `var axis: ScrollAxis` (up/down → .vertical, left/right → .horizontal) and `var sign: Double` (up/right → +1, down/left → −1).
  - `struct ScrollSpec: Codable, Equatable, Hashable { var direction: ScrollDirection; var mods: ModKeys; var lines: Double; var intervalMS: Int; var continuous: Bool }` — memberwise init with defaults `mods: [] , lines: 3, intervalMS: 100, continuous: false`.
  - `struct Chord: Codable, Equatable, Identifiable, Hashable { var id: UUID; var buttons: [ButtonID]; var actions: [Action]; var timeout: Double }` — `buttons[0]` is the initiator; memberwise init with `timeout: Double = 0.3`.
  - `Action` gains `case scroll(ScrollSpec)` (Codable synthesis covers it; `isHoldAction`/`isClickLock` unchanged).

- [ ] **Step 1: Write failing tests**

Append to `ActionModelTests.swift`:

```swift
func testScrollDirectionAxisAndSign() {
    XCTAssertEqual(ScrollDirection.up.axis, .vertical)
    XCTAssertEqual(ScrollDirection.down.axis, .vertical)
    XCTAssertEqual(ScrollDirection.left.axis, .horizontal)
    XCTAssertEqual(ScrollDirection.right.axis, .horizontal)
    XCTAssertEqual(ScrollDirection.up.sign, 1)
    XCTAssertEqual(ScrollDirection.down.sign, -1)
    XCTAssertEqual(ScrollDirection.right.sign, 1)
    XCTAssertEqual(ScrollDirection.left.sign, -1)
}

func testActionScrollCodableRoundTrip() throws {
    let spec = ScrollSpec(direction: .down, mods: [.shift], lines: 5, intervalMS: 50, continuous: true)
    let original: [Action] = [.scroll(spec)]
    let data = try JSONEncoder().encode(original)
    XCTAssertEqual(try JSONDecoder().decode([Action].self, from: data), original)
}

func testChordCodableRoundTripAndDefaults() throws {
    var chord = Chord(id: UUID(), buttons: [.middle, .fourth], actions: [.mission(.missionControl, reverse: false)])
    XCTAssertEqual(chord.timeout, 0.3, accuracy: 1e-12)
    chord.timeout = 0.5
    let data = try JSONEncoder().encode(chord)
    XCTAssertEqual(try JSONDecoder().decode(Chord.self, from: data), chord)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ActionModelTests`
Expected: FAIL — `ScrollDirection`/`ScrollSpec`/`Chord` not defined.

- [ ] **Step 3: Write the model files**

`ScrollDirection.swift`:

```swift
public enum ScrollDirection: String, Codable, CaseIterable, Equatable {
    case up, down, left, right

    public var axis: ScrollAxis {
        switch self {
        case .up, .down: return .vertical
        case .left, .right: return .horizontal
        }
    }

    /// Emission sign on the wheel axis for this direction.
    public var sign: Double {
        switch self {
        case .up, .right: return 1
        case .down, .left: return -1
        }
    }
}
```

`ScrollSpec.swift`:

```swift
/// Button→scroll action payload. Wheel reparametrization (sensFactor,
/// acceleration, modes) lives in WheelModeProfile — see plan header note.
public struct ScrollSpec: Codable, Equatable, Hashable {
    public var direction: ScrollDirection
    public var mods: ModKeys
    public var lines: Double
    public var intervalMS: Int
    public var continuous: Bool

    public init(direction: ScrollDirection, mods: ModKeys = [], lines: Double = 3,
                intervalMS: Int = 100, continuous: Bool = false) {
        self.direction = direction
        self.mods = mods
        self.lines = lines
        self.intervalMS = intervalMS
        self.continuous = continuous
    }
}
```

`ChordModel.swift`:

```swift
/// Multi-button combination: buttons[0] initiates capture; the chord fires
/// when every button in `buttons` is held within `timeout` seconds.
public struct Chord: Codable, Equatable, Identifiable, Hashable {
    public var id: UUID
    public var buttons: [ButtonID]
    public var actions: [Action]
    public var timeout: Double

    public init(id: UUID = UUID(), buttons: [ButtonID], actions: [Action], timeout: Double = 0.3) {
        self.id = id
        self.buttons = buttons
        self.actions = actions
        self.timeout = timeout
    }
}
```

`Action.swift`: add `case scroll(ScrollSpec)` to the enum (place after `.device`).

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ActionModelTests`
Expected: PASS (all, including the 3 new ones).

- [ ] **Step 5: Commit**

```bash
git add Sources/ArtMouseCore/Model Tests/ArtMouseCoreTests/ActionModelTests.swift
git commit -m "Add scroll, chord and wheel data models"
```

### Task 2: GlobalSettings — wheel fields, scroll bindings, chords, backward-compatible decoding

**Files:**
- Create: `Sources/ArtMouseCore/Settings/WheelModeProfile.swift`, `Sources/ArtMouseCore/Settings/ScrollBinding.swift`
- Modify: `Sources/ArtMouseCore/Settings/GlobalSettings.swift`
- Modify: `Tests/ArtMouseCoreTests/SettingsStoreTests.swift`

**Interfaces:**
- Consumes: `ScrollAxis`, `ScrollDirection`, `ModKeys`, `Action`, `ButtonID`, `WheelModeProfile`.
- Produces (exact):
  - `enum ScrollMode: String, Codable, CaseIterable { case acceleration, constant, auto }`
  - `struct WheelKeyEmulation: Codable, Equatable { var keyCode: UInt64; var mods: ModKeys; var repeatWhileRolling: Bool }`
  - `struct WheelModeProfile: Codable, Equatable, Identifiable { var id: UUID; var name: String; var mode: ScrollMode; var sensFactor: Double; var acceleration: Double; var lines: Double; var intervalMS: Int; var reverseVertical: Bool; var reverseHorizontal: Bool; var smoothScroll: Bool; var smoothIntervalMS: Int; var keyEmulation: WheelKeyEmulation?; var autoIntervalMS: Int; var autoStopTicks: Int }` — memberwise init with defaults: sensFactor 1.0, acceleration 0.0, lines 3.0, intervalMS 100, reverses false, smoothScroll false, smoothIntervalMS 16, keyEmulation nil, autoIntervalMS 50, autoStopTicks 5.
  - `struct ScrollBinding: Codable, Equatable, Identifiable { var id: UUID; var axis: ScrollAxis; var direction: ScrollDirection; var actions: [Action] }` (ScrollAxis gains `Codable` in this task).
  - `GlobalSettings` gains stored fields `wheelModeProfiles: [WheelModeProfile]`, `activeWheelModeProfileID: UUID?`, `scrollBindings: [ScrollBinding]`, `chords: [Chord]` — with a CUSTOM `init(from decoder:)` defaulting every new field when absent (Phase-1 JSON compatibility), and `static let default` extended: `wheelModeProfiles: [WheelModeProfile(name: "Default")]`, others empty/nil.
  - `extension GlobalSettings { var activeWheelProfile: WheelModeProfile? }` — explicit ID → profile named "Default" → first (same fallback chain as activeProfile).

- [ ] **Step 1: Write failing tests**

Append to `SettingsStoreTests.swift`:

```swift
func testPhase1SettingsJSONStillDecodes() throws {
    // Exact shape a Phase 1 save produced: no wheel/chord/scroll fields.
    let phase1JSON = """
    {"activeCursorSpeedProfileID":null,"buttonBindings":[],
     "cursorSpeedProfiles":[{"acceleration":1,"id":"11111111-1111-1111-1111-111111111111","name":"Default","sensitivity":1600}],
     "precisionProfileID":null,"schemaVersion":1}
    """
    let settings = try SettingsStore.decode(Data(phase1JSON.utf8))
    XCTAssertEqual(settings.buttonBindings, [])
    XCTAssertEqual(settings.wheelModeProfiles.count, 0)   // defaulted, file not rewritten until next save
    XCTAssertEqual(settings.chords, [])
    XCTAssertEqual(settings.scrollBindings, [])
}

func testWheelModeProfileFallbackChain() {
    var settings = GlobalSettings.default
    XCTAssertNil(settings.activeWheelProfile)   // empty list

    settings.wheelModeProfiles = [WheelModeProfile(name: "Fast")]
    XCTAssertEqual(settings.activeWheelProfile?.name, "Fast")   // no named "Default" → first profile
}
```

And add:

```swift
func testActiveWheelProfilePrefersExplicitIDThenNamedDefaultThenFirst() {
    var settings = GlobalSettings.default
    let first = WheelModeProfile(name: "One")
    let named = WheelModeProfile(name: "Default")
    let other = WheelModeProfile(name: "Three")
    settings.wheelModeProfiles = [first, named, other]

    settings.activeWheelModeProfileID = other.id
    XCTAssertEqual(settings.activeWheelProfile, other)

    settings.activeWheelModeProfileID = UUID()          // dangling
    XCTAssertEqual(settings.activeWheelProfile, named)  // named Default

    settings.wheelModeProfiles = [first]                // named gone
    XCTAssertEqual(settings.activeWheelProfile, first)  // first
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SettingsStoreTests`
Expected: FAIL — compile errors on the new fields/types.

- [ ] **Step 3: Write WheelModeProfile.swift and ScrollBinding.swift**

`WheelModeProfile.swift`:

```swift
import Foundation

public enum ScrollMode: String, Codable, CaseIterable {
    case acceleration, constant, auto
}

/// Wheel→keyboard emulation: while the wheel rolls, hold/repeat a key.
public struct WheelKeyEmulation: Codable, Equatable {
    public var keyCode: UInt64
    public var mods: ModKeys
    public var repeatWhileRolling: Bool

    public init(keyCode: UInt64, mods: ModKeys = [], repeatWhileRolling: Bool = true) {
        self.keyCode = keyCode
        self.mods = mods
        self.repeatWhileRolling = repeatWhileRolling
    }
}

public struct WheelModeProfile: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var mode: ScrollMode
    public var sensFactor: Double
    public var acceleration: Double
    public var lines: Double
    public var intervalMS: Int
    public var reverseVertical: Bool
    public var reverseHorizontal: Bool
    public var smoothScroll: Bool
    public var smoothIntervalMS: Int
    public var keyEmulation: WheelKeyEmulation?
    public var autoIntervalMS: Int
    public var autoStopTicks: Int

    public init(id: UUID = UUID(), name: String, mode: ScrollMode = .acceleration,
                sensFactor: Double = 1.0, acceleration: Double = 0.0, lines: Double = 3.0,
                intervalMS: Int = 100, reverseVertical: Bool = false, reverseHorizontal: Bool = false,
                smoothScroll: Bool = false, smoothIntervalMS: Int = 16,
                keyEmulation: WheelKeyEmulation? = nil, autoIntervalMS: Int = 50,
                autoStopTicks: Int = 5) {
        self.id = id
        self.name = name
        self.mode = mode
        self.sensFactor = sensFactor
        self.acceleration = acceleration
        self.lines = lines
        self.intervalMS = intervalMS
        self.reverseVertical = reverseVertical
        self.reverseHorizontal = reverseHorizontal
        self.smoothScroll = smoothScroll
        self.smoothIntervalMS = smoothIntervalMS
        self.keyEmulation = keyEmulation
        self.autoIntervalMS = autoIntervalMS
        self.autoStopTicks = autoStopTicks
    }
}
```

`ScrollBinding.swift`:

```swift
import Foundation

/// Two-way wheel binding: distinct actions per scroll direction.
public struct ScrollBinding: Codable, Equatable, Identifiable {
    public var id: UUID
    public var axis: ScrollAxis
    public var direction: ScrollDirection
    public var actions: [Action]

    public init(id: UUID = UUID(), axis: ScrollAxis, direction: ScrollDirection, actions: [Action]) {
        self.id = id
        self.axis = axis
        self.direction = direction
        self.actions = actions
    }
}
```

`ScrollAxis` (in `Model/InputEvent.swift`) gains `Codable`:

```swift
public enum ScrollAxis: Equatable, Codable {
```

- [ ] **Step 4: Extend GlobalSettings with custom decoding**

In `GlobalSettings.swift`: add the four stored fields AFTER the existing ones, extend `default` (`wheelModeProfiles: [WheelModeProfile(name: "Default")]`, `activeWheelModeProfileID: nil`, `scrollBindings: []`, `chords: []`), and replace the synthesized decoding with a custom `init(from:)` that reads the four new keys with `decodeIfPresent(...) ?? default`:

```swift
public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
    cursorSpeedProfiles = try c.decode([CursorSpeedProfile].self, forKey: .cursorSpeedProfiles)
    activeCursorSpeedProfileID = try c.decodeIfPresent(UUID.self, forKey: .activeCursorSpeedProfileID)
    precisionProfileID = try c.decodeIfPresent(UUID.self, forKey: .precisionProfileID)
    buttonBindings = try c.decode([ButtonBinding].self, forKey: .buttonBindings)
    // Phase 2 fields: absent in Phase 1 files → defaults (backward compat).
    wheelModeProfiles = try c.decodeIfPresent([WheelModeProfile].self, forKey: .wheelModeProfiles) ?? [WheelModeProfile(name: "Default")]
    activeWheelModeProfileID = try c.decodeIfPresent(UUID.self, forKey: .activeWheelModeProfileID)
    scrollBindings = try c.decodeIfPresent([ScrollBinding].self, forKey: .scrollBindings) ?? []
    chords = try c.decodeIfPresent([Chord].self, forKey: .chords) ?? []
}
```

(`CodingKeys` is synthesized for the stored fields; the memberwise-style default `static let default` initializer keeps assigning ALL fields explicitly.) Also add the fallback extension:

```swift
public extension GlobalSettings {
    var activeWheelProfile: WheelModeProfile? {
        if let id = activeWheelModeProfileID,
           let match = wheelModeProfiles.first(where: { $0.id == id }) { return match }
        if let named = wheelModeProfiles.first(where: { $0.name == "Default" }) { return named }
        return wheelModeProfiles.first
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter SettingsStoreTests`
Expected: PASS (all, including the 3 new ones). Full suite: `swift test` green (88 prior + new).

- [ ] **Step 6: Commit**

```bash
git add Sources/ArtMouseCore/Settings Sources/ArtMouseCore/Model/InputEvent.swift Tests/ArtMouseCoreTests/SettingsStoreTests.swift
git commit -m "Add wheel mode profiles, scroll bindings and chords with backward-compatible settings decode"
```

### Task 3: ScrollEmitter — virtual-clock event synthesizer

**Files:**
- Create: `Sources/ArtMouseCore/Scroll/ScrollEmitter.swift`
- Create: `Tests/ArtMouseCoreTests/ScrollEmitterTests.swift`

**Interfaces:**
- Consumes: `EventPosting` (poster.post tags events), `ScrollDirection`, `WheelKeyEmulation` (Task 2), `KeyCodes`/`CGFlagConversion` (Phase 1).
- Produces (exact):
  - `final class ScrollEmitter { init(poster: EventPosting); func emitOnce(direction: ScrollDirection, lines: Double); func beginSmooth(direction: ScrollDirection, lines: Double, intervalMS: Int, now: Double); func beginAuto(direction: ScrollDirection, lines: Double, intervalMS: Int, stopAfterTicks: Int, now: Double); func noteInput(now: Double); func beginKeys(_ keys: WheelKeyEmulation, direction: ScrollDirection, now: Double); func tick(now: Double); var isActive: Bool { get } }`
  - Pinned behavior:
    - `emitOnce` posts ONE scroll event immediately: line units, the direction's axis carries `direction.sign * lines`, the other axis 0.
    - Smooth: emissions = `max(1, Int(80.0 / Double(intervalMS)))` chunks of `lines / emissions` each; first chunk immediately at `beginSmooth`, then one per `intervalMS`; idles when all chunks are emitted.
    - Auto: first emission at `now + intervalMS`, then one per `tick` (the caller drives cadence, Task 4); each `noteInput` resets the since-input counter; a tick that finds the counter at `stopAfterTicks` emits nothing and idles.
    - Keys: `beginKeys` posts key DOWN; ticks post down+up repeat pairs every `keyRepeatInterval = 0.1` s while `now - lastInput < keyReleaseGap = 0.25` when `repeatWhileRolling`; the first tick past the gap posts key UP and idles. `repeatWhileRolling == false`: down on begin, up after the gap, no repeats.
    - `isActive` false only in idle.
  - All posts go through `poster.post` (the poster tags them).

- [ ] **Step 1: Write failing tests**

`Tests/ArtMouseCoreTests/ScrollEmitterTests.swift` (`RecordingPoster` is module-visible from ActionExecutorTests.swift):

```swift
import XCTest
import CoreGraphics
@testable import ArtMouseCore

final class ScrollEmitterTests: XCTestCase {
    private var now = 0.0
    private let poster = RecordingPoster()

    private func makeEmitter() -> ScrollEmitter {
        ScrollEmitter(poster: poster)
    }

    func testEmitOncePostsLineDeltaOnAxis() {
        let emitter = makeEmitter()
        emitter.emitOnce(direction: .down, lines: 5)
        XCTAssertEqual(poster.events.count, 1)
        let event = poster.events[0]
        XCTAssertEqual(event.type, .scrollWheel)
        XCTAssertEqual(event.getDoubleValueField(.scrollWheelEventDeltaAxis1), -5, accuracy: 1e-9)
        XCTAssertEqual(event.getDoubleValueField(.scrollWheelEventDeltaAxis2), 0, accuracy: 1e-9)
    }

    func testEmitOnceHorizontalRight() {
        let emitter = makeEmitter()
        emitter.emitOnce(direction: .right, lines: 2)
        XCTAssertEqual(poster.events[0].getDoubleValueField(.scrollWheelEventDeltaAxis2), 2, accuracy: 1e-9)
        XCTAssertEqual(poster.events[0].getDoubleValueField(.scrollWheelEventDeltaAxis1), 0, accuracy: 1e-9)
    }

    func testSmoothSpreadsLinesAcrossEmissions() {
        let emitter = makeEmitter()
        emitter.beginSmooth(direction: .up, lines: 6, intervalMS: 16, now: now)   // emissions = 80/16 = 5 → 1.2 each
        emitter.tick(now: now)                                                     // first chunk immediately
        XCTAssertEqual(poster.events.count, 1)
        XCTAssertEqual(poster.events[0].getDoubleValueField(.scrollWheelEventDeltaAxis1), 6.0 / 5.0, accuracy: 1e-9)
        for _ in 0..<4 { now += 0.016; emitter.tick(now: now) }
        XCTAssertEqual(poster.events.count, 5)
        XCTAssertFalse(emitter.isActive)                                           // all chunks emitted → idle
    }

    func testAutoEmitsThenStopsWithoutInput() {
        let emitter = makeEmitter()
        emitter.beginAuto(direction: .up, lines: 3, intervalMS: 50, stopAfterTicks: 3, now: now)
        XCTAssertFalse(emitter.isActive)                                           // first emission after interval
        for i in 1...3 {
            now += 0.05
            emitter.tick(now: now)
            XCTAssertEqual(poster.events.count, i)
        }
        now += 0.05
        emitter.tick(now: now)                                                     // stopAfterTicks reached → stop
        XCTAssertEqual(poster.events.count, 3)
        XCTAssertFalse(emitter.isActive)
    }

    func testAutoCounterResetsOnInput() {
        let emitter = makeEmitter()
        emitter.beginAuto(direction: .up, lines: 3, intervalMS: 50, stopAfterTicks: 2, now: now)
        now += 0.05; emitter.tick(now: now)                        // emission 1
        emitter.noteInput(now: now)                                // refresh gap anchor (counter preserved)
        now += 0.05; emitter.tick(now: now)                        // emission 2
        now += 0.05; emitter.tick(now: now)                        // emission 3 (counter reached stopAfter)
        now += 0.05; emitter.tick(now: now)                        // stop, no emission
        XCTAssertEqual(poster.events.count, 3)
        XCTAssertFalse(emitter.isActive)
    }

    func testKeysDownThenRepeatThenReleaseAfterGap() {
        let emitter = makeEmitter()
        emitter.beginKeys(WheelKeyEmulation(keyCode: KeyCodes.f), direction: .up, now: now)
        XCTAssertEqual(poster.events.count, 1)                     // down
        XCTAssertEqual(poster.events[0].type, .keyDown)
        now += 0.10; emitter.tick(now: now)                        // repeat pair (down+up)
        XCTAssertEqual(poster.events.count, 3)
        now += 0.30; emitter.tick(now: now)                        // gap exceeded → key up → idle
        XCTAssertEqual(poster.events.count, 4)
        XCTAssertEqual(poster.events[3].type, .keyUp)
        XCTAssertFalse(emitter.isActive)
    }

    func testKeysWithoutRepeatPostsSingleDownAndUp() {
        let emitter = makeEmitter()
        emitter.beginKeys(WheelKeyEmulation(keyCode: KeyCodes.f, repeatWhileRolling: false), direction: .up, now: now)
        XCTAssertEqual(poster.events.count, 1)
        now += 0.30; emitter.tick(now: now)
        XCTAssertEqual(poster.events.count, 2)
        XCTAssertEqual(poster.events[1].type, .keyUp)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ScrollEmitterTests`
Expected: FAIL — `ScrollEmitter` not defined.

- [ ] **Step 3: Write ScrollEmitter.swift**

```swift
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
        let interval = Double(intervalMS) / 1000.0
        let emissions = max(1, Int(80.0 / Double(intervalMS)))
        mode = .smooth(direction: direction, pendingLines: lines,
                       chunkLines: lines / Double(emissions), interval: interval, nextDue: now)
        tick(now: now)   // first chunk immediately
    }

    public func beginAuto(direction: ScrollDirection, lines: Double, intervalMS: Int,
                          stopAfterTicks: Int, now: Double) {
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

    private func postScroll(direction: ScrollDirection, lines: Double) {
        let v = direction.axis == .vertical ? direction.sign * lines : 0
        let h = direction.axis == .horizontal ? direction.sign * lines : 0
        // Same working wheel-event construction as CGEventTranslationTests (Phase 1).
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1,
                            wheel: v, h, 0, or: [])!
        poster.post(event)
    }

    private func postKey(_ keys: WheelKeyEmulation, down: Bool) {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keys.keyCode),
                            keyDown: down, flags: CGFlagConversion.cgFlags(keys.mods))!
        poster.post(event)
    }
}
```

Sanctioned SDK adaptation (same toolchain as Phase 1): if the variadic wheel-event init differs on this SDK, match the EXACT working form from `CGEventTranslationTests.testScrollAxis` and note the adaptation in code.

Design note for the auto-mode cadence: the emitter's auto mode emits once per `tick` call; the CALLER controls cadence (Task 4's controller pairs auto with an emitter-driver timer at `autoIntervalMS`). The auto tests above call `tick` manually at the right cadence — that is the contract.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ScrollEmitterTests`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/ArtMouseCore/Scroll Tests/ArtMouseCoreTests/ScrollEmitterTests.swift
git commit -m "Add virtual-clock scroll emitter"
```

### Task 4: ScrollController — profile → disposition, clamping, modes

**Files:**
- Create: `Sources/ArtMouseCore/Scroll/ScrollDisposition.swift`, `Sources/ArtMouseCore/Scroll/ScrollController.swift`
- Create: `Tests/ArtMouseCoreTests/ScrollControllerTests.swift`

**Interfaces:**
- Consumes: `SettingsStore`, `GlobalSettings.activeWheelProfile` (Task 2), `ScrollEmitter` (Task 3).
- Produces (exact):
  - `enum ScrollDisposition: Equatable { case passThrough; case scale(vertical: Double, horizontal: Double); case intercept }` — `.intercept` means the controller has already instructed the emitter; the router consumes the native event.
  - `protocol ScrollControlling: AnyObject { func disposition(forScroll axis: ScrollAxis, ticks: Double) -> ScrollDisposition }`
  - `final class ScrollController: ScrollControlling { init(store: SettingsStore, emitter: ScrollEmitter, clock: @escaping () -> Double = { Date().timeIntervalSince1970 }); func disposition(forScroll axis: ScrollAxis, ticks: Double) -> ScrollDisposition; func pumpEmitter(); func activateNextWheelMode() }`
  - Clamps at consumption (per Global Constraints): sensFactor 0.1...10.0, acceleration 0...10.0, lines 0...100.0, intervalMS 8...1000, smoothIntervalMS 8...1000, autoIntervalMS 8...1000, autoStopTicks 1...100.
  - Decision order per scroll event: (1) no active wheel profile → `.passThrough`; (2) `keyEmulation != nil` → `beginKeys` + `noteInput` → `.intercept`; (3) `smoothScroll` → `beginSmooth` → `.intercept`; (4) mode `.acceleration` → `.scale`; (5) mode `.constant` → `emitOnce` + `noteInput` → `.intercept`; (6) mode `.auto` → `beginAuto` (on direction change or idle emitter) or `noteInput` (same direction, running) → `.intercept`.
  - Scale math: `accelFactor = 1 + clampedAcceleration * (|ticks| / 3.0)` (3 ticks = fast flick reference, constant `accelerationReferenceTicks = 3.0`); `factor = clampedSensFactor * accelFactor`, signed by tick direction; reverse flips the ticked axis's factor sign; the non-ticked axis factor is 1.0.
  - `pumpEmitter()` calls `emitter.tick(now: clock())` and clears internal auto bookkeeping when the emitter idles. Cadence: Task 8 wires a dedicated 8 ms Timer on the main run loop in `.common` mode that calls it.

- [ ] **Step 1: Write failing tests**

`Tests/ArtMouseCoreTests/ScrollControllerTests.swift`:

```swift
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
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ScrollControllerTests`
Expected: FAIL — types not defined.

- [ ] **Step 3: Write the implementation**

`ScrollDisposition.swift`:

```swift
public enum ScrollDisposition: Equatable {
    case passThrough
    case scale(vertical: Double, horizontal: Double)
    case intercept
}

public protocol ScrollControlling: AnyObject {
    func disposition(forScroll axis: ScrollAxis, ticks: Double) -> ScrollDisposition
}
```

`ScrollController.swift`:

```swift
import Foundation

/// Resolves native scroll events against the active WheelModeProfile.
/// All user-facing numbers are clamped HERE (the engine boundary) so absurd
/// settings can never run away.
public final class ScrollController: ScrollControlling {
    static let accelerationReferenceTicks = 3.0

    private let store: SettingsStore
    private let emitter: ScrollEmitter
    private let clock: () -> Double
    /// The direction currently auto-scrolling (nil = not in auto).
    private var autoDirection: ScrollDirection?

    public init(store: SettingsStore, emitter: ScrollEmitter,
                clock: @escaping () -> Double = { Date().timeIntervalSince1970 }) {
        self.store = store
        self.emitter = emitter
        self.clock = clock
    }

    /// Cadence pump for smooth drain and auto emissions — Task 8 wires an
    /// 8 ms timer on the main run loop (.common mode) that calls this.
    public func pumpEmitter() {
        emitter.tick(now: clock())
        if !emitter.isActive { autoDirection = nil }
    }

    public func activateNextWheelMode() {
        let profiles = store.settings.wheelModeProfiles
        guard let current = store.settings.activeWheelProfile,
              let index = profiles.firstIndex(where: { $0.id == current.id }) else { return }
        store.settings.activeWheelModeProfileID = profiles[(index + 1) % profiles.count].id
    }

    public func disposition(forScroll axis: ScrollAxis, ticks: Double) -> ScrollDisposition {
        guard let profile = store.settings.activeWheelProfile else { return .passThrough }
        let sens = profile.sensitivity.clamped(0.1...10.0)
        let accel = profile.acceleration.clamped(0...10.0)
        let lines = profile.lines.clamped(0...100.0)
        let interval = Int(profile.intervalMS.clamped(8...1000))
        let autoInterval = Int(profile.autoIntervalMS.clamped(8...1000))
        let stopTicks = Int(Double(profile.autoStopTicks.clamped(1...100)))

        let direction = Self.direction(axis: axis, ticks: ticks)

        // 1. Wheel→keys takes absolute precedence.
        if let keys = profile.keyEmulation {
            emitter.beginKeys(keys, direction: direction, now: clock())
            return .intercept
        }
        // 2. Smooth scroll overlay.
        if profile.smoothScroll {
            let magnitude = Double(abs(ticks))
            let total = magnitude * sens * (1 + accel * (magnitude / Self.accelerationReferenceTicks))
            emitter.beginSmooth(direction: direction, lines: total,
                                intervalMS: Int(profile.smoothIntervalMS.clamped(8...1000)),
                                now: clock())
            return .intercept
        }
        // 3. Modes.
        switch profile.mode {
        case .acceleration:
            return Self.scaleOutcome(axis: axis, ticks: ticks, sens: sens, accel: accel,
                                     reverseVertical: profile.reverseVertical,
                                     reverseHorizontal: profile.reverseHorizontal)
        case .constant:
            emitter.emitOnce(direction: direction, lines: lines)
            emitter.noteInput(now: clock())
            return .intercept
        case .auto:
            if autoDirection != direction || !emitter.isActive {
                emitter.beginAuto(direction: direction, lines: lines, intervalMS: autoInterval,
                                  stopAfterTicks: stopTicks, now: clock())
            } else {
                emitter.noteInput(now: clock())
            }
            autoDirection = direction
            return .intercept
        }
    }

    static func direction(axis: ScrollAxis, ticks: Double) -> ScrollDirection {
        switch axis {
        case .vertical: return ticks > 0 ? .up : .down
        case .horizontal: return ticks > 0 ? .right : .left
        }
    }

    static func scaleOutcome(axis: ScrollAxis, ticks: Double, sens: Double, accel: Double,
                             reverseVertical: Bool, reverseHorizontal: Bool) -> ScrollDisposition {
        let magnitude = Double(abs(ticks))
        let accelFactor = 1 + accel * (magnitude / accelerationReferenceTicks)
        var factor = sens * accelFactor
        if ticks < 0 { factor = -factor }
        var vertical = 1.0
        var horizontal = 1.0
        switch axis {
        case .vertical:
            if reverseVertical { factor = -factor }
            vertical = factor
        case .horizontal:
            if reverseHorizontal { factor = -factor }
            horizontal = factor
        }
        return .scale(vertical: vertical, horizontal: horizontal)
    }
}

private extension Double {
    func clamped(_ range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
```

Note on `Double.clamped`: a private file-scope extension (Phase 1's ProfileEditorView had a public one that was removed — this file's is `private` to avoid symbol collision).

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ScrollControllerTests`
Expected: PASS (10 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/ArtMouseCore/Scroll Tests/ArtMouseCoreTests/ScrollControllerTests.swift
git commit -m "Add scroll controller with modes, clamping and wheel-mode switching"
```

### Task 5: Engine — scrollTransform outcome and axis field scaling

**Files:**
- Modify: `Sources/ArtMouseCore/Engine/RouterOutcome.swift`
- Modify: `Sources/ArtMouseCore/Engine/EventTapEngine.swift`
- Modify: `Tests/ArtMouseCoreTests/EventTapEngineTests.swift`

**Interfaces:**
- Consumes: `RouterOutcome` (Task 6 Phase 1), `EventTapEngine.process`.
- Produces (exact):
  - `RouterOutcome` gains `case scrollTransform(verticalFactor: Double, horizontalFactor: Double)`.
  - `EventTapEngine.process` scroll-wheel handling: on `.scrollTransform(v, h)` the engine multiplies `.scrollWheelEventDeltaAxis1` by `v` and `.scrollWheelEventDeltaAxis2` by `h` (Double fields, no rounding) and returns the event.
- [ ] **Step 1: Write failing tests**

Append to `EventTapEngineTests`:

```swift
struct ScrollScalingRouter: EventRouting {
    func handle(_ event: InputEvent) -> RouterOutcome {
        if case .scrolled = event { return .scrollTransform(verticalFactor: 2, horizontalFactor: -1) }
        return .passThrough
    }
}

final class EventTapEngineScrollTests: XCTestCase {
    func testScrollTransformScalesAxisDeltas() {
        let tap = MockTap()
        let engine = EventTapEngine(router: ScrollScalingRouter(), tapFactory: MockTapFactory(tap: tap))
        XCTAssertTrue(engine.start())
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel: 3, 0, 0, or: [])!
        event.setDoubleValueField(.scrollWheelEventDeltaAxis2, value: 1)
        let result = tap.emit(event, type: .scrollWheel)
        XCTAssertTrue(result === event)
        XCTAssertEqual(event.getDoubleValueField(.scrollWheelEventDeltaAxis1), 6, accuracy: 1e-9)
        XCTAssertEqual(event.getDoubleValueField(.scrollWheelEventDeltaAxis2), -1, accuracy: 1e-9)
    }
}
```

(Reuse the engine-construction pattern of the existing tests — MockTap/MockTapFactory are module-visible. If the synthetic scroll event construction differs on this SDK, match the exact working form from `CGEventTranslationTests.testScrollAxis`.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter EventTapEngineScrollTests`
Expected: FAIL — `scrollTransform` case missing.

- [ ] **Step 3: Implement**

`RouterOutcome.swift`: add the case:

```swift
public enum RouterOutcome: Equatable {
    case passThrough
    case consume
    case cursorTransform(dxFactor: Double, dyFactor: Double)
    case scrollTransform(verticalFactor: Double, horizontalFactor: Double)
}
```

`EventTapEngine.process`: add an arm after `.cursorTransform`:

```swift
case .scrollTransform(let vFactor, let hFactor):
    let v = event.getDoubleValueField(.scrollWheelEventDeltaAxis1)
    let h = event.getDoubleValueField(.scrollWheelEventDeltaAxis2)
    event.setDoubleValueField(.scrollWheelEventDeltaAxis1, value: v * vFactor)
    event.setDoubleValueField(.scrollWheelEventDeltaAxis2, value: h * hFactor)
    return event
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter EventTapEngineTests`
Expected: PASS (all, including the new one).

- [ ] **Step 5: Commit**

```bash
git add Sources/ArtMouseCore/Engine Tests/ArtMouseCoreTests/EventTapEngineTests.swift
git commit -m "Add scroll axis scaling to the event engine"
```

### Task 6: Two-way scroll bindings in the router

**Files:**
- Modify: `Sources/ArtMouseCore/Engine/EventRouter.swift`
- Modify: `Tests/ArtMouseCoreTests/EventRouterTests.swift`

**Interfaces:**
- Consumes: `ScrollBinding` (Task 2), `InputEvent.scrolled`, `ActionExecuting`.
- Produces (exact):
  - Routing rule: `.scrolled(axis, ticks)` resolves a `ScrollBinding` matching (axis, direction) where direction = ticks > 0 ? up/right : down/left; matched → perform its actions (each tick fires ONCE — no internal repeat) and `.consume`; unmatched → falls through to the scroll controller (Task 8 wires it; until then `.passThrough`).
  - `EventRouter` gains defaulted params `scroll: ScrollControlling? = nil` (nil → `.passThrough`) and — deferred to Task 8 — chords. Existing constructor call sites compile unchanged.

- [ ] **Step 1: Write failing tests**

Append to `EventRouterTests`:

```swift
func testScrollBindingFiresOncePerTick() {
    let executor = RecordingExecutor()
    var settings = GlobalSettings.default
    settings.scrollBindings = [ScrollBinding(axis: .vertical, direction: .up,
                                             actions: [.mission(.missionControl, reverse: false)])]
    let router = EventRouter(settings: store(settings), executor: executor,
                             clickLock: StubClickLock(), cursor: StubCursor())
    XCTAssertEqual(router.handle(.scrolled(axis: .vertical, ticks: 1)), .consume)
    XCTAssertEqual(executor.performed.count, 1)
    // Burst: dense tick stream fires once per tick, never amplified.
    for _ in 0..<10 { _ = router.handle(.scrolled(axis: .vertical, ticks: 2)) }
    XCTAssertEqual(executor.performed.count, 11)
}

func testScrollBindingDirectionMatching() {
    let executor = RecordingExecutor()
    var settings = GlobalSettings.default
    settings.scrollBindings = [ScrollBinding(axis: .vertical, direction: .up, actions: [.none])]
    let router = EventRouter(settings: store(settings), executor: executor,
                             clickLock: StubClickLock(), cursor: StubCursor())
    XCTAssertEqual(router.handle(.scrolled(axis: .vertical, ticks: -1)), .passThrough)  // down ≠ up
    XCTAssertEqual(router.handle(.scrolled(axis: .horizontal, ticks: 1)), .passThrough) // axis ≠
}

func testUnboundScrollFallsThroughToController() {
    // No bindings, no controller (nil) → passThrough (Phase 1 behavior).
    let router = EventRouter(settings: store(.default), executor: RecordingExecutor(),
                             clickLock: StubClickLock(), cursor: StubCursor())
    XCTAssertEqual(router.handle(.scrolled(axis: .vertical, ticks: 1)), .passThrough)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter EventRouterTests`
Expected: FAIL — `scroll` param and routing missing.

- [ ] **Step 3: Implement**

`EventRouter`: add stored `private let scroll: ScrollControlling?` with init param `scroll: ScrollControlling? = nil`; replace the `.scrolled` arm:

```swift
case .scrolled(let axis, let ticks):
    return handleScroll(axis: axis, ticks: ticks)

private func handleScroll(axis: ScrollAxis, ticks: Double) -> RouterOutcome {
    if let binding = scrollBinding(axis: axis, ticks: ticks) {
        for action in binding.actions { executor.perform(action) }
        return .consume
    }
    guard let scroll = scroll else { return .passThrough }
    switch scroll.disposition(forScroll: axis, ticks: ticks) {
    case .passThrough: return .passThrough
    case .scale(let v, let h): return .scrollTransform(verticalFactor: v, horizontalFactor: h)
    case .intercept: return .consume
    }
}

private func scrollBinding(axis: ScrollAxis, ticks: Double) -> ScrollBinding? {
    let direction: ScrollDirection
    switch axis {
    case .vertical: direction = ticks > 0 ? .up : .down
    case .horizontal: direction = ticks > 0 ? .right : .left
    }
    return settings.settings.scrollBindings.first { $0.axis == axis && $0.direction == direction && !$0.actions.isEmpty }
}
```

Note: `GlobalSettings` gains `ScrollDirection`/`ScrollBinding` visibility here via Task 2. `.none` actions in a binding still consume (explicit user intent) — the empty-actions filter matches Phase 1's zombie-binding fix.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter EventRouterTests`
Expected: PASS (all, including 3 new).

- [ ] **Step 5: Commit**

```bash
git add Sources/ArtMouseCore/Engine/EventRouter.swift Tests/ArtMouseCoreTests/EventRouterTests.swift
git commit -m "Add two-way scroll bindings to the router"
```

### Task 7: ChordEngine — multi-button FSM

**Files:**
- Create: `Sources/ArtMouseCore/Engine/ChordEngine.swift`
- Create: `Tests/ArtMouseCoreTests/ChordEngineTests.swift`

**Interfaces:**
- Consumes: `Chord` (Task 2), `SettingsStore`, `ButtonID`.
- Produces (exact):
  - `enum ChordDecision: Equatable { case route; case consume; case fire([Action]); case flush([ButtonID]) }`
  - `protocol ChordCoordinating: AnyObject { func intercept(_ event: InputEvent, now: Double) -> ChordDecision }`
  - `final class ChordEngine: ChordCoordinating { init(settings: SettingsStore, clock: @escaping () -> Double = { Date().timeIntervalSince1970 }) }`
  - FSM contract (pinned by tests; timeout is LAZY — evaluated on every intercept, no timer):
    - idle, `.buttonDown(b)`: b is `buttons[0]` of at least one chord → capture (timeout = max candidate timeout) → `.consume`; else `.route`. Non-down events → `.route`.
    - capturing, `.buttonDown(b)`: b already held → `.consume`. `held + b` completes a chord (set equality) → perform decision `.fire(actions)`, capture → nil. `held + b` is a subset of some chord → extend → `.consume`. Extends nothing → capture → nil, return `.flush(held)` (Task 8's router performs the flush then RE-SENDS the triggering down through intercept once — it then routes/fires fresh).
    - capturing, `.buttonUp(b)`: b not held → `.route`. b == first and held.count == 1 → capture → nil, `.flush(held)` (solo release fires its own binding). Otherwise remove b → `.consume` (a 3+-button chord keeps capturing).
    - capturing, timeout exceeded (`now - start > timeout`) on ANY intercept → capture → nil, `.flush(held)` (router re-sends the triggering event).
    - After a chord fires, the chord buttons' ups pass through (idle → route; bindings act on downs only).
  - ChordEngine never performs actions itself — `.fire`/`.flush` decisions are executed by the router (Task 8).

- [ ] **Step 1: Write failing tests**

`Tests/ArtMouseCoreTests/ChordEngineTests.swift`:

```swift
import XCTest
@testable import ArtMouseCore

final class ChordEngineTests: XCTestCase {
    private let executor = RecordingExecutor()   // present only to prove ChordEngine never performs

    private func makeEngine(_ chords: [Chord]) -> ChordEngine {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = SettingsStore(directory: dir)
        store.settings.chords = chords
        return ChordEngine(settings: store)
    }

    func testChordStartButtonCapturesAndCompletes() {
        let engine = makeEngine([Chord(buttons: [.middle, .fourth], actions: [.none])])
        XCTAssertEqual(engine.intercept(.buttonDown(.middle), now: 0), .consume)
        XCTAssertEqual(engine.intercept(.buttonDown(.fourth), now: 0.05), .fire([.none]))
        XCTAssertTrue(executor.performed.isEmpty)   // router executes, not the engine
    }

    func testNonChordButtonRoutes() {
        let engine = makeEngine([Chord(buttons: [.middle, .fourth], actions: [.none])])
        XCTAssertEqual(engine.intercept(.buttonDown(.fifth), now: 0), .route)
    }

    func testSoloReleaseFlushes() {
        let engine = makeEngine([Chord(buttons: [.middle, .fourth], actions: [.click(.left, [])])])
        XCTAssertEqual(engine.intercept(.buttonDown(.middle), now: 0), .consume)
        XCTAssertEqual(engine.intercept(.buttonUp(.middle), now: 0.05), .flush([.middle]))
    }

    func testTimeoutFlushesOnNextEvent() {
        let engine = makeEngine([Chord(buttons: [.middle, .fourth],
                                       actions: [.click(.left, [])], timeout: 0.3)])
        XCTAssertEqual(engine.intercept(.buttonDown(.middle), now: 0), .consume)
        XCTAssertEqual(engine.intercept(.buttonDown(.fifth), now: 0.35), .flush([.middle]))
        // Router re-sends after flushing; fresh capture works again:
        XCTAssertEqual(engine.intercept(.buttonDown(.middle), now: 0.36), .consume)
    }

    func testSubsetExtendsThenCompletes() {
        let engine = makeEngine([Chord(buttons: [.middle, .fourth, .fifth], actions: [.none])])
        XCTAssertEqual(engine.intercept(.buttonDown(.middle), now: 0), .consume)
        XCTAssertEqual(engine.intercept(.buttonDown(.fourth), now: 0.05), .consume)   // subset extends
        XCTAssertEqual(engine.intercept(.buttonDown(.fifth), now: 0.10), .fire([.none]))  // completes
    }

    func testLongestCandidateChordTimeoutGoverns() {
        let engine = makeEngine([Chord(buttons: [.middle, .fourth], actions: [.none], timeout: 0.2),
                                 Chord(buttons: [.middle, .fourth, .fifth], actions: [.none], timeout: 0.6)])
        XCTAssertEqual(engine.intercept(.buttonDown(.middle), now: 0), .consume)
        XCTAssertEqual(engine.intercept(.buttonDown(.fourth), now: 0.05), .consume)
        // The 3-button candidate's 0.6 timeout governs while it remains completable.
        XCTAssertEqual(engine.intercept(.buttonDown(.fifth), now: 0.5), .fire([.none]))
    }

    func testUpsAfterFiredChordRoute() {
        let engine = makeEngine([Chord(buttons: [.middle, .fourth], actions: [.none])])
        _ = engine.intercept(.buttonDown(.middle), now: 0)
        _ = engine.intercept(.buttonDown(.fourth), now: 0.05)
        XCTAssertEqual(engine.intercept(.buttonUp(.middle), now: 0.1), .route)
        XCTAssertEqual(engine.intercept(.buttonUp(.fourth), now: 0.12), .route)
    }

    func testPartialReleaseOfThreeButtonChord() {
        let engine = makeEngine([Chord(buttons: [.middle, .fourth, .fifth], actions: [.none], timeout: 1.0)])
        XCTAssertEqual(engine.intercept(.buttonDown(.middle), now: 0), .consume)
        XCTAssertEqual(engine.intercept(.buttonDown(.fourth), now: 0.05), .consume)
        XCTAssertEqual(engine.intercept(.buttonUp(.fourth), now: 0.10), .consume)   // release one: capture continues
        XCTAssertEqual(engine.intercept(.buttonDown(.fourth), now: 0.15), .consume) // re-press re-extends
        XCTAssertEqual(engine.intercept(.buttonDown(.fifth), now: 0.20), .fire([.none]))
    }

    func testRePressOfHeldButtonConsumes() {
        let engine = makeEngine([Chord(buttons: [.middle, .fourth], actions: [.none], timeout: 1.0)])
        XCTAssertEqual(engine.intercept(.buttonDown(.middle), now: 0), .consume)
        XCTAssertEqual(engine.intercept(.buttonDown(.middle), now: 0.05), .consume)  // already held
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ChordEngineTests`
Expected: FAIL — types not defined.

- [ ] **Step 3: Write ChordEngine.swift**

```swift
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
        if let chord = completingChord(for: extended) {
            let actions = chord.actions
            self.capture = nil
            return .fire(actions)
        }
        if extendsSomeChord(for: extended) {
            capture.held = extended
            self.capture = capture
            return .consume
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

    private func extendsSomeChord(for held: [ButtonID]) -> Bool {
        let set = Set(held)
        return settings.settings.chords.contains { Set($0.buttons).isSuperset(of: set) }
    }
}
```

Note: `ButtonID` is Hashable (Phase 1) — `Set<ButtonID>` matching treats chord buttons as combinations; `buttons[0]` remains the required initiator. `clock` is stored for signature stability and the Task 8 re-send path; it is not read by this file's FSM directly beyond that (if the compiler flags it unused, prefix with `_ = clock()` in `intercept`'s entry or keep for Task 8's logging — do NOT remove the parameter; Task 8's router re-send calls `intercept(event, now: clock())` through the router's own clock).

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ChordEngineTests`
Expected: PASS (9 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/ArtMouseCore/Engine/ChordEngine.swift Tests/ArtMouseCoreTests/ChordEngineTests.swift
git commit -m "Add chord engine state machine"
```

### Task 8: Router + bootstrap integration — chords, scroll controller, wheel-mode switching

**Files:**
- Modify: `Sources/ArtMouseCore/Engine/EventRouter.swift`
- Modify: `Sources/ArtMouseCore/Actions/ActionExecutor.swift`
- Modify: `Sources/artMouse/EngineBootstrap.swift`
- Create: `Tests/ArtMouseCoreTests/WheelModeSwitchingTests.swift`
- Modify: `Tests/ArtMouseCoreTests/EventRouterTests.swift`

**Interfaces:**
- Consumes: everything from Tasks 1–7.
- Produces (exact):
  - `EventRouter` gains defaulted `chords: ChordCoordinating? = nil` and a non-optional-behavior scroll path: full init `init(settings:executor:clickLock:cursor:scroll:chords:)`.
  - Button path order: chord intercept FIRST → `.route` continues to binding resolution; `.consume` → consume; `.fire(actions)` → perform each → consume; `.flush(buttons)` → perform each button's NORMAL binding down (binding resolution, not chords) → re-send the triggering event through `chords.intercept(event, now:)` ONCE (guard: only immediately after a flush) → apply that decision (route → normal resolution / consume / fire).
  - Executor gains `protocol WheelModeSwitching: AnyObject { func activateNextWheelMode() }` (in CursorController.swift's file family — place next to `CursorCoordinating`), weak `wheel: WheelModeSwitching? = nil` init param; `.device(.switchWheelMode)` → `wheel?.activateNextWheelMode()` (this op becomes LIVE in this task — Task 10 re-enables it in the Device action editor UI).
  - `ActionExecutor.perform` gains the `.scroll` arm: `case .scroll(let spec)` posts ONE scroll event through the executor's OWN tagged poster (direction.sign × spec.lines on the direction's axis, `spec.mods` as CGEventFlags). `continuous` is stored for Phase 3's hold-routing; the UI shows a "hold-to-repeat arrives in Phase 3" caption.
  - `EngineBootstrap.start(store:)`: construct `ScrollEmitter(poster:)`, `ScrollController(store:emitter:)`, `ChordEngine(settings:)`; wire the router with `scroll: scrollController, chords: chordEngine`; add an 8 ms `Timer` on the main run loop in `.common` mode calling `scrollController.pumpEmitter()`; pass `wheel: scrollController` to the executor.

- [ ] **Step 1: Write failing tests**

`Tests/ArtMouseCoreTests/WheelModeSwitchingTests.swift`:

```swift
import XCTest
@testable import ArtMouseCore

final class WheelModeSwitchingTests: XCTestCase {
    func testDeviceOpSwitchWheelModeActivatesNext() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = SettingsStore(directory: dir)
        let a = WheelModeProfile(name: "A")
        let b = WheelModeProfile(name: "B")
        store.settings.wheelModeProfiles = [a, b]
        let controller = ScrollController(store: store, emitter: ScrollEmitter(poster: RecordingPoster()))
        let executor = ActionExecutor(poster: RecordingPoster(), cursor: nil, wheel: controller)

        XCTAssertEqual(store.settings.activeWheelProfile, a)   // first fallback
        executor.perform(.device(.switchWheelMode))
        XCTAssertEqual(store.settings.activeWheelProfile, b)
    }

    func testScrollActionPostsTaggedEvent() {
        let poster = CGEventPoster()
        let executor = ActionExecutor(poster: poster)
        executor.perform(.scroll(ScrollSpec(direction: .up, lines: 4)))
        XCTAssertEqual(executor.postedScrollEvents.count, 1)   // see Step 3: expose for tests
    }
}
```

Note on the second test: `CGEventPoster` tags inside `post`; to assert ownership without reaching into CGEvent internals, expose on `ActionExecutor` an internal `private(set) var postedScrollEvents: [CGEvent]` recorded in the `.scroll` arm (production behavior unchanged). Alternative: assert via `poster.owns(event)` — keep whichever compiles without new public API on CGEventPoster; the point is: the executor's `.scroll` arm posts through the SAME poster (tagged), not a fresh `CGEvent(source: nil)` path.

Router chord tests (append to `EventRouterTests`):

```swift
final class RouterChordTests: XCTestCase {
    private func makeStore(_ chords: [Chord]) -> SettingsStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = SettingsStore(directory: dir)
        store.settings.chords = chords
        return store
    }

    func testChordFirePerformsActionsAndConsumes() {
        let executor = RecordingExecutor()
        let chord = Chord(buttons: [.middle, .fourth], actions: [.mission(.missionControl, reverse: false)])
        let engine = ChordEngine(settings: makeStore([chord]))
        let router = EventRouter(settings: store(GlobalSettings.default), executor: executor,
                                 clickLock: StubClickLock(), cursor: StubCursor(), chords: engine)
        XCTAssertEqual(router.handle(.buttonDown(.middle)), .consume)   // captured
        XCTAssertTrue(executor.performed.isEmpty)
        XCTAssertEqual(router.handle(.buttonDown(.fourth)), .consume)   // fired
        XCTAssertEqual(executor.performed, [.mission(.missionControl, reverse: false)])
    }

    func testChordFlushPerformsNormalBindingsThenReSends() {
        let executor = RecordingExecutor()
        var settings = GlobalSettings.default
        settings.buttonBindings = [ButtonBinding(button: .middle, actions: [.mission(.launchpad, reverse: false)])]
        let chord = Chord(buttons: [.middle, .fourth], actions: [.click(.left, [])], timeout: 0.3)
        let engine = ChordEngine(settings: makeStore([chord]))
        let router = EventRouter(settings: store(settings), executor: executor,
                                 clickLock: StubClickLock(), cursor: StubCursor(), chords: engine)
        XCTAssertEqual(router.handle(.buttonDown(.middle)), .consume)              // captured, not performed
        XCTAssertTrue(executor.performed.isEmpty)
        // Fifth extends nothing → immediate flush of held [middle]; the router
        // performs middle's normal binding, then re-sends fifth (routed,
        // unbound → nothing extra).
        XCTAssertEqual(router.handle(.buttonDown(.fifth)), .consume)
        XCTAssertEqual(executor.performed, [.mission(.launchpad, reverse: false)])
        XCTAssertEqual(executor.performed.count, 1)
    }

    func testChordStartButtonOwnBindingDeferredNotFiredDuringCapture() {
        let executor = RecordingExecutor()
        var settings = GlobalSettings.default
        settings.buttonBindings = [ButtonBinding(button: .middle, actions: [.music(.playPause, fineTune: false)])]
        let chord = Chord(buttons: [.middle, .fourth], actions: [.none], timeout: 10.0)
        let engine = ChordEngine(settings: makeStore([chord]))
        let router = EventRouter(settings: store(settings), executor: executor,
                                 clickLock: StubClickLock(), cursor: StubCursor(), chords: engine)
        XCTAssertEqual(router.handle(.buttonDown(.middle)), .consume)
        XCTAssertTrue(executor.performed.isEmpty)   // capture defers the binding
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter 'WheelModeSwitchingTests|RouterChordTests'`
Expected: FAIL — `wheel` param, `.scroll` arm, chord wiring missing.

- [ ] **Step 3: Implement**

**3a. WheelModeSwitching + executor wheel param** (protocol next to `CursorCoordinating` in `Cursor/CursorController.swift`; `ScrollController` conforms — `activateNextWheelMode` already exists):

```swift
public protocol WheelModeSwitching: AnyObject {
    func activateNextWheelMode()
}
```

`ActionExecutor`: add `private weak var wheel: WheelModeSwitching?` + defaulted init param `wheel: WheelModeSwitching? = nil`; in `performDevice`: `case .switchWheelMode: wheel?.activateNextWheelMode()` (was `break`). Remove `.switchWheelMode` from the UI-disabled list in Task 11.

**3b. Executor `.scroll` arm** in `perform`:

```swift
case .scroll(let spec):
    performScroll(spec)
```

```swift
/// Internal record for tests; no public API added.
private(set) var postedScrollEvents: [CGEvent] = []

private func performScroll(_ spec: ScrollSpec) {
    let v = spec.direction.axis == .vertical ? spec.direction.sign * spec.lines : 0
    let h = spec.direction.axis == .horizontal ? spec.direction.sign * spec.lines : 0
    let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1,
                        wheel: v, h, 0, or: [])!
    event.flags = CGFlagConversion.cgFlags(spec.mods)
    poster.post(event)
    postedScrollEvents.append(event)
}
```

(Match the working wheel-event construction from ScrollEmitter if this SDK differs.)

**3c. Router chord + scroll integration.** `EventRouter` gains `private let chords: ChordCoordinating?` (init param defaulted nil). New button-path shape:

```swift
private func handleDown(_ button: ButtonID) -> RouterOutcome {
    return handleButtonDown(button)
}

private func handleUp(_ button: ButtonID) -> RouterOutcome {
    return handleButtonUp(button)
}

private func handleButtonDown(_ button: ButtonID) -> RouterOutcome {
    if let chords = chords {
        switch chords.intercept(.buttonDown(button), now: Date().timeIntervalSince1970) {
        case .route:
            break   // continue to binding resolution below
        case .consume:
            return .consume
        case .fire(let actions):
            for action in actions { executor.perform(action) }
            return .consume
        case .flush(let flushed):
            for flushedButton in flushed { performNormalDown(flushedButton) }
            // Re-send the triggering event through intercept exactly once —
            // safe: the flush cleared the capture, so this pass routes fresh
            // and cannot re-flush.
            switch chords.intercept(.buttonDown(button), now: Date().timeIntervalSince1970) {
            case .route:
                return performNormalDown(button)
            case .consume:
                return .consume
            case .fire(let actions):
                for action in actions { executor.perform(action) }
                return .consume
            case .flush:
                return .consume   // nested flush: drop (one flush per event)
            }
        }
    }
    return performNormalDown(button)
}

/// Normal binding resolution (the Phase 1 handleDown body, chords stripped).
private func performNormalDown(_ button: ButtonID) -> RouterOutcome {
    guard let binding = binding(for: button), !binding.actions.isEmpty else { return .passThrough }
    if binding.actions.contains(where: { $0.isClickLock }) {
        if clickLock.shouldSwallowDown(button) { return .consume }
        clickLock.noteDown(button, now: Date().timeIntervalSince1970)
        return .consume
    }
    for action in binding.actions where action.isHoldAction {
        executor.beganHold(action)
        heldButtons[button] = action
        return .consume
    }
    for action in binding.actions {
        executor.perform(action)
    }
    return .consume
}
```

Mirror for `handleButtonUp`: chord intercept first — `.route` → normal up resolution (Phase 1 body incl. heldButtons/clickLock); `.consume` → consume; `.fire` → perform + consume; `.flush(buttons)` → for each flushed button perform its normal binding UP resolution (`performNormalUp`) → re-send `.buttonUp` once → apply. `performNormalUp` is the Phase 1 `handleUp` body. IMPORTANT subtlety: chord ups during capture consume (Task 7 contract) so a capture button's normal up never runs mid-capture; after flush the re-sent event's up runs normally on release. The Phase 1 `clickLock` and `heldButtons` logic moves VERBATIM into `performNormalDown/Up` — do not re-order their internals.

`.scrolled` arm already routes via `scroll` (Task 6) — Task 8's bootstrap passes the real controller. Nothing new here beyond construction.

**3d. Bootstrap wiring.** In `EngineBootstrap.start(store:)`:

```swift
let emitter = ScrollEmitter(poster: poster)   // poster is the shared CGEventPoster instance
let scrollController = ScrollController(store: store, emitter: emitter)
let chordEngine = ChordEngine(settings: store)
let executor = ActionExecutor(poster: poster, cursor: cursorController, wheel: scrollController)
let router = EventRouter(settings: store, executor: executor,
                         clickLock: clickLock, cursor: cursorController,
                         scroll: scrollController, chords: chordEngine)
// …tap engine as before…
emitterDriver = Timer.scheduledTimer(withTimeInterval: 0.008, repeats: true) { [weak scrollController] _ in
    scrollController?.pumpEmitter()
}
RunLoop.main.add(emitterDriver!, forMode: .common)
```

(`emitterDriver` is a new stored `Timer?`; existing timers untouched; all main-run-loop `.common` per the discipline. `ScrollController` is NOT @MainActor-annotated in ArtMouseCore — the calling discipline comment in EngineBootstrap covers it; extend the comment to name scroll/chord state.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: full suite green (previous + ~9 new tests). EventRouterTests' existing constructor call sites compile unchanged (defaulted params).

- [ ] **Step 5: Commit**

```bash
git add Sources Tests/ArtMouseCoreTests
git commit -m "Integrate chords, scroll controller and wheel-mode switching"
```

### Task 9: Wheel tab UI — scroll modes, params, wheel-mode profiles

**Files:**
- Create: `Sources/artMouse/Views/WheelTabView.swift`, `Sources/artMouse/Views/WheelProfileEditorView.swift`, `Sources/artMouse/Views/WheelKeysEditorView.swift`
- Modify: `Sources/artMouse/AppModel.swift`
- Modify: `Sources/artMouse/Views/SettingsWindow.swift` (add the Wheel tab)
- Modify: `Sources/artMouse/EngineBootstrap.swift` (noop — verify safety banner still wired; no change expected)

**Interfaces:**
- Consumes: `WheelModeProfile`, `WheelKeyEmulation`, `ScrollMode`, `AppModel` (Phase 1 patterns), `SettingsWindow(model:safetyBootstrap:)`.
- Produces (exact): `AppModel` gains `addWheelProfile()`, `removeWheelProfile(_ id: UUID)`, `updateWheelProfile(_ profile: WheelModeProfile)`, `setActiveWheelProfile(_ id: UUID)` — the exact Phase-1 cursor-profile pattern (removeProfile guards never-zero via `count > 1`, clears the active ID when pointing at the removed profile, every mutation saves immediately).

- [ ] **Step 1: Implement AppModel wheel-profile methods**

```swift
func addWheelProfile() {
    var settings = store.settings
    settings.wheelModeProfiles.append(
        WheelModeProfile(name: "Profile \(settings.wheelModeProfiles.count + 1)"))
    store.settings = settings
    save()
}

func removeWheelProfile(_ id: UUID) {
    var settings = store.settings
    guard settings.wheelModeProfiles.count > 1 else { return }
    settings.wheelModeProfiles.removeAll { $0.id == id }
    if settings.activeWheelModeProfileID == id { settings.activeWheelModeProfileID = nil }
    store.settings = settings
    save()
}

func updateWheelProfile(_ profile: WheelModeProfile) {
    var settings = store.settings
    if let index = settings.wheelModeProfiles.firstIndex(where: { $0.id == profile.id }) {
        settings.wheelModeProfiles[index] = profile
    }
    store.settings = settings
    save()
}

func setActiveWheelProfile(_ id: UUID) {
    store.settings.activeWheelModeProfileID = id
    save()
}
```

- [ ] **Step 2: Write the views**

`WheelTabView.swift` (mirrors CursorTabView's structure exactly — profiles list + active selection):

```swift
import SwiftUI
import ArtMouseCore

struct WheelTabView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Wheel mode profiles").font(.headline)
                Spacer()
                Button("Add Profile") { model.addWheelProfile() }
            }
            List(model.settings.wheelModeProfiles) { profile in
                WheelProfileEditorView(
                    profile: profile,
                    isActive: profile.id == model.settings.activeWheelProfile?.id,
                    onUpdate: { model.updateWheelProfile($0) },
                    onDelete: { model.removeWheelProfile($0.id) },
                    onActivate: { model.setActiveWheelProfile($0.id) })
            }
            Text("Sens multiplies wheel distance; Acceleration adds distance on fast rolls. Constant mode scrolls a fixed amount per notch; Auto keeps scrolling after a roll and stops after N notches of silence. Smooth spreads each notch into small steps. Keys sends a keystroke instead of scrolling.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
```

`WheelProfileEditorView.swift` (derive-from-props — NO `@State`):

```swift
import SwiftUI
import ArtMouseCore

struct WheelProfileEditorView: View {
    let profile: WheelModeProfile
    let isActive: Bool
    let onUpdate: (WheelModeProfile) -> Void
    let onDelete: (WheelModeProfile) -> Void
    let onActivate: (WheelModeProfile) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                TextField("Name", text: Binding(
                    get: { profile.name },
                    set: { onUpdate(copy(name: $0)) }))
                    .frame(width: 110)

                Picker("", selection: Binding(
                    get: { profile.mode },
                    set: { onUpdate(copy(mode: $0)) })) {
                    Text("Acceleration").tag(ScrollMode.acceleration)
                    Text("Constant").tag(ScrollMode.constant)
                    Text("Auto").tag(ScrollMode.auto)
                }
                .labelsHidden()
                .frame(width: 130)

                numericField("Sens", value: profile.sensFactor) { onUpdate(copy(sensFactor: $0)) }
                numericField("Accel", value: profile.acceleration) { onUpdate(copy(acceleration: $0)) }
                numericField("Lines", value: profile.lines) { onUpdate(copy(lines: $0)) }

                Button(isActive ? "Active" : "Use") { onActivate(profile) }
                    .disabled(isActive)
                Toggle("Reverse V", isOn: Binding(
                    get: { profile.reverseVertical },
                    set: { onUpdate(copy(reverseVertical: $0)) }))
                    .toggleStyle(.checkbox)
                Toggle("Reverse H", isOn: Binding(
                    get: { profile.reverseHorizontal },
                    set: { onUpdate(copy(reverseHorizontal: $0)) }))
                    .toggleStyle(.checkbox)
                Spacer()
                Button(role: .destructive) { onDelete(profile) } label: { Image(systemName: "trash") }
                    .disabled(isActive)
            }
            HStack(spacing: 12) {
                Toggle("Smooth Scroll", isOn: Binding(
                    get: { profile.smoothScroll },
                    set: { onUpdate(copy(smoothScroll: $0)) }))
                    .toggleStyle(.checkbox)
                if profile.smoothScroll {
                    numericField("Smooth step (ms)", value: Double(profile.smoothIntervalMS)) {
                        onUpdate(copy(smoothIntervalMS: Int($0)))
                    }
                }
                if profile.mode == .constant || profile.mode == .auto {
                    numericField("Interval (ms)", value: Double(profile.intervalMS)) {
                        onUpdate(copy(intervalMS: Int($0)))
                    }
                }
                if profile.mode == .auto {
                    numericField("Auto interval (ms)", value: Double(profile.autoIntervalMS)) {
                        onUpdate(copy(autoIntervalMS: Int($0)))
                    }
                    numericField("Auto stop (notches)", value: Double(profile.autoStopTicks)) {
                        onUpdate(copy(autoStopTicks: Int($0)))
                    }
                }
                WheelKeysEditorView(emulation: profile.keyEmulation) {
                    onUpdate(copy(keyEmulation: $0))
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func numericField(_ title: String, value: Double,
                              onChange: @escaping (Double) -> Void) -> some View {
        LabeledContent(title) {
            TextField("", value: Binding(
                get: { value },
                set: { onChange($0) }), format: .number)
                .frame(width: 60)
        }
        .frame(width: fieldWidth(title))
    }

    private func fieldWidth(_ title: String) -> CGFloat {
        switch title {
        case "Sens", "Accel", "Lines": return 120
        default: return 170
        }
    }

    // copy() helpers — one per mutated field, mirroring Phase 1's profileWithName pattern:
    private func copy(name: String) -> WheelModeProfile { var c = profile; c.name = name; return c }
    private func copy(mode: ScrollMode) -> WheelModeProfile { var c = profile; c.mode = mode; return c }
    private func copy(sensFactor: Double) -> WheelModeProfile { var c = profile; c.sensFactor = sensFactor; return c }
    private func copy(acceleration: Double) -> WheelModeProfile { var c = profile; c.acceleration = acceleration; return c }
    private func copy(lines: Double) -> WheelModeProfile { var c = profile; c.lines = lines; return c }
    private func copy(intervalMS: Int) -> WheelModeProfile { var c = profile; c.intervalMS = intervalMS; return c }
    private func copy(reverseVertical: Bool) -> WheelModeProfile { var c = profile; c.reverseVertical = reverseVertical; return c }
    private func copy(reverseHorizontal: Bool) -> WheelModeProfile { var c = profile; c.reverseHorizontal = reverseHorizontal; return c }
    private func copy(smoothScroll: Bool) -> WheelModeProfile { var c = profile; c.smoothScroll = smoothScroll; return c }
    private func copy(smoothIntervalMS: Int) -> WheelModeProfile { var c = profile; c.smoothIntervalMS = smoothIntervalMS; return c }
    private func copy(autoIntervalMS: Int) -> WheelModeProfile { var c = profile; c.autoIntervalMS = autoIntervalMS; return c }
    private func copy(autoStopTicks: Int) -> WheelModeProfile { var c = profile; c.autoStopTicks = autoStopTicks; return c }
    private func copy(keyEmulation: WheelKeyEmulation?) -> WheelModeProfile { var c = profile; c.keyEmulation = keyEmulation; return c }
}

```

Clamp placement (Phase 1 lesson): the numeric fields use IDENTITY bindings — what you type is what the editor shows; `ScrollController` clamps at consumption (Task 4), so out-of-range values can never run the engine away. The `numericField` helper takes no range parameter.

`WheelKeysEditorView.swift` (own file; derive-from-props; nil = off):

```swift
import SwiftUI
import ArtMouseCore

struct WheelKeysEditorView: View {
    let emulation: WheelKeyEmulation?
    let onChange: (WheelKeyEmulation?) -> Void

    var body: some View {
        Toggle("Wheel sends keys", isOn: Binding(
            get: { emulation != nil },
            set: { on -> Void in
                onChange(on ? WheelKeyEmulation(keyCode: 40) : nil)   // 40 = "k" placeholder; field below edits it
            }))
            .toggleStyle(.checkbox)
        if let emulation {
            TextField("Key code", value: Binding(
                get: { Double(emulation.keyCode) },
                set: { onChange(WheelKeyEmulation(keyCode: UInt64(max(0, $0)), mods: emulation.mods,
                                                  repeatWhileRolling: emulation.repeatWhileRolling)) }),
                format: .number)
                .frame(width: 70)
            Toggle("Repeat", isOn: Binding(
                get: { emulation.repeatWhileRolling },
                set: { onChange(WheelKeyEmulation(keyCode: emulation.keyCode, mods: emulation.mods,
                                                  repeatWhileRolling: $0)) }))
                .toggleStyle(.checkbox)
        }
    }
}
```

`SettingsWindow.swift`: add `.tabItem { Text("Wheel") }` hosting `WheelTabView(model: model)` after Buttons.

- [ ] **Step 3: Build + smoke**

Run: `swift build` clean; `swift test` full suite green; `./Scripts/make_app.sh && open build/artMouse.app` → pid stable 5 s → pkill. Visual pass remains Task 12.

- [ ] **Step 4: Commit**

```bash
git add Sources/artMouse
git commit -m "Add wheel mode profiles UI"
```

### Task 10: Scroll action editor + two-way scroll bindings UI

**Files:**
- Create: `Sources/artMouse/Views/ScrollActionEditorView.swift`, `Sources/artMouse/Views/ScrollBindingsTabView.swift`, `Sources/artMouse/Views/ScrollBindingRowView.swift`
- Modify: `Sources/artMouse/Views/ActionEditorView.swift` (ActionCategory gains `.scroll`)
- Modify: `Sources/artMouse/Views/DeviceActionEditorView.swift` (enable Switch Wheel Mode)
- Modify: `Sources/artMouse/AppModel.swift`
- Modify: `Sources/artMouse/Views/SettingsWindow.swift` (add the "Scroll Bindings" tab)

**Interfaces:**
- Consumes: `ScrollSpec`, `ScrollDirection`, `ScrollBinding`, `ActionCategory` (Phase 1).
- Produces (exact): `ActionCategory.scroll` case (label "Scroll", initialAction `.scroll(ScrollSpec(direction: .up))`); `AppModel.setScrollBinding(axis:direction:action:)` + `scrollBinding(for:direction:)` (mirror setBinding/binding); the Buttons tab's editor dispatch gains `case .scroll(let spec): ScrollActionEditorView(spec: spec, onChange: onChange)`.

- [ ] **Step 1: AppModel scroll-binding methods**

```swift
func setScrollBinding(axis: ScrollAxis, direction: ScrollDirection, action: Action?) {
    var settings = store.settings
    if let index = settings.scrollBindings.firstIndex(where: { $0.axis == axis && $0.direction == direction }) {
        settings.scrollBindings[index].actions = action.map { [$0] } ?? []
    } else if let action {
        settings.scrollBindings.append(ScrollBinding(axis: axis, direction: direction, actions: [action]))
    }
    store.settings = settings
    save()
}

func scrollBinding(axis: ScrollAxis, direction: ScrollDirection) -> ScrollBinding? {
    store.settings.scrollBindings.first { $0.axis == axis && $0.direction == direction }
}
```

(Empty actions are retained as explicit "bound but none" markers in the UI list — the ROUTER filters them, Phase-1 zombie fix; the UI shows them as "No Action" rows and lets the user delete via a Clear button that removes the binding entirely: add `removeScrollBinding(axis:direction:)`.)

```swift
func removeScrollBinding(axis: ScrollAxis, direction: ScrollDirection) {
    var settings = store.settings
    settings.scrollBindings.removeAll { $0.axis == axis && $0.direction == direction }
    store.settings = settings
    save()
}
```

- [ ] **Step 2: ActionCategory.scroll + ScrollActionEditorView**

`ActionEditorView.swift`: add `.scroll` to `ActionCategory` (allCases, label "Scroll", init case, `initialAction: .scroll(ScrollSpec(direction: .up))`) and the dispatch case `case .scroll(let spec): ScrollActionEditorView(spec: spec, onChange: onChange)`.

`ScrollActionEditorView.swift`:

```swift
import SwiftUI
import ArtMouseCore

struct ScrollActionEditorView: View {
    let spec: ScrollSpec
    let onChange: (Action?) -> Void

    var body: some View {
        HStack {
            Picker("", selection: Binding(
                get: { spec.direction },
                set: { onChange(.scroll(ScrollSpec(direction: $0, mods: spec.mods,
                                                   lines: spec.lines, intervalMS: spec.intervalMS,
                                                   continuous: spec.continuous))) })) {
                ForEach(ScrollDirection.allCases, id: \.self) { d in
                    Text(label(d)).tag(d)
                }
            }
            .labelsHidden()
            .frame(width: 110)
            LabeledContent("Lines") {
                TextField("", value: Binding(
                    get: { spec.lines },
                    set: { onChange(.scroll(ScrollSpec(direction: spec.direction, mods: spec.mods,
                                                       lines: $0, intervalMS: spec.intervalMS,
                                                       continuous: spec.continuous))) }), format: .number)
                    .frame(width: 60)
            }
            .frame(width: 110)
            Text("Hold-to-repeat arrives in Phase 3")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func label(_ d: ScrollDirection) -> String {
        switch d {
        case .up: return "Scroll Up"
        case .down: return "Scroll Down"
        case .left: return "Scroll Left"
        case .right: return "Scroll Right"
        }
    }
}
```

(`continuous` is stored but unrouted until Phase 3; the caption replaces a control so no dead UI ships.)

- [ ] **Step 3: ScrollBindingsTabView + row**

`ScrollBindingsTabView.swift`:

```swift
import SwiftUI
import ArtMouseCore

struct ScrollBindingsTabView: View {
    let model: AppModel

    private var rows: [(label: String, axis: ScrollAxis, direction: ScrollDirection)] {
        [("Wheel Up", .vertical, .up), ("Wheel Down", .vertical, .down),
         ("Wheel Left", .horizontal, .left), ("Wheel Right", .horizontal, .right)]
    }

    var body: some View {
        List(rows, id: \.label) { row in
            ScrollBindingRowView(model: model, label: row.label,
                                 axis: row.axis, direction: row.direction)
        }
    }
}
```

`ScrollBindingRowView.swift`:

```swift
import SwiftUI
import ArtMouseCore

struct ScrollBindingRowView: View {
    let model: AppModel
    let label: String
    let axis: ScrollAxis
    let direction: ScrollDirection

    var body: some View {
        HStack(alignment: .top) {
            Text(label).frame(width: 110, alignment: .leading).font(.body.weight(.medium))
            ActionEditorView(action: currentAction) { newAction in
                model.setScrollBinding(axis: axis, direction: direction, action: newAction)
            }
            Button("Clear") { model.removeScrollBinding(axis: axis, direction: direction) }
                .disabled(model.scrollBinding(axis: axis, direction: direction) == nil)
        }
        .padding(.vertical, 4)
    }

    private var currentAction: Action? {
        model.scrollBinding(axis: axis, direction: direction)?.actions.first
    }
}
```

Wire into `SettingsWindow` as tab "Scroll Bindings" after Wheel.

Also in this step — re-enable the now-live wheel-mode op: `Sources/artMouse/Views/DeviceActionEditorView.swift` — remove `.disabled(true)` and the `// phase 2` comment from the `Text("Switch Wheel Mode")` tag row only (DPI rows stay disabled for Phase 4).

- [ ] **Step 4: Build + smoke + commit**

`swift build` clean; `swift test` green; bundle smoke (open, pid stable, pkill).

```bash
git add Sources/artMouse
git commit -m "Add scroll action and two-way scroll bindings UI"
```

### Task 11: Chords tab UI

**Files:**
- Create: `Sources/artMouse/Views/ChordsTabView.swift`, `Sources/artMouse/Views/ChordEditorView.swift`
- Modify: `Sources/artMouse/AppModel.swift`
- Modify: `Sources/artMouse/Views/SettingsWindow.swift` (add the Chords tab)

**Interfaces:**
- Produces (exact): `AppModel.addChord()`, `updateChord(_ chord: Chord)`, `removeChord(_ id: UUID)` — add appends `Chord(buttons: [.middle, .fourth], actions: [])` seeded; update saves; remove deletes and saves.

- [ ] **Step 1: AppModel chord methods**

```swift
func addChord() {
    var settings = store.settings
    settings.chords.append(Chord(buttons: [.middle, .fourth], actions: []))
    store.settings = settings
    save()
}

func updateChord(_ chord: Chord) {
    var settings = store.settings
    if let index = settings.chords.firstIndex(where: { $0.id == chord.id }) {
        settings.chords[index] = chord
    }
    store.settings = settings
    save()
}

func removeChord(_ id: UUID) {
    var settings = store.settings
    settings.chords.removeAll { $0.id == id }
    store.settings = settings
    save()
}
```

- [ ] **Step 2: ChordsTabView + ChordEditorView**

`ChordsTabView.swift`:

```swift
import SwiftUI
import ArtMouseCore

struct ChordsTabView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Button chords").font(.headline)
                Spacer()
                Button("Add Chord") { model.addChord() }
            }
            List(model.settings.chords) { chord in
                ChordEditorView(chord: chord,
                                onUpdate: { model.updateChord($0) },
                                onDelete: { model.removeChord($0.id) })
            }
            Text("Press the first button, then the rest within the timeout. While a chord is possible, the first button's own binding is deferred; releasing it alone fires its normal binding.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
```

`ChordEditorView.swift` (derive-from-props; button set edited as toggle rows over the 5 standard buttons; actions via a compact action picker — reuse `ActionEditorView` with the chord's first action; multi-action chords are a Phase 3 refinement, v1 stores `[firstAction]`):

```swift
import SwiftUI
import ArtMouseCore

struct ChordEditorView: View {
    let chord: Chord
    let onUpdate: (Chord) -> Void
    let onDelete: (Chord) -> Void

    private let standardButtons: [ButtonID] = [.left, .right, .middle, .fourth, .fifth]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ForEach(standardButtons, id: \.self) { button in
                    Toggle(label(button), isOn: Binding(
                        get: { chord.buttons.contains(button) },
                        set: { on in updateButtons { $0.toggle(button, isOn: on) } }))
                        .toggleStyle(.checkbox)
                }
                TextField("Timeout (s)", value: Binding(
                    get: { chord.timeout },
                    set: { onUpdate(chord(timeout: max(0.05, min(2.0, $0)))) }), format: .number)
                    .frame(width: 90)
                Spacer()
                Button(role: .destructive) { onDelete(chord) } label: { Image(systemName: "trash") }
            }
            HStack {
                Text("Action:").font(.caption)
                ActionEditorView(action: chord.actions.first) { newAction in
                    onUpdate(chord(actions: newAction.map { [$0] } ?? []))
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func label(_ button: ButtonID) -> String {
        switch button {
        case .left: return "L"
        case .right: return "R"
        case .middle: return "M"
        case .fourth: return "4"
        case .fifth: return "5"
        case .extended(let n): return "+\(n + 1)"
        }
    }

    private func updateButtons(_ mutate: (inout [ButtonID]) -> Void) {
        var buttons = chord.buttons
        // buttons[0] stays the initiator unless it was toggled off: promote the next.
        mutate(&buttons)
        if buttons.isEmpty { buttons = chord.buttons }   // never empty
        onUpdate(chord(buttons: buttons))
    }
}

private extension Array where Element == ButtonID {
    mutating func toggle(_ button: ButtonID, isOn: Bool) {
        if isOn {
            if !contains(button) { append(button) }
        } else {
            removeAll { $0 == button }
        }
    }
}
```

(`chord(buttons:)`/`chord(actions:)`/`chord(timeout:)` are local copy helpers as in Phase 1's editors — write them.) The toggle order defines the array order; the FIRST element is the initiator — add a caption `Text("First checked button initiates.")` under the toggles.

- [ ] **Step 3: Build + smoke + commit**

`swift build` clean; `swift test` green; bundle smoke.

```bash
git add Sources/artMouse
git commit -m "Add chords UI"
```

### Task 12: Phase 2 verification checklist

**Files:**
- Create: `docs/verification/phase-2.md`

**Interfaces:**
- Consumes: the completed app.
- Produces: the recorded manual verification list (spec §8 pattern).

- [ ] **Step 1: Run the full automated suite**

Run: `swift test` — expect 88 prior + ~25 new ≈ 113 tests, 0 failures. Fix anything red with separate bug-fix commits before the manual steps.

- [ ] **Step 2: Automatable checks** (record evidence in the doc)

- App launches and stays alive (normal + `--safe-mode`, `ps` flag check, pkill cleanup) — same commands as Phase 1's doc.
- **Phase-1 settings survival (Review Focus 1):** with a real Phase-1 `settings.json` present (bindings/profiles from actual use), launch → verify via the Settings UI (System Events AX read like Phase 1's Task 19) that the Buttons tab still shows the Phase-1 bindings AND a Wheel tab exists with a "Default" profile.
- settings.json now contains the new fields after any UI mutation (json.tool lint).

- [ ] **Step 3: Human checklist** (unchecked, HOW TO VERIFY lines)

- [ ] Grant permissions on fresh launch; banner clears.
- [ ] Reverse scrolling: enable Reverse V → wheel up scrolls content down; disable restores.
- [ ] Acceleration mode: sens 2.0 → wheel scrolls visibly farther per notch.
- [ ] Constant mode: fixed distance per notch regardless of roll speed.
- [ ] Smooth scroll: notch spreads into multiple small steps (watch a long page glide).
- [ ] Auto mode: flick and watch it continue, then stop after the configured notches of silence.
- [ ] Wheel→keys: bind a key code; rolling the wheel types the key; stop rolling releases.
- [ ] Wheel-mode switching: bind a button to Device → Switch Wheel Mode; press cycles profiles (cursor-speed profiles unaffected).
- [ ] Two-way binding: Wheel Up → Mission Control fires on up-roll only; Wheel Down unbound scrolls stock.
- [ ] Button→scroll action: bind 4th button to Scroll Down; press scrolls down.
- [ ] **Click-lock + scroll interplay regression** (Phase 1's loop protection on the new synthetic-scroll path): smooth scroll ON, click lock ON, click-and-hold — no scroll storm, no input flood.
- [ ] Chords: Middle+4th fires the chord; Middle alone (released) fires Middle's own binding; Middle held past timeout then 4th pressed late does NOT fire the chord.
- [ ] Sleep/wake: wheel features still work after wake.
- [ ] Phase-1 regression spot-check: one click binding, cursor profiles, precision hold.

- [ ] **Step 4: Commit**

```bash
git add docs/verification/phase-2.md
git commit -m "Record phase 2 verification"
```

## Summary of delivered behavior (Phase 2)

After Task 12, artMouse additionally: reshapes native wheel scrolling (acceleration/constant/auto modes, sens/accel factors, reverse V/H, smooth-scroll interpolation, wheel→keyboard emulation) via switchable wheel-mode profiles; two-way per-direction wheel bindings; button→scroll actions; multi-button chords with lazy timeouts and solo-release flush; all synthetic events tagged and loop-safe; Phase-1 settings preserved through the upgrade.
