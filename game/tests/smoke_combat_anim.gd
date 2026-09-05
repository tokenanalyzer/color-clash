extends SceneTree
## Phase C integration smoke: boots the real game on a boss stage and proves
##   * a match/power drives Jamie's rig through a real windup->strike->recover
##   * CombatDirector damage stays authoritative — the rig on its own never
##     changes boss HP (visual != damage)
##   * the rig reports an enemy reaction that the boss bar consumes
##   * rapid moves don't wedge the rig or desync the numbers
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
	await app._go_to_level(10)                     # boss stage
	await process_frame
	var board = app._board
	var rig = app._jamie_rig
	assert(rig != null, "Jamie rig not created")
	assert(app._combat.is_boss, "stage 10 must be a boss fight")
	assert(not rig.is_busy(), "rig should start idle")
	print("Boss stage. boss_hp=%d/%d" % [app._combat.boss_hp, app._combat.boss_hp_max])

	# --- the rig ALONE never deals damage (presentation != combat) ---
	var hp_guard: int = app._combat.boss_hp
	rig.play(&"attack_bomb")
	for i in 40:
		rig._process(0.05)
	assert(app._combat.boss_hp == hp_guard, "the rig must not change boss HP on its own")
	assert(not rig.is_busy(), "rig should return to idle after a standalone action")
	print("Rig-only action ran and dealt NO damage. boss_hp still %d. OK" % app._combat.boss_hp)

	# --- a real match damages the boss via CombatDirector (authoritative) ---
	var hp_before: int = app._combat.boss_hp
	var path := _find_path(board.board)
	assert(path.size() >= board.board.min_group_size, "no valid path")
	await board._play_move(path)
	await process_frame
	assert(app._combat.boss_hp < hp_before, "the match must damage the boss via CombatDirector (%d -> %d)"
		% [hp_before, app._combat.boss_hp])
	print("Match -> boss took %d dmg via CombatDirector (authoritative). OK" % [hp_before - app._combat.boss_hp])

	# --- a fired power routes through the real handler into the rig, and the
	#     rig reports an enemy reaction the boss bar consumes ---
	var reacted := [StringName("")]
	rig.enemy_reaction.connect(func(k, _p): reacted[0] = k)
	var hp_at_power: int = app._combat.boss_hp
	app._on_power_fired(&"fire_sword", &"")          # the real CombatDirector -> app handler
	assert(rig.is_busy(), "a fired power must drive Jamie's rig")
	for i in 40:
		rig._process(0.05)
		await process_frame
	assert(reacted[0] != &"", "the rig should report an enemy reaction for the sword attack")
	assert(app._combat.boss_hp == hp_at_power, "the presentation handler must NOT change boss HP")
	assert(not rig.is_busy(), "rig should be idle again after the attack resolves")
	print("Fired power -> rig animated, reaction '%s', boss HP unchanged by presentation. OK" % reacted[0])

	# --- rapid moves: no wedge, no desync ---
	var guard := 0
	while app._combat.boss_hp > 0 and guard < 40 and not app._level_ended:
		guard += 1
		var p := _find_path(board.board)
		if p.size() < board.board.min_group_size:
			break
		app._moves_left = maxi(app._moves_left, 5)   # keep playing for the test
		await board._play_move(p)
		rig._process(0.033)
	for i in 30:
		rig._process(0.05)
	assert(not rig.is_busy() or app._combat.boss_hp == 0, "rig must not wedge under rapid input")
	print("Rapid moves handled. boss_hp=%d level_ended=%s. OK" % [app._combat.boss_hp, app._level_ended])

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
