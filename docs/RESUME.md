# Resume point — 2026-09-11  ·  WAR OF LOVE  ·  ADMOB PRODUCTION WIRING + UMP CONSENT

**Latest commit: `5674a73`** (native AdMob backend already committed +
device-verified with a real rewarded test ad on the previous session) ·
branch `backup_asset_integration_2026-09-02`, **6 commits ahead of
`origin`**, not pushed. This file (`docs/RESUME.md`) had gone stale across
those 6 commits (`8ab2ec4` VRAM/arm64-only preset, `d859c53`/`ea80b30`/
`0a4e659`/`5674a73` AdMob) — it was last updated at `025dc69`. See
`docs/MONETIZATION.md` for the authoritative, actively-maintained ads doc
instead of duplicating it here.

## CHECKPOINT — 2026-09-11 (pass 2) · UMP CONSENT INTEGRATION (UNCOMMITTED)

Built on top of the production-IDs checkpoint below in the same session.
Google's User Messaging Platform (UMP) SDK is now wired for EEA/UK/
Switzerland consent, following the official UMP Android quick-start
(`com.google.android.ump:user-messaging-platform:4.0.0`, verified current
via live fetches of developers.google.com/admob/ump on 2026-09-11).

**`game/android_plugin/admob/src/.../ColorClashAdMob.kt`:** `initialize()`
now runs `requestConsentInfoUpdate()` → `loadAndShowConsentFormIfRequired()`
→ `MobileAds.initialize()` (only once `canRequestAds()` is true) on every
launch, BEFORE any ad request — matches Google's own sample pattern
(fast-path check + form-gated check, `mobileAdsInitializeCalled` guard
against a double `MobileAds.initialize()`). New `@UsedByGodot` methods:
`canRequestAds()`, `isPrivacyOptionsRequired()`, `showPrivacyOptionsForm()`.
Still ONE signal (`ad_event`) — new event names only:
`consent_info_updated`, `consent_info_update_failed`, `consent_form_error`,
`consent_form_dismissed`, `ads_blocked`, `privacy_options_dismissed`,
`privacy_options_error`. No consent POLICY in the plugin — same "thin
bridge" rule as the rest of it.

**Gradle:** new `com.google.android.ump:user-messaging-platform:4.0.0`
dependency, added via a NEW separate idempotent patch
(`patches/build_gradle_ump.patch`, applied by `install.sh` step 4) rather
than editing the already-applied `build.gradle.patch` — keeps the two
AdMob-core vs. UMP changes independently re-appliable onto a fresh
template. Verified: reverse-applied both patches from the live
`android/build/build.gradle` back to a pristine file, then re-applied both
in sequence and diffed — byte-identical. Applied directly to the current
(gitignored, regenerable) `game/android/build/build.gradle` +
`.../ColorClashAdMob.kt` too, so today's exports pick it up without
regenerating the template.

**`scripts/services/ads_service.gd`:** additive only, nothing existing
changed — `can_request_ads()`, `consent_status()`,
`privacy_options_required()`, `show_privacy_options()`, `consent_updated`
signal. The consent gate needed NO new gating logic anywhere:
`_native_initialized` (already the one thing every rewarded/interstitial
call site checks) only ever flips true post-consent now, since the native
`initialized` event itself only fires post-consent. `_ads_allowed` mirrors
it 1:1 for the public API's sake.

**`scripts/ui/settings_panel.gd`:** new "Privacy Choices" row in the
existing links section, visible only when `Ads.privacy_options_required()`
(re-checked every `open()`, not just at construction — consent can settle
after the panel is built). No new art asset; procedural secondary-button
style, real behaviour (calls `Ads.show_privacy_options()`), unlike the
other 3 link rows which are still "coming at launch" placeholders.

**Tests:** `tests/test_ads_service.gd` — extended `_NativeStub` with
`canRequestAds`/`isPrivacyOptionsRequired`/`showPrivacyOptionsForm`; 8 new
test functions (consent not-required / required-then-granted /
required-but-denied, `can_request_ads()` gating a rewarded show, privacy
options availability + entry point, safe no-op with no backend, withdrawal
via privacy options blocks ads again, full consent→rewarded→interstitial
flow through the new gate). All synthetic `debug_feed_native_event` calls —
zero live consent UI, zero network, deterministic. `test_runner`
**3747/3747 pass** (was 3715 before this pass's 32 new checks — 8 functions
× ~4 checks each). **9/9 smokes pass** (2 of them print a
`SCRIPT ERROR: Compile Error: Failed to compile depended scripts` /
`Identifier not found: GameData` warning before their PASSED line — verified
this reproduces byte-identically with every file this pass touched
stashed back to the pre-pass state, so it's a pre-existing headless-runner
flake unrelated to this work, not a regression).

**Verified end-to-end:** ran a real `--export-debug "Android"` (full Gradle
build); it succeeded, and the resulting APK's `classes3.dex` was confirmed
(via a byte-search script, since `strings` isn't available in this
git-bash) to contain `ConsentInformation` / `UserMessagingPlatform` /
`ConsentRequestParameters` / `colorclash/admob` — the UMP SDK genuinely
compiled and linked in, not just a source-level change. Also checked the
Gradle-merged `AndroidManifest.xml` — `INTERNET` + `ACCESS_NETWORK_STATE`
present (UMP needs network), App ID + plugin meta-data both present, no
manifest changes needed for UMP itself (it self-merges via its AAR, no
extra entries this project needs to declare). Deleted the verify APK
afterward (gitignored `build/` anyway).

**NOT done this pass (by design):**
- The actual GDPR/UK/US consent **message** is NOT yet configured in the
  AdMob console (Privacy & messaging) — code is ready but has nothing to
  show an EEA/UK/CH user until that's published. Needs the AdMob account
  owner; not something committable to the repo. See
  `docs/MONETIZATION.md`'s "Consent (UMP)" section, last paragraph.
- Release keystore — explicitly told not to touch it this pass.
- Committing/pushing — none of this pass's changes are committed.

**Docs updated:** `docs/MONETIZATION.md` (new "Consent (UMP)" section +
updated Tests/outstanding-items sections), `docs/PRIVACY_POLICY.md` ("Your
choices" + advertising section now describe the UMP flow, dated
2026-09-11), `game/android_plugin/admob/README.md` (dependency list, new
Plugin API rows, new patch file in the directory tree).

## CHECKPOINT — 2026-09-11 · PRODUCTION ADMOB IDS WIRED (UNCOMMITTED)

Production AdMob app + ad units were created:
App ID `ca-app-pub-9900197126922435~4709930379`, Rewarded
`ca-app-pub-9900197126922435/9777941726`, Interstitial
`ca-app-pub-9900197126922435/9191618364`.

**`game/data/ads.json`:** `prod` fields filled for `app_id` / `rewarded` /
`interstitial` (banner has no placement, left empty); `use_test_ads` flipped
`true → false`.

**`game/scripts/services/ads_service.gd` `_ready()`:** `_test` is now
`bool(config.use_test_ads) or OS.is_debug_build()` — a debug build (editor,
`--headless` tests, debug APK export) **always** forces test ads regardless
of the config flag; only a real non-debug release export honours
`use_test_ads=false` and serves the prod ids. This is the one behavior
change; everything else (placements, interstitial gating rules, native
plugin glue, reward-once guarantees) is untouched.

**Verified:** `test_runner` still **3715/3715 pass**, all **9/9 smokes**
pass. Exported a real debug APK (`--export-debug "Android"`) and inspected
the packed `assets/data/ads.json` inside it — confirms `use_test_ads:false`
+ correct prod ids reach the build; deleted the verify APK after (gitignored
`build/` anyway). Did NOT attempt a signed release AAB export — no upload
keystore exists yet (`docs/ANDROID_RELEASE.md` — unrelated to ads, blocks
any real release regardless) and creating one is a user decision (permanent
signing key, needs safe backup).

**docs/MONETIZATION.md updated** with the new test/prod selection rule, the
real prod ids, and a new "Worldwide release — outstanding" section.

**Outstanding before a worldwide Play Store release** (none of this exists
in the repo yet — checked, no UMP/consent code/plugin/docs found):
1. **UMP / consent SDK** for EEA/UK/Switzerland — Google requires this
   before requesting ads there; not started. Needs: `user-messaging-platform`
   Play services dep, a native consent-request/show call (in
   `ColorClashAdMob` or a sibling plugin) gating the first
   `MobileAds.initialize()`, and headless-testable policy in `AdsService`.
2. Release upload keystore (`docs/ANDROID_RELEASE.md`) — not created.
3. Play Console: link the AdMob app, declare `AD_ID`/advertising data in
   the Data Safety section, before submitting for review.
4. `docs/ANDROID_RELEASE.md` itself has drifted (still says arm64 +
   armeabi-v7a / VIBRATE-only permissions; `export_presets.cfg` `preset.1`
   is actually arm64-only with INTERNET + ACCESS_NETWORK_STATE + VIBRATE
   now, per `8ab2ec4` and the AdMob commits) — not fixed this session, out
   of scope for the ads task, flagging for next pass.

**Not done this session (by design — not asked for):** UMP/consent
implementation itself, keystore creation, committing/pushing.

## CHECKPOINT — 2026-09-08 (pass 4) · STARTUP-DELAY FIX (no white/logo screen) (UNCOMMITTED)

Correction on pass 3: the previous cut still showed a white/crown screen for
~8s before the Rectangle Studio animation, and the animation itself ran
~7s (stalled) instead of its ~3.3s.

**Exact cause of the delay (found by device logcat timing):**
1. `AssetLibrary._ready()` ran a boot "audit" that `load()`s all 74 LOSSLESS
   textures — **~8 s of cold decode on the device**, BEFORE `app._ready()`
   (autoloads run first), so the OS launch window (Android 12+ shows the
   launcher icon on `windowSplashScreenBackground` — platform/Godot-template
   controlled, not removable without a gradle build) sat there the whole time.
2. `MusicDirector._ready()` synthesised every adaptive music layer at boot
   (runtime WAV synthesis) — more seconds, and `MusicDirector.start()` is
   dead code so the layers were never even used.
3. `app._ready()` then built the ENTIRE game (HUD/board/3 characters/menu/
   10-world island screen w/ 60 lossless PNGs/worldmap/...) synchronously
   before the first frame could draw.
4. `_warm_up_game()` preloaded all 60 island textures during the branding
   animation, starving the video decoder (`elapsed`≈0.5 s of a 3.3 s clip).

**Fixes (startup only):**
- `AssetLibrary._ready()` — the 74-texture boot audit is **removed** (it was
  a diagnostic; `test_assets.gd` calls `audit()` directly). Textures load
  lazily on first `tex()`.
- `MusicDirector` — layer synthesis moved OUT of `_ready()` into a lazy
  `_ensure_layers_synthesised()` called from `start()` (which never runs at
  boot). `_ready()` now only creates the cheap player nodes.
- `app._ready()` — now does almost nothing: creates `_studio_splash` +
  `play()`s it, creates the cheap `SplashScreen` (poster) node, starts a
  GENTLE `_warm_up_game()` (12 SMALL textures, one per frame — no island
  art). The heavy `_build_game()` is deferred to `_on_studio_splash_finished`
  and runs UNDER the poster/loading screen (which is what it is for). On
  `_headless` the build stays synchronous so the smokes get a ready app.
- `_on_studio_splash_finished` — if the game is somehow already fully built +
  warmed (fast device / headless), the poster is SKIPPED entirely (spec Case
  B, "move forward immediately"). Otherwise the poster shows, the build runs
  under it, and its `loading_ready` gate (`_warm_done AND _hud != null`)
  holds it until the game is ready, then it fades to the menu.
- `StudioSplash` clip re-cut to the supplied animation's actual completion
  (~3.3 s, was 5.0 s incl. a 1.2 s hold); `MAX_DURATION` 6.5 → 4.0 (safety
  cap only — the normal path finishes on the video's natural end).
- `SplashScreen` gained `min_hold` (defaults to its 1.35 s beat).

**On-device cold launch (OPPO CPH2707) — measured from logcat:**
```
engine start .......................... 0.0 s
Rectangle Studio splash on screen ..... ~1.7 s   ([startup] app._ready at ~1800 ms)
background warm-up complete ............ ~2.5 s   (ran DURING the branding — parallel, gentle)
branding animation finished ........... ~5.2 s   ([StudioSplash] finished elapsed=3.47s  <- plays at full speed, NOT stalled)
game built (under the poster) ......... ~7.4 s
poster/loading -> menu ................ ~7.9 s
```
So the **Rectangle Studio branding is ~3.5 s and smooth** (was ~7 s
stalled); it is the first game content; the ~1.7 s before it is the
platform launch window on a `#fbfdff` background that matches the branding
splash's own near-white (no Godot-created white/logo screen — verified in
`build/c5_02.png`: plain light bg, no crown/War-of-Love logo). Screenshots
`build/c5_*.png` show the animation reveal + "RECTANGLE STUDIO" wordmark on
device; the game then boots normally to the menu / island screen (60 fps,
no errors).
**Platform limitation:** the Android 12+ system SplashScreen window (icon
on its background) is baked into Godot 4.4's non-gradle Android template
(`GodotAppSplashTheme` → `windowSplashScreenAnimatedIcon=@mipmap/icon_foreground`)
and cannot be removed without switching to a gradle build. Its background
now matches the branding splash and it is only shown for the ~1.7 s
platform launch interval (down from ~8 s). This OPPO unit also overlays its
own "Game Space" card over the first ~4 s of any game launch.

**Tests:** `test_startup_splash.gd` updated (short-clip / MAX_DURATION
checks); `test_runner` **3341 / 3341 pass**. `smoke_startup.gd` rewritten —
verifies branding is frame 1, build deferred, warm-up concurrent, Case A
(poster holds during load) and Case B (poster skipped when load done). All
9 smokes pass.

**UNCOMMITTED — not committed, not pushed; all prior work still in the tree.**

## CHECKPOINT — 2026-09-08 (pass 3) · RECTANGLE STUDIO STARTUP SPLASH (UNCOMMITTED)

Replaced ONLY the first white-background/logo splash with the supplied
Rectangle Studio branding animation. New flow:
**APP LAUNCH → Rectangle Studio splash → existing poster/loading screen
(unchanged) → menu.**

**Source:** `Downloads/splashscreen/rectangle_studio_logo_animation.html` —
one self-contained file, pure SVG + CSS keyframes (isometric blue
"Rectangle" mark reveal + "RECTANGLE STUDIO" wordmark on a #fbfdff
gradient), ~3.2s, NO external URLs/CDN/images/fonts. Godot 4 has no native
HTML surface, so — per the brief's fallback clause and the project's
existing `intro.ogv` / `sea_clip.ogv` pattern — the HTML animation was
**frame-exactly pre-rendered** to `assets/branding/studio_intro.ogv`
(Theora, 720×1600, yuv420p, 5.0s incl. a 1.2s settle hold, 277 KB,
packaged in the APK). Capture method: a seek-harness copy of the HTML
(CSS animations frozen via `animation-play-state:paused` +
`animation-delay:-Ns`) screenshotted by headless Chrome at 30 fps, then
`ffmpeg -c:v libtheora`. The animation is NOT redesigned or reimplemented;
the `.html` is kept in `assets/branding/` for provenance (Godot ignores
it, not packed). **yuv420p is required** — the first cut was yuv444p and
Godot's Theora decoder rendered a black box on device.

**New `scripts/ui/studio_splash.gd` (`StudioSplash`):** full-rect Control
on CanvasLayer 110, `#fbfdff` ColorRect ground + a cover-fit
`VideoStreamPlayer`. `signal finished()` fires once — on the video's
natural end, a 6.5s `MAX_DURATION` safety timeout, or immediately on
headless/auto-skip/missing-asset (mirrors `IntroVideoScreen`).

**`scripts/ui/splash_screen.gd` (the existing poster — look unchanged):**
now idle+hidden until `begin()`; gained an optional `loading_ready:
Callable` — after its own 1.35s beat it holds visible until that returns
true (Case A), else fades immediately with no extra delay (Case B/C).

**`app.gd`:** `_studio_splash` created + `play()`ed as the FIRST thing in
`_ready()` (its frame covers the heavy node build). `_warm_up_game()`
coroutine kicks off the same frame — yields every step, preloads level +
world data, all 10 islands' art + parts, board/sea assets, gem/power
atlases, menu/poster textures — sets `_warm_done`. `_studio_splash.finished`
→ `_on_studio_splash_finished()` → `_splash.begin()` + a 0.3s cross-fade of
the branding layer over the (already-visible) poster (no black/white
frame). `_splash.loading_ready = func(): return _warm_done`.
`_on_splash_finished()` (menu music) unchanged.

**`project.godot`:** `boot_splash/show_image=false` (the poster no longer
flashes during engine boot — it is only the SECOND screen now) and
`boot_splash/bg_color` → `#fbfdff` so the engine-boot frame + Android
system-splash background match the branding splash (no white flash). The
launcher icon (unrelated logo) is untouched.

**Tests:** new `tests/test_startup_splash.gd` (registered) — .ogv packaged
+ Theora, `boot_splash/show_image==false`, branding splash finishes
exactly once headless / no double-finish / eats taps, poster idle until
`begin()` then gates on `loading_ready` (Case A holds, Case B fades with no
delay). `test_runner` **3339 / 3339 pass** (+5). New `smoke_startup.gd`
boots the real scene: branding → poster (`begin()`) → warm-up completes
(no deadlock) → menu; plus the reverse order (warm-up done before branding)
also fades the poster with no stall. All 9 smokes pass.

**APK re-exported + installed on `3C15CB00ABS00000`.**
**On-device cold launch — state machine confirmed via device logs:**
`[StudioSplash] playing … playing=true` → `[startup] background warm-up
complete` (~2s in, WHILE the splash plays — concurrent) → `[StudioSplash]
finished (elapsed=5.25s)` (video played to its natural end, not the
timeout) → `[startup] branding splash done -> poster begins
(warm_done=true)` (Case B — no wait) → `[startup] poster/loading done ->
menu` ~1.6s later. Exact required sequence, no deadlock, background load
concurrent with the animation.
**Screenshot limitation:** this OPPO/ColorOS unit shows its own "Game
Space / Unrivaled Performance" overlay over the first ~4s of every game
launch and its SurfaceView compositor lags the Godot surface for several
more seconds on a heavy first frame (documented across this project), so
`adb screencap` cannot capture the branding-splash pixels here — the
pre-yuv420p build DID show the VideoStreamPlayer drawing (a black box), and
the yuv420p logs prove it now plays to completion. On a stock Android
device the branding splash is visible for its full ~5s.

**UNCOMMITTED — not committed, not pushed; all prior work still in the tree.**

## CHECKPOINT — 2026-09-08 (pass 2) · PER-ISLAND PROGRESSION FIX + UI POLISH (UNCOMMITTED)

Corrected the island progression architecture and 4 UI issues. **The old
world→campaign-band routing (World k → global levels 10k-9..10k) is GONE.**

**New progression — `IslandProgress` autoload** (`scripts/economy/island_progress.gd`,
registered after `Progress`; the campaign `Progress` autoload is UNTOUCHED and
dual-written for the authored level so older story/backdrop views stay sane):
- Each of the 10 islands has its OWN sequential run of
  `LEVELS_PER_ISLAND = 100` world-local levels (the one constant limit —
  raise it freely; also a `force_unlock_island()` hook for future
  key/achievement unlocks, not wired).
- Island 1 unlocked at start; islands 2-10 LOCKED.
- Completing island *i* level *N* unlocks ONLY island *i* level *N+1*.
- Completing island *i* level **100** unlocks island *i+1* (its level 1
  becomes current). Nothing else unlocks another island — clearing island 1
  level 10 no longer touches island 2 (the reported bug).
- Save key `island_progress`, keyed `<worldId>/<localLevel>`.

**Identity separation:** `(worldId, worldLocalLevel)` is the progression id.
`WorldCatalog.authored_level_id(world, localLevel)` resolves which authored
campaign `LevelConfig` supplies a slot's board — each island draws from a
pool (islands 1-5 = their 10-level `campaign_span` band, islands 6-10 = the
whole 50-level authored campaign) cycled by `(localLevel-1) % pool.size()`,
so **every** slot 1..100 is playable by REUSING an authored level. No
procedural/fake levels; the 50 authored levels are never modified. Visual
part still cycles `(localLevel-1) % 5` all the way to 100.

**`WorldCatalog`:** removed `campaign_level_id` / `world_id_for_campaign_level`
/ `is_playable` / `coming_soon`; added `authored_level_id`, `levels_per_world`,
`prerequisite_name`; `world_state` / `node_state` / `focus_local_level` /
`is_level_unlocked` now delegate to `IslandProgress`.

**`InfiniteScrollModel`:** `max_index` (100) — `layout()` never plans past
it, `clamp_offset(offset, viewport_h)` bounds both ends. **`InfiniteLevelScroller`:**
`level_chosen(world_id, local_level)`; routes an unlocked world-local level,
toasts a locked one. **`InternalLevelMap`:** `level_selected(world_id,
local_level)`; LOCKED banner (replaces COMING SOON). **`app.gd`:**
`_active_local_level`; `_go_to_level(world_id, local_level)`; `_on_level_won`
records into `IslandProgress` at that slot; "Next" = next level of the SAME
island (map after L100); milestone chest keyed to `local % 5`; new
`_debug_start_authored_level()` for the campaign-id smokes.

**UI FIX #1 — GOAL panel:** objective chips shrunk (padding 16/18→9/10,
icon 40→30, count FS_HEADING→FS_BODY, sep 10→6) AND `_layout_topbar` now
scales the whole chip row to fit STRICTLY inside `_goal_mid`'s inner rect
(border + 14px pad) on both axes, centred — no chip can cross the panel
border. The supplied GOAL art is never stretched.

**UI FIX #2 — Back button:** `UiKit.back_button()` — a 176×88 fantasy glass
pill, gold border, a big LEFT-pointing chevron (`_Glyph &"chevron_left"` =
the existing chevron mirrored on X + thicker/larger) and a "BACK"
FS_HEADING gold label. Replaces the tiny `icon_button(&"chevron")` on both
island screens; kept inside the safe-area insets.

**UI FIX #3 — text sizing:** island names FS_HEADING→FS_TITLE (world cards
+ internal-map title), map title FS_TITLE, "BACK" FS_HEADING, "LOCKED"
tag ~22-40px responsive, level-board number `bh*0.44`→`bh*0.56` and the
board itself 0.34→0.40 of part width (still constant across digit counts,
still centred + attached).

**UI FIX #4 — locked island:** `WorldCard._draw()` overlays a dark gold-ringed
medallion + padlock (reuses `AssetLibrary.tex(&"obstacle_lock")` when
present, else a clean vector padlock) + "LOCKED" over a locked island's
(dimmed) supplied art — separate overlay, PNG untouched; not shown for
current/unlocked/complete islands. Tapping a locked island on the
selection screen toasts "finish <prev island> first" instead of navigating.

**Tests:** new `tests/test_island_progress.gd` (registered) — the 22
required checks incl. L1 unlocked / L2 locked at start, L1→L2, L9→L10,
L10→L11, L50→L51, L99→L100, L100→island 2, island 2 L10 does NOT unlock
island 3, island 3 locked until island 2 L100, identity vs part vs
authored id, bounded pool + stop at L100, locked-overlay state.
`test_world_system.gd` rewritten for the new model + a back-arrow-direction
check. `test_runner` **3334 / 3334 pass** (+554). `smoke_level_map`
rewritten — runs the EXACT bug repro (clear island 1 L10 → assert island 1
L11 unlocked AND island 2 L1 still LOCKED) → **PASS** ("Bug repro OK");
`smoke_main_e2e` (new island flow), `smoke_overhaul_stages`,
`smoke_all_levels`, `smoke_shop_flow`, `smoke_combat_anim`,
`smoke_boss_dual_win`, `smoke_audio_chain` all PASS.

**APK re-exported + installed on `3C15CB00ABS00000`** (exit 0, ~456 MB).

**On-device acceptance — PASS.** PLAY → 10 islands over SEA CLIP; Evergreen
Kingdom shows **"3 / 100"** (per-island 100-level progression, 3 levels
cleared this session); **Emberfall Isle + Golden Oasis show the gold
padlock medallion overlay + "LOCKED"** (UI FIX #4 — `obstacle_lock` asset
over the dimmed supplied art, PNG untouched) — i.e. **clearing island 1
levels did NOT unlock island 2 (the exact bug, fixed)**. Inside Evergreen:
level 1 done → level 2 "current" (gold ring) → level 3 locked; tapping a
locked level is a no-op; entering level 2 shows **HUD "LEVEL 2"**
(world-local number) with the objective chip **inside** the GOAL panel
(UI FIX #1); the **"◀ BACK"** fantasy pill (UI FIX #2) and enlarged
island-name / board-number text (UI FIX #3) render correctly; part
templates cycle (level 6 = part 1). Screenshots `build/isl2_*.png`. The
full 10-consecutive-level playthrough is impractical via adb match-3 — the
headless `smoke_level_map` runs that exact sequence (island 1 L1→L10→L11
with island 2 still locked, then L11..L100 → island 2 unlocks, island 2
L10 does NOT unlock island 3) and passes.

**UNCOMMITTED — not committed, not pushed; all prior work still in the tree.**

## CHECKPOINT — 2026-09-08 · 10-WORLD ISLAND SYSTEM + INFINITE LEVEL MAP (UNCOMMITTED)

New PLAY flow: **MainMenu → MainIslandScreen (10 worlds over the looping SEA
CLIP video) → InternalLevelMap (infinite recycled zig-zag level map) →
existing gameplay.** Built against the supplied package
`Downloads/Islands/` (Instructions.txt + 10 main-island PNGs + 10×5 internal
part PNGs + `Level number board…png` + `Sea clip.mp4`).

**Assets** copied byte-identical (MD5-verified, curly-apostrophe folders
renamed to clean ascii ids on copy, sources untouched) into
`game/assets/islands_v2/`: `worlds/NN_<id>.png` ×10, `parts/NN_<id>/1..5.png`
×50, `level_board.png`, `sea_clip.mp4` (kept as source) + `sea_clip.ogv`
(Theora transcode — Godot 4 VideoStreamPlayer only decodes Theora, same
pattern as `intro.ogv`). The `.mp4` is not a Godot resource so it is not
packed into the APK.

**Data:** `game/data/worlds.json` — 10 worlds (id, display_name, order 1-10,
playable, campaign_span, main_asset, parts[5]). Worlds 1-5 `playable:true`
route onto the existing 50 campaign levels; worlds 6-10 `playable:false` →
COMING SOON, every node locked, no routing, no invented levels.

**New scripts (concerns separated):**
- `scripts/world/world_catalog.gd` (`WorldCatalog`, static) — WORLD DATA +
  progression glue. `part_index(n) = (n-1) % 5`, `zigzag_side(n)`,
  `campaign_level_id(world, localN)` (delegates to `IslandModel` /
  `Progress` — no new save state), `world_state` / `node_state`.
- `scripts/world/infinite_scroll_model.gd` (`InfiniteScrollModel`, pure
  RefCounted) — SCROLL/RECYCLING math, no scene tree. `layout(offset, h)`
  returns ≤ `pool_size` `{index,y}` rows; min-clamp at level 1, no max
  (logically infinite).
- `scripts/ui/sea_clip_background.gd` (`SeaClipBackground`) — the ONE shared
  fixed looping video, `KEEP_ASPECT_COVERED` for portrait, headless/asset-
  missing → deep-sea gradient fallback. app.gd owns one on its own
  CanvasLayer (layer 8) behind both island screens.
- `scripts/ui/island_level_node.gd` (`IslandLevelNode`) — one pooled visual:
  supplied part PNG (aspect-fit, never stretched/merged) + the shared
  `level_board.png` child + dynamic `Label` number (world-local, constant
  board size for 1/10/100/1000) + locked/current/completed overlay.
- `scripts/ui/infinite_level_scroller.gd` (`InfiniteLevelScroller`) — VISUAL
  + INPUT. Fixed pool of `POOL_SIZE = 9` nodes, never grows; drag + wheel +
  inertia; `_refresh_pool()` re-assigns pooled nodes from the model plan
  each frame (recycle = new number + cycled part + new x/y + new state).
- `scripts/ui/main_island_screen.gd` (`MainIslandScreen`) — 10 world cards in
  a `KineticScrollView`, tap playable → `world_selected`, 6-10 show
  COMING SOON.
- `scripts/ui/internal_level_map.gd` (`InternalLevelMap`) — screen wrapper:
  back button + world title + COMING SOON banner around one reused
  `InfiniteLevelScroller`.
- `scripts/ui/kinetic_scroll_view.gd` (`KineticScrollView`) — reusable
  inertial ScrollContainer (extracted from level_map.gd's private class).

**app.gd:** `_map: LevelMap` replaced by `_islands` + `_worldmap` +
`_sea_clip` (+ `_active_world_id`). `_on_menu_play_pressed` → islands;
`_on_world_selected` → internal map; `_on_worldmap_back` → islands;
`_on_islands_back` (== `_on_home_pressed`) → menu + stop video; `_go_to_map`
(in-level "Quit to Map" / no-next) → the internal map of the level's own
world; `_go_to_level` unchanged downstream. `level_map.gd` kept as a
compiling but now-unreferenced class (no test imports it).

**Device-pass fixes (on OPPO CPH2707):**
- A fling that STARTS on an island node was being read as a level tap
  (child Button consumed the drag, scroller got no cancel). Fixed: nodes
  are now passive Controls (`IslandLevelNode extends Control`, mouse_filter
  IGNORE); `InfiniteLevelScroller` owns all touch, distinguishes drag from
  tap via an 18 px slop, and hit-tests pooled nodes on a settled tap only.
- The 10-world list would not scroll on device (world cards ate the drag;
  a `ScrollContainer` + deadzone still didn't respond to `adb input swipe`).
  `MainIslandScreen` rewritten to the same hand-rolled drag/inertia
  scroller + passive cards + tap hit-test (dropped `KineticScrollView`).
- Locked nodes now keep their (dimmed) level number + a small corner
  padlock badge instead of a blank board.

**Tests:** new `tests/test_world_system.gd` (registered) — 33 cases over
the 14 required points + drag-≠-tap on both screens + far-scroll to L517
with the pool staying == 9. `test_runner` **2780 / 2780 pass** (+442).
`smoke_main_e2e` + `smoke_level_map` rewritten for the new flow and PASS
(incl. bounded-pool + worlds-6-10 assertions); `smoke_overhaul_stages`
(11 stages), `smoke_all_levels` (0), `smoke_shop_flow`,
`smoke_combat_anim`, `smoke_boss_dual_win`, `smoke_audio_chain` all PASS.

**APK re-exported** `build/war-of-love-debug.apk` (exit 0, signed+verified,
~456 MB — up from ~420, the 60 lossless island PNGs + the .ogv), installed
on `3C15CB00ABS00000`.

**On-device acceptance — PASS.** Verified full flow: PLAY → 10 main
islands over the looping SEA CLIP video (vertical scroll through all 10,
worlds 6-10 show COMING SOON) → tap Evergreen → internal map, SEA CLIP
fixed behind, 5 part templates → scroll → parts cycle (L6=part1, L7=part2,
…) + zig-zag L/R + wooden board + dynamic number on each → short drag
scrolls without routing → tap Level 3 → routes into real Level 3 gameplay
→ Pause → Quit to Map returns to Evergreen's own internal map (SEA CLIP
resumes) → Back → world selection (single video instance). Tapping a
COMING SOON world opens its internal map with the COMING SOON banner and
all-locked nodes. Screenshots `build/isl_*.png`.

**UNCOMMITTED — not committed, not pushed; the 2026-09-07 gameplay-overhaul
+ top-bar work is untouched and still in the tree.**

## CHECKPOINT — 2026-09-07 · GAMEPLAY DEPTH + DIFFICULTY + VARIETY overhaul (UNCOMMITTED)

Big gameplay pass (NOT UI). All in the working tree, nothing committed.

**1. Escort special-object mechanic ("Love Crystal" / `relic`).** New real board
entity: `CellData.special_id` (+`has_special`/`has_movable_content`/`clear_special`);
`BoardModel.set_special`/`special_positions`; `apply_gravity` now carries a
special down its column and DELIVERS it (removes it, emits a `{delivered}`
move entry) the moment it reaches the bottom row; `generate`/`refill` skip
special cells; connections route around it (`is_selectable` false).
`ChainResolver.MoveResult` gains `specials_delivered` / `specials_moved`
(`_collect_specials` after all 3 gravity calls). New objective type
`deliver` (`ObjectiveTracker.apply_move` 5th arg `specials_delivered`).
`LevelConfig.specials` + `env`. `PieceView._draw_special` (rose glow +
`eco_reward_crystal` + bob); `BoardView` seats specials in `setup`, ghosts
special moves, and plays `_animate_special_delivery` ("SAVED!" + drop-out +
`special_deliver` sfx). `app.gd` feeds `result.specials_delivered.size()`
to the tracker.

**2. Minor-villain HEALTH BAR removed.** `CombatDirector` no longer has
`boss_hp`/`boss_hp_max`/`_spent_boss_attack`; `feed_move` no longer touches
HP or emits `boss_damaged/defeated/attacked`. `is_boss` now means "chapter
finale" (every 10th) — drives the villain-defeat presentation + boss music,
nothing else. `app.gd`: no boss signal connects, no `_hud.begin_boss`,
`_update_boss_pressure` + `_check_boss_win_or_flourish` + `_on_boss_defeated`
+ `_on_boss_attacked` DELETED, replaced by `_win_finale_stage()` (defeat
flourish -> `_on_level_won`), reached from the normal objectives-complete
path. `hud.begin_boss/set_boss_hp` are no-ops; the `BossBar` node stays but
is never shown. `EnemyModel.boss_hp`/`base_hp` removed. Villain identity /
per-island persistence unchanged (`enemy_for_stage`).

**3. Campaign data overhaul (`tools/level_gen/generate_levels.py` ->
`data/levels.json`, regenerated).** Objective LEAD-type now: clear_color 14,
break_obstacles 11, reach_score 10, deliver 9, create_powers 6 (was ~90%
clear_color-led). Escort recurs on 12 stages (8, 14, 18, 24, 28, 30, 34, 38,
40, 44, 48, 50), 1 -> 2 -> 3 crystals. Every level carries `env` = its
island theme (`env_floating_islands` / `_crystal_formations` /
`_large_structures` / `_clouds_mists` / `_aurora_energy_bands`). Blocker
curriculum kept (ice fam stage 5 -> lock 9 -> stone 16 -> timebomb 31).
Tutorial 1-3 = one goal, no blockers. Moves 30 -> 24 (floor 23, never a
starve). Difficulty from objective count / target magnitude / blocker
density+hp+layering / escort count — not move-starvation. New `_validate`
invariants: deliver target <= crystals, crystal in upper band on a clear
column, clear_color leads <= 55% campaign-wide, all 5 objective types
present, >= 8 escort stages.

**4. Backgrounds now per-island.** `Backdrop.set_scene_for_level(id, env_override)`
prefers the level's `env`, then `IslandModel.island_theme((id-1)/10)`, then
the old band fallback. `app.gd` passes `_current_level.env`.

**5. Gameplay SFX (`data/sfx.json` + `board_view.gd` + `app.gd`).** `select`
now fires only at connection MILESTONES (n>=3, odd) with a rising pitch —
no more per-cell tick. `match`/`blast`/`combo_ding`/`chain_step`/`power_*`/
`shuffle`/`level_complete` retuned toward a warmer crystalline palette (bell
partials + shimmer tails, lower per-wave volume). New ids `blocker_break`
(family-flavoured, one per move), `objective_progress` (one soft chime when
a non-score goal ticks up), `special_deliver`. Music untouched.

**Tests:** new `test_special_object.gd` + `test_gameplay_progression.gd`
(registered in `test_runner.gd`); `test_combat_system` / `test_enemy_model`
boss-HP tests rewritten; `smoke_boss_dual_win` -> "finale, no HP bar";
`smoke_combat_anim` / `smoke_shop_flow` reframed from boss-HP to
score/state invariance. `board_view.boss_obstruct_random_cell` kept as dead
but harmless helper. New non-CI `smoke_overhaul_stages.gd` boots the real
game through the 11 representative stages (1,3,5,10,11,20,21,30,40,49,50).

**Run status:** `test_runner` **2338/2338 pass** (was 1853; +485 from the
two new test files). All smokes pass — `smoke_all_levels` (0 failures with
the new data incl. escort), `smoke_main_e2e`, `smoke_shop_flow`,
`smoke_combat_anim`, `smoke_boss_dual_win` (FINALE NO HP BAR),
`smoke_audio_chain`, `smoke_level_map` (still prints its **pre-existing**
bare-`-s` `Audio`-autoload compile noise, then PASSES — unchanged from
`c847bc6`), `smoke_overhaul_stages` (**PASSED, 11 stages**: every stage
loads live, objectives wired, finales show NO HP bar / no `boss_hp`,
backdrop follows the island, escort crystals seated on L30/40/50, moves
resolve). **APK re-exported** `build/war-of-love-debug.apk` (exit 0, signed,
~420 MB). **Physical-device pass PENDING** — the OPPO test device
(`3C15CB00ABS00000`) disconnected mid-session and did not come back; the
APK is ready to sideload and the 11-stage headless smoke is the stand-in.

## CHECKPOINT — 2026-09-07 · gameplay TOP SECTION full rebuild (UNCOMMITTED)

Replaced (not patched) the gameplay top section against a NEW asset package
`Downloads/New Assets/` + `Gameplay Screen Reference.png` +
`Goal Parts/goal part instructions..txt`.

- **New assets** copied byte-identical (MD5-verified, sources untouched) into
  `game/assets/topbar/`: `pause_button` `settings_icon` `cart_icon`
  `add_button` `level_badge` `moves_badge` `score_badge` `fever_bar`
  `fever_crown` `goal_left` `goal_right` `goal_top`. Registered as
  `tbn_*` entries under `textures` in `data/ui_atlas.json` (whole PNGs via
  `AssetLibrary.ui_texture`, same graceful-null contract). `test_ui_assets`
  auto-verifies all 12 load → **1866/1866** (was 1854; +12).
- **Goal panel — dynamically constructed per the txt.** `_build_goal_zone()`
  in `hud.gd`: fixed `tbn_goal_left` / `tbn_goal_right` decorative end caps
  (aspect-fit, never stretched) + a **procedural rounded-blue `_goal_mid`
  Panel** (the "reusable rounded blue panel/background" the txt specifies)
  whose width grows with the objective count + `tbn_goal_top` "GOAL" header
  centred above the whole assembly. The middle tucks under the caps' opaque
  gold frame so the join is clean and the gold rail reads continuous. No
  flattening / redraw / full-image stretch. Objective chips rebuilt as
  horizontal blue pills (icon + white count, no progress bar) to match the
  reference.
- **MOVES / SCORE** → new `HUD.StatBadge` class: supplied crown-shield PNG
  aspect-fit + `UiKit.GlyphNum` value on the shield. `LevelBadge` now
  prefers `tbn_level`, drawn bigger, gold number. Row 2 is a plain Control
  positioned by maths in `_layout_topbar()` (one deliberate pass — badges
  taller than the Goal panel, crowns/ribbons overhang, per the reference).
- **FEVER** → `UiKit.FeverBarArt` reworked for `tbn_fever_bar` (FEVER tab +
  end diamonds baked in) aspect-fit to width & bottom-aligned, gold fill
  clipped to the alpha-measured track (x .106–.894, y .363–.869),
  `tbn_fever_crown` riding it near the left.
- Old `topbar_elements` sheet slices (`tb_panel_*`, `tb_emblem_*`,
  `tb_bar_fever`, `tb_goal_*`) no longer used; `tb_d0..tb_d9` gold digit
  glyphs kept (no new number art supplied). No coin-icon / coin-pill art
  supplied → those keep their look. `_tb_art_zone()` deleted.
- **Logic untouched:** `set_score/set_moves/set_coins/set_objectives/`
  `set_fever/set_level_info` signatures unchanged; board / difficulty /
  economy / boosters / save / characters not touched. Only
  `scripts/ui/hud.gd`, `scripts/ui/ui_kit.gd`, `data/ui_atlas.json`,
  `assets/topbar/*` + this doc.
- **Validated:** tests 1866/1866, all 6 smokes pass. APK re-exported
  (`build/war-of-love-debug.apk`, ~420 MB, exit 0), installed on
  `3C15CB00ABS00000`, entered live Level 22 — every element is the supplied
  art undistorted, Goal caps join the middle cleanly, header centred, chips
  inside, FEVER bar+crown match, MOVES/SCORE clear of the Goal panel,
  nothing clipped/overlapping, live values (LEVEL/MOVES/SCORE/coins/
  objectives) all populated from real state, board unchanged. Screenshot
  `build/wol_top_final.png`. **UNCOMMITTED — awaiting review.**

### Correction pass 2026-09-07 (still UNCOMMITTED) — reference-alignment audit

Device-verified pass against `Gameplay Screen Reference.png`:
- **FEVER crown** → rides the START of the meter (overlapping the "FEVER"
  tab's right edge, base on the track bottom rail, top above the gold rail);
  `FeverBarArt._relayout` crown x-frac 0.275, size 0.145·bar.
- **FEVER fill** → insets tightened (x .118, y .41/.16 of the bar rect) so
  it sits strictly inside the dark track — never reaches the gold frame —
  and is drawn under the crown. Draw order frame → fill → crown.
- **Dead band removed** — LEVEL badge box shrunk to 96→100 px but drawn
  2.15× oversize (reads as large as MOVES/SCORE, interleaves with row 2 like
  the reference); `_top_col` separation 4, `fever_gap` 4, row 2 reserves
  only 0.82·bh, `_fever_wrap` +6 headroom, `shield_cy` 0.52·bh. GOAL panel
  now sits directly under the LEVEL badge with the header touching it.
- **GOAL middle** now full cap-height at `goal_top` (was 0.94·, offset) so
  the caps and the procedural blue middle are flush → one continuous gold
  rail. Chips nudged up (0.52·cap_h). Mid tucks 24 % under each cap.
- **Power meters** (`power_meters.gd`) — no art supplied for these; polished
  presentation only: near-opaque dark rounded-pill tracks + drop shadow +
  lit rim so they read over the starfield, rounded-square tinted icon chip
  at each left end, fill inset 3.5 px so it never reaches the pill edge,
  height 34→46, gap 14, a 6 px lead-in spacer, and `playfield_top()` +40
  (was +14) so the row clears the board's gold frame.
- Tests 1866/1866, `smoke_main_e2e` + `smoke_combat_anim` pass, APK
  re-exported + installed, live Level 22 screenshot `build/wol_top_FINAL.png`
  — matches the reference. Files touched this pass: `scripts/ui/hud.gd`,
  `scripts/ui/ui_kit.gd`, `scripts/ui/power_meters.gd`, this doc.
  **UNCOMMITTED.**

## CHECKPOINT — 2026-09-06 · "new update" asset pass (UNCOMMITTED)

New package `Downloads/assets/ui elements/new update/`: `Home Screen Sample.png`
(home reference), `source (1).mp4` (560×752 green-screen dancing couple,
24fps/4s), `game panel topbar refrence.png` (gameplay top-bar reference),
`Gameplay Top Bar UI Elements.png` (element sheet). All copied byte-identical
into `game/assets/` (MD5-verified); sources untouched.

**Home Screen — DONE, device-verified.**
- `assets/home/dancers_source.mp4` → chroma-keyed offline (ramp key + hard
  de-spill + largest-blob) into `assets/home/dancers_sheet.png` (36-frame
  6×6 RGBA sheet). Godot 4 has no alpha video, so this is the sanctioned
  keyed-sheet route (like `tools/keyed_sprites/`). mp4 kept as the source.
- New `scripts/ui/dancers_anim.gd` (`class_name DancersAnim`): flips frames
  at 9fps, loops, `play()`/`stop()` on Home visibility (`visibility_changed`
  + `refresh()`). `main_menu.gd` creates it, positions it in
  `_apply_safe_area()` centred on the dais (`vp.y*0.775`, `vp.y*0.185` tall)
  — feet on the dais, head/cape/hair never clip, never touches edges.
- Utility trio bumped ~12% (`third_w … * 1.12`), still one row. PLAY
  unchanged (already the supplied art).

**Gameplay top bar — supplied art INTEGRATED + wired, needs a polish pass.**
- `ui_atlas.json` + new `topbar_elements` sheet: `tb_btn_pause/cart/gear`,
  `tb_panel_moves`, `tb_panel_goal`, `tb_emblem_score` (crest), `tb_emblem_crown`,
  `tb_bar_fever`, `tb_d0..tb_d9` (gold digit glyphs — gold row only; my first
  cut caught the silver row below and doubled every number, fixed).
- `ui_kit.gd`: `UiKit.GlyphNum` (renders a number from the supplied digit
  slices; duck-types `Label` — `text`, `warn`, accepts `add_theme_color_override`);
  `UiKit.FeverBarArt` (`tb_bar_fever` + `tb_emblem_crown` + gold fill clipped
  to `ratio`; same `ratio`/`active`/`flash`/`mult_text` surface as the old
  `FeverArt`).
- `hud.gd`: `_build_top_bar` reskinned — row1 = pause / coins chip / cart /
  gear (supplied circle art); row2 = MOVES panel + GOAL panel + SCORE crest
  (`_tb_*_zone` Controls, art stretched-aspect, GlyphNum + objective row +
  live star row overlaid, positioned in new `_layout_topbar()`); FEVER =
  `FeverBarArt`. Legacy path kept as `_build_top_bar_legacy` fallback.
  `set_score`/`set_moves`/`set_coins`/`set_objectives`/`set_fever`/
  `set_level_info` all still wired; `_update_score_stars()` lights the crest
  stars from running score vs `level.star_scores` (reflective only —
  StarRating still owns the real award). **Board / boosters / difficulty /
  economy / arena characters untouched.**
- **Still rough (flagged, needs another layout pass):** GOAL objective chips
  are a touch wider than the `tb_panel_goal` art (scale-to-fit added but not
  perfect); the panel's baked crown badge floats over the middle chip;
  vertical rhythm of row1/row2/FEVER is tight; SCORE crest top edge grazes
  the cart button. Home screen is clean; the top bar reads as the reference
  but the alignment isn't final.

**Tests 1846/1846 pass; all 6 smokes pass. APK ~417 MB, installed on
`3C15CB00ABS00000`, home + a live gameplay level screenshotted + eyeballed.
UNCOMMITTED — do not commit/push. This sits on top of the still-uncommitted
Settings/Daily/Inventory pass + Phase D below.**

### Gameplay top bar — polish pass (2026-09-06, still UNCOMMITTED)

Layout-only pass against `game panel topbar refrence.png` (art unchanged):
- **GOAL panel split.** `tb_panel_goal` (wide-aspect, fixed crown badge in
  the centre) can't be stretched to a flexible-width compartment without
  blowing up the badge. Sliced into `tb_goal_body` (blue rounded rect,
  9-patched to any width, nine `[92,0,92,10]`) + `tb_goal_badge` (the
  crown-coin, fixed aspect). `hud.gd` builds the GOAL zone as
  NinePatchRect(body) + badge parked top-centre (`mh*0.36`, `-bh*0.08`
  overhang) + the objective chip row scaled-to-fit in the body at
  `mh*0.62`. Chips now sit fully inside the panel, clear of the badge,
  evenly spaced.
- **One MOVES | GOAL | SCORE row**, all three zones the same height `mh`
  (`inner*0.128`, 110–168 px), same vertical centre. `moves_w = mh*1.42`,
  `score_w = mh*1.12`, GOAL takes the flexible middle; row separation 18.
- **SCORE crest ↔ Cart gap.** Crest zone is exactly `mh` (no upward
  overflow) and `_top_col` separation is 28, so the crest top clears the
  Cart button.
- **FEVER breathing room.** Dedicated 16 px spacer between row 2 and
  `_fever_wrap`; `_fever_wrap` height set to the bar-art aspect
  (`inner/9.2`). `FeverBarArt` crown emblem shrunk to `size.y*1.35`,
  overhang `-cw*0.06` (was overlapping MOVES).
- Digit slices `tb_d0..9` re-cut to the **gold row only** (first cut caught
  the silver row underneath and every number rendered doubled — fixed).
  `tb_bar_plain` / `tb_bar_gem` / silver digits / label chips: still unused
  (not in the reference composition — left out per your instruction).
- Untouched: board, moves/score/objective/fever/star/economy/booster logic,
  save, nav. `set_*` HUD setters unchanged; `GlyphNum` duck-types `Label`.

**Tests 1854/1854 pass; all 6 smokes pass. APK re-exported (~417 MB),
installed on `3C15CB00ABS00000`; entered a live level, top bar
screenshotted + eyeballed against the reference — MOVES/GOAL/SCORE aligned,
chips inside their panel, badge clear of chips, SCORE clear of Cart, FEVER
separated, nothing clipped, live values update, board unchanged. STILL
UNCOMMITTED.**

## CHECKPOINT — 2026-09-06 (UI asset integration pass 1, UNCOMMITTED)

Integrated the artist-supplied custom UI artwork for **Settings, Daily
Rewards and Inventory** (user brief: "my supplied UI artwork is the source
of truth — use it exactly, don't recreate it", panels must fill ~full
device width with ~10px side margins). **This is on top of the still-
uncommitted Phase D combat-presentation work below.** Nothing committed or
pushed.

**Source art:** `C:\Users\Administrator\Downloads\assets\ui elements\` — 8
PNGs. Copied byte-identical (MD5-verified) into `game/assets/ui_kit/`
(`settings_elements.png`, `daily_rewards_elements.png`, `btn_settings.png`,
`btn_inventory.png`, `btn_daily_reward.png`). Source files untouched. The 2
element sheets are sliced — never cut on disk — via `AtlasTexture`
sub-rects declared in the new **`game/data/ui_atlas.json`** (33 regions;
bounds derived from the sheets' alpha channels + gap analysis, verified on
magenta-bg montages). `Play Button.png` + the two "reference" mockups are
layout guides only, not used.

**New infra:**
- `AssetLibrary.ui_slice(id)` → cached `AtlasTexture` (filter_clip on),
  `ui_texture(id)` → whole button PNG, `ui_safe(id)` → frame content-inset
  fractions, `ui_bleed(id)` → the slice's transparent-margin fraction (so
  the *visible* gold border lands at ~10px, not the art's bounding box),
  `ui_aspect(id)`, `ui_nine(id)`.
- `UiKit.AssetFramePanel` — full-screen dialog shell on a supplied frame
  slice: sized to `viewport.x − 20` (÷ (1−2·bleed)), aspect-locked,
  vertically centred, `set_banner()` straddles the top edge,
  `set_close_x()` parks the ✕ fully inside the top-right, `content()` is a
  MarginContainer inset to the frame's safe area + `extra_pad`. A layout
  pass scans the `ui_aspect_fit` group and sizes each tagged child to the
  interior width × its art aspect (AspectRatioContainer can't do this in a
  VBox).
- `UiKit.AssetToggle` (ON/OFF switch slices — same API as `ToggleSwitch`:
  `toggled_value`, `set_state`), `UiKit.AssetSlider` (track-bg + green
  fill via `NinePatchRect` + knob slice — same API as `VolumeSlider`:
  `value_changed_by_user`), `asset_button` / `asset_button_fw` /
  `asset_rect` / `asset_rect_fw`. Every one degrades to the previous
  procedural widget if its slice is missing.

**Screens rebuilt (functionality + signals unchanged):**
- **`settings_panel.gd`** — supplied frame, SETTINGS banner (baked text),
  red ✕, 3 rows = supplied icon badge + live label (unchanged) + supplied
  ON/OFF toggle + supplied volume slider (Music/SFX), gold ornament
  dividers, 3 supplied purple link pills (baked text), supplied green
  CLOSE. `GoldFramePanel` (the small centred card — the "too small" bug)
  removed.
- **`daily_rewards.gd`** — supplied frame, DAILY REWARDS ribbon, red ✕,
  7 day tiles (baked "DAY N") + reward icon + value pill (baked number,
  100/150/250/400/600 line up 1:1 with `DailyRewards.TABLE`; days 3 & 5 =
  BOOST pill) + supplied green ✓ on claimed days, supplied green CLAIM.
  Status line stays live text (the supplied "come back" bar bakes a fixed
  "Day 5"). Streak/grant logic untouched.
- **`inventory_screen.gd`** — no Inventory panel art was supplied, so per
  the user's decision it reuses the Settings frame slice as its shell +
  the supplied ✕; tabs / scroll list / item cards unchanged.
- **`main_menu.gd`** — the 3 utility buttons are now the supplied wide
  banner PNGs (`btn_daily_reward` / `btn_inventory` / `btn_settings`),
  **stacked full-width under PLAY** (they're ~3:1 — can't sit
  side-by-side), aspect-locked. PLAY button + in-level HUD gear unchanged
  (no compact-gear asset supplied).

**Verification:**
- Unit **1759/1759 pass** (+188; new `game/tests/test_ui_assets.gd` —
  every atlas region resolves + lies inside its sheet + filter_clip set,
  frame safe-areas sane, slider nine-patch horizontal-only, pill/reward-
  day mapping matches `DailyRewards.TABLE`, missing-region → null).
  Registered in `test_runner.gd`.
- All 6 smokes pass (`smoke_level_map` still prints its **pre-existing**
  bare-`-s` `Audio`-autoload compile warning — unchanged from clean
  `c847bc6`, still "PASSED").
- APK re-exported (`build/war-of-love-debug.apk`, ~407 MB — up from
  ~303 MB; **the lossless import of the 5 UI PNGs is the cost**, flagged
  in the feasibility report) and installed on device `3C15CB00ABS00000`.
  Screenshotted + eyeballed all 3 panels + the menu: panels fill ~full
  width (~10–12 px visible border each side), aspect-locked/undistorted,
  top+bottom borders + all corner scrolls + mid-edge gems visible, ✕
  fully on-screen and **tappable** (verified: Daily ✕ closed the screen),
  nothing clipped, no overlaps.

**Known minor polish (not blocking, "keep layout" honoured):** Daily tile
rows 1 (4 tiles) vs 2 (3 tiles) differ slightly in tile size (different
source-art aspect); DAY 3's BOOST pill slightly overflows its small tile;
large empty area below content on Daily/Settings (spacer); row icons a
touch small. All cosmetic.

**Still needs clarification (reported, not guessed):** (1) no Inventory
panel/elements sheet was supplied — only the button; currently reusing the
Settings frame. (2) The `Settings Panel UI Elements` full-row images and
the `Daily Rewards` "come back" bar bake fixed text/state and are used as
layout reference only (per your confirmation). (3) The crossed-swords
reward icon has the green ✓ composited over it in the source → not cleanly
separable → omitted, day 3 uses the crystal icon.

**Next:** await review of these 3 screens on device; then remaining
screens (HUD, booster shop, map, popups) per the same rules, or an
Inventory panel sheet if you supply one. Do NOT commit/push until you
approve.

### Correction pass — 2026-09-06 (still UNCOMMITTED)

User feedback: the reference IMAGES (`settings panel reference.png`,
`Daily Reward Panel Reference.png`) are the source of truth for
placement/size/spacing; the element PNGs are the source of truth for
artwork. Corrections made:

- **Home screen** — PLAY is now the exact supplied `Play Button.png`
  (`assets/ui_kit/btn_play.png`, green banner + Jinn peeking), used whole,
  aspect-locked. The three utility buttons are now **side-by-side in ONE
  row** under PLAY (`main_menu.gd` `sub` HBox), each ~⅓ column width
  (`_apply_safe_area` sizes PLAY full-width, the trio at `(btn_w-24)/3`).
- **Daily Rewards** — `DayTile._relayout()` reproportioned from
  `Daily Reward Panel Reference.png` (icon ~0.50w centred, value pill
  ~0.72w at ~0.78h, ✓ tucked bottom-right). **Fixed the BOOST-pill
  overflow**: `UiKit.asset_rect()` floors size at native texture width, so
  the tile now clears `_pill.custom_minimum_size` before resizing it —
  cards no longer collide. Both calendar rows now use the SAME card size
  via `UiKit.tag_aspect_fit(tile, 0.66, 0.205)` + the panel's aspect-fit
  layout pass. The grid+status+CLAIM block is vertically centred between
  two equal expanding spacers (the `dr_frame` slice is more elongated
  than the mock, so a top-aligned grid left CLAIM stranded).
- **Inventory** — tab row 52→74 px, `_icon_badge` 60→82, cards 170×150→
  210×186, coins label FS_LABEL→FS_HEADING, ✕ 56→78, `set_content_top`
  0.045 so tabs clear the corner scrolls.
- **Settings** — spacing only (as requested): `AssetFramePanel.set_content_top(0.055)`
  + a 14 px lead spacer so the Music row drops clear of the SETTINGS
  header; nothing else touched.
- **✕ button** — `AssetFramePanel.set_close_x()` now parks it at
  `_close_cx_frac = 0.87` of panel width (was hard against the right
  edge), overlapping the top-right corner scroll like both references,
  fully on-screen and tappable (verified: Daily/Inventory ✕ close).
- **Panel width** — unchanged: `AssetFramePanel` sizes to
  `viewport.x − 20` over `(1 − 2·bleed)` so the *visible* gold border sits
  ~10–12 px from each screen edge. New `set_banner()` / `set_close_x()` /
  `set_content_top()` on `AssetFramePanel`; `UiKit.tag_aspect_fit()`
  public helper.

**New file:** `assets/ui_kit/btn_play.png` (MD5-verified copy). Atlas
`ui_atlas.json` gains `ui_btn_play`. **Tests 1760/1760 pass**, all 6
smokes pass. APK re-exported (~408 MB) and installed on device
`3C15CB00ABS00000` (the OEM "App guard" install-scanner
`com.oplus.stdsp` was temporarily disabled to get a clean sideload, then
**re-enabled**). All four screens screenshotted + verified: PLAY art +
one-row trio; Daily cards separated/equal/centred, ✕ inward; Inventory
elements enlarged; Settings Music has top breathing room; panels ~10 px
from both edges; nothing clipped; no sheet artwork bleed; no procedural
recreation.

**Known residual (structural, flagged):** the supplied frame slices'
aspect (~0.66) is more elongated than the reference mocks' panels
(~0.80), so at ~10 px side margins the panels are taller than the mocks
and carry more interior whitespace (Daily/Inventory). Cannot be closed
without squashing the supplied art or shrinking the panel below the
10 px-margin requirement — needs the user's call on which constraint
gives.


## CHECKPOINT — 2026-09-06 (Phase D, uncommitted)

Picked up at PHASE D. Note most of nominal Phase D (persistent non-boss
`EnemyActor`, targeted-booster → Jamie rig mapping) already shipped inside
`7612d76`; this session closed the remaining gaps. **All presentation
only — CombatDirector still owns every number; no gameplay maths touched.**

1. **Instant boosters now drive Jamie.** Shuffle and +5 Moves previously
   triggered zero character animation. New lightweight actions in
   `data/jamie_actions.json` — `gesture_shuffle` (Jamie sweeps the
   battlefield: a wide cool-tinted `vfx_shockwave_ring` expanding out of
   him via new `JamieRig._battlefield_sweep()`; no lunge/projectile/enemy
   hit) and `brace` (Jamie squares up for the extra push; Jasmine →
   `cheering`). `JamieRig._on_phase` short-circuits both their windup and
   strike phases to a self-only flourish so nothing spawns over the villain.
2. **No more double swing after a booster.** New `app.gd`
   `_booster_anim_this_move` guard: `_on_booster_committed` (targeted) and
   the instant-booster branch set it; `_on_jamie_attack` then skips the
   generic follow-up `attack_sword`; `_on_move_resolved` clears it at the
   top of every real match.
3. **Non-boss villain retreats on stage clear.** New
   `EnemyActor.play_retreat()` (recoil → fade-and-slide off its own side,
   lighter than `play_defeat()`, marks the actor defeated so a late hit
   no-ops). `app.gd::_on_level_won` calls it for non-boss wins; boss
   stages keep their existing `play_defeat()` from `_on_boss_defeated`.

**Tests: 1571/1571 unit pass** (+20; new checks in `tests/test_jamie_actions.gd`
— new actions exist, carry no offence payload, `gesture_shuffle` emits no
enemy_reaction at all, `play_retreat` is idempotent + no-ops later hits).
All 6 smokes pass (`smoke_combat_anim` re-verifies rig-only = zero damage).
Pre-existing `smoke_level_map` bare-`-s` `Audio` autoload compile warning
is unchanged (present at clean `c847bc6`, still prints PASSED) — not a
regression.

**Files:** `game/data/jamie_actions.json`, `game/scripts/app.gd`,
`game/scripts/character/jamie_rig.gd`, `game/scripts/character/enemy_actor.gd`,
`game/tests/test_jamie_actions.gd`, this doc. **Uncommitted, no APK rebuilt** —
needs a device pass on Jamie's shuffle sweep / +moves brace / minor-villain
retreat before commit. Next: PHASE E (enemy attack/hit/defeat depth).

## END-OF-DAY CHECKPOINT — 2026-09-05

Today's session picked up the Phase C work frozen at the end of
2026-09-04 (below) and shipped three things, all bundled into the single
commit `7612d76` (git history for this branch had been uncommitted since
`ca9ac2a`, so this one commit carries everything from Phase C through
today's UI pass):

1. **Asset/intro/audio/character/cinematic polish** — the full Phase C
   work described below (poster, opening cinematic, villain art fixes,
   Jasmine dynamic poses, real music tracks, the two real device-only
   bugs found and fixed).
2. **Gameplay depth & difficulty overhaul** — objective tracker (4 types),
   new obstacle families, power-combo ladder (`power_combos.json`), boss
   dual-win-condition + periodic boss-pressure cadence, data-driven
   level/enemy generation. NOT via fewer moves/more HP/random unfairness.
3. **Complete UI/UX polish pass** (today's main focus) — design-system
   upgrades in `UiKit` (new `ToggleSwitch`, `VolumeSlider`, consolidated
   `show_toast()`, tab-selected button kind, `GoldFramePanel.set_bg_color()`)
   applied across Settings, Daily Rewards, Inventory, Booster Shop, HUD,
   boss bar, story dialogue box. **Settings and Daily Rewards were
   rebuilt from scratch to match user-supplied reference screenshots**
   (`C:\Users\Administrator\Downloads\ref\settings.png` and
   `daily reward screen.png`) — violet gold-frame panel, solid circle
   icon badges, green volume sliders with ON/OFF-labelled toggles, a
   pointed-tail ribbon banner title for Daily Rewards. Main menu
   (bigger currency-chip icons, decluttered top bar, logo dropped) and
   level-map top bar (lighter overlay, bigger gear/chevron) were also
   tuned per direct live feedback. **Visual/UX only — no gameplay
   mechanics changed in this pass**, confirmed by keeping all prior
   gameplay tests green throughout.

**Verification:** 1551/1551 unit tests pass throughout every iteration.
APK rebuilt and reinstalled on device `3C15CB00ABS00000` repeatedly;
screenshotted and visually confirmed: main menu, level map, Settings
(new design), Daily Rewards (new design), Inventory (4 tabs), booster
tray zero-count shortcut (code/smoke-test verified; live tap timing was
imprecise but not blocking), a full level playthrough, and the
LEVEL COMPLETE panel (new gold-frame + exit animation).

**Shipped:** committed (`7612d76`), pushed to `origin/backup_asset_integration_2026-09-02`,
PR #1 opened against `main`. Nothing left uncommitted (working tree
clean except a harmless local `tools/keyed_sprites/__pycache__/`).

**For tomorrow:** PR #1 is open but not merged/reviewed. Booster-shop
zero-count tap shortcut still wants one clean live on-device tap to
visually confirm (logic + smoke test already pass). Otherwise pick up
at PHASE D below (booster → Jamie physical action polish + non-boss
enemy actor), unless the user wants to merge PR #1 / start a new task
first.

---

# Resume point — 2026-09-04  ·  WAR OF LOVE  ·  GAMEPLAY OVERHAUL

**Latest commit: `c08b8ec`**  ·  branch `backup_asset_integration_2026-09-02`
·  **NOT pushed** (do not push without an explicit ask).

## END-OF-DAY CHECKPOINT — 2026-09-04 (Phase C, session frozen for review)

**1. Completed today (Phase C, all uncommitted):**
- New War of Love poster (`WAR_OF_LOVE_SPLASH_SCREEN_9x16.png`) copied
  byte-identical (MD5-verified) into `game/assets/branding/splash.png`;
  original source in Downloads left untouched. Stretch mode fixed
  (`COVERED`→`CENTERED`) so it letterboxes cleanly with no crop/distortion
  on devices taller than 9:16. Loading indicator confirmed still a
  separate runtime layer, not baked into the poster.
- Opening cinematic rebuilt in `StoryScene` (flash/shake/particle-burst/
  bg-zoom+swap primitives) driving a rewritten 7-scene `opening` beat in
  `data/story.json`: peace → Jinn's arrival → Jasmine's fear → capture
  (new `captured` pose) → Jinn's taunt/escape → Jamie's shock → his promise.
- Jasmine dynamic emotion states/poses, Jinn story integration, minor
  villain (e.g. Toxic Slime) presentation, combat/booster visuals, and the
  Need More Moves modal clipping fix — all carried from the prior round and
  re-verified working on-device today.
- **Two real, previously-unknown bugs found and fixed** by inspecting live
  device screenshots (not just logs):
  1. `StoryScene._track_size()` was called before its children existed →
     dialogue box/SKIP button pinned top-left on every real device forever
     (this was the true cause of the old "harmless" boot error). Fixed by
     moving the call + `size_changed` connect to the end of `_ready()`.
  2. Minor-enemy portraits showed a garbled "10 MIN…" text fragment — a
     mirrored sliver of the enemy sheet's title banner bleeding into the
     crop. Fixed in `enemy_model.gd::enemy_face()` by moving the crop's y0
     past the measured banner extent (`h*0.065`).

**2. Current APK:**
`build/war-of-love-debug.apk` — 318,006,500 bytes (~303 MB), built from
the current uncommitted working tree, installed on device
`3C15CB00ABS00000` via `adb install -r`, launched successfully.

**3. Current Git HEAD:** `ca9ac2a` (Phase B commit). Phase A = `01bdb4d`.
Working tree has Phase C changes on top, **uncommitted**.

**4. Phase C status:** **UNCOMMITTED, NOT PUSHED.** ~15 modified files +
~20 new/untracked files (incl. `.uid`/`.import` sidecars) sitting in the
working tree exactly as built/tested. `git status --porcelain` confirms
HEAD has not moved. Frozen as-is per instruction — no further changes
made after this checkpoint note.

**5. Tests:** unit **1436/1436 pass**, 0 fail. All **6 smoke tests pass**
(`smoke_combat_anim`, `smoke_shop_flow`, `smoke_main_e2e`,
`smoke_level_map`, `smoke_all_levels`, `smoke_audio_chain`).

**6. Physical-device verification:** confirmed via multiple real
screenshots on the reconnected device — poster complete/letterboxed,
splash→menu transition clean, opening cinematic dialogue correctly
positioned and readable, gameplay arena clean (no checkerboard, no
garbled text over Toxic Slime), steady 58–60 FPS, 0 script errors in
logcat this session.

**7. Remaining for tomorrow:** continue Phase C systematically from this
checkpoint — the remaining items from the 12-priority list not yet fully
closed out (combat targeting polish, further booster identity/sound
passes, dialogue pass beyond the opening beat, any outstanding items from
the 32-item redesign brief not yet covered by the 12 priorities). Do not
start Phase D. Do not commit/push until the user gives explicit physical
approval of this exact frozen build.

## Gameplay difficulty/combat/booster/inventory overhaul — phased

Big brief: make the campaign a polished, *challenging* match-3 rescue
adventure (live character combat, in-level booster shop + extra moves,
Jamie attack animations, enemy/boss behaviour, Jasmine/Jinn presence,
equipment that affects gameplay, economy balance). Implemented in phases
A–J; **do not jump ahead — each phase must be test-stable first.**

### PHASE A — difficulty + objective data + move system  ✅ DONE (2026-09-04)
- `tools/level_gen/generate_levels.py` rewritten. New model: **moves are
  generous and only taper gently** (island 1 flat 30; islands 2–5 in a
  29→24 band; bosses 28–32; hard floor **23**, never below). Difficulty is
  carried by **objectives + blockers**, not move-starvation.
- New level-data keys: **`starting_moves`** (canonical; `move_limit` kept as
  an identical alias) and **`difficulty_rank`** (monotonic 1..10). Parsed in
  `LevelConfig.from_dict`.
- Objectives now ramp **single (island 1) → double (islands 2–3) → triple
  (islands 4–5)**, varied across all 4 supported types
  (`clear_color` / `reach_score` / `create_powers` / `break_obstacles` with
  per-obstacle/-power filters). Obstacle fields get denser + mixed each
  island (ice → +lock → +stone → +timebomb, 0→11 obstacles).
- Generator has `_validate()` enforcing fairness invariants (every
  `break_obstacles` target ≤ obstacles actually placed; every `reach_score`
  target ≤ the level's 1-star threshold; move floor; monotonic rank;
  obstacles inside a safe band). New `game/tests/test_level_design.gd`
  (registered in `test_runner.gd`) re-checks all of that against the live
  `data/levels.json`.
- **Tests: 1191/1191 unit pass** (was 894; +297 data checks). `smoke_all_levels`
  0 failures (every board still has valid moves), `smoke_main_e2e` /
  `smoke_level_map` / `smoke_audio_chain` all pass. No APK rebuilt — Phase A
  is data + one generator + tests only, no scene/asset change.
- **Only these files changed:** `tools/level_gen/generate_levels.py`,
  `game/data/levels.json`, `game/scripts/levels/level_config.gd`,
  `game/tests/test_level_design.gd`, `game/tests/test_runner.gd`, this doc.

### PHASE B — in-level booster shop + "Need More Moves?"  ✅ DONE (2026-09-04)
- **Single source of truth kept:** the shop reads/writes the existing
  `Boosters` autoload (the same one the Inventory screen's BOOSTERS tab
  uses) and coins via `Economy` / `SaveService`. No second currency, no
  second inventory, no sync layer.
- **HUD:** new "bag" icon button in the top-bar right cluster
  (`shop_pressed`). Two self-contained overlays owned by the HUD
  (`_booster_shop`, `_moves_prompt`) — instantiated via `load()` + kept
  untyped so `hud.gd` carries **no compile-time dependency** on them
  (they pull in `UiKit`→`HUD`, a typed ref would close a class cycle and
  the whole project stops resolving — this bit me once, hence the note).
- **`scripts/ui/booster_shop.gd`** (`class_name BoosterShop`) — frosted
  glass / gold modal: per-booster icon / name / OWNED x / price / BUY
  (→ in-panel confirm showing name, qty, price, coins, coins-after, or a
  "NOT ENOUGH COINS" state) / USE (owned only → routes into the existing
  `app._on_booster_pressed` pipeline: targeted boosters arm, instant fire).
  Signals `use_requested(id)`, `closed()` (both fire synchronously; only
  the fade is deferred).
- **`scripts/ui/extra_moves_prompt.gd`** (`class_name ExtraMovesPrompt`) —
  "NEED MORE MOVES?" with data-driven tiers, coins + coins-after per tier,
  GIVE UP. Signals `bought(moves)`, `gave_up()`.
- **`scripts/economy/continue_offers.gd`** (`class_name ContinueOffers`) —
  pure logic over new **`data/economy.json`** (`extra_moves_5` +5 / 140¢,
  `extra_moves_10` +10 / 240¢). `GameData.continue_offers`. Prices
  data-driven — no hard-coded costs in UI.
- **`data/boosters.json`** re-tuned so price scales with board impact
  (bomb 90 < lightning 120 < freeze 150 < rainbow 200; shuffle 60).
- **`app.gd`:** `_on_shop_pressed` freezes the board (existing
  `set_input_locked` pause path — no move consumed, no board/objective/
  enemy/boss/meter change), `_on_shop_closed` unfreezes, `_on_shop_use_booster`
  re-enters the booster pipeline (→ `CombatDirector` → Jamie/boss).
  `_offer_more_moves_or_lose()` runs at `moves_left <= 0` **before**
  `_on_level_lost()`; `_on_continue_bought` adds moves to the RUNNING
  level (never re-runs `_start_level`), `_on_continue_declined` →
  the unchanged `_on_level_lost()`. Works on boss stages (Jinn included) —
  boss music state is restored, boss HP untouched.
- **Tests: 1241/1241 unit pass** (+50 over Phase A; new
  `tests/test_shop_continue.gd`, registered). `tests/smoke_shop_flow.gd`
  (new, not in CI) drives the full loop on a **boss stage** + a normal
  stage and asserts board / score / objectives / boss HP all preserved
  across every modal and the level is never reset — **PASSES**.
  `smoke_main_e2e` / `smoke_level_map` / `smoke_all_levels` (0 failures) /
  `smoke_audio_chain` all pass. Only script error anywhere is the
  pre-existing `StoryScene._track_size` nil (item #7 below).
- **Test-run gotcha:** `.godot/` is gitignored, so `class_name` scripts
  added this phase aren't in the class cache on a fresh checkout. Run
  `godot4 --headless --editor --quit --path game` once before
  `test_runner.gd` after adding any new `class_name` (Phase A's test had
  none, so this is new).
- **Files changed:** `data/economy.json`*, `data/boosters.json`,
  `scripts/economy/continue_offers.gd`*, `scripts/ui/booster_shop.gd`*,
  `scripts/ui/extra_moves_prompt.gd`*, `scripts/ui/hud.gd`,
  `scripts/ui/ui_kit.gd` (bag glyph), `scripts/core/game_data.gd`,
  `scripts/app.gd`, `tests/test_shop_continue.gd`*,
  `tests/smoke_shop_flow.gd`*, `tests/test_runner.gd`, this doc.  (* = new)
- **No APK rebuilt** — offered to the user; the on-device checklist in the
  brief needs a physical device.

### PHASE C — real Jamie combat animation system  ✅ CODE DONE (2026-09-04) · device test PENDING
- **Assets:** `assets/story/jamie_actions_ref.png` is a loose mood/reference
  collage (opaque bg) — NOT sliceable. The real source is
  `assets/story/cast_atlas_transparent.png` (AssetLibrary `story_cast_atlas`,
  transparent). It's still a freeform collage, so poses are sliced by
  **explicit normalized regions** in `data/jamie_actions.json` (`poses` /
  `jinn_poses`), the same sanctioned pattern as `islands.json`'s
  `stage_regions`. Source PNGs are never modified (AtlasTexture sub-rects).
  Region rects are best-effort eyeballed and a Phase-J polish candidate.
- **`scripts/character/jamie_action_controller.gd`** (`JamieActionController`,
  pure RefCounted) — deterministic state machine IDLE→WINDUP→STRIKE→RECOVER
  + a bounded action queue (`QUEUE_MAX`, drops oldest on overflow,
  `dropped` counts it). `strike` is the authoritative "hit lands" beat
  (rig reacts to it, never to a tween finishing) so a dropped frame can't
  skip or duplicate a hit. `tick(dt)` crosses multiple phases in one call
  on a lag spike. A `sequence` action (Fever ultimate) emits `strike` once
  per sub-power. It has NO reference to CombatDirector / damage.
- **`scripts/character/jamie_rig.gd`** (`JamieRig`, Control) — renders the
  real Jamie pose art and turns controller phases into visuals only:
  anticipation crouch → lunge/dash toward the enemy anchor → a travelling
  projectile built from the supplied VFX art → impact burst → recover to
  the (unchanged) logical position. Emits `enemy_reaction(kind, pos)` and
  `shake_requested(mag)`. Only `set_process(true)` while an action runs.
- **`Cast`** — `jamie_pose()` / `jinn_pose()` slice `story_cast_atlas` by the
  JSON regions; `Cast.pose(WHO_JAMIE|WHO_JINN, …)` now returns real pose art
  (portrait fallback for unknown names).
- **Wiring (`app.gd`):** `_character` (CharacterView) is repointed from
  Jamie to **Jasmine** (bottom-right, still reacting to the event stream —
  cheer/scared/victory). A new `_jamie_rig` is the combat presence
  (bottom-left). `_on_power_fired` → `_rig_action_for_power()` →
  `_jamie_rig.play()` (fire_sword→attack_sword, lightning_hand→
  attack_lightning, lightning_boots→attack_dash, combos→attack_blast,
  ultimate→fever_ultimate). Plain matches drive `attack_sword` only when
  `damage>=3` and no power fired (keeps ordinary matching snappy).
  `_on_booster_committed` → `_rig_action_for_booster()` (bomb→attack_bomb,
  rainbow→attack_mega_blast, …). Fever activation → `fever_ultimate`.
  `_on_boss_attacked`→`hurt` (+ `boss_taunt()` on the final boss),
  `_on_boss_defeated`→`victory`. `_jamie_rig.enemy_reaction` →
  `_hud.boss_hit(kind)` (boss stages). `shake_requested` → `ScreenShake`.
- **`BossBar`** — `play_hit(kind)` (portrait flinch/knock + bar flash,
  scaled hit/heavy_hit/knockback/stun) and `play_taunt()` (final-boss
  pulse). HP is still set only via `set_hp()` so a reaction can never
  desync the numbers. `HUD.boss_hit()/boss_taunt()` passthroughs.
- **Authoritative-damage invariant:** CombatDirector still owns every
  number; the rig is presentation and reacts to the `strike` beat, not to
  animation completion. `smoke_combat_anim` proves a rig-only action deals
  **zero** damage and that a fired power animates without touching boss HP.
- **Tests: 1303/1303 unit pass** (+62; new `tests/test_jamie_actions.gd`,
  registered — controller phases, no-skip/no-dup strike, lag-spike, queue
  bound, reset, fever 3-strike, Cast slices, rig node). New
  `tests/smoke_combat_anim.gd` (not CI) — **passes**. `smoke_shop_flow` /
  `smoke_main_e2e` / `smoke_level_map` / `smoke_all_levels` (0 failures) /
  `smoke_audio_chain` all re-run and pass.
- **APK:** `build/war-of-love-debug.apk` (built this session).
- **NOT DONE — the brief's §19 on-device test.** Needs a human to sideload
  the APK and eyeball Jamie's sword / lightning / dash / bomb / fever, the
  boss reactions, 60 FPS and logcat. Headless proves the pipeline is
  correct and deterministic; it can't judge how the animation *reads*.
- **Partial within Phase C (deferred to their own phases per §20):** a
  persistent on-screen minor-villain actor for NON-boss stages (only boss
  stages have an enemy actor today — the BossBar); Jinn taunt/attack
  cinematics beyond the portrait pulse; per-pose region polish.
- **Files:** `data/jamie_actions.json`*, `scripts/character/jamie_action_controller.gd`*,
  `scripts/character/jamie_rig.gd`*, `scripts/character/character_view.gd`,
  `scripts/story/cast.gd`, `scripts/ui/boss_bar.gd`, `scripts/ui/hud.gd`,
  `scripts/app.gd`, `tests/test_jamie_actions.gd`*, `tests/smoke_combat_anim.gd`*,
  `tests/test_runner.gd`, this doc.  (* = new)

### PHASE C — VISUAL REWORK after physical device rejection  ✅ (2026-09-04)
The first Phase C build was rejected on-device: Jamie/Jasmine read as tiny
corner stickers, checkerboard artifacts around the characters, no visible
normal-stage enemy, wasted lower screen. Root-caused and fixed, still
uncommitted (waiting on your approval):

- **Root cause of the checkerboard:** `cast_atlas_transparent.png` and
  `enemies_and_bosses.png` are **RGB with no alpha** — a light-grey
  checkerboard is baked into the "empty" pixels despite the filenames.
  Slicing them for poses/enemy always showed that checker on device.
  `jasmine_poses_8.png` has the same problem (unused now).
- **Fix — use the clean art that actually has real transparency:**
  `jamie_portrait.png` / `jasmine_portrait.png` / `jinn_portrait.png` are
  genuine RGBA cut-outs (verified pixel-by-pixel). `Cast.jamie_pose()` /
  `jinn_pose()` now return the clean portrait instead of slicing the
  checkered atlas (`cast_atlas_transparent.png` is no longer read).
  New `tools/keyed_sprites/key_enemies.py` keys the enemy sheet's baked
  checkerboard (two near-white greys, verified colour values) to real
  alpha and writes `assets/story/enemies_keyed.png` — same art, same
  layout, original PNG untouched. `EnemyModel.enemy_face()` slices that.
- **A real combat arena, not corner portraits:** `HUD.ARENA_HEIGHT` (360)
  + `arena_top_y()`/`arena_floor_y()`/`tray_reserve()` carve a dedicated
  band between the board and the tray; `playfield_bottom()` grew so the
  board is fitted above it (board stays visually dominant — verified
  ~57% of screen height on the test device). `app._relayout_arena()`
  stands Jamie (left, ~88% of the band), the villain (right, ~86%,
  bigger on boss stages), and Jasmine (centre, set back, ~66%) on the
  arena floor with real spatial separation, drawn Jasmine → enemy → Jamie
  so Jamie reads on top during a dash.
- **New `EnemyActor`** (`scripts/character/enemy_actor.gd`) — the
  persistent normal-stage villain (`EnemyModel.enemy_for_stage`), replaced
  by that chapter's boss on every 10th stage
  (`EnemyModel.boss_for_stage`/`is_boss_stage`) — same node just swaps
  art, so "the boss takes over the combat presentation" per the brief.
  `play_hit(kind)` (flinch/knock/flash) and `play_defeat()`; HP still only
  ever comes from CombatDirector.
- **`JamieRig` rebuilt** around the one clean portrait: real multi-phase
  transform animation (windup lean+squash → lunge toward the enemy →
  weapon-hand ignites — sword=orange/orb=blue, keyed to `hand` in
  `jamie_actions.json` → projectile → impact → recover), not a portrait
  sliding around. Added an FX cap (`_fx_saturated()`, max 5 concurrent
  transient nodes) after an on-device FPS dip during Fever+rapid combos;
  gameplay-critical signals (`enemy_reaction`, `shake_requested`) still
  always fire even when decorative FX are skipped.
- **`CharacterView.portrait_only`** — Jasmine now blits her clean portrait
  directly (keep-aspect, feet-anchored), no pose-sheet slicing.
- **Two iterations verified live on the connected device**
  (`3C15CB00ABS00000`, adb-installed both times): iteration 1 fixed the
  composition but Jamie's flaming sword clipped the left screen edge and
  the enemy showed a sliver of its baked name label; iteration 2 (current)
  fixes both (`left_x` margin bump, enemy region height trimmed above the
  label bar). Confirmed via `adb screencap` on two different live levels —
  clean transparency, correct scale/position, board/tray untouched, real
  touch input advancing moves/objectives correctly. Idle/light-play FPS
  55–60 (matches pre-Phase-C baseline); a Fever-mode dip to ~35–46 was
  observed and is **pre-existing Fever board-aura cost**, not new from
  this rework (confirmed via a non-Fever idle sample on the same build) —
  noted, not chased further (out of this fix's scope).
- **Tests: 1314/1314 unit pass** (+11 over the first Phase C pass:
  `test_jamie_actions.gd` pose/rig-sizing/enemy-actor checks,
  `test_story_assets.gd` updated for the new `story_enemies_keyed` id and
  the label-safe enemy region). All 6 smokes re-verified green after both
  the redesign and the follow-up tuning.
- **New files:** `data/jamie_actions.json` (rewritten — no more hand-
  estimated pose regions), `scripts/character/enemy_actor.gd`,
  `tools/keyed_sprites/key_enemies.py`,
  `game/assets/story/enemies_keyed.png` (+`.import`).
- **Edited:** `scripts/character/jamie_rig.gd` (rebuilt), `character_view.gd`,
  `scripts/story/cast.gd`, `scripts/story/enemy_model.gd`,
  `scripts/core/asset_library.gd`, `scripts/ui/hud.gd` (arena geometry),
  `scripts/ui/boss_bar.gd` (unrelated `at`/Variant-inference build fix
  from the previous pass, caught this round), `scripts/app.gd` (arena
  wiring), `tests/test_jamie_actions.gd`, `tests/test_story_assets.gd`,
  `tests/test_runner.gd`, `tests/smoke_combat_anim.gd`.
- **Still uncommitted** — waiting on your approval before any commit.

### PHASE C — dynamic staging pass (priorities 1-12 of the 2nd device-rejection brief)  ✅ (2026-09-04)
Deep-inspected `C:\Users\Administrator\Downloads\Game Character and UI UX`
(10/11 files hash-identical to assets already in the repo; the 1 new file
was an old, already-largely-implemented UI wireframe doc — no new pose art
existed beyond what was already catalogued). That inspection found
`jasmine_expressions_ref.png` genuinely alpha-clean with story-critical
poses (scared/crying/captured/rescue-hug/victory) never wired up, and that
`jasmine_poses_8.png` has the SAME baked-checkerboard bug as the enemy
sheet. Implemented:
- **Priority 12 (device bug) FIXED:** `BoosterShop`/`ExtraMovesPrompt`/
  `SettingsPanel` are constructed inside `HUD._ready()` **before** HUD
  itself has a real size (CanvasLayer-parented Controls start at (0,0)) —
  their FULL_RECT anchor offsets baked in against that zero size, then
  double-counted once HUD grew to the real viewport, pushing "NEED MORE
  MOVES?" off the right edge. `HUD._track_size()` now re-tracks all three
  overlays after sizing itself. **Verified on-device**: modal now fully
  centred, no clipping. Regression test added (`test_overlay_children_are_not_double_sized_after_hud_settles`).
- **Priority 2/3 (checkerboard + Jasmine dynamic states):** generalized the
  keying tool (`tools/keyed_sprites/key_checkerboard.py`) and ran it on
  `jasmine_poses_8.png` → `jasmine_poses_8_keyed.png` (measured, not
  guessed, cell regions). Added 6 individually-cropped, individually
  dark-background-composited-and-verified emotion crops from
  `jasmine_expressions_ref.png` (already real alpha, no keying needed):
  scared, worried, crying, captured, rescued, victory. `Cast.jasmine_state()`
  is the new single entry point (`JASMINE_STATE_TABLE`); `JasmineActor`
  (new) renders it and nudges her position toward Jamie on a positive state,
  back on a fearful one.
- **Priorities 1/4 (dynamic staging):** `app.gd` now sets Jasmine's state
  from real signals — level start (captured on the final boss stage,
  scared on other boss stages, determined otherwise), near-fail (worried),
  fever (cheering), Ultimate fired (cheering), boss counter-attack
  (scared), boss defeated (rescued on the final boss, victory otherwise),
  normal level won (cheering), level lost (crying). **Confirmed live on
  device**: watched her pose flip determined → cheering (Fever) → worried
  (near-fail) across one play session, each a genuinely different supplied
  pose, no checkerboard, no clipping.
- **Priority 6:** `EnemyActor` gained a cheap looping idle bob (sprite-only
  tween, killed on defeat) so the villain reads as alive between hits.
- **Priority 7 (targeting):** re-verified — `EnemyActor.configure()`
  returns the torso point, `JamieRig.configure()` aims every projectile/
  impact at it; unchanged, still correct.
- **Priority 9 (booster identity):** Freeze and Rainbow got their own
  `jamie_actions.json` entries (were reusing the generic blast) — Freeze:
  `vfx_ice_burst`, `power_freeze` sfx, `stun` reaction; Rainbow:
  `vfx_rainbow_burst`, `power_rainbow` sfx. Shuffle already had its own
  sfx (`board_view.request_shuffle()` plays `shuffle`) — confirmed
  adequate, left alone.
- **Priority 5 (Jinn/Jasmine story panels) — evaluated, deferred, disclosed
  honestly:** cropped candidate compositions (cage, confrontation, "WE WIN")
  from `story_scenes_transparent.png`; native crop resolution (~250x250px)
  and post-keying edge quality on fine hair detail were below this pass's
  bar for a shipped background. Left `StoryScene` untouched rather than
  ship a soft/blocky panel; the crops are reproducible from the inspection
  notes in this session if a future pass wants to pursue higher-res source
  crops.
- **Tests: 1372/1372 unit pass** (+58: `test_jasmine_actor.gd` new,
  `test_story_assets.gd` extended for the state table + emotion regions +
  registry count 12, `test_shop_continue.gd` +1 overlay-sizing regression).
  All 6 smokes re-verified green.
- **Files:** new `tools/keyed_sprites/key_checkerboard.py`,
  `tools/keyed_sprites/key_jasmine_poses.py`,
  `game/assets/story/jasmine_poses_8_keyed.png`(+`.import`),
  `game/scripts/character/jasmine_actor.gd`,
  `game/tests/test_jasmine_actor.gd`; edited `scripts/story/cast.gd`
  (rewritten state table), `scripts/app.gd` (Jasmine wiring + freeze/
  rainbow mapping), `scripts/ui/hud.gd` (overlay re-track fix),
  `scripts/character/enemy_actor.gd` (idle bob), `data/jamie_actions.json`
  (+attack_freeze, +attack_rainbow), `tests/test_story_assets.gd`,
  `tests/test_shop_continue.gd`, `tests/test_runner.gd`.
- **Verified live on the connected device** (`3C15CB00ABS00000`): clean
  transparency throughout, Jasmine's dynamic poses, booster shop fully
  visible, "NEED MORE MOVES?" fully visible (the reported bug — confirmed
  fixed), steady 57-60 FPS through fever + swipes + modals, 0 script
  errors in logcat.
- **Still uncommitted** — waiting on your approval.

### PHASE C — new poster + opening cinematic + 2 real device-only bugs found & fixed  ✅ (2026-09-04)
- **Poster:** copied `C:\Users\Administrator\Downloads\War of Love\WAR_OF_LOVE_SPLASH_SCREEN_9x16.png`
  (verified MD5-identical after copy; source untouched) into
  `game/assets/branding/splash.png` — the single path both `SplashScreen`
  and Godot's native `boot_splash/image` read. Fixed `SplashScreen`'s
  stretch mode `COVERED`→`CENTERED` so devices taller than 9:16 no longer
  crop the artwork. **Confirmed on device: complete poster, fully
  letterboxed, no crop, no distortion.**
- **Opening cinematic:** extended `StoryScene` with reusable presentation
  primitives — a colour `flash` (+ matching sfx hook), a `shake`, a one-shot
  `particles` burst from existing VFX art, an always-on slow `bg` zoom
  (Ken Burns), and a mid-beat `bg` swap. Rewrote the `opening` beat in
  `data/story.json` to the full 7-scene kidnapping arc (peace → Jinn
  arrives → Jasmine's fear → capture, using her new `captured` pose →
  taunt/escape → Jamie's shock → his promise), ~43s, skippable. Also fixed
  a pre-existing mojibake (corrupted em-dash) bug in the dialogue text.
- **Real bug #1 (found via this verification, not previously known):**
  `StoryScene._track_size()` was called at the very TOP of `_ready()`,
  before `_box`/`_skip`/`_left`/`_right`/`_bg` existed — it crashed/no-op'd
  on that first call (null children) and, since nothing but an actual
  viewport resize event ever re-triggers it (which never fires on a static-
  orientation device), the dialogue box / SKIP button / character slots
  stayed pinned at Godot's default top-left rect on every real device,
  forever. **This is what the long-standing "harmless" boot-log error
  (`Invalid assignment ... 'size' ... Nil` at story_scene.gd) actually was**
  — RESUME's earlier "cosmetic, no functional impact" note was wrong. Fixed
  by moving the initial `_track_size()` call (and the `size_changed`
  connection) to the end of `_ready()`, after every child exists — same
  pattern HUD already uses. **Confirmed on device**: dialogue box now
  correctly bottom-centred and fully readable (screenshotted mid-beat);
  the boot-log error is gone entirely, not just relocated (checked logcat).
- **Real bug #2 (found via this verification):** some enemy crops
  (`EnemyModel.enemy_face()`) picked up a mirrored fragment of the sheet's
  "10 MINI BOSSES (JIN'S SERVANTS)" title banner (y~0.010-0.055 of
  `enemies_keyed.png`), rendered backwards by `EnemyActor`'s left-facing
  horizontal flip — visible on device as garbled "10 MIN" text floating
  above the minor villain. Measured the actual gap between the title and
  the art (starts ~y 0.065) and moved the crop's y0 there. **Confirmed on
  device**: the artifact is gone; verified all 10 enemies crop cleanly via
  a dark-background composite before shipping.
- **Tests: 1436/1436 unit pass** (+64 over the previous pass: new
  `test_story_scene.gd`, opening-beat structure/mojibake checks). All 6
  smokes pass. 0 script errors in logcat this session (previously 1
  recurring, now genuinely fixed).
- **Files:** new `tools/keyed_sprites/key_checkerboard.py` (generalized),
  `key_jasmine_poses.py`, `game/assets/story/jasmine_poses_8_keyed.png`
  (+`.import`), `game/scripts/character/jasmine_actor.gd`,
  `game/tests/{test_jasmine_actor,test_story_scene}.gd`; edited
  `game/assets/branding/splash.png` (new poster), `scripts/ui/splash_screen.gd`,
  `scripts/story/{story_scene,cast,enemy_model}.gd`, `data/story.json`,
  `scripts/app.gd`, `scripts/ui/hud.gd`, `tests/{test_story_assets,test_shop_continue,test_runner}.gd`.
- **Still uncommitted** — waiting on your approval.

### PHASE D (next) — booster → Jamie physical action polish + non-boss enemy actor
Then E: enemy attack/hit/defeat depth · F: boss presentation (+ multi-phase
Jinn) · G: Jasmine/Jinn gameplay presence depth · H: equipment gameplay
effects · I: economy balancing · J: full campaign difficulty + animation
polish pass.

---

## (earlier) End-of-day checkpoint — 2026-09-03

**Was at commit `c08b8ec`**, working tree clean, not pushed.

Commit chain today:
`ac324ca` map perf → `0381efe` story/Cast/EnemyModel foundation →
`dbbcac0` docs → `6c52370` combat/powers/boss/inventory/splash/branding →
`e9c9de0` docs → `c08b8ec` Android app icon + blank-splash fix.

---

## Current state — everything below is DONE, tested, and preserved

| Area | Status |
|---|---|
| Connect-3 core, hex board, powers, ChainResolver, level data, ProgressService | untouched, working |
| **Island campaign map + kinetic scrolling** | working (5 islands stacked, finger drag + inertia, auto-centre on current island) |
| **5 islands × 10 stages = 50** | `IslandModel` (pure view of Progress); sequential unlock unchanged |
| **Jamie / Jasmine / Jinn characters** | `assets/story/` (10 PNGs, sources untouched); `Cast` (portraits + Jasmine 8-pose AtlasTexture slices); real Jamie art in `CharacterView` |
| **Story system + cutscenes** | `Story` autoload + `data/story.json` (opening kidnapping, 5 chapter cards, boss intros, Jinn cameo @30, stage-50 finale, +6 mid-chapter beats); `StoryScene` overlay (tap/auto-advance; auto-skips headless) |
| **Small enemies + boss system** | `EnemyModel` + `data/enemies.json` (10 "Jin's servants", per-island rosters, boss map 10 Poison Beast / 20 Ice Wraith / 30 Dark Knight / 40 Chaos Sorcerer / 50 Jinn, HP scales by chapter) |
| **Match-3 → combat integration** | `CombatDirector` (one per stage, fed by `app._apply_move_result`); matches → Jamie attack energy → boss damage → boss_defeated → win (guarded vs double-fire) |
| **Jamie power meters + powers** | `JamiePowers` (Fire Sword / Blue Lightning Hand / Lightning Boots fill-and-fire, combos, ULTIMATE, levels 1-5 from Inventory); `PowerMeters` HUD strip — **confirmed live on device** |
| **Boss bar** | `BossBar` HUD (portrait ring, name, red HP bar, damage flash, defeat fade; stage 50 = larger gold "final boss") |
| **Inventory system** | `Inventory` autoload + `InventoryScreen` + `data/inventory.json`; POWERS (upgrade w/ coins) / BOOSTERS (buy) / EQUIPMENT (sword-boots-suit slots, boss drops) / ITEMS (Kingdom Shards); SaveService-backed, opened from main menu |
| **War of Love branding** | project + export name "War of Love" v0.6.0 (package id `com.colorclash.game` unchanged); wordmark "WAR OF LOVE" in menu/splash |
| **9:16 splash PNG** | `C:\Users\Administrator\Downloads\War of Love\WAR_OF_LOVE_SPLASH_SCREEN_9x16.png` (1080×1920) + title-only variant; composited from supplied character PNGs; also `game/assets/branding/splash.png` |
| **Android native splash fix** | ROOT CAUSE was `SplashScreen` (Control on a CanvasLayer) never sized to the viewport → poster TextureRect zero-size → blank. Fixed: `SplashScreen._track_size()` sizes self + children; dark ColorRect ground; `boot_splash/show_image=true` + `boot_splash/image` native splash. **Confirmed on device — poster shows on cold launch + relaunch, no blank.** |
| **App icon / adaptive launcher icon** | From supplied `logo.png app icon.png`. `game/icon.png` (512 square), `assets/branding/icon_{fg,bg,mono}.png` (432 adaptive); `export_presets.cfg launcher_icons/*` set. APK packs `res/mipmap-*/icon*.png`. **Confirmed on device — "War of Love" logo shows in the launcher.** |
| **Arabic-fantasy music/audio hooks** | `data/music.json` states `battle`/`boss`/`final_boss`/`story`/`victory`; `data/sfx.json` `sword_attack`/`lightning`/`power_up`/`boss_impact`. All synth placeholders; `Audio.register(id, stream)` is the seam for real files. `app.gd` switches to boss/final_boss music on boss stages. |
| Tests | **896 / 896 unit pass**; 4/4 smoke scripts pass |

---

## Build state
- `build/war-of-love-debug.apk` — **built 2026-09-03 22:56, exit 0, ~309 MB**,
  installed + verified on device `3C15CB00ABS00000` (splash + icon both
  confirmed; game runs at 60 FPS). This APK matches commit `c08b8ec`.
- Older: `build/color-clash-debug.apk` (pre-rename), `build/color-clash-2026-09-02-assets.apk`.

---

## Next pending tasks (NOT started — for tomorrow)
1. **Jamie power animation** — slice the opaque `story_jamie_actions` /
   `story_jinn_actions` sheets into pose AtlasTextures; extend `Cast.pose()`
   for Jamie/Jinn; drive from `CombatDirector.jamie_attack` / `power_fired`.
2. **Dedicated boss intro/defeat screens** (big "vs" card) instead of only
   the `Story` dialogue beats.
3. **Wire Inventory equipment bonuses into real numbers** (currently
   description strings) — feed into `JamiePowers` / `CombatDirector`.
4. **PowerMeters idle visibility** — caption / brighter empty tracks on
   non-boss stages.
5. **Real music & SFX files** — register via `Audio.register()`; 11 music
   slots already defined.
6. **Full on-device boss-fight walkthrough** (stage 10/20/30/40/50) — the
   BossBar + combat signals are unit-tested; a live playthrough not yet done.
7. Pre-existing harmless `SCRIPT ERROR: Invalid assignment ... 'size' ...
   'Nil'` in some smoke/boot logs (predates all this work, no functional
   impact) — trace + silence if time.
8. APK size (~309 MB) — ETC2/ASTC texture compression pass eventually.
9. `user://` save dir changed with the app rename (desktop/editor only;
   device save is per-package-id and unaffected) — nothing to fix, just noted.

## Do NOT (carried over)
- Push to origin.
- Rewrite connect-3 core / hex grid / ChainResolver / level data /
  ProgressService / IslandModel / island map / event stream / Story / Cast /
  EnemyModel / CombatDirector.
- Modify/crop/replace any supplied source PNG (slice via AtlasTexture).
- Rename Jamie/Jasmine/Jinn or redesign their look.
- Add a second save / currency / progression system.
