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
var _box: UiKit.GoldFramePanel
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
var _flash: ColorRect
var _bg_zoom_tween: Tween

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	z_index = 250

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

	# A quick full-screen colour pulse for dramatic beats (Jinn's dark magic,
	# a capture moment) — a per-line `flash` field, never baked into art.
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(0, 0, 0, 0)
	add_child(_flash)

	_left = _make_char_slot()
	_right = _make_char_slot()
	_right.flip_h = true
	add_child(_left)
	add_child(_right)

	# Gold-framed chrome (2026-09-05 UI pass) — every other modal in the app
	# already uses this look; the dialogue box was previously a plain glass
	# rect, the one panel in the whole UI without it.
	_box = UiKit.GoldFramePanel.new(14)
	add_child(_box)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_box.content().add_child(col)
	_name_label = VisualTheme.label("", VisualTheme.FS_HEADING, VisualTheme.TEXT_GOLD)
	col.add_child(_name_label)
	_text_label = VisualTheme.label("", VisualTheme.FS_BODY, VisualTheme.TEXT, 4)
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.custom_minimum_size = Vector2(0, 92)
	col.add_child(_text_label)
	_hint = VisualTheme.label("tap to continue  ▸", VisualTheme.FS_MICRO, VisualTheme.TEXT_DIM, 0)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(_hint)

	_skip = UiKit.button("SKIP", &"tertiary", VisualTheme.FS_CAPTION)
	_skip.custom_minimum_size = Vector2(108, 50)
	_skip.pressed.connect(_finish)
	add_child(_skip)

	gui_input.connect(_on_tap)

	# _track_size() reads/positions every child built above — it MUST run
	# after they exist. Calling it before (the previous bug) crashed on the
	# still-null _box/_skip/_left/_right on its first pass and — since
	# nothing but an actual viewport resize ever re-triggers it — the
	# dialogue box, SKIP button and character slots stayed pinned at their
	# Godot-default top-left rect FOREVER on a real device (no rotation
	# event ever fires). This is the real cause of the long-standing
	# "Invalid assignment ... 'size' ... Nil" error at boot — it was never
	# cosmetic, it silently broke every StoryScene beat's layout.
	_track_size()
	get_viewport().size_changed.connect(_track_size)

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
	_skip.position = Vector2(vp.x - 108.0 - 16.0, si.position.y + 16.0)
	if _flash != null:
		_flash.size = vp
		_flash.position = Vector2.ZERO

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
	_start_bg_zoom()
	_show_line()

## A slow, continuous "camera alive" zoom on the background art for the
## whole beat (classic Ken-Burns pan) — cheap (one looping tween), never
## touches the source art.
func _start_bg_zoom() -> void:
	if _bg_zoom_tween != null and _bg_zoom_tween.is_valid():
		_bg_zoom_tween.kill()
	_bg.pivot_offset = _bg.size * 0.5
	_bg.scale = Vector2(1.0, 1.0)
	_bg_zoom_tween = create_tween()
	_bg_zoom_tween.tween_property(_bg, "scale", Vector2(1.09, 1.09), 9.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _show_line() -> void:
	if _idx >= _lines.size():
		_finish()
		return
	_busy = true
	var line: Dictionary = _lines[_idx]
	var who := StringName(String(line.get("who", "narrator")))
	var pose := StringName(String(line.get("pose", "peaceful")))
	var text := String(line.get("text", ""))

	# Per-line background swap (a scene change within one beat — the peaceful
	# island giving way to Jinn's dark-magic backdrop, say). Beat-level
	# `background` still sets the default for lines that don't override it.
	if line.has("bg"):
		_swap_bg(StringName(String(line["bg"])))

	# Optional per-line beats: a dramatic colour pulse ("flash": "#rrggbb" or
	# a named preset) and/or a short shake — both presentation-only, never
	# baked into any art. Fire before the line settles so they land with it.
	if line.has("flash"):
		_play_flash(String(line["flash"]))
	if line.has("shake"):
		_play_shake(float(line["shake"]))
	if line.has("particles"):
		_play_particles(StringName(String(line["particles"])))

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

## Swap the background art mid-beat with a quick fade (a scene change without
## a hard cut). No-op if it's already showing `bg_id`.
func _swap_bg(bg_id: StringName) -> void:
	var tex := AssetLibrary.tex(bg_id)
	if tex == null or _bg.texture == tex:
		return
	var t := _bg.create_tween()
	t.tween_property(_bg, "modulate:a", 0.0, 0.15)
	t.tween_callback(func():
		_bg.texture = tex
		_bg.visible = true
		_start_bg_zoom())
	t.tween_property(_bg, "modulate:a", 1.0, 0.2)

const _FLASH_PRESETS := {
	"red": Color(0.85, 0.08, 0.12), "dark_magic": Color(0.6, 0.05, 0.5),
	"blue": Color(0.25, 0.55, 1.0), "white": Color(1, 1, 1), "gold": Color(1.0, 0.82, 0.3),
}
## Each flash preset also carries a non-verbal sound hook — existing
## synthesized ids (data/sfx.json), no licensed/external audio. The
## Audio.register(id, stream) seam means these swap for real voice/sfx
## later with no code change here.
const _FLASH_SFX := {
	"red": &"boss_impact", "dark_magic": &"boss_impact",
	"blue": &"lightning", "white": &"power_up", "gold": &"power_up",
}

## A quick colour pulse over the whole scene — "red"/"dark_magic"/"blue"/
## "white"/"gold" or a literal "#rrggbb". Presentation only.
func _play_flash(id: String) -> void:
	var col: Color = _FLASH_PRESETS.get(id, Color.html(id) if id.begins_with("#") else Color(1, 1, 1))
	_flash.color = Color(col.r, col.g, col.b, 0.0)
	var t := _flash.create_tween()
	t.tween_property(_flash, "color:a", 0.55, 0.08)
	t.tween_property(_flash, "color:a", 0.0, 0.42)
	if _FLASH_SFX.has(id):
		Audio.play(_FLASH_SFX[id], 0.8)

## A short decaying shake on the whole cutscene layer (Jinn's arrival, an
## impact beat). Local implementation — StoryScene is a Control, not the
## Node2D the shared ScreenShake utility expects.
func _play_shake(strength: float) -> void:
	if strength <= 0.0:
		return
	var rest := position
	var t := create_tween()
	var steps := 6
	for i in steps:
		var falloff := 1.0 - float(i + 1) / float(steps)
		var off := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * strength * falloff
		t.tween_property(self, "position", rest + off, 0.28 / float(steps))
	t.tween_property(self, "position", rest, 0.28 / float(steps))

## A one-shot magic particle burst using the supplied VFX art (not redrawn),
## centred unless `at` (viewport-normalized Vector2) is given in the line.
func _play_particles(vfx_id: StringName) -> void:
	var tex := AssetLibrary.tex(vfx_id)
	if tex == null:
		return
	var p := CPUParticles2D.new()
	p.texture = tex
	p.emitting = false
	p.one_shot = true
	p.amount = 22
	p.lifetime = 0.9
	p.explosiveness = 0.85
	p.direction = Vector2.UP
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 60.0
	p.initial_velocity_max = 220.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0
	p.position = size * 0.5
	add_child(p)
	p.restart()
	p.emitting = true
	get_tree().create_timer(p.lifetime + 0.2).timeout.connect(func():
		if is_instance_valid(p):
			p.queue_free()
	)

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
