class_name LevelMap
extends Control
## Campaign level-select screen: a winding, scrollable path of level nodes
## showing locked/unlocked/current/completed state and star rating, built
## entirely in code (no hand-authored scene or art assets) to match
## BoardView/HUD's pattern and Color Clash's layered-gem visual language.

signal level_selected(level_id: int)

const _CANVAS_WIDTH := 1080.0
const _TOP_MARGIN := 110.0
const _BOTTOM_MARGIN := 140.0
const _NODE_SPACING_Y := 175.0
const _X_AMPLITUDE := 220.0

var _coins_label: Label
var _scroll: ScrollContainer
var _canvas: Control
var _path_canvas: LevelPathCanvas
var _node_buttons: Dictionary = {} # int -> LevelNodeButton
var _node_positions: Dictionary = {} # int -> Vector2 (center, in canvas space)

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_background()
	_build_header()
	_build_scroll_area()
	refresh()
	call_deferred("_scroll_to_current")

func _build_background() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.05, 0.055, 0.09)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

func _build_header() -> void:
	var header := PanelContainer.new()
	header.set_anchors_preset(Control.PRESET_TOP_WIDE)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.08, 0.13, 0.95)
	sb.content_margin_top = 18
	sb.content_margin_bottom = 14
	header.add_theme_stylebox_override("panel", sb)
	add_child(header)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 4)
	header.add_child(vbox)

	var title := Label.new()
	title.text = "COLOR CLASH"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	title.add_theme_constant_override("outline_size", 4)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Select a Level"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", Color(0.78, 0.84, 0.95))
	vbox.add_child(subtitle)

	_coins_label = Label.new()
	_coins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_coins_label.add_theme_font_size_override("font_size", 20)
	_coins_label.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	vbox.add_child(_coins_label)

	# reserve room below the fixed header for the scroll area
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 130)
	vbox.add_child(spacer)

func _build_scroll_area() -> void:
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.offset_top = 130
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)

	var count: int = max(GameData.levels.count(), 1)
	var canvas_height := _TOP_MARGIN + _NODE_SPACING_Y * float(count - 1) + _BOTTOM_MARGIN

	_canvas = Control.new()
	_canvas.custom_minimum_size = Vector2(_CANVAS_WIDTH, canvas_height)
	_scroll.add_child(_canvas)

	_path_canvas = LevelPathCanvas.new()
	_path_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_path_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_path_canvas)

	var index := 0
	for level_id in GameData.levels.ordered_ids:
		var center := Vector2(
			_CANVAS_WIDTH * 0.5 + _X_AMPLITUDE * sin(float(index) * 0.9),
			_TOP_MARGIN + _NODE_SPACING_Y * float(index)
		)
		_node_positions[level_id] = center
		var btn := LevelNodeButton.new()
		btn.position = center - btn.custom_minimum_size * 0.5 # placeholder; corrected after configure()
		btn.pressed.connect(_on_node_pressed.bind(level_id))
		_canvas.add_child(btn)
		_node_buttons[level_id] = btn
		index += 1

## Re-reads Progress for every node — call whenever the map becomes visible
## again (a level may have just been completed).
func refresh() -> void:
	_coins_label.text = "🪙 %d" % Economy.coins
	var current_id := Progress.current_level_id()
	for level_id in GameData.levels.ordered_ids:
		var btn: LevelNodeButton = _node_buttons[level_id]
		var state: StringName
		if not Progress.is_unlocked(level_id):
			state = &"locked"
		elif Progress.is_completed(level_id):
			state = &"completed"
		elif level_id == current_id:
			state = &"current"
		else:
			state = &"unlocked"
		btn.configure(level_id, state, Progress.get_stars(level_id))
		var center: Vector2 = _node_positions[level_id]
		btn.position = center - btn.custom_minimum_size * 0.5

	var segments: Array = []
	var ids: Array[int] = GameData.levels.ordered_ids
	for i in range(1, ids.size()):
		segments.append({
			"from": _node_positions[ids[i - 1]],
			"to": _node_positions[ids[i]],
			"lit": Progress.is_unlocked(ids[i]),
		})
	_path_canvas.set_segments(segments)

func _scroll_to_current() -> void:
	var current_id := Progress.current_level_id()
	if not _node_positions.has(current_id):
		return
	var target_y: float = _node_positions[current_id].y
	var viewport_h := _scroll.size.y
	_scroll.scroll_vertical = int(max(target_y - viewport_h * 0.5, 0.0))

func _on_node_pressed(level_id: int) -> void:
	Audio.play(&"button_tap")
	level_selected.emit(level_id)
