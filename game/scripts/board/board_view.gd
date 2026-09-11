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
var sfx: SpriteFX               # prepared burst artwork (assets 19-26, 72-74)
var _path_head: Sprite2D        # comet head on the live end of the connection

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
	for sp in level.specials:
		board.set_special(Vector2i(int(sp.get("x", 0)), int(sp.get("y", 0))),
			StringName(String(sp.get("type", "relic"))))
	_generate_playable_board()

	_fit_layout(viewport_rect, level.width, level.height)
	_build_piece_pool(level.width, level.height)
	_resync_all_from_board()

	particles = ParticlePool.new()
	add_child(particles)
	sfx = SpriteFX.new()
	add_child(sfx)

	_path_head = Sprite2D.new()
	_path_head.texture = AssetLibrary.tex(&"vfx_energy_trail_head")
	_path_head.z_index = 52
	_path_head.visible = false
	_path_head.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if _path_head.texture != null:
		var hs := _cell_size * 0.9 / float(maxi(_path_head.texture.get_width(), _path_head.texture.get_height()))
		_path_head.scale = Vector2(hs, hs)
	add_child(_path_head)

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
	_path_line.width = _cell_size * 0.18
	_path_line.default_color = Color(1, 1, 1, 0.95)
	_path_line.z_index = 50
	_path_line.antialiased = true
	_path_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_path_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	_path_line.joint_mode = Line2D.LINE_JOINT_ROUND
	# comet taper — the trail thins towards its tail so the drawing hand reads
	# as the "live" end of the connection.
	var taper := Curve.new()
	taper.add_point(Vector2(0.0, 0.35))
	taper.add_point(Vector2(0.12, 1.0))
	taper.add_point(Vector2(1.0, 0.9))
	_path_line.width_curve = taper
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
				var jitter := Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * _cell_size * 0.22
				if sfx != null and AssetLibrary.has(&"vfx_glow_orb"):
					sfx.play(&"vfx_glow_orb", node.global_position + jitter, _cell_size * 0.8, Color(1, 1, 1, 0.85), 0.5, true)
				else:
					particles.burst(node.global_position + jitter, Color(1, 1, 1, 0.8), 2)
			return

## A screen-filling punctuation the instant Fever ignites: central flash,
## a ring of bursts around the board, a hard shake and a big FEVER! title.
func play_fever_burst() -> void:
	var vp := _board_rect_center()
	sfx.play_hold(&"cel_fever_activation_emblem", to_global(vp), _cell_size * 6.5, Color(1, 1, 1), 0.75, true, 0.6)
	particles.flash(to_global(vp), VisualTheme.FEVER_HOT, _cell_size * 8.0)
	var grid := _grid_px()
	for i in 10:
		var a := TAU * float(i) / 10.0
		var p := vp + Vector2(cos(a), sin(a)) * grid.length() * 0.42
		particles.burst(to_global(p), VisualTheme.FEVER if i % 2 == 0 else VisualTheme.FEVER_HOT, 16)
	ScreenShake.apply(self, 16.0, 0.4)
	Haptics.strong(110)
	ComboPopup.spawn(self, vp - Vector2(0, _cell_size), "FEVER!", VisualTheme.FEVER_HOT, 64, "GO WILD")

## Level-clear flourish over the board — a rising Level Complete Portal (#73)
## and a firework burst. Called by GameController just before the win panel.
func play_win_flourish() -> void:
	if sfx == null:
		return
	var c := _board_rect_center()
	sfx.play_hold(&"cel_level_complete_portal", to_global(c), _cell_size * 6.5, Color(1, 1, 1), 0.9, true, 0.4)
	sfx.play(&"cel_firework_burst", to_global(c) - Vector2(0, _cell_size * 1.5), _cell_size * 5.0, Color(1, 1, 1), 0.7, true)

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

## The full band the controller handed us (HUD-bottom → tray-top). The
## decorative board panel fills this; the honeycomb is centred inside it, so
## a width-bound board reads as a big framed playfield instead of a small
## grid marooned in empty space.
var _band_rect: Rect2 = Rect2(0, 0, 1080, 1500)

func _fit_layout(viewport_rect: Rect2, width: int, height: int) -> void:
	_band_rect = viewport_rect
	var margin_x := 14.0
	var margin_y := 24.0
	var avail := viewport_rect.size - Vector2(margin_x * 2.0, margin_y * 2.0)
	var span_x := float(width) + 0.5
	var span_y := float(height - 1) * HEX_ROW + 1.0
	# Portrait boards are almost always width-constrained; cap the cell so a
	# short-but-wide board can't inflate into cartoonish tiles.
	_cell_size = min(avail.x / span_x, avail.y / span_y, 168.0)
	var grid_size := Vector2(_cell_size * span_x, _cell_size * span_y)
	# Centred inside the band; the panel drawn in _draw() fills the rest.
	_origin.x = viewport_rect.position.x + (viewport_rect.size.x - grid_size.x) * 0.5
	var slack_y: float = maxf(viewport_rect.size.y - grid_size.y, 0.0)
	_origin.y = viewport_rect.position.y + slack_y * 0.5

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
			node.configure(cell.color_id, cell.power_id, cell.obstacle_id, cell.obstacle_hp, _cell_size, palette, cell.special_id)

func _draw() -> void:
	if board == null:
		return
	var pad := _cell_size * 0.5
	var grid := _grid_px()

	var r := _cell_size * 0.5

	# The decorative panel hugs the honeycomb (generous padding), then is
	# centred in the band by _fit_layout. A width-bound 9-wide board leaves
	# symmetric breathing room top & bottom — the animated backdrop shows
	# through it, which reads as intentional space, not a dead gap.
	var frame := Rect2(_origin - Vector2(pad, pad), grid + Vector2(pad, pad) * 2.0)
	var panel_r := minf(_cell_size * 0.6, 44.0)

	# soft outer glow behind the whole board — separates it from the backdrop
	for i in range(5, 0, -1):
		var t := float(i) / 5.0
		_draw_round_rect(frame.grow(6.0 + t * 22.0), panel_r + t * 16.0,
			Color(VisualTheme.ACCENT.r, VisualTheme.ACCENT.g, VisualTheme.ACCENT.b, 0.05 * (1.0 - t)))
	# drop shadow
	_draw_round_rect(Rect2(frame.position + Vector2(0, 12), frame.size), panel_r, Color(0, 0, 0, 0.45))

	# Fever aura
	if fever_active:
		var fpulse := 0.5 + 0.5 * sin(_fever_phase * 7.0)
		for i in 5:
			var t := float(i) / 4.0
			var col := VisualTheme.FEVER.lerp(VisualTheme.FEVER_HOT, fpulse)
			col.a = (0.30 - 0.05 * float(i)) * (0.6 + 0.4 * fpulse)
			_draw_round_rect(frame.grow(6.0 + t * 28.0 + fpulse * 12.0), panel_r + t * 22.0, col)

	# frame body: raised bevel — lighter top band, darker base
	_draw_round_rect(frame, panel_r, VisualTheme.PANEL_RAISED.darkened(0.12))
	_draw_round_rect(Rect2(frame.position, Vector2(frame.size.x, frame.size.y * 0.5)), panel_r,
		VisualTheme.PANEL_RAISED.lightened(0.10))
	_draw_round_rect(frame.grow(-4.0), panel_r - 2.0, VisualTheme.PANEL_SOLID)

	# accent / fever rim
	var rim_col := Color(VisualTheme.ACCENT.r, VisualTheme.ACCENT.g, VisualTheme.ACCENT.b, 0.28)
	if fever_active:
		rim_col = VisualTheme.FEVER_HOT
		rim_col.a = 0.55 + 0.35 * sin(_fever_phase * 9.0)
	_draw_round_rect_outline(frame.grow(-3.0), panel_r, rim_col, 2.5)

	# inner well with an inset shadow band across the top
	var well := Rect2(_origin - Vector2(pad * 0.5, pad * 0.5), grid + Vector2(pad * 0.5, pad * 0.5) * 2.0)
	_draw_round_rect(well, _cell_size * 0.44, VisualTheme.WELL)
	_draw_round_rect(Rect2(well.position, Vector2(well.size.x, _cell_size * 0.5)), _cell_size * 0.44,
		Color(0, 0, 0, 0.3))

	# per-cell sockets — each jewel drops into a defined recessed cup so the
	# honeycomb reads as separated pieces seated in the frame, not a mosaic:
	# a soft cast pool, a dark inset disc a touch wider than the jewel, a
	# crisp dark rim, a shaded upper inner wall and a lit lower lip.
	var socket_glow := 0.0
	if fever_active:
		socket_glow = 0.05 + 0.05 * sin(_fever_phase * 6.0)
	var s := _cell_size * 0.52
	var rim_w := maxf(_cell_size * 0.035, 2.0)
	for x in board.width:
		for y in board.height:
			var c := _slot_center(Vector2i(x, y))
			# cast pool below
			draw_circle(c + Vector2(0, _cell_size * 0.05), s * 1.02, Color(0.0, 0.0, 0.02, 0.5))
			# recessed cup
			draw_circle(c, s, Color(0.045, 0.06, 0.11, 0.92))
			# upper inner wall in shadow, lower lip catching light
			draw_arc(c, s * 0.9, PI * 0.9, TAU + PI * 0.1, 16, Color(0, 0, 0, 0.55), rim_w * 1.3, true)
			draw_arc(c, s * 0.88, PI * 0.08, PI * 0.92, 14, Color(0.5, 0.62, 0.95, 0.10), rim_w, true)
			# crisp outer rim
			draw_arc(c, s, 0.0, TAU, 24, Color(0, 0, 0, 0.6), rim_w, true)
			if socket_glow > 0.0:
				draw_circle(c, s * 1.08, Color(VisualTheme.FEVER_HOT.r, VisualTheme.FEVER_HOT.g, VisualTheme.FEVER_HOT.b, socket_glow))

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
	# Controlled feedback: a soft rising chime only at connection MILESTONES
	# (3 = it's now a valid match, then every 2 after) — not a tick on every
	# single cell. The pitch climbs with the milestone so a long connection
	# builds a little arpeggio instead of a machine-gun rattle.
	var n := _current_path.size()
	if n >= 3 and n % 2 == 1:
		Audio.play(&"select", clampf(float(n - 3) / 8.0, 0.0, 1.0), (n - 3) / 2)

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
			var n := _node_at(Vector2i(x, y))
			n.set_selected(false)
			if n.scale != Vector2.ONE and not _locked_input:
				n.scale = Vector2.ONE
	var pts := PackedVector2Array()
	for i in _current_path.size():
		var pos: Vector2i = _current_path[i]
		var node := _node_at(pos)
		node.set_selected(true)
		# the freshest node in the chain lifts a little more — a live "picked
		# up" feel that escalates as the connection grows.
		node.scale = Vector2.ONE * (1.16 if i == _current_path.size() - 1 else 1.08)
		pts.append(_slot_center(pos))
	if not _current_path.is_empty():
		var target := board.get_path_target_color(_current_path)
		_path_color = Color(1, 1, 1)
		if target != BoardModel.RAINBOW_COLOR_ID and palette != null and palette.has(target):
			_path_color = palette.get_def(target).glow_color
	_path_line.points = pts
	_path_glow.points = pts
	if _path_head != null:
		_path_head.visible = pts.size() >= 1 and _path_head.texture != null
		if _path_head.visible:
			_path_head.position = pts[pts.size() - 1]
			var hc := VisualTheme.FEVER_HOT if fever_active else _path_color
			_path_head.modulate = Color(hc.r, hc.g, hc.b, 0.95)
			var hs := _cell_size * (1.15 if fever_active else 0.95) / float(maxi(_path_head.texture.get_width(), _path_head.texture.get_height()))
			_path_head.scale = Vector2(hs, hs)
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

const _POW_FX_TINT := {
	&"bomb": Color(1.0, 0.42, 0.2), &"lightning": Color(0.7, 0.92, 1.0),
	&"freeze": Color(0.7, 0.95, 1.0), &"chain": Color(0.5, 1.0, 0.7),
	&"rainbow": Color(1.0, 0.8, 1.0),
}

## Signature per-power activation spectacle, layered on top of the generic
## wave burst. Bomb throws a shockwave + debris + hard shake; Lightning
## whips an actual jagged bolt down the cleared row/column; Freeze pushes a
## cyan ring of frost outward; Chain fires an energy streak from the last
## wave to this one; Rainbow blooms a prismatic radial burst. `combo` (a
## power+power move) scales everything up.
func _play_power_wave_fx(power_id: StringName, power_pos: Vector2i, cells: Array, wave_index: int, combo: bool) -> void:
	var origin := _slot_center(power_pos)
	var tint: Color = _POW_FX_TINT.get(power_id, Color(1, 1, 1))
	var amp := 1.0
	if combo:
		amp = 1.7
	if fever_active:
		amp *= 1.3

	match power_id:
		&"bomb":
			sfx.play(&"vfx_explosion_core", to_global(origin), _cell_size * (3.2 + 0.7 * wave_index) * amp, Color(1, 1, 1), 0.4)
			if combo or fever_active:
				sfx.play(&"vfx_fire_burst", to_global(origin), _cell_size * 3.6 * amp, Color(1, 1, 1), 0.45, true, 0.8)
			sfx.play_hold(&"vfx_shockwave_ring", to_global(origin), _cell_size * (4.6 + 1.1 * wave_index) * amp, tint, 0.5)
			sfx.play(&"vfx_debris_pieces", to_global(origin), _cell_size * 3.0 * amp, Color(1, 1, 1), 0.6, false, 2.4, 1.5)
			particles.flash(to_global(origin), Color(1, 1, 1), _cell_size * 1.6 * amp)
			for i in int(10 * amp):
				var a := TAU * float(i) / float(int(10 * amp))
				particles.burst(to_global(origin + Vector2(cos(a), sin(a)) * _cell_size * 0.4),
					Color(0.2, 0.18, 0.18) if i % 2 == 0 else tint, 5)
			ScreenShake.apply(self, (8.0 + 2.0 * wave_index) * amp, 0.3)
			Haptics.strong(int(70 * amp))
			# nearby tiles recoil from the blast
			for n in board.get_orthogonal_neighbors(power_pos):
				var node := _node_at(n)
				if node != null and board.get_cell(n) != null and not board.get_cell(n).is_empty():
					var dir := (_slot_center(n) - origin).normalized()
					var kt := create_tween()
					kt.tween_property(node, "position", _slot_center(n) + dir * _cell_size * 0.16, 0.06).set_trans(Tween.TRANS_QUAD)
					kt.tween_property(node, "position", _slot_center(n), 0.22).set_trans(Tween.TRANS_ELASTIC)
		&"lightning":
			# derive the struck axis from the cleared cells
			var horizontal := _cells_are_horizontal(cells)
			var a := origin
			var b := origin
			if horizontal:
				a = _slot_center(Vector2i(0, power_pos.y)) - Vector2(_cell_size, 0)
				b = _slot_center(Vector2i(board.width - 1, power_pos.y)) + Vector2(_cell_size, 0)
			else:
				a = _slot_center(Vector2i(power_pos.x, 0)) - Vector2(0, _cell_size)
				b = _slot_center(Vector2i(power_pos.x, board.height - 1)) + Vector2(0, _cell_size)
			_spawn_bolt(a, b, tint, 0.26)
			sfx.play(&"vfx_lightning_arc", to_global(origin), _cell_size * 2.8 * amp, tint, 0.3)
			particles.flash(to_global(origin), Color(1, 1, 1), _cell_size * 2.2 * amp)
			for pos in cells:
				particles.burst(_to_world(pos), Color(0.8, 0.95, 1.0), int(6 * amp))
			ScreenShake.apply(self, 5.0 * amp, 0.18)
			Haptics.strong(int(50 * amp))
		&"freeze":
			sfx.play(&"vfx_ice_burst", to_global(origin), _cell_size * 3.2 * amp, Color(1, 1, 1), 0.42)
			particles.flash(to_global(origin), tint, _cell_size * 3.0 * amp)
			for ring_i in 3:
				var rr := _cell_size * (0.8 + ring_i * 0.9)
				for i in 10:
					var a2 := TAU * float(i) / 10.0
					particles.burst(to_global(origin + Vector2(cos(a2), sin(a2)) * rr), Color(0.85, 0.97, 1.0), 3)
			Haptics.medium()
		&"chain":
			if _last_wave_center != Vector2.ZERO:
				_spawn_bolt(_last_wave_center, origin, tint, 0.2)
			sfx.play(&"vfx_chain_energy_burst", to_global(origin), _cell_size * (2.4 + 0.6 * wave_index) * amp, tint, 0.38)
			particles.flash(to_global(origin), tint, _cell_size * (1.8 + 0.5 * wave_index) * amp)
			for pos in cells:
				particles.burst(_to_world(pos), tint, int((5 + wave_index) * amp))
			Haptics.light()
		&"rainbow":
			sfx.play(&"vfx_rainbow_burst", to_global(origin), _cell_size * 4.0 * amp, Color(1, 1, 1), 0.46, true, 1.2)
			for i in int(18 * amp):
				var a3 := TAU * float(i) / float(int(18 * amp))
				var col: Color = PieceView._SPECTRUM[i % PieceView._SPECTRUM.size()]
				particles.burst(to_global(origin + Vector2(cos(a3), sin(a3)) * _cell_size * 0.5), col, 4)
			particles.flash(to_global(origin), Color(1, 0.9, 1.0), _cell_size * 4.0 * amp)
			# flare each target tile just before it pops
			for pos in cells:
				var node := _node_at(pos)
				if node != null:
					node.scale = Vector2(1.25, 1.25)
			ScreenShake.apply(self, 4.0 * amp, 0.2)
			Haptics.medium()

	if cells.size() > 0:
		var sum := Vector2.ZERO
		for pos in cells:
			sum += _slot_center(pos)
		_last_wave_center = sum / float(cells.size())

var _last_wave_center := Vector2.ZERO

func _to_world(pos: Vector2i) -> Vector2:
	return to_global(_slot_center(pos))

func _cells_are_horizontal(cells: Array) -> bool:
	if cells.size() < 2:
		return true
	var min_x := 999
	var max_x := -999
	var min_y := 999
	var max_y := -999
	for p in cells:
		min_x = mini(min_x, p.x); max_x = maxi(max_x, p.x)
		min_y = mini(min_y, p.y); max_y = maxi(max_y, p.y)
	return (max_x - min_x) >= (max_y - min_y)

## A transient jagged lightning/energy line drawn in board-local space that
## flashes bright then fades and frees itself. Cheap: one Line2D, one tween.
func _spawn_bolt(from: Vector2, to: Vector2, color: Color, life: float) -> void:
	var bolt := Line2D.new()
	bolt.z_index = 55
	bolt.width = _cell_size * 0.16
	bolt.default_color = Color(color.r, color.g, color.b, 0.95)
	bolt.begin_cap_mode = Line2D.LINE_CAP_ROUND
	bolt.end_cap_mode = Line2D.LINE_CAP_ROUND
	bolt.joint_mode = Line2D.LINE_JOINT_ROUND
	bolt.antialiased = true
	var seg := 10
	var dir := (to - from)
	var perp := Vector2(-dir.y, dir.x).normalized()
	var pts := PackedVector2Array()
	for i in seg + 1:
		var f := float(i) / float(seg)
		var j := 0.0 if (i == 0 or i == seg) else rng.randf_range(-1.0, 1.0) * _cell_size * 0.35
		pts.append(from.lerp(to, f) + perp * j)
	bolt.points = pts
	# bright white core underlay
	var core := Line2D.new()
	core.z_index = 56
	core.width = _cell_size * 0.06
	core.default_color = Color(1, 1, 1, 0.95)
	core.points = pts
	core.begin_cap_mode = Line2D.LINE_CAP_ROUND
	core.end_cap_mode = Line2D.LINE_CAP_ROUND
	add_child(bolt)
	add_child(core)
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(bolt, "modulate:a", 0.0, life).set_trans(Tween.TRANS_QUAD)
	t.tween_property(core, "modulate:a", 0.0, life).set_trans(Tween.TRANS_QUAD)
	t.chain().tween_callback(func():
		bolt.queue_free()
		core.queue_free()
	)

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

## The two distinct power ids that detonated this move (order-stable — first
## two distinct ids seen in `powers_activated`). Falls back to duplicating
## the one power found if, unusually, every activation this move was the
## same id detonating more than twice (still a valid same-power combo, e.g.
## three Bombs — reads as "bomb+bomb").
static func _combo_pair(powers_activated: Array) -> Array[StringName]:
	var pair: Array[StringName] = []
	for p in powers_activated:
		var pid: StringName = p["power_id"]
		if not pair.has(pid):
			pair.append(pid)
		if pair.size() >= 2:
			break
	if pair.is_empty():
		pair.append(&"bomb")
	if pair.size() < 2:
		pair.append(pair[0])
	return pair

func _combo_tint(a: StringName, b: StringName) -> Color:
	var ca: Color = _POW_FX_TINT.get(a, VisualTheme.ACCENT_HOT)
	var cb: Color = _POW_FX_TINT.get(b, VisualTheme.ACCENT_HOT)
	return ca.lerp(cb, 0.5)

func _combo_label(a: StringName, b: StringName) -> String:
	var pair := [String(a), String(b)]
	pair.sort()
	var key := "%s+%s" % [pair[0], pair[1]]
	return String(GameData.power_combo_labels.get(key, "POWER COMBO!"))

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

## Awaits a tween's completion ONLY while it is still actually running.
## A short tween created before an intervening `await` (e.g. a create_timer
## yield) can finish inside that yield; `await <done tween>.finished` then
## waits on a signal that will never fire again, parking the caller's
## coroutine forever (this is what left `_play_move()` stuck and the board
## silently unresponsive on lower-FPS devices during a cascade).
func _await_tween(t: Tween) -> void:
	if t != null and t.is_valid() and t.is_running():
		await t.finished

func _animate_result(result: ChainResolver.MoveResult, group_size: int = 0) -> void:
	var chain_depth := result.chain_depth
	var animated: Dictionary = {}
	var pop_tweens: Array[Tween] = []
	_last_wave_center = Vector2.ZERO

	# POWER + POWER: two or more power detonations in one resolve is a combo —
	# every per-wave effect is amplified and it gets its own screen-wide beat.
	var combo_powers := result.powers_activated.size()
	var is_combo := combo_powers >= 2
	if is_combo:
		var cc := _board_rect_center()
		# 2026-09-05: a combo is no longer just "everything amplified" — its
		# identity (name, color, and the actual two power sounds layered) is
		# derived from WHICH powers detonated together, so bomb+bomb reads
		# differently from lightning+lightning or bomb+lightning instead of
		# all three just being a bigger generic blast.
		var pair := _combo_pair(result.powers_activated)
		var combo_tint := _combo_tint(pair[0], pair[1])
		var combo_label := _combo_label(pair[0], pair[1])
		sfx.play(_power_sfx_id(pair[0]), to_global(cc), _cell_size * 4.2, combo_tint, 0.5, true, 1.6)
		sfx.play(_power_sfx_id(pair[1]), to_global(cc), _cell_size * 3.6, combo_tint, 0.42, true, 1.3)
		sfx.play_hold(&"vfx_shockwave_ring", to_global(cc), _cell_size * 9.0, combo_tint, 0.55)
		particles.flash(to_global(cc), Color(1, 1, 1), _cell_size * 7.0)
		particles.flash(to_global(cc), combo_tint, _cell_size * 9.5)
		ScreenShake.apply(self, 10.0 + float(combo_powers) * 2.0, 0.34)
		Haptics.strong(90)
		Audio.play(&"combo_ding", 0.0, 2)
		ComboPopup.spawn(self, cc - Vector2(0, _cell_size * 1.4), combo_label,
			combo_tint, 52, "x%d BLAST" % combo_powers)

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
			_play_power_wave_fx(power_id, power_pos, cells, wave_index, is_combo)
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
				if not is_power:
					sfx.play(&"vfx_energy_burst", to_global(wave_center), flash_r * 2.4 * (1.3 if fever_active else 1.0), flash_col, 0.34)
			if is_power:
				ScreenShake.apply(self, 4.0 + float(wave_hits) * 0.5, 0.2)
				Haptics.light()

		if wave_index < result.wave_cells.size() - 1:
			await get_tree().create_timer(_WAVE_STAGGER * _cascade_scale).timeout

	if not pop_tweens.is_empty():
		await _await_tween(pop_tweens[pop_tweens.size() - 1])
	for pos in animated.keys():
		var node := _node_at(pos)
		if node == null:
			continue
		node.scale = Vector2.ONE
		var _bc := board.get_cell(pos)
		node.configure(CellData.COLOR_EMPTY, CellData.POWER_NONE, node.obstacle_id, node.obstacle_hp, _cell_size, palette,
			_bc.special_id if _bc != null else CellData.SPECIAL_NONE)

	# shattered obstacles: one shard burst + one controlled break sound for
	# the move (not one per obstacle), flavoured by the family that broke.
	if not result.obstacles_broken.is_empty():
		var ob0: Dictionary = result.obstacles_broken[0]
		var opos: Vector2i = ob0.get("pos", Vector2i.ZERO)
		sfx.play(&"vfx_crystal_shards", to_global(_slot_center(opos)), _cell_size * 2.4, Color(1, 1, 1), 0.5, false, 1.6, 1.7)
		var fam := CellData.family_of(StringName(String(ob0.get("obstacle_id", "ice"))))
		var fam_map := {&"ice": 0, &"stone": 1, &"lock": 2, &"timebomb": 3}
		var fam_idx: int = fam_map.get(fam, 0)
		Audio.play(&"blocker_break", clampf(float(result.obstacles_broken.size()) / 4.0, 0.0, 1.0), fam_idx)

	if chain_depth >= 3:
		ScreenShake.apply(self, 6.0 + float(chain_depth), 0.28)
		Haptics.medium()
	elif chain_depth > 1:
		Haptics.light()

	var ghosts: Array[PieceView] = []
	var fly_tween: Tween = null
	for move in result.gravity_moves:
		if move.get("delivered", false):
			_animate_special_delivery(move["from"])
			continue
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
		await _await_tween(fly_tween)
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
		sfx.play(&"vfx_glow_orb", node.global_position, _cell_size * 2.6, tint, 0.42, true)
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
		await _await_tween(last_tween)

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
	sfx.play(&"vfx_ice_burst", _node_at(frozen[0]).global_position, _cell_size * 2.6, Color(1, 1, 1), 0.4)
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

## Boss stage "counter-attack" pressure mechanic (driven by app.gd, not the
## board itself): obstructs one live, unobstructed, powerless cell with an
## obstacle — reusing the exact same obstacle plumbing a level-authored
## obstacle uses (an `ice`-family id here: any clear/blast damages it), just
## placed mid-fight. Never strands the player: if a candidate cell would
## leave zero valid moves anywhere on the board, that placement is reverted
## and another cell is tried. Returns false (no-op) if no safe cell exists.
func boss_obstruct_random_cell(obstacle_id: StringName, hp: int) -> bool:
	if board == null:
		return false
	var candidates: Array[Vector2i] = []
	for x in board.width:
		for y in board.height:
			var pos := Vector2i(x, y)
			var cell := board.get_cell(pos)
			if cell != null and cell.is_selectable() and not cell.has_obstacle() and not cell.has_power():
				candidates.append(pos)
	while not candidates.is_empty():
		var idx := rng.randi_range(0, candidates.size() - 1)
		var pos: Vector2i = candidates[idx]
		candidates.remove_at(idx)
		var cell := board.get_cell(pos)
		var prev_id := cell.obstacle_id
		var prev_hp := cell.obstacle_hp
		board.set_obstacle(pos, obstacle_id, hp)
		if board.has_any_valid_move():
			var node := _node_at(pos)
			if node != null:
				node.configure(cell.color_id, cell.power_id, cell.obstacle_id, cell.obstacle_hp, _cell_size, palette)
			particles.flash(to_global(_slot_center(pos)), Color(0.6, 0.15, 0.75), _cell_size * 1.6)
			return true
		cell.obstacle_id = prev_id
		cell.obstacle_hp = prev_hp
	return false

func _spawn_ghost(cell: CellData, pos: Vector2) -> PieceView:
	var ghost := PieceView.new()
	ghost.configure(cell.color_id, cell.power_id, CellData.OBSTACLE_NONE, 0, _cell_size, palette, cell.special_id)
	ghost.position = pos
	add_child(ghost)
	return ghost

## The Love Crystal reached the bottom row — drop it out of the board with a
## bright rescue flourish. `bottom_pos` is the bottom-row cell it left from.
func _animate_special_delivery(bottom_pos: Vector2i) -> void:
	var start := _slot_center(bottom_pos)
	var ghost := PieceView.new()
	ghost.configure(CellData.COLOR_EMPTY, CellData.POWER_NONE, CellData.OBSTACLE_NONE, 0, _cell_size, palette, &"relic")
	ghost.position = start
	ghost.z_index = 60
	add_child(ghost)
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(ghost, "position:y", start.y + _cell_size * 2.2, 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(ghost, "scale", Vector2(1.3, 1.3), 0.16).set_trans(Tween.TRANS_BACK)
	t.chain().tween_property(ghost, "modulate:a", 0.0, 0.26)
	t.chain().tween_callback(ghost.queue_free)
	Audio.play(&"special_deliver", 0.0, 0)
	Haptics.medium()
	particles.flash(to_global(start), Color(1.0, 0.55, 0.72), _cell_size * 4.0)
	ScreenShake.apply(self, 5.0, 0.22)
	ComboPopup.spawn(self, start - Vector2(0, _cell_size * 1.1), "SAVED!", Color(1.0, 0.6, 0.78), 46, "LOVE CRYSTAL")

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
