# Phase 1 manual verification (2026-11-10)

Produced by the Task 19 verification pass. The automated portion was executed on this
machine (macOS 26, Apple Silicon) against `build/artMouse.app` built from `phase-1`
HEAD `0e45236` + this doc. Items that require TCC grants, a physical mouse, visual
judgement, or sleep/wake on real hardware are left unchecked with a HOW TO VERIFY line.

## Automated results — all executed 2026-11-10

- [x] **Full test suite**: `swift test` → `Executed 82 tests, with 0 failures (0 unexpected)`. All suites passed (SettingsStoreTests, EventTapEngineTests, MediaKeySynthesizerTests, and the rest of the 18-task surface).
- [x] **Bundle build**: `./Scripts/make_app.sh` → `Build complete!` / `Built build/artMouse.app` (codesigned; one pre-existing deprecation warning in `ActionExecutor.swift`, non-blocking).
- [x] **App launches and stays alive**: `open build/artMouse.app` → `pgrep -x artMouse` = 60024; after `sleep 5` the same PID 60024 was alive (`ps` etime 00:14); killed with `pkill -x artMouse`.
- [x] **Safe-mode launch**: `open build/artMouse.app --args --safe-mode` → `ps -o args= -p 60787` shows `/Users/mozammal161/Desktop/Work/artMouse/build/artMouse.app/Contents/MacOS/artMouse --safe-mode`; PID 60787 unchanged after `sleep 5`; then killed. (Whether the cursor actually behaves stock is the human item below — Review Focus 4.)
- [x] **settings.json write + reload round-trip**: note — the file is **not** created on launch; `SettingsStore.reload()` treats a missing file as in-memory defaults and only `save()` writes it, so the write was triggered through the real UI (System Events UI scripting: status menu → Settings… → Cursor tab → "Add Profile"). `~/Library/Application Support/artMouse/settings.json` then appeared (661 bytes) as valid JSON containing `Slow`/`Default`/`Fast` plus the added `Profile 4` and `"schemaVersion": 1`. After `pkill` + relaunch the Cursor tab showed 4 profile rows, proving the persisted file (not the 3-row default set) was loaded back. Removing the extra profile via the row's trash button rewrote the file back to exactly `Slow`/`Default`/`Fast`. Final state left on disk is the app-written default file.
- [x] **Corrupt-settings recovery**: with the app stopped, `printf 'CORRUPTED{{{ not json at all' > settings.json`, then normal launch → PID 60837 alive and unchanged after `sleep 5` (no crash). The Settings UI showed 3 profile rows, i.e. defaults were active from memory; a settings mutation (add + remove a profile) rewrote the file, replacing the garbage with valid JSON containing exactly `Slow`/`Default`/`Fast` and `"schemaVersion": 1`. This is the crash-safety contract from spec §7 verified end to end. The file was then left in this fresh, valid, defaults state (app-written), and the app was quit. **Re-run after the warning-banner fix**: same experiment against the rebuilt bundle (corrupt file → launch → PID 61498 stable 5 s); the Settings window's static texts now include the corruption warning "settings.json could not be read (The data couldn't be read because it isn't in the correct format.); using defaults." (read back via System Events AX), and the mutation cycle again rewrote valid defaults. Visual layout confirmation remains a human check below.
- [x] **Settings schema lint**: `python3 -I -m json.tool settings.json` → valid on every check above. Note: `plutil -lint` is **not applicable** to this file — it validates plists and rejects JSON (`settings.json: (Unexpected character { at line 1)`); the JSON validator was used instead.

### Findings from the automated pass

1. **FIXED in this pass**: the settings-corruption warning was never shown in the UI (`SettingsStore.lastLoadWarnings` had no consumer). Now surfaced via `WarningsBannerView` (yellow banner matching `PermissionBannerView`) between the permission banner and the tab view; verified live in the corrupt-settings experiment above. Human visual confirmation remains under Review Focus 2.
2. **settings.json is not created on launch** (created on first mutation). Consistent with the store's contract (missing file = silent defaults), but it changes how the "lint the regenerated file" step must be triggered (a UI mutation), as recorded above.
3. Pre-existing deprecation: `NSWorkspace.launchApplication(withBundleIdentifier:…​.withoutActivation)` in `Sources/ArtMouseCore/Actions/ActionExecutor.swift:13` (deprecated since macOS 11). Non-blocking.

## Human checklist

- [ ] Permissions: fresh TCC state → banner shows, Grant button opens the right panes; after granting, engine works without relaunch.
  HOW TO VERIFY: remove artMouse from System Settings → Privacy & Security → Accessibility and Input Monitoring, launch the app and confirm the banner (it was already observed present in this fresh state during the automated pass), click Grant for each row, approve both panes, then bind a button and confirm the remap works with no relaunch.
- [ ] Review Focus 1: bind 5th button to Device → Activate Next Speed; press it → cursor speed jumps, warning appears, speed restores exactly 5 s later.
  HOW TO VERIFY: in Settings → Buttons bind the 5th button to Device → Activate Next Speed, press the physical 5th button: cursor speed must change immediately with the warning banner, then restore to the previous profile exactly 5 s later.
  UPDATE (final fix wave): the warning clause is now implemented — `EngineBootstrap` is `@Observable` and mirrors `CursorController.safetyRestoreWarning` on the existing 0.5 s tick, and the new `SafetyWarningBannerView` (placed between the load-warnings banner and the tab view) renders it. The human visual confirmation above remains unchecked.
- [ ] Review Focus 2: hand-corrupt ~/Library/Application Support/artMouse/settings.json → app relaunches with defaults, warning visible in UI, no crash.
  HOW TO VERIFY: the defaults + no-crash + warning-shown half is already automated (see above — the banner text was read back from the live window via accessibility); for the human half, hand-corrupt the file, relaunch, and visually confirm the yellow warning banner renders correctly in the Settings window.
- [ ] Review Focus 3: revoke Input Monitoring while running → banner re-appears (tapActive flips false).
  HOW TO VERIFY: with both permissions granted and the app running, uncheck artMouse under Input Monitoring in System Settings and confirm the permission banner re-appears within a few seconds (the `tapActive` flip itself is covered by `EventTapEngineTests`).
- [ ] Review Focus 4: launch with --safe-mode → cursor behaves stock; verify no interception by binding nothing and observing normal clicks everywhere.
  HOW TO VERIFY: the flag + stable process is automated (see above); physically launch with `open build/artMouse.app --args --safe-mode` and click/type/drag everywhere — cursor and buttons must behave exactly like stock macOS.
- [ ] Review Focus 5: extended-button mouse (if available): unbound extra buttons act stock.
  HOW TO VERIFY: on a mouse with buttons beyond the standard five (e.g. an 8-button gaming mouse), press each unbound extra button and confirm it performs its stock macOS action with no interception.
- [ ] Buttons: each click op (left/right/middle/double/4th/5th) lands in TextEdit; modifier combos (e.g. Right Click + ⌘ = browser back-forward if bound).
  HOW TO VERIFY: bind each click operation in turn, click into TextEdit and confirm left/right/middle/double-click/4th/5th all land; then bind a modified combo (Right Click + ⌘ → browser back/forward) and confirm it fires in Safari.
- [ ] Click Lock: hold left beyond threshold → sticky drag; next click releases.
  HOW TO VERIFY: bind Click Lock, hold the left button past the threshold, drag, release — the drag must stay sticky; the next click must release it.
- [ ] Mission ops: Mission Control, App Windows, Launchpad, Show Desktop, Desktop 1–3, Move Space L/R, Spotlight, Fullscreen toggle.
  HOW TO VERIFY: bind each mission operation to a button and press it once: each must trigger its system effect (create at least 3 desktops and put a window fullscreen first for the space/fullscreen ops).
- [ ] Music ops: play/pause, next, previous, mute, volume ±, eject, with Music.app/Spotify.
  HOW TO VERIFY: start playback in Music.app (then repeat with Spotify), trigger each music operation from a bound button and confirm the transport/volume/eject effect (eject requires a mounted disc or removable volume).
- [ ] Zoom ops: app zoom in/out in Safari (⌘+/-), screen zoom (needs "Use keyboard shortcuts for zoom" enabled in Accessibility → Zoom).
  HOW TO VERIFY: enable "Use keyboard shortcuts for zoom" in System Settings → Accessibility → Zoom, then trigger app zoom in Safari (⌘+/- behaviour) and screen zoom from bound buttons.
- [ ] Switcher/open: switch to Safari by bundle ID, open a path, open a URL.
  HOW TO VERIFY: bind switch-next/switch-previous, switch-to-app (Safari via bundle ID), open path (any local folder) and open URL; press each and confirm the app activates or the path/URL opens.
- [ ] Cursor: Slow/Default/Fast profiles change feel; Precision hold (bound to a button) drops to Slow while held.
  HOW TO VERIFY: switch between Slow/Default/Fast with a bound button and feel the sensitivity difference; bind Precision to a button, hold it while moving — the cursor must drop to the Slow profile while held and restore on release.
- [ ] Sleep/wake: sleep the Mac, wake, bindings still work (tap re-enabled).
  HOW TO VERIFY: sleep the Mac from the Apple menu, wake it, and press a bound button as the first action after wake — it must work with no relaunch (the tap re-enable logic is exercised only on real hardware).
- [x] settings.json survives app restart and is valid JSON (lint it).
  Evidence: automated above — UI-written file (661 bytes, `python3 -I -m json.tool` valid, `Slow`/`Default`/`Fast` + schemaVersion 1), killed and relaunched the app, file unchanged on disk and its 4-profile content was loaded back into the UI; the linter to use is `python3 -m json.tool` (`plutil -lint` rejects JSON files).
