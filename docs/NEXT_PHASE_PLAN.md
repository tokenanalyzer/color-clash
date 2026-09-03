# Color Clash — Audit & Next-Phase Plan (2026-09-03)

Prepared as a planning checkpoint. **No gameplay code was changed today.** This
document is the audit result + agreed direction + asset request list + build
order for the polish phase. Nothing here reverts or replaces the completed
asset-integration work.

---

## 1. CURRENT STATE (verified in the repo, not from screenshots)

### Engine / build
- **Godot 4.4.1-stable** (standard, not Mono). `renderer = gl_compatibility`
  (mobile-safe). `run/max_fps = 60`.
- Portrait locked: `handheld/orientation = 1`, viewport `1080×1920`,
  `stretch = canvas_items / expand`.
- Android export preset present (`game/export_presets.cfg`): `com.colorclash.game`,
  v0.5.0 (code 1), arm64-v8a + armeabi-v7a, **only `VIBRATE` permission**,
  no internet, `use_gradle_build = false` (repacks prebuilt template — no
  Gradle/NDK needed until a native plugin is added).
- Two APKs built and in `build/` (`color-clash-2026-09-02-assets.apk`,
  `color-clash-debug.apk`). Build toolchain documented in `docs/ANDROID.md`.
- `[importer_defaults]` forces every PNG **LOSSLESS + mipmaps + fix_alpha_border**.

### What actually works (confirmed)
| System | State | Where |
|---|---|---|
| Board model (hex/honeycomb, 6-neighbour adjacency, gravity, refill) | **Working, pure, unit-tested** | `scripts/board/board_model.gd` |
| Free-form "connect 3+" input (drag path, validation, rainbow wildcard) | Working | `board_model.validate_path`, `board_view.gd` |
| Power creation (persistent tiles: bomb 4 / lightning 5 / freeze 6 / chain 7 / rainbow 8+, x2@10 x3@13) | Working, data-driven | `data/powers.json`, `chain_resolver.gd` |
| Power activation by threading into a connection, or tap, or booster | Working | `chain_resolver.resolve_move / resolve_power_tap / detonate_power_at` |
| Cascades — real multi-wave (multi-power-from-one-move + secondary exposed-cluster generation, capped at 6) | Working, deterministic, unit-tested | `chain_resolver.gd` |
| Power area effects (hex disc / hex ring / full row-col / whole-color) | Working | `power_resolver.gd` |
| Obstacles: **ice, lock, stone, timebomb** | Working, unit-tested | `board_model.gd`, `chain_resolver.gd` |
| Auto-reshuffle when no valid move exists | Working | `board_view.gd` (checked after every move + on setup) |
| Score (per-cell + power bonus × combo-depth mult × fever mult) | Working | `scripts/economy/score_calculator.gd` |
| Combo tracking (chain depth of one move) | Working | `scripts/combo/combo_system.gd` |
| Fever meter (built from strong moves, decays on weak, caps per-move, 6-move x1.5) | Working, data-driven, unit-tested | `scripts/combo/fever_system.gd`, `data/fever.json` |
| Objectives: `reach_score`, `clear_color`, `create_powers`, `break_obstacles` (mixed = all required) | Working, unit-tested | `scripts/levels/objective.gd` |
| 50-level campaign, data-driven, generated | Working | `data/levels.json`, `tools/level_gen/generate_levels.py` |
| Level DB / config loader (scales to hundreds, no code change) | Working | `scripts/levels/level_database.gd`, `level_config.gd` |
| Progression: linear unlock, stars (move-efficiency), best score, only-improves | Working, unit-tested | `scripts/economy/progress_service.gd`, `star_rating.gd` |
| Star rating | Working — **but move-efficiency only, ignores score** | `star_rating.gd` |
| Economy: coins, spend/grant, starter 500, local persist | Working | `scripts/economy/economy_service.gd` |
| Boosters: 6 (bomb/lightning/freeze/rainbow targeted-arm, shuffle/+5 instant), real gameplay behaviour, buy with coins | Working — **all 6 have real effects, none are fake UI** | `data/boosters.json`, `booster_inventory.gd`, `app.gd`, `board_view.gd` |
| Daily rewards (7-day, streak) | Working, unit-tested | `scripts/economy/daily_rewards.gd`, `scripts/ui/daily_rewards.gd` |
| Milestone chest every 5th level (first clear) | Working | `app.gd._present_milestone_chest` |
| Save/load (local JSON, `user://save.json`, offline-first) | Working | `scripts/save/save_service.gd` |
| Screen flow: Splash → Menu → Map ⇄ Play, Daily from Menu, Pause + Settings in Play | Working | `scripts/app.gd` |
| Settings: Music/SFX/Haptics toggles + Master/Music/SFX volume sliders, persisted, applied to real AudioServer buses | **Working in both in-level HUD (gear) and Main Menu (options)** | `scripts/audio/audio_settings.gd`, `hud.gd:495`, `main_menu.gd:196` |
| Audio: fully **synthesized at runtime** (no licensed samples) — SFX + 5-layer adaptive music with intensity states (idle/base/active/high/fever/tension), data-driven | Working, unit-tested (DSP + builders) | `scripts/audio/*`, `data/sfx.json`, `data/music.json` |
| VFX: pooled shard bursts, pooled impact rings, pooled textured one-shot sprites, screen shake (re-entrant safe), haptics wrapper, combo popup, animated backdrop with per-world scene cycle | Working | `scripts/vfx/*` |
| Art: **74 hand-made PNGs** wired through every renderer with procedural fallback per texture | Working — **74/74 load** (verified) | `scripts/core/asset_library.gd` |
| Service stubs: IAP / Ads / Firebase | **Interface only, not wired to gameplay** (intentional) | `scripts/services/*` |
| Headless test suite | **342 / 342 pass** (verified this session) | `game/tests/`, `test_runner.gd` |

### Previous session (what landed, per git + `docs/RESUME.md`)
Commit `2a14ecf` **did commit** both milestones the RESUME note was still
waiting on:
1. Mobile-fit / presentation pass (typography ramp, safe-area, menu/splash/map
   redesign).
2. Prepared-art integration (assets 1–74) — master art copied into
   `game/assets/`, `AssetLibrary` static registry, `SpriteFX` pool, LOSSLESS
   import defaults, every renderer switched to blit real sprites.

`docs/RESUME.md` is now **stale** — its "NEXT SESSION" list (commit both
milestones, no push) is already done. Its "Do NOT" list is still valid and
carried into this plan.

**Incomplete from the previous session (its own notes):**
- Not on-device verified since the art pass (fever meter ornament, safe-area on
  the real OnePlus Nord, 60 FPS check via `adb logcat`).
- Fever meter frame art (#53) is a chunky crowned capsule used as a small
  ornament on a thin bar — "legible, not gorgeous."
- Board scenes (env #58–65) letterbox above/below the honeycomb on 20:9.
- Splash wordmark timing.

---

## 2. PROBLEMS / GAPS (what needs to improve)

### Gameplay depth
1. **No power + power *combination recipes*.** Powers currently *chain*
   (one blast catches another live power) but two powers swept in the same
   connection just each fire their own area — there is no distinct
   "bomb+bomb = 5×5", "line+line = full cross", "rainbow+bomb = every gem of
   a colour becomes a bomb then all detonate", "rainbow+rainbow = clear
   board". This is the single most-felt missing mechanic vs. a modern
   match-3.
2. **The engine returns one fat `MoveResult`; the 1150-line `board_view.gd`
   re-derives the animation timeline from it.** This coupling is the main
   thing blocking "add mechanics without rewriting." Needs a typed
   **event stream** (see §7 architecture).
3. **Star rating ignores score.** `star_rating.gd` only looks at leftover
   moves, so every objective type gets stars the same way — fair, but flat.
   Modern match-3 stars are score-threshold based. Recommend per-level
   `star_scores: [s1, s2, s3]` in level data, fall back to move-efficiency.
4. **Only 4 objective types.** Missing the campaign backbone: a
   *coating / jelly / cover* goal ("clear every covered tile") and a
   *collect / bring-down* goal ("drop 3 tokens off the bottom"). These need
   one new obstacle each (§4).
5. **Only 4 obstacles.** GDD lists portal, crystal/multi-hit, and the design
   wants a spreading blocker. Missing.
6. **Authored level hints are dead data.** `data/levels.json` has a `hint`
   field on 7 levels; `LevelConfig.from_dict` never reads it and the HUD's
   `_hint_label` is only used for booster-arm prompts. Cheap to wire once a
   pre-level panel exists.
7. **No pre-level "start" panel** (show objectives + pick boosters before
   the board loads). Boosters can only be armed mid-level.
8. **No tutorial / onboarding sequence** — just static hint text. L1–5 are
   generously tuned but nothing *teaches* connect → release → power → activate.
9. **No Daily Rush mode** (GDD lists it as a mode; not implemented).
10. **No character system at all** (see §6).

### Presentation / feel
11. Juice constants (tween times, shake amplitudes, stagger) are scattered as
    magic numbers across `board_view.gd` — no single tunable table.
12. No **squash/stretch or anticipation** on gem land/spawn; no **match
    telegraph** (highlight a connectable group on touch-down).
13. Combo popup is plain bounce text; no escalating combo-tier art even
    though `cel_*` / `vfx_*` assets exist for it.
14. Fever meter presentation (carried from previous session).
15. Objective HUD is text; no per-objective icon + progress bar chip.
16. Board letterboxes on tall screens (20:9) — the env scene shows as bands.

### Mobile UI
17. Touch-target sizes not verified against a 48dp minimum on a real device.
18. `launcher_icons/*` in the export preset are **empty** — no adaptive icon
    foreground/background set (ships with the default Godot icon on the
    launcher).
19. Booster bar shows counts but no "+" affordance to buy more inline.

### Performance (mostly fine, watch-list only)
20. Every PNG imports LOSSLESS + mipmaps — generous VRAM. Fine for a modern
    phone; revisit `etc2/astc` for the `env/*` full-screen scenes if low-end
    devices stutter.
21. `board_view._process` runs an idle-sparkle loop every frame — cheap, but
    audit once more mechanics add per-frame work.
22. `_resync_all_from_board` rebuilds all piece visuals — only used on
    shuffle/setup, acceptable, but don't call it mid-cascade.

### Services / release
23. IAP / Ads / Firebase are stubs — fine for now, but no analytics means no
    data-driven difficulty tuning yet.
24. No CI runs the 342 tests automatically.

---

## 3. GAMEPLAY PLAN — target architecture

**Keep the connect-based core.** It is original (not a Candy Crush swap
clone), already deterministic and unit-tested, and it is the Color Clash
identity. We build depth *on top of it*, we do not rewrite it.

### 3.1 Formalise a headless `MatchEngine` + typed event stream
Wrap the existing pure classes (`BoardModel`, `PowerResolver`,
`ChainResolver`, `ObjectiveTracker`, `FeverSystem`, `ComboSystem`,
`ScoreCalculator`) behind one `MatchEngine` (still `RefCounted`, still
headless-testable) that runs a **turn state machine**:

```
IDLE → INPUT → VALIDATE → RESOLVE(wave loop) → GRAVITY → REFILL
     → OBJECTIVE/FEVER/SCORE UPDATE → CHECK WIN/LOSE → IDLE
```

`resolve_move` stops returning one fat struct and instead appends to an
ordered `Array[EngineEvent]`:

```
MOVE_STARTED, PATH_CLEARED, POWER_CREATED, POWER_ACTIVATED,
POWER_COMBINED{recipe}, WAVE_STARTED{index}, CELLS_CLEARED{cells,color},
OBSTACLE_HIT{pos,id,hp}, OBSTACLE_BROKEN{pos,id}, CELL_FROZEN,
TIMEBOMB_TICK, TIMEBOMB_EXPLODED, GRAVITY_MOVES, CELLS_REFILLED,
SCORE_GAINED{amount,reason}, OBJECTIVE_PROGRESS{index,value,target},
COMBO_REACHED{tier}, FEVER_CHANGED{meter,active}, MOVE_CONSUMED{penalty},
LEVEL_WON{stars}, LEVEL_LOST
```

The view layer (`board_view.gd`, `hud.gd`), the audio director, the VFX
director, and the new character director all become **pure consumers of that
event list** — each renders the events it cares about with its own timing.
Adding a mechanic = add an event type + its handler in the engine + one
render branch. No cross-system rewrite.

*(This is a refactor, not a redesign — the current `MoveResult` fields map
almost 1:1 to events. Do it early so everything after builds on it.)*

### 3.2 Special-piece system — `PowerCombiner`
- Keep the 5 powers. Add a `data/power_combos.json` recipe table keyed by an
  unordered pair of power ids → a combined effect:
  | Pair | Effect (original Color Clash naming) |
  |---|---|
  | bomb + bomb | **Shockburst** — radius-2 hex disc |
  | line + line (lightning×2) | **Crossfire** — full row *and* column from both origins |
  | bomb + line | **Comet** — a 3-wide swathe along the line |
  | freeze + any | detonates the "any", then frosts a radius-2 ring |
  | chain + any | clears the "any"'s colour board-wide, then fires "any" on the survivors |
  | rainbow + bomb/line/freeze | convert every gem of a chosen colour into that power, then detonate all |
  | rainbow + rainbow | **Prism Wipe** — clear the whole board (capped score contribution) |
  | rainbow + chain | clear the two largest colours |
- Trigger: when a single connection threads ≥2 power tiles, or a blast puts
  ≥2 powers in one wave, `ChainResolver` asks `PowerCombiner.recipe(a, b)`
  before falling back to "each fires independently."
- All recipes resolve through the same wave loop / event stream — cascades,
  obstacle rules and Fever gain stay consistent.

### 3.3 New obstacles (modular — each is a `CellData` flag + 2–3 engine hooks)
Priority order:
1. **Coating / "Stain"** (jelly-equivalent) — a cell overlay, 1–2 layers,
   removed when a match or blast touches the cell. Enables the
   `clear_all_coating` objective, the classic campaign backbone.
2. **Collectible token** ("Prism Shard") — occupies a cell, no colour, is
   *not* matched; falls with gravity; "collected" when it reaches the bottom
   row. Enables `collect_tokens` objective.
3. **Crate / "Lockbox"** — like stone but 2 HP and drops loot (coins) when
   broken. Reuses stone code path.
4. **Spreading blocker ("Creep")** — grows into one random empty neighbour
   every N moves unless a match is adjacent. High-pressure, late campaign.
5. **Portal** — links two cells; a piece leaving the bottom of portal A
   re-enters at portal B. Topology change; `apply_gravity` gets a redirect
   hook. Deferred until 1–4 ship.

### 3.4 New objective types (`objective.gd` — one `match` arm each)
`clear_coating`, `collect_tokens`, `clear_cells_at` (specific positions),
`survive_moves` (Daily-Rush style). Data-driven, no other change.

### 3.5 Difficulty & progression
- Keep the Python generator. Extend the curve tiers with the new obstacles
  as they land (coating from ~L8, tokens from ~L18, creep from ~L38).
- Add `star_scores` per level (generator computes from an expected-score
  model). Move-efficiency stays the fallback for score-less objectives.
- Add a lightweight **"replay for stars"** loop on the map (already
  tappable; just surface "2★ — beat 45,000 for 3★").

### 3.6 Level failure / retry
Already implemented (soft "So Close!" panel, retry keeps level). Add:
- Optional **+5 moves continue** offer on loss (spend coins now; rewarded-ad
  hook later — `AdsService` seam already exists).

---

## 4. SPECIAL PIECES / BOOSTERS — plan

All 6 existing boosters have real gameplay behaviour (verified) — **no fake
boosters exist**. Plan:
- Add **pre-level booster select** (start panel): choose up to 2, they arm at
  board load.
- Add a **7th booster: "Colour Swap"** — arm, tap a gem, cycles it to the
  next colour (uses the existing `power_energy_container` frame art).
- Wire the `PowerCombiner` recipes so a booster-placed power + a
  board power combine (booster path already shares `detonate_power_at`).
- Booster art: `powers/*.png` (7–12) already cover bomb/lightning/freeze/
  chain/rainbow/combo_core; `ui/booster_container.png` + `power_energy_container.png`
  are the tray frames. Shuffle / +Moves / Colour-Swap need small icons
  (see asset request §8-C).

---

## 5. ANIMATION & GAME FEEL — plan

Introduce a **`FeedbackDirector`** (event-stream consumer) + `data/juice.json`
holding every timing/curve/amplitude currently hard-coded in `board_view.gd`.
Then layer:
- **Gem move**: ease-out with a short overshoot; stagger by row on refill.
- **Match / destroy**: scale-punch → shard burst (pooled, exists) → light
  additive flash. Colour-tinted from `colors.json` `glow`.
- **Cascade**: each wave offset by `juice.wave_stagger`, rising SFX pitch
  (already wired), slight cumulative zoom on deep chains.
- **Power activation**: per-power signature (bomb = radial shove + shake;
  lightning = bolt sprite along the line, exists; freeze = frost bloom;
  chain = colour-wide ripple; rainbow = white flash + colour drain).
- **Combo feedback**: escalating popup art at tiers 2/4/6 using
  `cel_star_burst` / `vfx_energy_burst`; number pop.
- **Screen feedback**: shake amplitude from `juice.json`, capped; brief
  chromatic-free vignette pulse on Fever/big-combo only (perf-safe).
- **Score popup**: fly-to-HUD counter (partly exists), +N text at clear
  centroid.
- **Goal progress**: chip fills + a tick bounce when an objective completes.
- **Fever**: board aura + backdrop tint + HUD flash + ignition burst (exists)
  — keep, retune via `juice.json`.
- **Level complete / fail**: complete = crown + confetti + portal
  (`cel_*` assets exist); fail = soft desaturate + gentle descent (exists).
- **Button / booster feedback**: unify on one `_pulse` + click SFX helper.

Performance guard: all bursts stay pooled; particle count per event capped in
`juice.json`; no per-frame shader work; vignette pulse is a single modulated
`ColorRect`, not a shader.

---

## 6. CHARACTER SYSTEM — architecture (art supplied later)

**Nothing exists today.** Build the hooks now, drop art in later.

- **`data/character.json`** — maps engine events → reactions:
  ```json
  {
    "reactions": {
      "level_start":  {"pose": "wave",    "line": "Let's clash!"},
      "combo_tier_2": {"pose": "cheer",   "line": "Nice!"},
      "combo_tier_4": {"pose": "hype",    "line": "Colour storm!"},
      "power_created":{"pose": "point"},
      "fever_start":  {"pose": "power_up", "line": "FEVER!"},
      "near_fail":    {"pose": "worried"},
      "level_won":    {"pose": "victory"},
      "level_lost":   {"pose": "sad", "line": "So close!"},
      "reward":       {"pose": "gift"}
    }
  }
  ```
- **`CharacterDirector`** (autoload) — subscribes to the event stream,
  debounces (max one reaction / 1.2 s, priority-ordered), emits `react(pose,
  line)`.
- **`CharacterView`** (Node2D docked bottom-left of the HUD, above the tray)
  — plays the pose. Until real art: a **code-drawn placeholder** (rounded
  silhouette + expression dots + a small speech bubble). Swappable via
  `AssetLibrary` ids `char_idle`, `char_cheer`, … exactly like every other
  sprite (procedural fallback pattern already established).
- Participation points wired from day one: level start, combo tiers, power
  creation, Fever, near-fail, win, lose, reward-claim, map idle.
- No gameplay dependency on the character — it is pure feedback, so a missing
  art set never blocks a build.

---

## 7. LEVEL SYSTEM — schema extension (backward compatible)

Current level JSON already supports: `id`, `name`, `width`, `height`,
`colors`, `move_limit`, `objectives[]`, `obstacles[]`, `reward.coins`,
`difficulty`, `hint` (unused). Add, all optional with sane defaults:

```jsonc
{
  "background_theme": "crystal",        // -> AssetLibrary env id; default = world cycle
  "available_boosters": ["bomb","lightning","shuffle"],  // whitelist; default = all
  "star_scores": [30000, 45000, 60000], // score thresholds; default = move-efficiency
  "spawn_weights": { "red": 2, "blue": 1 }, // bias refill; default = uniform
  "preplaced": [ {"x":3,"y":4,"color":"red"} ], // fixed opening pieces
  "rng_seed": 12345,                    // reproducible board; default = random
  "portal_links": [ [[0,9],[8,9]] ],    // when portals ship
  "intro_hint": "Ice takes two hits."   // rename of `hint`, shown on start panel
}
```

`LevelConfig.from_dict` parses each with a default; `LevelDatabase` and the
generator get the new fields. **No existing level breaks.** Keep the Python
generator as the authoring tool; add a small JSON-schema validator run in CI.

---

## 8. ASSET REPORT

### A. Available & usable now (no action)
All **74 prepared PNGs** — gems 1–6, powers 7–12, obstacles 13–18, VFX 19–30,
economy 31–39, map 40–48, UI 49–57, environments 58–67, celebration 68–74.
All load (74/74 verified). `icon.png` (custom app icon source) present.

### B. Need minor adjustment
| Asset | Issue | Fix |
|---|---|---|
| `ui/fever_meter_frame.png` (#53) | 3:1 crowned capsule; HUD bar is thin full-width — used only as a small ornament | Redraw as a thin full-width bar frame, **or** we restyle the HUD fever row taller to fit it. Needs your call. |
| `env/*` full-screen scenes (#58–65) | letterbox above/below the board on 20:9 phones | Either extend the art vertically (bleed), or we keep the current "framed playfield" treatment (veiled ~0.30). Cosmetic. |
| `icon.png` | single source; export preset `launcher_icons/*` are empty | Provide adaptive-icon **foreground** (432×432, transparent) + **background** (432×432, opaque) + `main` 192×192. |

### C. Completely missing — safe for us to create procedurally / in code
(will build these; replace with your art later via the same `AssetLibrary` id)
- Coating/"Stain" overlay, collectible "Prism Shard" token, "Lockbox" crate,
  "Creep" spreading blocker — obstacle art.
- Match-telegraph highlight, combo-tier number art, score `+N` popup style.
- Character **placeholder** silhouette + pose set + speech bubble.
- Pre-level start-panel frame, objective progress-chip frame.
- Boot-splash fallback wordmark (already code-drawn in `splash_screen.gd`).
- Shuffle / +Moves / Colour-Swap booster glyphs (small, code-drawn).

### D. Assets **you need to provide** (we will NOT invent these)
| # | Asset | Why | Recommended size | Format | Transparency | Used in |
|---|---|---|---|---|---|---|
| 1 | **Company logo** | Studio branding pre-splash | 1024×1024 (fits ≤512 display) | PNG | Yes | Splash sequence frame 1, About panel |
| 2 | **Game logo / "Color Clash" wordmark** | Main menu + splash + store | 1600×600 (approx 8:3) | PNG | Yes | `main_menu.gd`, `splash_screen.gd` |
| 3 | **Splash screen artwork** | Branded boot screen | 1080×1920 (portrait, full-bleed) + a 2340-tall safe variant | PNG (or JPG if opaque) | Optional | `splash_screen.gd`, `project.godot boot_splash` |
| 4 | **App launcher icon** — adaptive foreground | Play Store / launcher | 432×432 | PNG | Yes (fg) | `export_presets.cfg launcher_icons` |
| 5 | **App launcher icon** — adaptive background | same | 432×432 | PNG | No | same |
| 6 | **App icon (legacy square)** | fallback icon | 512×512 | PNG | No | `icon.png` |
| 7 | **Character art** (if you want a real one, not our placeholder) | Mascot reactions | ~600×800 per pose, ~9 poses (idle, wave, cheer, hype, point, power_up, worried, victory, sad, gift) | PNG | Yes | `CharacterView` |
| 8 | **Store feature graphic** | Play listing | 1024×500 | PNG/JPG | No | Play Console (not in-game) |
| 9 | *(later, optional)* Real **music loops** (5: pad/bass/arp/perc/fever_lead, identical bar length) + **SFX** set | replace synth | — | OGG/WAV, loopable | — | `data/music.json`, `data/sfx.json` via `Audio.register()` |

### E. Assets we can safely generate procedurally / in code — see C.

### F. Assets that should be newly generated (by you or a future art pass)
- Final coating / token / crate / creep / portal art (we ship procedural
  placeholders; these upgrade them).
- Combo-tier celebration numerals if you want bespoke typography.
- Any world/theme backgrounds beyond the current 6 if the campaign grows
  past ~60 levels.

---

## 9. DEVELOPMENT ROADMAP (dependency-ordered)

> Rule of the phase: preserve the working state, keep every change reversible,
> commit at each phase boundary, no push without on-device verification.

### PHASE 1 — Core engine refactor (enables everything after)
- Introduce `MatchEngine` + typed `EngineEvent` stream (§3.1). Map current
  `MoveResult` → events. Keep `resolve_move` semantics identical.
- Port `board_view.gd` / `hud.gd` / audio / VFX to consume events.
- Add JSON-schema validator for `levels.json` + run all 342 tests in CI.
- **Exit:** all 342 tests still pass, game plays identically, event log
  asserted in a new test.

### PHASE 2 — Match / cascade / special mechanics
- `PowerCombiner` + `data/power_combos.json` (§3.2), unit-tested.
- New obstacles: coating, collectible token, crate (§3.3 items 1–3).
- New objectives: `clear_coating`, `collect_tokens` (§3.4).
- Extend the level generator curve to introduce them.
- Score-threshold stars (`star_scores`) with move-efficiency fallback.
- **Exit:** new mechanics unit-tested; 3–4 new campaign levels use them.

### PHASE 3 — Animation & VFX (game feel)
- `FeedbackDirector` + `data/juice.json`; move all magic numbers into it.
- Squash/stretch, match telegraph, escalating combo art, retuned Fever,
  score-fly, objective-chip fills, per-power signatures (§5).
- Perf pass: particle caps, pooled everything, on-device FPS log.
- **Exit:** 60 FPS on the OnePlus Nord during a deep cascade + Fever.

### PHASE 4 — Level / objective system polish
- Full schema extension (§7): themes, booster whitelist, spawn weights,
  preplaced, seeds.
- Pre-level **start panel** (objectives + booster select) + wire `intro_hint`.
- Replay-for-stars surfacing on the map.
- Loss "continue (+5 moves)" offer (coins now, ad seam later).
- **Exit:** a level fully defined by data alone, start panel shipped.

### PHASE 5 — Character system
- `data/character.json`, `CharacterDirector` autoload, `CharacterView` with
  code-drawn placeholder, all participation hooks (§6).
- Drop-in real art when provided.
- **Exit:** character reacts to start/combo/power/Fever/near-fail/win/lose/
  reward; zero gameplay dependency.

### PHASE 6 — UI / HUD polish (mobile-first, portrait)
- Objective chips (icon + bar), booster bar "+to buy", fever meter final
  treatment, typography lock, 48dp touch-target audit, safe-area re-check on
  device, board letterbox treatment decision.
- **Exit:** on-device screenshot review of every screen signed off.

### PHASE 7 — Audio integration readiness
- `assets/audio/{music,sfx}/` folders + a loader that prefers a real
  file over the synth for any id (`Audio.register` seam already exists).
- Documented id list (match/combo/power/booster/button/fever/win/fail/music).
- Settings already control music/SFX/haptics — verify against real streams.
- **Exit:** dropping an OGG into the folder replaces that sound, no code
  change.

### PHASE 8 — Branding / Splash / Logo
- Integrate company logo, game wordmark, splash artwork into
  `splash_screen.gd` + `project.godot boot_splash` + `main_menu.gd`.
- Adaptive launcher icon into `export_presets.cfg`.
- Keep the code-drawn splash as the fallback path.
- **Exit:** branded boot on device; store icon set.

### PHASE 9 — Android optimization
- ETC2/ASTC for `env/*` scenes if low-end stutter; texture-budget audit.
- Cascade allocation audit (no per-wave `Array` churn in hot loop).
- `--headless` export size check, startup-time check, memory profile.
- **Exit:** smooth on a low/mid device, APK size reasonable.

### PHASE 10 — Final QA & release build
- Full campaign playthrough, every objective/obstacle/combo path.
- Accessibility pass (shape/pattern cues, flashing limits, contrast).
- Security review (economy boundary, no secrets — `docs/SECURITY.md`).
- Release keystore, AAB export (`gradle_build/export_format = 1`), version
  bump, Play Console internal track.
- **Exit:** signed AAB, internal testers.

**Services (IAP / Ads / Firebase Analytics / Cloud Save / Remote Config)**
stay as stubs until after Phase 6, then slot in parallel with Phase 9–10 —
they are already isolated behind `scripts/services/*` and need a Gradle custom
build (documented in `docs/ANDROID.md`).

---

## 10. READY FOR NEXT SESSION

When you return, the following is in place and verified:
- **This plan** (`docs/NEXT_PHASE_PLAN.md`) and a refreshed `docs/RESUME.md`.
- **Full audit** of every system with file references — §1 table is the
  ground truth of what exists.
- **342/342 tests pass**, **74/74 art assets load**, project builds headless
  on Godot 4.4.1 — confirmed this session.
- A **concrete architecture** (event-stream `MatchEngine`) that makes the
  rest of the work additive rather than a rewrite.
- A **prioritised 10-phase roadmap** with dependency order and exit criteria.
- An **exact asset request list** (§8-D) — 8 branding/icon/character items
  we will not invent, plus the optional audio set.

**Nothing was rewritten, reverted, or replaced today.** The connect-based
core, hex board, persistent powers, 50-level campaign, asset integration,
economy, and progression are all preserved.

### Recommended first action next session
Confirm two product decisions, then start Phase 1:
1. **Fever meter** — redraw the frame art thin, or make the HUD row taller?
2. **Character** — real art set from you, or ship our procedural placeholder
   and upgrade later?
3. **Stars** — move to score thresholds (with move-efficiency fallback), or
   keep pure move-efficiency?
