extends TestCase
## Time Bomb obstacle: a countdown (stored in obstacle_hp) that ticks down
## one per player move. Clear the piece on it before it reaches zero to
## defuse it; let it hit zero and it detonates in a 3x3 blast and costs the
## player moves.

func _config() -> PowerConfig:
	return PowerConfig.from_dict({
		"thresholds": [
			{"power": "lightning", "min_size": 5, "count": 1},
			{"power": "bomb", "min_size": 4, "count": 1},
			{"power": "none", "min_size": 3, "count": 0},
		],
		"definitions": {"bomb": {"radius": 1, "activation_bonus": 150}},
		"base_points_per_piece": 10,
	})

func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	return rng

## Checkerboard of blue/green with a red triple along the top row for a
## valid, isolated player move that touches nothing else.
func _board_with_red_triple(w: int, h: int) -> BoardModel:
	var board := BoardModel.new(w, h, 3)
	for x in w:
		for y in h:
			board.get_cell(Vector2i(x, y)).color_id = &"blue" if (x + y) % 2 == 0 else &"green"
	for x in 3:
		board.get_cell(Vector2i(x, 0)).color_id = &"red"
	return board

func _red_path() -> Array[Vector2i]:
	return [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]

func test_board_model_helpers() -> void:
	var board := BoardModel.new(4, 4, 3)
	board.get_cell(Vector2i(1, 1)).color_id = &"red"
	board.set_obstacle(Vector2i(1, 1), &"timebomb", 3)
	check("is_timebomb", board.get_cell(Vector2i(1, 1)).is_timebomb())
	check("tick_not_zero_yet", not board.tick_timebomb(Vector2i(1, 1)))
	check_eq("hp_decremented", board.get_cell(Vector2i(1, 1)).obstacle_hp, 2)
	check("tick_again", not board.tick_timebomb(Vector2i(1, 1)))
	check("tick_reaches_zero", board.tick_timebomb(Vector2i(1, 1)))
	# defuse
	board.set_obstacle(Vector2i(2, 2), &"timebomb", 3)
	check("defuse_returns_true", board.defuse_timebomb(Vector2i(2, 2)))
	check("no_longer_timebomb", not board.get_cell(Vector2i(2, 2)).is_timebomb())

func test_untouched_timebomb_ticks_down_one_per_move() -> void:
	var board := _board_with_red_triple(6, 6)
	board.set_obstacle(Vector2i(5, 5), &"timebomb", 3)
	var result := ChainResolver.resolve_move(board, _red_path(), _config(), _rng(), [&"blue", &"green", &"red"], 0.0)
	check("move_valid", result.valid)
	check("no_explosion_yet", result.timebomb_explosions.is_empty())
	check_eq("no_move_penalty", result.move_penalty, 0)
	check_eq("countdown_decremented", board.get_cell(Vector2i(5, 5)).obstacle_hp, 2)
	check("still_a_timebomb", board.get_cell(Vector2i(5, 5)).is_timebomb())

func test_timebomb_detonates_when_countdown_hits_zero() -> void:
	var board := _board_with_red_triple(6, 6)
	board.set_obstacle(Vector2i(4, 4), &"timebomb", 1)
	var result := ChainResolver.resolve_move(board, _red_path(), _config(), _rng(), [&"blue", &"green", &"red"], 0.0)
	check_eq("one_explosion", result.timebomb_explosions.size(), 1)
	check_eq("explosion_at_bomb_pos", result.timebomb_explosions[0], Vector2i(4, 4))
	check_eq("move_penalty_applied", result.move_penalty, ChainResolver.TIMEBOMB_MOVE_PENALTY)
	check("counts_as_obstacle_broken", _has_broken(result, &"timebomb"))
	check("obstacle_removed", not board.get_cell(Vector2i(4, 4)).is_timebomb())
	# 3x3 blast cleared the neighbourhood (before gravity/refill it was 9
	# cells; the explosion wave is the last score event)
	var last_wave: Array = result.wave_cells[result.wave_cells.size() - 1]
	check("blast_touched_nine_cells", last_wave.size() == 9)
	check_eq("chain_depth_includes_the_blast_wave", result.chain_depth, 2)

func test_clearing_the_piece_on_a_timebomb_defuses_it_without_exploding() -> void:
	var board := _board_with_red_triple(6, 6)
	# put the timebomb under the middle red of the triple so the player's
	# own match clears its piece
	board.set_obstacle(Vector2i(1, 0), &"timebomb", 5)
	var result := ChainResolver.resolve_move(board, _red_path(), _config(), _rng(), [&"blue", &"green", &"red"], 0.0)
	check("no_explosion", result.timebomb_explosions.is_empty())
	check_eq("no_penalty", result.move_penalty, 0)
	check("defuse_counts_as_broken", _has_broken(result, &"timebomb"))
	check("defused_obstacle_gone", not board.get_cell(Vector2i(1, 0)).is_timebomb())

func test_booster_detonation_does_not_tick_timebombs() -> void:
	var board := _board_with_red_triple(6, 6)
	board.set_obstacle(Vector2i(5, 5), &"timebomb", 2)
	# a booster-style detonation is not a "move" and must not advance timers
	var result := ChainResolver.detonate_power_at(board, Vector2i(3, 3), &"bomb", _config(), _rng(), [&"blue", &"green"], 0.0)
	check("booster_valid", result.valid)
	check_eq("timebomb_untouched_by_booster", board.get_cell(Vector2i(5, 5)).obstacle_hp, 2)

func _has_broken(result: ChainResolver.MoveResult, id: StringName) -> bool:
	for b in result.obstacles_broken:
		if b["obstacle_id"] == id:
			return true
	return false
