extends SceneTree
## Manual dev tool: boots the real game and drives the corrected per-ISLAND
## progression end to end — PLAY -> 10 islands -> island 1 -> its internal
## level map -> play level 1 -> win -> return to map -> level 2 unlocked.
## Then the exact bug repro: clear island 1 level 10 and assert island 1
## level 11 unlocks while island 2 stays LOCKED.
##
## Not part of the CI test_runner. Uses a fresh IslandProgress (reset()) so it
## does not depend on other tests' save state.

func _initialize() -> void:
	await process_frame
	await process_frame

	var scene: PackedScene = load("res://scenes/main.tscn")
	var app := scene.instantiate()
	get_root().add_child(app)
	await process_frame
	await process_frame

	var ip := get_root().get_node("IslandProgress")
	ip.reset()

	var w1: StringName = WorldCatalog.world_id_at(0)
	var w2: StringName = WorldCatalog.world_id_at(1)

	if not app._menu.visible or app._board != null:
		push_error("should boot into the main menu with no level running"); quit(1); return

	await app._on_menu_play_pressed()
	await process_frame
	if not app._islands.visible or not app._sea_clip.visible:
		push_error("PLAY should open the island screen with SEA CLIP behind it"); quit(1); return
	if WorldCatalog.count() != 10:
		push_error("expected 10 islands"); quit(1); return

	# --- initial lock state ---
	if not ip.is_level_unlocked(w1, 1):
		push_error("island 1 level 1 must start unlocked"); quit(1); return
	if ip.is_level_unlocked(w1, 2):
		push_error("island 1 level 2 must start LOCKED"); quit(1); return
	if ip.is_island_unlocked(w2):
		push_error("island 2 must start LOCKED"); quit(1); return

	# --- enter island 1 ---
	await app._on_world_selected(w1)
	await process_frame
	if not app._worldmap.visible or app._worldmap.world_id != w1:
		push_error("selecting island 1 should open its internal map"); quit(1); return
	if not app._sea_clip.visible:
		push_error("SEA CLIP must stay on the internal map"); quit(1); return

	var pooled: int = app._worldmap._scroller.live_node_count()
	if pooled > InfiniteLevelScroller.POOL_SIZE:
		push_error("scroller pool exceeded its bound"); quit(1); return
	app._worldmap._scroller.debug_scroll_to_local_level(90)
	await process_frame
	if app._worldmap._scroller.live_node_count() != pooled:
		push_error("far scroll must not create more nodes"); quit(1); return
	app._worldmap._scroller.setup(w1)

	# --- play + win island 1 level 1 THROUGH the real app win flow ---
	_win_via_app(app, w1, 1)
	await process_frame
	if not ip.is_level_completed(w1, 1):
		push_error("level 1 should be completed via app._on_level_won"); quit(1); return
	if not ip.is_level_unlocked(w1, 2):
		push_error("completing island 1 level 1 must unlock island 1 level 2"); quit(1); return
	if ip.is_level_unlocked(w1, 3):
		push_error("island 1 level 3 must still be locked"); quit(1); return

	# --- THE BUG REPRO: clear island 1 up to level 10 ---
	for n in range(2, 11):
		ip.record_completion(w1, n, 3, 1000)
		await process_frame
	if not ip.is_level_completed(w1, 10):
		push_error("island 1 level 10 should be completed"); quit(1); return
	if not ip.is_level_unlocked(w1, 11):
		push_error("completing island 1 level 10 must unlock island 1 level 11"); quit(1); return
	if ip.is_island_unlocked(w2):
		push_error("BUG: completing island 1 level 10 must NOT unlock island 2"); quit(1); return
	if ip.is_level_unlocked(w2, 1):
		push_error("BUG: island 2 level 1 must still be LOCKED"); quit(1); return
	print("Bug repro OK: island 1 L11 unlocked, island 2 still locked.")

	# --- return to map, still island 1 ---
	app._active_world_id = w1
	app._active_local_level = 10
	await app._go_to_map()
	if not app._worldmap.visible or app._worldmap.world_id != w1:
		push_error("Quit to Map should return to island 1's map"); quit(1); return
	if WorldCatalog.node_state(w1, 11) == &"locked":
		push_error("map should show island 1 level 11 as reachable"); quit(1); return

	# --- finish island 1 (levels 11..100) -> island 2 unlocks ---
	for n in range(11, 101):
		ip.record_completion(w1, n, 3, 1000)
	await process_frame
	if not ip.is_island_complete(w1):
		push_error("island 1 should be complete after level 100"); quit(1); return
	if not ip.is_island_unlocked(w2):
		push_error("completing island 1 level 100 must unlock island 2"); quit(1); return
	if not ip.is_level_unlocked(w2, 1):
		push_error("island 2 level 1 must be unlocked once island 2 opens"); quit(1); return
	if ip.is_level_unlocked(w2, 2):
		push_error("island 2 level 2 must still be locked"); quit(1); return

	# island 2 level 1 -> level 2, but level 10 must NOT touch island 3
	_win_via_app(app, w2, 1)
	await process_frame
	if not ip.is_level_unlocked(w2, 2):
		push_error("island 2 level 1 completion must unlock island 2 level 2"); quit(1); return
	for n in range(2, 11):
		ip.record_completion(w2, n, 3, 1000)
	var w3: StringName = WorldCatalog.world_id_at(2)
	if ip.is_island_unlocked(w3):
		push_error("island 2 level 10 must NOT unlock island 3"); quit(1); return
	if not ip.is_level_unlocked(w2, 11):
		push_error("island 2 level 11 should be unlocked"); quit(1); return

	print("LEVEL MAP SMOKE TEST PASSED")
	quit(0)

## Wins a world-local level THROUGH the real app win flow (integration check
## that app._on_level_won records into IslandProgress with the right slot).
func _win_via_app(app, world_id: StringName, local_level: int) -> void:
	var authored := WorldCatalog.authored_level_id(world_id, local_level)
	app._active_world_id = world_id
	app._active_local_level = local_level
	app._start_level(authored)
	app._level_ended = false
	app._moves_left = app._current_level.move_limit
	app._score = 999999
	app._on_level_won()
	app._hud.hide_end_panel()
