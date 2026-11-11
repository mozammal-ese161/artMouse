# 🖱️ artMouse — The Missing Mouse Customizer for macOS

**Remap every button. Reshape scrolling. Automate anything.** artMouse is a free, lightweight menu-bar app that gives your mouse — gaming, productivity, trackball, or specialty — the deep level of control macOS never shipped. One app, no kernel extensions, zero background daemons beyond the app itself.

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-black) ![Language](https://img.shields.io/badge/language-Swift%205.9-orange) ![Tests](https://img.shields.io/badge/tests-240%20passing-brightgreen) ![Deps](https://img.shields.io/badge/dependencies-zero-blue)

## Why artMouse?

macOS treats every mouse beyond left-click/scroll as an afterthought: extra buttons are ignored, scroll speed is one slider shared with the trackpad, acceleration is a black box, and macros require third-party launchers glued together with system events. **artMouse fixes all of it in one place** — with per-application profiles, so your settings follow what you're doing.

## ✨ Features

**🔘 Total button freedom**
Assign any action to any button — standard, buttons 6–32, or raw device parts (pedals, thumb buttons):
clicks with modifiers, double-click, click-lock · keyboard entry · **multi-step macros** (key/click/wait steps; run-once, hold-to-repeat, or continuous) · scroll actions · Mission Control, Launchpad, Spaces, Notification Center, Spotlight, Siri · media keys with volume fine-tune · app & window switching · screen, pinch, smart, and in-app zoom · cursor snapping to any window's default button · open any file or URL · click-lock.

**🤝 Chords**
Combine buttons like keyboard shortcuts — hold two or three together to trigger an action, with configurable timing and chord-while-scrolling support.

**🎡 A scroll wheel that finally behaves**
Acceleration, constant-speed, and coasting auto-scroll modes · independent vertical/horizontal reverse · buttery smooth scrolling · wheel→keyboard emulation · **free-spin momentum** with adjustable decay for gaming wheels · multiple wheel profiles you can hot-switch by button or by app · two-way bindings (different action per direction).

**🎯 Cursor control macOS won't give you**
Independent sensitivity (counts-per-inch) and acceleration curves, decoupled from System Settings · 1:1 raw mode · multiple speed profiles with a 5-second safety auto-restore · momentary precision mode for pixel-perfect work.

**📱 Per-application profiles**
Different feel for different apps: Xcode gets precision scrolling, your browser gets reverse smooth wheel, your game gets raw buttons — artMouse switches automatically when the frontmost app changes.

**🔌 Real device support**
Per-device profiles by VID/PID with friendly part naming (pedals, tilt wheels, thumb buttons) · **buttons 6+ captured via raw HID** even when macOS never sees them · **DPI switching** (cycle/up/down/default/momentary shift) via feature reports · Device Analyzer showing your mouse's live raw events · device logging · per-device enable/disable · IORegistry details.

**⚙️ Everything is portable**
Human-editable JSON settings with one-click import/export. Corrupt or absurd values fall back to safe defaults with a visible warning — never a crash, never a lockout.

## 🚀 Quick start

```bash
git clone https://github.com/mozammal-ese161/artMouse.git
cd artMouse
Scripts/make_app.sh
open build/artMouse.app
```

Requires **macOS 14 or newer** (Apple Silicon or Intel). On first launch, grant **Accessibility** (window snapping) and **Input Monitoring** (event interception) when prompted — artMouse links you straight to the right System Settings panes and degrades gracefully until you do.

Settings live in `~/Library/Application Support/artMouse/settings.json`.

> 🛟 **Locked out?** Launch with `--safe-mode` (or hold ⌥⌘ at launch) to bypass all interception and undo any binding.

## 🛠 How it works (for the curious)

artMouse observes input through the public `IOHIDManager` API and intercepts standard events with a `CGEventTap` — all in user space, nothing signed into the kernel. Every synthetic event it posts is tagged with a private event source, so the app can always tell its own output from your hand: no feedback loops, ever. All engine state runs on one main-run-loop queue; all user-facing numbers are clamped at the engine boundary; settings decode backward-compatibly across releases.

The engine lives in a UI-free framework module (`ArtMouseCore`) covered by a 240-test suite — virtual-clock scroll math, macro scheduling, chord FSMs, routing contracts, settings round-trips — while the SwiftUI layer stays thin.

```bash
swift test    # run the suite
swift build   # engine + app
```

## 📚 Documentation

- `docs/verification/` — hardware verification checklists, one per development phase.
- `docs/superpowers/specs/2026-11-09-artmouse-design.md` — the design spec: architecture, data model, feature baseline.

## ⚠️ Honest limitations

- **DPI is device-specific.** Vendor DPI protocols are proprietary; artMouse ships a generic feature-report template you configure per device in the profile editor (meant for devices you own). Unconfigured devices gracefully fall back to cursor-speed profile switching.
- **Raw button capture is opt-in per device.** Most mice surface buttons 6–32 normally — leave capture off unless a button truly does nothing (the profile editor warns you).
- **Disabling a device** mutes its raw-HID features; events that reach the system tap still pass through. Full bypass = safe mode.
- Momentum is constant-mode-only and capped; wheel→keyboard and auto-scroll never coast (no runaway key repeats).

## 💼 Personal use

Free for personal use — no licensing, no trial, no telemetry, no phone-home.
