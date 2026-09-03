# Resume point — 2026-09-03 (island map integration)

Local commits today, **NOT pushed**:
- `bf58b3e` / `47fbd72` — Phase 1: typed gameplay event stream + character hooks + data-driven star scores.
- `07deda9` / `36bb282` — reference-matched premium UI (glass kit, settings/daily/HUD, first island map).
- `9875c2c` — **island campaign map from the 15 supplied PNGs** (this pass).

## Island map — what landed (9875c2c)
15 user PNGs in `game/assets/islands/` (Downloads source untouched, descriptive
names). No gameplay logic / save format / progression rules changed —
`IslandModel` is a pure view of `ProgressService`. **645/645 tests pass**
(+`test_island_assets.gd`: 15 ids load, 50 stage faces are valid in-bounds
AtlasTexture regions).

Asset map (identified by artwork, not filename):
| # | Island | Hero | Stages sheet | Map art |
|---|---|---|---|---|
| 1 | Sunlit Falls (Forest) | 05_47_05 | 05_50_06 | 06_27_18 |
| 2 | Frosthaven (Ice) | 05_52_50 | 05_55_52 | 06_30_10 |
| 3 | Volcania (Fire) | 05_58_58 | 06_01_28 | 06_32_38 |
| 4 | Sandoria (Desert) | 06_04_08 | 06_07_56 | 06_35_53 |
| 5 | Aurora Reach (Crystal) | 06_10_04 | 06_20_57 | 06_38_11 |

Each stage sheet = a 5×2 grid of the 10 stage dioramas. Island 2's sheet has
the logo + a 4+6 layout, so its 10 regions are explicit in `islands.json`;
the other four use a uniform grid. The source PNGs are **never cropped or
modified** — `IslandModel.stage_face()` returns a cached `AtlasTexture`
region.

- `IslandModel`: `island_hero_art` / `island_map_art` / `island_stages_sheet`,
  `stage_region_norm`, `stage_face`, `node_position_norm` (serpentine trail,
  data-overridable per island).
- `data/islands.json`: names/subtitles + asset ids + theme + Frosthaven's
  explicit regions. Positions + backgrounds stay data-driven / replaceable.
- `LevelNodeButton`: optional `face_texture` → the stage diorama becomes the
  node (dark pop halo, gold frame, corner number/lock/chest, star ribbon,
  current pulse+crown). Legacy vector node kept as the art-absent fallback.
- `level_map.gd IslandSection`: bg = assembled map art (COVER), glass header
  (name / subtitle / x-10 / lock|play|check badge), 10 positioned diorama
  nodes, soft "travelled" trail, full-island lock overlay when locked.
  KineticScroll + auto-centre unchanged.

## Known polish (non-blocking)
- The supplied map-art PNGs paint the island as a vignette on a dark void,
  so a section's edges read as "space around the island" rather than
  edge-to-edge scenery. Acceptable / on-theme; could zoom+crop harder or
  tint the void if you want it tighter.
- Node density: 10 nodes over ~720px of art → some visual overlap where the
  trail doubles back. Winding + drop shadows keep them tappable.
- The APK is now ~268 MB (15 island PNGs import LOSSLESS). Phase 9 should
  switch `env/*` + `islands/*` to ETC2/ASTC.
- **On-device pass is pending** — the OnePlus test device disconnected
  mid-session. Rebuild+install commands unchanged (`docs/ANDROID.md`);
  APK is at `build/color-clash-debug.apk`.

## NEXT
1. On-device smoke of the island map (scroll, tap a stage, verify state +
   60 FPS + no logcat errors).
2. Optional: wire `IslandModel.island_hero_art(i)` as the in-level backdrop
   for that island's 10 levels (currently the old env cycle).
3. Bottom map nav bar (MAP/EVENTS/CHESTS/SHOP) — reference shows it.
4. Phase 2 gameplay (PowerCombiner, coating/collectible/crate obstacles,
   migrate board_view/audio onto the event stream).
5. Character/storyline phase (after final character PNGs).

## Do NOT
- Push to origin.
- Rewrite the connect-based core, hex grid, powers, ChainResolver, level
  data, ProgressService, the event stream, or IslandModel's pure-view
  contract.
- Crop / modify / replace the supplied island PNGs (stage art is sliced via
  AtlasTexture at runtime).
- Invent branding / character art.
