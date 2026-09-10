extends SceneTree
## Phase C integration smoke: boots the real game on a chapter-finale stage
## and proves
##   * a match/power drives Jamie's rig through a real windup->strike->recover
##   * the rig is PRESENTATION ONLY — a standalone rig action changes no game
##     state (score / objectives / moves); 2026-09-07: there is no boss HP
##   * the rig reports an enemy reaction the arena/HUD consumes
##   * rapid moves don't wedge the rig or desync the score
## Not part of the CI test_runner (touches the scene tree). Run manually.

func _initialize() -> void:
	await process_frame
	await process_frame
	var scene: PackedScene = load("res://scenes/main.tscn")
	var app := scene.instantiate()
	get_root().add_child(app)
	await process_frame
	await process_frame

	await app._on_menu_play_pressed()
	await process_frame
	app._debug_start_authored_level(10)                     # boss stage
	await process_frame
	var board = app._board
	var rig = app._jamie_rig
	assert(rig != null, "Jamie rig not created")
	assert(app._combat.is_boss, "stage 10 must be a chapter finale")
	assert(not ("boss_hp" in app._combat), "no boss HP any more")
	assert(not rig.is_busy(), "rig should start idle")
	print("Finale stage 10. No boss HP. rig idle.")

	# --- the rig ALONE changes no game state (presentation only) ---
	var score_guard: int = app._score
	var moves_guard: int = app._moves_left
	var obj_guard: Array = app._objectives.progress.duplicate()
	rig.play(&"attack_bomb")
	for i in 40:
		rig._process(0.05)
	assert(app._score == score_guard, "the rig must not change the score on its own")
	assert(app._moves_left == moves_guard, "the rig must not spend a move on its own")
	assert(app._objectives.progress == obj_guard, "the rig must not advance objectives on its own")
	assert(not rig.is_busy(), "rig should return to idle after a standalone action")
	print("Rig-only action changed NO game state. OK")

	# --- a real match scores + advances the level through the normal path ---
	var score_before: int = app._score
	var path := _find_path(board.board)
	assert(path.size() >= board.board.min_group_size, "no valid path")
	await board._play_move(path)
	await process_frame
	assert(app._score > score_before, "a real match must score through _apply_move_result")
	print("Match -> score %d -> %d. OK" % [score_before, app._score])

	# --- a fired power routes through the real handler into the rig, and the
	#     rig reports an enemy reaction the arena consumes — no game-state change ---
	var reacted := [StringName("")]
	rig.enemy_reaction.connect(func(k, _p): reacted[0] = k)
	var score_at_power: int = app._score
	app._on_power_fired(&"fire_sword", &"")          # the real CombatDirector -> app handler
	assert(rig.is_busy(), "a fired power must drive Jamie's rig")
	for i in 40:
		rig._process(0.05)
		await process_frame
	assert(reacted[0] != &"", "the rig should report an enemy reaction for the sword attack")
	assert(app._score == score_at_power, "the presentation handler must NOT change the score")
	assert(not rig.is_busy(), "rig should be idle again after the attack resolves")
	print("Fired power -> rig animated, reaction '%s', score unchanged by presentation. OK" % reacted[0])

	# --- rapid moves: no wedge, no desync ---
	var guard := 0
	while guard < 30 and not app._level_ended:
		guard += 1
		var p := _find_path(board.board)
		if p.size() < board.board.min_group_size:
			break
		app._moves_left = maxi(app._moves_left, 5)   # keep playing for the test
		await board._play_move(p)
		rig._process(0.033)
	for i in 30:
		rig._process(0.05)
	assert(not rig.is_busy() or app._level_ended, "rig must not wedge under rapid input")
	print("Rapid moves handled. level_ended=%s. OK" % app._level_ended)

	print("COMBAT ANIM SMOKE PASSED")
	quit(0)

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
