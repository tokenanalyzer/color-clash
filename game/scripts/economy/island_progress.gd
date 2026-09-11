extends Node
## Autoload "IslandProgress" — per-ISLAND independent level progression for the
## island map (2026-09-08 correction pass).
##
## Each of the 10 islands has its OWN sequential run of LEVELS_PER_ISLAND
## world-local levels (100 now, the constant is the only limit — raise it
## freely later). Rules:
##   * Island 1 is unlocked from the start; islands 2..10 start LOCKED.
##   * Completing island i level N unlocks island i level N+1.
##   * Completing island i level LEVELS_PER_ISLAND unlocks island i+1
##     (its level 1 then becomes the current level).
##   * Nothing else unlocks another island — completing island 1 level 10 does
##     NOT touch island 2 (this was the bug being fixed).
##
## Identity is (worldId, worldLocalLevel) and is kept fully separate from the
## authored campaign level a slot happens to load (WorldCatalog.authored_level_id)
## and from the visual part template (WorldCatalog.part_index). This service is
## ADDITIVE — the campaign `Progress` autoload is untouched.
##
## Extensibility: `force_unlock_island()` is a hook for future key / achievement
## / reward unlocks. It is deliberately not wired to any mechanic yet.

signal level_completed(world_id: StringName, local_level: int, stars: int)
signal island_unlocked(world_id: StringName)

const LEVELS_PER_ISLAND := 100
const SAVE_KEY := "island_progress"

# world_id(str) -> { "levels": { "<n>": {"stars":int,"best_score":int} },
#                    "forced_unlock": bool }
var _data: Dictionary = {}

func _ready() -> void:
	_data = SaveService.get_value(SAVE_KEY, {})
	if typeof(_data) != TYPE_DICTIONARY:
		_data = {}

func _bucket(world_id) -> Dictionary:
	var k := String(world_id)
	if not _data.has(k):
		_data[k] = {"levels": {}}
	if not _data[k].has("levels"):
		_data[k]["levels"] = {}
	return _data[k]

func _order(world_id) -> int:
	return int(WorldCatalog.world(world_id).get("order", 1))

# ------------------------------------------------------------- queries --

func is_level_completed(world_id, local_level: int) -> bool:
	return _bucket(world_id)["levels"].has(str(local_level))

func get_stars(world_id, local_level: int) -> int:
	return int(_bucket(world_id)["levels"].get(str(local_level), {}).get("stars", 0))

func get_best_score(world_id, local_level: int) -> int:
	return int(_bucket(world_id)["levels"].get(str(local_level), {}).get("best_score", 0))

func completed_count(world_id) -> int:
	return _bucket(world_id)["levels"].size()

func is_island_complete(world_id) -> bool:
	return completed_count(world_id) >= LEVELS_PER_ISLAND

## Island 1 is always open; island k opens once island k-1's last level is
## done (or a special force-unlock has been granted).
func is_island_unlocked(world_id) -> bool:
	var o := _order(world_id)
	if o <= 1:
		return true
	if bool(_bucket(world_id).get("forced_unlock", false)):
		return true
	var prev_id := WorldCatalog.world_id_at(o - 2)
	return prev_id != &"" and is_level_completed(prev_id, LEVELS_PER_ISLAND)

## A world-local level is unlocked iff its island is open AND it is level 1 or
## the previous level of the SAME island is completed.
func is_level_unlocked(world_id, local_level: int) -> bool:
	if local_level < 1 or local_level > LEVELS_PER_ISLAND:
		return false
	if not is_island_unlocked(world_id):
		return false
	if local_level == 1:
		return true
	return is_level_completed(world_id, local_level - 1)

## The first not-yet-cleared level of this island (1..LEVELS_PER_ISLAND).
func current_level(world_id) -> int:
	if not is_island_unlocked(world_id):
		return 1
	for n in range(1, LEVELS_PER_ISLAND + 1):
		if not is_level_completed(world_id, n):
			return n
	return LEVELS_PER_ISLAND

## "locked" | "current" | "complete" — for a world card.
func island_state(world_id) -> StringName:
	if not is_island_unlocked(world_id):
		return &"locked"
	if is_island_complete(world_id):
		return &"complete"
	return &"current"

## "locked" | "unlocked" | "current" | "completed" — for one map node.
func node_state(world_id, local_level: int) -> StringName:
	if not is_level_unlocked(world_id, local_level):
		return &"locked"
	if is_level_completed(world_id, local_level):
		return &"completed"
	if local_level == current_level(world_id):
		return &"current"
	return &"unlocked"

# ------------------------------------------------------------- writes --

## Records (or improves) a world-local level result. Stars / best score only
## ever go up. Emits `level_completed`, and `island_unlocked` for the NEXT
## island when this was the final level of the current one.
func record_completion(world_id, local_level: int, stars: int, score: int) -> void:
	if local_level < 1 or local_level > LEVELS_PER_ISLAND:
		return
	var b := _bucket(world_id)
	var lv: Dictionary = b["levels"]
	var key := str(local_level)
	var ex: Dictionary = lv.get(key, {"stars": 0, "best_score": 0})
	var was_complete := is_island_complete(world_id)
	lv[key] = {
		"stars": maxi(int(ex.get("stars", 0)), stars),
		"best_score": maxi(int(ex.get("best_score", 0)), score),
	}
	SaveService.set_value(SAVE_KEY, _data)
	SaveService.save()
	level_completed.emit(StringName(String(world_id)), local_level, int(lv[key]["stars"]))
	if local_level == LEVELS_PER_ISLAND and not was_complete:
		var next_id := WorldCatalog.world_id_at(_order(world_id))   # order o -> index o == next island
		if next_id != &"":
			island_unlocked.emit(next_id)

## Future special-unlock hook (keys / achievements / rewards). Not used yet.
func force_unlock_island(world_id) -> void:
	_bucket(world_id)["forced_unlock"] = true
	SaveService.set_value(SAVE_KEY, _data)
	SaveService.save()
	island_unlocked.emit(StringName(String(world_id)))

## Test / debug helper — wipes all island progression.
func reset() -> void:
	_data = {}
	SaveService.set_value(SAVE_KEY, {})
	SaveService.save()
