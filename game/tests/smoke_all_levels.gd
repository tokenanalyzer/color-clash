extends SceneTree
## Manual dev tool: instantiates every campaign level's board (all obstacle
## types, all sizes) to catch generation/layout crashes early. Not part of
## the CI test_runner (it touches the scene tree), run manually.
##
## Deliberately avoids referencing BoardView/LevelConfig as bare
## class_name identifiers: as the --script entry point, this file's own
## dependency graph is compiled before autoloads are registered, and
## board_view.gd (transitively) references the Audio/Haptics autoloads —
## load()-ing it dynamically instead sidesteps that ordering issue. This
## is purely a test-harness quirk; the real game boots this exact code
## path fine (see the successful `--quit-after 30` and smoke_main_e2e.gd
## runs), since scenes are loaded lazily after autoloads are ready.

func _initialize() -> void:
	await process_frame
	await process_frame

	var game_data := get_root().get_node("GameData")
	var board_view_script := load("res://scripts/board/board_view.gd")

	var root_node := Node2D.new()
	get_root().add_child(root_node)

	var failures := 0
	for level_id in game_data.levels.ordered_ids:
		var level = game_data.levels.get_level(level_id)
		var board = board_view_script.new()
		root_node.add_child(board)
		var rainbow_chance := float(game_data.power_config.get_definition(&"rainbow").get("refill_spawn_chance", 0.0))
		board.setup(level, game_data.colors, game_data.power_config, rainbow_chance, level_id * 991, Rect2(Vector2.ZERO, Vector2(1080, 1500)))
		var ok: bool = board.has_valid_moves()
		print("Level %2d (%dx%d, %s, obstacles=%d): %s" % [level.id, level.width, level.height, level.difficulty, level.obstacles.size(), "OK" if ok else "NO VALID MOVE"])
		if not ok:
			failures += 1
		board.queue_free()

	print("---- All levels checked. Failures: %d ----" % failures)
	quit(1 if failures > 0 else 0)
