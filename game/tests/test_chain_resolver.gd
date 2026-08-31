extends TestCase
## Power discovery model: a big plain match LEAVES a power tile on the board
## (result.powers_formed). The player activates it later by threading it
## into a connection (resolve_move) or tapping it (resolve_power_tap) — that
## is when detonation, power+power interaction and secondary cascades run.

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

## Neutral filler: a greedy hex-colouring so NO cell shares a colour with any
## of its 6 honeycomb neighbours -> find_connected_group() is a no-op
## everywhere, isolating one interaction from the auto-chain mechanic.
## (The colour-name args are ignored — kept for call-site compatibility.)
func _checkerboard_board(w: int, h: int, _a: StringName = &"", _b: StringName = &"") -> BoardModel:
	var board := BoardModel.new(w, h, 3)
	var pal: Array[StringName] = [&"grayA", &"grayB", &"grayC", &"grayD"]
	for y in h:
		for x in w:
			var used := {}
			for n in board.get_neighbors(Vector2i(x, y)):
				var nc := board.get_cell(n)
				if nc != null and not nc.is_empty():
					used[nc.color_id] = true
			for c in pal:
				if not used.has(c):
					board.get_cell(Vector2i(x, y)).color_id = c
					break
	return board

func _paint(board: BoardModel, cells: Array, color: StringName) -> void:
	for c in cells:
		board.get_cell(c).color_id = color

func _typed(cells: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in cells:
		out.append(c)
	return out

# ------------------------------------------------------------- plain match --

func test_invalid_path_does_not_mutate_board() -> void:
	var board := BoardModel.new(3, 3, 3)
	board.get_cell(Vector2i(0, 0)).color_id = &"red"
	board.get_cell(Vector2i(1, 0)).color_id = &"blue"
	var result := ChainResolver.resolve_move(board, _typed([Vector2i(0, 0), Vector2i(1, 0)]), _power_config(), _rng(), [&"red", &"blue"], 0.0)
	check("invalid_path_reported", not result.valid)
	check("board_untouched", board.get_cell(Vector2i(0, 0)).color_id == &"red")

func test_three_match_clears_with_no_power() -> void:
	var board := _checkerboard_board(5, 5, &"blue", &"green")
	_paint(board, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)], &"red")
	var result := ChainResolver.resolve_move(board, _typed([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]), _power_config(), _rng(), [&"red", &"blue", &"green"], 0.0)
	check("valid_three_match", result.valid)
	check_eq("clears_exactly_three", result.cleared_cells.size(), 3)
	check_eq("no_power_created", result.powers_created.size(), 0)
	check("not_a_formation", not result.powers_formed)
	check_eq("chain_depth_is_one", result.chain_depth, 1)
	check_eq("three_red_counted", int(result.colors_cleared.get(&"red", 0)), 3)

func test_four_match_LEAVES_a_bomb_on_the_board() -> void:
	var board := _checkerboard_board(5, 5, &"blue", &"green")
	_paint(board, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, 1)], &"red")
	var result := ChainResolver.resolve_move(board, _typed([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, 1)]), _power_config(), _rng(), [&"red", &"blue", &"green"], 0.0)
	check("valid_four_match", result.valid)
	check_eq("one_power_created", result.powers_created.size(), 1)
	check_eq("power_is_bomb", String(result.powers_created[0]["power_id"]), "bomb")
	check("flagged_as_formation", result.powers_formed)
	check_eq("nothing_detonated_yet", result.powers_activated.size(), 0)
	check_eq("chain_depth_is_one_no_cascade", result.chain_depth, 1)
	check_eq("only_the_three_non_anchor_cells_cleared", result.cleared_cells.size(), 3)
	# the bomb tile actually persists on the board
	var bpos: Vector2i = result.powers_created[0]["pos"]
	check("bomb_tile_present_after_move", board.get_cell(bpos).has_power())
	check_eq("bomb_tile_power_id", board.get_cell(bpos).power_id, &"bomb")

func test_large_group_leaves_multiple_power_tiles() -> void:
	var board := _checkerboard_board(11, 5, &"blue", &"green")
	var path: Array[Vector2i] = []
	for x in 9:
		var pos := Vector2i(x, 0)
		board.get_cell(pos).color_id = &"red"
		path.append(pos)
	var result := ChainResolver.resolve_move(board, path, _power_config(), _rng(), [&"red", &"blue", &"green"], 0.0)
	check_eq("two_power_tiles_created", result.powers_created.size(), 2)
	check_eq("first_power_at_path_start", result.powers_created[0]["pos"], Vector2i(0, 0))
	check_eq("second_power_at_path_end", result.powers_created[1]["pos"], Vector2i(8, 0))
	check("both_persist", board.get_cell(Vector2i(0, 0)).has_power() and board.get_cell(Vector2i(8, 0)).has_power())
	check_eq("neither_detonated", result.powers_activated.size(), 0)

# ------------------------------------------------------------ activation --

func test_tapping_a_power_tile_detonates_it() -> void:
	var board := _checkerboard_board(5, 5, &"blue", &"green")
	board.get_cell(Vector2i(2, 2)).color_id = &"red"
	board.get_cell(Vector2i(2, 2)).power_id = &"bomb"
	var result := ChainResolver.resolve_power_tap(board, Vector2i(2, 2), _power_config(), _rng(), [&"red", &"blue"], 0.0)
	check("tap_valid", result.valid)
	check_eq("bomb_activated_once", result.powers_activated.size(), 1)
	check_eq("chain_depth_two", result.chain_depth, 2)
	check("blast_radius_cleared", result.cleared_cells.size() >= 5)
	check_eq("bomb_bonus_scored", int(result.score_events[result.score_events.size() - 1]["power_bonus"]), 150)

func test_threading_a_power_into_a_connection_activates_it() -> void:
	var board := _checkerboard_board(6, 6, &"blue", &"green")
	_paint(board, [Vector2i(0, 0), Vector2i(1, 0)], &"red")
	board.get_cell(Vector2i(2, 0)).color_id = &"red"
	board.get_cell(Vector2i(2, 0)).power_id = &"bomb"   # existing power tile at path end
	var result := ChainResolver.resolve_move(board, _typed([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]), _power_config(), _rng(), [&"red", &"blue", &"green"], 0.0)
	check("activation_valid", result.valid)
	check("not_a_formation", not result.powers_formed)
	check_eq("power_detonated", result.powers_activated.size(), 1)
	check_eq("two_plain_cells_were_wave0", (result.wave_cells[0] as Array).size(), 2)
	check_eq("chain_depth_two", result.chain_depth, 2)

func test_two_threaded_powers_chain_into_each_other() -> void:
	# Two same-colour chain powers: threading both, the first's colour-wide
	# blast necessarily catches the second — a real power+power interaction.
	var board := _checkerboard_board(11, 5, &"blue", &"green")
	_paint(board, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)], &"red")
	for p in [Vector2i(0, 0), Vector2i(8, 0)]:
		board.get_cell(p).color_id = &"red"
		board.get_cell(p).power_id = &"chain"
	# connect a straight red row that includes both power tiles
	var path: Array[Vector2i] = []
	for x in 9:
		board.get_cell(Vector2i(x, 0)).color_id = &"red"
	board.get_cell(Vector2i(0, 0)).power_id = &"chain"
	board.get_cell(Vector2i(8, 0)).power_id = &"chain"
	for x in 9:
		path.append(Vector2i(x, 0))
	var result := ChainResolver.resolve_move(board, path, _power_config(), _rng(), [&"red", &"blue", &"green"], 0.0)
	check_eq("both_powers_detonated", result.powers_activated.size(), 2)
	check("chain_depth_covers_both", result.chain_depth >= 3)

func test_detonate_power_at_is_a_two_wave_activation() -> void:
	var board := _checkerboard_board(5, 5, &"blue", &"green")
	var result := ChainResolver.detonate_power_at(board, Vector2i(2, 2), &"bomb", _power_config(), _rng(), [&"red", &"blue"], 0.0)
	check("detonate_power_at_valid", result.valid)
	check_eq("chain_depth_two", result.chain_depth, 2)

# ------------------------------------------------------- obstacle interplay --

func test_power_blast_breaks_stone_and_cracks_ice() -> void:
	var board := _checkerboard_board(5, 5, &"blue", &"green")
	board.get_cell(Vector2i(2, 2)).color_id = &"red"
	board.get_cell(Vector2i(2, 2)).power_id = &"bomb"
	board.set_obstacle(Vector2i(1, 1), &"stone", 0)   # a hex neighbour of (2,2)
	board.set_obstacle(Vector2i(3, 2), &"ice", 2)     # the E hex neighbour
	var result := ChainResolver.resolve_power_tap(board, Vector2i(2, 2), _power_config(), _rng(), [&"red", &"blue"], 0.0)
	var broke_stone := false
	for b in result.obstacles_broken:
		if b["obstacle_id"] == &"stone":
			broke_stone = true
	check("stone_broken_by_blast", broke_stone)
	check("stone_gone", not board.get_cell(Vector2i(1, 1)).is_stone())
	check_eq("ice_cracked_not_broken", board.get_cell(Vector2i(3, 2)).obstacle_hp, 1)

func test_rainbow_wildcard_in_path_resolves_to_group_color() -> void:
	var board := _checkerboard_board(5, 5, &"blue", &"green")
	board.get_cell(Vector2i(0, 0)).color_id = &"red"
	board.get_cell(Vector2i(1, 0)).color_id = BoardModel.RAINBOW_COLOR_ID
	board.get_cell(Vector2i(2, 0)).color_id = &"red"
	var result := ChainResolver.resolve_move(board, _typed([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]), _power_config(), _rng(), [&"red", &"blue", &"green"], 0.0)
	check("valid_with_rainbow_wildcard", result.valid)
	check_eq("two_red_plus_rainbow_counted_as_red", int(result.colors_cleared.get(&"red", 0)), 2)

# ----------------------------------------------- secondary generation --

func test_activation_blast_can_expose_a_secondary_cluster() -> void:
	# Tapping a chain power (colour-wide clear) exposes a pre-existing purple
	# cluster that then auto-clears as a genuine bonus wave.
	var board := _checkerboard_board(8, 8, &"blue", &"green")
	board.get_cell(Vector2i(0, 0)).color_id = &"red"
	board.get_cell(Vector2i(0, 0)).power_id = &"bomb"
	# purple line adjacent to (1,0), which the bomb's 3x3 clears -> exposed
	_paint(board, [Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2)], &"purple")
	var result := ChainResolver.resolve_power_tap(board, Vector2i(0, 0), _power_config(), _rng(), [&"red", &"blue", &"green", &"purple"], 0.0)
	check("valid", result.valid)
	check("secondary_trigger_recorded", result.secondary_triggers >= 1)
	check("purple_cluster_cleared", int(result.colors_cleared.get(&"purple", 0)) >= 3)
	check("chain_depth_deepened", result.chain_depth >= 3)
