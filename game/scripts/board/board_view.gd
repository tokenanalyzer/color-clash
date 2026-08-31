class_name BoardView
extends Node2D
## Owns one level's BoardModel plus its visual/interactive presentation:
## touch/drag path selection, resolving moves through ChainResolver, and
## animating the result (power flash -> pop -> gravity/refill -> settle).
## Game-session concerns (score, combo, fever, objectives, moves-left) live
## in GameController, which listens to `move_resolved`.

signal move_resolved(result: ChainResolver.MoveResult)
signal booster_resolved(result: ChainResolver.MoveResult)
signal board_shuffled()

var board: BoardModel
var palette: PieceColorPalette
var power_config: PowerConfig
var available_colors: Array[StringName] = []
var rainbow_chance: float = 0.0
var rng := RandomNumberGenerator.new()

var particles: ParticlePool

var _piece_nodes: Array = [] # [x][y] -> PieceView
var _cell_size: float = 64.0
var _origin: Vector2 = Vector2.ZERO
var _dragging := false
var _current_path: Array[Vector2i] = []
var _locked_input := false
var _path_glow: Line2D
var _path_line: Line2D
var _path_color: Color = Color(1, 1, 1)

func setup(level: LevelConfig, p_palette: PieceColorPalette, p_power_config: PowerConfig, p_rainbow_chance: float, rng_seed: int, viewport_rect: Rect2) -> void:
	palette = p_palette
	power_config = p_power_config
	rainbow_chance = p_rainbow_chance
	available_colors = level.colors
	rng.seed = rng_seed

	board = BoardModel.new(level.width, level.height, power_config.min_group_size())
	for obstacle in level.obstacles:
		var pos := Vector2i(int(obstacle.get("x", 0)), int(obstacle.get("y", 0)))
		board.set_obstacle(pos, StringName(String(obstacle.get("type", "none"))), int(obstacle.get("hp", 0)))
	_generate_playable_board()

	_fit_layout(viewport_rect, level.width, level.height)
	_build_piece_pool(level.width, level.height)
	_resync_all_from_board()

	particles = ParticlePool.new()
	add_child(particles)

	_path_glow = Line2D.new()
	_path_glow.width = _cell_size * 0.42
	_path_glow.default_color = Color(1, 1, 1, 0.18)
	_path_glow.z_index = 49
	_path_glow.antialiased = true
	_path_glow.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_path_glow.end_cap_mode = Line2D.LINE_CAP_ROUND
	_path_glow.joint_mode = Line2D.LINE_JOINT_ROUND
	add_child(_path_glow)

	_path_line = Line2D.new()
	_path_line.width = _cell_size * 0.16
	_path_line.default_color = Color(1, 1, 1, 0.9)
	_path_line.z_index = 50
	_path_line.antialiased = true
	_path_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_path_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	_path_line.joint_mode = Line2D.LINE_JOINT_ROUND
	add_child(_path_line)

	queue_redraw()

func has_valid_moves() -> bool:
	return board.has_any_valid_move()

## External input gate (pause menu). Never unlocks while a cascade is mid-
## resolve — `_play_move` clears its own lock when it finishes.
func set_input_locked(v: bool) -> void:
	_locked_input = v

func _generate_playable_board() -> void:
	board.generate(rng, available_colors)
	var guard := 0
	while not board.has_any_valid_move() and guard < 20:
		board.generate(rng, available_colors)
		guard += 1

func _fit_layout(viewport_rect: Rect2, width: int, height: int) -> void:
	var margin := 24.0
	var avail := viewport_rect.size - Vector2(margin, margin) * 2.0
	_cell_size = min(avail.x / float(width), avail.y / float(height))
	var grid_size := Vector2(_cell_size * width, _cell_size * height)
	_origin = (viewport_rect.size - grid_size) * 0.5

func _build_piece_pool(width: int, height: int) -> void:
	_piece_nodes.resize(width)
	for x in width:
		var col: Array = []
		col.resize(height)
		for y in height:
			var node := PieceView.new()
			node.position = _slot_center(Vector2i(x, y))
			add_child(node)
			col[y] = node
		_piece_nodes[x] = col

func _slot_center(pos: Vector2i) -> Vector2:
	return _origin + Vector2(pos.x + 0.5, pos.y + 0.5) * _cell_size

func _node_at(pos: Vector2i) -> PieceView:
	if pos.x < 0 or pos.x >= _piece_nodes.size():
		return null
	var col: Array = _piece_nodes[pos.x]
	if pos.y < 0 or pos.y >= col.size():
		return null
	return col[pos.y]

func _resync_all_from_board() -> void:
	for x in board.width:
		for y in board.height:
			var pos := Vector2i(x, y)
			var cell := board.get_cell(pos)
			var node := _node_at(pos)
			node.scale = Vector2.ONE
			node.modulate.a = 1.0
			node.configure(cell.color_id, cell.power_id, cell.obstacle_id, cell.obstacle_hp, _cell_size, palette)

func _draw() -> void:
	if board == null:
		return
	var pad := _cell_size * 0.34
	var grid := Vector2(board.width, board.height) * _cell_size
	var frame := Rect2(_origin - Vector2(pad, pad), grid + Vector2(pad, pad) * 2.0)

	# outer frame: drop shadow, gradient body, bright top edge
	var r := _cell_size * 0.5
	draw_rect(Rect2(frame.position + Vector2(0, 10), frame.size), Color(0, 0, 0, 0.35), true)
	_draw_round_rect(frame, r, VisualTheme.PANEL_RAISED)
	_draw_round_rect(frame.grow(-3.0), r, VisualTheme.PANEL_SOLID)
	# inner well
	var well := Rect2(_origin - Vector2(pad * 0.4, pad * 0.4), grid + Vector2(pad * 0.4, pad * 0.4) * 2.0)
	_draw_round_rect(well, _cell_size * 0.4, VisualTheme.WELL)

	# per-cell sockets
	for x in board.width:
		for y in board.height:
			var c := _slot_center(Vector2i(x, y))
			var s := _cell_size * 0.4
			draw_circle(c + Vector2(0, _cell_size * 0.04), s, Color(0, 0, 0, 0.22))
			draw_circle(c, s, Color(1, 1, 1, 0.035))

	# selection path pips
	if _current_path.size() >= 1:
		for pos in _current_path:
			var p := _slot_center(pos)
			draw_circle(p, _cell_size * 0.12, Color(_path_color.r, _path_color.g, _path_color.b, 0.9))
			draw_circle(p, _cell_size * 0.07, Color(1, 1, 1, 0.95))

func _draw_round_rect(rect: Rect2, radius: float, color: Color) -> void:
	var pts := ShapeDrawUtils.rounded_rect_points(rect.size, radius, 5)
	var moved := PackedVector2Array()
	for p in pts:
		moved.append(p + rect.position + rect.size * 0.5)
	draw_colored_polygon(moved, color)

# ---------------------------------------------------------------- input --

func _unhandled_input(event: InputEvent) -> void:
	if _locked_input or board == null:
		return
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed:
			_begin_drag(e.position)
		else:
			_end_drag()
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		_update_drag((event as InputEventScreenDrag).position)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var e := event as InputEventMouseButton
		if e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				_begin_drag(e.position)
			else:
				_end_drag()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		_update_drag((event as InputEventMouseMotion).position)
		get_viewport().set_input_as_handled()

func _pixel_to_cell(local: Vector2) -> Vector2i:
	var rel := local - _origin
	return Vector2i(int(floor(rel.x / _cell_size)), int(floor(rel.y / _cell_size)))

func _begin_drag(screen_pos: Vector2) -> void:
	var cell := _pixel_to_cell(to_local(screen_pos))
	if not board.in_bounds(cell):
		return
	var cell_data := board.get_cell(cell)
	if cell_data == null or not cell_data.is_selectable():
		return
	_dragging = true
	_current_path = [cell]
	_refresh_selection_visual()
	Audio.play(&"select", 0.0)

func _update_drag(screen_pos: Vector2) -> void:
	if not _dragging:
		return
	var cell := _pixel_to_cell(to_local(screen_pos))
	if not board.in_bounds(cell):
		return
	if _current_path.size() >= 2 and cell == _current_path[_current_path.size() - 2]:
		_current_path.pop_back()
		_refresh_selection_visual()
		return
	if _current_path.has(cell):
		return
	if not board.is_adjacent(_current_path[_current_path.size() - 1], cell):
		return
	var cell_data := board.get_cell(cell)
	if cell_data == null or not cell_data.is_selectable():
		return
	var target := board.get_path_target_color(_current_path)
	if target != BoardModel.RAINBOW_COLOR_ID and cell_data.color_id != BoardModel.RAINBOW_COLOR_ID and cell_data.color_id != target:
		return
	_current_path.append(cell)
	_refresh_selection_visual()
	Audio.play(&"select", clampf(float(_current_path.size()) / 10.0, 0.0, 1.0))

func _end_drag() -> void:
	if not _dragging:
		return
	_dragging = false
	var path := _current_path
	_current_path = []
	_refresh_selection_visual()
	if path.size() >= board.min_group_size:
		_locked_input = true
		_play_move(path)

func _refresh_selection_visual() -> void:
	for x in board.width:
		for y in board.height:
			_node_at(Vector2i(x, y)).set_selected(false)
	var pts := PackedVector2Array()
	for pos in _current_path:
		_node_at(pos).set_selected(true)
		pts.append(_slot_center(pos))
	if not _current_path.is_empty():
		var target := board.get_path_target_color(_current_path)
		_path_color = Color(1, 1, 1)
		if target != BoardModel.RAINBOW_COLOR_ID and palette != null and palette.has(target):
			_path_color = palette.get_def(target).glow_color
	_path_line.points = pts
	_path_glow.points = pts
	_path_line.default_color = Color(1, 1, 1, 0.92)
	_path_glow.default_color = Color(_path_color.r, _path_color.g, _path_color.b, 0.28)
	queue_redraw()

# ------------------------------------------------------------- resolve --

## Chain depth is 1 for a plain match, 2 for one power created+detonated,
## and 3+ for a real multi-stage cascade — either a big move that created
## several powers which catch each other, or a blast exposing a fresh
## same-color cluster that auto-chains into another wave (and maybe another
## power) — see chain_resolver.gd's docstring. All three tiers are reachable
## through real play, not just the first.
const _COMBO_TIERS := [2, 4, 6]
const _WAVE_STAGGER := 0.07

func _play_move(path: Array[Vector2i]) -> void:
	var result := ChainResolver.resolve_move(board, path, power_config, rng, available_colors, rainbow_chance)
	if not result.valid:
		_locked_input = false
		return
	await _animate_result(result, path.size())
	_locked_input = false
	move_resolved.emit(result)
	if not board.has_any_valid_move():
		await _reshuffle()

static func _power_sfx_id(power_id: StringName) -> StringName:
	match power_id:
		&"bomb":
			return &"power_bomb"
		&"lightning":
			return &"power_lightning"
		&"chain":
			return &"power_chain"
		&"rainbow":
			return &"power_rainbow"
		_:
			return &"blast"

## Plays out one move's whole cascade wave-by-wave (initial match, then each
## power detonation in order) so both the visuals and the audio ripple
## outward and escalate rather than popping everything at once — this is
## what makes a big chain feel like an escalating musical event instead of
## one flat explosion. `group_size` is the player's drawn path length (0 for
## booster-triggered detonations, which skip the "match" sfx since nothing
## was connected).
func _animate_result(result: ChainResolver.MoveResult, group_size: int = 0) -> void:
	var chain_depth := result.chain_depth
	var animated: Dictionary = {}
	var pop_tweens: Array[Tween] = []

	for wave_index in result.wave_cells.size():
		var cells: Array = result.wave_cells[wave_index]
		# Each wave carries its own metadata (whether it's a power detonation,
		# and which power) rather than assuming wave_index lines up 1:1 with
		# powers_activated — auto-chain waves (a secondary exposed-cluster
		# clear) are interspersed and don't activate a power themselves.
		var wave_info: Dictionary = result.score_events[wave_index]
		if wave_info.has("power_id"):
			var power_pos: Vector2i = wave_info["power_pos"]
			var power_id: StringName = wave_info["power_id"]
			var power_node := _node_at(power_pos)
			if power_node != null:
				power_node.power_id = power_id
				power_node.queue_redraw()
			Audio.play(_power_sfx_id(power_id), 0.0, 0)
			Audio.play(&"chain_step", clampf(float(wave_index) / 6.0, 0.0, 1.0), wave_index - 1)
		elif wave_index == 0 and group_size > 0:
			Audio.play(&"match", clampf(float(group_size - 3) / 5.0, 0.0, 1.0))

		Audio.play(&"blast", clampf(float(cells.size()) / 10.0, 0.0, 1.0), wave_index)

		var pop_tween: Tween = null
		var wave_sum := Vector2.ZERO
		var wave_hits := 0
		var wave_tint := Color(1, 1, 1)
		for pos in cells:
			if animated.has(pos):
				continue
			animated[pos] = true
			var node := _node_at(pos)
			if node == null:
				continue
			var board_cell := board.get_cell(pos)
			if board_cell != null and not board_cell.is_empty():
				continue
			if pop_tween == null:
				pop_tween = create_tween()
				pop_tween.set_parallel(true)
			wave_tint = _burst_color_for(node)
			particles.burst(node.global_position, wave_tint, 8 + wave_index * 2)
			wave_sum += node.position
			wave_hits += 1
			pop_tween.tween_property(node, "scale", Vector2.ZERO, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		if pop_tween != null:
			pop_tweens.append(pop_tween)
		if wave_hits > 0:
			var wave_center := wave_sum / float(wave_hits)
			var flash_col := wave_tint
			if wave_info.has("power_id"):
				flash_col = Color(1, 1, 1)
			particles.flash(to_global(wave_center), flash_col, _cell_size * (1.2 + 0.14 * float(wave_hits)))
			if wave_info.has("power_id"):
				ScreenShake.apply(self, 4.0 + float(wave_hits) * 0.4, 0.2)

		if wave_index < result.wave_cells.size() - 1:
			await get_tree().create_timer(_WAVE_STAGGER).timeout

	if not pop_tweens.is_empty():
		await pop_tweens[pop_tweens.size() - 1].finished
	for pos in animated.keys():
		var node := _node_at(pos)
		if node == null:
			continue
		node.scale = Vector2.ONE
		node.configure(CellData.COLOR_EMPTY, CellData.POWER_NONE, node.obstacle_id, node.obstacle_hp, _cell_size, palette)

	if chain_depth >= 3:
		ScreenShake.apply(self, 6.0 + float(chain_depth), 0.28)
		Haptics.medium()
	elif chain_depth > 1:
		Haptics.light()

	var ghosts: Array[PieceView] = []
	var fly_tween: Tween = null
	for move in result.gravity_moves:
		var from_pos: Vector2i = move["from"]
		var to_pos: Vector2i = move["to"]
		var cell := board.get_cell(to_pos)
		var ghost := _spawn_ghost(cell, _slot_center(from_pos))
		ghosts.append(ghost)
		if fly_tween == null:
			fly_tween = create_tween()
			fly_tween.set_parallel(true)
		fly_tween.tween_property(ghost, "position", _slot_center(to_pos), 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	var column_refill_index: Dictionary = {}
	for pos in result.refilled_cells:
		var cell := board.get_cell(pos)
		var idx: int = column_refill_index.get(pos.x, 0)
		column_refill_index[pos.x] = idx + 1
		var start := _slot_center(Vector2i(pos.x, -1 - idx))
		var ghost := _spawn_ghost(cell, start)
		ghosts.append(ghost)
		if fly_tween == null:
			fly_tween = create_tween()
			fly_tween.set_parallel(true)
		fly_tween.tween_property(ghost, "position", _slot_center(pos), 0.24 + float(idx) * 0.03).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

	if fly_tween != null:
		await fly_tween.finished
	for g in ghosts:
		g.queue_free()

	_resync_all_from_board()

	if not result.cleared_cells.is_empty() and (chain_depth > 1 or result.cleared_cells.size() >= 6):
		var anchor := Vector2.ZERO
		for cp in result.cleared_cells:
			anchor += _slot_center(cp)
		anchor /= float(result.cleared_cells.size())
		anchor.y -= _cell_size * 0.6
		var pr := VisualTheme.praise(chain_depth, result.cleared_cells.size())
		var sub := "COMBO x%d" % chain_depth if chain_depth > 1 else ""
		ComboPopup.spawn(self, anchor, String(pr["text"]), pr["color"], 46, sub)
		var tier := _combo_tier(chain_depth)
		if tier >= 0:
			Audio.play(&"combo_ding", 0.0, tier)

func _combo_tier(chain_depth: int) -> int:
	var tier := -1
	for i in _COMBO_TIERS.size():
		if chain_depth >= _COMBO_TIERS[i]:
			tier = i
	return tier

# ------------------------------------------------------------ boosters --

## Detonates a Bomb/Lightning/Rainbow booster at a random eligible cell.
func apply_power_booster(power_id: StringName) -> void:
	if _locked_input or board == null:
		return
	var candidates: Array[Vector2i] = []
	for x in board.width:
		for y in board.height:
			var pos := Vector2i(x, y)
			var cell := board.get_cell(pos)
			if cell != null and cell.is_selectable():
				candidates.append(pos)
	if candidates.is_empty():
		return
	_locked_input = true
	var pos: Vector2i = candidates[rng.randi_range(0, candidates.size() - 1)]
	var result := ChainResolver.detonate_power_at(board, pos, power_id, power_config, rng, available_colors, rainbow_chance)
	await _animate_result(result)
	_locked_input = false
	booster_resolved.emit(result)
	if not board.has_any_valid_move():
		await _reshuffle()

## Shuffles the whole board without consuming a move (Shuffle booster).
func request_shuffle() -> void:
	if _locked_input or board == null:
		return
	await _reshuffle()

func _spawn_ghost(cell: CellData, pos: Vector2) -> PieceView:
	var ghost := PieceView.new()
	ghost.configure(cell.color_id, cell.power_id, CellData.OBSTACLE_NONE, 0, _cell_size, palette)
	ghost.position = pos
	add_child(ghost)
	return ghost

func _burst_color_for(node: PieceView) -> Color:
	if node.color_id == BoardModel.RAINBOW_COLOR_ID:
		return Color(1, 1, 1)
	if palette != null and palette.has(node.color_id):
		return palette.get_def(node.color_id).glow_color
	return Color(0.8, 0.8, 0.8)

func _reshuffle() -> void:
	_locked_input = true
	var fade_out := create_tween()
	fade_out.set_parallel(true)
	for x in board.width:
		for y in board.height:
			fade_out.tween_property(_node_at(Vector2i(x, y)), "modulate:a", 0.15, 0.15)
	await fade_out.finished

	_generate_playable_board()
	_resync_all_from_board()

	var fade_in := create_tween()
	fade_in.set_parallel(true)
	for x in board.width:
		for y in board.height:
			fade_in.tween_property(_node_at(Vector2i(x, y)), "modulate:a", 1.0, 0.2)
	await fade_in.finished

	Audio.play(&"shuffle")
	_locked_input = false
	board_shuffled.emit()
