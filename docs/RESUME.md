# Resume point — 2026-09-03 (Phase 1 complete)

Phase 1 of `docs/NEXT_PHASE_PLAN.md` is **implemented, verified, and
committed locally** (`bf58b3e` — NOT pushed). Additive only; no existing
gameplay logic was rewritten.

## What landed in Phase 1
- **Typed gameplay event stream.** `EngineEvent` (25 typed constants),
  `GameplayEventStream`, `MoveEventTranslator` (pure MoveResult -> events,
  does not re-run game logic), `GameEvents` autoload bus. `app.gd` now
  publishes translated move events + session events every move. The old
  `board_view -> app` signal wiring is untouched and runs alongside.
- **Character system architecture.** `CharacterDirector` autoload
  (data-driven `data/character.json`, debounced reactions, consumes the
  bus), `CharacterView` code-drawn placeholder mascot (bottom-left,
  faded with game chrome). Real art drops in via `AssetLibrary`
  `char_<pose>` ids later — no code change.
- **Thin Fever meter.** `HUD.FeverArt` reworked to a slim code-drawn
  capsule frame (gold ring + crown tick + crystal on fill edge). Chunky
  #53 frame art no longer used here. HUD row height unchanged.
- **Score-threshold stars.** `StarRating.stars_for_score()` — per-level
  `star_scores` from `data/levels.json` is primary, move-efficiency is
  fallback. `stars_for()` kept. `LevelConfig` parses `star_scores` +
  `hint`. `generate_levels.py` emits `star_scores` (first-pass model,
  re-tune from analytics later). `levels.json` regenerated.

## Verified
- Unit: **384 / 384** (`test_runner.gd`; +`test_event_stream.gd` 11
  tests incl. determinism, +8 star-threshold asserts). 342 prior all pass.
- Smokes: all 4 pass against the real main scene.
- Android: debug APK exported (~221 MB), installed + launched on device
  `3C15CB00ABS00000`, a real level played on-device — moves, score,
  objectives, cascades, powers, obstacles, Fever all advancing; **60 FPS
  held**; zero script errors in `adb logcat`.
- Offscreen renders: thin fever meter + placeholder mascot confirmed.

## NEXT SESSION — Phase 2 (see docs/NEXT_PHASE_PLAN.md §9)
Do NOT start before these are decided/ready:
1. `PowerCombiner` + `data/power_combos.json` recipe table.
2. New obstacles: coating/"Stain", collectible "Prism Shard", crate.
3. New objectives: `clear_coating`, `collect_tokens`.
4. Extend the generator curve to introduce them; add 3-4 showcase levels.
5. Migrate `board_view` / `hud` / audio director onto the event stream as
   their primary input (Phase 1 built the stream; they still use the
   direct signals — that migration is Phase 2/3 groundwork).

Remaining Phase 1 follow-ups (small, non-blocking):
- `MoveEventTranslator` does not emit `OBSTACLE_DAMAGED` (partial ice/lock
  hits) — needs one additive field on `ChainResolver`. Deferred so the
  tested resolver stayed untouched.
- Star-threshold numbers are a first-pass model — re-tune once analytics
  exist.
- On-device: mascot contrast is low against the dark board band; final
  placement + real art come with the character phase.

## Do NOT
- Push to origin.
- Rewrite the connect-based core, hex grid, persistent powers, level
  system, ProgressService, or ChainResolver. Phase 1 kept all of them
  byte-for-byte; keep it that way — extend via the event stream + new
  modules.
- Invent branding/logo/splash/character art — request list is
  `docs/NEXT_PHASE_PLAN.md` §8-D.
