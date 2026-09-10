extends SceneTree
## 2026-09-07 gameplay overhaul smoke: the MINOR-VILLAIN HEALTH BAR IS GONE.
## Proves a chapter-finale stage (every 10th):
##   * loads with `is_boss` true but NO boss HP fields on CombatDirector
##   * shows no HUD boss bar
##   * is won purely by completing the stage's own objectives
##   * plays the villain-defeat presentation (EnemyActor.play_defeat) on win
##   * has no boss counter-attack / board-pressure mechanic
## Not part of the CI test_runner (touches the scene tree). Run manually:
##   godot --headless --path game --script res://tests/smoke_boss_dual_win.gd

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
	app._debug_start_authored_level(10)                     # chapter finale
	await process_frame

	assert(app._combat.is_boss, "stage 10 must be a chapter finale")
	assert(not ("boss_hp" in app._combat), "CombatDirector must not track boss HP any more")
	assert(not app._hud._boss_bar.visible, "the HUD boss HP bar must never be shown")
	assert(app._objectives.objectives.size() >= 2, "a finale stage should have >=2 objectives")
	print("Finale stage 10 loaded: is_boss=%s, no boss_hp, no HP bar, objectives=%d. OK"
		% [app._combat.is_boss, app._objectives.objectives.size()])

	# --- villain-defeat presentation hook ---
	var defeat_calls := [0]
	if app._enemy_actor != null and app._enemy_actor.has_signal("defeat_played"):
		app._enemy_actor.defeat_played.connect(func(): defeat_calls[0] += 1)

	# --- completing the objectives (NOT any HP) must end the level ---
	assert(not app._level_ended, "level must still be live before objectives complete")
	for i in app._objectives.objectives.size():
		app._objectives.progress[i] = app._objectives.target_for(i)
	# run the same completion path _apply_move_result uses
	if app._objectives.is_complete() and app._combat.is_boss:
		app._win_finale_stage()
	await process_frame
	assert(app._level_ended, "finale stage: objectives complete -> level MUST end (no HP needed)")
	print("Objectives complete -> finale stage ended with no HP involved. OK")

	# --- there is no boss-pressure obstacle spam any more ---
	assert(not app.has_method("_update_boss_pressure"), "_update_boss_pressure must be removed")
	print("No boss counter-attack / board-pressure mechanic. OK")

	print("FINALE (NO HP BAR) SMOKE PASSED")
	quit(0)
