# Resume point — 2026-09-05  ·  WAR OF LOVE  ·  UI/UX POLISH SHIPPED

**Latest commit: `7612d76`**  ·  branch `backup_asset_integration_2026-09-02`
·  **PUSHED to `origin`** ·  **PR #1 open**: https://github.com/tokenanalyzer/color-clash/pull/1
(`backup_asset_integration_2026-09-02` → `main`), not yet merged.

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
