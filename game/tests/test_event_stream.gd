extends TestCase
## Phase 1 event-stream layer: EngineEvent value object, GameplayEventStream
## collection, and MoveEventTranslator (the pure MoveResult -> typed events
## mapping). These assert the stream is well-formed and deterministic without
## touching the existing ChainResolver behaviour.

func _power_config() -> PowerConfig:
	return PowerConfig.from_dict({
		"thresholds": [
			{"power": "chain", "min_size": 6, "count": 1},
			{"power": "lightning", "min_size": 5, "count": 1},
			{"power": "bomb", "min_size": 4, "count": 1},
			{"power": "none", "min_size": 3, "count": 0}
		],
		"definitions": {
			"bomb": {"radius": 1, "activation_bonus": 150},
			"lightning": {"activation_bonus": 250},
			"chain": {"activation_bonus": 400},
		},
		"base_points_per_piece": 10
	})

func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	return rng

func _checkerboard_board(w: int, h: int) -> BoardModel:
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

# ---------------------------------------------------- EngineEvent / stream --

func test_engine_event_construction_and_accessors() -> void:
	var e := EngineEvent.make(EngineEvent.MATCH_FOUND, {"size": 5, "color": &"red"})
	check_eq("type_set", e.type, EngineEvent.MATCH_FOUND)
	check_eq("payload_read", e.get_value("size"), 5)
	check_eq("payload_default", e.get_value("missing", -1), -1)

func test_stream_push_query_and_order() -> void:
	var s := GameplayEventStream.new()
	s.push(EngineEvent.MOVE_STARTED, {})
	s.push(EngineEvent.MATCH_FOUND, {"size": 3})
	s.push(EngineEvent.GEM_REMOVED, {"count": 3})
	s.push(EngineEvent.MATCH_FOUND, {"size": 4})
	check_eq("size", s.size(), 4)
	check_eq("count_of_match", s.count_of(EngineEvent.MATCH_FOUND), 2)
	check("has_type", s.has_type(EngineEvent.GEM_REMOVED))
	check("missing_type", not s.has_type(EngineEvent.LEVEL_FAILED))
	check_eq("first_type", s.types()[0], EngineEvent.MOVE_STARTED)
	check_eq("of_type_returns_both", s.of_type(EngineEvent.MATCH_FOUND).size(), 2)

func test_stream_extend_preserves_order() -> void:
	var s := GameplayEventStream.new()
	var batch: Array[EngineEvent] = [
		EngineEvent.make(EngineEvent.CASCADE_STARTED, {}),
		EngineEvent.make(EngineEvent.CASCADE_FINISHED, {"chain_depth": 2}),
	]
	s.extend(batch)
	check_eq("extended_size", s.size(), 2)
	check_eq("order_kept", s.types(), [EngineEvent.CASCADE_STARTED, EngineEvent.CASCADE_FINISHED] as Array[StringName])

# --------------------------------------------------- MoveEventTranslator --

func test_invalid_move_yields_no_events() -> void:
	var board := BoardModel.new(3, 3, 3)
	board.get_cell(Vector2i(0, 0)).color_id = &"red"
	board.get_cell(Vector2i(1, 0)).color_id = &"blue"
	var result := ChainResolver.resolve_move(board, _typed([Vector2i(0, 0), Vector2i(1, 0)]), _power_config(), _rng(), [&"red", &"blue"], 0.0)
	var events := MoveEventTranslator.events_for_move(result)
	check_eq("no_events_for_invalid_move", events.size(), 0)

func test_plain_three_match_event_sequence() -> void:
	var board := _checkerboard_board(5, 5)
	_paint(board, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)], &"red")
	var result := ChainResolver.resolve_move(board, _typed([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]), _power_config(), _rng(), [&"red", &"grayA", &"grayB"], 0.0)
	var s := GameplayEventStream.new()
	s.extend(MoveEventTranslator.events_for_move(result, {"kind": "match", "group_size": 3, "color": &"red"}))
	var t := s.types()
	check_eq("starts_with_move_started", t[0], EngineEvent.MOVE_STARTED)
	check_eq("then_cascade_started", t[1], EngineEvent.CASCADE_STARTED)
	check("has_match_found", s.has_type(EngineEvent.MATCH_FOUND))
	check_eq("match_size_carried", s.of_type(EngineEvent.MATCH_FOUND)[0].get_value("size"), 3)
	check_eq("gem_removed_count", s.of_type(EngineEvent.GEM_REMOVED)[0].get_value("count"), 3)
	check("no_power_created", not s.has_type(EngineEvent.POWER_CREATED))
	check("no_power_activated", not s.has_type(EngineEvent.POWER_ACTIVATED))
	check_eq("ends_with_cascade_finished", t[t.size() - 1], EngineEvent.CASCADE_FINISHED)
	check_eq("cascade_finished_depth", s.of_type(EngineEvent.CASCADE_FINISHED)[0].get_value("chain_depth"), 1)

func test_four_match_emits_formed_power_created() -> void:
	var board := _checkerboard_board(6, 6)
	_paint(board, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, 1)], &"red")
	var result := ChainResolver.resolve_move(board, _typed([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, 1)]), _power_config(), _rng(), [&"red", &"grayA", &"grayB"], 0.0)
	var s := GameplayEventStream.new()
	s.extend(MoveEventTranslator.events_for_move(result))
	check_eq("one_power_created", s.count_of(EngineEvent.POWER_CREATED), 1)
	check("power_created_flagged_formed", s.of_type(EngineEvent.POWER_CREATED)[0].get_value("formed"))
	check_eq("power_id_is_bomb", String(s.of_type(EngineEvent.POWER_CREATED)[0].get_value("power_id")), "bomb")
	check("no_activation_on_formation", not s.has_type(EngineEvent.POWER_ACTIVATED))

func test_power_tap_emits_activation_and_cascade_steps() -> void:
	var board := _checkerboard_board(6, 6)
	board.get_cell(Vector2i(2, 2)).color_id = &"red"
	board.get_cell(Vector2i(2, 2)).power_id = &"bomb"
	var result := ChainResolver.resolve_power_tap(board, Vector2i(2, 2), _power_config(), _rng(), [&"red", &"grayA"], 0.0)
	var s := GameplayEventStream.new()
	s.extend(MoveEventTranslator.events_for_move(result, {"kind": "power_tap"}))
	check("has_power_activated", s.has_type(EngineEvent.POWER_ACTIVATED))
	check_eq("activation_power_is_bomb", String(s.of_type(EngineEvent.POWER_ACTIVATED)[0].get_value("power_id")), "bomb")
	check("has_cascade_step", s.has_type(EngineEvent.CASCADE_STEP))
	check_eq("cascade_finished_depth_two", s.of_type(EngineEvent.CASCADE_FINISHED)[0].get_value("chain_depth"), 2)
	# a power tap has no separate initial clear — every wave is a cascade step
	check("no_match_found_on_power_tap", not s.has_type(EngineEvent.MATCH_FOUND))
	check_eq("step_count_matches_waves", s.count_of(EngineEvent.CASCADE_STEP), result.wave_cells.size())

func test_obstacle_cleared_event_from_blast() -> void:
	var board := _checkerboard_board(6, 6)
	board.get_cell(Vector2i(2, 2)).color_id = &"red"
	board.get_cell(Vector2i(2, 2)).power_id = &"bomb"
	board.set_obstacle(Vector2i(1, 1), &"stone", 0)
	var result := ChainResolver.resolve_power_tap(board, Vector2i(2, 2), _power_config(), _rng(), [&"red", &"grayA"], 0.0)
	var s := GameplayEventStream.new()
	s.extend(MoveEventTranslator.events_for_move(result))
	var found_stone := false
	for e in s.of_type(EngineEvent.OBSTACLE_CLEARED):
		if String(e.get_value("obstacle_id")) == "stone":
			found_stone = true
	check("stone_obstacle_cleared_event", found_stone)

func test_translation_is_deterministic() -> void:
	var seq_a := _resolve_and_type_seq()
	var seq_b := _resolve_and_type_seq()
	check_eq("same_event_type_sequence_twice", seq_a, seq_b)

func _resolve_and_type_seq() -> Array:
	var board := _checkerboard_board(7, 7)
	board.get_cell(Vector2i(3, 3)).color_id = &"red"
	board.get_cell(Vector2i(3, 3)).power_id = &"bomb"
	_paint(board, [Vector2i(5, 3), Vector2i(5, 4), Vector2i(5, 5)], &"purple")
	var result := ChainResolver.resolve_power_tap(board, Vector2i(3, 3), _power_config(), _rng(), [&"red", &"grayA", &"grayB", &"purple"], 0.0)
	var out: Array = []
	for e in MoveEventTranslator.events_for_move(result):
		out.append(e.type)
	return out
