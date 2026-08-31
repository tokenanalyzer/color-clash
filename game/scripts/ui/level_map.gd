class_name LevelMap
extends Control
## Campaign level-select: a scrollable serpentine trail of level nodes over
## a stylised environment, with locked / unlocked / current / completed
## state, star ratings and periodic chest beats. Built entirely in code (no
## scene, no art assets). Explicitly tracks the viewport size rather than
## trusting anchor-preset fill under a CanvasLayer.

signal level_selected(level_id: int)

const _TOP_MARGIN := 150.0
const _BOTTOM_MARGIN := 180.0
const _NODE_SPACING_Y := 190.0
const _CHEST_EVERY := 5

var _header: Control
var _coins_label: Label
var _gems_label: Label
var _scroll: ScrollContainer
var _canvas: Control
var _env: MapEnvironment
var _path_canvas: LevelPathCanvas
var _node_buttons: Dictionary = {}
var _node_positions: Dictionary = {}

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
	_scroll.position = Vector2(0, 132)
	_scroll.size = Vector2(vp.x, vp.y - 132)
	_layout_nodes(vp.x)
	_header.size = Vector2(vp.x, 132)

func _build_header() -> void:
	_header = PanelContainer.new()
	_header.add_theme_stylebox_override("panel", VisualTheme.panel(Color(0.06, 0.07, 0.13, 0.96), 0, Color(0, 0, 0, 0), 0))
	add_child(_header)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 8)
	_header.add_child(vbox)

	var logo := WordmarkLabel.new()
	logo.custom_minimum_size = Vector2(0, 52)
	vbox.add_child(logo)

	var currency := HBoxContainer.new()
	currency.alignment = BoxContainer.ALIGNMENT_CENTER
	currency.add_theme_constant_override("separation", 16)
	vbox.add_child(currency)
	_coins_label = _currency_pill(currency, &"coin", VisualTheme.TEXT_GOLD)
	_gems_label = _currency_pill(currency, &"gem", Color(0.8, 0.7, 1.0))

func _currency_pill(parent: Control, kind: StringName, text_color: Color) -> Label:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", VisualTheme.panel(VisualTheme.PANEL, 18, VisualTheme.PANEL_BORDER, 2))
	parent.add_child(pc)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	pc.add_child(row)
	var icon := HUD.GemIcon.new()
	icon.kind = kind
	icon.tint = VisualTheme.GEM
	icon.custom_minimum_size = Vector2(20, 20)
	row.add_child(icon)
	var lbl := VisualTheme.label("0", 20, text_color)
	row.add_child(lbl)
	return lbl

func _build_scroll_area() -> void:
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)

	var count: int = max(GameData.levels.count(), 1)
	var canvas_height := _TOP_MARGIN + _NODE_SPACING_Y * float(count - 1) + _BOTTOM_MARGIN

	_canvas = Control.new()
	_canvas.custom_minimum_size = Vector2(0, canvas_height)
	_scroll.add_child(_canvas)

	_path_canvas = LevelPathCanvas.new()
	_path_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_path_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_path_canvas)

	for level_id in GameData.levels.ordered_ids:
		var btn := LevelNodeButton.new()
		btn.pressed.connect(_on_node_pressed.bind(level_id))
		_canvas.add_child(btn)
		_node_buttons[level_id] = btn

func _layout_nodes(width: float) -> void:
	if width <= 0.0:
		width = 1080.0
	_canvas.custom_minimum_size.x = width
	var amp: float = min(width * 0.26, 230.0)
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
	_rebuild_path()

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


## Stylised parallax environment behind the trail: gradient sky, three
## rolling hill bands, drifting motes. Original vector art, no textures.
class MapEnvironment extends Control:
	var _t := 0.0

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		set_process(true)

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var s := size
		if s.x < 1.0:
			return
		VisualTheme.draw_v_gradient(self, Rect2(Vector2.ZERO, s),
			Color(0.10, 0.16, 0.28), Color(0.05, 0.08, 0.16), 18)
		VisualTheme.draw_glow(self, Vector2(s.x * 0.72, s.y * 0.12), s.x * 0.5,
			Color(0.5, 0.7, 1.0, 0.12), 5)
		# hill bands (far → near, brightening toward the foreground)
		var bands := [
			{"y": s.y * 0.40, "amp": 34.0, "col": Color(0.16, 0.34, 0.40), "rim": Color(0.30, 0.52, 0.55)},
			{"y": s.y * 0.56, "amp": 46.0, "col": Color(0.13, 0.30, 0.34), "rim": Color(0.24, 0.46, 0.48)},
			{"y": s.y * 0.74, "amp": 62.0, "col": Color(0.10, 0.24, 0.28), "rim": Color(0.20, 0.40, 0.42)},
		]
		var k := 0
		for band in bands:
			var top_pts := PackedVector2Array()
			var steps := 26
			for i in steps + 1:
				var x := s.x * float(i) / float(steps)
				var y: float = band["y"] + sin(x * 0.008 + float(k) * 1.7 + _t * 0.05) * band["amp"]
				top_pts.append(Vector2(x, y))
			var poly := top_pts.duplicate()
			poly.append(Vector2(s.x, s.y))
			poly.append(Vector2(0, s.y))
			draw_colored_polygon(poly, band["col"])
			draw_polyline(top_pts, band["rim"], 3.0, true)
			k += 1
		# fireflies
		for i in 14:
			var fx: float = fposmod(float(i) * 97.0 + _t * 8.0, s.x)
			var fy: float = s.y * (0.3 + 0.5 * fposmod(float(i) * 0.137, 1.0)) + sin(_t + float(i)) * 10.0
			var tw: float = 0.5 + 0.5 * sin(_t * 2.0 + float(i))
			draw_circle(Vector2(fx, fy), 2.5, Color(0.8, 1.0, 0.7, 0.5 * tw))


## "COLOR CLASH" wordmark — each letter individually tinted, drawn centred.
class WordmarkLabel extends Control:
	const _WORD := "COLOR CLASH"
	const _TINTS := [
		Color(1.0, 0.36, 0.42), Color(1.0, 0.66, 0.24), Color(1.0, 0.86, 0.28),
		Color(0.42, 0.82, 0.5), Color(0.36, 0.66, 1.0),
		Color(1, 1, 1),
		Color(0.62, 0.44, 0.95), Color(1.0, 0.42, 0.6), Color(0.36, 0.8, 0.86),
		Color(1.0, 0.72, 0.3), Color(0.5, 0.84, 0.56),
	]

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var fs := 40
		var total := font.get_string_size(_WORD, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var x := size.x * 0.5 - total * 0.5
		var y := 42.0
		for i in _WORD.length():
			var ch := _WORD[i]
			var tint: Color = _TINTS[i] if i < _TINTS.size() else Color.WHITE
			draw_string_outline(font, Vector2(x, y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.6))
			draw_string(font, Vector2(x, y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, tint)
			x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
