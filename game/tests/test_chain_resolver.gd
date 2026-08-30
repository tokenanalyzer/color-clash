extends TestCase

func _power_config() -> PowerConfig:
	return PowerConfig.from_dict({
		"thresholds": [
			{"power": "chain", "min_size": 6},
			{"power": "lightning", "min_size": 5},
			{"power": "bomb", "min_size": 4},
			{"power": "none", "min_size": 3}
		],
		"definitions": {
			"bomb": {"radius": 1, "activation_bonus": 150},
			"lightning": {"activation_bonus": 250},
			"chain": {"activation_bonus": 400},
			"rainbow": {"activation_bonus": 500}
		},
		"base_points_per_piece": 10
	})

func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	return rng

func test_invalid_path_does_not_mutate_board() -> void:
	var board := BoardModel.new(3, 3, 3)
	board.get_cell(Vector2i(0, 0)).color_id = &"red"
	board.get_cell(Vector2i(1, 0)).color_id = &"blue"
	var path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	var result := ChainResolver.resolve_move(board, path, _power_config(), _rng(), [&"red", &"blue"], 0.0)
	check("invalid_path_reported", not result.valid)
	check("board_untouched", board.get_cell(Vector2i(0, 0)).color_id == &"red")

func test_three_match_clears_with_no_power() -> void:
	var board := BoardModel.new(5, 5, 3)
	for x in 5:
		for y in 5:
			board.get_cell(Vector2i(x, y)).color_id = &"blue"
	for pos in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]:
		board.get_cell(pos).color_id = &"red"
	var path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
	var result := ChainResolver.resolve_move(board, path, _power_config(), _rng(), [&"red", &"blue"], 0.0)
	check("valid_three_match", result.valid)
	check_eq("clears_exactly_three", result.cleared_cells.size(), 3)
	check_eq("no_power_created", result.powers_created.size(), 0)
	check_eq("chain_depth_is_one", result.chain_depth, 1)
	check_eq("three_red_counted", int(result.colors_cleared.get(&"red", 0)), 3)

func test_four_match_creates_and_autodetonates_bomb() -> void:
	var board := BoardModel.new(5, 5, 3)
	for x in 5:
		for y in 5:
			board.get_cell(Vector2i(x, y)).color_id = &"blue"
	for pos in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, 1)]:
		board.get_cell(pos).color_id = &"red"
	var path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, 1)]
	var result := ChainResolver.resolve_move(board, path, _power_config(), _rng(), [&"red", &"blue"], 0.0)
	check("valid_four_match", result.valid)
	check_eq("bomb_created_at_release", result.powers_created.size(), 1)
	check_eq("bomb_power_id", String(result.powers_created[0]["power_id"]), "bomb")
	check_eq("bomb_auto_activated", result.powers_activated.size(), 1)
	check_eq("chain_depth_two_waves", result.chain_depth, 2)
	check_eq("ten_cells_cleared_total", result.cleared_cells.size(), 10)
	check_eq("bomb_bonus_in_second_wave", int(result.score_events[1]["power_bonus"]), 150)
	check_eq("board_refilled_all_cleared_cells", result.refilled_cells.size(), 10)
	check_eq("wave_cells_has_two_waves", result.wave_cells.size(), 2)
	check_eq("wave0_touched_three_path_cells", (result.wave_cells[0] as Array).size(), 3)
	# wave_cells lists every cell the bomb's blast radius touched (9: itself
	# + 8 neighbors), including two that wave0 already cleared — unlike
	# score_events' "cells" count, wave_cells is for view/audio staging and
	# intentionally doesn't dedupe against earlier waves.
	check_eq("wave1_touched_full_blast_radius", (result.wave_cells[1] as Array).size(), 9)
	var wave1: Array = result.wave_cells[1]
	check("wave1_includes_bomb_origin", wave1.has(Vector2i(2, 1)))

func test_detonate_power_at_scores_same_chain_depth_as_a_matched_power() -> void:
	# A booster-triggered detonation and a player match that creates then
	# auto-detonates the same power must both read as "one wave, one
	# activation" (chain_depth 2) -- otherwise boosters would never build
	# Combo/Fever the way an equivalent match does.
	var board := BoardModel.new(5, 5, 3)
	for x in 5:
		for y in 5:
			board.get_cell(Vector2i(x, y)).color_id = &"blue"
	var result := ChainResolver.detonate_power_at(board, Vector2i(2, 2), &"bomb", _power_config(), _rng(), [&"red", &"blue"], 0.0)
	check("detonate_power_at_valid", result.valid)
	check_eq("booster_detonation_chain_depth_matches_match_triggered", result.chain_depth, 2)

func test_stone_only_clears_via_power_not_plain_match() -> void:
	var board := BoardModel.new(5, 5, 3)
	for x in 5:
		for y in 5:
			board.get_cell(Vector2i(x, y)).color_id = &"blue"
	for pos in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, 1)]:
		board.get_cell(pos).color_id = &"red"
	board.set_obstacle(Vector2i(1, 1), &"stone", 0) # inside the future bomb's blast radius
	var path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, 1)]
	var result := ChainResolver.resolve_move(board, path, _power_config(), _rng(), [&"red", &"blue"], 0.0)
	check_eq("stone_broken_by_bomb_blast", result.obstacles_broken.size(), 1)
	check_eq("stone_break_type", String(result.obstacles_broken[0]["obstacle_id"]), "stone")
	check("stone_no_longer_present", not board.get_cell(Vector2i(1, 1)).is_stone())

func test_ice_cracks_from_bomb_blast_without_fully_breaking() -> void:
	var board := BoardModel.new(5, 5, 3)
	for x in 5:
		for y in 5:
			board.get_cell(Vector2i(x, y)).color_id = &"blue"
	for pos in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, 1)]:
		board.get_cell(pos).color_id = &"red"
	board.set_obstacle(Vector2i(1, 1), &"ice", 2)
	var path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, 1)]
	var result := ChainResolver.resolve_move(board, path, _power_config(), _rng(), [&"red", &"blue"], 0.0)
	check_eq("ice_not_yet_broken_after_one_hit", result.obstacles_broken.size(), 0)
	check("ice_piece_still_cleared_underneath", not board.get_cell(Vector2i(1, 1)).has_power())
	check_eq("ice_hp_reduced", board.get_cell(Vector2i(1, 1)).obstacle_hp, 1)

func test_rainbow_wildcard_in_path_resolves_to_group_color() -> void:
	var board := BoardModel.new(5, 5, 3)
	for x in 5:
		for y in 5:
			board.get_cell(Vector2i(x, y)).color_id = &"blue"
	board.get_cell(Vector2i(0, 0)).color_id = &"red"
	board.get_cell(Vector2i(1, 0)).color_id = BoardModel.RAINBOW_COLOR_ID
	board.get_cell(Vector2i(2, 0)).color_id = &"red"
	var path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
	var result := ChainResolver.resolve_move(board, path, _power_config(), _rng(), [&"red", &"blue"], 0.0)
	check("valid_with_rainbow_wildcard", result.valid)
	check_eq("two_red_plus_rainbow_counted_as_red", int(result.colors_cleared.get(&"red", 0)), 2)
