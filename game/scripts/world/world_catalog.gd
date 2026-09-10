class_name WorldCatalog
extends RefCounted
## WORLD DATA layer for the 10-world island system (2026-09-08).
##
## Pure, static, data-driven read model over `res://data/worlds.json`. Holds
## NO save state and defines NO new progression — worlds 1-5 route straight
## onto the existing 50 campaign levels through IslandModel / ProgressService
## (world `order` k  <->  island index k-1), and worlds 6-10 (`playable:false`)
## have no authored gameplay, so their internal map opens COMING SOON with
## every node locked and no routing.
##
## The five `parts` per world are REUSABLE VISUAL TEMPLATES, cycled by
## `part_index(localLevel) = (localLevel - 1) % 5`. They are not five levels.
## The logical level id is always kept separate from the visual part index.

const _PATH := "res://data/worlds.json"
const PARTS_PER_WORLD := 5

static var _data: Dictionary = {}
static var _tex_cache: Dictionary = {}

static func _catalog() -> Dictionary:
	if _data.is_empty():
		_data = JsonLoader.load_json(_PATH)
	return _data

## Ordered list of raw world dictionaries (order 1..10).
static func worlds() -> Array:
	var list: Array = _catalog().get("worlds", [])
	return list

static func count() -> int:
	return worlds().size()

## World dict by string id, or {} if unknown.
static func world(id: StringName) -> Dictionary:
	for w in worlds():
		if String(w.get("id", "")) == String(id):
			return w
	return {}

## World dict by 1-based `order`, or {} if out of range.
static func world_by_order(order: int) -> Dictionary:
	for w in worlds():
		if int(w.get("order", -1)) == order:
			return w
	return {}

static func world_id_at(idx: int) -> StringName:
	var list := worlds()
	if idx < 0 or idx >= list.size():
		return &""
	return StringName(String(list[idx].get("id", "")))

# ---------------------------------------------------------------- assets --

static func board_asset_path() -> String:
	return String(_catalog().get("board_asset", ""))

static func sea_clip_path() -> String:
	return String(_catalog().get("sea_clip", ""))

static func _tex(path: String) -> Texture2D:
	if path == "":
		return null
	if _tex_cache.has(path):
		return _tex_cache[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		var res := load(path)
		if res is Texture2D:
			t = res
	_tex_cache[path] = t
	return t

## The big main-island artwork for the world-selection screen (or null).
static func main_island_texture(id: StringName) -> Texture2D:
	return _tex(String(world(id).get("main_asset", "")))

## The reusable wooden level-board PNG shared by every node (or null).
static func board_texture() -> Texture2D:
	return _tex(board_asset_path())

## 0-based visual template index for a 1-based world-local level number.
## Level 1->0, 2->1, ... 5->4, 6->0, 7->1, ...  (localLevel - 1) % 5.
static func part_index(local_level: int) -> int:
	return (maxi(local_level, 1) - 1) % PARTS_PER_WORLD

## Resolved part texture for a world-local level (cycled), or null.
static func part_texture(id: StringName, local_level: int) -> Texture2D:
	var parts: Array = world(id).get("parts", [])
	if parts.is_empty():
		return null
	return _tex(String(parts[part_index(local_level)]))

## All five part paths for a world (order 1..5), in declaration order.
static func part_paths(id: StringName) -> Array:
	return world(id).get("parts", []).duplicate()

# ----------------------------------------------------- layout / zig-zag --

## Deterministic side for a 1-based level index: 1->LEFT, 2->RIGHT, 3->LEFT...
## Returns -1 for LEFT, +1 for RIGHT so callers multiply an x-offset by it.
static func zigzag_side(level_index: int) -> int:
	return -1 if (level_index % 2) == 1 else 1

static func is_left(level_index: int) -> bool:
	return zigzag_side(level_index) < 0

# ----------------------------------------- authored-gameplay resolution --
## The island map's (worldId, worldLocalLevel) identity is INDEPENDENT of the
## authored campaign level a slot loads. Each world has an ordered pool of
## authored levels; a world-local level picks from it by
## `(localLevel - 1) % pool.size()`, so every slot up to LEVELS_PER_ISLAND is
## always playable by reusing an authored level — no procedural / fake levels,
## and the existing 50 authored levels are never modified. When real authored
## data for a specific slot is added later, `_authored_pool` is where it wires
## in.

## Ordered authored campaign level ids this world draws its gameplay from.
## Worlds 1-5 use their declared `campaign_span` band (10 levels); worlds
## without a band fall back to the whole authored campaign.
static func _authored_pool(id: StringName) -> Array:
	var span = world(id).get("campaign_span", null)
	var ids: Array = GameData.levels.ordered_ids
	if span is Array and span.size() == 2:
		var out: Array = []
		for lid in ids:
			if int(lid) >= int(span[0]) and int(lid) <= int(span[1]):
				out.append(int(lid))
		if not out.is_empty():
			return out
	var all: Array = []
	for lid in ids:
		all.append(int(lid))
	return all

## Authored campaign LevelConfig id to load for a world-local level, or -1 if
## the campaign has no levels at all.
static func authored_level_id(id: StringName, local_level: int) -> int:
	var pool := _authored_pool(id)
	if pool.is_empty():
		return -1
	return int(pool[(maxi(local_level, 1) - 1) % pool.size()])

## Highest world-local level this world exposes (extensible — bump the
## IslandProgress constant, nothing here).
static func levels_per_world() -> int:
	return IslandProgress.LEVELS_PER_ISLAND

# ------------------------------------------------------------- state --
## All of the following delegate to IslandProgress — the per-island
## sequential progression is the single source of truth.

## "locked" | "current" | "complete" for a world card.
static func world_state(id: StringName) -> StringName:
	if world(id).is_empty():
		return &"locked"
	return IslandProgress.island_state(id)

static func is_island_unlocked(id: StringName) -> bool:
	return IslandProgress.is_island_unlocked(id)

## "locked" | "unlocked" | "current" | "completed" for one map node.
static func node_state(id: StringName, local_level: int) -> StringName:
	return IslandProgress.node_state(id, local_level)

static func node_stars(id: StringName, local_level: int) -> int:
	return IslandProgress.get_stars(id, local_level)

static func is_level_unlocked(id: StringName, local_level: int) -> bool:
	return IslandProgress.is_level_unlocked(id, local_level)

## World-local level the player is dropped at when opening this world's map.
static func focus_local_level(id: StringName) -> int:
	return IslandProgress.current_level(id)

## Progress summary for a world card, e.g. "17 / 100", or "LOCKED".
static func world_progress_text(id: StringName) -> String:
	if not IslandProgress.is_island_unlocked(id):
		return "LOCKED"
	return "%d / %d" % [IslandProgress.completed_count(id), IslandProgress.LEVELS_PER_ISLAND]

## Display name of the island that must be cleared to unlock this one ("" for
## island 1). Used by the "locked" toast on the world-selection screen.
static func prerequisite_name(id: StringName) -> String:
	var o := int(world(id).get("order", 1))
	if o <= 1:
		return ""
	var prev := world_by_order(o - 1)
	return String(prev.get("display_name", ""))
