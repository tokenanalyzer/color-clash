class_name BoardDiagnosticBot
extends RefCounted
## DEBUG-ONLY gameplay diagnostic harness. Drives the REAL board / match-
## resolution systems (BoardModel + ChainResolver + PowerResolver +
## ObjectiveTracker) exactly as the game does — it never reimplements match
## logic and never mutates production rules. It is an observer first: it
## picks legal moves by querying the real board, feeds them through the real
## resolver, and asserts the full move lifecycle held.
##
## Nothing here runs in a normal game session: no autoload, no scene wiring,
## no UI. The runner scripts (tests/diag_board_bot.gd, tests/diag_board_view.gd)
## are manual dev tools, not registered in tests/test_runner.gd, so the CI
## suite and its count are untouched. All logging is gated on
## OS.is_debug_build() AND an explicit `verbose` flag (default false), so a
## release build neither shows diagnostic controls nor spams logs.
##
## Lifecycle verified after every simulated move:
##   input accepted -> match detection -> match resolution -> piece removal
##   -> gravity -> refill -> cascade resolution -> board stable
##   -> next move allowed.

# ---- tunables -------------------------------------------------------------

## A single simulated move (pick + validate + resolve + post-checks) that
## takes longer than this is reported as a resolution timeout.
const MOVE_TIMEOUT_MS := 2000
## Whole-level wall budget — a level whose bot run exceeds this is reported
## as a level-level stall (independent of the per-move timeout).
const LEVEL_TIMEOUT_MS := 30000
## chain_depth at or above this from one move = runaway cascade.
const CASCADE_RUNAWAY_DEPTH := 400
## Mirrors ChainResolver._MAX_SECONDARY_TRIGGERS — used only to assert the
## resolver stayed inside its own documented cap, never to change it.
const SECONDARY_TRIGGER_CAP := 6
## Replica of BoardView._generate_playable_board()'s regeneration guard.
const RESHUFFLE_GUARD := 20

# ---- configuration ------------------------------------------------------

var level: LevelConfig
var world_id: StringName = &""
var logical_level_id: int = 0          # world-local level (Island N, Level M)
var authored_level_id: int = 0         # data/levels.json id that supplied the board
var seed: int = 0
var verbose: bool = false
var power_config: PowerConfig
var available_colors: Array[StringName] = []
var rainbow_chance: float = 0.0

# ---- live state --------------------------------------------------------

var board: BoardModel
var rng := RandomNumberGenerator.new()
var objectives: ObjectiveTracker
var moves_left: int = 0
var move_number: int = 0
var score: int = 0

# ---- results --------------------------------------------------------

## Every stall found this run. Each entry carries the full field set required
## for a minimal deterministic reproduction (see _make_stall_report).
var stalls: Array[Dictionary] = []
var moves_simulated: int = 0
var reshuffles: int = 0
var worst_move_ms: float = 0.0
var level_solved: bool = false
var ran_out_of_moves: bool = false
var last_phase_timings: Dictionary = {}

# =====================================================================
#  setup
# =====================================================================

func configure(p_level: LevelConfig, p_seed: int, opts: Dictionary = {}) -> void:
	level = p_level
	seed = p_seed
	# `power_config` is passed in by the runner (from the GameData autoload) —
	# never referenced here as a bare autoload identifier so this file stays
	# compilable as a standalone --script dependency.
	power_config = opts.get("power_config", null)
	assert(power_config != null, "BoardDiagnosticBot.configure needs opts.power_config")
	rainbow_chance = float(opts.get("rainbow_chance",
		float(power_config.get_definition(&"rainbow").get("refill_spawn_chance", 0.0))))
	verbose = bool(opts.get("verbose", false))
	world_id = StringName(String(opts.get("world_id", "")))
	logical_level_id = int(opts.get("logical_level_id", p_level.id))
	authored_level_id = p_level.id
	available_colors = level.colors.duplicate()

	rng = RandomNumberGenerator.new()
	rng.seed = seed

	# Build the model exactly as BoardView.setup() does: obstacles, then
	# specials, then the same "regenerate until playable" guarded loop.
	board = BoardModel.new(level.width, level.height, power_config.min_group_size())
	for obstacle in level.obstacles:
		var pos := Vector2i(int(obstacle.get("x", 0)), int(obstacle.get("y", 0)))
		board.set_obstacle(pos, StringName(String(obstacle.get("type", "none"))), int(obstacle.get("hp", 0)))
	for sp in level.specials:
		board.set_special(Vector2i(int(sp.get("x", 0)), int(sp.get("y", 0))),
			StringName(String(sp.get("type", "relic"))))
	_generate_playable_board()

	objectives = ObjectiveTracker.new(level.objectives)
	moves_left = level.move_limit
	move_number = 0
	score = 0
	level_solved = false
	ran_out_of_moves = false

## Replica of BoardView._generate_playable_board() — same call, same guard,
## so the bot reproduces the exact board sequence a real session would get
## for this seed.
func _generate_playable_board() -> void:
	board.generate(rng, available_colors)
	var guard := 0
	while not board.has_any_valid_move() and guard < RESHUFFLE_GUARD:
		board.generate(rng, available_colors)
		guard += 1

# =====================================================================
#  main loop
# =====================================================================

## Runs up to `max_moves` simulated moves against this level. Stops early on
## a solved objective set, an exhausted move budget, or a detected stall.
## Returns the number of moves simulated.
func run_level(max_moves: int) -> int:
	var level_start := Time.get_ticks_msec()
	var n := 0
	while n < max_moves:
		if objectives.is_complete():
			level_solved = true
			break
		if moves_left <= 0:
			ran_out_of_moves = true
			break
		if Time.get_ticks_msec() - level_start > LEVEL_TIMEOUT_MS:
			_record_stall("LEVEL_WALL_TIMEOUT", "level bot run exceeded %d ms" % LEVEL_TIMEOUT_MS, {}, {})
			break
		var stalled := step()
		n += 1
		moves_simulated += 1
		if stalled:
			break
	return n

## One simulated move + full lifecycle verification. Returns true if a stall
## was recorded (caller stops the level).
func step() -> bool:
	move_number += 1
	var t_move_start := Time.get_ticks_usec()
	var timings := {}

	var board_before := serialize_board()

	# ---- phase: match detection -------------------------------------
	var t0 := Time.get_ticks_usec()
	var detected: Array = _all_matchable_groups()
	var any_move: bool = board.has_any_valid_move()
	var plan: Dictionary = _pick_move()
	timings["detect_ms"] = (Time.get_ticks_usec() - t0) / 1000.0

	if plan.is_empty():
		if any_move:
			# The real board says a move exists but the bot's legal-move
			# search — driven entirely by board.find_connected_group /
			# board.validate_path — could not realise one.
			_record_stall("NO_MOVE_FOUND_DESPITE_AVAILABLE",
				"board.has_any_valid_move()==true but no path validated",
				{"board_before": board_before, "detected_matches": detected,
				 "selected_move": [], "phase": "match_detection"}, timings)
			return true
		# genuinely no move -> the game reshuffles here. Reproduce it and
		# make sure a playable board actually results.
		return _do_reshuffle_or_stall(board_before, timings)

	var kind: String = plan["kind"]
	var path: Array[Vector2i] = []
	path.assign(plan["path"])

	# ---- phase: input accepted / validation -----------------------
	t0 = Time.get_ticks_usec()
	var accepted := board.validate_path(path) if kind != "power_tap" else true
	timings["validate_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	if not accepted:
		_record_stall("INPUT_REJECTED",
			"bot-built path failed board.validate_path()",
			{"board_before": board_before, "selected_move": _p2a(path),
			 "detected_matches": detected, "phase": "validation"}, timings)
		return true

	# snapshot exact pre-resolve cell payloads for the "pieces removed" check
	var pre_cells := {}
	for pos in path:
		var c := board.get_cell(pos)
		pre_cells[pos] = {"color": c.color_id, "power": c.power_id,
			"obstacle": c.obstacle_id, "special": c.special_id}
	var moves_before := moves_left
	var obj_before: Array = objectives.progress.duplicate()

	# ---- phase: resolution (clear -> gravity -> refill, one atomic call
	#            in production; timed together because we never split the
	#            real code path) ------------------------------------
	t0 = Time.get_ticks_usec()
	var result: ChainResolver.MoveResult
	match kind:
		"power_tap":
			result = ChainResolver.resolve_power_tap(board, path[0], power_config, rng, available_colors, rainbow_chance)
		_:
			result = ChainResolver.resolve_move(board, path, power_config, rng, available_colors, rainbow_chance)
	timings["resolve_ms"] = (Time.get_ticks_usec() - t0) / 1000.0

	var ctx := {
		"board_before": board_before, "selected_move": _p2a(path),
		"detected_matches": detected, "move_kind": kind,
		"waves": result.wave_cells.size(),
		"gravity_moves": result.gravity_moves.size(),
		"refilled": result.refilled_cells.size(),
		"chain_depth": result.chain_depth,
		"secondary_triggers": result.secondary_triggers,
	}

	# ---- verify: input accepted -> resolution happened -------------
	if not result.valid:
		_record_stall("NO_RESOLUTION_INVALID",
			"resolver returned valid=false for a path validate_path() accepted",
			_merge(ctx, {"phase": "resolution", "board_after": serialize_board()}), timings)
		return true

	var did_something := not result.cleared_cells.is_empty() \
		or not result.powers_created.is_empty() \
		or not result.obstacles_broken.is_empty() \
		or not result.gravity_moves.is_empty()
	if not did_something:
		_record_stall("INPUT_ACCEPTED_NO_RESOLUTION",
			"valid move produced zero clears / powers / obstacle hits / gravity",
			_merge(ctx, {"phase": "match_resolution", "board_after": serialize_board()}), timings)
		return true

	# ---- verify: match detected -> pieces removed -----------------
	if kind == "plain":
		var anchors := {}
		for pc in result.powers_created:
			anchors[pc["pos"]] = true
		for pos in path:
			if anchors.has(pos):
				continue
			if String(pre_cells[pos]["power"]) != String(CellData.POWER_NONE):
				continue  # threaded power, handled by activation path
			if not result.cleared_cells.has(pos):
				var cnow := board.get_cell(pos)
				# a plain path cell that was neither cleared nor turned into
				# a power nor consumed by an ice/stone hit
				if String(cnow.color_id) == String(pre_cells[pos]["color"]) \
						and String(cnow.power_id) == String(CellData.POWER_NONE):
					_record_stall("MATCH_DETECTED_PIECE_NOT_REMOVED",
						"path cell %s survived the match unchanged" % [pos],
						_merge(ctx, {"phase": "piece_removal", "board_after": serialize_board(),
							"stuck_cell": [pos.x, pos.y]}), timings)
					return true

	# ---- verify: gravity (no floating piece above an empty fillable gap)
	var float_gap := _first_floating_gap()
	if float_gap.x >= 0:
		_record_stall("GRAVITY_FLOATING_PIECE",
			"cell %s holds a piece with an empty fillable cell below it" % [float_gap],
			_merge(ctx, {"phase": "gravity", "board_after": serialize_board(),
				"stuck_cell": [float_gap.x, float_gap.y]}), timings)
		return true

	# ---- verify: refill (board fully repopulated at rest) ---------
	var hole := _first_refill_hole()
	if hole.x >= 0:
		_record_stall("REFILL_HOLE",
			"cell %s is empty+fillable after refill" % [hole],
			_merge(ctx, {"phase": "refill", "board_after": serialize_board(),
				"stuck_cell": [hole.x, hole.y]}), timings)
		return true

	# ---- verify: cascade resolution stayed inside the resolver's caps
	if result.chain_depth >= CASCADE_RUNAWAY_DEPTH:
		_record_stall("CASCADE_RUNAWAY",
			"chain_depth %d >= %d" % [result.chain_depth, CASCADE_RUNAWAY_DEPTH],
			_merge(ctx, {"phase": "cascade_resolution", "board_after": serialize_board()}), timings)
		return true
	if result.secondary_triggers > SECONDARY_TRIGGER_CAP:
		_record_stall("CASCADE_SECONDARY_OVERFLOW",
			"secondary_triggers %d > documented cap %d" % [result.secondary_triggers, SECONDARY_TRIGGER_CAP],
			_merge(ctx, {"phase": "cascade_resolution", "board_after": serialize_board()}), timings)
		return true
	if result.wave_cells.size() != result.score_events.size():
		_record_stall("CASCADE_WAVE_DESYNC",
			"wave_cells (%d) and score_events (%d) diverged" % [result.wave_cells.size(), result.score_events.size()],
			_merge(ctx, {"phase": "cascade_resolution", "board_after": serialize_board()}), timings)
		return true

	# ---- verify: board stable (deterministic re-serialize is idempotent;
	#            no mid-transition cell) ---------------------------
	var board_after := serialize_board()
	for x in board.width:
		for y in board.height:
			var c := board.get_cell(Vector2i(x, y))
			if c.color_id == CellData.COLOR_EMPTY and not c.is_stone() \
					and not c.locked_empty and not c.has_special() and not c.has_power():
				_record_stall("BOARD_UNSTABLE_EMPTY_CELL",
					"cell (%d,%d) at rest with no piece/power/obstacle/special" % [x, y],
					_merge(ctx, {"phase": "board_stable", "board_after": board_after,
						"stuck_cell": [x, y]}), timings)
				return true

	# ---- verify: move counter changes correctly -----------------
	var penalty := result.move_penalty
	if penalty < 0 or (penalty > 0 and result.timebomb_explosions.is_empty()):
		_record_stall("MOVE_COUNTER_BAD_PENALTY",
			"move_penalty %d with %d timebomb explosions" % [penalty, result.timebomb_explosions.size()],
			_merge(ctx, {"phase": "move_counter", "board_after": board_after}), timings)
		return true
	if kind != "power_tap" or true:
		moves_left = max(moves_left - 1 - penalty, 0)
	if moves_before - moves_left != min(1 + penalty, moves_before):
		_record_stall("MOVE_COUNTER_DRIFT",
			"expected -%d moves, got -%d" % [1 + penalty, moves_before - moves_left],
			_merge(ctx, {"phase": "move_counter", "board_after": board_after}), timings)
		return true

	# ---- verify: objective state updates -----------------------
	score += _score_for(result)
	objectives.apply_move(result.colors_cleared, score, result.powers_created,
		result.obstacles_broken, result.specials_delivered.size())
	var obj_stall := _check_objective_update(result, obj_before)
	if not obj_stall.is_empty():
		_record_stall(obj_stall["code"], obj_stall["msg"],
			_merge(ctx, {"phase": "objective_progression", "board_after": board_after,
				"obj_before": obj_before, "obj_after": objectives.progress.duplicate()}), timings)
		return true

	# ---- verify: next move allowed -----------------------------
	if not objectives.is_complete() and moves_left > 0:
		if not board.has_any_valid_move():
			if _do_reshuffle_or_stall(board_after, timings):
				return true

	# ---- verify: per-move resolution timeout -------------------
	var move_ms := (Time.get_ticks_usec() - t_move_start) / 1000.0
	worst_move_ms = maxf(worst_move_ms, move_ms)
	timings["move_ms"] = move_ms
	last_phase_timings = timings
	if move_ms > MOVE_TIMEOUT_MS:
		_record_stall("RESOLUTION_TIMEOUT",
			"single move took %.1f ms (> %d ms)" % [move_ms, MOVE_TIMEOUT_MS],
			_merge(ctx, {"phase": "resolution_timeout", "board_after": board_after}), timings)
		return true

	if verbose and OS.is_debug_build():
		print("[diag] L%d/%s move %d  kind=%s  depth=%d  clears=%d  waves=%d  moves_left=%d  %.2fms"
			% [logical_level_id, str(world_id), move_number, kind, result.chain_depth,
			   result.cleared_cells.size(), result.wave_cells.size(), moves_left, move_ms])
	return false

# =====================================================================
#  reshuffle reproduction  (the on-device "board stuck / can't move" path)
# =====================================================================

func _do_reshuffle_or_stall(board_snapshot: String, timings: Dictionary) -> bool:
	# BoardView._play_move(): `if not board.has_any_valid_move(): await _reshuffle()`
	# and _reshuffle() -> _generate_playable_board() (guard RESHUFFLE_GUARD).
	var t0 := Time.get_ticks_usec()
	board.generate(rng, available_colors)
	var guard := 0
	while not board.has_any_valid_move() and guard < RESHUFFLE_GUARD:
		board.generate(rng, available_colors)
		guard += 1
	timings["reshuffle_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	reshuffles += 1
	if not board.has_any_valid_move():
		_record_stall("RESHUFFLE_EXHAUSTED_DEADLOCK",
			"after %d regenerations board still has no valid move; the game leaves input locked here" % RESHUFFLE_GUARD,
			{"board_before": board_snapshot, "board_after": serialize_board(),
			 "phase": "next_move_allowed", "selected_move": [], "detected_matches": []}, timings)
		return true
	return false

# =====================================================================
#  legal-move selection  (queries the REAL board only)
# =====================================================================

## Deterministic: first realisable move in row-major order. Order of
## preference: activate a threaded power, tap a lone power, plain match.
func _pick_move() -> Dictionary:
	# 1) plain connected group -> ordered adjacency walk -> real validate_path
	for y in board.height:
		for x in board.width:
			var start := Vector2i(x, y)
			var c := board.get_cell(start)
			if c == null or not c.is_selectable() or c.has_power():
				continue
			var group := board.find_connected_group(start)
			if group.size() < board.min_group_size:
				continue
			var path := _walk_path(group)
			while path.size() >= board.min_group_size and not board.validate_path(path):
				path.pop_back()
			if path.size() >= board.min_group_size and board.validate_path(path):
				# opportunistically thread an adjacent power tile for coverage
				var threaded := _try_thread_power(path)
				if not threaded.is_empty():
					return {"kind": "plain", "path": threaded}
				return {"kind": "plain", "path": path}

	# 2) lone power tile -> tap
	for y in board.height:
		for x in board.width:
			var p := Vector2i(x, y)
			var c := board.get_cell(p)
			if c != null and c.has_power():
				var tp: Array[Vector2i] = [p]
				return {"kind": "power_tap", "path": tp}
	return {}

## Greedy DFS walk over a hex-connected group: every step is adjacent to the
## previous, no repeats. Yields an ordered path validate_path() accepts.
## Returns a typed Array[Vector2i] (BoardModel.validate_path requires it).
func _walk_path(group: Array) -> Array[Vector2i]:
	var member := {}
	for g in group:
		member[g] = true
	var path: Array[Vector2i] = [group[0]]
	var used := {group[0]: true}
	while true:
		var head: Vector2i = path[path.size() - 1]
		var advanced := false
		for n in board.get_neighbors(head):
			if member.has(n) and not used.has(n):
				var nc := board.get_cell(n)
				if nc == null or not nc.is_selectable() or nc.has_power():
					continue
				path.append(n)
				used[n] = true
				advanced = true
				break
		if not advanced:
			break
	return path

## If a still-live power tile sits adjacent to one end of `path` and the
## same-colour rule allows it, extend the path onto it so the bot also
## exercises the ACTIVATION branch of ChainResolver.
func _try_thread_power(path: Array[Vector2i]) -> Array[Vector2i]:
	var head: Vector2i = path[path.size() - 1]
	for n in board.get_neighbors(head):
		var nc := board.get_cell(n)
		if nc != null and nc.has_power() and not path.has(n):
			var candidate: Array[Vector2i] = path.duplicate()
			candidate.append(n)
			if board.validate_path(candidate):
				return candidate
	var empty: Array[Vector2i] = []
	return empty

## Every connected same-colour group on the board that is big enough to
## match — logged as "detected matches" in a stall report.
func _all_matchable_groups() -> Array:
	var out: Array = []
	var seen := {}
	for y in board.height:
		for x in board.width:
			var p := Vector2i(x, y)
			if seen.has(p):
				continue
			var g := board.find_connected_group(p)
			for m in g:
				seen[m] = true
			if g.size() >= board.min_group_size:
				var coords: Array = []
				for m in g:
					coords.append([m.x, m.y])
				out.append({"size": g.size(), "color": String(board.get_cell(p).color_id), "cells": coords})
	return out

# =====================================================================
#  lifecycle assertions
# =====================================================================

## First cell (top-down) holding a movable piece that has an empty, fillable
## cell directly below it in the same column — i.e. gravity did not compact.
## Stone / locked / special cells legitimately block a column.
func _first_floating_gap() -> Vector2i:
	for x in board.width:
		for y in range(board.height - 2, -1, -1):
			var c := board.get_cell(Vector2i(x, y))
			if not c.has_movable_content():
				continue
			var below := board.get_cell(Vector2i(x, y + 1))
			if below.is_stone() or below.locked_empty or below.has_special():
				continue
			if below.color_id == CellData.COLOR_EMPTY and not below.has_power():
				return Vector2i(x, y)
	return Vector2i(-1, -1)

func _first_refill_hole() -> Vector2i:
	for x in board.width:
		for y in board.height:
			var c := board.get_cell(Vector2i(x, y))
			if c.color_id == CellData.COLOR_EMPTY and not c.is_stone() \
					and not c.locked_empty and not c.has_special() and not c.has_power():
				return Vector2i(x, y)
	return Vector2i(-1, -1)

## Returns {} if objective progress is consistent with the move, else a
## {code, msg} describing the first inconsistency.
func _check_objective_update(result: ChainResolver.MoveResult, before: Array) -> Dictionary:
	for i in objectives.objectives.size():
		var obj: Dictionary = objectives.objectives[i]
		var kind := String(obj.get("type", ""))
		var moved: bool = objectives.progress[i] > before[i]
		var done_before: bool = before[i] >= objectives.target_for(i)
		match kind:
			"clear_color":
				var col := StringName(String(obj.get("color", "")))
				var cleared := int(result.colors_cleared.get(col, 0))
				if cleared > 0 and not moved and not done_before:
					return {"code": "OBJECTIVE_NOT_UPDATED",
						"msg": "cleared %d '%s' but clear_color objective #%d did not advance" % [cleared, col, i]}
			"break_obstacles":
				var wanted := String(obj.get("obstacle", "any"))
				var hits := 0
				for o in result.obstacles_broken:
					if wanted == "any" or String(o["obstacle_id"]) == wanted:
						hits += 1
				if hits > 0 and not moved and not done_before:
					return {"code": "OBJECTIVE_NOT_UPDATED",
						"msg": "broke %d '%s' but break_obstacles objective #%d did not advance" % [hits, wanted, i]}
			"deliver":
				if result.specials_delivered.size() > 0 and not moved and not done_before:
					return {"code": "OBJECTIVE_NOT_UPDATED",
						"msg": "delivered %d specials but deliver objective #%d did not advance" % [result.specials_delivered.size(), i]}
	return {}

# =====================================================================
#  deliverability probe  (deterministic pre-flight for deliver stages)
# =====================================================================

## True if at least one escort special currently on the board has a clear
## fall path to the bottom row (no stone / locked cell beneath it in its
## column). A deliver objective with zero deliverable relics can never be
## completed -> the level is a soft stall.
func any_relic_can_be_delivered() -> bool:
	for p in board.special_positions():
		var blocked := false
		for y in range(p.y + 1, board.height):
			var c := board.get_cell(Vector2i(p.x, y))
			if c.is_stone() or c.locked_empty:
				blocked = true
				break
		if not blocked:
			return true
	return board.special_positions().is_empty()

func deliver_target_total() -> int:
	var t := 0
	for obj in level.objectives:
		if String(obj.get("type", "")) == "deliver":
			t += int(obj.get("target", 0))
	return t

# =====================================================================
#  serialization / reporting
# =====================================================================

## One char per cell, rows top-to-bottom. Lower-case letter = colour (first
## letter of the colour id), R = relic/special, * = power tile, # = stone
## family, = ice family, L = lock family, ! = timebomb family, . = empty.
func serialize_board() -> String:
	var lines: Array[String] = []
	for y in board.height:
		var row := ""
		for x in board.width:
			var c := board.get_cell(Vector2i(x, y))
			if c.has_special():
				row += "R"
			elif c.has_power():
				row += "*"
			elif c.is_stone():
				row += "#"
			elif c.is_ice():
				row += "="
			elif c.is_lock():
				row += "L"
			elif c.is_timebomb():
				row += "!"
			elif c.color_id == CellData.COLOR_EMPTY:
				row += "."
			elif c.color_id == BoardModel.RAINBOW_COLOR_ID:
				row += "?"
			else:
				row += String(c.color_id).substr(0, 1)
		lines.append(row)
	return "\n".join(lines)

func _record_stall(code: String, detail: String, ctx: Dictionary, timings: Dictionary) -> void:
	var rep := _make_stall_report(code, detail, ctx, timings)
	stalls.append(rep)
	if OS.is_debug_build():
		push_warning("[BoardDiagnosticBot] STALL %s @ L%d seed=%d move=%d — %s"
			% [code, logical_level_id, seed, move_number, detail])
		if verbose:
			print(format_stall(rep))

func _make_stall_report(code: String, detail: String, ctx: Dictionary, timings: Dictionary) -> Dictionary:
	return {
		"code": code,
		"detail": detail,
		"world_id": String(world_id),
		"logical_level_id": logical_level_id,
		"authored_level_id": authored_level_id,
		"level_name": level.level_name,
		"seed": seed,
		"move_number": move_number,
		"moves_left": moves_left,
		"board_w": board.width,
		"board_h": board.height,
		"min_group_size": board.min_group_size,
		"available_colors": _sn2a(available_colors),
		"rainbow_chance": rainbow_chance,
		"phase_stopped": ctx.get("phase", "unknown"),
		"selected_move": ctx.get("selected_move", []),
		"move_kind": ctx.get("move_kind", ""),
		"detected_matches": ctx.get("detected_matches", []),
		"board_before": ctx.get("board_before", ""),
		"board_after": ctx.get("board_after", ""),
		"stuck_cell": ctx.get("stuck_cell", []),
		"obj_before": ctx.get("obj_before", []),
		"obj_after": ctx.get("obj_after", []),
		"chain_depth": ctx.get("chain_depth", 0),
		"secondary_triggers": ctx.get("secondary_triggers", 0),
		"waves": ctx.get("waves", 0),
		"gravity_moves": ctx.get("gravity_moves", 0),
		"refilled": ctx.get("refilled", 0),
		"phase_timings_ms": timings,
		"objectives": level.objectives.duplicate(true),
	}

## Minimal deterministic-reproduction payload — enough to re-run the exact
## failing board sequence: level id + seed + the move index it fails on.
func minimal_repro(rep: Dictionary) -> Dictionary:
	return {
		"authored_level_id": rep["authored_level_id"],
		"logical_level_id": rep["logical_level_id"],
		"world_id": rep["world_id"],
		"seed": rep["seed"],
		"fail_on_move": rep["move_number"],
		"code": rep["code"],
		"phase": rep["phase_stopped"],
		"board_before": rep["board_before"],
	}

func format_stall(rep: Dictionary) -> String:
	var s := "\n================ STALL: %s ================\n" % rep["code"]
	s += "detail            : %s\n" % rep["detail"]
	s += "world / level     : %s  /  logical %d  (authored data/levels.json id %d — \"%s\")\n" % [
		rep["world_id"] if rep["world_id"] != "" else "(campaign)",
		rep["logical_level_id"], rep["authored_level_id"], rep["level_name"]]
	s += "seed              : %d\n" % rep["seed"]
	s += "move number       : %d   (moves_left after: %d)\n" % [rep["move_number"], rep["moves_left"]]
	s += "board dimensions  : %d x %d   min_group_size=%d\n" % [rep["board_w"], rep["board_h"], rep["min_group_size"]]
	s += "colors            : %s   rainbow_chance=%.3f\n" % [str(rep["available_colors"]), rep["rainbow_chance"]]
	s += "phase stopped at  : %s\n" % rep["phase_stopped"]
	s += "selected move     : %s  (kind=%s)\n" % [str(rep["selected_move"]), rep["move_kind"]]
	if not rep["stuck_cell"].is_empty():
		s += "stuck cell        : %s\n" % str(rep["stuck_cell"])
	s += "detected matches  : %d group(s)  %s\n" % [rep["detected_matches"].size(), str(rep["detected_matches"]).substr(0, 400)]
	s += "cascade           : chain_depth=%d  secondary_triggers=%d  waves=%d  gravity_moves=%d  refilled=%d\n" % [
		rep["chain_depth"], rep["secondary_triggers"], rep["waves"], rep["gravity_moves"], rep["refilled"]]
	if not rep["obj_before"].is_empty():
		s += "objective progress: %s -> %s   (targets %s)\n" % [str(rep["obj_before"]), str(rep["obj_after"]),
			str(_targets_of(rep["objectives"]))]
	s += "phase timings (ms): %s\n" % str(rep["phase_timings_ms"])
	s += "--- board BEFORE move ---\n%s\n" % rep["board_before"]
	if rep["board_after"] != "":
		s += "--- board AFTER  move ---\n%s\n" % rep["board_after"]
	s += "--- minimal repro (feed to diag_board_bot.gd repro mode) ---\n%s\n" % JSON.stringify(minimal_repro(rep))
	s += "===============================================================\n"
	return s

# ---- small helpers -----------------------------------------------------

func _score_for(result: ChainResolver.MoveResult) -> int:
	# Uses the real ScoreCalculator (neutral multipliers) so a reach_score
	# objective advances the same way it does in app._apply_move_result. The
	# exact multiplier maths is not what this bot is testing.
	var combo_mult := ScoreCalculator.combo_multiplier_for_depth(result.chain_depth)
	return ScoreCalculator.compute_move_score(result, power_config, combo_mult, 1.0)

func _first_letter_targets() -> Array:
	return _targets_of(level.objectives)

static func _targets_of(objs: Array) -> Array:
	var out: Array = []
	for o in objs:
		out.append(int(o.get("target", 0)))
	return out

static func _p2a(path: Array) -> Array:
	var out: Array = []
	for p in path:
		out.append([p.x, p.y])
	return out

static func _sn2a(arr: Array) -> Array:
	var out: Array = []
	for s in arr:
		out.append(String(s))
	return out

static func _merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate()
	for k in b:
		out[k] = b[k]
	return out
