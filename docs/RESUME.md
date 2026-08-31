# Resume point — 2026-08-31

Pick up here next session.

## Where things stand

- **Branch:** `main`, working tree clean. **11 commits ahead of `origin/main`, NOT pushed**
  (standing instruction: do not push automatically — push only when the user asks).
- **Last milestone commit:** `2f754be` — portrait lock, honeycomb hex board,
  persistent power tiles, armed 6-booster tray, 50-level curve, visual pass.
- **Debug APK:** `build/color-clash-debug.apk` (55 MB, v0.5.0 / code 1,
  `com.colorclash.game`, arm64-v8a + armeabi-v7a, minSdk 21, portrait manifest).
  `build/` is git-ignored.

## Verified on the physical phone (OnePlus CPH2707, Android 16)

- Installs with `adb install -r` (no uninstall, save preserved).
- Launches, runs steadily, **PORTRAIT** confirmed (surface 1272×2800, `SCREEN_ORIENTATION_PORTRAIT`, ROTATION_0).
- No crashes, no Godot script errors, no GL/resource errors, no emoji-font error.
- Honeycomb board + persistent power tiles + 6-chip booster bar all render upright.

## Tests

- 313 / 313 unit assertions pass; all 4 smoke scripts pass.
- Run: `<godot4> --headless --path game --script res://tests/test_runner.gd`
  Smokes: `smoke_main_e2e`, `smoke_audio_chain`, `smoke_level_map`, `smoke_all_levels`.
- Godot 4.4.1 lives in the session scratchpad only (not in repo). Reinstall from
  godotengine.org if the scratchpad is gone; export templates are at
  `%APPDATA%\Godot\export_templates\4.4.1.stable\`.

## Rebuild + reinstall (quick reference)

```
<godot4> --headless --path game --import
<godot4> --headless --path game --export-debug "Android" <repo>\build\color-clash-debug.apk
C:\Android\platform-tools\adb.exe install -r <repo>\build\color-clash-debug.apk
C:\Android\platform-tools\adb.exe shell am start -n com.colorclash.game/com.godot.game.GodotApp
C:\Android\platform-tools\adb.exe logcat -s godot GodotApp Godot
```
See `docs/ANDROID.md` for the full toolchain.

## Open items / next candidates (not yet done)

1. **On-device play feedback** — the user will play this exact APK; act on what
   looks/feels off (board could use more of the vertical space; steady-state FPS
   not yet measured over a real session; check booster taps aren't eaten by the
   bottom gesture bar).
2. Fever meter / SCORE label area in the HUD is a bit cramped — tidy spacing.
3. Backdrop nebula washes still slightly banded on some frames.
4. Level-map environment is darker/moodier than the reference's sunny map.
5. Score "+N" fly-up numbers on blasts (reference shows "AMAZING! 560").
6. `docs/ANDROID.md` still says "40-level" in one place — trivially stale.
7. Deferred per the user until the visual/gameplay bar is satisfactory:
   Firebase / Ads / IAP wiring, release AAB.

## Do NOT

- Push to origin without being asked.
- Re-detonate powers automatically on the creating match (persistence is intentional).
- Revert the hex grid — reference-matching requires it; `BoardModel.get_neighbors()`
  is the single source of truth.
