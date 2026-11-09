# artMouse Phase 1 — Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the artMouse foundation: menu-bar app, permission flow, event-tap engine, button remapping (clicks, mission, music, zoom, switcher, open, profile-switching device ops), and cursor speed/sensitivity control with speed profiles.

**Architecture:** One always-running Swift menu-bar app hosts UI and engine. `ArtMouseCore` is a UI-free framework target containing all engine logic (testable); the `artMouse` executable target is AppKit/SwiftUI glue. `CGEventTap` intercepts standard mouse events; `EventRouter` resolves bindings from `SettingsStore` and delegates to `ActionExecutor` (button actions) and `CursorController` (move transforms). Spec §4.

**Tech Stack:** Swift 5.9, Swift Package Manager, AppKit (menu bar), SwiftUI (settings), XCTest. Zero third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-11-09-artmouse-design.md` — the plan argues from the spec; executors read both. Phase 1 implements spec §4 architecture, §5 data model (phase-1 action subset), §6 Phase 1 bullet (including AppWatcher), §7 error handling, §8 testing (phase-1 action subset), §6 Phase 1 bullet, §7 error handling, §8 testing.

## Global Constraints

- macOS 14.0 floor: `platforms: [.macOS(.v14)]`, `// swift-tools-version: 5.9`.
- Zero third-party package dependencies.
- Bundle id `app.artmouse`; app bundle assembled by `Scripts/make_app.sh` (SPM cannot emit app bundles).
- Engine logic lives only in `ArtMouseCore`; app-target files render and forward only (model layer holds decisions; small focused files; one view class per file; split any file nearing ~150 lines).
- TDD: failing test first, then minimal implementation, then green, then commit. Commits: plain imperative messages, no AI attribution trailers (never `Co-Authored-By`).
- Test command: `swift test --filter <Name>` from repo root. Build: `swift build`.
- Phase-1 action subset (later phases extend the enums; do not implement ahead): `Action` cases `.none, .click, .mission, .music, .zoom, .switcher, .open, .device`. No scroll/macro/snapping cases yet.
- Deferred ops are declared but the executor reports them unavailable (UI shows them disabled) — do NOT silently accept them: `ZoomOp.pinchIn/.pinchOut/.smartZoom`, `MissionOp.notificationCenter/.siri`, `SwitcherOp.showSwitcher`, `DeviceOp.dpi*`, `.switchWheelMode` (phases 2–4).

## Review Focus

Failure modes the spec implies that unit tests below do not fully exercise. Each line's pinning verification lives in the named task.

1. **Self-lockout after an absurd cursor-speed switch** (spec §7): a button action setting sensitivity far too high must auto-restore the previous profile after 5 s with a visible warning — never leave the machine unusable. Pinned by Task 14 timer test + Task 19 manual checklist ("activate Fast profile from a button, confirm restore banner appears").
2. **Malformed settings JSON** (spec §7): a hand-edited `settings.json` with a typo must load defaults, surface a warning in the UI, and must never crash or brick the engine. Pinned by Task 4 malformed-fallback test + Task 19 manual edit check.
3. **Permission revoked while running** (spec §7): System Settings revoking Accessibility/Input Monitoring mid-run must surface the permission banner again, not a silently dead engine. Pinned by Task 15 tap-loss detection test + Task 19 manual revoke check.
4. **Safe-mode launch** (spec §7): `--safe-mode` (or holding ⌥⌘ during launch) must result in zero interception — every mouse event reaches the system untouched. Pinned by Task 15 bootstrap test + Task 19 manual launch check.
5. **Unbound extended buttons pass through untouched**: a 6+ button mouse whose extra buttons have no binding must behave exactly as without artMouse (phase 1 has no raw-HID path yet, so any observable change is a defect). Pinned by Task 7 router pass-through test + Task 19 multi-button manual check.

---

## File Structure (Phase 1)

```
artMouse/
├── Package.swift
├── Scripts/make_app.sh
├── Sources/
│   ├── ArtMouseCore/
│   │   ├── Model/
│   │   │   ├── ButtonID.swift            # physical button identity
│   │   │   ├── ModKeys.swift             # modifier OptionSet
│   │   │   ├── Action.swift              # Action + sub-op enums (phase-1 subset)
│   │   │   └── InputEvent.swift          # normalized input events
│   │   ├── Settings/
│   │   │   ├── GlobalSettings.swift      # settings + profiles + bindings models
│   │   │   └── SettingsStore.swift       # JSON persistence + malformed fallback
│   │   ├── Devices/
│   │   │   ├── HIDDeviceIdentity.swift
│   │   │   ├── HIDDeviceEnumerating.swift
│   │   │   ├── IOKitDeviceEnumerator.swift
│   │   │   └── DeviceManager.swift
│   │   ├── Engine/
│   │   │   ├── CGEventTranslation.swift  # CGEvent → InputEvent
│   │   │   ├── EventTapCreating.swift    # tap abstraction + real factory
│   │   │   ├── EventTapEngine.swift      # orchestration, re-enable on wake
│   │   │   ├── RouterOutcome.swift
│   │   │   ├── EventRouter.swift
│   │   │   ├── ClickLockCoordinator.swift
│   │   │   ├── BootstrapDecision.swift
│   │   │   └── AppWatcher.swift
│   │   ├── Actions/
│   │   │   ├── EventPosting.swift        # poster protocol + real poster
│   │   │   ├── KeyCodes.swift            # ANSI keycodes + NX media key constants
│   │   │   ├── ActionExecutor.swift      # performs Actions
│   │   │   └── MediaKeySynthesizer.swift # NX system-defined events
│   │   └── Cursor/
│   │       ├── CursorMath.swift          # pure sensitivity/acceleration math
│   │       └── CursorController.swift    # profiles, precision hold, safety restore
│   └── artMouse/
│       ├── main.swift                    # NSApplication bootstrap
│       ├── AppDelegate.swift             # menu bar item, engine bootstrap, safe mode
│       ├── PermissionsController.swift
│       ├── AppModel.swift
│       └── Views/
│           ├── SettingsWindow.swift      # window + tab host
│           ├── PermissionBannerView.swift
│           ├── ButtonsTabView.swift
│           ├── BindingRowView.swift
│           ├── ActionEditorView.swift    # dispatches to per-type editors
│           ├── ClickActionEditorView.swift
│           ├── MissionActionEditorView.swift
│           ├── MusicActionEditorView.swift
│           ├── ZoomActionEditorView.swift
│           ├── SwitcherActionEditorView.swift
│           ├── OpenActionEditorView.swift
│           ├── DeviceActionEditorView.swift
│           ├── CursorTabView.swift
│           └── ProfileEditorView.swift
└── Tests/ArtMouseCoreTests/
    ├── ActionModelTests.swift
    ├── SettingsStoreTests.swift
    ├── DeviceManagerTests.swift
    ├── CGEventTranslationTests.swift
    ├── EventTapEngineTests.swift
    ├── EventRouterTests.swift
    ├── ClickLockCoordinatorTests.swift
    ├── AppWatcherTests.swift
    ├── ActionExecutorTests.swift
    ├── MediaKeySynthesizerTests.swift
    ├── CursorMathTests.swift
    └── CursorControllerTests.swift
```

---

### Task 1: Package scaffold and app-bundle script

**Files:**
- Create: `Package.swift`, `Sources/ArtMouseCore/Model/ButtonID.swift` (placeholder stub), `Sources/artMouse/main.swift` (placeholder stub), `Tests/ArtMouseCoreTests/ActionModelTests.swift` (placeholder stub), `Scripts/make_app.sh`

**Interfaces:**
- Consumes: nothing (first task).
- Produces: buildable package with targets `ArtMouseCore` (library), `artMouse` (executable), `ArtMouseCoreTests`; `Scripts/make_app.sh` producing `build/artMouse.app`.

- [ ] **Step 1: Write Package.swift and stub files**

`Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "artMouse",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ArtMouseCore"),
        .executableTarget(name: "artMouse", dependencies: ["ArtMouseCore"]),
        .testTarget(name: "ArtMouseCoreTests", dependencies: ["ArtMouseCore"]),
    ]
)
```

`Sources/ArtMouseCore/Model/ButtonID.swift` (real model, reused by Task 3 tests):

```swift
/// Physical button identity. Standard buttons map to CGEvent button numbers
/// (left=0, right=1, middle=2, fourth=3, fifth=4); extended buttons carry
/// their raw number (phase 4 binds them via raw HID).
public enum ButtonID: Hashable, Codable, CaseIterable {
    case left, right, middle, fourth, fifth
    case extended(Int)

    /// CGEvent mouse button number used when posting events.
    public var cgButtonNumber: Int {
        switch self {
        case .left: return 0
        case .right: return 1
        case .middle: return 2
        case .fourth: return 3
        case .fifth: return 4
        case .extended(let n): return n
        }
    }
}
```

`Sources/artMouse/main.swift`:

```swift
import Foundation

print("artMouse placeholder — replaced in Task 2")
```

`Tests/ArtMouseCoreTests/ActionModelTests.swift`:

```swift
import XCTest
@testable import ArtMouseCore

final class ActionModelTests: XCTestCase {
    func testButtonIDCodableRoundTrip() throws {
        let original: [ButtonID] = [.left, .right, .middle, .fourth, .fifth, .extended(7)]
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([ButtonID].self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
```

- [ ] **Step 2: Verify the package builds and the test passes**

Run: `swift build && swift test`
Expected: build succeeds; 1 test passes.

- [ ] **Step 3: Write Scripts/make_app.sh and make it executable**

```bash
#!/bin/bash
# Assembles build/artMouse.app from the release build output.
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="${ARTMOUSE_SIGNING_IDENTITY:--}"   # default: ad-hoc signing
APP="build/artMouse.app"

swift build -c release
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/artMouse" "$APP/Contents/MacOS/artMouse"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>app.artmouse</string>
    <key>CFBundleName</key><string>artMouse</string>
    <key>CFBundleExecutable</key><string>artMouse</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST
codesign --force --sign "$IDENTITY" "$APP"
echo "Built $APP"
```

Run: `chmod +x Scripts/make_app.sh && ./Scripts/make_app.sh`
Expected: prints `Built build/artMouse.app`.

- [ ] **Step 4: Commit**

```bash
git add Package.swift Sources Scripts Tests
git commit -m "Scaffold package with app bundle script"
```

### Task 2: Menu bar app shell

**Files:**
- Modify: `Sources/artMouse/main.swift`
- Create: `Sources/artMouse/AppDelegate.swift`

**Interfaces:**
- Consumes: nothing from ArtMouseCore yet.
- Produces: `AppDelegate` — `NSApplicationDelegate` that installs a status item with a Settings…/Quit menu and owns `func startEngine()` (empty until Task 15). `main.swift` bootstraps `NSApplication` with it. Manual verification only (no UI tests).

- [ ] **Step 1: Replace main.swift with app bootstrap**

```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu-bar app; no Dock icon
app.run()
```

- [ ] **Step 2: Write AppDelegate with status item and menu**

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit artMouse", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.title = "🖱"   // placeholder glyph; replaced by template icon later
        item.menu = menu
        statusItem = item

        startEngine()
    }

    /// Engine bootstrap; wired in Task 15.
    func startEngine() {}

    @objc func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        // Settings window arrives in Task 16; placeholder opens an empty window.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        window.title = "artMouse Settings"
        window.makeKeyAndOrderFront(nil)
    }

    @objc func quit() { NSApp.terminate(nil) }
}
```

Keep `AppDelegate.swift` under 150 lines; when Task 15 wiring grows it, move engine bootstrap into a separate `EngineBootstrap.swift` file in the app target.

- [ ] **Step 3: Rebuild bundle and launch manually**

Run: `./Scripts/make_app.sh && open build/artMouse.app`
Expected: menu-bar glyph appears; menu shows Settings… (opens an empty window) and Quit works. Leave the app closed when done: `pkill -x artMouse || true`.

- [ ] **Step 4: Commit**

```bash
git add Sources/artMouse
git commit -m "Add menu bar app shell"
```

### Task 3: Action model (phase-1 subset)

**Files:**
- Create: `Sources/ArtMouseCore/Model/ModKeys.swift`, `Sources/ArtMouseCore/Model/Action.swift`
- Modify: `Tests/ArtMouseCoreTests/ActionModelTests.swift`

**Interfaces:**
- Consumes: `ButtonID` (Task 1).
- Produces (exact — every later task uses these):
  - `enum ModKeys: UInt8, OptionSet, Codable, Hashable, CaseIterable { case command = 1, control = 2, option = 4, shift = 8 }`
  - `enum ClickOp: String, Codable, CaseIterable { case left, middle, right, doubleLeft, fourth, fifth, clickLock }`
  - `enum MissionOp: Hashable, Codable { case missionControl, appWindows, launchpad, showDesktop, notificationCenter, spotlight, siri, fullscreenButton; case desktop(Int); case moveSpaceLeft; case moveSpaceRight }`
  - `enum MusicOp: String, Codable, CaseIterable { case playPause, next, previous, mute, volumeUp, volumeDown, eject }`
  - `enum ZoomOp: String, Codable, CaseIterable { case screenZoomIn, screenZoomOut, appZoomIn, appZoomOut, pinchIn, pinchOut, smartZoom }`
  - `enum AppTarget: Hashable, Codable { case bundleID(String); case url(String); case bookmark(String) }`
  - `enum SwitcherOp: Hashable, Codable { case app(AppTarget); case nextApp; case previousApp; case applicationWindows; case showSwitcher }`
  - `enum OpenTarget: Hashable, Codable { case path(String); case url(String) }`
  - `enum DeviceOp: Hashable, Codable { case activateCursorSpeed(String?); case switchPrecisionMode; case dpiCycle; case dpiUp; case dpiDown; case dpiShift; case defaultDPI; case switchWheelMode }`
  - `enum Action: Hashable, Codable { case none; case click(ClickOp, ModKeys); case mission(MissionOp, reverse: Bool); case music(MusicOp, fineTune: Bool); case zoom(ZoomOp, reverse: Bool); case switcher(SwitcherOp); case open(OpenTarget); case device(DeviceOp) }`
  - `extension Action { var isHoldAction: Bool; var isClickLock: Bool }` — hold: true only for `.device(.switchPrecisionMode)`; click-lock: true for any `.click(.clickLock, _)` regardless of modifiers.

- [ ] **Step 1: Write failing tests**

Append to `Tests/ArtMouseCoreTests/ActionModelTests.swift`:

```swift
func testActionCodableRoundTripAllCases() throws {
    let actions: [Action] = [
        .none,
        .click(.doubleLeft, [.command, .shift]),
        .mission(.desktop(3), reverse: false),
        .mission(.moveSpaceRight, reverse: true),
        .music(.volumeUp, fineTune: true),
        .zoom(.appZoomIn, reverse: false),
        .switcher(.app(.bundleID("com.apple.Safari"))),
        .open(.path("/Applications")),
        .device(.activateCursorSpeed(nil)),
        .device(.switchPrecisionMode),
    ]
    let data = try JSONEncoder().encode(actions)
    let decoded = try JSONDecoder().decode([Action].self, from: data)
    XCTAssertEqual(decoded, actions)
}

func testIsHoldAction() {
    XCTAssertTrue(Action.device(.switchPrecisionMode).isHoldAction)
    XCTAssertFalse(Action.click(.left, []).isHoldAction)
    XCTAssertFalse(Action.device(.activateCursorSpeed(nil)).isHoldAction)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ActionModelTests`
Expected: FAIL — `Action`, `ModKeys` etc. not defined.

- [ ] **Step 3: Write ModKeys.swift**

```swift
/// Modifier buttons held during an action. Raw values match CGEventFlags shifts
/// conceptually but are persisted as-is; conversion to CGEventFlags lives in
/// ActionExecutor (system layer only).
public struct ModKeys: UInt8, OptionSet, Codable, Hashable, CaseIterable {
    public static let command = ModKeys(rawValue: 1)
    public static let control = ModKeys(rawValue: 2)
    public static let option  = ModKeys(rawValue: 4)
    public static let shift   = ModKeys(rawValue: 8)

    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public var rawValue: UInt8
}
```

- [ ] **Step 4: Write Action.swift**

```swift
/// Button-press actions (phase-1 subset of spec §5). Cases are extended in
/// later phases (scroll, macro, snapping); decoding of phase-1 JSON is
/// unaffected because Codable synthesis is per-case.
public enum Action: Hashable, Codable {
    case none
    case click(ClickOp, ModKeys)
    case mission(MissionOp, reverse: Bool)
    case music(MusicOp, fineTune: Bool)
    case zoom(ZoomOp, reverse: Bool)
    case switcher(SwitcherOp)
    case open(OpenTarget)
    case device(DeviceOp)

    /// Hold actions activate on button-down and revert on button-up.
    public var isHoldAction: Bool {
        if case .device(.switchPrecisionMode) = self { return true }
        return false
    }

    /// Click-lock bindings match regardless of the modifier set.
    public var isClickLock: Bool {
        if case .click(.clickLock, _) = self { return true }
        return false
    }
}

public enum ClickOp: String, Codable, CaseIterable {
    case left, middle, right, doubleLeft, fourth, fifth, clickLock
}

public enum MissionOp: Hashable, Codable {
    case missionControl, appWindows, launchpad, showDesktop
    case notificationCenter   // deferred: executor reports unavailable (phase 4)
    case spotlight, siri      // siri deferred
    case fullscreenButton
    case desktop(Int)         // 1...9 → ctrl+<n>
    case moveSpaceLeft, moveSpaceRight
}

public enum MusicOp: String, Codable, CaseIterable {
    case playPause, next, previous, mute, volumeUp, volumeDown, eject
}

public enum ZoomOp: String, Codable, CaseIterable {
    case screenZoomIn, screenZoomOut
    case appZoomIn, appZoomOut
    case pinchIn, pinchOut, smartZoom   // deferred: gesture emulation (phase 4)
}

public enum AppTarget: Hashable, Codable {
    case bundleID(String), url(String), bookmark(String)
}

public enum SwitcherOp: Hashable, Codable {
    case app(AppTarget)
    case nextApp, previousApp
    case applicationWindows
    case showSwitcher   // deferred: custom overlay (phase 4)
}

public enum OpenTarget: Hashable, Codable {
    case path(String), url(String)
}

public enum DeviceOp: Hashable, Codable {
    case activateCursorSpeed(String?)   // nil = next profile in order
    case switchPrecisionMode            // hold: precision profile while held
    // DPI + wheel-mode ops declared for parity; implemented in phases 2/4.
    case dpiCycle, dpiUp, dpiDown, dpiShift, defaultDPI, switchWheelMode
}
```

Split this file if it passes ~150 lines (one file per top-level type group is fine, e.g. `ClickOp+MissionOp.swift`).

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter ActionModelTests`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add Sources/ArtMouseCore Tests/ArtMouseCoreTests
git commit -m "Add phase-1 action model"
```

### Task 4: Settings store with malformed-input fallback

**Files:**
- Create: `Sources/ArtMouseCore/Settings/GlobalSettings.swift`, `Sources/ArtMouseCore/Settings/SettingsStore.swift`
- Create: `Tests/ArtMouseCoreTests/SettingsStoreTests.swift`

**Interfaces:**
- Consumes: `Action`, `ButtonID` (Task 3/1).
- Produces (exact):
  - `struct CursorSpeedProfile: Codable, Equatable, Identifiable { var id: UUID; var name: String; var sensitivity: Double; var acceleration: Double }`
  - `struct ButtonBinding: Codable, Equatable, Identifiable { var id: UUID; var button: ButtonID; var actions: [Action] }`
  - `struct GlobalSettings: Codable, Equatable { var schemaVersion: Int; var cursorSpeedProfiles: [CursorSpeedProfile]; var activeCursorSpeedProfileID: UUID?; var precisionProfileID: UUID?; var buttonBindings: [ButtonBinding]; static let `default`: GlobalSettings }` — default: schemaVersion 1, three profiles `Slow(800, 0.0) / Default(1600, 1.0) / Fast(3200, 2.0)`, active = Default, precision = Slow, no bindings.
  - `final class SettingsStore: ObservableObject { init(directory: URL); var settings: GlobalSettings { get set }; var lastLoadWarnings: [String] { get }; func save() throws; func reload(); static func decode(_ data: Data) throws -> GlobalSettings }` — `reload()` falls back to `.default` on undecodable/missing file, appending a human-readable warning; `save()` writes atomically.

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
import Combine
@testable import ArtMouseCore

final class SettingsStoreTests: XCTestCase {
    private func tempDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testFirstLoadCreatesDefaults() throws {
        let store = SettingsStore(directory: tempDirectory())
        XCTAssertEqual(store.settings, .default)
        XCTAssertTrue(store.lastLoadWarnings.isEmpty)
    }

    func testSaveThenReloadRoundTrip() throws {
        let dir = tempDirectory()
        var settings = GlobalSettings.default
        settings.buttonBindings = [
            ButtonBinding(id: UUID(), button: .fourth, actions: [.mission(.missionControl, reverse: false)])
        ]
        let store = SettingsStore(directory: dir)
        store.settings = settings
        try store.save()

        let reloaded = SettingsStore(directory: dir)
        XCTAssertEqual(reloaded.settings, settings)
    }

    func testMalformedJSONFallsBackToDefaultsWithWarning() throws {
        let dir = tempDirectory()
        try Data("not json at all".utf8).write(to: dir.appendingPathComponent("settings.json"))
        let store = SettingsStore(directory: dir)
        XCTAssertEqual(store.settings, .default)
        XCTAssertEqual(store.lastLoadWarnings.count, 1)
        XCTAssertTrue(store.lastLoadWarnings[0].contains("settings.json"))
    }

    func testDecodeThrowsOnGarbage() {
        XCTAssertThrowsError(try SettingsStore.decode(Data("nope".utf8)))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SettingsStoreTests`
Expected: FAIL — types not defined.

- [ ] **Step 3: Write GlobalSettings.swift**

```swift
import Foundation

public struct CursorSpeedProfile: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    /// Counts per inch; 1600 = system-neutral scale factor 1.0.
    public var sensitivity: Double
    /// 0 disables acceleration entirely (1:1 for the movement component).
    public var acceleration: Double

    public init(id: UUID = UUID(), name: String, sensitivity: Double, acceleration: Double) {
        self.id = id
        self.name = name
        self.sensitivity = sensitivity
        self.acceleration = acceleration
    }
}

public struct ButtonBinding: Codable, Equatable, Identifiable {
    public var id: UUID
    public var button: ButtonID
    public var actions: [Action]

    public init(id: UUID = UUID(), button: ButtonID, actions: [Action]) {
        self.id = id
        self.button = button
        self.actions = actions
    }
}

public struct GlobalSettings: Codable, Equatable {
    public var schemaVersion: Int
    public var cursorSpeedProfiles: [CursorSpeedProfile]
    public var activeCursorSpeedProfileID: UUID?
    public var precisionProfileID: UUID?
    public var buttonBindings: [ButtonBinding]

    public static let `default` = GlobalSettings(
        schemaVersion: 1,
        cursorSpeedProfiles: [
            CursorSpeedProfile(name: "Slow", sensitivity: 800, acceleration: 0.0),
            CursorSpeedProfile(name: "Default", sensitivity: 1600, acceleration: 1.0),
            CursorSpeedProfile(name: "Fast", sensitivity: 3200, acceleration: 2.0),
        ],
        activeCursorSpeedProfileID: nil,   // resolved to "Default" by name on first run
        precisionProfileID: nil,
        buttonBindings: []
    )
}
```

Then in the same file add default resolution so `activeCursorSpeedProfileID: nil` means "the profile named Default":

```swift
public extension GlobalSettings {
    /// The profile used for cursor transforms (falls back to first profile).
    var activeProfile: CursorSpeedProfile? {
        let profiles = cursorSpeedProfiles
        if let id = activeCursorSpeedProfileID,
           let match = profiles.first(where: { $0.id == id }) { return match }
        if let named = profiles.first(where: { $0.name == "Default" }) { return named }
        return profiles.first
    }

    var precisionProfile: CursorSpeedProfile? {
        if let id = precisionProfileID,
           let match = cursorSpeedProfiles.first(where: { $0.id == id }) { return match }
        return cursorSpeedProfiles.first
    }
}
```

- [ ] **Step 4: Write SettingsStore.swift**

```swift
import Foundation
import Combine

/// Loads/saves settings.json in the given directory. A malformed or missing
/// file yields defaults plus a warning (spec §7) — never a crash.
public final class SettingsStore: ObservableObject {
    static let settingsFileName = "settings.json"

    @Published public private(set) var lastLoadWarnings: [String] = []
    @Published public var settings: GlobalSettings {
        didSet { objectWillChange.send() }
    }

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent(Self.settingsFileName)
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
        self.settings = .default
        reload()
    }

    public func reload() {
        guard let data = try? Data(contentsOf: fileURL) else {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                lastLoadWarnings = ["Could not read \(Self.settingsFileName); using defaults."]
            }
            return
        }
        do {
            settings = try Self.decode(data)
            lastLoadWarnings = []
        } catch {
            settings = .default
            lastLoadWarnings = ["\(Self.settingsFileName) could not be read (\(error.localizedDescription)); using defaults."]
        }
    }

    public func save() throws {
        let data = try encoder.encode(settings)
        try data.write(to: fileURL, options: .atomic)
    }

    /// Strict decode used by tests and import; falls back happen in reload().
    public static func decode(_ data: Data) throws -> GlobalSettings {
        try JSONDecoder().decode(GlobalSettings.self, from: data)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter SettingsStoreTests`
Expected: PASS (4 tests).

- [ ] **Step 6: Commit**

```bash
git add Sources/ArtMouseCore/Settings Tests/ArtMouseCoreTests/SettingsStoreTests.swift
git commit -m "Add settings store with malformed-input fallback"
```

### Task 5: Device enumeration

**Files:**
- Create: `Sources/ArtMouseCore/Devices/HIDDeviceIdentity.swift`, `Sources/ArtMouseCore/Devices/HIDDeviceEnumerating.swift`, `Sources/ArtMouseCore/Devices/IOKitDeviceEnumerator.swift`, `Sources/ArtMouseCore/Devices/DeviceManager.swift`
- Create: `Tests/ArtMouseCoreTests/DeviceManagerTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces (exact):
  - `struct HIDDeviceIdentity: Equatable, Hashable { var vendorID: Int; var productID: Int; var name: String; var transport: String; var settingsKey: String }` — `settingsKey` is `"\(vendorID)_\(productID)"`.
  - `protocol HIDDeviceEnumerating { func currentPointingDevices() -> [HIDDeviceIdentity] }`
  - `final class IOKitDeviceEnumerator: HIDDeviceEnumerating` — real IOHIDManager wrapper.
  - `final class DeviceManager: ObservableObject { init(enumerator: HIDDeviceEnumerating); @Published private(set) var devices: [HIDDeviceIdentity]; func refresh() }`

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
@testable import ArtMouseCore

final class DeviceManagerTests: XCTestCase {
    func testRefreshPopulatesDevices() {
        let fixture = [
            HIDDeviceIdentity(vendorID: 0x046D, productID: 0xB019, name: "MX Master", transport: "Bluetooth"),
            HIDDeviceIdentity(vendorID: 0x05AC, productID: 0x030D, name: "Mighty Mouse", transport: "USB"),
        ]
        let manager = DeviceManager(enumerator: MockEnumerator(result: fixture))
        manager.refresh()
        XCTAssertEqual(manager.devices, fixture)
    }

    func testSettingsKeyFormat() {
        let id = HIDDeviceIdentity(vendorID: 1133, productID: 45081, name: "x", transport: "USB")
        XCTAssertEqual(id.settingsKey, "1133_45081")
    }
}

private struct MockEnumerator: HIDDeviceEnumerating {
    let result: [HIDDeviceIdentity]
    func currentPointingDevices() -> [HIDDeviceIdentity] { result }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter DeviceManagerTests`
Expected: FAIL — types not defined.

- [ ] **Step 3: Write the model and protocol**

`HIDDeviceIdentity.swift`:

```swift
public struct HIDDeviceIdentity: Equatable, Hashable {
    public var vendorID: Int
    public var productID: Int
    public var name: String
    public var transport: String

    /// Stable settings key ("vid_pid") used for enable/disable sets and
    /// future device profiles.
    public var settingsKey: String { "\(vendorID)_\(productID)" }

    public init(vendorID: Int, productID: Int, name: String, transport: String) {
        self.vendorID = vendorID
        self.productID = productID
        self.name = name
        self.transport = transport
    }
}
```

`HIDDeviceEnumerating.swift`:

```swift
public protocol HIDDeviceEnumerating {
    func currentPointingDevices() -> [HIDDeviceIdentity]
}
```

- [ ] **Step 4: Write the real enumerator**

`IOKitDeviceEnumerator.swift`:

```swift
import Foundation
import IOKit
import IOKit.hid

/// Enumerates pointing devices via IOHIDManager (public API). Raw report
/// observation arrives in Phase 4 (HIDObserver); this only lists devices.
public final class IOKitDeviceEnumerator: HIDDeviceEnumerating {
    public init() {}

    public func currentPointingDevices() -> [HIDDeviceIdentity] {
        guard let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOHIDManagerOptionNone) else {
            return []
        }
        defer { IOHIDManagerClose(manager, IOHIDManagerOptionNone) }

        let page = kHIDPage_GenericDesktop
        let usage = kHIDUsage_GD_Mouse
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDDeviceUsagePageKey as String: page,
            kIOHIDDeviceUsageKey as String: usage,
        ] as CFDictionary)

        guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            return []
        }

        return deviceSet.compactMap { device in
            guard
                let vendor = IOHIDDeviceGetIntegerProperty(device, kIOHIDVendorIDKey as CFString) as Int?,
                let product = IOHIDDeviceGetIntegerProperty(device, kIOHIDProductIDKey as CFString) as Int?
            else { return nil }
            let name = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String) ?? "Mouse"
            let transport = (IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String) ?? ""
            return HIDDeviceIdentity(vendorID: vendor, productID: product, name: name, transport: transport)
        }
        .sorted { ($0.vendorID, $0.productID) < ($1.vendorID, $1.productID) }
    }
}
```

- [ ] **Step 5: Write DeviceManager**

```swift
import Foundation
import Combine

@objc public final class DeviceManager: NSObject, ObservableObject {
    @Published public private(set) var devices: [HIDDeviceIdentity] = []
    private let enumerator: HIDDeviceEnumerating

    public init(enumerator: HIDDeviceEnumerating) {
        self.enumerator = enumerator
        super.init()
    }

    public func refresh() {
        devices = enumerator.currentPointingDevices()
    }
}
```

Note: drop the `@objc`/`NSObject` unless a later task needs selectors — plain `final class DeviceManager: ObservableObject` is preferred; keep whichever compiles clean.

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --filter DeviceManagerTests`
Expected: PASS (2 tests).

- [ ] **Step 7: Commit**

```bash
git add Sources/ArtMouseCore/Devices Tests/ArtMouseCoreTests/DeviceManagerTests.swift
git commit -m "Add HID device enumeration"
```

### Task 6: Input events, CGEvent translation, and the tap engine

**Files:**
- Create: `Sources/ArtMouseCore/Model/InputEvent.swift`, `Sources/ArtMouseCore/Engine/CGEventTranslation.swift`, `Sources/ArtMouseCore/Engine/EventTapCreating.swift`, `Sources/ArtMouseCore/Engine/EventTapEngine.swift`, `Sources/ArtMouseCore/Engine/RouterOutcome.swift`
- Create: `Tests/ArtMouseCoreTests/CGEventTranslationTests.swift`, `Tests/ArtMouseCoreTests/EventTapEngineTests.swift`

**Interfaces:**
- Consumes: `ButtonID` (Task 1).
- Produces (exact):
  - `enum InputEvent: Equatable { case buttonDown(ButtonID); case buttonUp(ButtonID); case moved(dx: Double, dy: Double); case dragged(dx: Double, dy: Double); case scrolled(axis: ScrollAxis, ticks: Double); case other }` with `enum ScrollAxis: Equatable { case vertical, horizontal }` (scroll handling itself is Phase 2; the case exists so the router pipeline is final).
  - `enum CGEventTranslation { static func inputEvent(from type: CGEventType, _ event: CGEvent) -> InputEvent }`
  - `protocol EventTapHandle: AnyObject { func enable(); func disable(); var isEnabled: Bool { get } }`
  - `protocol EventTapCreating { func createTap(mask: CGEventMask, callback: @escaping (CGEvent, CGEventType) -> CGEvent?) -> EventTapHandle? }`
  - `final class CGEventTapFactory: EventTapCreating` — real `CGEventTapCreate(kCGSessionEventTap, .headInsertEventTap, .defaultTap, mask, …)` wrapper.
  - `enum RouterOutcome: Equatable { case passThrough; case consume; case cursorTransform(dxFactor: Double, dyFactor: Double) }`
  - `protocol EventRouting { func handle(_ event: InputEvent) -> RouterOutcome }` (implemented by `EventRouter`, Task 7)
  - `final class EventTapEngine { init(router: EventRouting, tapFactory: EventTapCreating, workspaceNotificationCenter: NotificationCenter = .default); func start() -> Bool; func stop() }` — `start()` returns false when the tap cannot be created (missing Input Monitoring / Accessibility). Re-enables the tap on `NSWorkspace.didWakeNotification`.

- [ ] **Step 1: Write failing translation tests**

`Tests/ArtMouseCoreTests/CGEventTranslationTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import ArtMouseCore

final class CGEventTranslationTests: XCTestCase {
    private func mouseEvent(_ type: CGEventType, button: CGMouseButton) -> CGEvent {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: .zero, mouseButton: button)!
    }

    func testStandardButtons() {
        XCTAssertEqual(
            CGEventTranslation.inputEvent(from: .leftMouseDown, mouseEvent(.leftMouseDown, button: .left)),
            .buttonDown(.left))
        XCTAssertEqual(
            CGEventTranslation.inputEvent(from: .rightMouseUp, mouseEvent(.rightMouseUp, button: .right)),
            .buttonUp(.right))
    }

    func testOtherButtonsByNumber() {
        // CGMouseButton only carries 0..2; the true button number travels in
        // the mouseEventButtonNumber field, which is what translation reads.
        let down = CGEvent(mouseEventSource: nil, mouseType: .otherMouseDown, mouseCursorPosition: .zero, mouseButton: .center)!
        down.setIntegerValueField(.mouseEventButtonNumber, value: 2)
        XCTAssertEqual(CGEventTranslation.inputEvent(from: .otherMouseDown, down), .buttonDown(.middle))
        let fifth = CGEvent(mouseEventSource: nil, mouseType: .otherMouseDown, mouseCursorPosition: .zero, mouseButton: .center)!
        fifth.setIntegerValueField(.mouseEventButtonNumber, value: 4)
        XCTAssertEqual(CGEventTranslation.inputEvent(from: .otherMouseDown, fifth), .buttonDown(.fifth))
    }

    func testMoveAndDragCarryDeltas() {
        let moved = mouseEvent(.mouseMoved, button: .left)
        moved.setIntegerValueField(.mouseEventDeltaX, value: 12)
        moved.setIntegerValueField(.mouseEventDeltaY, value: -3)
        XCTAssertEqual(
            CGEventTranslation.inputEvent(from: .mouseMoved, moved),
            .moved(dx: 12, dy: -3))
    }

    func testScrollAxis() {
        let scroll = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel: 1, 0, 0, or: [])!
        XCTAssertEqual(
            CGEventTranslation.inputEvent(from: .scrollWheel, scroll),
            .scrolled(axis: .vertical, ticks: 1))
    }
}
```

- [ ] **Step 2: Write failing engine tests**

`Tests/ArtMouseCoreTests/EventTapEngineTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import ArtMouseCore

final class EventTapEngineTests: XCTestCase {
    func testStartReturnsFalseWhenTapCreationFails() {
        let engine = EventTapEngine(router: PassThroughRouter(), tapFactory: FailingTapFactory())
        XCTAssertFalse(engine.start())
    }

    func testConsumedEventReturnsNilFromCallback() {
        let tap = MockTap()
        let factory = MockTapFactory(tap: tap)
        let router = ConsumingRouter()
        let engine = EventTapEngine(router: router, tapFactory: factory)
        XCTAssertTrue(engine.start())
        let event = CGEvent(source: nil)!
        XCTAssertNil(tap.emit(event, type: .leftMouseDown))
    }

    func testPassThroughReturnsOriginalEvent() {
        let tap = MockTap()
        let engine = EventTapEngine(router: PassThroughRouter(), tapFactory: MockTapFactory(tap: tap))
        XCTAssertTrue(engine.start())
        let event = CGEvent(source: nil)!
        XCTAssertTrue(tap.emit(event, type: .leftMouseDown) === event)
    }

    func testCursorTransformScalesDeltaFields() {
        let tap = MockTap()
        let engine = EventTapEngine(router: ScalingRouter(factor: 2.0), tapFactory: MockTapFactory(tap: tap))
        XCTAssertTrue(engine.start())
        let event = CGEvent(source: nil)!
        event.setIntegerValueField(.mouseEventDeltaX, value: 5)
        event.setIntegerValueField(.mouseEventDeltaY, value: 7)
        let result = tap.emit(event, type: .mouseMoved)
        XCTAssertTrue(result === event)
        XCTAssertEqual(event.integerValueField(.mouseEventDeltaX), 10)
        XCTAssertEqual(event.integerValueField(.mouseEventDeltaY), 14)
    }

    func testReenablesTapOnWake() {
        let tap = MockTap()
        let testCenter = NotificationCenter()   // isolated center: the engine must observe THIS one
        let engine = EventTapEngine(router: PassThroughRouter(), tapFactory: MockTapFactory(tap: tap),
                                    workspaceNotificationCenter: testCenter)
        XCTAssertTrue(engine.start())
        tap.disable()
        XCTAssertFalse(tap.isEnabled)
        testCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        XCTAssertTrue(tap.isEnabled)
    }
}

// Test doubles + fixture routers
struct PassThroughRouter: EventRouting {
    func handle(_ event: InputEvent) -> RouterOutcome { .passThrough }
}
struct ConsumingRouter: EventRouting {
    func handle(_ event: InputEvent) -> RouterOutcome { .consume }
}
struct ScalingRouter: EventRouting {
    let factor: Double
    func handle(_ event: InputEvent) -> RouterOutcome {
        if case .moved = event { return .cursorTransform(dxFactor: factor, dyFactor: factor) }
        return .passThrough
    }
}
final class MockTap: EventTapHandle {
    private(set) var isEnabled = true
    var callback: ((CGEvent, CGEventType) -> CGEvent?)?
    func enable() { isEnabled = true }
    func disable() { isEnabled = false }
    @discardableResult
    func emit(_ event: CGEvent, type: CGEventType) -> CGEvent? { callback?(event, type) }
}
final class MockTapFactory: EventTapCreating {
    let tap: MockTap
    init(tap: MockTap) { self.tap = tap }
    func createTap(mask: CGEventMask, callback: @escaping (CGEvent, CGEventType) -> CGEvent?) -> EventTapHandle? {
        tap.callback = callback
        return tap
    }
}
struct FailingTapFactory: EventTapCreating {
    func createTap(mask: CGEventMask, callback: @escaping (CGEvent, CGEventType) -> CGEvent?) -> EventTapHandle? { nil }
}
```

Note: `NSWorkspace.didWakeNotification` and `NSWorkspace` require AppKit in the test target — add `import AppKit` at the top of the test file.

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter 'CGEventTranslationTests|EventTapEngineTests'`
Expected: FAIL — types not defined.

- [ ] **Step 4: Write InputEvent.swift**

```swift
public enum ScrollAxis: Equatable {
    case vertical, horizontal
}

/// Normalized input event fed to EventRouter. Produced from CGEvents by
/// CGEventTranslation, and (phase 4) from raw HID reports by HIDObserver.
public enum InputEvent: Equatable {
    case buttonDown(ButtonID)
    case buttonUp(ButtonID)
    case moved(dx: Double, dy: Double)
    case dragged(dx: Double, dy: Double)
    case scrolled(axis: ScrollAxis, ticks: Double)
    case other
}
```

- [ ] **Step 5: Write CGEventTranslation.swift**

```swift
import CoreGraphics

public enum CGEventTranslation {
    public static func inputEvent(from type: CGEventType, _ event: CGEvent) -> InputEvent {
        switch type {
        case .leftMouseDown: return .buttonDown(.left)
        case .leftMouseUp: return .buttonUp(.left)
        case .rightMouseDown: return .buttonDown(.right)
        case .rightMouseUp: return .buttonUp(.right)
        case .otherMouseDown: return .buttonDown(buttonID(forCGNumber: cgButton(event)))
        case .otherMouseUp: return .buttonUp(buttonID(forCGNumber: cgButton(event)))
        case .mouseMoved:
            return .moved(dx: event.doubleValueField(.mouseEventDeltaX),
                          dy: event.doubleValueField(.mouseEventDeltaY))
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            return .dragged(dx: event.doubleValueField(.mouseEventDeltaX),
                            dy: event.doubleValueField(.mouseEventDeltaY))
        case .scrollWheel:
            // Vertical scroll events carry a nonzero Axis1 delta; horizontal
            // events a nonzero Axis2 delta.
            let axis: ScrollAxis = event.doubleValueField(.scrollWheelEventDeltaAxis1) != 0 ? .vertical : .horizontal
            let ticks = axis == .vertical
                ? event.doubleValueField(.scrollWheelEventDeltaAxis1)
                : event.doubleValueField(.scrollWheelEventDeltaAxis2)
            return .scrolled(axis: axis, ticks: ticks)
        default:
            return .other
        }
    }

    private static func cgButton(_ event: CGEvent) -> Int {
        Int(event.getIntegerValueField(.mouseEventButtonNumber))
    }

    public static func buttonID(forCGNumber number: Int) -> ButtonID {
        switch number {
        case 0: return .left
        case 1: return .right
        case 2: return .middle
        case 3: return .fourth
        case 4: return .fifth
        default: return .extended(number)
        }
    }
}
```

Scroll-axis invariant pinned by `testScrollAxis`: a single-axis vertical event (Axis1 ≠ 0, Axis2 = 0) maps to `.vertical`.

- [ ] **Step 6: Write EventTapCreating.swift and RouterOutcome.swift**

`EventTapCreating.swift`:

```swift
import CoreGraphics

public protocol EventTapHandle: AnyObject {
    func enable()
    func disable()
    var isEnabled: Bool { get }
}

public protocol EventTapCreating {
    /// Returns nil when the tap cannot be created (missing permission).
    func createTap(mask: CGEventMask, callback: @escaping (CGEvent, CGEventType) -> CGEvent?) -> EventTapHandle?
}

/// Box so the C callback can reach the Swift closure (CGEventTapCreate's
/// Swift binding takes no userInfo; we pass a retained pointer ourselves).
final class EventTapCallbackBox {
    var handler: ((CGEvent, CGEventType) -> CGEvent?)?
    func handle(type: CGEventType, event: CGEvent) -> CGEvent? {
        handler?(event, type)
    }
}

public final class CGEventTapFactory: EventTapCreating {
    public init() {}

    public func createTap(mask: CGEventMask, callback: @escaping (CGEvent, CGEventType) -> CGEvent?) -> EventTapHandle? {
        let box = EventTapCallbackBox()
        box.handler = callback
        // One +1 retain whose opaque pointer travels to the C callback as
        // userInfo; CGEventTapHandleImp owns it and releases it in deinit.
        let boxPointer = Unmanaged.passRetained(box).toOpaque()
        guard let tap = CGEventTapCreate(
            kCGSessionEventTap,
            .headInsertEventTap,
            .defaultTap,
            mask,
            { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let box = Unmanaged<EventTapCallbackBox>.fromOpaque(userInfo).takeUnretainedValue()
                return box.handle(type: type, event: event)
            },
            boxPointer) as CFMachPort?
        else {
            Unmanaged<EventTapCallbackBox>.fromOpaque(boxPointer).release()   // balance the +1 above
            return nil
        }

        return CGEventTapHandleImp(tap: tap, box: box, boxPointer: boxPointer)
    }
}

final class CGEventTapHandleImp: EventTapHandle {
    private let tap: CFMachPort
    private let runLoopSource: CFRunLoopSource?
    private let box: EventTapCallbackBox
    private let boxPointer: UnsafeMutableRawPointer
    private(set) var isEnabled: Bool

    init(tap: CFMachPort, box: EventTapCallbackBox, boxPointer: UnsafeMutableRawPointer) {
        self.tap = tap
        self.box = box
        self.boxPointer = boxPointer
        self.isEnabled = CGEventTapIsEnabled(tap)
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }

    func enable() { CGEventTapEnable(tap, true); isEnabled = CGEventTapIsEnabled(tap) }
    func disable() { CGEventTapEnable(tap, false); isEnabled = CGEventTapIsEnabled(tap) }

    deinit {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        Unmanaged<EventTapCallbackBox>.fromOpaque(boxPointer).release()
    }
}
```

Note: the real factory is exercised manually (Task 19); all logic tests go through `MockTap`/`MockTapFactory`.
`RouterOutcome.swift`:

```swift
public enum RouterOutcome: Equatable {
    case passThrough
    case consume
    /// Scale the CGEvent delta fields by these factors (CursorController).
    case cursorTransform(dxFactor: Double, dyFactor: Double)
}
```

- [ ] **Step 7: Write EventTapEngine.swift**

```swift
import CoreGraphics
import AppKit

public protocol EventRouting {
    func handle(_ event: InputEvent) -> RouterOutcome
}

/// Owns the CGEventTap, translates events to InputEvents, consults the
/// router, and applies the outcome to the real CGEvent. Re-enables the tap
/// after system wake (spec §7).
public final class EventTapEngine {
    private let router: EventRouting
    private let tapFactory: EventTapCreating
    private let notificationCenter: NotificationCenter
    private var tap: EventTapHandle?
    private var wakeObserver: NSObjectProtocol?

    /// Standard mouse event mask; raw-HID buttons beyond these arrive in
    /// phase 4 via HIDObserver.
    public static let eventMask: CGEventMask =
        (1 << CGEventType.leftMouseDown.rawValue)
        | (1 << CGEventType.leftMouseUp.rawValue)
        | (1 << CGEventType.rightMouseDown.rawValue)
        | (1 << CGEventType.rightMouseUp.rawValue)
        | (1 << CGEventType.otherMouseDown.rawValue)
        | (1 << CGEventType.otherMouseUp.rawValue)
        | (1 << CGEventType.mouseMoved.rawValue)
        | (1 << CGEventType.leftMouseDragged.rawValue)
        | (1 << CGEventType.rightMouseDragged.rawValue)
        | (1 << CGEventType.otherMouseDragged.rawValue)
        | (1 << CGEventType.scrollWheel.rawValue)

    public init(router: EventRouting, tapFactory: EventTapCreating,
                workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        self.router = router
        self.tapFactory = tapFactory
        self.notificationCenter = workspaceNotificationCenter
    }

    /// Returns false when the tap could not be created (missing permission).
    @discardableResult
    public func start() -> Bool {
        guard tap == nil else { return true }
        guard let handle = tapFactory.createTap(mask: Self.eventMask, callback: { [weak self] event, type in
            self?.process(event: event, type: type)
        }) else { return false }
        tap = handle
        registerWakeHandler()
        return true
    }

    public func stop() {
        tap?.disable()
        tap = nil
        if let observer = wakeObserver {
            notificationCenter.removeObserver(observer)
            wakeObserver = nil
        }
    }

    private func registerWakeHandler() {
        wakeObserver = notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.tap?.enable()
        }
    }

    func process(event: CGEvent, type: CGEventType) -> CGEvent? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            tap?.enable()
            return event
        }
        let input = CGEventTranslation.inputEvent(from: type, event)
        switch router.handle(input) {
        case .passThrough:
            return event
        case .consume:
            return nil
        case .cursorTransform(let dxFactor, let dyFactor):
            let dx = event.getIntegerValueField(.mouseEventDeltaX)
            let dy = event.getIntegerValueField(.mouseEventDeltaY)
            event.setIntegerValueField(.mouseEventDeltaX, value: Int64((Double(dx) * dxFactor).rounded()))
            event.setIntegerValueField(.mouseEventDeltaY, value: Int64((Double(dy) * dyFactor).rounded()))
            return event
        }
    }
}
```

The engine's `process` is `internal` so tests can call it directly if needed; the tap factory wires the same method through the box.

- [ ] **Step 8: Run tests to verify they pass**

Run: `swift test --filter 'CGEventTranslationTests|EventTapEngineTests'`
Expected: PASS (9 tests).

- [ ] **Step 9: Commit**

```bash
git add Sources/ArtMouseCore Tests/ArtMouseCoreTests
git commit -m "Add event tap engine with CGEvent translation"
```

### Task 7: EventRouter — binding resolution and outcome dispatch

**Files:**
- Create: `Sources/ArtMouseCore/Engine/EventRouter.swift`, `Sources/ArtMouseCore/Actions/EventPosting.swift` (protocol only here; executor in Task 8)
- Create: `Tests/ArtMouseCoreTests/EventRouterTests.swift`

**Interfaces:**
- Consumes: `InputEvent`, `RouterOutcome`, `EventRouting` (Task 6), `GlobalSettings`/`ButtonBinding`/`Action` (Tasks 3–4).
- Produces (exact):
  - `protocol ActionExecuting: AnyObject { func perform(_ action: Action); func beganHold(_ action: Action); func endedHold(_ action: Action) }`
  - `final class EventRouter: EventRouting { init(settings: SettingsStore, executor: ActionExecuting, clickLock: ClickLockCoordinating, cursor: CursorControlling); func handle(_ event: InputEvent) -> RouterOutcome }`
  - `protocol ClickLockCoordinating: AnyObject { func noteDown(_ button: ButtonID, now: Double); func noteUp(_ button: ButtonID, now: Double) -> Bool /* true = swallow this up */; func isLocked(_ button: ButtonID) -> Bool; func shouldSwallowDown(_ button: ButtonID) -> Bool }` (implementation Task 9; router is written against the protocol with a stub test double)
  - `protocol CursorControlling: AnyObject { func outcome(forMove: InputEvent) -> RouterOutcome }` (implementation Task 13; stub in tests)

Routing rules (pinned by tests):
- `buttonDown` for a button with a binding whose actions are all tap actions → executor.perform each, return `.consume`.
- `buttonDown`/`buttonUp` for a button bound to a hold action (`.device(.switchPrecisionMode)`) → `beganHold` on down, `endedHold` on up, `.consume` both ways.
- `buttonDown`/`buttonUp` for a button bound to `.click(.clickLock)` → delegated to `ClickLockCoordinating` + executor posts (Task 9 wires posting; router consumes and coordinates).
- Buttons with no binding → `.passThrough` (Review Focus #5).
- `.moved`/`.dragged` → `cursor.outcome(forMove:)` result.
- `.scrolled`/`.other` → `.passThrough` (Phase 2 handles scroll).

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
@testable import ArtMouseCore

final class EventRouterTests: XCTestCase {
    private func store(_ settings: GlobalSettings) -> SettingsStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = SettingsStore(directory: dir)
        store.settings = settings
        return store
    }

    func testUnboundButtonPassesThrough() {
        let executor = RecordingExecutor()
        let router = EventRouter(settings: store(.default), executor: executor,
                                 clickLock: StubClickLock(), cursor: StubCursor())
        XCTAssertEqual(router.handle(.buttonDown(.fifth)), .passThrough)
        XCTAssertTrue(executor.performed.isEmpty)
    }

    func testTapBindingPerformsAndConsumes() {
        let executor = RecordingExecutor()
        var settings = GlobalSettings.default
        settings.buttonBindings = [ButtonBinding(button: .fourth, actions: [.mission(.missionControl, reverse: false)])]
        let router = EventRouter(settings: store(settings), executor: executor,
                                 clickLock: StubClickLock(), cursor: StubCursor())
        XCTAssertEqual(router.handle(.buttonDown(.fourth)), .consume)
        XCTAssertEqual(executor.performed, [.mission(.missionControl, reverse: false)])
    }

    func testHoldBindingBeginsAndEnds() {
        let executor = RecordingExecutor()
        var settings = GlobalSettings.default
        settings.buttonBindings = [ButtonBinding(button: .middle, actions: [.device(.switchPrecisionMode)])]
        let router = EventRouter(settings: store(settings), executor: executor,
                                 clickLock: StubClickLock(), cursor: StubCursor())
        XCTAssertEqual(router.handle(.buttonDown(.middle)), .consume)
        XCTAssertEqual(router.handle(.buttonUp(.middle)), .consume)
        XCTAssertEqual(executor.holdsBegan, [.device(.switchPrecisionMode)])
        XCTAssertEqual(executor.holdsEnded, [.device(.switchPrecisionMode)])
    }

    func testMoveDelegatesToCursor() {
        let executor = RecordingExecutor()
        let cursor = StubCursor(outcome: .cursorTransform(dxFactor: 0.5, dyFactor: 0.5))
        let router = EventRouter(settings: store(.default), executor: executor,
                                 clickLock: StubClickLock(), cursor: cursor)
        XCTAssertEqual(router.handle(.moved(dx: 3, dy: 4)), .cursorTransform(dxFactor: 0.5, dyFactor: 0.5))
    }

    func testScrollPassesThroughInPhase1() {
        let router = EventRouter(settings: store(.default), executor: RecordingExecutor(),
                                 clickLock: StubClickLock(), cursor: StubCursor())
        XCTAssertEqual(router.handle(.scrolled(axis: .vertical, ticks: 1)), .passThrough)
    }

    func testExtendedUnboundButtonPassesThrough() {
        let router = EventRouter(settings: store(.default), executor: RecordingExecutor(),
                                 clickLock: StubClickLock(), cursor: StubCursor())
        XCTAssertEqual(router.handle(.buttonDown(.extended(11))), .passThrough)
        XCTAssertEqual(router.handle(.buttonUp(.extended(11))), .passThrough)
    }
}

final class RecordingExecutor: ActionExecuting {
    private(set) var performed: [Action] = []
    private(set) var holdsBegan: [Action] = []
    private(set) var holdsEnded: [Action] = []
    func perform(_ action: Action) { performed.append(action) }
    func beganHold(_ action: Action) { holdsBegan.append(action) }
    func endedHold(_ action: Action) { holdsEnded.append(action) }
}

final class StubClickLock: ClickLockCoordinating {
    func noteDown(_ button: ButtonID, now: Double) {}
    func noteUp(_ button: ButtonID, now: Double) -> Bool { false }
    func isLocked(_ button: ButtonID) -> Bool { false }
    func shouldSwallowDown(_ button: ButtonID) -> Bool { false }
}

final class StubCursor: CursorControlling {
    let outcome: RouterOutcome
    init(outcome: RouterOutcome = .passThrough) { self.outcome = outcome }
    func outcome(forMove event: InputEvent) -> RouterOutcome { outcome }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter EventRouterTests`
Expected: FAIL — `EventRouter`, protocols not defined.

- [ ] **Step 3: Write EventPosting.swift (protocol) and EventRouter.swift**

`EventPosting.swift`:

```swift
/// Anything that can perform actions. ActionExecutor (Task 8) is the real
/// implementation; tests use recording doubles.
public protocol ActionExecuting: AnyObject {
    func perform(_ action: Action)
    func beganHold(_ action: Action)
    func endedHold(_ action: Action)
}
```

`EventRouter.swift`:

```swift
import Foundation

public protocol ClickLockCoordinating: AnyObject {
    /// A button-down for a click-lock bound button. `now` is seconds.
    func noteDown(_ button: ButtonID, now: Double)
    /// A button-up for a click-lock bound button. Returns true when the up
    /// should be swallowed (locked, or release after lock threshold).
    func noteUp(_ button: ButtonID, now: Double) -> Bool
    /// True while the lock is stuck down for this button.
    func isLocked(_ button: ButtonID) -> Bool
    /// A down arriving while locked releases the lock: swallow it.
    func shouldSwallowDown(_ button: ButtonID) -> Bool
}

public protocol CursorControlling: AnyObject {
    func outcome(forMove event: InputEvent) -> RouterOutcome
}

public final class EventRouter: EventRouting {
    private let settings: SettingsStore
    private let executor: ActionExecuting
    private let clickLock: ClickLockCoordinating
    private let cursor: CursorControlling
    /// Buttons currently held that were activated with hold actions.
    private var heldButtons: Set<ButtonID> = []

    public init(settings: SettingsStore, executor: ActionExecuting,
                clickLock: ClickLockCoordinating, cursor: CursorControlling) {
        self.settings = settings
        self.executor = executor
        self.clickLock = clickLock
        self.cursor = cursor
    }

    public func handle(_ event: InputEvent) -> RouterOutcome {
        switch event {
        case .buttonDown(let button): return handleDown(button)
        case .buttonUp(let button): return handleUp(button)
        case .moved, .dragged:
            return cursor.outcome(forMove: event)
        case .scrolled, .other:
            return .passThrough
        }
    }

    private func binding(for button: ButtonID) -> ButtonBinding? {
        settings.settings.buttonBindings.first { $0.button == button }
    }

    private func handleDown(_ button: ButtonID) -> RouterOutcome {
        guard let binding = binding(for: button) else { return .passThrough }

        if binding.actions.contains(where: { $0.isClickLock }) {
            if clickLock.shouldSwallowDown(button) { return .consume }   // releasing a lock
            clickLock.noteDown(button, now: Date().timeIntervalSince1970)
            return .consume
        }

        for action in binding.actions where action.isHoldAction {
            executor.beganHold(action)
            heldButtons.insert(button)
            return .consume
        }
        for action in binding.actions {
            executor.perform(action)
        }
        return .consume
    }

    private func handleUp(_ button: ButtonID) -> RouterOutcome {
        guard let binding = binding(for: button) else { return .passThrough }

        if binding.actions.contains(where: { $0.isClickLock }) {
            let swallow = clickLock.noteUp(button, now: Date().timeIntervalSince1970)
            return .consume   // coordinator decides posting (Task 9)
        }

        if heldButtons.contains(button) {
            heldButtons.remove(button)
            for action in binding.actions where action.isHoldAction {
                executor.endedHold(action)
            }
            return .consume
        }
        return .consume
    }
}
```

Note: click-lock detection uses `Action.isClickLock` (Task 3) because modifiers vary per binding; direct `.click(.clickLock)` equality would not compile.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter EventRouterTests`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/ArtMouseCore Tests/ArtMouseCoreTests/EventRouterTests.swift
git commit -m "Add event router with binding resolution"
```

### Task 8: Keycodes and ActionExecutor — clicks

**Files:**
- Create: `Sources/ArtMouseCore/Actions/KeyCodes.swift`, `Sources/ArtMouseCore/Actions/EventPosting.swift` (append real poster to the protocol file), `Sources/ArtMouseCore/Actions/ActionExecutor.swift`
- Create: `Tests/ArtMouseCoreTests/ActionExecutorTests.swift`

**Interfaces:**
- Consumes: `Action`, `ButtonID`, `ModKeys`, `ActionExecuting` (Tasks 3, 7).
- Produces (exact):
  - `enum KeyCodes { static let upArrow: UInt64 = 126; downArrow: UInt64 = 125; leftArrow: UInt64 = 124; rightArrow: UInt64 = 123; space: UInt64 = 49; f4: UInt64 = 130; f11: UInt64 = 103; equals: UInt64 = 24; minus: UInt64 = 27; f: UInt64 = 3; digit(_ n: Int) -> UInt64 }` — `digit(1)=18, digit(2)=19, digit(3)=20, digit(4)=21, digit(5)=23` (ANSI layout).
  - `enum CGFlagConversion { static func cgFlags(_ modKeys: ModKeys) -> CGEventFlags }` — command→.maskCommand, control→.maskControl, option→.maskAlternate, shift→.maskShift.
  - `protocol EventPosting: AnyObject { func post(_ event: CGEvent) }` and `final class CGEventPoster: EventPosting { func post(_ event: CGEvent) { event.post(tap: .cghidEventTap) } }`
  - `final class ActionExecutor: ActionExecuting { init(poster: EventPosting, workspace: WorkspaceOpening = NSWorkspaceOpener()) ; func perform(_ action: Action); func beganHold(_ action: Action); func endedHold(_ action: Action); func postButton(_ id: ButtonID, down: Bool, mods: ModKeys) }`
  - `protocol WorkspaceOpening: AnyObject { func launchApp(bundleID: String); func openURL(_ url: URL); func openFile(path: String) }`, `final class NSWorkspaceOpener: WorkspaceOpening` (used by switcher/open in Task 10).
  - `final class RecordingPoster: EventPosting { private(set) var events: [CGEvent]; func clear() }` (defined in the test file).

Click semantics (pinned by tests):
- `.click(.left/.middle/.right, mods)` → one click pair: down event then up event, `mouseEventButtonNumber` set, `flags` carry mods, clickState 1.
- `.click(.doubleLeft, mods)` → two pairs, second pair clickState 2.
- `.click(.fourth/.fifth, mods)` → otherMouseDown/Up with button number 3/4.
- `.click(.clickLock, mods)` → no immediate posting; engine-level behavior (Task 9).
- Unsupported actions (zoom pinch/smart, notificationCenter, siri, showSwitcher, dpi*, switchWheelMode) → perform() is a no-op for them in this phase (UI disables them; Task 16).

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
import CoreGraphics
@testable import ArtMouseCore

final class ActionExecutorTests: XCTestCase {
    func testLeftClickPostsDownUpPairWithFlags() {
        let poster = RecordingPoster()
        let executor = ActionExecutor(poster: poster)
        executor.perform(.click(.left, [.command]))
        XCTAssertEqual(poster.events.count, 2)
        XCTAssertEqual(poster.events[0].type, .leftMouseDown)
        XCTAssertEqual(poster.events[0].integerValueField(.mouseEventClickState), 1)
        XCTAssertTrue(poster.events[0].flags.contains(.maskCommand))
        XCTAssertEqual(poster.events[1].type, .leftMouseUp)
    }

    func testDoubleLeftClickPostsFourEvents() {
        let poster = RecordingPoster()
        let executor = ActionExecutor(poster: poster)
        executor.perform(.click(.doubleLeft, []))
        XCTAssertEqual(poster.events.count, 4)
        XCTAssertEqual(poster.events[0].type, .leftMouseDown)
        XCTAssertEqual(poster.events[1].type, .leftMouseUp)
        XCTAssertEqual(poster.events[2].type, .leftMouseDown)
        XCTAssertEqual(poster.events[2].integerValueField(.mouseEventClickState), 2)
        XCTAssertEqual(poster.events[3].type, .leftMouseUp)
    }

    func testMiddleClickUsesOtherMouseEvents() {
        let poster = RecordingPoster()
        let executor = ActionExecutor(poster: poster)
        executor.perform(.click(.middle, []))
        XCTAssertEqual(poster.events.count, 2)
        XCTAssertEqual(poster.events[0].type, .otherMouseDown)
        XCTAssertEqual(poster.events[0].integerValueField(.mouseEventButtonNumber), 2)
    }

    func testFourthAndFifthClicks() {
        let poster = RecordingPoster()
        let executor = ActionExecutor(poster: poster)
        executor.perform(.click(.fourth, []))
        executor.perform(.click(.fifth, []))
        XCTAssertEqual(poster.events[0].integerValueField(.mouseEventButtonNumber), 3)
        XCTAssertEqual(poster.events[2].integerValueField(.mouseEventButtonNumber), 4)
    }

    func testClickLockPostsNothingImmediately() {
        let poster = RecordingPoster()
        let executor = ActionExecutor(poster: poster)
        executor.perform(.click(.clickLock, []))
        XCTAssertTrue(poster.events.isEmpty)
    }

    func testKeyCodesANSIValues() {
        XCTAssertEqual(KeyCodes.digit(1), 18)
        XCTAssertEqual(KeyCodes.digit(5), 23)
        XCTAssertEqual(KeyCodes.upArrow, 126)
        XCTAssertEqual(KeyCodes.f4, 130)
    }

    func testFlagConversion() {
        XCTAssertEqual(CGFlagConversion.cgFlags([.command, .shift]), CGEventFlags.maskCommand.union(.maskShift))
    }
}

final class RecordingPoster: EventPosting {
    private(set) var events: [CGEvent] = []
    func post(_ event: CGEvent) { events.append(event) }
    func clear() { events.removeAll() }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ActionExecutorTests`
Expected: FAIL — types not defined.

- [ ] **Step 3: Write KeyCodes.swift and append poster to EventPosting.swift**

`KeyCodes.swift`:

```swift
import CoreGraphics

/// ANSI US keycodes used by posted shortcuts (mission, zoom).
public enum KeyCodes {
    public static let upArrow: UInt64 = 126
    public static let downArrow: UInt64 = 125
    public static let leftArrow: UInt64 = 124
    public static let rightArrow: UInt64 = 123
    public static let space: UInt64 = 49
    public static let f4: UInt64 = 130
    public static let f11: UInt64 = 103
    public static let equals: UInt64 = 24
    public static let minus: UInt64 = 27
    public static let f: UInt64 = 3

    public static func digit(_ n: Int) -> UInt64 {
        // ANSI: 1=0x12(18), 2=0x13(19), 3=0x14(20), 4=0x15(21), 5=0x17(23)
        switch n {
        case 1: return 18
        case 2: return 19
        case 3: return 20
        case 4: return 21
        case 5: return 23
        default: return 18
        }
    }
}

public enum CGFlagConversion {
    public static func cgFlags(_ modKeys: ModKeys) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modKeys.contains(.command) { flags.insert(.maskCommand) }
        if modKeys.contains(.control) { flags.insert(.maskControl) }
        if modKeys.contains(.option) { flags.insert(.maskAlternate) }
        if modKeys.contains(.shift) { flags.insert(.maskShift) }
        return flags
    }
}
```

Add this keycode-distinctness test to the KeyCodes section of `ActionExecutorTests.swift`:

```swift
func testArrowCodesDistinct() {
    XCTAssertNotEqual(KeyCodes.leftArrow, KeyCodes.rightArrow)
    XCTAssertEqual(KeyCodes.leftArrow, 124)
    XCTAssertEqual(KeyCodes.rightArrow, 123)
    XCTAssertEqual(KeyCodes.downArrow, 125)
}
```

Append to `EventPosting.swift`:

```swift
import CoreGraphics

public protocol EventPosting: AnyObject {
    func post(_ event: CGEvent)
}

public final class CGEventPoster: EventPosting {
    public init() {}
    public func post(_ event: CGEvent) {
        event.post(tap: .cghidEventTap)
    }
}
```

- [ ] **Step 4: Write ActionExecutor.swift (click portion; mission/music/zoom/switcher/open in Task 10)**

```swift
import AppKit
import CoreGraphics

public protocol WorkspaceOpening: AnyObject {
    func launchApp(bundleID: String)
    func openURL(_ url: URL)
    func openFile(path: String)
}

public final class NSWorkspaceOpener: WorkspaceOpening {
    public init() {}
    public func launchApp(bundleID: String) {
        NSWorkspace.shared.launchApplication(withBundleIdentifier: bundleID, options: [.withoutActivation], additionalEventParamDescriptor: nil, launchIdentifier: nil)
    }
    public func openURL(_ url: URL) { NSWorkspace.shared.open(url) }
    public func openFile(path: String) { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
}

public final class ActionExecutor: ActionExecuting {
    private let poster: EventPosting
    private let workspace: WorkspaceOpening

    public init(poster: EventPosting, workspace: WorkspaceOpening = NSWorkspaceOpener()) {
        self.poster = poster
        self.workspace = workspace
    }

    public func perform(_ action: Action) {
        switch action {
        case .none:
            break
        case .click(let op, let mods):
            performClick(op, mods: mods)
        case .mission, .music, .zoom, .switcher, .open, .device:
            performAction(action)   // Task 10 replaces this stub dispatch
        }
    }

    public func beganHold(_ action: Action) { performAction(action) }   // precision-mode begin, Task 13
    public func endedHold(_ action: Action) {}                          // precision-mode end, Task 13

    /// Used by ClickLockCoordinator to post lock-phase button events.
    public func postButton(_ id: ButtonID, down: Bool, mods: ModKeys) {
        postButtonEvent(id, down: down, mods: mods, clickState: 1)
    }

    private func performClick(_ op: ClickOp, mods: ModKeys) {
        switch op {
        case .clickLock:
            break   // engine-level; EventRouter + ClickLockCoordinator own it
        case .doubleLeft:
            postStandardClick(.left, clickState: 1, mods: mods)
            postStandardClick(.left, clickState: 2, mods: mods)
        case .left:
            postStandardClick(.left, clickState: 1, mods: mods)
        case .middle:
            postButtonEvent(.middle, down: true, mods: mods, clickState: 1)
            postButtonEvent(.middle, down: false, mods: mods, clickState: 1)
        case .right:
            postButtonEvent(.right, down: true, mods: mods, clickState: 1)
            postButtonEvent(.right, down: false, mods: mods, clickState: 1)
        case .fourth:
            postButtonEvent(.fourth, down: true, mods: mods, clickState: 1)
            postButtonEvent(.fourth, down: false, mods: mods, clickState: 1)
        case .fifth:
            postButtonEvent(.fifth, down: true, mods: mods, clickState: 1)
            postButtonEvent(.fifth, down: false, mods: mods, clickState: 1)
        }
    }

    private func postStandardClick(_ button: ButtonID, clickState: Int64, mods: ModKeys) {
        postButtonEvent(button, down: true, mods: mods, clickState: clickState)
        postButtonEvent(button, down: false, mods: mods, clickState: clickState)
    }

    private func postButtonEvent(_ id: ButtonID, down: Bool, mods: ModKeys, clickState: Int64) {
        let number = id.cgButtonNumber
        let type: CGEventType
        switch (id, down) {
        case (.left, true): type = .leftMouseDown
        case (.left, false): type = .leftMouseUp
        case (.right, true): type = .rightMouseDown
        case (.right, false): type = .rightMouseUp
        case (_, true): type = .otherMouseDown
        case (_, false): type = .otherMouseUp
        }
        let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: .zero, mouseButton: CGMouseButton(rawValue: UInt32(clamping: number)) ?? .center)!
        event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(number))
        event.setIntegerValueField(.mouseEventClickState, value: clickState)
        event.flags = CGFlagConversion.cgFlags(mods)
        poster.post(event)
    }

    private func performAction(_ action: Action) {
        // Task 10 fills mission/music/zoom/switcher/open dispatch.
    }
}
```

Note: `CGMouseButton(rawValue:)` only accepts 0…2; extended numbers force `.center` with the button number set explicitly afterward — that ordering (create, then set field) is what the tests pin.

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter 'ActionExecutorTests|EventRouterTests'`
Expected: PASS (router suite must stay green — `RecordingExecutor` still satisfies the protocol).

- [ ] **Step 6: Commit**

```bash
git add Sources/ArtMouseCore/Actions Tests/ArtMouseCoreTests/ActionExecutorTests.swift
git commit -m "Add action executor click ops with keycode table"
```

### Task 9: ClickLock coordinator

**Files:**
- Create: `Sources/ArtMouseCore/Engine/ClickLockCoordinator.swift`
- Create: `Tests/ArtMouseCoreTests/ClickLockCoordinatorTests.swift`
- Modify: `Sources/ArtMouseCore/Engine/EventRouter.swift` (route click-lock button events through coordinator + executor)

**Interfaces:**
- Consumes: `ClickLockCoordinating` (Task 7), `ActionExecutor.postButton` (Task 8).
- Produces (exact): `final class ClickLockCoordinator: ClickLockCoordinating { init(executor: ActionExecuting, clock: @escaping () -> Double = { Date().timeIntervalSince1970 }, threshold: Double = 0.5); /* protocol methods */ }`

State machine per button (pinned by tests; `threshold` in seconds, default 0.5):
- `idle` — `noteDown` → post down, state `pressed` (timer starts at `now`).
- `pressed` — `noteUp` while `now - downTime < threshold` → post up, state `idle` (normal click).
- `pressed` — `noteUp` while `now - downTime >= threshold` → swallow the up (locked: physical release ignored), state `locked`.
- `locked` — `isLocked == true`. Next `noteDown` → post up (release), swallow the down, state `idle` (`shouldSwallowDown` returns true).

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
@testable import ArtMouseCore

final class ClickLockCoordinatorTests: XCTestCase {
    private var now = 0.0

    func testNormalClickPostsDownAndUp() {
        let coordinator = makeCoordinator()
        coordinator.noteDown(.left, now: 0.0)
        let swallowed = coordinator.noteUp(.left, now: 0.1)
        XCTAssertFalse(swallowed)
    }

    func testReleaseAfterThresholdLocks() {
        let coordinator = makeCoordinator()
        coordinator.noteDown(.left, now: 0.0)
        let swallowed = coordinator.noteUp(.left, now: 0.6)
        XCTAssertTrue(swallowed)                     // physical release ignored
        XCTAssertTrue(coordinator.isLocked(.left))   // sticky down
    }

    func testNextClickReleasesLock() {
        let coordinator = makeCoordinator()
        coordinator.noteDown(.left, now: 0.0)
        _ = coordinator.noteUp(.left, now: 0.6)      // locks
        XCTAssertTrue(coordinator.shouldSwallowDown(.left))
        XCTAssertFalse(coordinator.isLocked(.left))  // released
    }

    func testButtonsTrackIndependently() {
        let coordinator = makeCoordinator()
        coordinator.noteDown(.left, now: 0.0)
        _ = coordinator.noteUp(.left, now: 0.6)      // left locks
        XCTAssertFalse(coordinator.shouldSwallowDown(.right))
        XCTAssertTrue(coordinator.isLocked(.left))
        XCTAssertFalse(coordinator.isLocked(.right))
    }

    private func makeCoordinator() -> ClickLockCoordinator {
        ClickLockCoordinator(executor: RecordingExecutor(), clock: { [weak self] in self?.now ?? 0 }, threshold: 0.5)
    }
}
```

The executor-posting assertions (lock posts a synthetic up on release) are added in Step 4 after `postButton` wiring — `RecordingExecutor` must gain `postedButtons: [(ButtonID, Bool)]` then. Update the test file in Step 4 accordingly:

```swift
func testLockReleasePostsSyntheticUp() {
    let executor = RecordingExecutor()
    let coordinator = ClickLockCoordinator(executor: executor, clock: { 0 }, threshold: 0.5)
    coordinator.noteDown(.left, now: 0.0)
    _ = coordinator.noteUp(.left, now: 0.6)          // locks
    XCTAssertTrue(coordinator.shouldSwallowDown(.left))
    XCTAssertTrue(executor.postedButtons.contains { $0.0 == .left && $0.1 == false })
}
```

And in `RecordingExecutor` (EventRouterTests.swift):

```swift
final class RecordingExecutor: ActionExecuting {
    private(set) var performed: [Action] = []
    private(set) var holdsBegan: [Action] = []
    private(set) var holdsEnded: [Action] = []
    private(set) var postedButtons: [(ButtonID, Bool)] = []
    func perform(_ action: Action) { performed.append(action) }
    func beganHold(_ action: Action) { holdsBegan.append(action) }
    func endedHold(_ action: Action) { holdsEnded.append(action) }
    func postButton(_ id: ButtonID, down: Bool, mods: ModKeys) { postedButtons.append((id, down)) }
}
```

(Note: `postButton` must live on `ActionExecuting` for this to compile — move `func postButton(_ id: ButtonID, down: Bool, mods: ModKeys)` from `ActionExecutor` into the `ActionExecuting` protocol in Task 8's `EventPosting.swift` and keep the `ActionExecutor` conformance. Do this edit as part of Step 4.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ClickLockCoordinatorTests`
Expected: FAIL — `ClickLockCoordinator` not defined.

- [ ] **Step 3: Write ClickLockCoordinator.swift**

```swift
import Foundation

public final class ClickLockCoordinator: ClickLockCoordinating {
    private enum State {
        case idle
        case pressed(downTime: Double)
        case locked
    }

    private let executor: ActionExecuting
    private let clock: () -> Double
    private let threshold: Double
    private var states: [ButtonID: State] = [:]

    public init(executor: ActionExecuting,
                clock: @escaping () -> Double = { Date().timeIntervalSince1970 },
                threshold: Double = 0.5) {
        self.executor = executor
        self.clock = clock
        self.threshold = threshold
    }

    public func noteDown(_ button: ButtonID, now: Double) {
        if case .locked = state(for: button) {
            executor.postButton(button, down: false, mods: [])   // release sticky down
            states[button] = .idle
            return
        }
        executor.postButton(button, down: true, mods: [])
        states[button] = .pressed(downTime: now)
    }

    public func noteUp(_ button: ButtonID, now: Double) -> Bool {
        switch state(for: button) {
        case .pressed(let downTime):
            if now - downTime >= threshold {
                states[button] = .locked          // swallow physical release
                return true
            }
            executor.postButton(button, down: false, mods: [])
            states[button] = .idle
            return false
        default:
            return false
        }
    }

    public func isLocked(_ button: ButtonID) -> Bool {
        if case .locked = state(for: button) { return true }
        return false
    }

    public func shouldSwallowDown(_ button: ButtonID) -> Bool {
        isLocked(button)
    }

    private func state(for button: ButtonID) -> State {
        states[button] ?? .idle
    }
}
```

- [ ] **Step 4: Wire into EventRouter and protocol**

1. Move `postButton` into `ActionExecuting` (see note in Step 1); update `ActionExecutor` to keep its existing method as the protocol conformance.
2. In `EventRouter.handleDown`, for a click-lock bound button replace the current block with:

```swift
if binding.actions.contains(where: { $0 == .click(.clickLock) }) {
    if clickLock.shouldSwallowDown(button) { return .consume }
    clickLock.noteDown(button, now: Date().timeIntervalSince1970)
    return .consume
}
```

3. Add the `testLockReleasePostsSyntheticUp` test from Step 1 and update `RecordingExecutor` as shown.

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter 'ClickLockCoordinatorTests|EventRouterTests|ActionExecutorTests'`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/ArtMouseCore Tests/ArtMouseCoreTests
git commit -m "Add click lock coordinator wired into router"
```

### Task 10: ActionExecutor — mission, music, zoom, switcher, open

**Files:**
- Create: `Sources/ArtMouseCore/Actions/MediaKeySynthesizer.swift`
- Modify: `Sources/ArtMouseCore/Actions/ActionExecutor.swift` (replace `performAction` stub)
- Create: `Tests/ArtMouseCoreTests/ActionExecutorShortcutTests.swift`, `Tests/ArtMouseCoreTests/MediaKeySynthesizerTests.swift`

**Interfaces:**
- Consumes: `KeyCodes`, `CGFlagConversion`, `EventPosting`, `WorkspaceOpening` (Task 8), mission/music/zoom/switcher/open op enums (Task 3).
- Produces (exact):
  - `enum MediaKeySynthesizer { static func makeEvent(keyCode: Int64, keyDown: Bool) -> CGEvent }` — NX system-defined media event (subtype 8 = media): `data1 = (8 << 16) | (keyCode << 8) | (down ? 0x0A : 0x0B)` into field 41, `data2 = down ? -1 : 0` into field 42, event type `NSEvent.EventType.systemDefined` (raw 14).
  - `enum NXMediaKey { static let soundUp: Int64 = 0; soundDown: Int64 = 1; mute: Int64 = 7; eject: Int64 = 14; rewind: Int64 = 18; fast: Int64 = 19; play: Int64 = 20 }`
  - `extension ActionExecutor { func keyPress(_ keyCode: UInt64, flags: CGEventFlags) }` — down + up pair with given flags (used by shortcut-based ops).

Shortcut table (pinned by tests):

| Op | Posted keys |
|---|---|
| `mission(.missionControl, _)` | ctrl + upArrow |
| `mission(.appWindows, _)` | ctrl + downArrow |
| `mission(.launchpad, _)` | F4 |
| `mission(.showDesktop, _)` | F11 |
| `mission(.desktop(n), _)` | ctrl + digit(n) |
| `mission(.moveSpaceLeft, _)` / `moveSpaceRight` (reverse flips L/R) | ctrl + leftArrow / rightArrow |
| `mission(.spotlight, _)` | cmd + space |
| `mission(.fullscreenButton, _)` | ctrl + cmd + f |
| `zoom(.appZoomIn, _)` / `.appZoomOut` (reverse flips) | cmd + equals / cmd + minus |
| `zoom(.screenZoomIn, _)` / `.screenZoomOut` (reverse flips) | option + cmd + equals / minus |
| `music(op)` | NX media keys: playPause→play, next→fast, previous→rewind, mute→mute, volumeUp→soundUp, volumeDown→soundDown, eject→eject |
| `switcher(.nextApp)` / `.previousApp` | cmd + tab / cmd + shift + tab (tab = keycode 48) |
| `switcher(.applicationWindows)` | ctrl + downArrow |
| `switcher(.app(.bundleID(id)))` | `workspace.launchApp(bundleID:)` |
| `switcher(.app(.url(u)))` | `workspace.openURL(URL)` |
| `switcher(.app(.bookmark(b)))` | resolve bookmark data → URL → open (stale bookmark → no-op) |
| `open(.path(p))` | `workspace.openFile(path:)` |
| `open(.url(u))` | `workspace.openURL(URL)` |
| `mission(.notificationCenter)`, `mission(.siri)`, `zoom(.pinchIn/.pinchOut/.smartZoom)`, `switcher(.showSwitcher)`, `device(.dpi*)`, `device(.switchWheelMode)` | no-op in phase 1 (UI disables) |

- [ ] **Step 1: Write failing tests**

`Tests/ArtMouseCoreTests/ActionExecutorShortcutTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import ArtMouseCore

final class ActionExecutorShortcutTests: XCTestCase {
    func testMissionControlPostsCtrlUp() {
        let poster = RecordingPoster()
        let executor = ActionExecutor(poster: poster)
        executor.perform(.mission(.missionControl, reverse: false))
        XCTAssertEqual(poster.events.count, 2)   // down + up
        XCTAssertEqual(poster.events[0].type, .keyDown)
        XCTAssertEqual(UInt64(poster.events[0].integerValueField(.keyboardEventKeycode)), KeyCodes.upArrow)
        XCTAssertTrue(poster.events[0].flags.contains(.maskControl))
        XCTAssertEqual(poster.events[1].type, .keyUp)
    }

    func testDesktopThreePostsCtrlDigit3() {
        let poster = RecordingPoster()
        let executor = ActionExecutor(poster: poster)
        executor.perform(.mission(.desktop(3), reverse: false))
        XCTAssertEqual(UInt64(poster.events[0].integerValueField(.keyboardEventKeycode)), KeyCodes.digit(3))
        XCTAssertTrue(poster.events[0].flags.contains(.maskControl))
    }

    func testMoveSpaceReverseFlipsDirection() {
        let poster = RecordingPoster()
        let executor = ActionExecutor(poster: poster)
        executor.perform(.mission(.moveSpaceLeft, reverse: true))
        XCTAssertEqual(UInt64(poster.events[0].integerValueField(.keyboardEventKeycode)), KeyCodes.rightArrow)
    }

    func testSpotlightUsesCommandSpace() {
        let poster = RecordingPoster()
        let executor = ActionExecutor(poster: poster)
        executor.perform(.mission(.spotlight, reverse: false))
        XCTAssertEqual(UInt64(poster.events[0].integerValueField(.keyboardEventKeycode)), KeyCodes.space)
        XCTAssertTrue(poster.events[0].flags.contains(.maskCommand))
    }

    func testNextAppPostsCommandTab() {
        let poster = RecordingPoster()
        let executor = ActionExecutor(poster: poster)
        executor.perform(.switcher(.nextApp))
        XCTAssertEqual(UInt64(poster.events[0].integerValueField(.keyboardEventKeycode)), 48)
        XCTAssertTrue(poster.events[0].flags.contains(.maskCommand))
    }

    func testPreviousAppAddsShift() {
        let poster = RecordingPoster()
        let executor = ActionExecutor(poster: poster)
        executor.perform(.switcher(.previousApp))
        XCTAssertTrue(poster.events[0].flags.contains(.maskCommand))
        XCTAssertTrue(poster.events[0].flags.contains(.maskShift))
    }

    func testAppZoomPostsCommandEquals() {
        let poster = RecordingPoster()
        let executor = ActionExecutor(poster: poster)
        executor.perform(.zoom(.appZoomIn, reverse: false))
        XCTAssertEqual(UInt64(poster.events[0].integerValueField(.keyboardEventKeycode)), KeyCodes.equals)
        XCTAssertTrue(poster.events[0].flags.contains(.maskCommand))
    }

    func testScreenZoomPostsOptionCommandEquals() {
        let poster = RecordingPoster()
        let executor = ActionExecutor(poster: poster)
        executor.perform(.zoom(.screenZoomIn, reverse: false))
        XCTAssertTrue(poster.events[0].flags.contains(.maskAlternate))
        XCTAssertTrue(poster.events[0].flags.contains(.maskCommand))
        XCTAssertEqual(UInt64(poster.events[0].integerValueField(.keyboardEventKeycode)), KeyCodes.equals)
    }

    func testDeferredOpsPostNothing() {
        let poster = RecordingPoster()
        let executor = ActionExecutor(poster: poster)
        executor.perform(.mission(.notificationCenter, reverse: false))
        executor.perform(.mission(.siri, reverse: false))
        executor.perform(.zoom(.pinchIn, reverse: false))
        executor.perform(.zoom(.smartZoom, reverse: false))
        executor.perform(.switcher(.showSwitcher))
        executor.perform(.device(.dpiCycle))
        executor.perform(.device(.switchWheelMode))
        XCTAssertTrue(poster.events.isEmpty)
    }
}

final class StubOpener: WorkspaceOpening {
    private(set) var launched: [String] = []
    private(set) var openedURLs: [URL] = []
    private(set) var openedFiles: [String] = []
    func launchApp(bundleID: String) { launched.append(bundleID) }
    func openURL(_ url: URL) { openedURLs.append(url) }
    func openFile(path: String) { openedFiles.append(path) }
}

final class ActionExecutorSwitcherTests: XCTestCase {
    func testSwitchToAppByBundleID() {
        let poster = RecordingPoster()
        let opener = StubOpener()
        let executor = ActionExecutor(poster: poster, workspace: opener)
        executor.perform(.switcher(.app(.bundleID("com.apple.Safari"))))
        XCTAssertEqual(opener.launched, ["com.apple.Safari"])
    }

    func testOpenPathAndURL() {
        let opener = StubOpener()
        let executor = ActionExecutor(poster: RecordingPoster(), workspace: opener)
        executor.perform(.open(.path("/tmp")))
        executor.perform(.open(.url("https://example.com")))
        XCTAssertEqual(opener.openedFiles, ["/tmp"])
        XCTAssertEqual(opener.openedURLs.map(\.absoluteString), ["https://example.com"])
    }

    func testOpenInvalidURLOnlyMarksOneEvent() {
        let opener = StubOpener()
        let executor = ActionExecutor(poster: RecordingPoster(), workspace: opener)
        executor.perform(.open(.url("::::not-a-url")))
        XCTAssertTrue(opener.openedURLs.isEmpty)   // invalid URL is a no-op, not a crash
    }
}
```

`Tests/ArtMouseCoreTests/MediaKeySynthesizerTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import ArtMouseCore

final class MediaKeySynthesizerTests: XCTestCase {
    func testPlayKeyDownEncoding() {
        let event = MediaKeySynthesizer.makeEvent(keyCode: NXMediaKey.play, keyDown: true)
        XCTAssertEqual(event.type, CGEventType(rawValue: NSEvent.EventType.systemDefined.rawValue))
        let data1 = event.integerValueField(CGEventField(rawValue: 41))
        XCTAssertEqual(data1, (8 << 16) | (NXMediaKey.play << 8) | 0x0A)
        XCTAssertEqual(event.integerValueField(CGEventField(rawValue: 42)), -1)
    }

    func testKeyUpEncoding() {
        let event = MediaKeySynthesizer.makeEvent(keyCode: NXMediaKey.fast, keyDown: false)
        let data1 = event.integerValueField(CGEventField(rawValue: 41))
        XCTAssertEqual(data1, (8 << 16) | (NXMediaKey.fast << 8) | 0x0B)
        XCTAssertEqual(event.integerValueField(CGEventField(rawValue: 42)), 0)
    }

    func testMusicOpsPostPressAndRelease() {
        let poster = RecordingPoster()
        let executor = ActionExecutor(poster: poster)
        executor.perform(.music(.playPause, fineTune: false))
        XCTAssertEqual(poster.events.count, 2)   // press + release of system-defined event
        XCTAssertEqual(poster.events[0].type.rawValue, NSEvent.EventType.systemDefined.rawValue)
    }
}
```

(Add `import AppKit` to both test files for `NSEvent`.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter 'ActionExecutorShortcutTests|ActionExecutorSwitcherTests|MediaKeySynthesizerTests'`
Expected: FAIL — synthesizer missing, stub dispatch no-ops.

- [ ] **Step 3: Write MediaKeySynthesizer.swift**

```swift
import CoreGraphics

/// NX system-defined media key constants (classic SPMediaKeyTap table).
public enum NXMediaKey {
    public static let soundUp: Int64 = 0
    public static let soundDown: Int64 = 1
    public static let mute: Int64 = 7
    public static let eject: Int64 = 14
    public static let rewind: Int64 = 18
    public static let fast: Int64 = 19
    public static let play: Int64 = 20
}

public enum MediaKeySynthesizer {
    /// NSSystemDefinedEventSubtypeMedia = 8; 0x0A key-down, 0x0B key-up.
    public static func makeEvent(keyCode: Int64, keyDown: Bool) -> CGEvent {
        let event = CGEvent(source: nil)!
        event.type = CGEventType(rawValue: NSEvent.EventType.systemDefined.rawValue)!
        let data1 = (Int64(8) << 16) | (keyCode << 8) | (keyDown ? 0x0A : 0x0B)
        event.setIntegerValueField(CGEventField(rawValue: 41), value: data1)
        event.setIntegerValueField(CGEventField(rawValue: 42), value: keyDown ? -1 : 0)
        return event
    }
}
```

(`import AppKit` required for `NSEvent`.)

- [ ] **Step 4: Fill in ActionExecutor.performAction**

Replace the Task 8 stub:

```swift
private func performAction(_ action: Action) {
    switch action {
    case .mission(let op, let reverse):
        performMission(op, reverse: reverse)
    case .music(let op, _):
        performMusic(op)
    case .zoom(let op, let reverse):
        performZoom(op, reverse: reverse)
    case .switcher(let op):
        performSwitcher(op)
    case .open(let target):
        performOpen(target)
    default:
        break   // device ops (Task 13), deferred ops no-op
    }
}

private func keyPress(_ keyCode: UInt64, flags: CGEventFlags) {
    let down = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: true, flags: flags)!
    poster.post(down)
    let up = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: false, flags: flags)!
    poster.post(up)
}

private func performMission(_ op: MissionOp, reverse: Bool) {
    let ctrl: CGEventFlags = [.maskControl]
    switch op {
    case .missionControl: keyPress(KeyCodes.upArrow, flags: ctrl)
    case .appWindows: keyPress(KeyCodes.downArrow, flags: ctrl)
    case .launchpad: keyPress(KeyCodes.f4, flags: [])
    case .showDesktop: keyPress(KeyCodes.f11, flags: [])
    case .desktop(let n): keyPress(KeyCodes.digit(n), flags: ctrl)
    case .moveSpaceLeft: keyPress(reverse ? KeyCodes.rightArrow : KeyCodes.leftArrow, flags: ctrl)
    case .moveSpaceRight: keyPress(reverse ? KeyCodes.leftArrow : KeyCodes.rightArrow, flags: ctrl)
    case .spotlight: keyPress(KeyCodes.space, flags: [.maskCommand])
    case .fullscreenButton: keyPress(KeyCodes.f, flags: [.maskControl, .maskCommand])
    case .notificationCenter, .siri:
        break   // deferred (phase 4); UI disables
    }
}

private func performMusic(_ op: MusicOp) {
    let keyCode: Int64
    switch op {
    case .playPause: keyCode = NXMediaKey.play
    case .next: keyCode = NXMediaKey.fast
    case .previous: keyCode = NXMediaKey.rewind
    case .mute: keyCode = NXMediaKey.mute
    case .volumeUp: keyCode = NXMediaKey.soundUp
    case .volumeDown: keyCode = NXMediaKey.soundDown
    case .eject: keyCode = NXMediaKey.eject
    }
    poster.post(MediaKeySynthesizer.makeEvent(keyCode: keyCode, keyDown: true))
    poster.post(MediaKeySynthesizer.makeEvent(keyCode: keyCode, keyDown: false))
}

private func performZoom(_ op: ZoomOp, reverse: Bool) {
    switch op {
    case .appZoomIn, .appZoomOut:
        let zoomIn = (op == .appZoomIn) != reverse
        keyPress(zoomIn ? KeyCodes.equals : KeyCodes.minus, flags: [.maskCommand])
    case .screenZoomIn, .screenZoomOut:
        let zoomIn = (op == .screenZoomIn) != reverse
        keyPress(zoomIn ? KeyCodes.equals : KeyCodes.minus, flags: [.maskAlternate, .maskCommand])
    case .pinchIn, .pinchOut, .smartZoom:
        break   // deferred gesture emulation (phase 4); UI disables
    }
}

private func performSwitcher(_ op: SwitcherOp) {
    switch op {
    case .nextApp: keyPress(48, flags: [.maskCommand])
    case .previousApp: keyPress(48, flags: [.maskCommand, .maskShift])
    case .applicationWindows: keyPress(KeyCodes.downArrow, flags: [.maskControl])
    case .showSwitcher: break   // deferred custom overlay (phase 4)
    case .app(let target):
        switch target {
        case .bundleID(let id): workspace.launchApp(bundleID: id)
        case .url(let string):
            if let url = URL(string: string) { workspace.openURL(url) }
        case .bookmark(let base64):
            guard let data = Data(base64Encoded: base64) else { return }
            var isStale = false
            if let url = try? URL(resolvingBookmarkData: data, options: [],
                                  relativeTo: nil, bookmarkDataIsStale: &isStale) {
                workspace.openURL(url)
            }
        }
    }
}

private func performOpen(_ target: OpenTarget) {
    switch target {
    case .path(let p): workspace.openFile(path: p)
    case .url(let string):
        if let url = URL(string: string) { workspace.openURL(url) }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter 'ActionExecutor|MediaKeySynthesizer|EventRouter|ClickLock'`
Expected: PASS (all executor-family suites).

- [ ] **Step 6: Commit**

```bash
git add Sources/ArtMouseCore/Actions Tests/ArtMouseCoreTests
git commit -m "Add mission, music, zoom, switcher and open actions"
```

### Task 11: Cursor math (pure functions)

**Files:**
- Create: `Sources/ArtMouseCore/Cursor/CursorMath.swift`
- Create: `Tests/ArtMouseCoreTests/CursorMathTests.swift`

**Interfaces:**
- Consumes: `CursorSpeedProfile` (Task 4).
- Produces (exact):
  - `enum CursorMath { static func sensitivityFactor(_ sensitivity: Double) -> Double; static func accelerationFactor(acceleration: Double, speed: Double) -> Double; static func deltaFactor(profile: CursorSpeedProfile, speed: Double) -> (dxFactor: Double, dyFactor: Double) }`
  - Constants: `systemNeutralSensitivity = 1600.0`, `accelerationReferenceSpeed = 8.0`.

Model (spec §4 CursorController; SteerMouse's SpeedHelp semantics — "Acceleration affects cursor speed while the mouse is moved quickly; Sensitivity affects cursor speed while the mouse is moved slowly"):
- `sensitivityFactor(s) = s / 1600.0` — uniform scale on every event.
- `accelerationFactor(a, speed) = 1 + a * (speed / 8.0)` where `speed = hypot(dx, dy)` in points/event; at rest (speed 0) it is exactly 1 regardless of `a`, so acceleration only affects fast movement. Linear v1 curve; the reference-speed constant is the tuning knob.
- `deltaFactor` = product of both, applied uniformly to dx and dy.

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
@testable import ArtMouseCore

final class CursorMathTests: XCTestCase {
    func testSensitivityScalesLinearly() {
        XCTAssertEqual(CursorMath.sensitivityFactor(1600), 1.0, accuracy: 1e-12)
        XCTAssertEqual(CursorMath.sensitivityFactor(800), 0.5, accuracy: 1e-12)
        XCTAssertEqual(CursorMath.sensitivityFactor(3200), 2.0, accuracy: 1e-12)
    }

    func testAccelerationIsOneAtRest() {
        XCTAssertEqual(CursorMath.accelerationFactor(acceleration: 3.0, speed: 0), 1.0, accuracy: 1e-12)
    }

    func testAccelerationGrowsWithSpeed() {
        let slow = CursorMath.accelerationFactor(acceleration: 1.0, speed: 2)
        let fast = CursorMath.accelerationFactor(acceleration: 1.0, speed: 16)
        XCTAssertEqual(slow, 1.25, accuracy: 1e-12)
        XCTAssertEqual(fast, 3.0, accuracy: 1e-12)
        XCTAssertLessThan(slow, fast)
    }

    func testZeroAccelerationIsAlwaysOne() {
        for speed in [0.0, 1.0, 5.0, 20.0, 100.0] {
            XCTAssertEqual(CursorMath.accelerationFactor(acceleration: 0, speed: speed), 1.0, accuracy: 1e-12)
        }
    }

    func testDeltaFactorCombinesBoth() {
        let profile = CursorSpeedProfile(name: "T", sensitivity: 800, acceleration: 1.0)
        let factor = CursorMath.deltaFactor(profile: profile, speed: 8)   // speed = reference
        XCTAssertEqual(factor.dxFactor, 0.5 * 2.0, accuracy: 1e-12)
        XCTAssertEqual(factor.dyFactor, 0.5 * 2.0, accuracy: 1e-12)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CursorMathTests`
Expected: FAIL — `CursorMath` not defined.

- [ ] **Step 3: Write CursorMath.swift**

```swift
import Foundation

public enum CursorMath {
    /// Sensitivity value that produces a 1.0 scale (macOS default behavior).
    public static let systemNeutralSensitivity = 1600.0
    /// Speed (points/event) at which acceleration contributes +1.0 × acceleration.
    public static let accelerationReferenceSpeed = 8.0

    public static func sensitivityFactor(_ sensitivity: Double) -> Double {
        sensitivity / systemNeutralSensitivity
    }

    /// Linear acceleration curve: exactly 1 at rest, grows with speed.
    /// (v1 curve; SteerMouse-exact curves are a later tuning pass.)
    public static func accelerationFactor(acceleration: Double, speed: Double) -> Double {
        1 + acceleration * (speed / accelerationReferenceSpeed)
    }

    public static func deltaFactor(profile: CursorSpeedProfile, speed: Double) -> (dxFactor: Double, dyFactor: Double) {
        let factor = sensitivityFactor(profile.sensitivity) * accelerationFactor(acceleration: profile.acceleration, speed: speed)
        return (factor, factor)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CursorMathTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/ArtMouseCore/Cursor Tests/ArtMouseCoreTests/CursorMathTests.swift
git commit -m "Add cursor sensitivity and acceleration math"
```

### Task 12: CursorController — profiles, precision hold, 5 s safety restore

**Files:**
- Create: `Sources/ArtMouseCore/Cursor/CursorController.swift`
- Create: `Tests/ArtMouseCoreTests/CursorControllerTests.swift`

**Interfaces:**
- Consumes: `CursorMath` (Task 11), `GlobalSettings` (Task 4), `CursorControlling`/`RouterOutcome` (Tasks 6–7).
- Produces (exact):
  - `final class CursorController: CursorControlling { init(store: SettingsStore, clock: @escaping () -> Double = { Date().timeIntervalSince1970 }); func outcome(forMove event: InputEvent) -> RouterOutcome; func activate(profileID: UUID, source: ProfileSwitchSource); func activateNext(source: ProfileSwitchSource); func beginPrecision(); func endPrecision(); var activeProfile: CursorSpeedProfile? { get }; var safetyRestoreWarning: String? { get } }`
  - `enum ProfileSwitchSource: Equatable { case user; case buttonAction }`

Behavior (pinned by tests):
- `outcome(forMove:)` → `.cursorTransform` computed via `CursorMath.deltaFactor` using the *effective* profile (precision profile while `beginPrecision()` is active, else active profile); `.moved` uses its dx/dy to derive speed.
- `activate(profileID:, source: .user)` → switches persistently, cancels any pending restore, clears warning.
- `activate(profileID:, source: .buttonAction)` → switches AND schedules restore to the pre-switch profile at `now + 5.0`; sets `safetyRestoreWarning` (Review Focus #1). A second button activation re-arms the timer (extends), not a second restore target.
- Restore fires: active profile returns to the pre-button-switch profile, warning clears. Firing is driven by the engine calling `tick()` — add `func tick()` which checks the clock (keeps the controller synchronous and testable; the engine calls it from a 0.5 s timer).

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
@testable import ArtMouseCore

final class CursorControllerTests: XCTestCase {
    private var now = 0.0

    private func makeStore() -> SettingsStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return SettingsStore(directory: dir)
    }

    private func makeController(_ store: SettingsStore) -> CursorController {
        CursorController(store: store, clock: { [weak self] in self?.now ?? 0 })
    }

    // Default profile: sensitivity 1600 (factor 1.0), acceleration 1.0.
    // .moved(dx: 4) → speed = 4 → accel factor = 1 + 1×(4/8) = 1.5 → total 1.5.
    func testOutcomeUsesActiveProfileTransform() {
        let store = makeStore()
        let controller = makeController(store)
        XCTAssertEqual(controller.outcome(forMove: .moved(dx: 4, dy: 0)),
                       .cursorTransform(dxFactor: 1.5, dyFactor: 1.5))
    }

    func testUserSwitchPersistsAndCancelsRestore() {
        let store = makeStore()
        let controller = makeController(store)
        let slow = store.settings.cursorSpeedProfiles[0]
        controller.activate(profileID: slow.id, source: .user)
        XCTAssertEqual(controller.activeProfile, slow)
        now += 10
        controller.tick()
        XCTAssertEqual(controller.activeProfile, slow)      // no auto-restore for user switches
        XCTAssertNil(controller.safetyRestoreWarning)
    }

    func testButtonSwitchRestoresAfterFiveSeconds() {
        let store = makeStore()
        let controller = makeController(store)
        let profiles = store.settings.cursorSpeedProfiles
        let fast = profiles[2]                              // Fast

        controller.activate(profileID: fast.id, source: .buttonAction)
        XCTAssertEqual(controller.activeProfile, fast)
        XCTAssertNotNil(controller.safetyRestoreWarning)    // visible warning (Review Focus #1)

        now += 4
        controller.tick()
        XCTAssertEqual(controller.activeProfile, fast)      // not yet

        now += 1.5                                          // 5.5 s total
        controller.tick()
        XCTAssertEqual(controller.activeProfile, profiles[1])   // restored to Default
        XCTAssertNil(controller.safetyRestoreWarning)
    }

    func testSecondButtonSwitchReArmsTimer() {
        let store = makeStore()
        let controller = makeController(store)
        let profiles = store.settings.cursorSpeedProfiles

        controller.activate(profileID: profiles[0].id, source: .buttonAction)   // Slow
        now += 4
        controller.tick()
        controller.activate(profileID: profiles[2].id, source: .buttonAction)   // Fast, re-arm
        now += 4
        controller.tick()
        XCTAssertEqual(controller.activeProfile, profiles[2])   // still Fast (timer re-armed 4 s ago)
        now += 1.5
        controller.tick()
        XCTAssertEqual(controller.activeProfile, profiles[1])   // restored
    }

    // Slow: sensitivity 800 (0.5), acceleration 0 (1.0) → 0.5.
    // Fast: sensitivity 3200 (2.0), acceleration 2.0 → at speed 8: 1 + 2×1 = 3.0 → 6.0.
    func testPrecisionHoldOverridesActiveProfile() {
        let store = makeStore()
        var settings = store.settings
        settings.precisionProfileID = settings.cursorSpeedProfiles[0].id   // Slow
        settings.activeCursorSpeedProfileID = settings.cursorSpeedProfiles[2].id   // Fast
        store.settings = settings
        let controller = makeController(store)

        controller.beginPrecision()
        XCTAssertEqual(controller.outcome(forMove: .moved(dx: 8, dy: 0)),
                       .cursorTransform(dxFactor: 0.5, dyFactor: 0.5))
        controller.endPrecision()
        XCTAssertEqual(controller.outcome(forMove: .moved(dx: 8, dy: 0)),
                       .cursorTransform(dxFactor: 6.0, dyFactor: 6.0))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CursorControllerTests`
Expected: FAIL — `CursorController` not defined.

- [ ] **Step 3: Write CursorController.swift**

```swift
import Foundation

public enum ProfileSwitchSource: Equatable {
    case user
    case buttonAction
}

/// Resolves cursor speed profiles into event transforms; owns profile
/// switching, precision hold, and the 5 s safety restore (spec §7).
public final class CursorController: CursorControlling {
    static let safetyRestoreDelay: Double = 5.0
    static let restoreWarningText = "Cursor speed was switched by a button. Restoring the previous speed in 5 seconds."

    private let store: SettingsStore
    private let clock: () -> Double

    private var pendingRestore: (target: UUID, at: Double)?
    private var precisionActive = false
    private(set) public var safetyRestoreWarning: String?

    public init(store: SettingsStore, clock: @escaping () -> Double = { Date().timeIntervalSince1970 }) {
        self.store = store
        self.clock = clock
    }

    public var activeProfile: CursorSpeedProfile? {
        store.settings.activeProfile
    }

    public func outcome(forMove event: InputEvent) -> RouterOutcome {
        let (dx, dy): (Double, Double)
        switch event {
        case .moved(let x, let y), .dragged(let x, let y): (dx, dy) = (x, y)
        default: return .passThrough
        }
        guard let profile = effectiveProfile() else { return .passThrough }
        let speed = (dx * dx + dy * dy).squareRoot()
        let factor = CursorMath.deltaFactor(profile: profile, speed: speed)
        return .cursorTransform(dxFactor: factor.dxFactor, dyFactor: factor.dyFactor)
    }

    public func activate(profileID: UUID, source: ProfileSwitchSource) {
        switch source {
        case .user:
            pendingRestore = nil
            safetyRestoreWarning = nil
        case .buttonAction:
            if pendingRestore == nil, let current = store.settings.activeProfile?.id {
                pendingRestore = (target: current, at: clock() + Self.safetyRestoreDelay)
                safetyRestoreWarning = Self.restoreWarningText
            } else if pendingRestore != nil {
                pendingRestore?.at = clock() + Self.safetyRestoreDelay   // re-arm
            }
        }
        store.settings.activeCursorSpeedProfileID = profileID
    }

    public func activateNext(source: ProfileSwitchSource) {
        let profiles = store.settings.cursorSpeedProfiles
        guard let current = activeProfile,
              let index = profiles.firstIndex(where: { $0.id == current.id }) else { return }
        let next = profiles[(index + 1) % profiles.count]
        activate(profileID: next.id, source: source)
    }

    public func beginPrecision() { precisionActive = true }
    public func endPrecision() { precisionActive = false }

    /// Called on a timer (engine wiring, Task 15) to fire due restores.
    public func tick() {
        guard let restore = pendingRestore, clock() >= restore.at else { return }
        store.settings.activeCursorSpeedProfileID = restore.target
        pendingRestore = nil
        safetyRestoreWarning = nil
    }

    private func effectiveProfile() -> CursorSpeedProfile? {
        if precisionActive, let id = store.settings.precisionProfileID,
           let match = store.settings.cursorSpeedProfiles.first(where: { $0.id == id }) {
            return match
        }
        return store.settings.activeProfile
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CursorControllerTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/ArtMouseCore/Cursor Tests/ArtMouseCoreTests/CursorControllerTests.swift
git commit -m "Add cursor controller with profiles and safety restore"
```

### Task 13: Wire device ops into ActionExecutor (profile switching, precision hold)

**Files:**
- Modify: `Sources/ArtMouseCore/Actions/ActionExecutor.swift`
- Create: `Tests/ArtMouseCoreTests/DeviceOpTests.swift`

**Interfaces:**
- Consumes: `ActionExecutor` (Tasks 8, 10), `CursorController` (Task 12).
- Produces (exact): `ActionExecutor` gains `init(poster:workspace:cursor:)` where `cursor: CursorCoordinating? = nil`, with `protocol CursorCoordinating: AnyObject { func activateNext(source: ProfileSwitchSource); func beginPrecision(); func endPrecision() }` (`CursorController` conforms). Device-op dispatch: `.device(.activateCursorSpeed)` → `cursor?.activateNext(source: .buttonAction)`; `.device(.switchPrecisionMode)` — handled through hold lifecycle, not `perform`; hold dispatch changes: `beganHold(.device(.switchPrecisionMode))` → `cursor?.beginPrecision()`, `endedHold(...)` → `cursor?.endPrecision()`. DPI/wheel-mode ops stay no-ops.

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
@testable import ArtMouseCore

final class DeviceOpTests: XCTestCase {
    private func makeStore() -> SettingsStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return SettingsStore(directory: dir)
    }

    func testActivateCursorSpeedAdvancesProfile() {
        let store = makeStore()
        let controller = CursorController(store: store)
        let executor = ActionExecutor(poster: RecordingPoster(), cursor: controller)
        XCTAssertEqual(controller.activeProfile?.name, "Default")
        executor.perform(.device(.activateCursorSpeed(nil)))
        XCTAssertEqual(controller.activeProfile?.name, "Fast")     // next in default order
    }

    func testPrecisionHoldLifecycle() {
        let store = makeStore()
        var settings = store.settings
        settings.precisionProfileID = settings.cursorSpeedProfiles[0].id
        store.settings = settings
        let controller = CursorController(store: store)
        let executor = ActionExecutor(poster: RecordingPoster(), cursor: controller)

        executor.beganHold(.device(.switchPrecisionMode))
        XCTAssertEqual(controller.outcome(forMove: .moved(dx: 8, dy: 0)),
                       .cursorTransform(dxFactor: 0.5, dyFactor: 0.5))   // Slow active while held
        executor.endedHold(.device(.switchPrecisionMode))
        XCTAssertNotEqual(controller.outcome(forMove: .moved(dx: 8, dy: 0)),
                          .cursorTransform(dxFactor: 0.5, dyFactor: 0.5))
    }

    func testDPIAndWheelOpsAreNoOps() {
        let executor = ActionExecutor(poster: RecordingPoster(), cursor: nil)
        executor.perform(.device(.dpiCycle))
        executor.perform(.device(.dpiUp))
        executor.perform(.device(.dpiDown))
        executor.perform(.device(.dpiShift))
        executor.perform(.device(.defaultDPI))
        executor.perform(.device(.switchWheelMode))
        // no crash, no state change; UI disables these (Task 16)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter DeviceOpTests`
Expected: FAIL — `ActionExecutor(poster:cursor:)` missing.

- [ ] **Step 3: Implement**

In `ActionExecutor`:

```swift
public protocol CursorCoordinating: AnyObject {
    func activateNext(source: ProfileSwitchSource)
    func beginPrecision()
    func endPrecision()
}

public final class ActionExecutor: ActionExecuting {
    private let poster: EventPosting
    private let workspace: WorkspaceOpening
    private weak var cursor: CursorCoordinating?

    public init(poster: EventPosting,
                workspace: WorkspaceOpening = NSWorkspaceOpener(),
                cursor: CursorCoordinating? = nil) {
        self.poster = poster
        self.workspace = workspace
        self.cursor = cursor
    }

    public func beganHold(_ action: Action) {
        if case .device(.switchPrecisionMode) = action { cursor?.beginPrecision() }
    }

    public func endedHold(_ action: Action) {
        if case .device(.switchPrecisionMode) = action { cursor?.endPrecision() }
    }
    // performAction: replace `default: break` device arm with:
    //   case .device(let op): performDevice(op)
}

private func performDevice(_ op: DeviceOp) {
    switch op {
    case .activateCursorSpeed: cursor?.activateNext(source: .buttonAction)
    case .switchPrecisionMode: break   // hold lifecycle, not a tap action
    case .dpiCycle, .dpiUp, .dpiDown, .dpiShift, .defaultDPI, .switchWheelMode:
        break   // phases 2/4; UI disables
    }
}
```

(Place `CursorCoordinating` in `Cursor/CursorController.swift` — `CursorController` gets the conformance for free; keep the executor's `cursor` reference weak to avoid a retain cycle through the router graph.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter DeviceOpTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/ArtMouseCore Tests/ArtMouseCoreTests/DeviceOpTests.swift
git commit -m "Wire device ops to cursor profile switching"
```

### Task 14: Permissions controller and engine bootstrap (safe mode)

**Files:**
- Create: `Sources/ArtMouseCore/Engine/BootstrapDecision.swift`
- Create: `Sources/artMouse/PermissionsController.swift`, `Sources/artMouse/EngineBootstrap.swift`
- Create: `Tests/ArtMouseCoreTests/BootstrapDecisionTests.swift`
- Modify: `Sources/artMouse/AppDelegate.swift` (call bootstrap; thin delegate)

**Interfaces:**
- Consumes: everything above (full stack assembly).
- Produces (exact):
  - `enum PermissionState: Equatable { case granted; case denied }` (app target)
  - `final class PermissionsController: ObservableObject { @Published var accessibility: PermissionState; @Published var inputMonitoring: PermissionState; func refresh(); func reportTapCreation(_ succeeded: Bool); func promptAccessibility(); static func deepLinkToInputMonitoring() }` (app target)
  - `enum BootstrapDecision { static func shouldRunEngine(arguments: [String], flagsAtLaunch: ModKeys) -> Bool; static func currentFlags() -> ModKeys }` (ArtMouseCore) — false when `--safe-mode` in arguments OR both `.command` and `.option` held at launch (Review Focus #4).
  - `final class EngineBootstrap { init(devices: DeviceManager, permissions: PermissionsController); func start(store: SettingsStore) }` (app target) — owns CursorController, ClickLockCoordinator, ActionExecutor, EventRouter, EventTapEngine, a 0.5 s cursor-tick timer, and a 2 s device-refresh timer. AppDelegate creates `SettingsStore` and `DeviceManager` so Task 16's `AppModel` shares the same instances.

- [ ] **Step 1: Write failing bootstrap-decision tests**

`Tests/ArtMouseCoreTests/BootstrapDecisionTests.swift`:

```swift
import XCTest
@testable import ArtMouseCore

final class BootstrapDecisionTests: XCTestCase {
    func testNormalLaunchRunsEngine() {
        XCTAssertTrue(BootstrapDecision.shouldRunEngine(arguments: [], flagsAtLaunch: []))
    }

    func testSafeModeFlagDisablesEngine() {
        XCTAssertFalse(BootstrapDecision.shouldRunEngine(arguments: ["--safe-mode"], flagsAtLaunch: []))
    }

    func testCommandOptionHeldAtLaunchDisablesEngine() {
        XCTAssertFalse(BootstrapDecision.shouldRunEngine(arguments: [], flagsAtLaunch: [.command, .option]))
        XCTAssertTrue(BootstrapDecision.shouldRunEngine(arguments: [], flagsAtLaunch: [.command]))
        XCTAssertTrue(BootstrapDecision.shouldRunEngine(arguments: [], flagsAtLaunch: [.option, .shift]))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter BootstrapDecisionTests`
Expected: FAIL — not defined.

- [ ] **Step 3: Implement BootstrapDecision in ArtMouseCore**

`Sources/ArtMouseCore/Engine/BootstrapDecision.swift`:

```swift
import CoreGraphics

public enum BootstrapDecision {
    /// Engine runs unless --safe-mode is passed or ⌥⌘ held at launch.
    public static func shouldRunEngine(arguments: [String], flagsAtLaunch: ModKeys) -> Bool {
        if arguments.contains("--safe-mode") { return false }
        if flagsAtLaunch.contains(.command) && flagsAtLaunch.contains(.option) { return false }
        return true
    }

    /// Modifier state at process start (no posted events exist yet).
    public static func currentFlags() -> ModKeys {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        var result: ModKeys = []
        if flags.contains(.maskCommand) { result.insert(.command) }
        if flags.contains(.maskControl) { result.insert(.control) }
        if flags.contains(.maskAlternate) { result.insert(.option) }
        if flags.contains(.maskShift) { result.insert(.shift) }
        return result
    }
}
```

- [ ] **Step 4: Write PermissionsController.swift (app target)**

```swift
import AppKit
import ApplicationServices

enum PermissionState: Equatable {
    case granted, denied
}

final class PermissionsController: ObservableObject {
    @Published var accessibility: PermissionState = .denied
    @Published var inputMonitoring: PermissionState = .denied

    func refresh() {
        accessibility = AXIsProcessTrusted() ? .granted : .denied
        // Input Monitoring cannot be queried directly; the tap creation
        // result reported through reportTapCreation drives `inputMonitoring`.
    }

    func reportTapCreation(_ succeeded: Bool) {
        inputMonitoring = succeeded ? .granted : .denied
    }

    func promptAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func deepLinkToInputMonitoring() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_InputMonitoring") {
            NSWorkspace.shared.open(url)
        }
    }
}
```

- [ ] **Step 5: Write EngineBootstrap.swift (app target)**

```swift
import AppKit
import ArtMouseCore

/// Assembles the engine stack and owns its timers. The SettingsStore and
/// DeviceManager are created by AppDelegate and shared with the UI (Task 16).
final class EngineBootstrap {
    private let permissions: PermissionsController
    private let devices: DeviceManager
    private var cursor: CursorController?
    private var engine: EventTapEngine?
    private var tickTimer: Timer?
    private var deviceTimer: Timer?

    init(devices: DeviceManager, permissions: PermissionsController) {
        self.permissions = permissions
        self.devices = devices
    }

    func start(store: SettingsStore) {
        let cursorController = CursorController(store: store)
        self.cursor = cursorController

        let executor = ActionExecutor(poster: CGEventPoster(), cursor: cursorController)
        let clickLock = ClickLockCoordinator(executor: executor)
        let router = EventRouter(settings: store, executor: executor,
                                 clickLock: clickLock, cursor: cursorController)
        let tapEngine = EventTapEngine(router: router, tapFactory: CGEventTapFactory())
        self.engine = tapEngine

        let started = tapEngine.start()
        permissions.reportTapCreation(started)
        permissions.refresh()

        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak cursorController] _ in
            cursorController?.tick()
        }
        deviceTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak devices] _ in
            devices?.refresh()
        }
    }
    // Tap-loss observation (`tapActive`) is added to this class in Task 15.
}
```

- [ ] **Step 6: Wire AppDelegate**

Replace the Task 2 `startEngine()` stub and `applicationDidFinishLaunching` engine call:

```swift
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var permissions: PermissionsController?
    private var bootstrap: EngineBootstrap?
    private var store: SettingsStore?           // shared with AppModel in Task 16
    private var devices: DeviceManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // ... menu setup from Task 2 unchanged ...

        let permissions = PermissionsController()
        self.permissions = permissions
        if BootstrapDecision.shouldRunEngine(arguments: CommandLine.arguments,
                                             flagsAtLaunch: BootstrapDecision.currentFlags()) {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let directory = appSupport.appendingPathComponent("artMouse", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let store = SettingsStore(directory: directory)
            let devices = DeviceManager(enumerator: IOKitDeviceEnumerator())
            self.store = store
            self.devices = devices
            let bootstrap = EngineBootstrap(devices: devices, permissions: permissions)
            bootstrap.start(store: store)
            self.bootstrap = bootstrap
        }
    }
    // startEngine() from Task 2 is deleted.
}
```

- [ ] **Step 7: Run tests, then manual smoke**

Run: `swift test --filter BootstrapDecisionTests`
Expected: PASS (3 tests).

Manual: build and launch; grant Accessibility when the prompt appears; with the Default profile active, slow cursor movement should feel identical to stock macOS (factor ≈ 1.0), faster movement slightly amplified (acceleration 1.0). Bind nothing yet.

- [ ] **Step 8: Commit**

```bash
git add Sources Tests/ArtMouseCoreTests/BootstrapDecisionTests.swift
git commit -m "Add permission flow and engine bootstrap with safe mode"
```

### Task 15: Tap-loss detection in EventTapEngine

**Files:**
- Modify: `Sources/ArtMouseCore/Engine/EventTapEngine.swift`
- Modify: `Tests/ArtMouseCoreTests/EventTapEngineTests.swift`

**Interfaces:**
- Consumes: EventTapEngine (Task 6).
- Produces (exact): `EventTapEngine` gains `@Published public var tapActive: Bool = false` and `public var tapActivePublisher: Published<Bool>.Publisher { $tapActive }`. Rules: `tapActive` becomes true when `start()` succeeds and after any successful re-enable; when a `tapDisabledByTimeout`/`tapDisabledByUserInput` event arrives, the engine re-enables and, if the tap still reports disabled afterward, sets `tapActive = false` (Review Focus #3 — the bootstrap surfaces the banner from this).

- [ ] **Step 1: Write failing tests**

Append to `EventTapEngineTests`:

```swift
func testTapActiveTracksLifecycle() {
    let tap = MockTap()
    let engine = EventTapEngine(router: PassThroughRouter(), tapFactory: MockTapFactory(tap: tap))
    XCTAssertFalse(engine.tapActive)
    XCTAssertTrue(engine.start())
    XCTAssertTrue(engine.tapActive)
    tap.disable()
    tap.emit(CGEvent(source: nil)!, type: .tapDisabledByTimeout)   // mock tap stays disabled
    XCTAssertFalse(engine.tapActive)
    tap.enable()                                                   // simulated recovery
    tap.emit(CGEvent(source: nil)!, type: .leftMouseDown)
    XCTAssertTrue(engine.tapActive)
}

func testStopResetsTapActive() {
    let tap = MockTap()
    let engine = EventTapEngine(router: PassThroughRouter(), tapFactory: MockTapFactory(tap: tap))
    engine.start()
    engine.stop()
    XCTAssertFalse(engine.tapActive)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter EventTapEngineTests`
Expected: new tests FAIL (`tapActive` missing); old tests stay green.

- [ ] **Step 3: Implement**

In `EventTapEngine`:

```swift
@Published public private(set) var tapActive: Bool = false

// in start(): after tap = handle
tapActive = true

// in stop(): tapActive = false

// in process(), replace the tapDisabled branch:
if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
    tap?.enable()
    if let tap = tap, !tap.isEnabled {
        tapActive = false       // re-enable failed — surface the banner
    } else {
        tapActive = true
    }
    return event
}
```

`@Published` requires `import Combine` in the engine file. In `EngineBootstrap` (app target), add `private var cancellable: AnyCancellable?` and observe in `start(store:)`:

```swift
import Combine   // EngineBootstrap

cancellable = tapEngine.$tapActive
    .receive(on: RunLoop.main)
    .sink { [weak permissions] active in
        if !active {
            permissions?.refresh()
            permissions?.reportTapCreation(false)
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter EventTapEngineTests`
Expected: PASS (11 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/ArtMouseCore Tests/ArtMouseCoreTests/EventTapEngineTests.swift
git commit -m "Detect and report event tap loss"
```

### Task 16: Settings window — tabs shell, permission banner, Buttons tab

**Files:**
- Create: `Sources/artMouse/AppModel.swift`, `Sources/artMouse/Views/SettingsWindow.swift`, `Sources/artMouse/Views/PermissionBannerView.swift`, `Sources/artMouse/Views/ButtonsTabView.swift`, `Sources/artMouse/Views/BindingRowView.swift`, `Sources/artMouse/Views/ActionEditorView.swift`, `Sources/artMouse/Views/ClickActionEditorView.swift`, `Sources/artMouse/Views/MissionActionEditorView.swift`, `Sources/artMouse/Views/MusicActionEditorView.swift`, `Sources/artMouse/Views/ZoomActionEditorView.swift`, `Sources/artMouse/Views/SwitcherActionEditorView.swift`, `Sources/artMouse/Views/OpenActionEditorView.swift`, `Sources/artMouse/Views/DeviceActionEditorView.swift`
- Modify: `Sources/artMouse/AppDelegate.swift` (openSettings shows the real window)

**Interfaces:**
- Consumes: `SettingsStore`, `GlobalSettings`, `ButtonBinding`, `Action` (+ sub-ops), `PermissionsController`, `DeviceManager` (Tasks 3–5, 14).
- Produces (exact):
  - `@Observable final class AppModel { init(store: SettingsStore, permissions: PermissionsController, devices: DeviceManager); var settings: GlobalSettings; func setBinding(_ button: ButtonID, action: Action?); func save() }` — `Action?` nil unbinds. Profile methods arrive in Task 17.
  - One `View` struct per file (style rule). `SettingsWindow` hosts `TabView { ButtonsTab, CursorTab (placeholder until Task 17), DevicesTab }` plus `PermissionBannerView` above the tabs.

- [ ] **Step 1: Write AppModel.swift**

```swift
import SwiftUI
import ArtMouseCore

@Observable
final class AppModel {
    private let store: SettingsStore
    let permissions: PermissionsController
    let devices: DeviceManager

    init(store: SettingsStore, permissions: PermissionsController, devices: DeviceManager) {
        self.store = store
        self.permissions = permissions
        self.devices = devices
        devices.refresh()
    }

    var settings: GlobalSettings { store.settings }

    func binding(for button: ButtonID) -> ButtonBinding? {
        store.settings.buttonBindings.first { $0.button == button }
    }

    func setBinding(_ button: ButtonID, action: Action?) {
        var settings = store.settings
        if let index = settings.buttonBindings.firstIndex(where: { $0.button == button }) {
            settings.buttonBindings[index].actions = action.map { [$0] } ?? []
        } else if let action {
            settings.buttonBindings.append(ButtonBinding(button: button, actions: [action]))
        }
        store.settings = settings
        save()
    }

    func save() {
        try? store.save()
    }
}
```

- [ ] **Step 2: Write SettingsWindow.swift and PermissionBannerView.swift**

`SettingsWindow.swift`:

```swift
import SwiftUI

struct SettingsWindow: View {
    @State private var model: AppModel

    init(model: AppModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        VStack(spacing: 0) {
            PermissionBannerView(permissions: model.permissions)
            TabView {
                ButtonsTabView(model: model)
                    .tabItem { Text("Buttons") }
                CursorTabView(model: model)
                    .tabItem { Text("Cursor") }
                DevicesTabView(model: model)
                    .tabItem { Text("Devices") }
            }
            .padding()
        }
        .frame(minWidth: 680, minHeight: 460)
    }
}

struct DevicesTabView: View {
    let model: AppModel
    var body: some View {
        List(model.devices.devices, id: \.settingsKey) { device in
            VStack(alignment: .leading) {
                Text(device.name).font(.body)
                Text("\(device.transport) — VID \(device.vendorID) PID \(device.productID)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
```

`PermissionBannerView.swift` (PermissionsController is an `ObservableObject`, so observe with `@ObservedObject`):

```swift
import SwiftUI

struct PermissionBannerView: View {
    @ObservedObject var permissions: PermissionsController

    var body: some View {
        if permissions.accessibility == .denied || permissions.inputMonitoring == .denied {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                Text("artMouse needs Accessibility and Input Monitoring permissions.")
                Spacer()
                Button("Grant") {
                    permissions.promptAccessibility()
                    PermissionsController.deepLinkToInputMonitoring()
                }
            }
            .padding(8)
            .background(.yellow.opacity(0.25))
        }
    }
}
```

- [ ] **Step 3: Write the Buttons tab, row, and editors**

`ButtonsTabView.swift`:

```swift
import SwiftUI
import ArtMouseCore

struct ButtonsTabView: View {
    let model: AppModel

    private var buttons: [ButtonID] {
        let standard: [ButtonID] = [.left, .right, .middle, .fourth, .fifth]
        let extendedNumbers = model.settings.buttonBindings.compactMap { binding -> Int? in
            if case .extended(let n) = binding.button { return n }
            return nil
        }
        return standard + extendedNumbers.sorted().map { ButtonID.extended($0) }
    }

    var body: some View {
        List(buttons, id: \.self) { button in
            BindingRowView(model: model, button: button)
        }
    }
}
```

`BindingRowView.swift`:

```swift
import SwiftUI
import ArtMouseCore

struct BindingRowView: View {
    let model: AppModel
    let button: ButtonID

    var body: some View {
        HStack(alignment: .top) {
            Text(label).frame(width: 90, alignment: .leading).font(.body.weight(.medium))
            ActionEditorView(action: currentAction) { newAction in
                model.setBinding(button, action: newAction)
            }
        }
        .padding(.vertical, 4)
    }

    private var currentAction: Action? {
        model.binding(for: button)?.actions.first
    }

    private var label: String {
        switch button {
        case .left: return "Left"
        case .right: return "Right"
        case .middle: return "Middle"
        case .fourth: return "4th"
        case .fifth: return "5th"
        case .extended(let n): return "Button \(n + 1)"
        }
    }
}
```

`ActionEditorView.swift`:

```swift
import SwiftUI
import ArtMouseCore

struct ActionEditorView: View {
    let action: Action?
    let onChange: (Action?) -> Void

    var body: some View {
        HStack {
            categoryPicker
            editor
        }
    }

    @ViewBuilder private var editor: some View {
        switch action {
        case .click(let op, let mods): ClickActionEditorView(op: op, mods: mods, onChange: onChange)
        case .mission(let op, let reverse): MissionActionEditorView(op: op, reverse: reverse, onChange: onChange)
        case .music(let op, let fineTune): MusicActionEditorView(op: op, fineTune: fineTune, onChange: onChange)
        case .zoom(let op, let reverse): ZoomActionEditorView(op: op, reverse: reverse, onChange: onChange)
        case .switcher(let op): SwitcherActionEditorView(op: op, onChange: onChange)
        case .open(let target): OpenActionEditorView(target: target, onChange: onChange)
        case .device(let op): DeviceActionEditorView(op: op, onChange: onChange)
        case .none: Text("Unbound").foregroundStyle(.secondary)
        }
    }

    private var categoryPicker: some View {
        Picker("", selection: Binding(
            get: { action.map(ActionCategory.init) ?? .none },
            set: { onChange($0.initialAction) })) {
            ForEach(ActionCategory.allCases, id: \.self) { category in
                Text(category.label).tag(category)
            }
        }
        .labelsHidden()
        .frame(width: 110)
    }
}

enum ActionCategory: CaseIterable {
    case none, click, mission, music, zoom, switcher, open, device

    var label: String {
        switch self {
        case .none: return "None"
        case .click: return "Click"
        case .mission: return "Mission"
        case .music: return "Music"
        case .zoom: return "Zoom"
        case .switcher: return "Switcher"
        case .open: return "Open"
        case .device: return "Device"
        }
    }

    init(_ action: Action) {
        switch action {
        case .none: self = .none
        case .click: self = .click
        case .mission: self = .mission
        case .music: self = .music
        case .zoom: self = .zoom
        case .switcher: self = .switcher
        case .open: self = .open
        case .device: self = .device
        }
    }

    var initialAction: Action? {
        switch self {
        case .none: return nil
        case .click: return .click(.left, [])
        case .mission: return .mission(.missionControl, reverse: false)
        case .music: return .music(.playPause, fineTune: false)
        case .zoom: return .zoom(.appZoomIn, reverse: false)
        case .switcher: return .switcher(.nextApp)
        case .open: return .open(.path(""))
        case .device: return .device(.activateCursorSpeed(nil))
        }
    }
}
```

`ClickActionEditorView.swift`:

```swift
import SwiftUI
import ArtMouseCore

struct ClickActionEditorView: View {
    let op: ClickOp
    let mods: ModKeys
    let onChange: (Action?) -> Void

    var body: some View {
        HStack {
            opPicker
            modifierCheck("⌘", .command)
            modifierCheck("⌃", .control)
            modifierCheck("⌥", .option)
            modifierCheck("⇧", .shift)
        }
    }

    private var opPicker: some View {
        Picker("", selection: Binding(
            get: { op },
            set: { onChange(.click($0, mods)) })) {
            ForEach(ClickOp.allCases, id: \.self) { option in
                Text(label(option)).tag(option)
            }
        }
        .labelsHidden()
    }

    private func modifierCheck(_ title: String, _ key: ModKeys) -> some View {
        Toggle(title, isOn: Binding(
            get: { mods.contains(key) },
            set: { on in
                var next = mods
                if on { next.insert(key) } else { next.remove(key) }
                onChange(.click(op, next))
            }))
        .toggleStyle(.checkbox)
    }

    private func label(_ op: ClickOp) -> String {
        switch op {
        case .left: return "Left Click"
        case .right: return "Right Click"
        case .middle: return "Middle Click"
        case .doubleLeft: return "Double Click"
        case .fourth: return "4th Click"
        case .fifth: return "5th Click"
        case .clickLock: return "Click Lock"
        }
    }
}
```

`MissionActionEditorView.swift`:

```swift
import SwiftUI
import ArtMouseCore

struct MissionActionEditorView: View {
    @State var op: MissionOp
    @State var reverse: Bool
    let onChange: (Action?) -> Void

    var body: some View {
        HStack {
            Picker("", selection: Binding(
                get: { op },
                set: { op = $0; emit() })) {
                Text("Mission Control").tag(MissionOp.missionControl)
                Text("Application Windows").tag(MissionOp.appWindows)
                Text("Launchpad").tag(MissionOp.launchpad)
                Text("Show Desktop").tag(MissionOp.showDesktop)
                Text("Notification Center").tag(MissionOp.notificationCenter).disabled(true)   // phase 4
                Text("Spotlight").tag(MissionOp.spotlight)
                Text("Siri").tag(MissionOp.siri).disabled(true)                                // phase 4
                Text("Fullscreen Button").tag(MissionOp.fullscreenButton)
                Text("Move Left a Space").tag(MissionOp.moveSpaceLeft)
                Text("Move Right a Space").tag(MissionOp.moveSpaceRight)
                ForEach(1...5, id: \.self) { n in
                    Text("Desktop \(n)").tag(MissionOp.desktop(n))
                }
            }
            .labelsHidden()
            .frame(width: 190)

            if isSpaceSwitch {
                Toggle("Reverse", isOn: Binding(get: { reverse }, set: { reverse = $0; emit() }))
                    .toggleStyle(.checkbox)
            }
        }
    }

    private var isSpaceSwitch: Bool {
        op == .moveSpaceLeft || op == .moveSpaceRight
    }

    private func emit() {
        onChange(.mission(op, reverse: reverse))
    }
}
```

`MusicActionEditorView.swift`:

```swift
import SwiftUI
import ArtMouseCore

struct MusicActionEditorView: View {
    @State var op: MusicOp
    @State var fineTune: Bool
    let onChange: (Action?) -> Void

    var body: some View {
        HStack {
            Picker("", selection: Binding(get: { op }, set: { op = $0; emit() })) {
                Text("Play / Pause").tag(MusicOp.playPause)
                Text("Next").tag(MusicOp.next)
                Text("Previous").tag(MusicOp.previous)
                Text("Mute").tag(MusicOp.mute)
                Text("Volume Up").tag(MusicOp.volumeUp)
                Text("Volume Down").tag(MusicOp.volumeDown)
                Text("Eject").tag(MusicOp.eject)
            }
            .labelsHidden()
            .frame(width: 150)

            Toggle("Fine-tune Volume", isOn: Binding(get: { fineTune }, set: { fineTune = $0; emit() }))
                .toggleStyle(.checkbox)
        }
    }

    private func emit() {
        onChange(.music(op, fineTune: fineTune))
    }
}
```

`ZoomActionEditorView.swift`:

```swift
import SwiftUI
import ArtMouseCore

struct ZoomActionEditorView: View {
    @State var op: ZoomOp
    @State var reverse: Bool
    let onChange: (Action?) -> Void

    var body: some View {
        HStack {
            Picker("", selection: Binding(get: { op }, set: { op = $0; emit() })) {
                Text("Screen Zoom In").tag(ZoomOp.screenZoomIn)
                Text("Screen Zoom Out").tag(ZoomOp.screenZoomOut)
                Text("App Zoom In").tag(ZoomOp.appZoomIn)
                Text("App Zoom Out").tag(ZoomOp.appZoomOut)
                Text("Pinch Zoom In").tag(ZoomOp.pinchIn).disabled(true)    // phase 4
                Text("Pinch Zoom Out").tag(ZoomOp.pinchOut).disabled(true)  // phase 4
                Text("Smart Zoom").tag(ZoomOp.smartZoom).disabled(true)     // phase 4
            }
            .labelsHidden()
            .frame(width: 160)

            Toggle("Reverse", isOn: Binding(get: { reverse }, set: { reverse = $0; emit() }))
                .toggleStyle(.checkbox)
        }
    }

    private func emit() {
        onChange(.zoom(op, reverse: reverse))
    }
}
```

`SwitcherActionEditorView.swift`:

```swift
import SwiftUI
import ArtMouseCore

struct SwitcherActionEditorView: View {
    @State var op: SwitcherOp
    let onChange: (Action?) -> Void

    var body: some View {
        HStack {
            Picker("", selection: Binding(
                get: { op },
                set: { op = $0; emit() })) {
                Text("Next Application").tag(SwitcherOp.nextApp)
                Text("Previous Application").tag(SwitcherOp.previousApp)
                Text("Application Windows").tag(SwitcherOp.applicationWindows)
                Text("Show Switcher Window").tag(SwitcherOp.showSwitcher).disabled(true)   // phase 4
                Text("Switch to App…").tag(SwitcherOp.app(.bundleID("")))
            }
            .labelsHidden()
            .frame(width: 180)

            if case .app(let target) = op {
                switch target {
                case .bundleID(let id):
                    TextField("Bundle ID", text: Binding(
                        get: { id },
                        set: { op = .app(.bundleID($0)); emit() }))
                        .frame(width: 180)
                case .url(let u):
                    TextField("URL", text: Binding(
                        get: { u },
                        set: { op = .app(.url($0)); emit() }))
                        .frame(width: 180)
                case .bookmark:
                    EmptyView()   // created via URL/bookmark picker in a later phase
                }
            }
        }
    }

    private func emit() {
        onChange(.switcher(op))
    }
}
```

`OpenActionEditorView.swift`:

```swift
import SwiftUI
import AppKit
import ArtMouseCore

struct OpenActionEditorView: View {
    @State var target: OpenTarget
    let onChange: (Action?) -> Void

    var body: some View {
        HStack {
            switch target {
            case .path(let p):
                TextField("Path", text: Binding(
                    get: { p },
                    set: { target = .path($0); onChange(.open(target)) }))
                    .frame(width: 220)
                Button("Choose…") { chooseFile() }
            case .url(let u):
                TextField("URL", text: Binding(
                    get: { u },
                    set: { target = .url($0); onChange(.open(target)) }))
                    .frame(width: 220)
            }
            Picker("", selection: Binding(
                get: { kind },
                set: { newKind in
                    target = newKind == .pathKind ? .path("") : .url("")
                    onChange(.open(target))
                })) {
                Text("Path").tag(Kind.pathKind)
                Text("URL").tag(Kind.urlKind)
            }
            .frame(width: 70)
        }
    }

    private enum Kind { case pathKind, urlKind }

    private var kind: Kind {
        if case .path = target { return .pathKind }
        return .urlKind
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            target = .path(url.path)
            onChange(.open(target))
        }
    }
}
```

`DeviceActionEditorView.swift`:

```swift
import SwiftUI
import ArtMouseCore

struct DeviceActionEditorView: View {
    @State var op: DeviceOp
    let onChange: (Action?) -> Void

    var body: some View {
        Picker("", selection: Binding(get: { op }, set: { op = $0; onChange(.device($0)) })) {
            Text("Activate Next Cursor Speed").tag(DeviceOp.activateCursorSpeed(nil))
            Text("Switch Precision Mode").tag(DeviceOp.switchPrecisionMode)
            Text("DPI Cycle").tag(DeviceOp.dpiCycle).disabled(true)        // phase 4
            Text("DPI Up").tag(DeviceOp.dpiUp).disabled(true)              // phase 4
            Text("DPI Down").tag(DeviceOp.dpiDown).disabled(true)          // phase 4
            Text("DPI Shift").tag(DeviceOp.dpiShift).disabled(true)        // phase 4
            Text("Default DPI").tag(DeviceOp.defaultDPI).disabled(true)    // phase 4
            Text("Switch Wheel Mode").tag(DeviceOp.switchWheelMode).disabled(true)  // phase 2
        }
        .labelsHidden()
        .frame(width: 230)
    }
}
```

- [ ] **Step 4: Wire AppDelegate.openSettings and run the app**

AppDelegate gains stored properties `private var appModel: AppModel?` and `private var settingsWindow: NSWindow?`. In `applicationDidFinishLaunching`, after the bootstrap block (store/devices exist only when the engine is allowed to run — build them unconditionally so the UI works in safe mode too):

```swift
let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
let directory = appSupport.appendingPathComponent("artMouse", isDirectory: true)
try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let store = SettingsStore(directory: directory)
let devices = DeviceManager(enumerator: IOKitDeviceEnumerator())
self.store = store
self.devices = devices
appModel = AppModel(store: store, permissions: permissions, devices: devices)
// then the existing BootstrapDecision check calls EngineBootstrap(devices:permissions:).start(store:)
```

(The store/device creation moves out of the bootstrap block so both paths share it.)

```swift
@objc func openSettings() {
    guard let appModel else { return }
    NSApp.activate(ignoringOtherApps: true)
    if settingsWindow == nil {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "artMouse Settings"
        window.contentView = NSHostingView(rootView: SettingsWindow(model: appModel))
        settingsWindow = window
    }
    settingsWindow?.makeKeyAndOrderFront(nil)
}
```

Manual: `./Scripts/make_app.sh && open build/artMouse.app` → Settings… shows Buttons tab; assign Middle → Mission Control; quit; relaunch; verify the binding survived (settings.json round-trip through the UI) and the assignment actually triggers Mission Control.

- [ ] **Step 5: Run full unit suite**

Run: `swift test`
Expected: all suites PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/artMouse
git commit -m "Add settings window with buttons tab and action editors"
```

### Task 17: Cursor tab UI

**Files:**
- Create: `Sources/artMouse/Views/CursorTabView.swift`, `Sources/artMouse/Views/ProfileEditorView.swift`
- Modify: `Sources/artMouse/AppModel.swift` (profile mutations)

**Interfaces:**
- Consumes: `CursorSpeedProfile`, `GlobalSettings`, `AppModel` (Task 16).
- Produces (exact): `AppModel` gains `func addProfile(); func removeProfile(_ id: UUID); func updateProfile(_ profile: CursorSpeedProfile); func setActiveProfile(_ id: UUID); func setPrecisionProfile(_ id: UUID?)` — all save immediately.

- [ ] **Step 1: Implement AppModel profile methods**

```swift
func addProfile() {
    var settings = store.settings
    settings.cursorSpeedProfiles.append(
        CursorSpeedProfile(name: "Profile \(settings.cursorSpeedProfiles.count + 1)",
                           sensitivity: 1600, acceleration: 1.0))
    store.settings = settings
    save()
}

func removeProfile(_ id: UUID) {
    var settings = store.settings
    guard settings.cursorSpeedProfiles.count > 1 else { return }   // never zero profiles
    settings.cursorSpeedProfiles.removeAll { $0.id == id }
    if settings.activeCursorSpeedProfileID == id { settings.activeCursorSpeedProfileID = nil }
    if settings.precisionProfileID == id { settings.precisionProfileID = nil }
    store.settings = settings
    save()
}

func updateProfile(_ profile: CursorSpeedProfile) {
    var settings = store.settings
    if let index = settings.cursorSpeedProfiles.firstIndex(where: { $0.id == profile.id }) {
        settings.cursorSpeedProfiles[index] = profile
    }
    store.settings = settings
    save()
}

func setActiveProfile(_ id: UUID) {
    store.settings.activeCursorSpeedProfileID = id
    save()
}

func setPrecisionProfile(_ id: UUID?) {
    store.settings.precisionProfileID = id
    save()
}
```

- [ ] **Step 2: Write CursorTabView.swift and ProfileEditorView.swift**

`CursorTabView.swift`:

```swift
import SwiftUI
import ArtMouseCore

struct CursorTabView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Speed profiles").font(.headline)
                Spacer()
                Button("Add Profile") { model.addProfile() }
            }
            List(model.settings.cursorSpeedProfiles) { profile in
                ProfileEditorView(
                    profile: profile,
                    isActive: profile.id == effectiveActiveID,
                    isPrecision: profile.id == model.settings.precisionProfileID,
                    onUpdate: { model.updateProfile($0) },
                    onDelete: { model.removeProfile($0.id) },
                    onActivate: { model.setActiveProfile($0.id) },
                    onTogglePrecision: { model.setPrecisionProfile(profile.id == model.settings.precisionProfileID ? nil : profile.id) })
            }
            Text("Sensitivity scales all cursor movement (1600 ≈ system default). Acceleration adds extra distance on fast movements; 0 disables it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var effectiveActiveID: UUID? {
        model.settings.activeProfile?.id
    }
}
```

`ProfileEditorView.swift`:

```swift
import SwiftUI
import ArtMouseCore

struct ProfileEditorView: View {
    let profile: CursorSpeedProfile
    let isActive: Bool
    let isPrecision: Bool
    let onUpdate: (CursorSpeedProfile) -> Void
    let onDelete: (CursorSpeedProfile) -> Void
    let onActivate: (CursorSpeedProfile) -> Void
    let onTogglePrecision: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            TextField("Name", text: Binding(
                get: { profile.name },
                set: { onUpdate(profileWithName($0)) }))
                .frame(width: 110)

            LabeledContent("Sensitivity") {
                TextField("", value: Binding(
                    get: { profile.sensitivity },
                    set: { onUpdate(profileWithSensitivity($0)) }), format: .number)
                    .frame(width: 70)
            }
            .frame(width: 190)

            LabeledContent("Acceleration") {
                TextField("", value: Binding(
                    get: { profile.acceleration },
                    set: { onUpdate(profileWithAcceleration($0)) }), format: .number)
                    .frame(width: 70)
            }
            .frame(width: 180)

            Button(isActive ? "Active" : "Use") { onActivate(profile) }
                .disabled(isActive)

            Toggle("Precision", isOn: Binding(get: { isPrecision }, set: { _ in onTogglePrecision() }))
                .toggleStyle(.checkbox)

            Spacer()

            Button(role: .destructive) { onDelete(profile) } label: { Image(systemName: "trash") }
                .disabled(isActive)
        }
    }

    private func profileWithName(_ name: String) -> CursorSpeedProfile {
        var copy = profile; copy.name = name; return copy
    }
    private func profileWithSensitivity(_ value: Double) -> CursorSpeedProfile {
        var copy = profile; copy.sensitivity = value.clamped(200...6400); return copy
    }
    private func profileWithAcceleration(_ value: Double) -> CursorSpeedProfile {
        var copy = profile; copy.acceleration = value.clamped(0...10); return copy
    }
}

extension Double {
    func clamped(_ range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
```

- [ ] **Step 3: Manual smoke**

Run: `./Scripts/make_app.sh && open build/artMouse.app`
Expected: Cursor tab lists Slow/Default/Fast; edit sensitivity to 800 on Default → settings.json reflects it; switching Active profile changes cursor feel immediately (engine reads the store live — the router already reads `settings.settings` per event).

- [ ] **Step 4: Run full suite and commit**

Run: `swift test` — all PASS.

```bash
git add Sources/artMouse
git commit -m "Add cursor speed profiles UI"
```

### Task 18: AppWatcher — frontmost application tracking

**Files:**
- Create: `Sources/ArtMouseCore/Engine/AppWatcher.swift`
- Create: `Tests/ArtMouseCoreTests/AppWatcherTests.swift`

**Interfaces:**
- Consumes: nothing (AppKit/NSWorkspace).
- Produces (exact): `final class AppWatcher { init(notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter); private(set) var frontmostBundleID: String?; func start(); func handleActivation(_ bundleID: String?); static func bundleID(fromActivation userInfo: [AnyHashable: Any]) -> String? }` — `start()` observes `NSWorkspace.didActivateApplicationNotification` and routes `NSRunningApplication.bundleIdentifier` into `handleActivation`. Phase 1 only records the value (router does not consume it yet); Phase 3's per-app profiles read it.

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
@testable import ArtMouseCore

final class AppWatcherTests: XCTestCase {
    func testHandleActivationUpdatesFrontmost() {
        let watcher = AppWatcher(notificationCenter: NotificationCenter())
        XCTAssertNil(watcher.frontmostBundleID)
        watcher.handleActivation("com.apple.Safari")
        XCTAssertEqual(watcher.frontmostBundleID, "com.apple.Safari")
        watcher.handleActivation("com.apple.TextEdit")
        XCTAssertEqual(watcher.frontmostBundleID, "com.apple.TextEdit")
    }

    func testHandleActivationNilKeepsPrevious() {
        let watcher = AppWatcher(notificationCenter: NotificationCenter())
        watcher.handleActivation("com.apple.Safari")
        watcher.handleActivation(nil)   // activation notifications always carry an app; nil input tolerated
        XCTAssertEqual(watcher.frontmostBundleID, "com.apple.Safari")
    }

    func testBundleIDExtractionWithoutAppReturnsNil() {
        XCTAssertNil(AppWatcher.bundleID(fromActivation: [:]))
        XCTAssertNil(AppWatcher.bundleID(fromActivation: ["unrelated": 1]))
    }
}
```

(`NSRunningApplication` cannot be constructed for arbitrary apps, so extraction is tested for its nil paths; the app-present path is verified in Task 19's manual checklist by watching `frontmostBundleID` change in a debug log line — add `NSLog("artMouse frontmost: %@", watcher.frontmostBundleID ?? "nil")` temporarily in Task 19 if needed.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter AppWatcherTests`
Expected: FAIL — `AppWatcher` not defined.

- [ ] **Step 3: Write AppWatcher.swift**

```swift
import AppKit

public final class AppWatcher {
    private let notificationCenter: NotificationCenter
    public private(set) var frontmostBundleID: String?
    private var observer: NSObjectProtocol?

    public init(notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        self.notificationCenter = notificationCenter
    }

    public func start() {
        guard observer == nil else { return }
        observer = notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let bundleID = Self.bundleID(fromActivation: notification.userInfo ?? [:])
            self?.handleActivation(bundleID)
        }
    }

    public func handleActivation(_ bundleID: String?) {
        guard let bundleID else { return }
        frontmostBundleID = bundleID
    }

    public static func bundleID(fromActivation userInfo: [AnyHashable: Any]) -> String? {
        (userInfo[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
    }

    deinit {
        if let observer {
            notificationCenter.removeObserver(observer)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter AppWatcherTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Start the watcher from EngineBootstrap**

In `EngineBootstrap.start(store:)`, add a stored `appWatcher` property and `appWatcher.start()` next to the timers.

- [ ] **Step 6: Commit**

```bash
git add Sources/ArtMouseCore/Engine/AppWatcher.swift Tests/ArtMouseCoreTests/AppWatcherTests.swift Sources/artMouse/EngineBootstrap.swift
git commit -m "Add frontmost app watcher"
```

### Task 19: Phase 1 verification checklist

**Files:**
- Create: `docs/verification/phase-1.md`
- Modify: none (verification only; fixes found here are normal bug-fix commits)

**Interfaces:**
- Consumes: the completed app.
- Produces: the recorded manual verification list (spec §8).

- [ ] **Step 1: Run the full automated suite**

Run: `swift test`
Expected: all suites PASS; fix anything red before manual steps (bugs found are separate commits, e.g. `Fix click-lock release ordering`).

- [ ] **Step 2: Manual verification per Review Focus + spec §8**

Create `docs/verification/phase-1.md` with this checklist and record each result:

```markdown
# Phase 1 manual verification (2026-11-XX)

- [ ] Permissions: fresh TCC state (remove app from Privacy lists) → banner shows, Grant button opens the right panes; after granting, engine works without relaunch.
- [ ] Review Focus 1: bind 5th button to Device → Activate Next Speed; press it → cursor speed jumps, warning appears, speed restores exactly 5 s later.
- [ ] Review Focus 2: hand-corrupt ~/Library/Application Support/artMouse/settings.json → app relaunches with defaults, warning visible in UI, no crash.
- [ ] Review Focus 3: revoke Input Monitoring while running → banner re-appears (tapActive flips false).
- [ ] Review Focus 4: launch with --safe-mode → cursor behaves stock; verify no interception by binding nothing and observing normal clicks everywhere.
- [ ] Review Focus 5: extended-button mouse (if available): unbound extra buttons act stock.
- [ ] Buttons: each click op (left/right/middle/double/4th/5th) lands in TextEdit; modifier combos (e.g. Right Click + ⌘ = browser back-forward if bound).
- [ ] Click Lock: hold left beyond threshold → sticky drag; next click releases.
- [ ] Mission ops: Mission Control, App Windows, Launchpad, Show Desktop, Desktop 1–3, Move Space L/R, Spotlight, Fullscreen toggle.
- [ ] Music ops: play/pause, next, previous, mute, volume ±, eject, with Music.app/Spotify.
- [ ] Zoom ops: app zoom in/out in Safari (⌘+/-), screen zoom (needs "Use keyboard shortcuts for zoom" enabled in Accessibility → Zoom).
- [ ] Switcher/open: switch to Safari by bundle ID, open a path, open a URL.
- [ ] Cursor: Slow/Default/Fast profiles change feel; Precision hold (bound to a button) drops to Slow while held.
- [ ] Sleep/wake: sleep the Mac, wake, bindings still work (tap re-enabled).
- [ ] settings.json survives app restart and is valid JSON (lint it).
```

- [ ] **Step 3: Fix anything the manual pass found, re-run suite, commit**

```bash
git add docs/verification/phase-1.md
git commit -m "Record phase 1 verification"
```

## Summary of delivered behavior (Phase 1)

After Task 19, artMouse: intercepts all standard mouse events; remaps any of the 5 standard buttons to clicks (incl. double/4th/5th/click-lock + modifiers), mission ops, media ops, zoom (app + screen), switcher (next/prev app, app by bundle ID/URL/bookmark, app windows), open (path/URL), and cursor-profile switching (incl. precision hold + 5 s safety restore); per-event cursor sensitivity/acceleration transforms; JSON settings with malformed-input fallback; menu-bar UI (Buttons/Cursor/Devices tabs) with live effect; permission flow with banner + guided grants; safe-mode launch; tap re-enable after wake and tap-loss detection.
