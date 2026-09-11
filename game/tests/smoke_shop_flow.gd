extends SceneTree
## Phase B integration smoke: boots the real main scene and walks the whole
## in-level economy loop —
##
##   PART A (boss stage 10): match -> open shop (board frozen) -> buy booster
##     -> close shop -> USE a booster -> booster detonation feeds
##     CombatDirector and the boss takes damage.
##   PART B (a normal stage): run out of moves -> "Need More Moves?" ->
##     buy +5 -> the SAME board / objectives / score resume (no reset) ->
##     on the next fail, decline -> normal loss.
##
## Not part of the CI test_runner (touches the scene tree) — run manually.

func _initialize() -> void:
	await process_frame
	await process_frame

	var scene: PackedScene = load("res://scenes/main.tscn")
	var app := scene.instantiate()
	get_root().add_child(app)
	await process_frame
	await process_frame

	var economy := get_root().get_node("Economy")
	var boosters := get_root().get_node("Boosters")
	var game_data := get_root().get_node("GameData")
	economy.grant(8000)

	await app._on_menu_play_pressed()
	await process_frame

	# ================= PART A — boss stage 10 =========================
	app._debug_start_authored_level(10)
	await process_frame
	var board = app._board
	var hud = app._hud
	assert(board != null, "board not created")
	assert(app._combat != null and app._combat.is_boss, "stage 10 must be a chapter finale")
	assert(not ("boss_hp" in app._combat), "no boss HP any more (2026-09-07)")
	print("Finale stage 10 loaded. moves=%d" % app._moves_left)

	var path := _find_path(board.board)
	assert(path.size() >= board.board.min_group_size, "no valid path")
	await board._play_move(path)
	await process_frame
	var score_snap: int = app._score
	var moves_snap: int = app._moves_left
	var obj_snap := _obj_sig(app)
	var board_snap := _board_sig(board.board)

	# --- open shop: board + all gameplay state frozen ---
	app._on_shop_pressed()
	await process_frame
	assert(hud._booster_shop.is_open(), "shop did not open")
	assert(board._locked_input, "board must be frozen while the shop is open")
	assert(app._score == score_snap, "score changed while shop open")
	assert(app._moves_left == moves_snap, "moves changed while shop open")
	assert(_obj_sig(app) == obj_snap, "objective progress changed while shop open")
	assert(_board_sig(board.board) == board_snap, "board changed while shop open")
	print("Shop open on a finale stage — board/score/moves/objectives all frozen. OK")

	# --- buy a booster in-level ---
	var coins_before: int = economy.coins
	var bombs_before: int = boosters.get_count(&"bomb")
	hud._booster_shop.request_buy(&"bomb")
	assert(hud._booster_shop.confirm_buy(), "confirm_buy failed with plenty of coins")
	var bomb_cost: int = int(game_data.boosters[&"bomb"].get("cost", 0))
	assert(boosters.get_count(&"bomb") == bombs_before + 1, "bomb count did not increase")
	assert(economy.coins == coins_before - bomb_cost, "coins not deducted by the bomb price")
	assert(int(get_root().get_node("SaveService").get_int("coins", -1)) == economy.coins, "purchase not persisted")
	print("Bought Bomb in-level. coins %d -> %d, bombs %d -> %d, persisted. OK"
		% [coins_before, economy.coins, bombs_before, boosters.get_count(&"bomb")])

	# --- close shop: board unfrozen, nothing mutated by the visit ---
	hud._booster_shop.close()
	await process_frame
	assert(not hud._booster_shop.is_open(), "shop did not close")
	assert(not board._locked_input, "board still frozen after shop closed")
	assert(_board_sig(board.board) == board_snap, "board changed by a no-op shop visit")
	print("Shop closed, board unfrozen and unchanged. OK")

	# --- USE a targeted booster: it arms on the board ---
	boosters.add(&"lightning", 1)
	hud._booster_shop.open()
	hud._booster_shop.request_use(&"lightning")
	await process_frame
	assert(not hud._booster_shop.is_open(), "shop should close on USE")
	assert(app._armed_booster == &"lightning", "USE of a targeted booster should arm it on the board")
	board.disarm_booster()
	app._armed_booster = &""
	hud.set_booster_armed(&"")
	print("USE of Lightning armed the board booster. OK")

	# --- a booster detonation runs the normal resolve path and scores ---
	var score_pre_booster: int = app._score
	boosters.purchase(&"bomb")
	await board.apply_power_booster(&"bomb")
	await process_frame
	assert(app._score >= score_pre_booster,
		"a booster detonation must resolve through the board (score %d -> %d)"
		% [score_pre_booster, app._score])
	print("Booster detonation resolved through the board: score %d -> %d. OK"
		% [score_pre_booster, app._score])

	# ================= PART B — 'Need More Moves?' on a normal stage ===
	if app._level_ended:
		app._hud.hide_end_panel()
	app._debug_start_authored_level(13)
	await process_frame
	board = app._board
	assert(not app._combat.is_boss, "stage 13 should be a normal stage")
	assert(not app._level_ended, "fresh level should not be ended")

	# play down to the last move, then take it
	var pB := _find_path(board.board)
	assert(pB.size() >= board.board.min_group_size, "no valid path on stage 13")
	app._moves_left = 1
	hud.set_moves(1)
	await board._play_move(pB)
	await process_frame
	assert(app._moves_left == 0, "moves should have hit zero")
	assert(hud._moves_prompt.is_open(), "'Need More Moves?' prompt should be open")
	assert(not app._level_ended, "the level must NOT be failed while the prompt is up")
	assert(board._locked_input, "board should be frozen under the continue prompt")
	# snapshot AFTER the failing move resolved and the prompt is up — the
	# continue purchase must not perturb any of this
	var score_at_zero: int = app._score
	var obj_at_zero := _obj_sig(app)
	var board_at_zero := _board_sig(board.board)

	# buy +5 and resume the SAME level
	var coins_pre: int = economy.coins
	var cost5: int = game_data.continue_offers.cost_of(&"extra_moves_5")
	hud._moves_prompt._buy(&"extra_moves_5")
	await process_frame
	assert(app._moves_left == 5, "continue must add exactly 5 moves (got %d)" % app._moves_left)
	assert(not app._level_ended, "level must continue after buying moves")
	assert(economy.coins == coins_pre - cost5, "continue not charged correctly")
	assert(app._score == score_at_zero, "score changed by the continue purchase")
	assert(_obj_sig(app) == obj_at_zero, "objective progress changed by the continue purchase")
	assert(_board_sig(board.board) == board_at_zero, "board was reset by the continue purchase")
	assert(not board._locked_input, "board still frozen after the continue")
	print("Bought +5 moves — SAME board / score / objectives. No reset. OK")

	# next fail -> decline -> normal loss
	app._moves_left = 1
	hud.set_moves(1)
	var pC := _find_path(board.board)
	await board._play_move(pC)
	await process_frame
	assert(hud._moves_prompt.is_open(), "prompt should reopen at zero moves")
	hud._moves_prompt._decline()
	await process_frame
	assert(app._level_ended, "declining the continue should fail the level")
	print("Declined the continue -> normal loss. OK")

	print("SHOP + CONTINUE SMOKE PASSED")
	quit(0)

# ------------------------------------------------------------ helpers --

func _obj_sig(app) -> String:
	if app._objectives == null:
		return ""
	return ",".join(app._objectives.progress.map(func(v): return str(v)))

func _board_sig(board) -> String:
	var parts: Array[String] = []
	for x in board.width:
		for y in board.height:
			var c = board.get_cell(Vector2i(x, y))
			parts.append("_" if c == null else "%s|%s|%s" % [c.color_id, c.power_id, c.obstacle_id])
	return ",".join(parts)

func _find_path(board) -> Array[Vector2i]:
	for x in board.width:
		for y in board.height:
			var start := Vector2i(x, y)
			var cell = board.get_cell(start)
			if cell == null or not cell.is_selectable():
				continue
			var visited := {start: true}
			var path: Array[Vector2i] = [start]
			if _extend(board, cell.color_id, visited, path, board.min_group_size):
				return path
	return []

func _extend(board, color: StringName, visited: Dictionary, path: Array[Vector2i], want: int) -> bool:
	if path.size() >= want:
		return true
	for n in board.get_orthogonal_neighbors(path[path.size() - 1]):
		if visited.has(n):
			continue
		var cell = board.get_cell(n)
		if cell == null or not cell.is_selectable() or cell.color_id != color:
			continue
		visited[n] = true
		path.append(n)
		if _extend(board, color, visited, path, want):
			return true
		path.pop_back()
	return false
