class_name StoryScene
extends Control
## A reusable cutscene overlay for one story beat (data/story.json). Shows the
## speaking character's supplied art on one side, a glass dialogue box with
## the speaker's name + line, and advances on tap. `narrator` lines centre
## the text with both characters dimmed. Entrance/exit are simple tweens —
## no character art is deformed or redrawn, only moved / scaled / faded.
##
##   var s := StoryScene.new(); parent.add_child(s)
##   s.finished.connect(...)
##   s.play(Story.beat_for("campaign_start"))

signal finished()

var _scrim: ColorRect
var _bg: TextureRect
var _left: TextureRect
var _right: TextureRect
var _box: PanelContainer
var _name_label: Label
var _text_label: Label
var _hint: Label
var _skip: Button

var _lines: Array = []
var _idx := 0
var _busy := false
var _line_token := 0
var _left_who: StringName = &""
var _right_who: StringName = &""

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	z_index = 250
	_track_size()
	get_viewport().size_changed.connect(_track_size)

	_bg = TextureRect.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.modulate = Color(0.5, 0.52, 0.62, 1.0)
	add_child(_bg)

	_scrim = ColorRect.new()
	_scrim.color = Color(0.02, 0.03, 0.07, 0.62)
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_scrim)

	_left = _make_char_slot()
	_right = _make_char_slot()
	_right.flip_h = true
	add_child(_left)
	add_child(_right)

	_box = PanelContainer.new()
	_box.add_theme_stylebox_override("panel", UiKit.glass(24, true))
	add_child(_box)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_box.add_child(col)
	_name_label = VisualTheme.label("", VisualTheme.FS_HEADING, VisualTheme.TEXT_GOLD)
	col.add_child(_name_label)
	_text_label = VisualTheme.label("", VisualTheme.FS_BODY, VisualTheme.TEXT, 4)
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.custom_minimum_size = Vector2(0, 92)
	col.add_child(_text_label)
	_hint = VisualTheme.label("tap to continue  ▸", VisualTheme.FS_MICRO, VisualTheme.TEXT_DIM, 0)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(_hint)

	_skip = UiKit.button("SKIP", &"tertiary", VisualTheme.FS_MICRO)
	_skip.custom_minimum_size = Vector2(96, 44)
	_skip.pressed.connect(_finish)
	add_child(_skip)

	gui_input.connect(_on_tap)

func _make_char_slot() -> TextureRect:
	var tr := TextureRect.new()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.modulate.a = 0.0
	return tr

func _track_size() -> void:
	var vp := get_viewport_rect().size
	size = vp
	custom_minimum_size = vp
	var si := VisualTheme.safe_insets(self)
	var ch: float = vp.y * 0.52
	var cw: float = ch * 0.72
	_left.size = Vector2(cw, ch)
	_left.position = Vector2(-cw * 0.06, vp.y * 0.30)
	_right.size = Vector2(cw, ch)
	_right.position = Vector2(vp.x - cw * 0.94, vp.y * 0.30)
	var bw: float = minf(vp.x - 32.0, 760.0)
	_box.size = Vector2(bw, 0)
	_box.position = Vector2((vp.x - bw) * 0.5, vp.y - 250.0 - si.size.y)
	_box.custom_minimum_size = Vector2(bw, 190)
	_skip.position = Vector2(vp.x - 96.0 - 16.0, si.position.y + 16.0)

## When true, play() resolves on the next frame without showing anything —
## for headless smoke tests / automated runs where nobody can tap.
static var auto_skip := false

## Play one beat. Emits `finished` when the last line is dismissed (or SKIP).
func play(beat: Dictionary) -> void:
	if beat.is_empty():
		finished.emit()
		return
	if auto_skip or DisplayServer.get_name() == "headless":
		call_deferred("emit_signal", "finished")
		return
	_lines = beat.get("lines", [])
	_idx = 0
	var bg_id := StringName(String(beat.get("background", "")))
	_bg.texture = AssetLibrary.tex(bg_id) if bg_id != &"" else null
	_bg.visible = _bg.texture != null
	_left_who = &""
	_right_who = &""
	_left.modulate.a = 0.0
	_right.modulate.a = 0.0
	visible = true
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.25)
	_show_line()

func _show_line() -> void:
	if _idx >= _lines.size():
		_finish()
		return
	_busy = true
	var line: Dictionary = _lines[_idx]
	var who := StringName(String(line.get("who", "narrator")))
	var pose := StringName(String(line.get("pose", "peaceful")))
	var text := String(line.get("text", ""))

	if who == &"narrator":
		_name_label.text = ""
		_text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_dim_both()
	else:
		_name_label.text = Cast.display_name(who)
		_text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_place_speaker(who, pose)
	_text_label.text = text

	# quick typewriter-ish reveal via alpha
	_text_label.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_text_label, "modulate:a", 1.0, 0.18)
	tw.tween_callback(func(): _busy = false)

	# auto-advance if the player doesn't tap (roughly reading speed)
	_line_token += 1
	var tok := _line_token
	var dwell: float = clampf(1.6 + float(text.length()) * 0.035, 2.2, 6.0)
	get_tree().create_timer(dwell).timeout.connect(func():
		if tok == _line_token and visible and not _busy:
			_idx += 1
			_show_line()
	)

## Puts `who` on whichever side they already hold, else the free side.
func _place_speaker(who: StringName, pose: StringName) -> void:
	var tex := Cast.pose(who, pose)
	var slot: TextureRect
	if _left_who == who:
		slot = _left
	elif _right_who == who:
		slot = _right
	elif _left_who == &"" or who == Cast.WHO_JAMIE:
		slot = _left
		_left_who = who
	else:
		slot = _right
		_right_who = who
	if slot.texture != tex:
		slot.texture = tex
	var other := _right if slot == _left else _left
	var from_x := slot.position.x
	slot.modulate = Color(1, 1, 1, 1)
	slot.scale = Vector2(1.04, 1.04)
	var t := slot.create_tween()
	t.tween_property(slot, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK)
	other.create_tween().tween_property(other, "modulate", Color(0.5, 0.5, 0.58, 0.7), 0.2)

func _dim_both() -> void:
	for s in [_left, _right]:
		if s.modulate.a > 0.01:
			s.create_tween().tween_property(s, "modulate", Color(0.5, 0.5, 0.58, 0.6), 0.2)

func _on_tap(event: InputEvent) -> void:
	if (event is InputEventMouseButton or event is InputEventScreenTouch) and event.pressed and not _busy:
		_idx += 1
		_show_line()

func _finish() -> void:
	set_process_input(false)
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.22)
	t.tween_callback(func():
		visible = false
		finished.emit()
	)
