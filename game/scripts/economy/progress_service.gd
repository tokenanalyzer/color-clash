extends Node
## Autoload "Progress". Campaign progression: which levels are completed,
## their star rating/best score, and which levels are unlocked. Local-only
## and offline-first, like the rest of the economy — persisted through
## SaveService, no server round-trip required to play.

signal level_completed(level_id: int, stars: int)

var _entries: Dictionary = {} # str(level_id) -> {"stars": int, "best_score": int}

func _ready() -> void:
	_entries = SaveService.get_value("level_progress", {})

func is_completed(level_id: int) -> bool:
	return _entries.has(str(level_id))

func get_stars(level_id: int) -> int:
	var e: Dictionary = _entries.get(str(level_id), {})
	return int(e.get("stars", 0))

func get_best_score(level_id: int) -> int:
	var e: Dictionary = _entries.get(str(level_id), {})
	return int(e.get("best_score", 0))

## A level is unlocked if it's the first level in the campaign, or the
## previous level (by campaign order) has been completed.
func is_unlocked(level_id: int) -> bool:
	var first_id := GameData.levels.first_level_id()
	if level_id == first_id:
		return true
	var prev_id := _previous_level_id(level_id)
	return prev_id != -1 and is_completed(prev_id)

## Records (or improves) a level's result. Stars/best_score only ever go up.
func record_completion(level_id: int, stars: int, score: int) -> void:
	var key := str(level_id)
	var existing: Dictionary = _entries.get(key, {"stars": 0, "best_score": 0})
	var new_stars: int = max(int(existing.get("stars", 0)), stars)
	var new_score: int = max(int(existing.get("best_score", 0)), score)
	_entries[key] = {"stars": new_stars, "best_score": new_score}
	SaveService.set_value("level_progress", _entries)
	SaveService.save()
	level_completed.emit(level_id, new_stars)

## The furthest level the player can currently play — the first unlocked,
## not-yet-completed level, or the last unlocked level if the whole
## campaign so far is complete.
func current_level_id() -> int:
	var last_unlocked := GameData.levels.first_level_id()
	for id in GameData.levels.ordered_ids:
		if not is_unlocked(id):
			break
		last_unlocked = id
		if not is_completed(id):
			return id
	return last_unlocked

func _previous_level_id(level_id: int) -> int:
	var ids: Array[int] = GameData.levels.ordered_ids
	var idx := ids.find(level_id)
	if idx <= 0:
		return -1
	return ids[idx - 1]
