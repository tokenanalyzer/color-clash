# Resume point — 2026-09-03 (UI/UX reference pass)

Two milestones committed locally today, **NOT pushed**:
- `bf58b3e` / `47fbd72` — Phase 1: typed gameplay event stream + character
  hooks + data-driven star scores.
- `07deda9` — reference-matched premium UI (this pass).

## UI pass — what landed (07deda9)
Implements the approved `UIUX reference image color clash.png`. No gameplay
logic, board engine, save format, progression, audio, or VFX changed — the
UI is upgraded *around* the existing systems. **412/412 unit tests pass, all
4 smoke scripts pass, Android debug APK built + device-verified at 60 FPS.**

- **`scripts/ui/ui_kit.gd`** — shared kit: frosted-glass styleboxes (replace
  every opaque black strip), beveled premium buttons, `GoldFramePanel`
  (ornate gold frame + diamond corners), glass currency chips, glass icon
  buttons, pop/press/count-up animation helpers.
- **Home** (`main_menu.gd`) — PLAY enlarged + moved to ~40% height; frosted
  glass currency bar; DAILY REWARD + SETTINGS beneath; wordmark uses
  `AssetLibrary &"brand_wordmark"` PNG when supplied, else code wordmark.
- **Island map** (`level_map.gd` + `levels/island_model.gd` +
  `data/islands.json`) — genuinely vertical finger-drag + inertia
  (`KineticScroll`), auto-centres on the current island. `IslandModel` is a
  PURE view of ProgressService: 5 islands × 10 stages, **no new save state,
  unlock rules unchanged**. Per-island header (name, x/10, lock/current/
  complete). Nodes still `LevelNodeButton`.
- **Settings** (`settings_panel.gd`, shared by menu + HUD) — gold-framed
  frosted dialog, animated open/close, wired to real `AudioSettings`. HUD's
  old inline settings panel removed → one design.
- **Daily rewards** (`daily_rewards.gd`) — gold-framed frosted dialog, 4+3
  grid with claimed/current/upcoming/locked tiles, claim burst. Logic
  unchanged.
- **Gameplay HUD** (`hud.gd`) — glass pills/cards/tray; `FeverArt` reworked
  into the full **golden bar** (gold double frame, crown, golden fill +
  glow + sheen, crystal on the edge, x1.5 gold badge). Win/lose/pause
  panels glassed.
- **`asset_library.gd`** — `_OPTIONAL` path table for branding + character
  PNGs (NOT in the 74-asset audit; `tex()` returns null → code fallback
  until the file is dropped at the reserved path).

## Known follow-ups (small, non-blocking)
- Settings Music-row toggle width tightened in code (label 150 + slider 130)
  — verify on next device build.
- PLAY button bevel could be more gold-framed per reference.
- Map top bar chips a touch cramped on narrow widths.
- `_capture.gd` doesn't cover the settings dialog — add a case.
- Character mascot contrast low on the dark board band (character phase).

## NEXT — remaining reference items / Phase 2
1. Real branding PNGs (see §"ASSETS NEEDED" in the report / below).
2. Bottom map nav bar (MAP/EVENTS/CHESTS/SHOP) — reference shows it; only
   MAP exists now.
3. Phase 2 gameplay: `PowerCombiner` recipes, coating/collectible/crate
   obstacles + objectives, migrate board_view/audio onto the event stream.
4. Character/storyline phase (after final character PNGs).

## ASSETS NEEDED FROM USER (unchanged, still pending)
- Company logo PNG · Game logo / wordmark PNG (`assets/branding/wordmark.png`)
- Splash artwork · App icon + adaptive icon (FG/BG) · Feature graphic
- Character pose set (`assets/character/<pose>.png`, ~9 poses)
- Real music loops + SFX (later)
All have reserved `AssetLibrary` paths — drop the PNG in, no code change.

## Do NOT
- Push to origin.
- Rewrite the connect-based core, hex grid, powers, ChainResolver, level
  data, ProgressService, or the event stream.
- Replace the 74 prepared art assets or invent branding/character art.
