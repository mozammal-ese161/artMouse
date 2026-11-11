# artMouse

A native macOS menu-bar utility that reproduces the full **SteerMouse 5.8** feature set for personal use — button remapping, chords, wheel reshaping, macros, cursor control, per-application profiles, and raw device support — in one app, with no kernel extensions.

Single Swift codebase, zero third-party dependencies. The engine lives in the `ArtMouseCore` framework module (UI-free, unit-tested); the SwiftUI settings UI is a thin layer over it.

**Status:** feature-complete (all 4 planned phases merged). 240 unit tests, all green.

## Features

- **Buttons** — every action type assignable to any button (standard 1–5, buttons 6–32, and raw-HID device parts):
  clicks with modifiers, double-click, click-lock · keyboard entry · macros (enter-key / click / wait steps; run-once, hold-repeat, continuous) · scroll-from-button · system ops · zoom (screen/pinch/smart/app) · app switcher (bundle ID / next / previous) · music & media keys with fine-tune · Mission Control / Launchpad / Show Desktop / Desktop 1–5 / Move a Space / Notification Center / Spotlight / Siri · device ops (DPI, wheel mode, precision mode) · cursor snapping to a window's default button (jump / click / bounce) · open file/URL
- **Chords** — multi-button combinations with configurable timeout; longest-match subset semantics.
- **Wheel** — acceleration / constant / auto modes · speed (lines, interval, sens factor, acceleration) · reverse vertical/horizontal in every mode · smooth scroll · wheel→keyboard emulation · free-spin momentum with adjustable decay · auto-scroll · two-way scroll bindings · multiple wheel-mode profiles, switchable by button and per-app.
- **Cursor** — independent sensitivity (counts/inch) + acceleration, decoupled from System Settings · disable-accel (1:1) · speed profiles with button switching and the 5-second safety restore · precision mode (momentary).
- **Per-application profiles** — auto-switch on focus; overrides any subset of button bindings, scroll bindings, cursor speed, and wheel mode.
- **Devices** — device profiles matched by VID/PID with user-named parts (buttons, wheels, pedals) · buttons 6+ that never surface as CGEvents via raw HID capture · Device Analyzer (live raw-element view) · Device Log (optional file persistence) · DPI feature reports (cycle/up/down/default/shift) for configured devices · enable/disable per device · IORegistry details.
- **Settings** — human-editable JSON with import/export; malformed input falls back to defaults with a visible warning, never a crash.

## Build & run

```bash
Scripts/make_app.sh     # builds and signs build/artMouse.app
open build/artMouse.app
```

Requirements: **macOS 14 or newer**, Apple Silicon or Intel, Xcode toolchain for building.

On first launch artMouse asks for two permissions it needs to see and shape input:

1. **Accessibility** — cursor snapping (window default-button lookup) and guided setup.
2. **Input Monitoring** — the CGEventTap that intercepts mouse events. If the tap can't be created (or the system disables it later), the app shows a permission banner and deep-links to System Settings.

Settings live in `~/Library/Application Support/artMouse/settings.json`. **Safe mode:** launch with `--safe-mode` (or hold ⌥⌘ at launch) to bypass all engine interception — the UI still works, so you can always un-bind a button that locked you out.

## Development

```bash
swift test     # 240 tests
swift build    # engine + UI
```

- `Sources/ArtMouseCore/` — the engine: event tap, router, chord/macro engines, scroll emitter + controller, cursor controller, snapping, HID observer pipeline (`Devices/`), settings model. UI-free and fully unit-tested.
- `Sources/artMouse/` — SwiftUI menu-bar app: settings window tabs (Buttons, Wheel, Scroll Bindings, Chords, Apps, General, Cursor, Devices), permission flows, bootstrap.
- `Tests/ArtMouseCoreTests/` — the 240-test suite (router contracts, scroll/momentum virtual-clock math, macro engine, translator policy, DPI builder, settings round-trips).
- `docs/verification/` — human hardware-verification checklists, one per phase. `phase-4.md` is the current one (15 checks on real devices).
- `docs/superpowers/specs/2026-11-09-artmouse-design.md` — the design spec (architecture, data model, parity baseline recovered by static analysis of SteerMouse 5.8).

## Known limitations

- **DPI is vendor-proprietary.** Feature-report layouts differ per vendor; artMouse ships a generic byte-template you configure per device in the profile editor, intended for devices you own and can test. On unconfigured devices, DPI buttons degrade to cursor-speed profile switching.
- **Raw button capture is opt-in per device.** Most mice surface buttons 6–32 as normal CGEvents — leave capture off (the profile editor warns; enabling it on a mouse that already surfaces its buttons makes each press fire twice).
- **Disabling a device** stops all HID-side features for it (raw parts, analyzer traffic routing, DPI). Events that arrive through the system tap from that device still pass through — disabling is per-feature, not a full blocker (safe mode is).
- Momentum coasts are capped and constant-mode-only by design; wheel→keys and auto-scroll never coast.

## Personal use

Built for personal use — no licensing, trial, updater, or notarization. Not distributed on the App Store.
