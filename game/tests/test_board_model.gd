extends TestCase

func test_hex_adjacency() -> void:
	# Honeycomb (odd-r offset): every interior cell has 6 neighbours.
	var board := BoardModel.new(5, 5, 3)
	check("left_right_adjacent", board.is_adjacent(Vector2i(2, 2), Vector2i(3, 2)))
	check("same_cell_not_adjacent", not board.is_adjacent(Vector2i(2, 2), Vector2i(2, 2)))
	check_eq("interior_cell_has_six_neighbours", board.get_neighbors(Vector2i(2, 2)).size(), 6)
	# even row (y=2): the two cells directly above are (2,1) and (1,1)
	check("even_row_up_neighbours", board.is_adjacent(Vector2i(2, 2), Vector2i(2, 1)) and board.is_adjacent(Vector2i(2, 2), Vector2i(1, 1)))
	check("even_row_skips_far_diagonal", not board.is_adjacent(Vector2i(2, 2), Vector2i(3, 1)))
	# odd row (y=1): the two cells above are (1,0) and (2,0)
	check("odd_row_up_neighbours", board.is_adjacent(Vector2i(1, 1), Vector2i(1, 0)) and board.is_adjacent(Vector2i(1, 1), Vector2i(2, 0)))
	check_eq("top_left_corner_has_two_neighbours", board.get_neighbors(Vector2i(0, 0)).size(), 2)

func test_validate_path_requires_min_size() -> void:
	var board := _colored_board(3, 3, &"red")
	var path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	check("too_short_rejected", not board.validate_path(path))

func test_validate_path_accepts_straight_line() -> void:
	var board := _colored_board(3, 3, &"red")
	var path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
	check("valid_line_accepted", board.validate_path(path))

func test_validate_path_rejects_non_adjacent_step() -> void:
	var board := _colored_board(3, 3, &"red")
	var path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(2, 0), Vector2i(2, 1)]
	check("non_adjacent_rejected", not board.validate_path(path))

func test_validate_path_rejects_mixed_colors() -> void:
	var board := _colored_board(3, 3, &"red")
	board.get_cell(Vector2i(2, 0)).color_id = &"blue"
	var path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
	check("mixed_colors_rejected", not board.validate_path(path))

func test_validate_path_rejects_repeated_cell() -> void:
	var board := _colored_board(3, 3, &"red")
	var path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 0)]
	check("repeated_cell_rejected", not board.validate_path(path))

func test_validate_path_allows_rainbow_wildcard() -> void:
	var board := _colored_board(3, 3, &"red")
	board.get_cell(Vector2i(1, 0)).color_id = BoardModel.RAINBOW_COLOR_ID
	var path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
	check("rainbow_wildcard_accepted", board.validate_path(path))
	check_eq("target_color_resolves_past_wildcard", board.get_path_target_color(path), &"red")

func test_stone_blocks_selection() -> void:
	var board := BoardModel.new(3, 3, 3)
	board.set_obstacle(Vector2i(1, 1), &"stone", 0)
	var cell := board.get_cell(Vector2i(1, 1))
	check("stone_not_selectable", not cell.is_selectable())
	check("stone_not_damaged_by_plain_clear", cell.is_stone())
	var broke := board.damage_stone(Vector2i(1, 1))
	check("stone_breaks_on_power_hit", broke)
	check("stone_cleared_after_hit", not board.get_cell(Vector2i(1, 1)).is_stone())

func test_ice_requires_two_hits() -> void:
	var board := _colored_board(3, 3, &"red")
	board.set_obstacle(Vector2i(0, 0), &"ice", 2)
	var first := board.damage_ice(Vector2i(0, 0))
	check("ice_survives_first_hit", not first)
	check_eq("ice_hp_after_first_hit", board.get_cell(Vector2i(0, 0)).obstacle_hp, 1)
	var second := board.damage_ice(Vector2i(0, 0))
	check("ice_breaks_on_second_hit", second)
	check("ice_obstacle_removed", not board.get_cell(Vector2i(0, 0)).is_ice())

func test_lock_unlocks_from_neighbor_clear() -> void:
	var board := _colored_board(3, 3, &"red")
	board.set_obstacle(Vector2i(1, 0), &"lock", 1)
	check("lock_starts_unselectable", not board.get_cell(Vector2i(1, 0)).is_selectable())
	var unlocked := board.unlock_neighbors(Vector2i(0, 0))
	check("neighbor_clear_unlocks_lock", unlocked.has(Vector2i(1, 0)))
	check("lock_cell_now_fillable", not board.get_cell(Vector2i(1, 0)).is_lock())

func test_gravity_compacts_column_and_stops_at_blockers() -> void:
	var board := BoardModel.new(1, 5, 3)
	board.set_obstacle(Vector2i(0, 3), &"stone", 0)
	board.get_cell(Vector2i(0, 0)).color_id = &"red"
	var moves := board.apply_gravity()
	check("piece_falls_to_bottom_of_segment", board.get_cell(Vector2i(0, 2)).color_id == &"red")
	check("original_cell_now_empty", board.get_cell(Vector2i(0, 0)).is_empty())
	check("stone_segment_untouched", board.get_cell(Vector2i(0, 3)).is_stone())
	check("one_move_recorded", moves.size() == 1)

func test_refill_fills_empty_non_blocker_cells() -> void:
	var board := BoardModel.new(2, 2, 3)
	board.set_obstacle(Vector2i(1, 1), &"stone", 0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var colors: Array[StringName] = [&"red", &"blue"]
	var filled := board.refill(rng, colors, 0.0)
	check_eq("fills_three_open_cells", filled.size(), 3)
	check("stone_cell_stays_empty", board.get_cell(Vector2i(1, 1)).is_empty())

func test_find_connected_group_flood_fills_same_color() -> void:
	var board := _colored_board(4, 4, &"red")
	var group := board.find_connected_group(Vector2i(0, 0))
	check_eq("uniform_board_group_is_whole_board", group.size(), 16)

func test_find_connected_group_stops_at_color_boundary() -> void:
	var board := _colored_board(4, 4, &"red")
	board.get_cell(Vector2i(2, 0)).color_id = &"blue"
	board.get_cell(Vector2i(3, 0)).color_id = &"blue"
	var group := board.find_connected_group(Vector2i(0, 0))
	check_eq("group_stops_before_blue", group.size(), 14)
	check("blue_cells_excluded", not group.has(Vector2i(2, 0)) and not group.has(Vector2i(3, 0)))

func test_find_connected_group_excludes_power_tiles_as_boundary() -> void:
	var board := _colored_board(3, 3, &"red")
	board.get_cell(Vector2i(1, 1)).power_id = &"bomb" # still red, but now "live"
	var group := board.find_connected_group(Vector2i(0, 0))
	check("power_tile_not_a_member", not group.has(Vector2i(1, 1)))
	check_eq("group_excludes_only_the_power_cell", group.size(), 8)

func test_find_connected_group_returns_empty_for_power_or_unselectable_start() -> void:
	var board := _colored_board(3, 3, &"red")
	board.get_cell(Vector2i(1, 1)).power_id = &"bomb"
	check_eq("power_tile_start_yields_empty", board.find_connected_group(Vector2i(1, 1)).size(), 0)
	board.set_obstacle(Vector2i(0, 0), &"stone", 0)
	check_eq("stone_start_yields_empty", board.find_connected_group(Vector2i(0, 0)).size(), 0)

func test_has_any_valid_move_true_for_uniform_board() -> void:
	var board := _colored_board(3, 3, &"red")
	check("uniform_board_has_move", board.has_any_valid_move())

func test_has_any_valid_move_false_when_every_cell_is_isolated() -> void:
	# Greedy-colour so no cell shares a colour with any of its 6 hex
	# neighbours -> every connected group is size 1 -> no valid move.
	var board := BoardModel.new(4, 4, 3)
	var palette: Array[StringName] = [&"red", &"blue", &"green", &"yellow", &"purple", &"orange", &"pink"]
	for y in 4:
		for x in 4:
			var used := {}
			for n in board.get_neighbors(Vector2i(x, y)):
				var nc := board.get_cell(n)
				if nc != null and not nc.is_empty():
					used[nc.color_id] = true
			for c in palette:
				if not used.has(c):
					board.get_cell(Vector2i(x, y)).color_id = c
					break
	check("isolated_board_has_no_move", not board.has_any_valid_move())

func _colored_board(w: int, h: int, color: StringName) -> BoardModel:
	var board := BoardModel.new(w, h, 3)
	for x in w:
		for y in h:
			board.get_cell(Vector2i(x, y)).color_id = color
	return board
