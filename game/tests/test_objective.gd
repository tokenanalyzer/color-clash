extends TestCase

func test_clear_color_objective_accumulates() -> void:
	var objectives: Array[Dictionary] = [{"type": "clear_color", "color": "red", "target": 10}]
	var tracker := ObjectiveTracker.new(objectives)
	tracker.apply_move({&"red": 4}, 0, [], [])
	check_eq("progress_after_first_move", tracker.progress[0], 4)
	check("not_complete_yet", not tracker.is_complete())
	tracker.apply_move({&"red": 6}, 0, [], [])
	check_eq("progress_clamped_to_target", tracker.progress[0], 10)
	check("complete_when_target_reached", tracker.is_complete())

func test_reach_score_objective_tracks_running_total() -> void:
	var objectives: Array[Dictionary] = [{"type": "reach_score", "target": 1000}]
	var tracker := ObjectiveTracker.new(objectives)
	tracker.apply_move({}, 400, [], [])
	check_eq("score_progress_reflects_total", tracker.progress[0], 400)
	tracker.apply_move({}, 1200, [], [])
	check_eq("score_progress_clamped_to_target", tracker.progress[0], 1000)
	check("score_objective_complete", tracker.is_complete())

func test_create_powers_objective_counts_matching_type() -> void:
	var objectives: Array[Dictionary] = [{"type": "create_powers", "power": "bomb", "target": 2}]
	var tracker := ObjectiveTracker.new(objectives)
	tracker.apply_move({}, 0, [{"pos": Vector2i.ZERO, "power_id": &"lightning"}], [])
	check_eq("wrong_power_type_not_counted", tracker.progress[0], 0)
	tracker.apply_move({}, 0, [{"pos": Vector2i.ZERO, "power_id": &"bomb"}, {"pos": Vector2i.ONE, "power_id": &"bomb"}], [])
	check_eq("matching_powers_counted", tracker.progress[0], 2)
	check("powers_objective_complete", tracker.is_complete())

func test_break_obstacles_objective_any_type() -> void:
	var objectives: Array[Dictionary] = [{"type": "break_obstacles", "obstacle": "any", "target": 3}]
	var tracker := ObjectiveTracker.new(objectives)
	tracker.apply_move({}, 0, [], [{"pos": Vector2i.ZERO, "obstacle_id": &"ice"}, {"pos": Vector2i.ONE, "obstacle_id": &"stone"}])
	check_eq("any_obstacle_type_counted", tracker.progress[0], 2)

func test_mixed_objectives_require_all_complete() -> void:
	var objectives: Array[Dictionary] = [
		{"type": "clear_color", "color": "red", "target": 5},
		{"type": "clear_color", "color": "blue", "target": 5},
	]
	var tracker := ObjectiveTracker.new(objectives)
	tracker.apply_move({&"red": 5}, 0, [], [])
	check("only_one_objective_complete", not tracker.is_complete())
	tracker.apply_move({&"blue": 5}, 0, [], [])
	check("all_objectives_complete", tracker.is_complete())
