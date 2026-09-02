class_name LevelMap
extends Control
## Campaign level-select: a scrollable serpentine trail of level nodes over a
## stylised "puzzle world" — layered glowing ridges, a hero light, drifting
## hex-gem islands and fireflies — with locked / unlocked / current /
## completed state, star ratings and periodic chest beats. Built entirely in
## code (no scene, no art assets). Safe-area aware; tracks the viewport size
## rather than trusting anchor-preset fill under a CanvasLayer.
##
## Progression / unlock / star logic is untouched — it all still comes from
## ProgressService via refresh().

signal level_selected(level_id: int)
signal home_pressed()

const _TOP_MARGIN := 170.0
const _BOTTOM_MARGIN := 220.0
const _NODE_SPACING_Y := 200.0
const _CHEST_EVERY := 5

var _header: PanelContainer
var _header_inner: MarginContainer
var _home_btn: Button
var _coins_label: Label
var _gems_label: Label
var _stars_label: Label
var _scroll: ScrollContainer
var _canvas: Control
var _env: MapEnvironment
var _path_canvas: LevelPathCanvas
var _node_buttons: Dictionary = {}
var _node_positions: Dictionary = {}
var _deco: Array = []      # [{node: TextureRect, id: StringName}] trail decorations
var _header_h := 132.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_env = MapEnvironment.new()
	_env.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_env)
	_build_scroll_area()
	_build_header()
	_relayout()
	get_viewport().size_changed.connect(_relayout)
	refresh()
	call_deferred("_scroll_to_current")

func _relayout() -> void:
	var vp := get_viewport_rect().size
	size = vp
	custom_minimum_size = vp
	_env.size = vp
	var si := VisualTheme.safe_insets(self)
	_header_h = si.position.y + 120.0
	_scroll.position = Vector2(0, _header_h)
	_scroll.size = Vector2(vp.x, vp.y - _header_h)
	_header.size = Vector2(vp.x, _header_h)
	_header.position = Vector2.ZERO
	_header_inner.add_theme_constant_override("margin_top", int(si.position.y + 14.0))
	_home_btn.position = Vector2(20, si.position.y + 16.0)
	_env.gesture_inset = si.size.y
	_layout_nodes(vp.x)

func _build_header() -> void:
	_header = PanelContainer.new()
	var hsb := VisualTheme.panel(Color(0.05, 0.06, 0.12, 0.92), 0, Color(0, 0, 0, 0), 0)
	hsb.shadow_size = 20
	hsb.shadow_offset = Vector2(0, 6)
	_header.add_theme_stylebox_override("panel", hsb)
	add_child(_header)

	_header_inner = MarginContainer.new()
	_header_inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	_header.add_child(_header_inner)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 8)
	_header_inner.add_child(vbox)

	var logo := WordmarkLabel.new()
	logo.custom_minimum_size = Vector2(0, 46)
	vbox.add_child(logo)

	var currency := HBoxContainer.new()
	currency.alignment = BoxContainer.ALIGNMENT_CENTER
	currency.add_theme_constant_override("separation", 16)
	vbox.add_child(currency)
	_coins_label = _currency_pill(currency, &"coin", VisualTheme.TEXT_GOLD)
	_gems_label = _currency_pill(currency, &"crystal", Color(0.8, 0.7, 1.0))
	_stars_label = _currency_pill(currency, &"trophy", VisualTheme.STAR)

	_home_btn = Button.new()
	_home_btn.text = "‹ HOME"
	_home_btn.add_theme_font_size_override("font_size", VisualTheme.FS_MICRO)
	_home_btn.add_theme_color_override("font_color", VisualTheme.TEXT)
	_home_btn.add_theme_stylebox_override("normal", VisualTheme.panel(VisualTheme.PANEL_RAISED, 16, VisualTheme.PANEL_BORDER, 1))
	_home_btn.add_theme_stylebox_override("hover", VisualTheme.panel(VisualTheme.PANEL_RAISED.lightened(0.1), 16))
	_home_btn.add_theme_stylebox_override("pressed", VisualTheme.panel(VisualTheme.PANEL_SOLID, 16))
	_home_btn.focus_mode = Control.FOCUS_NONE
	_home_btn.pressed.connect(func():
		Audio.play(&"button_tap")
		home_pressed.emit()
	)
	_home_btn.z_index = 5
	add_child(_home_btn)

func _currency_pill(parent: Control, kind: StringName, text_color: Color) -> Label:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", VisualTheme.panel(VisualTheme.PANEL, 18, VisualTheme.PANEL_BORDER, 2))
	parent.add_child(pc)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	pc.add_child(row)
	var icon := HUD.GemIcon.new()
	icon.kind = kind
	icon.tint = VisualTheme.GEM
	icon.custom_minimum_size = Vector2(24, 24)
	row.add_child(icon)
	var lbl := VisualTheme.label("0", VisualTheme.FS_LABEL, text_color)
	row.add_child(lbl)
	return lbl

func _build_scroll_area() -> void:
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.clip_contents = true
	add_child(_scroll)

	var count: int = max(GameData.levels.count(), 1)
	var canvas_height := _TOP_MARGIN + _NODE_SPACING_Y * float(count - 1) + _BOTTOM_MARGIN

	_canvas = Control.new()
	_canvas.custom_minimum_size = Vector2(0, canvas_height)
	_scroll.add_child(_canvas)

	# Prepared trail decorations (drawn behind the path + nodes): a World
	# Landmark vista at the summit, a Destination Structure at the final node,
	# a Map Gate every 10 levels and a Portal beside each chest milestone.
	_build_decorations()

	_path_canvas = LevelPathCanvas.new()
	_path_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_path_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_path_canvas)

	for level_id in GameData.levels.ordered_ids:
		var btn := LevelNodeButton.new()
		btn.pressed.connect(_on_node_pressed.bind(level_id))
		_canvas.add_child(btn)
		_node_buttons[level_id] = btn

func _deco_rect(id: StringName, sz: Vector2, alpha := 1.0, cover := false) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = AssetLibrary.tex(id)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED if cover else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = sz
	tr.size = sz
	tr.modulate = Color(1, 1, 1, alpha)
	tr.clip_contents = true
	tr.visible = tr.texture != null
	_canvas.add_child(tr)
	_deco.append({"node": tr, "id": id})
	return tr

func _build_decorations() -> void:
	_deco.clear()
	var w := 1080.0
	_deco_rect(&"env_world_landmark", Vector2(w, 480), 0.55, true)   # summit vista
	_deco_rect(&"map_destination_structure", Vector2(210, 210))       # final node
	var count: int = max(GameData.levels.count(), 1)
	for i in range(9, count, 10):                                    # gate every 10 levels
		_deco_rect(&"map_gate", Vector2(160, 160))
	for i in range(4, count, _CHEST_EVERY):                          # portal by each chest
		_deco_rect(&"map_portal", Vector2(140, 140))

func _layout_nodes(width: float) -> void:
	if width <= 0.0:
		width = 1080.0
	_canvas.custom_minimum_size.x = width
	var amp: float = min(width * 0.27, 250.0)
	var index := 0
	for level_id in GameData.levels.ordered_ids:
		var center := Vector2(
			width * 0.5 + amp * sin(float(index) * 0.9),
			_TOP_MARGIN + _NODE_SPACING_Y * float(index)
		)
		_node_positions[level_id] = center
		var btn: LevelNodeButton = _node_buttons[level_id]
		btn.position = center - btn.custom_minimum_size * 0.5
		index += 1
	_layout_decorations(width)
	_rebuild_path()

func _layout_decorations(width: float) -> void:
	if _deco.is_empty():
		return
	var ids: Array[int] = GameData.levels.ordered_ids
	var last_pos: Vector2 = _node_positions.get(ids[ids.size() - 1], Vector2(width * 0.5, _TOP_MARGIN))
	var gi := 0
	var pi := 0
	for entry in _deco:
		var tr: TextureRect = entry["node"]
		var sz: Vector2 = tr.custom_minimum_size
		var p := Vector2(width * 0.5, _TOP_MARGIN)
		match entry["id"]:
			&"env_world_landmark":
				p = Vector2(width * 0.5, _TOP_MARGIN * 0.30)
			&"map_destination_structure":
				p = last_pos + Vector2(0, -6)
			&"map_gate":
				var idx := 9 + gi * 10
				gi += 1
				if idx + 1 < ids.size() and _node_positions.has(ids[idx]) and _node_positions.has(ids[idx + 1]):
					p = (_node_positions[ids[idx]] + _node_positions[ids[idx + 1]]) * 0.5
			&"map_portal":
				var idx2 := 4 + pi * _CHEST_EVERY
				pi += 1
				if idx2 < ids.size() and _node_positions.has(ids[idx2]):
					p = _node_positions[ids[idx2]] + Vector2(0, 4)
		tr.position = p - sz * 0.5

func _rebuild_path() -> void:
	var segments: Array = []
	var ids: Array[int] = GameData.levels.ordered_ids
	for i in range(1, ids.size()):
		if not _node_positions.has(ids[i]):
			continue
		segments.append({
			"from": _node_positions[ids[i - 1]],
			"to": _node_positions[ids[i]],
			"lit": Progress.is_unlocked(ids[i]),
		})
	_path_canvas.set_segments(segments)

## Re-reads Progress for every node — call whenever the map becomes visible.
func refresh() -> void:
	_coins_label.text = str(Economy.coins)
	_gems_label.text = str(SaveService.get_int("gems", 0))
	var total_stars := 0
	for lid in GameData.levels.ordered_ids:
		total_stars += Progress.get_stars(lid)
	if _stars_label != null:
		_stars_label.text = str(total_stars)
	var current_id := Progress.current_level_id()
	var idx := 0
	for level_id in GameData.levels.ordered_ids:
		var btn: LevelNodeButton = _node_buttons[level_id]
		var st: StringName
		if not Progress.is_unlocked(level_id):
			st = &"locked"
		elif Progress.is_completed(level_id):
			st = &"completed"
		elif level_id == current_id:
			st = &"current"
		else:
			st = &"unlocked"
		var is_chest := (idx + 1) % _CHEST_EVERY == 0
		btn.configure(level_id, st, Progress.get_stars(level_id), is_chest)
		if _node_positions.has(level_id):
			btn.position = _node_positions[level_id] - btn.custom_minimum_size * 0.5
		idx += 1
	_rebuild_path()

func _scroll_to_current() -> void:
	var current_id := Progress.current_level_id()
	if not _node_positions.has(current_id):
		return
	var target_y: float = _node_positions[current_id].y
	_scroll.scroll_vertical = int(max(target_y - _scroll.size.y * 0.5, 0.0))

func _on_node_pressed(level_id: int) -> void:
	Audio.play(&"button_tap")
	level_selected.emit(level_id)


## Stylised parallax "puzzle world" behind the trail: a deep gradient sky, a
## hero light, layered glowing ridge silhouettes, drifting hex-gem islands
## and fireflies. Original vector art, no textures, one CanvasItem.
class MapEnvironment extends Control:
	var _t := 0.0
	var gesture_inset := 0.0
	var _islands: Array = []

	const _HUES := [
		Color(0.95, 0.30, 0.42), Color(1.0, 0.62, 0.24), Color(1.0, 0.85, 0.30),
		Color(0.36, 0.82, 0.52), Color(0.34, 0.62, 1.0), Color(0.64, 0.40, 0.96),
	]

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		set_process(true)
		var rng := RandomNumberGenerator.new()
		rng.seed = 71042
		for i in 6:
			_islands.append({
				"x": rng.randf(), "y": rng.randf(),
				"r": rng.randf_range(30.0, 58.0),
				"spd": rng.randf_range(0.5, 1.0),
				"ph": rng.randf() * TAU,
				"hue": rng.randi_range(0, 5),
			})

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var s := size
		if s.x < 1.0:
			return

		var bg := AssetLibrary.tex(&"env_map_landmarks")
		if bg != null:
			# full-screen "world map" scene, cover-fit (aspect kept, centred),
			# with a slight downward parallax as the trail scrolls.
			var bw: float = float(bg.get_width())
			var bh: float = float(bg.get_height())
			var k: float = maxf(s.x / bw, s.y / bh)
			var dw := bw * k
			var dh := bh * k
			var dx := (s.x - dw) * 0.5
			var dy := (s.y - dh) * 0.5
			draw_texture_rect(bg, Rect2(dx, dy, dw, dh), false)
			# readability veil so the trail + node discs always pop, plus a
			# stronger gradient toward the bottom where the newest nodes sit
			draw_rect(Rect2(Vector2.ZERO, s), Color(0.05, 0.05, 0.12, 0.38))
			_v_grad(Rect2(0, s.y * 0.55, s.x, s.y * 0.45),
				Color(0.05, 0.05, 0.12, 0.0), Color(0.04, 0.04, 0.10, 0.22), Color(0.03, 0.03, 0.08, 0.45))
		else:
			# deep gradient sky, indigo crown -> plum floor
			_v_grad(Rect2(Vector2.ZERO, s),
				Color(0.11, 0.14, 0.30), Color(0.16, 0.11, 0.26), Color(0.05, 0.05, 0.12))
			var hero := Vector2(s.x * 0.74, s.y * 0.14)
			for k in range(6, 0, -1):
				var t := float(k) / 6.0
				draw_circle(hero, s.x * 0.5 * t, Color(0.6, 0.72, 1.0, 0.05 * (1.0 - t)))
			var ridges := [
				{"y": 0.34, "amp": 40.0, "col": Color(0.20, 0.24, 0.46), "rim": Color(0.42, 0.52, 0.9, 0.5)},
				{"y": 0.52, "amp": 56.0, "col": Color(0.24, 0.18, 0.40), "rim": Color(0.7, 0.42, 0.78, 0.5)},
				{"y": 0.72, "amp": 74.0, "col": Color(0.13, 0.12, 0.26), "rim": Color(0.36, 0.5, 0.85, 0.45)},
			]
			var k2 := 0
			for r in ridges:
				var pts := PackedVector2Array()
				var steps := 30
				for i in steps + 1:
					var x := s.x * float(i) / float(steps)
					var y: float = s.y * float(r["y"]) + sin(x * 0.006 + float(k2) * 1.9 + _t * 0.04) * float(r["amp"])
					pts.append(Vector2(x, y))
				var poly := pts.duplicate()
				poly.append(Vector2(s.x, s.y))
				poly.append(Vector2(0, s.y))
				draw_colored_polygon(poly, r["col"])
				draw_polyline(pts, r["rim"], 3.0, true)
				k2 += 1
			for isl in _islands:
				var iy: float = fposmod(isl["y"] - _t * 0.01 * isl["spd"], 1.1) - 0.05
				var p := Vector2(isl["x"] * s.x + sin(_t * 0.2 + isl["ph"]) * 26.0, iy * s.y)
				var col: Color = _HUES[isl["hue"]]
				var rr: float = isl["r"]
				for g in range(3, 0, -1):
					var gt := float(g) / 3.0
					draw_circle(p, rr * 1.5 * gt, Color(col.r, col.g, col.b, 0.05 * (1.0 - gt)))
				var hx := PackedVector2Array()
				for j in 6:
					var a := PI / 6.0 + TAU * float(j) / 6.0
					hx.append(p + Vector2(cos(a), sin(a)) * rr)
				draw_colored_polygon(hx, Color(col.r, col.g, col.b, 0.12))
				hx.append(hx[0])
				draw_polyline(hx, Color(col.r, col.g, col.b, 0.30), 2.0, true)
		# fireflies
		for i in 18:
			var fx: float = fposmod(float(i) * 97.0 + _t * 7.0, s.x)
			var fy: float = s.y * (0.25 + 0.55 * fposmod(float(i) * 0.137, 1.0)) + sin(_t + float(i)) * 12.0
			var tw: float = 0.5 + 0.5 * sin(_t * 2.0 + float(i))
			draw_circle(Vector2(fx, fy), 2.6, Color(0.95, 0.9, 0.7, 0.55 * tw))
		# bottom safety scrim so the last nodes never fight the gesture bar
		if gesture_inset > 0.0:
			draw_rect(Rect2(0, s.y - gesture_inset - 8.0, s.x, gesture_inset + 8.0), Color(0.05, 0.05, 0.12, 0.5))

	func _v_grad(rect: Rect2, top: Color, mid: Color, bottom: Color) -> void:
		var bands := 24
		var bh := rect.size.y / float(bands)
		for i in bands:
			var t := float(i) / float(bands - 1)
			var col := top.lerp(mid, t / 0.5) if t < 0.5 else mid.lerp(bottom, (t - 0.5) / 0.5)
			draw_rect(Rect2(rect.position + Vector2(0, bh * i), Vector2(rect.size.x, bh + 1.0)), col)


## "COLOR CLASH" wordmark, centred (delegates to VisualTheme.draw_wordmark).
class WordmarkLabel extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		VisualTheme.draw_wordmark(self, Vector2(size.x * 0.5, 40.0), 38.0, 1.0)
