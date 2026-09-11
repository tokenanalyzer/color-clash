extends TestCase

func test_combo_multiplier_grows_with_depth() -> void:
	check_eq("depth_one_no_bonus", ScoreCalculator.combo_multiplier_for_depth(1, 0.35), 1.0)
	check_eq("depth_three_bonus", ScoreCalculator.combo_multiplier_for_depth(3, 0.35), 1.7)

func test_compute_move_score_applies_multipliers() -> void:
	var power_config := PowerConfig.from_dict({
		"thresholds": [{"power": "none", "min_size": 3}],
		"definitions": {},
		"base_points_per_piece": 10
	})
	var move_result := ChainResolver.MoveResult.new()
	move_result.score_events = [{"cells": 4, "power_bonus": 0}, {"cells": 3, "power_bonus": 150}]
	# (4*10 + 0) + (3*10 + 150) = 40 + 180 = 220
	var score := ScoreCalculator.compute_move_score(move_result, power_config, 1.0, 1.0)
	check_eq("base_score_no_multipliers", score, 220)

	var boosted := ScoreCalculator.compute_move_score(move_result, power_config, 2.0, 1.5)
	check_eq("score_scales_with_combo_and_fever", boosted, int(round(220.0 * 2.0 * 1.5)))
