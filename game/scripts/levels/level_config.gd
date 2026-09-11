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
## Move budget for the level. `starting_moves` is the canonical data key
## (data/levels.json); `move_limit` is kept as an identical alias so every
## existing consumer and any older saved data keeps working unchanged.
var move_limit: int
var starting_moves: int
## Monotonic 1..10 difficulty index across the campaign — surfaced for
## enemy-strength / reward scaling. Data-driven per level, never a global.
var difficulty_rank: int = 1
var objectives: Array[Dictionary] = []
var obstacles: Array[Dictionary] = []
## Escort specials seated on the board at level start: [{x, y, type}].
## `type` is currently always "relic" (the Love Crystal).
var specials: Array[Dictionary] = []
## AssetLibrary env id for this level's in-level backdrop. Empty -> the
## backdrop falls back to its per-island / per-band default.
var env: StringName = &""
var reward_coins: int
var difficulty: String
## Ascending score thresholds [s1, s2, s3] for the 1/2/3-star rating. Empty
## when the level doesn't define them — StarRating then falls back to
## move-efficiency. Data-driven per level (data/levels.json), never a global.
var star_scores: Array[int] = []
## Optional one-line coaching shown when the level opens (mechanic teaching).
var hint: String = ""

static func from_dict(d: Dictionary) -> LevelConfig:
	var lc := LevelConfig.new()
	lc.id = int(d["id"])
	lc.level_name = String(d.get("name", "Level %d" % lc.id))
	lc.width = int(d["width"])
	lc.height = int(d["height"])
	for c in d.get("colors", []):
		lc.colors.append(StringName(String(c)))
	lc.move_limit = int(d.get("starting_moves", d.get("move_limit", 20)))
	lc.starting_moves = lc.move_limit
	lc.difficulty_rank = int(d.get("difficulty_rank", 1))
	for o in d.get("objectives", []):
		lc.objectives.append(o)
	for ob in d.get("obstacles", []):
		lc.obstacles.append(ob)
	for sp in d.get("specials", []):
		lc.specials.append(sp)
	lc.env = StringName(String(d.get("env", "")))
	lc.reward_coins = int((d.get("reward", {}) as Dictionary).get("coins", 0))
	lc.difficulty = String(d.get("difficulty", "normal"))
	for s in d.get("star_scores", []):
		lc.star_scores.append(int(s))
	lc.hint = String(d.get("hint", d.get("intro_hint", "")))
	return lc
