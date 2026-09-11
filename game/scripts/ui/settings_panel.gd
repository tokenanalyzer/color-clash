class_name SettingsPanel
extends Control
## Shared premium Settings dialog, used by BOTH the main menu and the in-level
## HUD so there is one design. Every control is wired to the real
## AudioSettings autoload; nothing here is cosmetic-only.
##
## 2026-09-06 UI asset integration: the panel chrome is now the artist-
## supplied artwork (assets/ui_kit/settings_elements.png, sliced via
## AssetLibrary.ui_slice — source PNG untouched). The decorative frame is
## shown at nearly the full portrait width (~10px each side), aspect-locked,
## never stretched; the SETTINGS banner, red ✕, ON/OFF toggles, volume
## slider, link pills and green CLOSE button are all the supplied slices.
## Only the row labels ("Music" / "Sound Effects" / "Haptics") are live text,
## exactly as before. If the sheet is missing every piece falls back to the
## previous procedural UiKit widget.

signal closed()

var _panel: UiKit.AssetFramePanel
var _scrim: ColorRect
var _privacy_choices_btn: Control

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	z_index = 200

	_scrim = ColorRect.new()
	_scrim.color = Color(0, 0, 0, 0.66)
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_scrim.gui_input.connect(func(e):
		if (e is InputEventMouseButton or e is InputEventScreenTouch) and e.pressed:
			close()
	)
	add_child(_scrim)

	_panel = UiKit.AssetFramePanel.new(&"settings_frame", 10.0, 30.0)
	add_child(_panel)
	# SETTINGS banner across the top edge (baked gold text) + red ✕ corner.
	_panel.set_banner(&"settings_title", 0.60)
	_panel.set_close_x(&"settings_close_x", func():
		Audio.play(&"button_tap")
		close())
	# Reference match: the Music section sits well below the SETTINGS header —
	# drop the whole content group so it never touches the header/banner.
	_panel.set_content_top(0.055)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.content().add_child(col)
	if AssetLibrary.ui_slice(&"settings_title") == null:
		col.add_child(VisualTheme.label("SETTINGS", VisualTheme.FS_TITLE, VisualTheme.TEXT_GOLD))

	col.add_child(_divider())
	# a little more air between the header divider and the Music row
	var lead := Control.new()
	lead.custom_minimum_size = Vector2(0, 14)
	col.add_child(lead)
	col.add_child(_audio_row("Music", &"music", true))
	col.add_child(_audio_row("Sound Effects", &"sfx", true))
	col.add_child(_audio_row("Haptics", &"haptics", false))
	col.add_child(_divider())

	var links := VBoxContainer.new()
	links.add_theme_constant_override("separation", 10)
	links.add_child(_link_button("Privacy Policy", &"settings_btn_privacy"))
	links.add_child(_link_button("Terms of Service", &"settings_btn_terms"))
	links.add_child(_link_button("Restore Purchases", &"settings_btn_restore"))
	_privacy_choices_btn = _privacy_choices_button()
	_privacy_choices_btn.visible = Ads.privacy_options_required()
	links.add_child(_privacy_choices_btn)
	col.add_child(links)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)

	col.add_child(_close_button())

	_track_size()
	get_viewport().size_changed.connect(_track_size)

func _track_size() -> void:
	var vp := get_viewport_rect().size
	size = vp
	custom_minimum_size = vp
	if _panel != null:
		_panel.layout(vp)

func open() -> void:
	visible = true
	_track_size()
	_refresh()
	_scrim.modulate.a = 0.0
	var st := _scrim.create_tween()
	st.tween_property(_scrim, "modulate:a", 1.0, 0.16)
	UiKit.pop_in(_panel.visual())

func close() -> void:
	var t := UiKit.pop_out(_panel.visual())
	_scrim.create_tween().tween_property(_scrim, "modulate:a", 0.0, 0.16)
	await t.finished
	visible = false
	closed.emit()

func _refresh() -> void:
	# UMP consent may have settled (or been withdrawn) since the panel was
	# built — re-check every time the player opens Settings, not just once.
	if _privacy_choices_btn != null:
		_privacy_choices_btn.visible = Ads.privacy_options_required()

## Gold ornament divider from the supplied sheet, or the old thin gold line.
func _divider() -> Control:
	var d := UiKit.asset_rect_fw(&"settings_divider", 0.5)
	if d != null:
		return d
	var line_wrap := Control.new()
	line_wrap.custom_minimum_size = Vector2(0, 2)
	var line := ColorRect.new()
	line.color = Color(UiKit.GOLD.r, UiKit.GOLD.g, UiKit.GOLD.b, 0.30)
	line.set_anchors_preset(Control.PRESET_FULL_RECT)
	line_wrap.add_child(line)
	return line_wrap

## One audio row: supplied icon badge + live label + supplied ON/OFF toggle,
## with an optional supplied volume slider on a second line (Music / SFX).
func _audio_row(text: String, key: StringName, has_slider: bool) -> VBoxContainer:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 8)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	wrap.add_child(top)

	var icon_id := StringName("settings_icon_" + ("music" if key == &"music" else ("sfx" if key == &"sfx" else "haptics")))
	var icon: Control = UiKit.asset_rect(icon_id)
	if icon != null:
		icon.custom_minimum_size = Vector2(84, 84)
	else:
		var ci := _RowIcon.new()
		ci.kind = key
		ci.custom_minimum_size = Vector2(48, 48)
		icon = ci
	top.add_child(icon)

	var label := VisualTheme.label(text, VisualTheme.FS_BODY, VisualTheme.TEXT, 3)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(label)

	var toggle = _make_toggle(_enabled(key))
	toggle.toggled_value.connect(func(v):
		Audio.play(&"button_tap")
		match key:
			&"music": AudioSettings.set_music_enabled(v)
			&"sfx": AudioSettings.set_sfx_enabled(v)
			&"haptics": AudioSettings.set_haptics_enabled(v)
	)
	top.add_child(toggle)

	if has_slider:
		var slider_row := HBoxContainer.new()
		var indent := Control.new()
		indent.custom_minimum_size = Vector2(70, 0)
		slider_row.add_child(indent)
		var slider = _make_slider(AudioSettings.music_volume if key == &"music" else AudioSettings.sfx_volume)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.value_changed_by_user.connect(func(v):
			if key == &"music": AudioSettings.set_music_volume(v)
			else: AudioSettings.set_sfx_volume(v)
		)
		slider_row.add_child(slider)
		wrap.add_child(slider_row)

	return wrap

## Supplied ON/OFF toggle art when present, else the procedural ToggleSwitch.
func _make_toggle(value: bool):
	if UiKit.AssetToggle.available():
		var t := UiKit.AssetToggle.new()
		t.custom_minimum_size = Vector2(168, 80)
		t.set_state(value)
		UiKit.attach_press_feedback(t)
		return t
	return UiKit.toggle(value)

## Supplied slider art when present, else the procedural VolumeSlider.
func _make_slider(value: float):
	if UiKit.AssetSlider.available():
		var s := UiKit.AssetSlider.new()
		s.custom_minimum_size = Vector2(160, 46)
		s.value = value
		return s
	return UiKit.volume_slider(value)

func _enabled(key: StringName) -> bool:
	match key:
		&"music": return AudioSettings.music_enabled
		&"sfx": return AudioSettings.sfx_enabled
		&"haptics": return AudioSettings.haptics_enabled
	return true

## Supplied purple pill (baked text) when present, else the old secondary
## button. Behaviour (a "coming at launch" toast) is unchanged.
func _link_button(text: String, slice_id: StringName) -> Control:
	var b := UiKit.asset_button_fw(AssetLibrary.ui_slice(slice_id), 0.94)
	if b != null:
		b.pressed.connect(func():
			Audio.play(&"button_tap")
			UiKit.show_toast(self, "%s — available at launch" % text)
		)
		return b
	var pb := UiKit.button(text, &"secondary", VisualTheme.FS_BODY, 28)
	pb.custom_minimum_size = Vector2(0, 56)
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pb.pressed.connect(func():
		Audio.play(&"button_tap")
		UiKit.show_toast(self, "%s — available at launch" % text)
	)
	return pb

## EEA/UK/Switzerland consent revisit entry point (UMP "privacy options").
## Only shown when `Ads.privacy_options_required()` is true (see `_refresh()`
## and where this is added in `_ready()`). No supplied art for this yet, so
## it always uses the procedural secondary-button look — unlike the other
## link rows, this one is a real, functional action, not a "coming at
## launch" placeholder.
func _privacy_choices_button() -> Control:
	var pb := UiKit.button("Privacy Choices", &"secondary", VisualTheme.FS_BODY, 28)
	pb.custom_minimum_size = Vector2(0, 56)
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pb.pressed.connect(func():
		Audio.play(&"button_tap")
		Ads.show_privacy_options()
	)
	return pb

## Supplied green CLOSE button (baked text) when present, else primary button.
func _close_button() -> Control:
	var b := UiKit.asset_button_fw(AssetLibrary.ui_slice(&"settings_btn_close"), 0.66)
	if b != null:
		b.pressed.connect(func():
			Audio.play(&"button_tap")
			close()
		)
		return b
	var cb := UiKit.button("CLOSE", &"primary", VisualTheme.FS_BUTTON)
	cb.custom_minimum_size = Vector2(0, 72)
	cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cb.pressed.connect(func():
		Audio.play(&"button_tap")
		close()
	)
	return cb


## Small code-drawn glyph for an audio setting row — the fallback only, used
## when the supplied icon slices are unavailable (note / speaker / wave).
class _RowIcon extends Control:
	var kind: StringName = &"music"
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.4
		draw_circle(c, r + 6.0, UiKit.PURPLE_FACE.darkened(0.1))
		draw_arc(c, r + 5.0, 0, TAU, 24, UiKit.GOLD.lerp(UiKit.PURPLE_FACE, 0.4), 1.5, true)
		var col := Color(1, 1, 1)
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
