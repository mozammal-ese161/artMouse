# Phase 2 manual verification (2026-11-10)

Produced by the Task 12 verification pass. The automated portion was executed on this
machine (macOS 26, Apple Silicon) against `build/artMouse.app` built from `phase-2`
HEAD `d972e14` + this doc. Items that require TCC grants, a physical mouse/wheel,
visual judgement, or sleep/wake on real hardware are left unchecked with a
HOW TO VERIFY line.

## Automated results — all executed 2026-11-10

- [x] **Full test suite**: `swift test` → `Executed 143 tests, with 0 failures (0 unexpected)` across 22 suites (ScrollControllerTests, ScrollEmitterTests, WheelModeSwitchingTests, ChordEngineTests, RouterChordTests, EventTapEngineScrollTests, SettingsStoreTests, plus the Phase 1 suites). The plan's estimate (~113) drifted upward because Phase 2 landed more tests than budgeted; nothing failed.
- [x] **Bundle build**: `./Scripts/make_app.sh` → `Build complete!` / `Built build/artMouse.app` (codesigned, no warnings in this pass).
- [x] **App launches and stays alive**: `open build/artMouse.app` → `pgrep -x artMouse` = 7473; after `sleep 5` the same PID 7473 was alive (`ps` etime 00:14); killed with `pkill -x artMouse`.
- [x] **Safe-mode launch**: `open build/artMouse.app --args --safe-mode` → `ps -o args= -p 7561` shows `…/build/artMouse.app/Contents/MacOS/artMouse --safe-mode`; PID 7561 unchanged after `sleep 5`; then killed. (Whether the wheel/cursor actually behave stock is the human item below.)
- [x] **Phase-1 settings survival (Review Focus 1)**: with the app stopped, a Phase-1-shaped `settings.json` was installed — exactly the keys a Phase 1 save produced (`schemaVersion`, `cursorSpeedProfiles` Slow/Default/Fast, `buttonBindings` with 4th → Device → Activate Next Cursor Speed and 5th → Mission → Mission Control), and **no** Phase 2 keys (the action/binding encodings were generated with the model's own `JSONEncoder`, then the `wheelModeProfiles`/`activeWheelModeProfileID`/`scrollBindings`/`chords` keys removed; the exact shape is pinned by `SettingsStoreTests.testPhase1SettingsJSONStillDecodes`). Normal launch → PID 8149 stable after `sleep 5`. Settings UI read back live via System Events AX: the Buttons tab showed the two seeded bindings (row 4: `Device` / `Activate Next Cursor Speed`, row 5: `Mission` / `Mission Control`), and the tab bar (window toolbar overflow menu "Navigation Tab Bar") lists `Buttons, Wheel, Scroll Bindings, Chords, Cursor, Devices`. A `pkill` + relaunch (PID 8673) loaded the same bindings and wheel profile back, proving the file — not defaults — was read.
- [x] **Wheel tab + "Default" profile**: the Wheel tab renders; note a Phase 1 file upgrades to an **empty** wheel list by design (absent Phase 2 keys default to `[]`, no profile auto-created — pass-through until the user adds one, per `testWheelModeProfileFallbackChain`). During this pass "Add Profile" was clicked via AX (creates "Profile 1"), the row's Name field was set to `Default` via AX (`value of text field 1 … to "Default"`), and after relaunch the Wheel tab showed 1 row named `Default`. Cursor-speed profiles were untouched by this.
- [x] **settings.json gains the new fields after a UI mutation**: after the Add-Profile/rename mutation, `python3 -I -m json.tool settings.json` → valid. Contents: preserved Phase 1 fields (`schemaVersion: 1`, `cursorSpeedProfiles` Slow/Default/Fast, `buttonBindings` fourth→device / fifth→mission) **plus** `wheelModeProfiles: [Default/acceleration]`, `activeWheelModeProfileID: null`, `scrollBindings: []`, `chords: []`. Phase 1 data survived the rewrite byte-for-byte in meaning.
- [x] **Corrupt-settings recovery**: with the app stopped, `printf 'CORRUPTED{{{ not json at all' > settings.json`, then normal launch → PID 8737 alive and unchanged after `sleep 5` (no crash). The Settings window's static texts included the corruption warning `settings.json could not be read (The data couldn't be read because it isn't in the correct format.); using defaults.` (read back via System Events AX) and all five button rows showed `Unbound` (defaults active from memory). A UI mutation cycle (Cursor tab: Add Profile 3→4 rows, delete 4→3 rows) rewrote the file, replacing the garbage with valid JSON: exactly `Slow`/`Default`/`Fast`, 0 bindings, 0 wheel profiles, `schemaVersion` 1 and the empty Phase 2 fields. The experiment was then cleaned up: the file was left in this fresh, valid, app-written defaults state and the app was quit (`pkill -x artMouse`).
- [x] **Settings schema lint**: `python3 -I -m json.tool settings.json` → valid on every check above (same tool choice as Phase 1; `plutil -lint` does not apply to JSON files).

### Findings from the automated pass

1. No defects found. Test count (143) exceeds the plan estimate (~113); both the brief and the estimate predate the final Phase 2 test surface, and every suite passed.
2. Phase 1 → Phase 2 upgrade leaves the wheel-mode list empty rather than seeding a "Default" profile. This matches the pinned fallback contract (no active wheel profile = stock pass-through) but means the "Wheel tab shows a Default profile" state only exists after the user adds one. Recorded above rather than "fixed", since seeding profiles on load would overwrite user intent.
3. The Settings tab strip lives in the window toolbar's overflow ("more toolbar items" → "Navigation Tab Bar") on macOS 26; tab switching had to go through that popup in AX. Human-only note for the visual pass below: check the tab bar layout/row widths there.

## Human checklist

- [ ] Permissions: fresh TCC state → banner shows, Grant button opens the right panes; after granting, wheel + button features work without relaunch.
  HOW TO VERIFY: remove artMouse from System Settings → Privacy & Security → Accessibility and Input Monitoring, launch the app and confirm the banner (observed present during the automated pass), click Grant for each row, approve both panes, then roll the wheel and press a bound button — both must work with no relaunch.
- [ ] Reverse scrolling: enable Reverse V → wheel up scrolls content down; disable restores stock direction.
  HOW TO VERIFY: in Settings → Wheel enable Reverse V on the active profile, roll the wheel up over a scrollable page — content must move down; disable it and confirm stock direction returns immediately.
- [ ] Acceleration mode: sens 2.0 → wheel scrolls visibly farther per notch.
  HOW TO VERIFY: set the wheel profile mode to Acceleration with Sens 2.0 and roll the wheel one notch in a long document — the scroll distance must be about twice the stock notch; lower Sens to 0.5 and confirm it visibly shortens.
- [ ] Constant mode: fixed distance per notch regardless of roll speed.
  HOW TO VERIFY: set mode to Constant, roll the wheel slowly once and then flick rapidly several times — every notch must advance the same fixed distance, with no speed-dependent jumps.
- [ ] Smooth scroll: a notch spreads into multiple small steps (watch a long page glide); per-notch distance should match Constant mode at the same Lines setting (3 lines/notch at defaults).
  HOW TO VERIFY: enable Smooth Scroll on the active profile, roll one notch over a long web page — the page must glide in several small steps instead of jumping, and stop cleanly when you roll again. Then set mode to Constant, roll one notch, and confirm the smooth glide covers about the same total distance as the constant notch (both 3 lines at defaults; if one visibly overshoots the other, the smooth total is wrong).
- [ ] Auto mode: flick and watch it continue, then stop after the configured notches of silence.
  HOW TO VERIFY: set mode to Auto with the default Auto Interval/Stop Ticks, flick the wheel once — scrolling must continue after you stop rolling and then halt by itself after roughly the configured ticks of silence; a reverse flick must stop or reverse it.
- [ ] Wheel→keys: bind a key code; rolling the wheel types the key; stop rolling releases.
  HOW TO VERIFY: on a Wheel profile enable the Keys section and choose a key code (e.g. Down-arrow), roll the wheel in TextEdit — the key must repeat while rolling and stop when the wheel stops, with no stuck key afterwards.
- [ ] Wheel-mode switching: bind a button to Device → Switch Wheel Mode; pressing cycles wheel profiles (cursor-speed profiles unaffected).
  HOW TO VERIFY: create two wheel profiles with obviously different Sens, bind a button to Device → Switch Wheel Mode, press it repeatedly — the active wheel profile must cycle (row highlighted in Settings) while the cursor speed stays on its current profile.
- [ ] Two-way binding: Wheel Up → Mission Control fires on up-roll only; Wheel Down unbound scrolls stock.
  HOW TO VERIFY: in Settings → Scroll Bindings bind Wheel Up to Mission Control, leave Wheel Down unbound; roll up (Mission Control must open) and roll down in a page (stock downward scroll, no Mission Control).
- [ ] Button→scroll action: bind 4th button to Scroll Down; press scrolls down.
  HOW TO VERIFY: in Settings → Buttons bind the 4th button to the Scroll Down action, press it over a scrollable page — the page must scroll down by roughly a wheel notch per press.
- [ ] Click-lock + scroll interplay regression (Phase 1 loop protection on the new synthetic-scroll path): smooth scroll ON, click lock ON, click-and-hold — no scroll storm, no input flood.
  HOW TO VERIFY: enable Smooth Scroll on the active wheel profile, bind Click Lock, click-and-hold past the threshold and keep rolling the wheel — the synthetic scroll events must not re-enter the interceptor and feed back (no runaway scrolling, system stays responsive; CPU of artMouse stays flat in Activity Monitor).
- [ ] Chords: Middle+4th fires the chord; Middle alone (released) fires Middle's own binding; Middle held past timeout then 4th pressed late does NOT fire the chord.
  HOW TO VERIFY: create a Chord on Middle+4th, bind Middle to Middle Click and the chord to a visible action; press both together → only the chord fires; press and release Middle alone → Middle's binding fires; hold Middle longer than the chord timeout, then press 4th → the chord must not fire (Middle's held action state is whatever the spec dictates, but the chord must not trigger late).
- [ ] Sleep/wake: wheel features still work after wake.
  HOW TO VERIFY: with reverse scroll or a scroll binding active, sleep the Mac from the Apple menu, wake it, and roll the wheel as the first action — it must work with no relaunch (tap re-enable logic only exercises on real hardware).
- [ ] Phase-1 regression spot-check: one click binding, cursor profiles, precision hold.
  HOW TO VERIFY: bind a button to a click op and confirm it lands in TextEdit; switch cursor speed profiles with a bound button and feel the difference; bind Precision, hold it while moving — cursor must drop to the Slow profile while held and restore on release.
- [ ] Visual pass incl. row width: Settings window layout is correct in light and dark mode, wheel-profile rows fit their controls without truncation, and the tab bar (toolbar "Navigation Tab Bar" overflow on macOS 26) renders all six tabs.
  HOW TO VERIFY: open Settings in both light and dark mode, switch through every tab, and confirm the binding rows, wheel-profile rows (Sens/Accel/Lines fields), chord rows and banners are readable, aligned and not clipped — particularly the wide wheel-profile rows noted in the automated findings.
