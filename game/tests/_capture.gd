extends SceneTree
## DEV TOOL (not a test): boots the real main scene and writes PNG
## screenshots of each screen to user://shots/ for out-of-editor review.
##   godot --path game --script res://tests/_capture.gd
## Uses only `await process_frame` — a SceneTree script deadlocks on
## SceneTree.create_timer.

const OUT := "user://shots"

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _initialize() -> void:
	await _frames(3)
	DirAccess.make_dir_recursive_absolute(OUT)
	var save := get_root().get_node("SaveService")
	save.set_int("coins", 1240)
	save.set_int("gems", 350)

	var app = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(app)

	await _frames(12)
	await _shot("00_splash")

	# let the splash run its ~1.25s and free itself
	await _frames(150)
	await _shot("01_menu")

	await app._on_menu_play_pressed()
	await _frames(30)
	await _shot("02_map")

	var gd = get_root().get_node("GameData")
	await app._go_to_level(gd.levels.first_level_id())
	await _frames(40)
	await _shot("03_gameplay")

	var board = app._board
	for pass_i in 3:
		var raw := _find_path(board.board)
		if raw.size() >= board.board.min_group_size:
			var path: Array[Vector2i] = []
			for p in raw:
				path.append(p)
			await board._play_move(path)
			await _frames(30)
	await _shot("04_gameplay_played")

	get_root().get_node("Economy").grant(500)
	app._on_level_won()
	await _frames(70)
	await _shot("05_win")

	app._hud.hide_end_panel()
	await app._go_to_level(gd.levels.first_level_id())
	await _frames(20)
	app._hud.show_pause_panel(true)
	await _frames(25)
	await _shot("06_pause")
	app._hud.show_pause_panel(false)

	# Daily rewards screen
	get_root().get_node("SaveService").set_int("daily_last_claim_day", -1)
	get_root().get_node("SaveService").set_int("daily_streak", 0)
	app._daily.refresh()
	app._daily.visible = true
	app._daily.modulate.a = 1.0
	await _frames(25)
	await _shot("07_daily")
	app._daily.visible = false

	# Reward popup (chest open)
	var rp = load("res://scripts/ui/reward_popup.gd").present(app._hud, [
		{"type": "coins", "amount": 380},
		{"type": "booster", "id": &"bomb", "amount": 1},
	], {"title": "Milestone Chest!"})
	await _frames(120)
	await _shot("08_reward_chest")
	if is_instance_valid(rp):
		rp.queue_free()
	await _frames(3)

	# Fever mode (forced on)
	board = app._board
	app._fever.moves_remaining = 6
	app._was_fever = false
	board.set_fever(true)
	app._backdrop.set_accent_target(Color(1.0, 0.24, 0.52), 0.1)
	app._hud.set_fever(60.0, 100.0, true)
	board.play_fever_burst()
	await _frames(20)
	var fp := _find_path(board.board)
	if fp.size() >= board.board.min_group_size:
		var fpath: Array[Vector2i] = []
		for p in fp:
			fpath.append(p)
		await board._play_move(fpath)
	await _frames(30)
	await _shot("09_fever")

	# Time bomb level
	board.set_fever(false)
	await app._go_to_level(28)
	await _frames(40)
	await _shot("10_timebomb_level")

	print("shots -> ", ProjectSettings.globalize_path(OUT))
	quit(0)

func _shot(name: String) -> void:
	await _frames(2)
	var tex := get_root().get_texture()
	if tex == null:
		print("  no texture -> skip ", name); return
	var img := tex.get_image()
	if img == null:
		print("  null image -> skip ", name); return
	img.save_png("%s/%s.png" % [OUT, name])
	print("  saved ", name, " ", img.get_size())

func _find_path(board) -> Array:
	for x in board.width:
		for y in board.height:
			var start := Vector2i(x, y)
			var cell = board.get_cell(start)
			if cell == null or not cell.is_selectable():
				continue
			var visited := {start: true}
			var p: Array = [start]
			if _extend(board, cell.color_id, visited, p, board.min_group_size + 2):
				return p
	return []

func _extend(board, color, visited: Dictionary, path: Array, target_len: int) -> bool:
	if path.size() >= target_len:
		return true
	for n in board.get_orthogonal_neighbors(path[path.size() - 1]):
		if visited.has(n):
			continue
		var cell = board.get_cell(n)
		if cell == null or not cell.is_selectable() or (cell.color_id != color and cell.color_id != BoardModel.RAINBOW_COLOR_ID):
			continue
		visited[n] = true
		path.append(n)
		if _extend(board, color, visited, path, target_len):
			return true
		path.pop_back()
	return false
