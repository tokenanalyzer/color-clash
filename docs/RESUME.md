# Resume point — 2026-09-03  ·  "Jamie, Jasmine & Jinn" foundation

Local commits today (NOT pushed). Latest: `0381efe`.
Recent chain: island map (`9875c2c`, `638acdf`, `ac324ca`) → story foundation (`0381efe`).

## Where things stand
The game is **Color Clash / "Jamie, Jasmine & Jinn"** — a connect-3 campaign:
5 islands × 10 stages = 50, scrollable island map, sequential unlock via
ProgressService (all intact). Today added the **story / character / enemy
foundation**. Everything is additive over the working map/economy/progress —
no source PNG modified, no system rebuilt. **830/830 unit tests pass, all 4
smoke scripts pass, Android APK builds (exit 0) and installs.**

### Assets (assets/story/, 10 PNGs — Downloads source untouched)
| id | file | content |
|---|---|---|
| story_jamie_portrait | jamie_portrait.png | Jamie hero (crown, fire sword, blue lightning hand, lightning boots) |
| story_jasmine_portrait | jasmine_portrait.png | Jasmine princess |
| story_jinn_portrait | jinn_portrait.png | Jinn villain (red jinn, smoke body) |
| story_jasmine_poses | jasmine_poses_8.png | 4×2 pose sheet → 8 AtlasTexture cells |
| story_cast_atlas / story_scenes | *_transparent.png | scene reference (Phase-12 cutscenes) |
| story_enemies | enemies_and_bosses.png | 10 labelled "Jin's servants" (top row → AtlasTexture) |
| story_jamie_actions / story_jinn_actions / story_jasmine_expr | *_ref.png | opaque action sheets (Phase-5 slicing) |

Registered in `AssetLibrary._STORY_ART` (+ `story_art_audit()`).

### Systems built
- **`Cast`** (`scripts/story/cast.gd`) — `portrait(who)`, `pose(who,name)`.
  Jasmine's 8 poses sliced by name (captured / hopeful / scared / thinking /
  rescued / …). Jamie & Jinn → portrait until their action sheets are sliced.
- **`EnemyModel`** (`scripts/story/enemy_model.gd` + `data/enemies.json`) —
  10 enemies, per-island rosters, **boss-stage map**: 10 Poison Beast · 20
  Ice Wraith · 30 Dark Knight · 40 Chaos Sorcerer · 50 **Jinn**. Tier HP
  (`normal 3 … final_boss 30`) scaling by chapter, `enemy_face` Atlas slices.
- **`Story`** autoload (`scripts/story/story_director.gd` + `data/story.json`)
  — data-driven beats keyed by trigger (`campaign_start` | `island_start:N` |
  `stage_start:N` | `stage_complete:N`). Content: opening kidnapping
  cinematic, a chapter card per island, boss intros, a **Jinn cameo at stage
  30**, the stage-50 finale + reunion. Each beat plays once, persisted via
  SaveService (`story_seen`).
- **`StoryScene`** (`scripts/story/story_scene.gd`) — reusable cutscene
  overlay: supplied character art slides in per speaker, glass dialogue box,
  tap **or** auto-advance (reading-speed timer). `auto_skip` / headless →
  resolves instantly so automation never blocks.
- **Wiring** (`app.gd`): pre-level beats in `_go_to_level` /
  `_on_next_level_pressed` before `_start_level`; post-stage beats in
  `_on_level_won` before the win panel. `CharacterView` now renders the real
  Jamie portrait (code placeholder kept as fallback).

### Tests added
`test_story_assets.gd` · `test_enemy_model.gd` · `test_story_data.gd`
(registered in `test_runner.gd`).

## NOT done yet — clean integration points are in place
- **Opening cinematic** plays as a dialogue beat; a richer scripted sequence
  (backgrounds, Jinn entrance FX, kidnap animation) is Phase 4 polish.
- **Jamie power presentation** (fire sword / lightning hand / boots states)
  — slice `story_jamie_actions` opaque sheet; extend `Cast.pose` for Jamie.
- **Boss HP battles** on 10/20/30/40/50 — `EnemyModel.boss_hp()` is ready;
  needs a `BossBar` HUD element + match-energy → damage in `_apply_move_result`.
- **Match-3 → attack energy** coupling — hook the existing `GameEvents`
  stream (`MATCH_FOUND`, `POWER_ACTIVATED`, `CASCADE_FINISHED`) to a
  `CombatDirector` that drives Jamie attacks + boss damage.
- **Inventory screen** — character / powers / equipment / boosters, over the
  existing `Boosters`/`Economy`/`Progress` save. Follow the UI/UX ref.
- **Music/SFX** — Arabic-fantasy direction; 11 music slots + combat SFX.
  Use the existing `Audio`/`Music` synth architecture / `Audio.register()`.
- **On-device verification of this build is pending** — the USB test device
  disconnected repeatedly this session. APK is at `build/color-clash-debug.apk`
  (~302 MB); it installed successfully once before dropping.

## Do NOT
- Push to origin.
- Rewrite the connect-3 core, hex grid, powers, ChainResolver, level data,
  ProgressService, IslandModel, the event stream, or the island map.
- Modify / crop / replace any supplied source PNG (slice via AtlasTexture).
- Rename Jamie / Jasmine / Jinn or redesign their look.
- Add a second save/progression/currency system.
