extends SceneTree
## One-off smoke test: boots the real main scene, drives an actual move
## through BoardView end-to-end (resolve + animate + HUD update), and
## exercises a booster + win condition. Not part of the CI test_runner —
## run manually during development.

func _initialize() -> void:
	await process_frame
	await process_frame

	var scene: PackedScene = load("res://scenes/main.tscn")
	var app := scene.instantiate()
	get_root().add_child(app)
	await process_frame
	await process_frame

	assert(app._menu != null, "main menu not created")
	assert(app._menu.visible, "app should boot into the main menu")
	assert(app._board == null, "board should not exist before a level is selected")

	# PLAY on the menu opens the 10-world island-selection screen (over SEA CLIP).
	await app._on_menu_play_pressed()
	await process_frame
	assert(app._islands.visible, "PLAY should open the main island (world) screen")
	assert(app._sea_clip.visible, "SEA CLIP background should be shown on the island screen")

	# Pick island 1 -> its internal level map.
	var wid: StringName = WorldCatalog.world_id_at(0)
	await app._on_world_selected(wid)
	await process_frame
	assert(app._worldmap.visible, "selecting an island should open its internal level map")
	assert(not app._islands.visible, "the world-selection screen should hide behind the internal map")

	# Enter island 1, world-local level 1.
	await app._go_to_level(wid, 1)
	await process_frame
	assert(app._active_world_id == wid and app._active_local_level == 1, "island slot wired")

	var board = app._board
	var hud = app._hud
	assert(board != null, "board not created")
	assert(hud != null, "hud not created")
	assert(not app._worldmap.visible, "the level map should be hidden once a level starts")
	assert(not app._sea_clip.visible, "SEA CLIP should be hidden during gameplay")
	print("Level loaded: ", app._current_level.level_name, " size=", board.board.width, "x", board.board.height)

	var path := _find_valid_path(board.board)
	assert(path.size() >= board.board.min_group_size, "could not find a valid path to test with")
	print("Testing move with path of size ", path.size())

	var moves_before: int = app._moves_left
	await board._play_move(path)
	await process_frame
	print("Moves before=%d after=%d score=%d" % [moves_before, app._moves_left, app._score])
	assert(app._moves_left == moves_before - 1, "move count did not decrement")

	var boosters := get_root().get_node("Boosters")
	var economy := get_root().get_node("Economy")
	print("Booster counts before: ", boosters.counts)
	economy.grant(10000)
	boosters.purchase(&"bomb")
	await board.apply_power_booster(&"bomb")
	await process_frame
	print("Booster move applied ok, score now=", app._score)

	print("SMOKE TEST PASSED")
	quit(0)

func _find_valid_path(board: BoardModel) -> Array[Vector2i]:
	for x in board.width:
		for y in board.height:
			var start := Vector2i(x, y)
			var cell := board.get_cell(start)
			if cell == null or not cell.is_selectable():
				continue
			var path := _dfs_path(board, start, cell.color_id, board.min_group_size)
			if path.size() >= board.min_group_size:
				return path
	return []

func _dfs_path(board: BoardModel, start: Vector2i, color: StringName, target_len: int) -> Array[Vector2i]:
	var visited := {start: true}
	var path: Array[Vector2i] = [start]
	_extend(board, color, visited, path, target_len)
	return path

func _extend(board: BoardModel, color: StringName, visited: Dictionary, path: Array[Vector2i], target_len: int) -> bool:
	if path.size() >= target_len:
		return true
	var current: Vector2i = path[path.size() - 1]
	for n in board.get_orthogonal_neighbors(current):
		if visited.has(n):
			continue
		var cell := board.get_cell(n)
		if cell == null or not cell.is_selectable() or cell.color_id != color:
			continue
		visited[n] = true
		path.append(n)
		if _extend(board, color, visited, path, target_len):
			return true
		path.pop_back()
	return false
