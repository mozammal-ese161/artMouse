# artMouse — Design Spec

**Date:** 2026-11-09
**Status:** Approved design, pending implementation plan
**Distribution:** Personal use (no licensing, no trial, no notarization, no auto-updater)

## 1. Overview

artMouse is a native Swift macOS utility that reproduces the SteerMouse 5.8 feature set for personal use. It intercepts mouse input system-wide, remaps buttons, controls cursor behavior, reshapes scrolling, and applies per-application settings. SteerMouse's feature surface was recovered by static reverse engineering of `/Applications/SteerMouse.app` 5.8(0920) (nib archives, binary strings, device-definition XMLs); the feature inventory in Appendix A is the parity baseline.

## 2. Goals

- Full SteerMouse feature parity across 8 feature groups (Appendix A), sequenced in 4 phases.
- Support multi-button (6+) mice and specialty devices (trackballs, tilt/thumb wheels, pedals) via raw HID observation.
- Single native Swift codebase; engine isolated in a testable framework module.
- Human-editable JSON settings with import/export.

## 3. Non-goals

- No licensing / trial system.
- Notarized distribution or Sparkle updates (personal build).
- App Store distribution (requires private-API removal — incompatible with Approach A).
- Hardware DPI control for arbitrary vendors: DPI via HID feature reports is vendor-proprietary; artMouse implements it only for devices owned and testable by the user. On unsupported devices, DPI operations degrade to cursor-speed profile switching.
- Kernel extensions or DriverKit (rejected: entitlement burden, no gain over user-space).

## 4. Architecture

**Process model:** one always-running menu-bar app (`artMouse.app`, `LSUIElement`, minimum macOS 14, Apple Silicon + Intel). The app hosts both the SwiftUI settings UI and the engine. The engine lives in the `ArtMouseCore` framework module, UI-free, so it is unit-testable and can later be extracted into a login-item helper without redesign.

**Event pipeline:**

```
HID devices ──▶ DeviceManager (IOHIDManager: discovery, VID/PID match, hot-plug)
     │
     ├─▶ HIDObserver (IOHIDEventSystemClient: raw reports → InputEvent)
     │        buttons 6+, tilt/thumb wheels, pedals, vendor reports
     │
     └─▶ EventTapEngine (CGEventTap listen+modify: standard events)
              merged with HIDObserver stream
                        │
                        ▼
                 EventRouter
                  │ picks active profile: GlobalSettings or AppProfile (AppWatcher)
                  │ feeds ChordEngine (multi-button FSM)
                  ▼
     ┌────────────┼──────────────┬─────────────────┐
     ▼            ▼              ▼                 ▼
 button       Scroll       Cursor            Snapping
 bindings   Controller    Controller        Controller
     │            │              │                 │
     └──────▶ ActionExecutor / MacroEngine ◀──────┘
              (posts clicks, keys, media, mission, zoom, open…)
```

**Module breakdown (all inside `ArtMouseCore` unless noted):**

| Unit | Responsibility | Key dependency |
|---|---|---|
| `DeviceManager` | Enumerate HID devices, match `DeviceProfile` by VID/PID/usage, hot-plug events | IOHIDManager |
| `HIDObserver` | Observe raw HID reports, translate vendor events into `InputEvent` | IOHIDEventSystemClient |
| `EventTapEngine` | Intercept/modify standard mouse events; re-enable after sleep; merges both sources into one stream | CGEventTap |
| `EventRouter` | Resolve active profile, run chord FSM, dispatch to controllers | — |
| `ActionExecutor` | Perform one `Action` | CGEvent post, NSWorkspace, NX system-defined media-key events |
| `MacroEngine` | Key sequences: enter/click/wait steps, repeat, repeat-delay, continuous, modifier proxy | async scheduling |
| `ScrollController` | Scroll modes (acceleration/constant/auto), smooth-scroll interpolation, reverse V/H, wheel→keys, auto-scroll, two-way actions, wheel-mode profiles, free-spin momentum handling, mouse vs trackball direction convention | timer-driven event synthesis |
| `CursorController` | Sensitivity + acceleration curve rewriting, speed profiles, precision mode, shift-sens, 5 s safety restore | CGEvent field rewrite |
| `ChordEngine` | Multi-button combos with timeout | FSM |
| `SnappingController` | Snap actions with click/bounce/jump flags | Accessibility read of default buttons |
| `AppWatcher` | Frontmost app tracking → active `AppProfile` | NSWorkspace |
| `SettingsStore` | Load/save/observe JSON settings; import/export | Codable + Observation |
| `DeviceProfileManager` | Bundled + user device profiles (JSON), part naming | — |
| UI (app target) | Menu bar + settings window: Buttons, Wheel, Chords, Cursor, DPI, Devices, Apps, Options tabs | SwiftUI |

**Permissions:** Accessibility (`AXIsProcessTrustedWithOptions` guided prompt on first run) and Input Monitoring (deep-link to System Settings when CGEventTap creation returns a denied tap). Engine runs degraded-but-visible until granted: UI works, engine shows a permission banner.

## 5. Data model

Mirrors SteerMouse's recovered `_400ActData` action union:

```swift
enum Action: Codable, Equatable {
    case none
    case click(ClickOp, modifiers: ModKeys)
        // ClickOp: left, middle, right, double, fourth, fifth, clickLock
    case macro([MacroStep], repeat: RepeatBehavior, modifierProxy: Bool)
        // MacroStep: .enterKey(KeyEvent) | .click(ClickOp, mods) | .wait(milliseconds)
        // RepeatBehavior: none | hold(interval) | continuous
    case scroll(ScrollSpec)
        // direction (vert/horz × up/down/left/right), modkeys, linear,
        // sensFactor, acceleration, interval, lines, autoMode(interval, movement), reverse
    case system(SystemOp)
        // autoScroll, cursorSnapping, …
    case zoom(ZoomOp, reverse: Bool)
        // screenZoomIn, screenZoomOut, pinchIn, pinchOut, smartZoom, appZoomIn, appZoomOut
    case switcher(SwitcherOp)
        // app(bundleID|URL|bookmark), nextApp, previousApp, applicationWindows, showSwitcher
    case music(MusicOp, fineTune: Bool)
        // play, next, previous, mute, volumeUp, volumeDown, eject
    case mission(MissionOp, reverse: Bool)
        // missionControl, launchpad, showDesktop, desktop(1…n), moveSpaceLeft/Right,
        // notificationCenter, spotlight, siri, fullscreenButton
    case device(DeviceOp)
        // dpiCycle, dpiUp, dpiDown, dpiShift, defaultDPI,
        // switchWheelMode, switchPrecisionMode
    case snapping(SnappingOp)
        // flags: click, bounce, jump
    case open(OpenTarget)
        // file(path), url(URL), bookmark
}
```

**Bindings.** `DeviceProfile` describes parts: `buttons: [ButtonPart]` (indexed), `wheels: [WheelPart]` (vertical/horizontal/tilt/thumb). A `Binding` = trigger (part + direction + modifier buttons) → `[Action]`, with optional **two-way** pairs (distinct action per scroll direction). `Chord` = ordered `ButtonSet` → `[Action]` with a configurable timeout.

**Profile layers (later wins):**
1. `GlobalSettings` — cursor speed profiles `[CursorSpeedProfile]` (sensitivity + acceleration, one active, switchable by `DeviceOp`), wheel-mode profiles `[WheelModeProfile]` (scroll mode + per-wheel params, switchable by `DeviceOp`), options (click timing, chord timeout, snapping defaults).
2. `AppProfile` — matched by bundle ID (fallback: matching key); overrides any subset of bindings, cursor speed, wheel mode.

**Storage:** JSON in `~/Library/Application Support/artMouse/`:
`settings.json` (global + app profiles + chords), `devices/*.json` (device profiles, bundled copies seeded on first run), schema `version: 1`. Human-editable; import/export = file copy. Invalid settings fall back to defaults with a UI warning, never a crash or lockout.

## 6. Phasing

- **Phase 1 — Foundation (working remapper):** app skeleton + menu bar, permission flow, `SettingsStore`, `DeviceManager`, `EventTapEngine`, `EventRouter`, `AppWatcher`; button bindings for `click`, `mission`, `music`, `zoom`, `switcher`, `open`; `CursorController` (sensitivity, acceleration, disable-accel/sens, speed profiles + switching + 5 s safety restore).
- **Phase 2 — Wheel + Chords:** scroll modes, reverse, speed params (lines/interval/sensFactor/acceleration), smooth scroll, wheel→keys, auto-scroll, two-way scroll actions, wheel-mode profiles; `ChordEngine`.
- **Phase 3 — Macros + Snap + Per-app:** macro sequences (enter/click/wait, repeat, repeat-delay, continuous, modifier proxy), `SnappingController`, `AppProfile` + auto-switching, import/export UI.
- **Phase 4 — Raw HID + Devices:** `HIDObserver` (buttons 6+, thumb/tilt wheels, pedals), device-profile system (bundled + user-defined, part naming), Device Analyzer (live raw-event view), Device Log, DPI feature reports for owned devices, IORegistry info view.

Each phase ends with the manual verification step in §8 and a working app.

## 7. Error handling

- **Self-lockout protection (two hatches):** cursor-speed changes from a `device` action auto-restore after 5 s with a visible warning (SteerMouse behavior), and launching with `--safe-mode` (or holding ⌥⌘ at launch) bypasses all engine interception.
- **Permission denial:** guided prompt; deep-link to System Settings; engine stays disabled but UI functional.
- **Sleep/wake:** re-enable tap (`CGEventTapEnable`); re-scan devices on wake.
- **Hot-plug:** `DeviceManager` reconnects observers and re-resolves the active profile.
- **Malformed settings:** per-field fallback to defaults with a warning list in UI; never crash.
- **Tap loss:** if the tap callback stops receiving events (system revoked), detect and prompt.

## 8. Testing

- **Unit (`ArtMouseCore`, XCTest):** `EventRouter` with injected `InputEvent` streams (profile selection, binding resolution, two-way scroll); `ScrollController` math (mode curves, interpolation timing); `MacroEngine` scheduling with virtual clock; `ChordEngine` FSM; `CursorController` transforms (sensitivity/acceleration curve math); `SettingsStore` round-trip + malformed-input fallback; `DeviceProfileManager` matching. Recorded HID report sequences serve as fixtures for `HIDObserver` translation.
- **Manual per phase:** real-device verification list maintained in the repo (`docs/verification/<phase>.md`): every shipped binding type exercised on the user's hardware; permission flows; sleep/wake; safe-mode.
- UI (SwiftUI) is not unit-tested; smoke-tested manually.

## Appendix A — SteerMouse parity baseline (evidence-backed)

Recovered from SteerMouse 5.8(0920): Info.plist (`ev_a8405f7c…`), decoded nib archives (MainMenu.nib: 1,382 objects; custom delegate classes `SM215…SM250`), Manager binary strings (`_400ActData` struct, `SM###` config keys), and 88 device-definition XMLs.

1. **Cursor:** sensitivity (counts/inch) + acceleration independent of System Prefs; disable both (1:1); fine tuning; cursor-speed profiles with button switching + 5 s safety restore; Switch Precision Mode; Shift Sens (momentary); per-device settings.
2. **Buttons:** per-button assignments — clicks (L/M/R/double/4th/5th/click-lock, + modifiers), key entry, macros (sequences, repeat, delay, continuous), scroll-from-button, system ops, zoom, switcher, music, mission, device ops, snapping, open, no-action.
3. **Chords:** multi-button combinations → actions.
4. **Wheel:** modes acceleration/constant/auto; speed (lines, interval, sensFactor, acceleration); reverse V/H; smooth scroll; free spin; wheel→keyboard emulation; auto-scroll; two-way actions; wheel-mode profiles; mouse vs trackball direction.
5. **DPI:** per-device DPI table, default level, DPI Shift (momentary), DPI Cycle/Up/Down.
6. **Devices:** list + enable/disable, custom part names, Device Analyzer, Device Log, IORegistry viewer, vendor profiles.
7. **Per-application settings:** app profiles by bundle ID/matching key, auto-switch on focus, import/export.
8. **System integration:** Mission ops (Mission Control, Launchpad, Show Desktop, Desktop 1–5, Move a Space, Notification Center, Spotlight, Siri), media ops (play/next/prev/mute/volume/eject + fine-tune), zoom ops (screen/pinch/smart/app), switcher (app by bundle ID/URL/bookmark, next/prev app), open (file/URL/bookmark).

**Architecture observed in SteerMouse (approach A basis):** config app + Manager login item (LaunchAgent `jp.plentycom.boa.SteerMouse`); engine uses CGEventTap + IOHIDEventSystemClient/IOHIDServiceClient (type-encoded strings in the Manager binary). artMouse collapses this into one process by design (§4).
