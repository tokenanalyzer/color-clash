class_name LevelConfig
extends RefCounted
## Everything about one level: board shape, palette, move limit, objectives,
## obstacles and reward — all data, loaded from data/levels.json. Adding a
## level never requires touching gameplay code.

var id: int
var level_name: String
var width: int
var height: int
var colors: Array[StringName] = []
var move_limit: int
var objectives: Array[Dictionary] = []
var obstacles: Array[Dictionary] = []
var reward_coins: int
var difficulty: String

static func from_dict(d: Dictionary) -> LevelConfig:
	var lc := LevelConfig.new()
	lc.id = int(d["id"])
	lc.level_name = String(d.get("name", "Level %d" % lc.id))
	lc.width = int(d["width"])
	lc.height = int(d["height"])
	for c in d.get("colors", []):
		lc.colors.append(StringName(String(c)))
	lc.move_limit = int(d.get("move_limit", 20))
	for o in d.get("objectives", []):
		lc.objectives.append(o)
	for ob in d.get("obstacles", []):
		lc.obstacles.append(ob)
	lc.reward_coins = int((d.get("reward", {}) as Dictionary).get("coins", 0))
	lc.difficulty = String(d.get("difficulty", "normal"))
	return lc
