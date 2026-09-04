# Resume point — 2026-09-04  ·  WAR OF LOVE  ·  GAMEPLAY OVERHAUL

**Latest commit: `c08b8ec`**  ·  branch `backup_asset_integration_2026-09-02`
·  **NOT pushed** (do not push without an explicit ask).

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

### PHASE C (next) — Jamie combat animation event pipeline
Slice `story_jamie_actions` / `story_jinn_actions` into pose AtlasTextures;
extend `Cast.pose()` for Jamie/Jinn; drive Jamie reactions off
`CombatDirector.jamie_attack` / `power_fired` and the booster USE hooks
already wired in Phase B. Then D: booster→Jamie physical actions ·
E: enemy attack/hit/defeat · F: boss presentation (+ multi-phase Jinn) ·
G: Jasmine/Jinn gameplay presence · H: equipment gameplay effects ·
I: economy balancing · J: full campaign difficulty pass.

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
