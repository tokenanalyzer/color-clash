extends TestCase
## Freeze power on the honeycomb: shatters a hex disc (centre + 6) and
## encases the plain pieces on the ring one hex-step further out in ice.

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

func _filled(w: int, h: int) -> BoardModel:
	# 3-colour cycle so nothing forms a matchable group (isolates the test
	# from auto-chain), every cell still holds a piece.
	var board := BoardModel.new(w, h, 3)
	var pal: Array[StringName] = [&"red", &"blue", &"green"]
	for x in w:
		for y in h:
			board.get_cell(Vector2i(x, y)).color_id = pal[(x + 2 * y) % 3]
	return board

func test_freeze_area_is_a_hex_disc() -> void:
	var board := BoardModel.new(7, 7, 3)
	var cells := PowerResolver.affected_cells(board, Vector2i(3, 3), &"freeze", true, &"red", {"radius": 1})
	check_eq("freeze_disc_is_seven_hexes", cells.size(), 7)
	check("hits_centre", cells.has(Vector2i(3, 3)))
	for n in board.get_neighbors(Vector2i(3, 3)):
		check("hits_every_neighbour", cells.has(n))

func test_freeze_ring_is_the_second_hex_ring() -> void:
	var board := BoardModel.new(9, 9, 3)
	var ring := PowerResolver.freeze_ring_cells(board, Vector2i(4, 4), 1)
	check_eq("second_hex_ring_has_twelve_cells", ring.size(), 12)
	for c in ring:
		check("ring_cell_not_in_disc", not PowerResolver.affected_cells(board, Vector2i(4, 4), &"freeze", true, &"red", {"radius": 1}).has(c))

func test_freeze_ring_clips_at_board_edge() -> void:
	var board := BoardModel.new(7, 7, 3)
	var ring := PowerResolver.freeze_ring_cells(board, Vector2i(0, 0), 1)
	check("corner_ring_is_clipped", ring.size() > 0 and ring.size() < 12)

func test_detonation_freezes_the_ring_pieces_into_ice() -> void:
	var board := _filled(9, 9)
	var result := ChainResolver.detonate_power_at(board, Vector2i(4, 4), &"freeze", _config(), _rng(), [&"red", &"blue", &"green"], 0.0)
	check("detonation_valid", result.valid)
	check_eq("twelve_ring_pieces_frozen", result.frozen_cells.size(), 12)
	for c in result.frozen_cells:
		check("frozen_cell_is_ice", board.get_cell(c).is_ice())
		check("frozen_cell_hp_two", board.get_cell(c).obstacle_hp == 2)
	check("shattered_centre_was_cleared", result.cleared_cells.has(Vector2i(4, 4)))

func test_freeze_ring_leaves_existing_obstacles_and_gaps_alone() -> void:
	var board := _filled(9, 9)
	var ring := PowerResolver.freeze_ring_cells(board, Vector2i(4, 4), 1)
	board.set_obstacle(ring[0], &"stone", 0)
	board.get_cell(ring[1]).clear_piece()
	var result := ChainResolver.detonate_power_at(board, Vector2i(4, 4), &"freeze", _config(), _rng(), [&"red", &"blue", &"green"], 0.0)
	check("stone_ring_cell_not_frozen", not result.frozen_cells.has(ring[0]))
	check("stone_ring_cell_still_stone", board.get_cell(ring[0]).is_stone())
	check("empty_ring_cell_not_frozen", not result.frozen_cells.has(ring[1]))
	check_eq("ten_of_twelve_ring_cells_frozen", result.frozen_cells.size(), 10)

func test_real_power_config_maps_size_six_to_freeze() -> void:
	var cfg := PowerConfig.from_dict(JsonLoader.load_json("res://data/powers.json"))
	check_eq("size_six_creates_freeze", String(cfg.power_for_group_size(6)), "freeze")
	check_eq("size_five_still_lightning", String(cfg.power_for_group_size(5)), "lightning")
	check_eq("size_seven_is_chain", String(cfg.power_for_group_size(7)), "chain")
	check_eq("size_eight_is_rainbow", String(cfg.power_for_group_size(8)), "rainbow")
