extends SceneTree
## DEBUG gameplay diagnostic runner (manual dev tool — NOT registered in
## tests/test_runner.gd, so the CI suite and its count are untouched).
##
## Drives BoardDiagnosticBot, which drives the REAL board / match-resolution
## systems. Three modes:
##
##   stress   (default) — many legal moves across every authored level, N
##                        seeds each, extra passes on levels 20..50. Reports
##                        moves, boards, stalls, deadlocks, failed
##                        resolutions, worst resolution time, and the exact
##                        level+seed pairs that reproduce a stall.
##
##   repro    --repro-level=<id> --repro-seed=<seed> [--repro-move=<n>]
##            — re-runs ONE level with ONE seed deterministically and dumps
##              the full stall report (same board sequence every run).
##
##   range    --from=<id> --to=<id> [--seeds=<k>] [--moves=<m>]
##            — stress a contiguous authored-level range.
##
## Common flags:  --moves=<per-level>  --seeds=<per-level>  --verbose
##
## Examples:
##   godot4 --headless --path game --script res://tests/diag_board_bot.gd
##   godot4 --headless --path game --script res://tests/diag_board_bot.gd -- --repro-level=48 --repro-seed=12345 --verbose
##   godot4 --headless --path game --script res://tests/diag_board_bot.gd -- --from=20 --to=50 --seeds=8 --moves=120

const DEFAULT_MOVES := 80
const DEFAULT_SEEDS := 4
const FOCUS_LO := 20
const FOCUS_HI := 50
const FOCUS_EXTRA_SEEDS := 6

## Loaded dynamically (not as a bare class_name) so this --script entry
## point compiles before autoloads/class cache are guaranteed ready.
const _BOT := preload("res://scripts/debug/board_diagnostic_bot.gd")

var _args := {}

func _initialize() -> void:
	await process_frame
	await process_frame

	if not OS.is_debug_build():
		push_warning("diag_board_bot: not a debug build — diagnostic runner is a no-op.")
		quit(0)
		return

	_args = _parse_args()
	var gd := get_root().get_node("GameData")

	if _args.has("repro-level"):
		_run_repro(gd, int(_args["repro-level"]), int(_args.get("repro-seed", 1)),
			int(_args.get("repro-move", 0)))
		return

	var lo := int(_args.get("from", 1))
	var hi := int(_args.get("to", 50))
	var moves := int(_args.get("moves", DEFAULT_MOVES))
	var seeds := int(_args.get("seeds", DEFAULT_SEEDS))
	var verbose := _args.has("verbose")
	_run_stress(gd, lo, hi, moves, seeds, verbose)

# ---------------------------------------------------------------- repro --

func _run_repro(gd, level_id: int, seed: int, _fail_move: int) -> void:
	var level = gd.levels.get_level(level_id)
	if level == null:
		push_error("no authored level %d" % level_id); quit(1); return
	print("==== DETERMINISTIC REPRO — authored level %d, seed %d ====" % [level_id, seed])

	var runs := []
	for pass_i in 2:  # run twice, prove the board sequence is identical
		var bot := _BOT.new()
		bot.configure(level, seed, {"power_config": gd.power_config, "verbose": true,
			"logical_level_id": level_id})
		var first_board: String = bot.serialize_board()
		bot.run_level(int(_args.get("moves", 200)))
		runs.append({"first_board": first_board, "moves": bot.moves_simulated,
			"stalls": bot.stalls, "solved": bot.level_solved})

	var same: bool = String(runs[0]["first_board"]) == String(runs[1]["first_board"])
	print("determinism: identical starting board across 2 runs = %s" % ("YES" if same else "NO"))
	print("moves simulated: %d   solved: %s   stalls: %d" % [
		runs[0]["moves"], runs[0]["solved"], runs[0]["stalls"].size()])
	var bot2 := _BOT.new()
	bot2.configure(level, seed, {"power_config": gd.power_config, "verbose": true, "logical_level_id": level_id})
	for s in runs[0]["stalls"]:
		print(bot2.format_stall(s))
	_save_repro(runs[0]["stalls"])
	quit(1 if runs[0]["stalls"].size() > 0 or not same else 0)

# --------------------------------------------------------------- stress --

func _run_stress(gd, lo: int, hi: int, moves: int, seeds: int, verbose: bool) -> void:
	print("==== STRESS — authored levels %d..%d  |  %d moves/run  |  %d base seeds/level  |  focus %d..%d (+%d seeds) ====" % [
		lo, hi, moves, seeds, FOCUS_LO, FOCUS_HI, FOCUS_EXTRA_SEEDS])

	var total_moves := 0
	var total_boards := 0
	var total_stalls := 0
	var total_deadlocks := 0
	var total_failed_resolutions := 0
	var worst_ms := 0.0
	var worst_where := ""
	var repro_pairs := []          # [{level, seed, code, move}]
	var by_code := {}
	var solved := 0
	var unsolved := 0

	for level_id in range(lo, hi + 1):
		var level = gd.levels.get_level(level_id)
		if level == null:
			continue
		var n_seeds := seeds
		if level_id >= FOCUS_LO and level_id <= FOCUS_HI:
			n_seeds += FOCUS_EXTRA_SEEDS
		for si in n_seeds:
			var seed := _seed_for(level_id, si)
			var bot := _BOT.new()
			bot.configure(level, seed, {"power_config": gd.power_config,
				"verbose": verbose, "logical_level_id": level_id})
			# deliver-stage pre-flight: unreachable relics = soft stall
			if bot.deliver_target_total() > 0 and not bot.any_relic_can_be_delivered():
				var rep := {
					"code": "DELIVER_UNREACHABLE", "detail": "no relic on the start board has a clear fall path to the bottom row",
					"world_id": "", "logical_level_id": level_id, "authored_level_id": level_id,
					"level_name": level.level_name, "seed": seed, "move_number": 0, "moves_left": level.move_limit,
					"board_w": level.width, "board_h": level.height, "min_group_size": bot.board.min_group_size,
					"available_colors": [], "rainbow_chance": bot.rainbow_chance,
					"phase_stopped": "objective_progression", "selected_move": [], "move_kind": "",
					"detected_matches": [], "board_before": bot.serialize_board(), "board_after": "",
					"stuck_cell": [], "obj_before": [], "obj_after": [], "chain_depth": 0,
					"secondary_triggers": 0, "waves": 0, "gravity_moves": 0, "refilled": 0,
					"phase_timings_ms": {}, "objectives": level.objectives.duplicate(true),
				}
				bot.stalls.append(rep)

			bot.run_level(moves)

			total_boards += 1 + bot.reshuffles
			total_moves += bot.moves_simulated
			if bot.level_solved:
				solved += 1
			else:
				unsolved += 1
			if bot.worst_move_ms > worst_ms:
				worst_ms = bot.worst_move_ms
				worst_where = "L%d seed=%d" % [level_id, seed]

			for st in bot.stalls:
				total_stalls += 1
				var code: String = st["code"]
				by_code[code] = int(by_code.get(code, 0)) + 1
				if code in ["RESHUFFLE_EXHAUSTED_DEADLOCK", "CASCADE_RUNAWAY", "LEVEL_WALL_TIMEOUT", "RESOLUTION_TIMEOUT"]:
					total_deadlocks += 1
				if code in ["NO_RESOLUTION_INVALID", "INPUT_ACCEPTED_NO_RESOLUTION", "INPUT_REJECTED", "MATCH_DETECTED_PIECE_NOT_REMOVED"]:
					total_failed_resolutions += 1
				repro_pairs.append({"level": level_id, "seed": seed, "code": code, "move": st["move_number"]})
				if OS.is_debug_build():
					print(bot.format_stall(st))

	print("\n================ STRESS SUMMARY (levels %d..%d) ================" % [lo, hi])
	print("simulated moves         : %d" % total_moves)
	print("boards tested           : %d  (initial boards + reshuffles)" % total_boards)
	print("levels solved by bot    : %d" % solved)
	print("levels not solved       : %d" % unsolved)
	print("stalls detected         : %d" % total_stalls)
	print("  deadlocks / timeouts  : %d" % total_deadlocks)
	print("  failed resolutions    : %d" % total_failed_resolutions)
	print("worst resolution time   : %.2f ms   (%s)" % [worst_ms, worst_where if worst_where != "" else "n/a"])
	print("stalls by code          : %s" % str(by_code))
	if repro_pairs.is_empty():
		print("reproducing level/seed  : NONE — no stall reproduced")
	else:
		print("reproducing level/seed pairs:")
		for rp in repro_pairs:
			print("  level %d  seed %d  ->  %s  (fails on move %d)" % [rp["level"], rp["seed"], rp["code"], rp["move"]])
	print("==============================================================")
	_save_repro_pairs(repro_pairs)
	quit(1 if total_stalls > 0 else 0)

# ------------------------------------------------------------- helpers --

## Stable, documented seed derivation so a summary line's "seed N" can be
## fed straight back into repro mode.
static func _seed_for(level_id: int, seed_index: int) -> int:
	return level_id * 100000 + seed_index * 7919 + 1

func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		var s := a.lstrip("-")
		if s.contains("="):
			var kv := s.split("=", true, 1)
			out[kv[0]] = kv[1]
		else:
			out[s] = true
	return out

func _save_repro(stalls: Array) -> void:
	if stalls.is_empty():
		return
	var dir := "user://diag"
	DirAccess.make_dir_recursive_absolute(dir)
	var path := "%s/repro_%d.json" % [dir, Time.get_unix_time_from_system()]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		var bot := _BOT.new()
		var minimal := []
		for s in stalls:
			minimal.append(bot.minimal_repro(s))
		f.store_string(JSON.stringify({"stalls": stalls, "minimal": minimal}, "  "))
		f.close()
		print("saved full repro -> %s" % ProjectSettings.globalize_path(path))

func _save_repro_pairs(pairs: Array) -> void:
	if pairs.is_empty():
		return
	var dir := "user://diag"
	DirAccess.make_dir_recursive_absolute(dir)
	var path := "%s/stress_pairs_%d.json" % [dir, Time.get_unix_time_from_system()]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(pairs, "  "))
		f.close()
		print("saved stress repro pairs -> %s" % ProjectSettings.globalize_path(path))
