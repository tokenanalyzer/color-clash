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

## Fever spectacle: while active the board wears a pulsing hot aura, the
## selection trail runs hotter/wider, blasts throw more (and hotter)
## particles, and the whole cascade plays back faster (`_cascade_scale`).
var fever_active := false
var _fever_phase := 0.0
var _cascade_scale := 1.0

func setup(level: LevelConfig, p_palette: PieceColorPalette, p_power_config: PowerConfig, p_rainbow_chance: float, rng_seed: int, viewport_rect: Rect2) -> void:
	palette = p_palette
	power_config = p_power_config
	rainbow_chance = p_rainbow_chance
	available_colors = level.colors
	rng.seed = rng_seed

	# Bake the jewel textures once (hidden by the level-in fade). Cheap
	# re-call after the first level — GemTextures caches everything.
	GemTextures.prime(palette)

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

	# _process only runs during Fever (board aura pulse) — off by default so
	# a normal board costs nothing per frame.
	set_process(false)
	queue_redraw()

func has_valid_moves() -> bool:
	return board.has_any_valid_move()

## Re-fit the board to a new viewport rect (orientation / window resize).
## Cell nodes keep their identity; only geometry is recomputed.
func refit(viewport_rect: Rect2) -> void:
	if board == null or _locked_input:
		return
	_fit_layout(viewport_rect, board.width, board.height)
	for x in board.width:
		for y in board.height:
			var node := _node_at(Vector2i(x, y))
			if node != null:
				node.position = _slot_center(Vector2i(x, y))
				node.cell_size = _cell_size
				node.queue_redraw()
	_path_line.width = _cell_size * 0.16
	_path_glow.width = _cell_size * 0.42
	_refresh_selection_visual()
	queue_redraw()

## External input gate (pause menu). Never unlocks while a cascade is mid-
## resolve — `_play_move` clears its own lock when it finishes.
func set_input_locked(v: bool) -> void:
	_locked_input = v

## Toggled by the controller when FeverSystem activates / expires.
func set_fever(v: bool) -> void:
	if fever_active == v:
		return
	fever_active = v
	_cascade_scale = 0.55 if v else 1.0
	_update_process()
	_refresh_selection_visual()
	queue_redraw()

func _process(delta: float) -> void:
	_fever_phase += delta
	if fever_active or _armed_booster_id != &"":
		queue_redraw()
	# occasional idle glint on a random settled jewel — keeps the board alive
	if not _locked_input and board != null:
		_idle_t += delta
		if _idle_t >= _next_sparkle:
			_idle_t = 0.0
			_next_sparkle = randf_range(1.6, 3.4)
			_idle_sparkle()

func _idle_sparkle() -> void:
	if particles == null:
		return
	for _try in 5:
		var p := Vector2i(rng.randi_range(0, board.width - 1), rng.randi_range(0, board.height - 1))
		var cell := board.get_cell(p)
		if cell != null and not cell.is_empty() and not cell.has_power():
			var node := _node_at(p)
			if node != null:
				particles.burst(node.global_position + Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * _cell_size * 0.25,
					Color(1, 1, 1, 0.8), 2)
			return

## A screen-filling punctuation the instant Fever ignites: central flash,
## a ring of bursts around the board, a hard shake and a big FEVER! title.
func play_fever_burst() -> void:
	var vp := _board_rect_center()
	particles.flash(to_global(vp), VisualTheme.FEVER_HOT, _cell_size * 8.0)
	var grid := _grid_px()
	for i in 10:
		var a := TAU * float(i) / 10.0
		var p := vp + Vector2(cos(a), sin(a)) * grid.length() * 0.42
		particles.burst(to_global(p), VisualTheme.FEVER if i % 2 == 0 else VisualTheme.FEVER_HOT, 16)
	ScreenShake.apply(self, 16.0, 0.4)
	Haptics.strong(110)
	ComboPopup.spawn(self, vp - Vector2(0, _cell_size), "FEVER!", VisualTheme.FEVER_HOT, 64, "GO WILD")

## Pixel span of the honeycomb playfield (top-left at _origin).
func _grid_px() -> Vector2:
	return Vector2((float(board.width) + 0.5) * _cell_size,
		(float(board.height - 1) * HEX_ROW + 1.0) * _cell_size)

func _board_rect_center() -> Vector2:
	return _origin + _grid_px() * 0.5

func _generate_playable_board() -> void:
	board.generate(rng, available_colors)
	var guard := 0
	while not board.has_any_valid_move() and guard < 20:
		board.generate(rng, available_colors)
		guard += 1

## Honeycomb layout: odd rows are shifted +½ cell right, and rows are packed
## at HEX_ROW (≈0.866) of a cell apart so the hexagons interlock. The grid
## therefore spans (width + 0.5) cells across and (height·0.866 + 0.134) down.
const HEX_ROW := 0.866025

func _fit_layout(viewport_rect: Rect2, width: int, height: int) -> void:
	var margin := 20.0
	var avail := viewport_rect.size - Vector2(margin, margin) * 2.0
	var span_x := float(width) + 0.5
	var span_y := float(height - 1) * HEX_ROW + 1.0
	_cell_size = min(avail.x / span_x, avail.y / span_y)
	var grid_size := Vector2(_cell_size * span_x, _cell_size * span_y)
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
	var x_off := 0.5 if (pos.y & 1) == 1 else 0.0
	return _origin + Vector2((float(pos.x) + 0.5 + x_off) * _cell_size,
		(float(pos.y) * HEX_ROW + 0.5) * _cell_size)

## Nearest hex-cell centre to a local point (robust inverse of _slot_center).
func _cell_at_point(local: Vector2) -> Vector2i:
	var approx_y := int(round((local.y - _origin.y) / (_cell_size * HEX_ROW) - 0.5))
	var best := Vector2i(-1, -1)
	var best_d := INF
	for dy in range(-1, 2):
		var y := approx_y + dy
		if y < 0 or y >= board.height:
			continue
		var x_off := 0.5 if (y & 1) == 1 else 0.0
		var approx_x := int(round((local.x - _origin.x) / _cell_size - 0.5 - x_off))
		for dx in range(-1, 2):
			var x := approx_x + dx
			if x < 0 or x >= board.width:
				continue
			var d := local.distance_squared_to(_slot_center(Vector2i(x, y)))
			if d < best_d:
				best_d = d
				best = Vector2i(x, y)
	return best

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
	var grid := _grid_px()
	var frame := Rect2(_origin - Vector2(pad, pad), grid + Vector2(pad, pad) * 2.0)

	var r := _cell_size * 0.5

	# soft outer glow behind the whole board — separates it from the backdrop
	for i in range(5, 0, -1):
		var t := float(i) / 5.0
		_draw_round_rect(frame.grow(6.0 + t * 22.0), r + t * 16.0,
			Color(VisualTheme.ACCENT.r, VisualTheme.ACCENT.g, VisualTheme.ACCENT.b, 0.05 * (1.0 - t)))
	# drop shadow
	_draw_round_rect(Rect2(frame.position + Vector2(0, 12), frame.size), r, Color(0, 0, 0, 0.45))

	# Fever aura
	if fever_active:
		var fpulse := 0.5 + 0.5 * sin(_fever_phase * 7.0)
		for i in 5:
			var t := float(i) / 4.0
			var col := VisualTheme.FEVER.lerp(VisualTheme.FEVER_HOT, fpulse)
			col.a = (0.30 - 0.05 * float(i)) * (0.6 + 0.4 * fpulse)
			_draw_round_rect(frame.grow(6.0 + t * 28.0 + fpulse * 12.0), r + t * 22.0, col)

	# frame body: raised bevel — lighter top band, darker base
	_draw_round_rect(frame, r, VisualTheme.PANEL_RAISED.darkened(0.12))
	_draw_round_rect(Rect2(frame.position, Vector2(frame.size.x, frame.size.y * 0.5)), r,
		VisualTheme.PANEL_RAISED.lightened(0.10))
	_draw_round_rect(frame.grow(-4.0), r - 2.0, VisualTheme.PANEL_SOLID)

	# accent / fever rim
	var rim_col := Color(VisualTheme.ACCENT.r, VisualTheme.ACCENT.g, VisualTheme.ACCENT.b, 0.28)
	if fever_active:
		rim_col = VisualTheme.FEVER_HOT
		rim_col.a = 0.55 + 0.35 * sin(_fever_phase * 9.0)
	_draw_round_rect_outline(frame.grow(-3.0), r, rim_col, 2.5)

	# inner well with an inset shadow band across the top
	var well := Rect2(_origin - Vector2(pad * 0.42, pad * 0.42), grid + Vector2(pad * 0.42, pad * 0.42) * 2.0)
	_draw_round_rect(well, _cell_size * 0.42, VisualTheme.WELL)
	_draw_round_rect(Rect2(well.position, Vector2(well.size.x, _cell_size * 0.5)), _cell_size * 0.42,
		Color(0, 0, 0, 0.3))

	# per-cell sockets (recessed: dark rim + subtle bottom light)
	var socket_glow := 0.0
	if fever_active:
		socket_glow = 0.05 + 0.05 * sin(_fever_phase * 6.0)
	for x in board.width:
		for y in board.height:
			var c := _slot_center(Vector2i(x, y))
			var s := _cell_size * 0.42
			draw_circle(c + Vector2(0, _cell_size * 0.05), s, Color(0, 0, 0, 0.28))
			draw_circle(c, s * 0.96, Color(0.10, 0.12, 0.2, 0.5))
			draw_arc(c, s * 0.96, PI * 0.15, PI * 0.85, 10, Color(1, 1, 1, 0.05), 2.0, true)
			if socket_glow > 0.0:
				draw_circle(c, s * 1.05, Color(VisualTheme.FEVER_HOT.r, VisualTheme.FEVER_HOT.g, VisualTheme.FEVER_HOT.b, socket_glow))

	# armed-booster targeting overlay
	if _armed_booster_id != &"":
		var tint: Color = PieceView._POWER_GLOW.get(_armed_power_id, Color(1, 1, 1))
		var pulse := 0.5 + 0.5 * sin(_fever_phase * 6.0)
		var rp := ShapeDrawUtils.rounded_rect_points(frame.size, r, 6)
		var moved := PackedVector2Array()
		for p in rp:
			moved.append(p + frame.position + frame.size * 0.5)
		moved.append(moved[0])
		draw_polyline(moved, Color(tint.r, tint.g, tint.b, 0.4 + 0.4 * pulse), 4.0 + 2.0 * pulse, true)
		for x in board.width:
			for y in board.height:
				var c := _slot_center(Vector2i(x, y))
				draw_arc(c, _cell_size * 0.44, 0, TAU, 6, Color(tint.r, tint.g, tint.b, 0.12 + 0.1 * pulse), 2.0, true)

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

func _draw_round_rect_outline(rect: Rect2, radius: float, color: Color, width: float) -> void:
	var pts := ShapeDrawUtils.rounded_rect_points(rect.size, radius, 6)
	var moved := PackedVector2Array()
	for p in pts:
		moved.append(p + rect.position + rect.size * 0.5)
	moved.append(moved[0])
	draw_polyline(moved, color, width, true)

# ---------------------------------------------------------------- input --

## When set, a booster is "armed": the next tap on the board fires that
## power at the tapped cell instead of drawing a connection.
var _armed_booster_id: StringName = &""
var _armed_power_id: StringName = &""
var _press_cell := Vector2i(-1, -1)
var _drag_moved := false

signal booster_committed(booster_id: StringName)
signal booster_disarmed()

func arm_booster(booster_id: StringName, power_id: StringName) -> void:
	_armed_booster_id = booster_id
	_armed_power_id = power_id
	if _dragging:
		_dragging = false
		_current_path = []
		_refresh_selection_visual()
	_update_process()
	queue_redraw()

func disarm_booster() -> void:
	if _armed_booster_id != &"":
		_armed_booster_id = &""
		_armed_power_id = &""
		_update_process()
		queue_redraw()
		booster_disarmed.emit()

func _update_process() -> void:
	# always on for the idle sparkle; the board itself only redraws when it
	# actually animates (fever aura / armed reticle).
	set_process(true)

var _idle_t := 0.0
var _next_sparkle := 1.2

func is_booster_armed() -> bool:
	return _armed_booster_id != &""

func _unhandled_input(event: InputEvent) -> void:
	if _locked_input or board == null:
		return
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed:
			_begin_drag(e.position)
		else:
			_end_drag(e.position)
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
				_end_drag(e.position)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		_update_drag((event as InputEventMouseMotion).position)
		get_viewport().set_input_as_handled()

func _pixel_to_cell(local: Vector2) -> Vector2i:
	return _cell_at_point(local)

func _begin_drag(screen_pos: Vector2) -> void:
	var cell := _pixel_to_cell(to_local(screen_pos))
	_press_cell = cell
	_drag_moved = false
	if not board.in_bounds(cell):
		return
	# Armed booster: a plain tap fires it — no path drawing.
	if _armed_booster_id != &"":
		return
	var cell_data := board.get_cell(cell)
	if cell_data == null or not cell_data.is_selectable():
		return
	_dragging = true
	_current_path = [cell]
	_refresh_selection_visual()
	Audio.play(&"select", 0.0)

func _update_drag(screen_pos: Vector2) -> void:
	var cell := _pixel_to_cell(to_local(screen_pos))
	if cell != _press_cell:
		_drag_moved = true
	if not _dragging:
		return
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
	# Power tiles connect to any colour; otherwise the path must stay on one.
	if not cell_data.has_power():
		var target := board.get_path_target_color(_current_path)
		if target != BoardModel.RAINBOW_COLOR_ID and cell_data.color_id != BoardModel.RAINBOW_COLOR_ID and cell_data.color_id != target:
			return
	_current_path.append(cell)
	_refresh_selection_visual()
	Audio.play(&"select", clampf(float(_current_path.size()) / 10.0, 0.0, 1.0))

func _end_drag(screen_pos: Vector2 = Vector2.ZERO) -> void:
	# Armed-booster tap.
	if _armed_booster_id != &"":
		var tap := _pixel_to_cell(to_local(screen_pos)) if screen_pos != Vector2.ZERO else _press_cell
		if board.in_bounds(tap):
			var tc := board.get_cell(tap)
			if tc != null and (tc.is_selectable() or tc.is_stone() or tc.is_timebomb()):
				var used := _armed_booster_id
				_armed_booster_id = &""
				_armed_power_id = &""
				_locked_input = true
				booster_committed.emit(used)
				_apply_power_booster_at(tap, _power_for_booster(used))
				return
		disarm_booster()
		return

	if not _dragging:
		return
	_dragging = false
	var path := _current_path
	_current_path = []
	_refresh_selection_visual()

	# Single tap on a lone power tile -> detonate it.
	if path.size() == 1 and not _drag_moved and board.get_cell(path[0]).has_power():
		_locked_input = true
		_play_power_tap(path[0])
		return
	if board.validate_path(path):
		_locked_input = true
		_play_move(path)

func _power_for_booster(booster_id: StringName) -> StringName:
	var def: Dictionary = GameData.boosters.get(booster_id, {})
	return StringName(String(def.get("power", booster_id)))

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
	if fever_active:
		_path_line.width = _cell_size * 0.22
		_path_glow.width = _cell_size * 0.6
		_path_line.default_color = Color(1, 0.95, 0.9, 0.95)
		_path_glow.default_color = Color(VisualTheme.FEVER_HOT.r, VisualTheme.FEVER_HOT.g, VisualTheme.FEVER_HOT.b, 0.4)
	else:
		_path_line.width = _cell_size * 0.16
		_path_glow.width = _cell_size * 0.42
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

## Single tap on a power tile the player already built.
func _play_power_tap(pos: Vector2i) -> void:
	var result := ChainResolver.resolve_power_tap(board, pos, power_config, rng, available_colors, rainbow_chance)
	if not result.valid:
		_locked_input = false
		return
	await _animate_result(result, 0)
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
		&"freeze":
			return &"power_freeze"
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
		elif wave_info.has("timebomb"):
			# A time bomb the player left on the board just went off.
			Audio.play(&"timebomb_explode", 0.0, 0)
			ScreenShake.apply(self, 15.0, 0.42)
			Haptics.strong(130)
			var tb_pos: Vector2i = wave_info["power_pos"]
			particles.flash(_node_at(tb_pos).global_position, Color(1, 0.35, 0.2), _cell_size * 3.4)
			ComboPopup.spawn(self, _node_at(tb_pos).position - Vector2(0, _cell_size * 0.7), "BOOM!", Color(1, 0.4, 0.25), 44, "-%d MOVES" % ChainResolver.TIMEBOMB_MOVE_PENALTY)
		elif wave_index == 0 and group_size > 0:
			Audio.play(&"match", clampf(float(group_size - 3) / 5.0, 0.0, 1.0))

		Audio.play(&"blast", clampf(float(cells.size()) / 10.0, 0.0, 1.0), wave_index)

		# Anticipation -> impact -> reward: the wave's tiles first snap UP a
		# touch (anticipation), then collapse (impact) with the burst + flash
		# landing at the peak, then the popup/score reward follows.
		var anticip := 0.06 * _cascade_scale
		var collapse := 0.12 * _cascade_scale
		var wave_sum := Vector2.ZERO
		var wave_hits := 0
		var wave_tint := Color(1, 1, 1)
		var last_pop: Tween = null
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
			wave_tint = _burst_color_for(node)
			wave_sum += node.position
			wave_hits += 1
			var ct := create_tween()
			ct.tween_property(node, "scale", Vector2(1.18, 1.18), anticip).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			ct.tween_property(node, "scale", Vector2.ZERO, collapse).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			last_pop = ct
		if last_pop != null:
			pop_tweens.append(last_pop)
		if wave_hits > 0:
			var wave_center := wave_sum / float(wave_hits)
			var is_power := wave_info.has("power_id")
			var flash_col := Color(1, 1, 1) if is_power else wave_tint
			# Tiered feedback: a plain 3-match is quiet (small bursts, no flash);
			# a bigger clear or any power wave escalates.
			var big := wave_hits >= 5 or is_power
			var amount := (6 if not big else 10) + wave_index * 2
			if fever_active:
				amount = int(amount * 1.7)
				flash_col = flash_col.lerp(VisualTheme.FEVER_HOT, 0.35)
			await get_tree().create_timer(anticip).timeout
			for pos in cells:
				var node := _node_at(pos)
				if node != null:
					particles.burst(node.global_position, wave_tint.lerp(VisualTheme.FEVER_HOT, 0.4) if fever_active else wave_tint, amount)
			if big:
				var flash_r := _cell_size * (1.2 + 0.14 * float(wave_hits))
				particles.flash(to_global(wave_center), flash_col, flash_r * (1.4 if fever_active else 1.0))
			if is_power:
				ScreenShake.apply(self, 4.0 + float(wave_hits) * 0.5, 0.2)
				Haptics.light()

		if wave_index < result.wave_cells.size() - 1:
			await get_tree().create_timer(_WAVE_STAGGER * _cascade_scale).timeout

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
		fly_tween.tween_property(ghost, "position", _slot_center(to_pos), 0.18 * _cascade_scale).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

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
		fly_tween.tween_property(ghost, "position", _slot_center(pos), (0.24 + float(idx) * 0.03) * _cascade_scale).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

	if fly_tween != null:
		await fly_tween.finished
	for g in ghosts:
		g.queue_free()

	_resync_all_from_board()
	_settle_frozen_cells(result.frozen_cells)
	if result.powers_formed:
		await _animate_powers_formed(result)

	if not result.powers_formed and not result.cleared_cells.is_empty() and (chain_depth > 1 or result.cleared_cells.size() >= 5):
		var anchor := Vector2.ZERO
		for cp in result.cleared_cells:
			anchor += _slot_center(cp)
		anchor /= float(result.cleared_cells.size())
		anchor.y -= _cell_size * 0.6
		var pr := VisualTheme.praise(chain_depth, result.cleared_cells.size())
		var sub := "COMBO x%d" % chain_depth if chain_depth > 1 else ""
		var fs := 40 + mini(chain_depth, 6) * 4
		ComboPopup.spawn(self, anchor, String(pr["text"]), pr["color"], fs, sub)
		var tier := _combo_tier(chain_depth)
		if tier >= 0:
			Audio.play(&"combo_ding", 0.0, tier)

const _POWER_LABELS := {
	&"bomb": "BOMB", &"lightning": "LIGHTNING", &"freeze": "FREEZE",
	&"chain": "CHAIN", &"rainbow": "RAINBOW",
}
const _POWER_TINTS := {
	&"bomb": Color(1.0, 0.35, 0.3), &"lightning": Color(1.0, 0.9, 0.35),
	&"freeze": Color(0.6, 0.9, 1.0), &"chain": Color(0.4, 1.0, 0.6),
	&"rainbow": Color(0.9, 0.6, 1.0),
}

## "Power discovery" beat — a big plain match just LEFT a power tile on the
## board (not detonated). Pop it in, ring-flash it, name it the first few
## times so the player learns what they made, and nudge them to use it.
func _animate_powers_formed(result: ChainResolver.MoveResult) -> void:
	var seen: Dictionary = SaveService.get_value("powers_seen", {})
	var first_pid := &""
	var first_pos := Vector2.ZERO
	var last_tween: Tween = null
	for entry in result.powers_created:
		var pos: Vector2i = entry["pos"]
		var pid: StringName = entry["power_id"]
		var node := _node_at(pos)
		if node == null:
			continue
		if first_pid == &"":
			first_pid = pid
			first_pos = node.position
		var tint: Color = _POWER_TINTS.get(pid, Color(1, 1, 1))
		particles.flash(node.global_position, tint, _cell_size * 2.6)
		particles.burst(node.global_position, tint, 14)
		node.scale = Vector2(0.2, 0.2)
		var t := create_tween()
		t.tween_property(node, "scale", Vector2(1.32, 1.32), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(node, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_SINE)
		last_tween = t
	Audio.play(_power_sfx_id(first_pid), 0.2, 0)
	Haptics.light()
	ScreenShake.apply(self, 3.0, 0.16)
	if last_tween != null:
		await last_tween.finished

	# Teach the name + "connect it to fire" the first two times per type.
	var shown := int(seen.get(String(first_pid), 0))
	if shown < 2 and first_pid != &"":
		var label: String = _POWER_LABELS.get(first_pid, "POWER")
		ComboPopup.spawn(self, first_pos - Vector2(0, _cell_size * 0.9), "%s READY" % label,
			_POWER_TINTS.get(first_pid, Color(1, 1, 1)), 34, "connect it to fire")
		seen[String(first_pid)] = shown + 1
		SaveService.set_value("powers_seen", seen)
		SaveService.save()

## Frost-settle beat for cells the Freeze power just encased: an icy burst
## and a quick over-shoot scale on each newly-frozen node.
func _settle_frozen_cells(frozen: Array) -> void:
	if frozen.is_empty():
		return
	var frost := Color(0.7, 0.92, 1.0)
	var tw: Tween = null
	for pos in frozen:
		var node := _node_at(pos)
		if node == null:
			continue
		particles.burst(node.global_position, frost, 10)
		node.scale = Vector2(1.28, 1.28)
		if tw == null:
			tw = create_tween()
			tw.set_parallel(true)
		tw.tween_property(node, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	particles.flash(_node_at(frozen[0]).global_position, frost, _cell_size * 2.0)

func _combo_tier(chain_depth: int) -> int:
	var tier := -1
	for i in _COMBO_TIERS.size():
		if chain_depth >= _COMBO_TIERS[i]:
			tier = i
	return tier

# ------------------------------------------------------------ boosters --

## Detonates a targeted booster (Bomb/Lightning/Freeze/Rainbow) at `pos`.
## Called from _end_drag when an armed booster is tapped onto the board.
func _apply_power_booster_at(pos: Vector2i, power_id: StringName) -> void:
	if board == null:
		_locked_input = false
		return
	var cell := board.get_cell(pos)
	if cell == null:
		_locked_input = false
		return
	var result := ChainResolver.detonate_power_at(board, pos, power_id, power_config, rng, available_colors, rainbow_chance)
	if not result.valid:
		_locked_input = false
		return
	await _animate_result(result)
	_locked_input = false
	booster_resolved.emit(result)
	if not board.has_any_valid_move():
		await _reshuffle()

## Random-cell fallback (kept for any caller that fires a booster without a
## chosen target).
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
	await _apply_power_booster_at(candidates[rng.randi_range(0, candidates.size() - 1)], power_id)

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
