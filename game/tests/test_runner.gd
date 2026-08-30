extends SceneTree
## Headless test entry point:
## godot --headless --path game --script res://tests/test_runner.gd
## Exits with code 1 if any test fails (CI-friendly).

const TEST_SCRIPTS := [
	"res://tests/test_board_model.gd",
	"res://tests/test_power_resolver.gd",
	"res://tests/test_chain_resolver.gd",
	"res://tests/test_score_calculator.gd",
	"res://tests/test_objective.gd",
	"res://tests/test_fever_system.gd",
	"res://tests/test_economy.gd",
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
