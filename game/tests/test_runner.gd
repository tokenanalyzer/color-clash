extends SceneTree
## Headless test entry point:
## godot --headless --path game --script res://tests/test_runner.gd
## Exits with code 1 if any test fails (CI-friendly).

const TEST_SCRIPTS := [
	"res://tests/test_board_model.gd",
	"res://tests/test_power_resolver.gd",
	"res://tests/test_chain_resolver.gd",
	"res://tests/test_power_combos.gd",
	"res://tests/test_score_calculator.gd",
	"res://tests/test_objective.gd",
	"res://tests/test_level_design.gd",
	"res://tests/test_fever_system.gd",
	"res://tests/test_economy.gd",
	"res://tests/test_synth.gd",
	"res://tests/test_sfx_builder.gd",
	"res://tests/test_music_layer_builder.gd",
	"res://tests/test_power_config.gd",
	"res://tests/test_star_rating.gd",
	"res://tests/test_progress.gd",
	"res://tests/test_freeze_power.gd",
	"res://tests/test_timebomb.gd",
	"res://tests/test_daily_rewards.gd",
	"res://tests/test_assets.gd",
	"res://tests/test_event_stream.gd",
	"res://tests/test_island_model.gd",
	"res://tests/test_island_assets.gd",
	"res://tests/test_story_assets.gd",
	"res://tests/test_enemy_model.gd",
	"res://tests/test_boss_progression.gd",
	"res://tests/test_ads_service.gd",
	"res://tests/test_story_data.gd",
	"res://tests/test_combat_system.gd",
	"res://tests/test_inventory.gd",
	"res://tests/test_shop_continue.gd",
	"res://tests/test_jamie_actions.gd",
	"res://tests/test_jasmine_actor.gd",
	"res://tests/test_story_scene.gd",
	"res://tests/test_ui_assets.gd",
	"res://tests/test_special_object.gd",
	"res://tests/test_gameplay_progression.gd",
	"res://tests/test_world_system.gd",
	"res://tests/test_island_progress.gd",
	"res://tests/test_startup_splash.gd",
]

func _initialize() -> void:
	# Autoload singletons (GameData, Economy, Boosters, ...) run their
	# _ready() on the first processed frame, not synchronously here — wait
	# for it so economy/booster tests see fully-loaded config.
	await process_frame
	await process_frame

	var total_pass := 0
	var total_fail := 0
	var failures: Array[String] = []

	for path in TEST_SCRIPTS:
		if not ResourceLoader.exists(path):
			continue
		var script: GDScript = load(path)
		var instance: TestCase = script.new()
		var test_results: Array[Dictionary] = instance.run()
		for r in test_results:
			if r["pass"]:
				total_pass += 1
			else:
				total_fail += 1
				failures.append("%s :: %s -- %s" % [path, r["name"], r.get("message", "")])

	print("---- Color Clash Test Results ----")
	print("PASS: %d  FAIL: %d" % [total_pass, total_fail])
	for f in failures:
		print("FAIL: " + f)
	quit(1 if total_fail > 0 else 0)
