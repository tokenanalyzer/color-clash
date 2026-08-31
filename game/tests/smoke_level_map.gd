extends SceneTree
## Manual dev tool: boots the real game to confirm the campaign map screen
## works end to end — boots into the main menu, PLAY opens the map (not
## straight into a level), selecting an unlocked node transitions into
## play, winning a level
## records progress/stars and unlocks the next node, and a not-yet-reached
## level stays locked. Not part of the CI test_runner; run manually after
## any map/progress change.
##
## Note: other smoke tests / unit tests persist to the same user://save.json,
## so this avoids hard-asserting on levels those may have already touched
## (level 1, and levels 24/25 which test_progress.gd uses) — it works with
## whatever the current save state is rather than assuming a pristine one.

func _initialize() -> void:
	await process_frame
	await process_frame

	var scene: PackedScene = load("res://scenes/main.tscn")
	var app := scene.instantiate()
	get_root().add_child(app)
	await process_frame
	await process_frame

	var progress := get_root().get_node("Progress")
	var game_data := get_root().get_node("GameData")
	var first_id: int = game_data.levels.first_level_id()
	var second_id: int = game_data.levels.next_level_id(first_id)
	# A level deep enough that nothing else in the test suite plays through
	# to it sequentially, so it should reliably still be locked.
	var far_id: int = game_data.levels.ordered_ids[14]

	print("App booted. Menu visible=", app._menu.visible, " board=", app._board)
	if not app._menu.visible or app._board != null:
		push_error("should boot into the main menu with no level running")
		quit(1)
		return

	# PLAY opens the campaign map.
	await app._on_menu_play_pressed()
	await process_frame
	print("After PLAY. Map visible=", app._map.visible)
	if not app._map.visible:
		push_error("PLAY should open the campaign map")
		quit(1)
		return

	var first_btn: LevelNodeButton = app._map._node_buttons[first_id]
	var far_btn: LevelNodeButton = app._map._node_buttons[far_id]
	print("Level %d state=%s disabled=%s" % [first_id, first_btn.state, first_btn.disabled])
	print("Level %d state=%s disabled=%s" % [far_id, far_btn.state, far_btn.disabled])
	if first_btn.disabled:
		push_error("the first campaign level must always be selectable")
		quit(1)
		return
	if not progress.is_completed(far_id) and not far_btn.disabled:
		push_error("a not-yet-reached level must be locked/disabled")
		quit(1)
		return

	print("Selecting level %d from the map..." % first_id)
	app._map.level_selected.emit(first_id)
	await process_frame
	var guard := 0
	while app._board == null and guard < 120:
		await process_frame
		guard += 1
	if app._board == null or app._map.visible:
		push_error("selecting a level from the map should start it and hide the map")
		quit(1)
		return
	print("Level started via map tap: ", app._current_level.level_name)

	print("Forcing a win to test progress recording + unlock...")
	var score_before: int = progress.get_best_score(first_id)
	app._moves_left = app._current_level.move_limit # finishing with a full move budget -> 3 stars
	app._score = score_before + 999
	app._on_level_won()
	await process_frame
	if not progress.is_completed(first_id):
		push_error("level should be marked completed after winning")
		quit(1)
		return
	if progress.get_stars(first_id) != 3:
		push_error("finishing with a full move budget should award 3 stars")
		quit(1)
		return
	if not progress.is_unlocked(second_id):
		push_error("completing a level should unlock the next one")
		quit(1)
		return
	print("Progress recorded: stars=%d, next level %d unlocked=%s" % [progress.get_stars(first_id), second_id, progress.is_unlocked(second_id)])

	print("Returning to the map...")
	await app._go_to_map()
	var refreshed_first_btn: LevelNodeButton = app._map._node_buttons[first_id]
	var refreshed_second_btn: LevelNodeButton = app._map._node_buttons[second_id]
	if refreshed_first_btn.state != &"completed":
		push_error("map should reflect the completed level")
		quit(1)
		return
	if refreshed_second_btn.state == &"locked":
		push_error("map should reflect the newly-unlocked level")
		quit(1)
		return
	print("Map refreshed: level %d=%s, level %d=%s" % [first_id, refreshed_first_btn.state, second_id, refreshed_second_btn.state])

	print("LEVEL MAP SMOKE TEST PASSED")
	quit(0)
