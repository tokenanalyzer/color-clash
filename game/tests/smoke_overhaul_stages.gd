extends SceneTree
## 2026-09-07 gameplay-overhaul smoke: boots the REAL game and steps through
## the representative stages from the brief (1,3,5,10,11,20,21,30,40,49,50),
## asserting for each:
##   * the level loads and the board has a valid move (never a dead board)
##   * objectives are wired and non-trivial
##   * NO boss HP bar is shown on the finale stages
##   * the backdrop scene matches the stage's island theme
##   * escort stages seat the Love Crystal(s) on the board and it is
##     inert to selection but movable by gravity
##   * a handful of real moves resolve with no crash and score climbs
## Not part of CI (touches the scene tree). Run manually:
##   godot --headless --path game --script res://tests/smoke_overhaul_stages.gd

const STAGES := [1, 3, 5, 10, 11, 20, 21, 30, 40, 49, 50]
const FINALES := [10, 20, 30, 40, 50]
const ISLAND_ENV := [
	"env_floating_islands", "env_crystal_formations", "env_large_structures",
	"env_clouds_mists", "env_aurora_energy_bands",
]

func _initialize() -> void:
	await process_frame
	await process_frame
	var app := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(app)
	await process_frame
	await process_frame
	await app._on_menu_play_pressed()
	await process_frame

	var failures := 0
	for sid: int in STAGES:
		app._debug_start_authored_level(sid)
		await process_frame
		await process_frame
		var ok: bool = await _check_stage(app, sid)
		if not ok:
			failures += 1
		app._hud.hide_end_panel()

	if failures == 0:
		print("OVERHAUL STAGES SMOKE PASSED (%d stages)" % STAGES.size())
		quit(0)
	else:
		print("OVERHAUL STAGES SMOKE FAILED (%d stage(s))" % failures)
		quit(1)

func _check_stage(app, sid: int) -> bool:
	var board = app._board
	var lc = app._current_level
	var ok := true
	var tag := "L%d" % sid

	if board == null or lc == null:
		print("%s: FAILED to load" % tag); return false
	if not board.board.has_any_valid_move():
		print("%s: dead board on load" % tag); ok = false
	if app._objectives == null or app._objectives.objectives.is_empty():
		print("%s: no objectives" % tag); ok = false
	if app._objectives.is_complete():
		print("%s: objectives already complete at load" % tag); ok = false

	# finale stages: chapter finale flag but NO HP bar, NO boss_hp
	if sid in FINALES:
		if not app._combat.is_boss:
			print("%s: finale stage not flagged is_boss" % tag); ok = false
		if "boss_hp" in app._combat:
			print("%s: CombatDirector still has boss_hp!" % tag); ok = false
		if app._hud._boss_bar.visible:
			print("%s: boss HP bar is visible!" % tag); ok = false
	else:
		if app._combat.is_boss:
			print("%s: non-finale flagged is_boss" % tag); ok = false

	# backdrop follows the island
	var isl := (sid - 1) / 10
	var want_env: String = ISLAND_ENV[isl]
	if String(app._backdrop.scene_id) != want_env:
		print("%s: backdrop is '%s', expected island theme '%s'" % [tag, app._backdrop.scene_id, want_env]); ok = false

	# escort stages: the crystal is really on the board and inert to selection
	if not lc.specials.is_empty():
		var relics: Array = board.board.special_positions()
		if relics.size() != lc.specials.size():
			print("%s: %d crystals in data but %d on board" % [tag, lc.specials.size(), relics.size()]); ok = false
		for rp: Vector2i in relics:
			var c = board.board.get_cell(rp)
			if c.is_selectable():
				print("%s: crystal at %s is selectable (must not be)" % [tag, rp]); ok = false
			if not c.has_movable_content():
				print("%s: crystal at %s not gravity-movable" % [tag, rp]); ok = false

	# play a few real moves — no crash, score climbs
	var start_score: int = int(app._score)
	var moves_made := 0
	for i in 6:
		if app._level_ended:
			break
		var path := _find_path(board.board)
		if path.size() < board.board.min_group_size:
			break
		await board._play_move(path)
		await process_frame
		moves_made += 1
	if moves_made > 0 and app._score <= start_score and not app._level_ended:
		print("%s: %d moves made but score did not climb (%d)" % [tag, moves_made, app._score]); ok = false
	if not app._level_ended and not board.board.has_any_valid_move():
		print("%s: board dead after %d moves and no reshuffle" % [tag, moves_made]); ok = false

	print("%s: OK  goals=%d obs=%d crystals=%d env=%s moves=%d score=%d%s"
		% [tag, app._objectives.objectives.size(), lc.obstacles.size(), lc.specials.size(),
		   app._backdrop.scene_id, moves_made, app._score,
		   "  [ENDED]" if app._level_ended else ""])
	return ok

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
