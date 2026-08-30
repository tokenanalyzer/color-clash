class_name LevelDatabase
extends RefCounted
## In-memory registry of every LevelConfig, loaded from data/levels.json.
## Scales to hundreds of levels without any code change — see
## tools/level_gen/generate_levels.py for the authoring workflow.

var _levels: Dictionary = {} # int -> LevelConfig
var ordered_ids: Array[int] = []

static func from_dict(data: Dictionary) -> LevelDatabase:
	var db := LevelDatabase.new()
	for entry in data.get("levels", []):
		var lc := LevelConfig.from_dict(entry)
		db._levels[lc.id] = lc
		db.ordered_ids.append(lc.id)
	db.ordered_ids.sort()
	return db

func get_level(id: int) -> LevelConfig:
	return _levels.get(id, null)

func has_level(id: int) -> bool:
	return _levels.has(id)

func count() -> int:
	return ordered_ids.size()

func first_level_id() -> int:
	return ordered_ids[0] if ordered_ids.size() > 0 else -1

func next_level_id(current: int) -> int:
	var idx := ordered_ids.find(current)
	if idx == -1 or idx + 1 >= ordered_ids.size():
		return -1
	return ordered_ids[idx + 1]
