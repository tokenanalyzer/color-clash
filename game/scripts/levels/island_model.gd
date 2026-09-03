class_name IslandModel
extends RefCounted
## Groups the flat campaign (GameData.levels) into islands of exactly
## LEVELS_PER_ISLAND stages for the scrollable island map. This is a pure
## VIEW-of the existing data — it adds NO new save state and does NOT change
## unlock rules. An island is "unlocked" iff its first level is unlocked
## under the existing ProgressService sequential rule, which already means
## "the previous island's last level is complete".
##
## Island names / background themes are data-driven (data/islands.json) with
## a code fallback so the map always renders.

const LEVELS_PER_ISLAND := 10

const _FALLBACK := [
	{"name": "Sunlit Falls", "subtitle": "Forest Kingdom", "theme": "env_floating_islands", "hero": "island1_hero", "stages": "island1_stages", "map": "island1_map"},
	{"name": "Frosthaven", "subtitle": "Ice Kingdom", "theme": "env_crystal_formations", "hero": "island2_hero", "stages": "island2_stages", "map": "island2_map"},
	{"name": "Volcania", "subtitle": "Fire Kingdom", "theme": "env_large_structures", "hero": "island3_hero", "stages": "island3_stages", "map": "island3_map"},
	{"name": "Sandoria", "subtitle": "Desert Kingdom", "theme": "env_clouds_mists", "hero": "island4_hero", "stages": "island4_stages", "map": "island4_map"},
	{"name": "Aurora Reach", "subtitle": "Crystal Kingdom", "theme": "env_aurora_energy_bands", "hero": "island5_hero", "stages": "island5_stages", "map": "island5_map"},
]

static var _meta: Array = []
static var _atlas_cache: Dictionary = {}   # "isl_stg" -> AtlasTexture

static func _ensure_meta() -> void:
	if not _meta.is_empty():
		return
	var data := JsonLoader.load_json("res://data/islands.json")
	var list: Array = data.get("islands", [])
	if list.is_empty():
		_meta = _FALLBACK.duplicate(true)
	else:
		_meta = list

static func _ordered_ids() -> Array:
	return GameData.levels.ordered_ids

static func island_count() -> int:
	var n: int = _ordered_ids().size()
	return int(ceil(float(max(n, 1)) / float(LEVELS_PER_ISLAND)))

## 0-based island index for a level id (by campaign order, not raw id).
static func island_index_for_level(level_id: int) -> int:
	var idx: int = _ordered_ids().find(level_id)
	if idx < 0:
		return 0
	return idx / LEVELS_PER_ISLAND

static func level_ids_for_island(island_idx: int) -> Array[int]:
	var out: Array[int] = []
	var ids: Array = _ordered_ids()
	var start := island_idx * LEVELS_PER_ISLAND
	for i in range(start, min(start + LEVELS_PER_ISLAND, ids.size())):
		out.append(int(ids[i]))
	return out

static func island_name(island_idx: int) -> String:
	_ensure_meta()
	if island_idx >= 0 and island_idx < _meta.size():
		return String(_meta[island_idx].get("name", "Island %d" % (island_idx + 1)))
	return "Island %d" % (island_idx + 1)

static func island_subtitle(island_idx: int) -> String:
	_ensure_meta()
	if island_idx >= 0 and island_idx < _meta.size():
		return String(_meta[island_idx].get("subtitle", ""))
	return ""

static func _entry(island_idx: int) -> Dictionary:
	_ensure_meta()
	if island_idx >= 0 and island_idx < _meta.size():
		return _meta[island_idx]
	return {}

## AssetLibrary env id used as this island's in-level backdrop scene.
static func island_theme(island_idx: int) -> StringName:
	return StringName(String(_entry(island_idx).get("theme", "env_main_background")))

## Full island scene + name banner (in-level backdrop / island intro).
static func island_hero_art(island_idx: int) -> Texture2D:
	return AssetLibrary.tex(StringName(String(_entry(island_idx).get("hero", ""))))

## Assembled island map scene used as the map section background.
static func island_map_art(island_idx: int) -> Texture2D:
	return AssetLibrary.tex(StringName(String(_entry(island_idx).get("map", ""))))

## The 5x2 sheet of the 10 stage dioramas.
static func island_stages_sheet(island_idx: int) -> Texture2D:
	return AssetLibrary.tex(StringName(String(_entry(island_idx).get("stages", ""))))

## Normalized (0..1) region of the stages sheet for one stage (0-based).
## Uses the island's explicit `stage_regions` when present, else a uniform
## 5x2 grid whose cell keeps the top ~66% (the diorama, minus the baked badge).
static func stage_region_norm(island_idx: int, stage_idx: int) -> Rect2:
	var regs: Array = _entry(island_idx).get("stage_regions", [])
	if stage_idx >= 0 and stage_idx < regs.size():
		var r: Array = regs[stage_idx]
		return Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	var col := stage_idx % 5
	var row := stage_idx / 5
	return Rect2(float(col) * 0.2 + 0.006, float(row) * 0.5 + 0.012, 0.188, 0.318)

## An AtlasTexture of the stage diorama — the source sheet PNG is never
## modified or cropped on disk; this just references a sub-rect of it. null
## when the sheet is missing. Cached for the process lifetime.
static func stage_face(island_idx: int, stage_idx: int) -> Texture2D:
	var key := "%d_%d" % [island_idx, stage_idx]
	if _atlas_cache.has(key):
		return _atlas_cache[key]
	var sheet := island_stages_sheet(island_idx)
	var result: Texture2D = null
	if sheet != null:
		var n := stage_region_norm(island_idx, stage_idx)
		var at := AtlasTexture.new()
		at.atlas = sheet
		at.region = Rect2(n.position.x * sheet.get_width(), n.position.y * sheet.get_height(),
			n.size.x * sheet.get_width(), n.size.y * sheet.get_height())
		at.filter_clip = true
		result = at
	_atlas_cache[key] = result
	return result

## Normalized (0..1) position of a stage node within its map section. Uses
## the island's explicit `node_positions` when present, else a procedural
## serpentine that flows from a bottom-centre "entrance" (stage 1) up to a
## top-centre "summit" (stage 10) — the shape every supplied map reference
## follows. `count` is how many stages the island has (usually 10).
static func node_position_norm(island_idx: int, stage_idx: int, count: int = 10) -> Vector2:
	var pts: Array = _entry(island_idx).get("node_positions", [])
	if stage_idx >= 0 and stage_idx < pts.size():
		var p: Array = pts[stage_idx]
		return Vector2(float(p[0]), float(p[1]))
	var t := 0.0 if count <= 1 else float(stage_idx) / float(count - 1)
	# bottom (t=0) -> top (t=1); a calm serpentine that keeps adjacent nodes
	# well separated. Ends ease toward centre so 1 sits by the "entrance" and
	# 10 by the "summit", matching every supplied map reference.
	var y := lerpf(0.90, 0.08, t)
	var phase := float(island_idx) * 1.3
	# enough winding that vertically-adjacent nodes are always offset sideways
	var sway := sin(t * PI * 2.4 + phase)
	var envelope := 0.5 + 0.5 * sin(t * PI)            # narrower near the ends
	var x := 0.5 + 0.32 * sway * envelope
	return Vector2(clampf(x, 0.13, 0.87), y)

## Unlocked iff the island's first level is unlocked (existing sequential rule).
static func is_island_unlocked(island_idx: int) -> bool:
	var ids := level_ids_for_island(island_idx)
	return not ids.is_empty() and Progress.is_unlocked(ids[0])

static func island_completed_count(island_idx: int) -> int:
	var n := 0
	for lid in level_ids_for_island(island_idx):
		if Progress.is_completed(lid):
			n += 1
	return n

static func island_total(island_idx: int) -> int:
	return level_ids_for_island(island_idx).size()

static func is_island_complete(island_idx: int) -> bool:
	var total := island_total(island_idx)
	return total > 0 and island_completed_count(island_idx) >= total

## "complete" | "current" | "locked" — drives the island header styling.
static func island_state(island_idx: int) -> StringName:
	if not is_island_unlocked(island_idx):
		return &"locked"
	if is_island_complete(island_idx):
		return &"complete"
	return &"current"

static func current_island_index() -> int:
	return island_index_for_level(Progress.current_level_id())

## Total stars earned across an island (for its header).
static func island_stars(island_idx: int) -> int:
	var s := 0
	for lid in level_ids_for_island(island_idx):
		s += Progress.get_stars(lid)
	return s
