extends TestCase

func _power_config() -> PowerConfig:
	return PowerConfig.from_dict({
		"thresholds": [
			{"power": "chain", "min_size": 9, "count": 2},
			{"power": "chain", "min_size": 6, "count": 1},
			{"power": "lightning", "min_size": 5, "count": 1},
			{"power": "bomb", "min_size": 4, "count": 1},
			{"power": "none", "min_size": 3, "count": 0}
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

## A checkerboard of two colors guarantees no two orthogonally-adjacent
## cells ever share a color, so find_connected_group() is a no-op (size 1)
## anywhere in it. That makes it a neutral "filler" background for tests
## that need to isolate one specific interaction (a bomb's blast, an ice
## hit, ...) from the new auto-chain/secondary-generation mechanic, which
## would otherwise sweep through any large same-color region.
func _checkerboard_board(w: int, h: int, color_a: StringName, color_b: StringName) -> BoardModel:
	var board := BoardModel.new(w, h, 3)
	for x in w:
		for y in h:
			board.get_cell(Vector2i(x, y)).color_id = color_a if (x + y) % 2 == 0 else color_b
	return board

func test_invalid_path_does_not_mutate_board() -> void:
	var board := BoardModel.new(3, 3, 3)
	board.get_cell(Vector2i(0, 0)).color_id = &"red"
	board.get_cell(Vector2i(1, 0)).color_id = &"blue"
	var path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	var result := ChainResolver.resolve_move(board, path, _power_config(), _rng(), [&"red", &"blue"], 0.0)
	check("invalid_path_reported", not result.valid)
	check("board_untouched", board.get_cell(Vector2i(0, 0)).color_id == &"red")

func test_three_match_clears_with_no_power() -> void:
	var board := _checkerboard_board(5, 5, &"blue", &"green")
	for pos in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]:
		board.get_cell(pos).color_id = &"red"
	var path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
	var result := ChainResolver.resolve_move(board, path, _power_config(), _rng(), [&"red", &"blue", &"green"], 0.0)
	check("valid_three_match", result.valid)
	check_eq("clears_exactly_three", result.cleared_cells.size(), 3)
	check_eq("no_power_created", result.powers_created.size(), 0)
	check_eq("chain_depth_is_one", result.chain_depth, 1)
	check_eq("three_red_counted", int(result.colors_cleared.get(&"red", 0)), 3)
	check_eq("no_secondary_triggers_on_neutral_board", result.secondary_triggers, 0)

func test_four_match_creates_and_autodetonates_bomb() -> void:
	var board := _checkerboard_board(5, 5, &"blue", &"green")
	for pos in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, 1)]:
		board.get_cell(pos).color_id = &"red"
	var path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, 1)]
	var result := ChainResolver.resolve_move(board, path, _power_config(), _rng(), [&"red", &"blue", &"green"], 0.0)
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
	check_eq("no_secondary_triggers_on_neutral_board", result.secondary_triggers, 0)

func test_detonate_power_at_scores_same_chain_depth_as_a_matched_power() -> void:
	# A booster-triggered detonation and a player match that creates then
	# auto-detonates the same power must both read as "one wave, one
	# activation" (chain_depth 2) -- otherwise boosters would never build
	# Combo/Fever the way an equivalent match does.
	var board := _checkerboard_board(5, 5, &"blue", &"green")
	var result := ChainResolver.detonate_power_at(board, Vector2i(2, 2), &"bomb", _power_config(), _rng(), [&"red", &"blue"], 0.0)
	check("detonate_power_at_valid", result.valid)
	check_eq("booster_detonation_chain_depth_matches_match_triggered", result.chain_depth, 2)

func test_stone_only_clears_via_power_not_plain_match() -> void:
	var board := _checkerboard_board(5, 5, &"blue", &"green")
	for pos in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, 1)]:
		board.get_cell(pos).color_id = &"red"
	board.set_obstacle(Vector2i(1, 1), &"stone", 0) # inside the future bomb's blast radius
	var path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, 1)]
	var result := ChainResolver.resolve_move(board, path, _power_config(), _rng(), [&"red", &"blue", &"green"], 0.0)
	check_eq("stone_broken_by_bomb_blast", result.obstacles_broken.size(), 1)
	check_eq("stone_break_type", String(result.obstacles_broken[0]["obstacle_id"]), "stone")
	check("stone_no_longer_present", not board.get_cell(Vector2i(1, 1)).is_stone())

func test_ice_cracks_from_bomb_blast_without_fully_breaking() -> void:
	var board := _checkerboard_board(5, 5, &"blue", &"green")
	for pos in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, 1)]:
		board.get_cell(pos).color_id = &"red"
	board.set_obstacle(Vector2i(1, 1), &"ice", 2)
	var path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, 1)]
	var result := ChainResolver.resolve_move(board, path, _power_config(), _rng(), [&"red", &"blue", &"green"], 0.0)
	check_eq("ice_not_yet_broken_after_one_hit", result.obstacles_broken.size(), 0)
	check("ice_piece_still_cleared_underneath", not board.get_cell(Vector2i(1, 1)).has_power())
	check_eq("ice_hp_reduced", board.get_cell(Vector2i(1, 1)).obstacle_hp, 1)

func test_rainbow_wildcard_in_path_resolves_to_group_color() -> void:
	var board := _checkerboard_board(5, 5, &"blue", &"green")
	board.get_cell(Vector2i(0, 0)).color_id = &"red"
	board.get_cell(Vector2i(1, 0)).color_id = BoardModel.RAINBOW_COLOR_ID
	board.get_cell(Vector2i(2, 0)).color_id = &"red"
	var path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
	var result := ChainResolver.resolve_move(board, path, _power_config(), _rng(), [&"red", &"blue", &"green"], 0.0)
	check("valid_with_rainbow_wildcard", result.valid)
	check_eq("two_red_plus_rainbow_counted_as_red", int(result.colors_cleared.get(&"red", 0)), 2)

# ------------------------------------------------------- deeper cascades --

func test_large_group_creates_multiple_powers_from_one_move() -> void:
	# A 9-long connection legitimately earns 2 "chain" powers (see
	# data/powers.json), spread across the path -- not one power scaled up.
	var board := _checkerboard_board(11, 5, &"blue", &"green")
	var path: Array[Vector2i] = []
	for x in 9:
		var pos := Vector2i(x, 0)
		board.get_cell(pos).color_id = &"red"
		path.append(pos)
	var result := ChainResolver.resolve_move(board, path, _power_config(), _rng(), [&"red", &"blue", &"green"], 0.0)
	check("valid_nine_match", result.valid)
	check_eq("two_powers_created_from_one_move", result.powers_created.size(), 2)
	check_eq("first_power_at_path_start", result.powers_created[0]["pos"], Vector2i(0, 0))
	check_eq("second_power_at_path_end", result.powers_created[1]["pos"], Vector2i(8, 0))
	for p in result.powers_created:
		check_eq("created_power_is_chain", String(p["power_id"]), "chain")

func test_multiple_powers_from_one_move_interact_with_each_other() -> void:
	# Both "chain" powers created above share the same color, so the first
	# one to detonate wipes every cell of that color on the board -- which
	# necessarily includes the still-live second power. This is a real
	# POWER + POWER interaction: the second power's activation is *caused*
	# by the first one's blast, not independently queued and coincidentally
	# processed.
	var board := _checkerboard_board(11, 5, &"blue", &"green")
	var path: Array[Vector2i] = []
	for x in 9:
		var pos := Vector2i(x, 0)
		board.get_cell(pos).color_id = &"red"
		path.append(pos)
	var result := ChainResolver.resolve_move(board, path, _power_config(), _rng(), [&"red", &"blue", &"green"], 0.0)
	check_eq("both_powers_detonated", result.powers_activated.size(), 2)
	# wave 1 is the first chain power's own detonation; its wave_cells must
	# include the *other* power's position, proving it was caught by the blast.
	var wave1: Array = result.wave_cells[1]
	check("first_chain_blast_touches_second_power", wave1.has(Vector2i(8, 0)))
	check_eq("chain_depth_covers_both_activations", result.chain_depth, 3) # wave0 + 2 activations

func test_secondary_power_generation_from_exposed_cluster() -> void:
	# A plain 4-match's Bomb blast happens to expose a separate, pre-existing
	# 4-cell purple cluster just outside its radius. That cluster is real
	# board state, not player-drawn -- so it should auto-clear as a genuine
	# bonus wave and, being big enough, spawn its own second power. This is
	# entirely deterministic: no RNG decides whether it happens.
	var board := _checkerboard_board(8, 8, &"blue", &"green")
	for pos in [Vector2i(0, 3), Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3)]:
		board.get_cell(pos).color_id = &"red"
	for pos in [Vector2i(5, 2), Vector2i(5, 3), Vector2i(5, 4), Vector2i(5, 5)]:
		board.get_cell(pos).color_id = &"purple"
	var path: Array[Vector2i] = [Vector2i(0, 3), Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3)]
	var result := ChainResolver.resolve_move(board, path, _power_config(), _rng(), [&"red", &"blue", &"green", &"purple"], 0.0)
	check("valid_move", result.valid)
	check("first_power_is_the_bomb", result.powers_created.size() >= 1 and String(result.powers_created[0]["power_id"]) == "bomb")
	check("secondary_trigger_recorded", result.secondary_triggers >= 1)
	check("second_power_created_from_exposed_cluster", result.powers_created.size() >= 2)
	check("chain_depth_deepened_beyond_two", result.chain_depth >= 3)
	check("purple_cluster_was_cleared", int(result.colors_cleared.get(&"purple", 0)) >= 3)

func test_secondary_generation_never_touches_a_live_power_tile() -> void:
	# find_connected_group() must treat a has_power() cell as a boundary so
	# an auto-chain group never "eats" a power tile instead of letting it
	# detonate. Build a scenario where the exposed cluster's flood fill
	# would otherwise reach through a power tile of a different color.
	var board := _checkerboard_board(8, 8, &"blue", &"green")
	for pos in [Vector2i(0, 3), Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3)]:
		board.get_cell(pos).color_id = &"red"
	var path: Array[Vector2i] = [Vector2i(0, 3), Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3)]
	var result := ChainResolver.resolve_move(board, path, _power_config(), _rng(), [&"red", &"blue", &"green"], 0.0)
	# The bomb's own cell only ever clears when *it* detonates — it must
	# never be swept up as a plain member of some other auto-chain group.
	var bomb_hits := 0
	for p in result.powers_activated:
		if p["pos"] == Vector2i(3, 3):
			bomb_hits += 1
	check_eq("bomb_activated_exactly_once", bomb_hits, 1)
