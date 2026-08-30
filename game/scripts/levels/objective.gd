class_name ObjectiveTracker
extends RefCounted
## Evaluates a level's data-driven objectives against running match stats.
## Supported types: clear_color, reach_score, create_powers, break_obstacles.
## A level with multiple objectives requires ALL of them complete (mixed
## objectives), matching docs/GAME_DESIGN.md.

var objectives: Array[Dictionary] = []
var progress: Array[int] = []

func _init(p_objectives: Array[Dictionary]) -> void:
	objectives = p_objectives
	progress.resize(objectives.size())
	for i in progress.size():
		progress[i] = 0

func target_for(index: int) -> int:
	return int(objectives[index].get("target", 0))

func is_complete() -> bool:
	for i in objectives.size():
		if progress[i] < target_for(i):
			return false
	return true

## Feeds one resolved move's stats into every objective's progress.
func apply_move(colors_cleared: Dictionary, total_score: int, powers_created: Array[Dictionary], obstacles_broken: Array[Dictionary]) -> void:
	for i in objectives.size():
		var obj: Dictionary = objectives[i]
		match String(obj.get("type", "")):
			"clear_color":
				var color := StringName(String(obj.get("color", "")))
				progress[i] += int(colors_cleared.get(color, 0))
			"reach_score":
				progress[i] = total_score
			"create_powers":
				var wanted := String(obj.get("power", "any"))
				for p in powers_created:
					if wanted == "any" or String(p["power_id"]) == wanted:
						progress[i] += 1
			"break_obstacles":
				var wanted_obs := String(obj.get("obstacle", "any"))
				for o in obstacles_broken:
					if wanted_obs == "any" or String(o["obstacle_id"]) == wanted_obs:
						progress[i] += 1
			_:
				pass
		progress[i] = min(progress[i], target_for(i))
