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
	{"name": "Sunlit Falls", "theme": "env_floating_islands"},
	{"name": "Crystal Caves", "theme": "env_crystal_formations"},
	{"name": "Lava Peaks", "theme": "env_large_structures"},
	{"name": "Cloud Spires", "theme": "env_clouds_mists"},
	{"name": "Aurora Reach", "theme": "env_aurora_energy_bands"},
	{"name": "Starfall Vault", "theme": "env_energy_crystals"},
]

static var _meta: Array = []

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

## AssetLibrary env id used as this island's backdrop scene.
static func island_theme(island_idx: int) -> StringName:
	_ensure_meta()
	if island_idx >= 0 and island_idx < _meta.size():
		return StringName(String(_meta[island_idx].get("theme", "env_main_background")))
	return &"env_main_background"

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
