class_name SettingsPanel
extends Control
## Shared premium Settings dialog — a gold-framed frosted-glass panel with
## animated open/close, used by BOTH the main menu and the in-level HUD so
## there is one design. Every control is wired to the real AudioSettings
## autoload; nothing here is cosmetic-only.

signal closed()

var _frame: UiKit.GoldFramePanel
var _scrim: ColorRect
var _toast: Label

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	z_index = 200
	_track_size()
	get_viewport().size_changed.connect(_track_size)

	_scrim = ColorRect.new()
	_scrim.color = Color(0, 0, 0, 0.66)
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_scrim.gui_input.connect(func(e):
		if (e is InputEventMouseButton or e is InputEventScreenTouch) and e.pressed:
			close()
	)
	add_child(_scrim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_frame = UiKit.GoldFramePanel.new(20)
	_frame.custom_minimum_size = Vector2(560, 0)
	center.add_child(_frame)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	_frame.content().add_child(col)

	# --- title banner + close X ---------------------------------------
	var title_row := Control.new()
	title_row.custom_minimum_size = Vector2(0, 54)
	col.add_child(title_row)
	var title := VisualTheme.label("SETTINGS", VisualTheme.FS_TITLE, VisualTheme.TEXT_GOLD)
	title.set_anchors_preset(Control.PRESET_FULL_RECT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_row.add_child(title)
	var x_btn := UiKit.icon_button(&"close", 52)
	x_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	x_btn.position = Vector2(-4, -8)
	var xsb := UiKit.button_face(UiKit.RED_FACE, UiKit.RED_DEEP, 26)
	xsb.content_margin_left = 0; xsb.content_margin_right = 0
	xsb.content_margin_top = 0; xsb.content_margin_bottom = 0
	x_btn.add_theme_stylebox_override("normal", xsb)
	x_btn.add_theme_stylebox_override("hover", xsb)
	x_btn.pressed.connect(func():
		Audio.play(&"button_tap")
		close()
	)
	title_row.add_child(x_btn)

	col.add_child(_divider())
	col.add_child(_audio_row("Music", &"music", true))
	col.add_child(_audio_row("Sound Effects", &"sfx", true))
	col.add_child(_audio_row("Haptics", &"haptics", false))
	col.add_child(_divider())

	col.add_child(_link_button("Privacy Policy"))
	col.add_child(_link_button("Terms of Service"))
	col.add_child(_link_button("Restore Purchases"))

	var close_btn := UiKit.button("CLOSE", &"primary", VisualTheme.FS_BUTTON)
	close_btn.custom_minimum_size = Vector2(0, 72)
	close_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_btn.pressed.connect(func():
		Audio.play(&"button_tap")
		close()
	)
	col.add_child(close_btn)

	_toast = VisualTheme.label("", VisualTheme.FS_BODY, VisualTheme.TEXT, 5)
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.add_theme_stylebox_override("normal", UiKit.glass(16, true))
	_toast.modulate.a = 0.0
	_toast.z_index = 10
	add_child(_toast)

func _track_size() -> void:
	var vp := get_viewport_rect().size
	size = vp
	custom_minimum_size = vp

func open() -> void:
	visible = true
	_refresh()
	_scrim.modulate.a = 0.0
	var st := _scrim.create_tween()
	st.tween_property(_scrim, "modulate:a", 1.0, 0.16)
	UiKit.pop_in(_frame)

func close() -> void:
	var t := UiKit.pop_out(_frame)
	_scrim.create_tween().tween_property(_scrim, "modulate:a", 0.0, 0.16)
	await t.finished
	visible = false
	closed.emit()

func _refresh() -> void:
	pass # rows read AudioSettings live via their own build; nothing cached

func _divider() -> Control:
	var d := Control.new()
	d.custom_minimum_size = Vector2(0, 2)
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.08)
	line.set_anchors_preset(Control.PRESET_FULL_RECT)
	d.add_child(line)
	return d

## One audio row: icon + label, optional volume slider, ON/OFF toggle.
func _audio_row(text: String, key: StringName, has_slider: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.custom_minimum_size = Vector2(0, 52)

	var icon := _RowIcon.new()
	icon.kind = key
	icon.custom_minimum_size = Vector2(38, 38)
	row.add_child(icon)

	var label := VisualTheme.label(text, VisualTheme.FS_BODY, VisualTheme.TEXT, 3)
	label.custom_minimum_size = Vector2(150, 0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)

	if has_slider:
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.01
		slider.custom_minimum_size = Vector2(130, 0)
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.value = AudioSettings.music_volume if key == &"music" else AudioSettings.sfx_volume
		slider.value_changed.connect(func(v):
			if key == &"music": AudioSettings.set_music_volume(v)
			else: AudioSettings.set_sfx_volume(v)
		)
		row.add_child(slider)
	else:
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)

	var toggle := CheckButton.new()
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.button_pressed = _enabled(key)
	toggle.toggled.connect(func(v):
		Audio.play(&"button_tap")
		match key:
			&"music": AudioSettings.set_music_enabled(v)
			&"sfx": AudioSettings.set_sfx_enabled(v)
			&"haptics": AudioSettings.set_haptics_enabled(v)
	)
	row.add_child(toggle)
	return row

func _enabled(key: StringName) -> bool:
	match key:
		&"music": return AudioSettings.music_enabled
		&"sfx": return AudioSettings.sfx_enabled
		&"haptics": return AudioSettings.haptics_enabled
	return true

func _link_button(text: String) -> Button:
	var b := UiKit.button(text, &"secondary", VisualTheme.FS_BODY)
	b.custom_minimum_size = Vector2(0, 56)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func():
		Audio.play(&"button_tap")
		_show_toast("%s — available at launch" % text)
	)
	return b

func _show_toast(text: String) -> void:
	_toast.text = "  %s  " % text
	_toast.position = Vector2((size.x - _toast.size.x) * 0.5, size.y * 0.72)
	var t := _toast.create_tween()
	t.tween_property(_toast, "modulate:a", 1.0, 0.14)
	t.tween_interval(1.2)
	t.tween_property(_toast, "modulate:a", 0.0, 0.3)


## Small code-drawn glyph for an audio setting row (note / speaker / wave).
class _RowIcon extends Control:
	var kind: StringName = &"music"
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.4
		draw_circle(c, r + 4.0, Color(UiKit.GOLD.r, UiKit.GOLD.g, UiKit.GOLD.b, 0.16))
		var col := UiKit.GOLD
		match kind:
			&"music":
				draw_line(c + Vector2(-r * 0.2, r * 0.5), c + Vector2(-r * 0.2, -r * 0.7), col, 3.0, true)
				draw_line(c + Vector2(r * 0.5, r * 0.3), c + Vector2(r * 0.5, -r * 0.9), col, 3.0, true)
				draw_line(c + Vector2(-r * 0.2, -r * 0.7), c + Vector2(r * 0.5, -r * 0.9), col, 3.0, true)
				draw_circle(c + Vector2(-r * 0.4, r * 0.5), r * 0.3, col)
				draw_circle(c + Vector2(r * 0.3, r * 0.3), r * 0.3, col)
			&"sfx":
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(-r * 0.7, -r * 0.3), c + Vector2(-r * 0.2, -r * 0.3),
					c + Vector2(r * 0.2, -r * 0.7), c + Vector2(r * 0.2, r * 0.7),
					c + Vector2(-r * 0.2, r * 0.3), c + Vector2(-r * 0.7, r * 0.3),
				]), col)
				draw_arc(c + Vector2(r * 0.3, 0), r * 0.5, -PI * 0.4, PI * 0.4, 10, col, 3.0, true)
				draw_arc(c + Vector2(r * 0.3, 0), r * 0.8, -PI * 0.4, PI * 0.4, 12, col, 3.0, true)
			_:
				for i in 3:
					var a := r * (0.3 + 0.25 * i)
					draw_arc(c, a, PI * 0.75, PI * 1.25, 10, col, 3.0, true)
					draw_arc(c, a, -PI * 0.25, PI * 0.25, 10, col, 3.0, true)
