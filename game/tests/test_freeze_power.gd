extends TestCase
## Freeze power: shatters a small Manhattan diamond and encases the plain
## pieces on the ring one step further out in ice (a deliberate, testable
## side effect rather than a clear).

func _config() -> PowerConfig:
	return PowerConfig.from_dict({
		"thresholds": [
			{"power": "chain", "min_size": 7, "count": 1},
			{"power": "freeze", "min_size": 6, "count": 1},
			{"power": "lightning", "min_size": 5, "count": 1},
			{"power": "bomb", "min_size": 4, "count": 1},
			{"power": "none", "min_size": 3, "count": 0},
		],
		"definitions": {
			"freeze": {"radius": 1, "freeze_hp": 2, "activation_bonus": 300},
		},
		"base_points_per_piece": 10,
	})

func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	return rng

func _checkerboard(w: int, h: int) -> BoardModel:
	var board := BoardModel.new(w, h, 3)
	for x in w:
		for y in h:
			board.get_cell(Vector2i(x, y)).color_id = &"red" if (x + y) % 2 == 0 else &"blue"
	return board

func test_affected_cells_is_manhattan_diamond() -> void:
	var board := BoardModel.new(7, 7, 3)
	var cells := PowerResolver.affected_cells(board, Vector2i(3, 3), &"freeze", true, &"red", {"radius": 1})
	check_eq("freeze_diamond_is_five_cells", cells.size(), 5)
	check("freeze_hits_center", cells.has(Vector2i(3, 3)))
	check("freeze_hits_orthogonals", cells.has(Vector2i(2, 3)) and cells.has(Vector2i(4, 3)) and cells.has(Vector2i(3, 2)) and cells.has(Vector2i(3, 4)))
	check("freeze_skips_diagonals", not cells.has(Vector2i(2, 2)))

func test_freeze_ring_is_eight_cells_in_open_space() -> void:
	var board := BoardModel.new(7, 7, 3)
	var ring := PowerResolver.freeze_ring_cells(board, Vector2i(3, 3), 1)
	check_eq("ring_has_eight_cells", ring.size(), 8)
	for c in ring:
		check("ring_cells_are_manhattan_distance_two", abs(c.x - 3) + abs(c.y - 3) == 2)

func test_freeze_ring_clips_at_board_edge() -> void:
	var board := BoardModel.new(7, 7, 3)
	var ring := PowerResolver.freeze_ring_cells(board, Vector2i(0, 0), 1)
	check_eq("corner_ring_clipped_to_three", ring.size(), 3)

func test_detonation_freezes_the_ring_pieces_into_ice() -> void:
	var board := _checkerboard(7, 7)
	var result := ChainResolver.detonate_power_at(board, Vector2i(3, 3), &"freeze", _config(), _rng(), [&"red", &"blue"], 0.0)
	check("detonation_valid", result.valid)
	check_eq("ring_pieces_frozen", result.frozen_cells.size(), 8)
	# frozen cells on rows/columns the shatter did not touch keep their frost
	check("left_ring_cell_is_ice", board.get_cell(Vector2i(1, 3)).is_ice())
	check("right_ring_cell_is_ice", board.get_cell(Vector2i(5, 3)).is_ice())
	check("frozen_cell_hp_is_two", board.get_cell(Vector2i(1, 3)).obstacle_hp == 2)
	check("shattered_center_is_empty", board.get_cell(Vector2i(3, 3)).is_empty() or not board.get_cell(Vector2i(3, 3)).is_ice())

func test_freeze_ring_leaves_existing_obstacles_and_gaps_alone() -> void:
	var board := _checkerboard(7, 7)
	board.set_obstacle(Vector2i(1, 3), &"stone", 0) # a ring cell
	board.get_cell(Vector2i(5, 3)).clear_piece()     # an empty ring cell
	var result := ChainResolver.detonate_power_at(board, Vector2i(3, 3), &"freeze", _config(), _rng(), [&"red", &"blue"], 0.0)
	check("stone_ring_cell_not_frozen", not result.frozen_cells.has(Vector2i(1, 3)))
	check("stone_ring_cell_still_stone", board.get_cell(Vector2i(1, 3)).is_stone())
	check("empty_ring_cell_not_frozen", not result.frozen_cells.has(Vector2i(5, 3)))
	check_eq("only_six_of_eight_ring_cells_frozen", result.frozen_cells.size(), 6)

func test_real_power_config_maps_size_six_to_freeze() -> void:
	var data := JsonLoader.load_json("res://data/powers.json")
	var cfg := PowerConfig.from_dict(data)
	check_eq("size_six_creates_freeze", String(cfg.power_for_group_size(6)), "freeze")
	check_eq("size_five_still_lightning", String(cfg.power_for_group_size(5)), "lightning")
	check_eq("size_seven_is_chain", String(cfg.power_for_group_size(7)), "chain")
