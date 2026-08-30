extends TestCase

func test_adjacency() -> void:
	var board := BoardModel.new(3, 3, 3)
	check("orthogonal_adjacent", board.is_adjacent(Vector2i(1, 1), Vector2i(1, 2)))
	check("diagonal_not_adjacent", not board.is_adjacent(Vector2i(1, 1), Vector2i(2, 2)))
	check("same_cell_not_adjacent", not board.is_adjacent(Vector2i(1, 1), Vector2i(1, 1)))

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

func test_has_any_valid_move_true_for_uniform_board() -> void:
	var board := _colored_board(3, 3, &"red")
	check("uniform_board_has_move", board.has_any_valid_move())

func test_has_any_valid_move_false_for_isolated_singletons() -> void:
	var board := BoardModel.new(3, 3, 3)
	var colors: Array[StringName] = [&"red", &"blue"]
	var i := 0
	for x in 3:
		for y in 3:
			board.get_cell(Vector2i(x, y)).color_id = colors[(x + y) % 2]
			i += 1
	check("checkerboard_has_no_move", not board.has_any_valid_move())

func _colored_board(w: int, h: int, color: StringName) -> BoardModel:
	var board := BoardModel.new(w, h, 3)
	for x in w:
		for y in h:
			board.get_cell(Vector2i(x, y)).color_id = color
	return board
