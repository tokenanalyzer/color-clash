extends TestCase
## Campaign difficulty / move / objective data (Phase A of the gameplay
## overhaul). Validates the real data/levels.json through GameData.levels,
## so a bad generator edit fails CI instead of shipping an unfair campaign.
##
## Fairness contract mirrored from tools/level_gen/generate_levels.py:
##   * move budgets are generous and data-driven, never below the floor
##   * difficulty rises monotonically (difficulty_rank 1..10)
##   * objectives grow single -> double -> triple across the islands
##   * every break_obstacles goal is satisfiable (target <= obstacles placed)
##   * every reach_score goal sits at or below the level's 1-star threshold

const MOVE_FLOOR := 23
const BOSS_STAGES: Array[int] = [10, 20, 30, 40, 50]

func _ids() -> Array:
	return GameData.levels.ordered_ids

func _obstacle_count(level: LevelConfig, kind: String) -> int:
	var n := 0
	for o in level.obstacles:
		if kind == "any" or String(o.get("type", "")) == kind:
			n += 1
	return n

# --------------------------------------------------------------- moves --

func test_level_config_parses_starting_moves() -> void:
	var lc := LevelConfig.from_dict({
		"id": 999, "width": 7, "height": 8, "colors": ["red"],
		"starting_moves": 27, "difficulty_rank": 5, "objectives": [],
	})
	check_eq("starting_moves read from data", lc.starting_moves, 27)
	check_eq("move_limit aliases starting_moves", lc.move_limit, 27)
	check_eq("difficulty_rank read from data", lc.difficulty_rank, 5)

func test_level_config_falls_back_to_move_limit() -> void:
	var lc := LevelConfig.from_dict({
		"id": 998, "width": 7, "height": 8, "colors": ["red"],
		"move_limit": 21, "objectives": [],
	})
	check_eq("legacy move_limit still honoured", lc.starting_moves, 21)

func test_every_level_has_a_fair_move_budget() -> void:
	var worst := 999
	for id in _ids():
		var lv: LevelConfig = GameData.levels.get_level(id)
		worst = mini(worst, lv.starting_moves)
		check("L%d move budget >= floor" % id, lv.starting_moves >= MOVE_FLOOR,
			"L%d has only %d moves" % [id, lv.starting_moves])
		check_eq("L%d starting_moves / move_limit alias" % id, lv.move_limit, lv.starting_moves)
	check("campaign move floor is generous", worst >= MOVE_FLOOR, "worst budget = %d" % worst)

func test_move_counts_are_level_data_driven() -> void:
	var seen := {}
	for id in _ids():
		seen[GameData.levels.get_level(id).starting_moves] = true
	check("move counts vary per level (not a fixed limit)", seen.size() >= 3,
		"only %d distinct move counts" % seen.size())

# ---------------------------------------------------------- difficulty --

func test_difficulty_rank_is_monotonic_and_spans_the_range() -> void:
	var ids := _ids()
	var prev := 0
	var regressed := false
	for id in ids:
		var r: int = GameData.levels.get_level(id).difficulty_rank
		if r < prev:
			regressed = true
		prev = r
	check("difficulty_rank never regresses across the campaign", not regressed)
	check_eq("first stage is rank 1", GameData.levels.get_level(ids[0]).difficulty_rank, 1)
	check_eq("last stage is rank 10", GameData.levels.get_level(ids[-1]).difficulty_rank, 10)

func test_later_islands_have_denser_obstacle_fields() -> void:
	var first_island := 0
	var last_island := 0
	for i in range(0, 10):
		first_island += GameData.levels.get_level(_ids()[i]).obstacles.size()
	for i in range(40, 50):
		last_island += GameData.levels.get_level(_ids()[i]).obstacles.size()
	check("island 5 is more blocked than island 1", last_island > first_island,
		"island1=%d island5=%d obstacles" % [first_island, last_island])

# ---------------------------------------------------------- objectives --

func test_every_level_has_one_to_three_objectives() -> void:
	for id in _ids():
		var n: int = GameData.levels.get_level(id).objectives.size()
		check("L%d objective count in 1..3" % id, n >= 1 and n <= 3, "L%d has %d" % [id, n])

func test_objectives_grow_from_single_to_multi_goal() -> void:
	var early := 0
	var late := 0
	for i in range(0, 10):
		early += GameData.levels.get_level(_ids()[i]).objectives.size()
	for i in range(40, 50):
		late += GameData.levels.get_level(_ids()[i]).objectives.size()
	check("late islands stack more objectives than the first", late > early,
		"island1 goals=%d island5 goals=%d" % [early, late])

func test_break_obstacle_goals_are_always_satisfiable() -> void:
	for id in _ids():
		var lv: LevelConfig = GameData.levels.get_level(id)
		for obj in lv.objectives:
			if String(obj.get("type", "")) != "break_obstacles":
				continue
			var kind := String(obj.get("obstacle", "any"))
			var avail := _obstacle_count(lv, kind)
			var target := int(obj.get("target", 0))
			check("L%d: break %d '%s' vs %d on board" % [id, target, kind, avail],
				target >= 1 and target <= avail,
				"L%d asks for %d but only %d placed" % [id, target, avail])

func test_score_goals_never_exceed_one_star() -> void:
	for id in _ids():
		var lv: LevelConfig = GameData.levels.get_level(id)
		if lv.star_scores.size() < 1:
			continue
		for obj in lv.objectives:
			if String(obj.get("type", "")) != "reach_score":
				continue
			var target := int(obj.get("target", 0))
			check("L%d score goal %d <= 1-star %d" % [id, target, lv.star_scores[0]],
				target <= lv.star_scores[0])

func test_clear_color_goals_use_the_level_palette() -> void:
	for id in _ids():
		var lv: LevelConfig = GameData.levels.get_level(id)
		for obj in lv.objectives:
			if String(obj.get("type", "")) != "clear_color":
				continue
			var col := StringName(String(obj.get("color", "")))
			check("L%d clear_color '%s' is in palette" % [id, col], lv.colors.has(col))

func test_create_powers_targets_stay_modest() -> void:
	for id in _ids():
		var lv: LevelConfig = GameData.levels.get_level(id)
		for obj in lv.objectives:
			if String(obj.get("type", "")) != "create_powers":
				continue
			var target := int(obj.get("target", 0))
			check("L%d create_powers target %d in 1..6" % [id, target], target >= 1 and target <= 6)

# --------------------------------------------------------------- boss --

func test_boss_stages_exist_and_are_non_trivial() -> void:
	for bid in BOSS_STAGES:
		check("boss stage %d exists" % bid, GameData.levels.has_level(bid))
		var lv: LevelConfig = GameData.levels.get_level(bid)
		if lv == null:
			continue
		check("boss stage %d has >= 2 objectives" % bid, lv.objectives.size() >= 2)
		check("boss stage %d has an endurance move budget" % bid, lv.starting_moves >= MOVE_FLOOR)
