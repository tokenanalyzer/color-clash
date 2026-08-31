class_name MainMenu
extends Control
## Home screen: wordmark + tagline over the shared animated Backdrop, a big
## PLAY button into the campaign map, currency readout, and an options
## popup (the essential audio toggles — full sliders live in the in-game
## settings panel). Built in code, no scene/assets.

signal play_pressed()
signal daily_pressed()

var _coins_label: Label
var _gems_label: Label
var _options: CenterContainer
var _daily_btn: Button
var _daily_dot: Control

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_track_size()
	get_viewport().size_changed.connect(_track_size)

	var bg := Backdrop.new()
	bg.accent = VisualTheme.ACCENT
	add_child(bg)

	var title := TitleBlock.new()
	title.set_anchors_preset(Control.PRESET_FULL_RECT)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 18)
	col.set_anchors_preset(Control.PRESET_CENTER)
	col.offset_top = 40
	add_child(col)

	var play := _big_button("PLAY", VisualTheme.GOOD, 30)
	play.pressed.connect(func():
		Audio.play(&"button_tap")
		_bounce(play)
		play_pressed.emit()
	)
	col.add_child(play)

	_daily_btn = _big_button("Daily Reward", VisualTheme.STAR.darkened(0.05), 20)
	_daily_btn.custom_minimum_size = Vector2(260, 56)
	_daily_btn.pressed.connect(func():
		Audio.play(&"button_tap")
		daily_pressed.emit()
	)
	col.add_child(_daily_btn)
	_daily_dot = ClaimDot.new()
	_daily_dot.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_daily_dot.position = Vector2(-6, -6)
	_daily_dot.custom_minimum_size = Vector2(18, 18)
	_daily_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_daily_btn.add_child(_daily_dot)

	var opt := _big_button("Settings", VisualTheme.ACCENT, 22)
	opt.custom_minimum_size = Vector2(220, 52)
	opt.pressed.connect(func():
		Audio.play(&"button_tap")
		_options.visible = true
		_bounce(_options.get_child(0))
	)
	col.add_child(opt)

	# currency row, top of screen
	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override("separation", 16)
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_top = 40
	add_child(top)
	_coins_label = _pill(top, &"coin", VisualTheme.TEXT_GOLD)
	_gems_label = _pill(top, &"gem", Color(0.82, 0.72, 1.0))

	var ver := VisualTheme.label("v0.4  •  offline", 13, VisualTheme.TEXT_DIM, 0)
	ver.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ver.offset_top = -34
	add_child(ver)

	_build_options()
	refresh()

func _track_size() -> void:
	var vp := get_viewport_rect().size
	size = vp
	custom_minimum_size = vp

func refresh() -> void:
	_coins_label.text = str(Economy.coins)
	_gems_label.text = str(SaveService.get_int("gems", 0))
	if _daily_dot != null:
		_daily_dot.visible = DailyRewardsScreen.has_claimable()

func _pill(parent: Control, kind: StringName, tc: Color) -> Label:
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
	var lbl := VisualTheme.label("0", 20, tc)
	row.add_child(lbl)
	return lbl

func _big_button(text: String, tint: Color, fs: int) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(300, 72)
	b.add_theme_font_size_override("font_size", fs)
	b.add_theme_color_override("font_color", VisualTheme.TEXT)
	b.add_theme_stylebox_override("normal", VisualTheme.button_face(tint.darkened(0.1)))
	b.add_theme_stylebox_override("hover", VisualTheme.button_face(tint))
	b.add_theme_stylebox_override("pressed", VisualTheme.button_face(tint.darkened(0.3)))
	b.focus_mode = Control.FOCUS_NONE
	return b

func _build_options() -> void:
	_options = CenterContainer.new()
	_options.set_anchors_preset(Control.PRESET_FULL_RECT)
	_options.visible = false
	_options.z_index = 50
	add_child(_options)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 320)
	panel.add_theme_stylebox_override("panel", VisualTheme.panel(Color(0.09, 0.10, 0.19, 0.98), 26, VisualTheme.PANEL_BORDER_BRIGHT, 2))
	_options.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	var t := VisualTheme.label("Settings", 26, VisualTheme.TEXT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	v.add_child(_toggle("Music", AudioSettings.music_enabled, func(x): AudioSettings.set_music_enabled(x)))
	v.add_child(_toggle("Sound Effects", AudioSettings.sfx_enabled, func(x): AudioSettings.set_sfx_enabled(x)))
	v.add_child(_toggle("Haptics", AudioSettings.haptics_enabled, func(x): AudioSettings.set_haptics_enabled(x)))
	var close := _big_button("Close", VisualTheme.ACCENT, 20)
	close.custom_minimum_size = Vector2(200, 52)
	close.pressed.connect(func():
		Audio.play(&"button_tap")
		_options.visible = false
	)
	v.add_child(close)

func _toggle(text: String, initial: bool, fn: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := VisualTheme.label(text, 18, VisualTheme.TEXT_DIM, 0)
	l.custom_minimum_size = Vector2(240, 0)
	row.add_child(l)
	var cb := CheckButton.new()
	cb.button_pressed = initial
	cb.toggled.connect(func(x):
		Audio.play(&"button_tap")
		fn.call(x)
	)
	row.add_child(cb)
	return row

func _bounce(node: Control) -> void:
	if node == null:
		return
	node.pivot_offset = node.size * 0.5
	var t := node.create_tween()
	t.tween_property(node, "scale", Vector2(1.06, 1.06), 0.08)
	t.tween_property(node, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Pulsing "you have something" badge on the Daily Reward button.
class ClaimDot extends Control:
	var _t := 0.0
	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()
	func _draw() -> void:
		var c := size * 0.5
		var p := 0.6 + 0.4 * sin(_t * 6.0)
		draw_circle(c, 10.0 * p, Color(1, 0.3, 0.3, 0.4))
		draw_circle(c, 7.0, Color(1, 0.35, 0.35))
		draw_circle(c + Vector2(-2, -2), 2.5, Color(1, 0.8, 0.8))


## Wordmark + tagline, gently bobbing.
class TitleBlock extends Control:
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var s := size
		if s.x < 1.0:
			return
		var cx := s.x * 0.5
		var cy := s.y * 0.30 + sin(_t * 1.6) * 5.0
		VisualTheme.draw_glow(self, Vector2(cx, cy), s.x * 0.55, Color(0.5, 0.6, 1.0, 0.12), 6)
		VisualTheme.draw_wordmark(self, Vector2(cx, cy), 58.0, 1.0)
		var font := ThemeDB.fallback_font
		var tag := "CONNECT   BLAST   COMBO"
		var tw := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		draw_string(font, Vector2(cx - tw * 0.5, cy + 52.0), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.72, 0.82, 0.96))
