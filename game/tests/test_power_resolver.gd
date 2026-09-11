extends TestCase

func test_bomb_is_a_hex_disc() -> void:
	var board := BoardModel.new(5, 5, 3)
	# radius 1 on the honeycomb = the cell + its 6 neighbours
	var cells := PowerResolver.affected_cells(board, Vector2i(2, 2), &"bomb", true, &"red", {"radius": 1})
	check_eq("bomb_centre_is_seven_hexes", cells.size(), 7)
	check("includes_centre", cells.has(Vector2i(2, 2)))
	# radius 2 = centre + 6 + 12
	var big := PowerResolver.affected_cells(board, Vector2i(2, 2), &"bomb", true, &"red", {"radius": 2})
	check_eq("radius_two_is_nineteen", big.size(), 19)

func test_bomb_clips_at_board_edge() -> void:
	var board := BoardModel.new(5, 5, 3)
	var cells := PowerResolver.affected_cells(board, Vector2i(0, 0), &"bomb", true, &"red", {"radius": 1})
	# top-left corner (even row 0) only has 2 neighbours -> 3 hexes total
	check_eq("bomb_corner_clipped_to_three", cells.size(), 3)

func test_lightning_horizontal_covers_row() -> void:
	var board := BoardModel.new(5, 6, 3)
	var cells := PowerResolver.affected_cells(board, Vector2i(2, 3), &"lightning", true, &"red", {})
	check_eq("lightning_row_width", cells.size(), 5)
	for c in cells:
		check("lightning_row_stays_on_y", c.y == 3)

func test_lightning_vertical_covers_column() -> void:
	var board := BoardModel.new(5, 6, 3)
	var cells := PowerResolver.affected_cells(board, Vector2i(2, 3), &"lightning", false, &"red", {})
	check_eq("lightning_column_height", cells.size(), 6)
	for c in cells:
		check("lightning_column_stays_on_x", c.x == 2)

func test_color_cells_match_only_target_color() -> void:
	var board := BoardModel.new(3, 3, 3)
	board.get_cell(Vector2i(0, 0)).color_id = &"red"
	board.get_cell(Vector2i(1, 1)).color_id = &"red"
	board.get_cell(Vector2i(2, 2)).color_id = &"blue"
	var cells := PowerResolver.affected_cells(board, Vector2i(0, 0), &"chain", true, &"red", {})
	check_eq("chain_hits_all_red_cells", cells.size(), 2)
	check("chain_ignores_blue", not cells.has(Vector2i(2, 2)))

func test_color_cells_ignore_rainbow_sentinel() -> void:
	var board := BoardModel.new(3, 3, 3)
	board.get_cell(Vector2i(0, 0)).color_id = &"red"
	var cells := PowerResolver.affected_cells(board, Vector2i(0, 0), &"rainbow", true, BoardModel.RAINBOW_COLOR_ID, {})
	check_eq("rainbow_sentinel_source_yields_no_cells", cells.size(), 0)
