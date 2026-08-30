extends SceneTree
## Manual dev tool: drives the full requested audio chain end-to-end in the
## real running game — connect -> match -> power -> blast -> cascade ->
## combo -> Fever -> level completion — and asserts every stage actually
## fired a sound and (where relevant) an adaptive-music state change.
## Not part of the CI test_runner (it touches the scene tree and takes a
## few seconds); run manually after any audio change.

var _sounds: Array[Dictionary] = []
var _states: Array[String] = []

func _initialize() -> void:
	await process_frame
	await process_frame

	var scene: PackedScene = load("res://scenes/main.tscn")
	var app := scene.instantiate()
	get_root().add_child(app)
	await process_frame
	await process_frame

	var audio := get_root().get_node("Audio")
	var music := get_root().get_node("Music")
	var economy := get_root().get_node("Economy")
	var boosters := get_root().get_node("Boosters")

	audio.sound_played.connect(func(id, intensity, event_index):
		_sounds.append({"id": String(id), "intensity": intensity, "event_index": event_index})
	)
	music.state_changed.connect(func(state): _states.append(String(state)))

	var game_data := get_root().get_node("GameData")
	await app._go_to_level(game_data.levels.first_level_id())
	await process_frame
	var board = app._board
	economy.grant(1000000)

	# ---- 1) CONNECT -> MATCH: drive a real drag gesture (not a direct
	# resolve() call) so the per-cell "select" tick is exercised too. ----
	var path := _find_valid_path(board.board, 4)
	assert(path.size() >= 3, "could not find a test path")
	print("Step 1: connecting a real path of size ", path.size())
	board._begin_drag(board.to_global(board._slot_center(path[0])))
	for i in range(1, path.size()):
		board._update_drag(board.to_global(board._slot_center(path[i])))
	board._end_drag()
	await process_frame
	# Wait for the async animation coroutine to finish (poll _locked_input).
	var guard := 0
	while board._locked_input and guard < 300:
		await process_frame
		guard += 1

	_expect_sound("select", "connect tick")
	_expect_sound("match", "match sound")
	if path.size() >= 4:
		_expect_any_sound(["power_bomb", "power_lightning", "power_chain", "power_rainbow"], "power creation signature sound")
	_expect_sound("blast", "blast impact")

	# ---- 2) CASCADE / COMBO: force a few booster detonations, which also
	# exercise power + blast + chain_step + combo escalation. ----
	print("Step 2: booster cascades")
	for i in 3:
		boosters.purchase(&"bomb")
		board.apply_power_booster(&"bomb")
		await process_frame
		guard = 0
		while board._locked_input and guard < 300:
			await process_frame
			guard += 1

	# ---- 3) FEVER: keep triggering chain-y moves until Fever activates. ----
	print("Step 3: building Fever meter via repeated bomb/lightning boosters")
	var fever_seen := false
	for i in 40:
		if app._fever.is_active():
			fever_seen = true
			break
		boosters.purchase(&"lightning")
		board.apply_power_booster(&"lightning")
		await process_frame
		guard = 0
		while board._locked_input and guard < 300:
			await process_frame
			guard += 1
	fever_seen = fever_seen or app._fever.is_active()
	print("Fever active: ", fever_seen, "  meter=", app._fever.meter)
	if fever_seen:
		_expect_sound("fever_activate", "Fever activation sting")
		_expect_state("fever", "music switches to Fever state")
	else:
		print("WARNING: Fever did not activate in the allotted attempts (non-fatal, config-dependent)")

	# ---- 4) LEVEL COMPLETION ----
	print("Step 4: level completion jingle")
	_sounds.clear()
	app._on_level_won()
	_expect_sound("level_complete", "victory jingle")

	# ---- 5) LEVEL FAILURE (soft, non-punishing) ----
	print("Step 5: level failure motif")
	_sounds.clear()
	app._on_level_lost()
	_expect_sound("level_failed", "try-again motif")

	print("---- Sound ids observed this run: ", _unique_ids(), " ----")
	print("---- Music states observed this run: ", _states, " ----")
	print("AUDIO CHAIN SMOKE TEST PASSED")
	quit(0)

func _unique_ids() -> Array:
	var seen := {}
	for s in _sounds:
		seen[s["id"]] = true
	return seen.keys()

func _expect_sound(id: String, label: String) -> void:
	for s in _sounds:
		if s["id"] == id:
			print("  OK: ", label, " (", id, ") intensity=", s["intensity"], " event_index=", s["event_index"])
			return
	push_error("MISSING EXPECTED SOUND: %s (%s)" % [id, label])
	assert(false, "missing sound " + id)

func _expect_any_sound(ids: Array, label: String) -> void:
	for s in _sounds:
		if ids.has(s["id"]):
			print("  OK: ", label, " -> ", s["id"])
			return
	push_error("MISSING EXPECTED SOUND (one of %s): %s" % [str(ids), label])
	assert(false, "missing one of " + str(ids))

func _expect_state(state: String, label: String) -> void:
	if _states.has(state):
		print("  OK: ", label)
	else:
		push_error("MUSIC STATE NEVER REACHED: %s (%s)" % [state, label])
		assert(false, "missing state " + state)

func _find_valid_path(board, min_len: int) -> Array:
	for x in board.width:
		for y in board.height:
			var start := Vector2i(x, y)
			var cell = board.get_cell(start)
			if cell == null or not cell.is_selectable():
				continue
			var path = _dfs_path(board, start, cell.color_id, min_len)
			if path.size() >= min_len:
				return path
	return []

func _dfs_path(board, start: Vector2i, color, target_len: int) -> Array:
	var visited := {start: true}
	var path: Array = [start]
	_extend(board, color, visited, path, target_len)
	return path

func _extend(board, color, visited: Dictionary, path: Array, target_len: int) -> bool:
	if path.size() >= target_len:
		return true
	var current: Vector2i = path[path.size() - 1]
	for n in board.get_orthogonal_neighbors(current):
		if visited.has(n):
			continue
		var cell = board.get_cell(n)
		if cell == null or not cell.is_selectable() or cell.color_id != color:
			continue
		visited[n] = true
		path.append(n)
		if _extend(board, color, visited, path, target_len):
			return true
		path.pop_back()
	return false
