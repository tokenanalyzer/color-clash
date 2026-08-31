class_name HUD
extends Control
## Mobile-first gameplay HUD, built entirely in code so the layout stays
## anchor-driven and scales to any portrait resolution. Three top pills
## (MOVES / TARGET / COINS), a Fever meter, a bottom booster tray, and
## animated win/lose + settings overlays. The board renders beneath this
## layer; only the top/bottom strips and popups intercept touch.

signal booster_pressed(booster_id: StringName)
signal next_level_pressed()
signal retry_pressed()
signal map_pressed()
signal pause_pressed()
signal resume_pressed()

var _level_label: Label
var _score_label: Label
var _moves_value: Label
var _moves_pill: PanelContainer
var _objective_row: HBoxContainer
var _objective_chips: Array[Node] = []
var _coins_label: Label
var _fever_bar: ProgressBar
var _fever_label: Label
var _fever_wrap: Control
var _booster_buttons: Dictionary = {}
var _booster_badges: Dictionary = {}
var _booster_slots: Dictionary = {}      # id -> Control (for scale/armed FX)
var _booster_counts: Dictionary = {}     # id -> int (last known)
var _armed_booster: StringName = &""
var _hint_label: Label
var _end_panel: PanelContainer
var _end_center: CenterContainer
var _end_title: Label
var _end_stars: StarRow
var _end_body: Label
var _end_button: Button
var _end_map_button: Button
var _end_confetti: CPUParticles2D
var _settings_panel: PanelContainer
var _settings_center: CenterContainer
var _pause_center: CenterContainer
var _pause_panel: PanelContainer
var _scrim: ColorRect
var _displayed_coins: int = 0
var _fever_running := false
var _fever_pulse: Tween

## Order + identity of the in-level booster tray. Icons are code-drawn
## (IconDraw) — no emoji (Android dropped the legacy emoji font).
const _BOOSTER_ORDER: Array[StringName] = [
	&"bomb", &"lightning", &"freeze", &"rainbow", &"shuffle", &"extra_moves",
]
const _BOOSTER_TINT := {
	&"bomb": Color(0.85, 0.22, 0.28), &"lightning": Color(0.98, 0.72, 0.14),
	&"freeze": Color(0.28, 0.66, 0.96), &"rainbow": Color(0.62, 0.34, 0.94),
	&"shuffle": Color(0.2, 0.7, 0.55), &"extra_moves": Color(0.3, 0.6, 0.95),
}

## Screen-edge insets (notch / status bar / gesture bar) in viewport units,
## resolved from DisplayServer.get_display_safe_area(). Everything at the
## top/bottom of the HUD is pushed in by these so nothing is ever clipped.
var _safe_top := 0.0
var _safe_bottom := 0.0
var _top_margin: MarginContainer
var _bottom_col: VBoxContainer

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_resolve_safe_area()
	_build_top_bar()
	_build_fever_meter()
	_build_booster_bar()
	_scrim = ColorRect.new()
	_scrim.color = Color(0, 0, 0, 0.55)
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scrim.visible = false
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_scrim)
	_build_end_panel()
	_build_settings_panel()
	_build_pause_panel()
	_track_size()
	get_viewport().size_changed.connect(_track_size)

## A Control parented to a CanvasLayer is not auto-resized to the viewport,
## so anchor presets (BOTTOM_WIDE, CENTER, ...) collapse unless we set the
## rect ourselves. Keep it pinned to the visible viewport.
func _track_size() -> void:
	var vp := get_viewport_rect().size
	size = vp
	custom_minimum_size = vp
	_resolve_safe_area()
	if _top_margin != null:
		_top_margin.add_theme_constant_override("margin_top", int(_safe_top + 40.0))
	if _bottom_col != null:
		_bottom_col.offset_bottom = -int(_safe_bottom + 14.0)
	if _fever_wrap != null:
		_fever_wrap.offset_top = _safe_top + 138.0
	if _level_label != null:
		_level_label.offset_top = _safe_top + 12.0

func _resolve_safe_area() -> void:
	var vp := get_viewport_rect().size
	var safe := DisplayServer.get_display_safe_area()
	var win := DisplayServer.window_get_size()
	if win.y <= 0 or safe.size.y <= 0:
		return
	var sy := vp.y / float(win.y)
	_safe_top = maxf(float(safe.position.y) * sy, 0.0)
	_safe_bottom = maxf(float(win.y - (safe.position.y + safe.size.y)) * sy, 0.0)

# ------------------------------------------------------------- top bar --

func _icon_button(kind: StringName, size: int = 46) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(size, size)
	b.add_theme_stylebox_override("normal", VisualTheme.panel(VisualTheme.PANEL_RAISED, size / 2, VisualTheme.PANEL_BORDER, 2))
	b.add_theme_stylebox_override("hover", VisualTheme.panel(VisualTheme.PANEL_RAISED.lightened(0.1), size / 2))
	b.add_theme_stylebox_override("pressed", VisualTheme.panel(VisualTheme.PANEL_SOLID, size / 2))
	b.focus_mode = Control.FOCUS_NONE
	var icon := MiniIcon.new()
	icon.kind = kind
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(icon)
	return b

func _pill(child: Control, min_w: float = 0.0) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", VisualTheme.panel(VisualTheme.PANEL, 22, VisualTheme.PANEL_BORDER, 2))
	pc.custom_minimum_size = Vector2(min_w, 0)
	pc.add_child(child)
	return pc

func _build_top_bar() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_TOP_WIDE)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", int(_safe_top + 30.0))
	_top_margin = margin
	add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)

	var pause_btn := _icon_button(&"pause")
	pause_btn.pressed.connect(func():
		Audio.play(&"button_tap")
		pause_pressed.emit()
	)
	row.add_child(pause_btn)

	# MOVES pill
	var moves_box := VBoxContainer.new()
	moves_box.alignment = BoxContainer.ALIGNMENT_CENTER
	moves_box.add_theme_constant_override("separation", 0)
	var moves_cap := VisualTheme.label("MOVES", 13, VisualTheme.TEXT_DIM, 0)
	moves_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	moves_box.add_child(moves_cap)
	_moves_value = VisualTheme.label("20", 32, VisualTheme.TEXT)
	_moves_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	moves_box.add_child(_moves_value)
	_moves_pill = _pill(moves_box, 78)
	row.add_child(_moves_pill)

	# TARGET pill (expands)
	var tgt_box := VBoxContainer.new()
	tgt_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tgt_box.add_theme_constant_override("separation", 2)
	var tgt_cap := VisualTheme.label("TARGET", 13, VisualTheme.TEXT_DIM, 0)
	tgt_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tgt_box.add_child(tgt_cap)
	_objective_row = HBoxContainer.new()
	_objective_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_objective_row.add_theme_constant_override("separation", 14)
	tgt_box.add_child(_objective_row)
	var tgt_pill := _pill(tgt_box)
	tgt_pill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(tgt_pill)

	# COINS pill
	var coin_box := HBoxContainer.new()
	coin_box.alignment = BoxContainer.ALIGNMENT_CENTER
	coin_box.add_theme_constant_override("separation", 6)
	var coin_icon := GemIcon.new()
	coin_icon.kind = &"coin"
	coin_icon.custom_minimum_size = Vector2(22, 22)
	coin_box.add_child(coin_icon)
	_coins_label = VisualTheme.label("0", 22, VisualTheme.TEXT_GOLD)
	coin_box.add_child(_coins_label)
	row.add_child(_pill(coin_box, 70))

	var gear := _icon_button(&"gear")
	gear.pressed.connect(func():
		Audio.play(&"button_tap")
		_show_settings(true)
	)
	row.add_child(gear)

	_level_label = VisualTheme.label("LEVEL 1", 16, VisualTheme.TEXT_GOLD, 4)
	_level_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_label.offset_top = 12
	_level_label.custom_minimum_size = Vector2(0, 22)
	add_child(_level_label)

# ------------------------------------------------------------ fever --

func _build_fever_meter() -> void:
	_score_label = VisualTheme.label("0", 22, VisualTheme.TEXT, 4)
	_score_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_label.offset_top = _safe_top + 108.0
	_score_label.custom_minimum_size = Vector2(0, 26)
	add_child(_score_label)

	_fever_wrap = Control.new()
	_fever_wrap.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_fever_wrap.offset_top = 150
	_fever_wrap.offset_left = 56
	_fever_wrap.offset_right = -56
	_fever_wrap.custom_minimum_size = Vector2(0, 22)
	add_child(_fever_wrap)

	_fever_bar = ProgressBar.new()
	_fever_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fever_bar.min_value = 0
	_fever_bar.max_value = 100
	_fever_bar.show_percentage = false
	_fever_bar.custom_minimum_size = Vector2(0, 22)
	_fever_bar.add_theme_stylebox_override("background", _bar_style(Color(0.05, 0.06, 0.11, 0.95)))
	_fever_bar.add_theme_stylebox_override("fill", _bar_style(VisualTheme.FEVER))
	_fever_wrap.add_child(_fever_bar)

	_fever_label = VisualTheme.label("FEVER", 13, VisualTheme.TEXT_DIM, 4)
	_fever_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fever_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fever_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_fever_wrap.add_child(_fever_label)

func _bar_style(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(9)
	return sb

# ---------------------------------------------------------- boosters --

func _build_booster_bar() -> void:
	# Anchored directly (not via a MarginContainer) so it has a real rect on
	# a Control that's parented to a CanvasLayer.
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	col.offset_left = 10
	col.offset_right = -10
	col.offset_top = -150
	col.offset_bottom = -int(_safe_bottom + 14.0)
	col.alignment = BoxContainer.ALIGNMENT_END
	col.add_theme_constant_override("separation", 6)
	_bottom_col = col
	add_child(col)

	_hint_label = VisualTheme.label("", 15, VisualTheme.TEXT_GOLD, 4)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.custom_minimum_size = Vector2(0, 20)
	col.add_child(_hint_label)

	var tray := PanelContainer.new()
	tray.add_theme_stylebox_override("panel", VisualTheme.panel(VisualTheme.PANEL_RAISED, 24, VisualTheme.PANEL_BORDER_BRIGHT, 2))
	col.add_child(tray)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	tray.add_child(row)

	for id in _BOOSTER_ORDER:
		var tint: Color = _BOOSTER_TINT[id]
		var slot := Control.new()
		slot.custom_minimum_size = Vector2(66, 72)
		slot.pivot_offset = slot.custom_minimum_size * 0.5

		var chip := BoosterChip.new()
		chip.tint = tint
		chip.booster_id = id
		chip.set_anchors_preset(Control.PRESET_FULL_RECT)
		slot.add_child(chip)

		var btn := Button.new()
		btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		btn.flat = true
		btn.focus_mode = Control.FOCUS_NONE
		var empty := StyleBoxEmpty.new()
		for s in ["normal", "hover", "pressed", "disabled", "focus"]:
			btn.add_theme_stylebox_override(s, empty)
		btn.pressed.connect(func():
			Audio.play(&"button_tap")
			booster_pressed.emit(id)
		)
		slot.add_child(btn)

		var badge := VisualTheme.label("0", 15, VisualTheme.TEXT, 4)
		badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		badge.offset_left = -22
		badge.offset_top = -22
		badge.custom_minimum_size = Vector2(22, 22)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.add_theme_stylebox_override("normal", VisualTheme.panel(Color(0.05, 0.06, 0.11, 0.98), 11, VisualTheme.PANEL_BORDER_BRIGHT, 1))
		slot.add_child(badge)

		row.add_child(slot)
		_booster_buttons[id] = btn
		_booster_badges[id] = badge
		_booster_slots[id] = slot
		_booster_counts[id] = 0

## Called by the controller so the tray can show which booster is armed
## and prompt the player. Pass &"" to clear.
func set_booster_armed(id: StringName) -> void:
	_armed_booster = id
	for bid in _booster_slots.keys():
		var slot: Control = _booster_slots[bid]
		var chip = slot.get_child(0)
		chip.armed = (bid == id)
		chip.queue_redraw()
		var t := slot.create_tween()
		t.tween_property(slot, "scale", Vector2(1.12, 1.12) if bid == id else Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK)
	if id == &"":
		_hint_label.text = ""
	else:
		var def: Dictionary = GameData.boosters.get(id, {})
		_hint_label.text = "Tap the board — %s" % String(def.get("help", "")).to_lower()
		_pulse(_hint_label, 1.06)

func flash_booster(id: StringName) -> void:
	if not _booster_slots.has(id):
		return
	var slot: Control = _booster_slots[id]
	var t := slot.create_tween()
	t.tween_property(slot, "scale", Vector2(1.3, 1.3), 0.1).set_trans(Tween.TRANS_BACK)
	t.tween_property(slot, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_ELASTIC)

# --------------------------------------------------------- overlays --

func _build_end_panel() -> void:
	_end_center = CenterContainer.new()
	_end_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end_center.visible = false
	add_child(_end_center)

	_end_panel = PanelContainer.new()
	_end_panel.custom_minimum_size = Vector2(440, 400)
	_end_panel.add_theme_stylebox_override("panel", VisualTheme.panel(Color(0.09, 0.10, 0.19, 0.98), 28, VisualTheme.PANEL_BORDER_BRIGHT, 2))
	_end_center.add_child(_end_panel)

	_end_confetti = CPUParticles2D.new()
	_end_confetti.emitting = false
	_end_confetti.one_shot = true
	_end_confetti.amount = 70
	_end_confetti.lifetime = 1.6
	_end_confetti.explosiveness = 0.85
	_end_confetti.direction = Vector2.DOWN
	_end_confetti.spread = 180.0
	_end_confetti.gravity = Vector2(0, 420)
	_end_confetti.initial_velocity_min = 220.0
	_end_confetti.initial_velocity_max = 460.0
	_end_confetti.scale_amount_min = 3.0
	_end_confetti.scale_amount_max = 6.0
	_end_confetti.angular_velocity_min = -720.0
	_end_confetti.angular_velocity_max = 720.0
	_end_confetti.position = Vector2(220, 30)
	_end_panel.add_child(_end_confetti)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	_end_panel.add_child(vbox)

	_end_title = VisualTheme.label("Level Complete!", 34, VisualTheme.TEXT_GOLD)
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_end_title)

	_end_stars = StarRow.new()
	_end_stars.custom_minimum_size = Vector2(220, 64)
	vbox.add_child(_end_stars)

	_end_body = VisualTheme.label("", 21, VisualTheme.TEXT)
	_end_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_end_body)

	_end_button = _cta_button("Continue", VisualTheme.GOOD)
	vbox.add_child(_end_button)

	_end_map_button = _cta_button("Level Map", VisualTheme.ACCENT)
	_end_map_button.pressed.connect(func():
		Audio.play(&"button_tap")
		map_pressed.emit()
	)
	vbox.add_child(_end_map_button)

func _cta_button(text: String, tint: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(240, 58)
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", VisualTheme.TEXT)
	b.add_theme_stylebox_override("normal", VisualTheme.button_face(tint.darkened(0.1)))
	b.add_theme_stylebox_override("hover", VisualTheme.button_face(tint))
	b.add_theme_stylebox_override("pressed", VisualTheme.button_face(tint.darkened(0.3)))
	b.focus_mode = Control.FOCUS_NONE
	return b

func _build_settings_panel() -> void:
	_settings_center = CenterContainer.new()
	_settings_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_center.visible = false
	_settings_center.z_index = 200
	add_child(_settings_center)

	_settings_panel = PanelContainer.new()
	_settings_panel.custom_minimum_size = Vector2(460, 460)
	_settings_panel.add_theme_stylebox_override("panel", VisualTheme.panel(Color(0.09, 0.10, 0.19, 0.98), 28, VisualTheme.PANEL_BORDER_BRIGHT, 2))
	_settings_center.add_child(_settings_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	_settings_panel.add_child(vbox)

	var title := VisualTheme.label("Settings", 28, VisualTheme.TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	vbox.add_child(_toggle_row("Music", AudioSettings.music_enabled, func(v): AudioSettings.set_music_enabled(v)))
	vbox.add_child(_toggle_row("Sound Effects", AudioSettings.sfx_enabled, func(v): AudioSettings.set_sfx_enabled(v)))
	vbox.add_child(_toggle_row("Haptics", AudioSettings.haptics_enabled, func(v): AudioSettings.set_haptics_enabled(v)))
	vbox.add_child(_slider_row("Master Volume", AudioSettings.master_volume, func(v): AudioSettings.set_master_volume(v)))
	vbox.add_child(_slider_row("Music Volume", AudioSettings.music_volume, func(v): AudioSettings.set_music_volume(v)))
	vbox.add_child(_slider_row("SFX Volume", AudioSettings.sfx_volume, func(v): AudioSettings.set_sfx_volume(v)))

	var close_btn := _cta_button("Close", VisualTheme.ACCENT)
	close_btn.pressed.connect(func():
		Audio.play(&"button_tap")
		_show_settings(false)
	)
	vbox.add_child(close_btn)

func _show_settings(v: bool) -> void:
	_settings_center.visible = v
	_refresh_scrim()
	if v:
		_pop_in(_settings_panel)

func _refresh_scrim() -> void:
	_scrim.visible = _end_center.visible or _settings_center.visible or _pause_center.visible

func _build_pause_panel() -> void:
	_pause_center = CenterContainer.new()
	_pause_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_center.visible = false
	_pause_center.z_index = 190
	add_child(_pause_center)

	_pause_panel = PanelContainer.new()
	_pause_panel.custom_minimum_size = Vector2(420, 380)
	_pause_panel.add_theme_stylebox_override("panel", VisualTheme.panel(Color(0.09, 0.10, 0.19, 0.98), 28, VisualTheme.PANEL_BORDER_BRIGHT, 2))
	_pause_center.add_child(_pause_panel)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	_pause_panel.add_child(vbox)

	var title := VisualTheme.label("Paused", 32, VisualTheme.TEXT_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var resume := _cta_button("Resume", VisualTheme.GOOD)
	resume.pressed.connect(func():
		Audio.play(&"button_tap")
		show_pause_panel(false)
		resume_pressed.emit()
	)
	vbox.add_child(resume)

	var restart := _cta_button("Restart", VisualTheme.FEVER)
	restart.pressed.connect(func():
		Audio.play(&"button_tap")
		show_pause_panel(false)
		retry_pressed.emit()
	)
	vbox.add_child(restart)

	var settings := _cta_button("Settings", VisualTheme.ACCENT)
	settings.pressed.connect(func():
		Audio.play(&"button_tap")
		_show_settings(true)
	)
	vbox.add_child(settings)

	var to_map := _cta_button("Quit to Map", VisualTheme.ACCENT.darkened(0.2))
	to_map.pressed.connect(func():
		Audio.play(&"button_tap")
		show_pause_panel(false)
		map_pressed.emit()
	)
	vbox.add_child(to_map)

func show_pause_panel(v: bool) -> void:
	_pause_center.visible = v
	_refresh_scrim()
	if v:
		_pop_in(_pause_panel)

func _toggle_row(label_text: String, initial: bool, on_toggled: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := VisualTheme.label(label_text, 18, VisualTheme.TEXT_DIM, 0)
	label.custom_minimum_size = Vector2(240, 0)
	row.add_child(label)
	var toggle := CheckButton.new()
	toggle.button_pressed = initial
	toggle.toggled.connect(func(v):
		Audio.play(&"button_tap")
		on_toggled.call(v)
	)
	row.add_child(toggle)
	return row

func _slider_row(label_text: String, initial: float, on_changed: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := VisualTheme.label(label_text, 18, VisualTheme.TEXT_DIM, 0)
	label.custom_minimum_size = Vector2(240, 0)
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = initial
	slider.custom_minimum_size = Vector2(180, 0)
	slider.value_changed.connect(func(v): on_changed.call(v))
	row.add_child(slider)
	return row

# ----------------------------------------------------------- updates --

func set_level_info(level: LevelConfig) -> void:
	_level_label.text = level.level_name.to_upper()
	set_booster_armed(&"")

var _shown_score := 0
func set_score(v: int) -> void:
	if v == _shown_score:
		_score_label.text = _fmt(v)
		return
	var from := _shown_score
	_shown_score = v
	var t := create_tween()
	t.tween_method(func(x: float): _score_label.text = _fmt(int(round(x))), float(from), float(v), 0.35)

func _fmt(n: int) -> String:
	var s := str(n)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out

func set_moves(remaining: int) -> void:
	var r := maxi(remaining, 0)
	_moves_value.text = str(r)
	_moves_value.add_theme_color_override("font_color", VisualTheme.ACCENT_HOT if r <= 3 else VisualTheme.TEXT)
	_pulse(_moves_pill)

func set_coins(amount: int) -> void:
	if amount == _displayed_coins:
		_coins_label.text = str(amount)
		return
	var from := _displayed_coins
	_displayed_coins = amount
	var t := create_tween()
	t.tween_method(func(v: float): _coins_label.text = str(int(round(v))), float(from), float(amount), 0.4)

func set_objectives(tracker: ObjectiveTracker, level: LevelConfig) -> void:
	for c in _objective_chips:
		c.queue_free()
	_objective_chips.clear()
	for i in level.objectives.size():
		var obj: Dictionary = level.objectives[i]
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", 5)
		var icon := GemIcon.new()
		icon.custom_minimum_size = Vector2(22, 22)
		_style_obj_icon(icon, obj)
		chip.add_child(icon)
		var done: int = tracker.progress[i]
		var tgt: int = tracker.target_for(i)
		var txt := VisualTheme.label("%d/%d" % [mini(done, tgt), tgt], 19,
			VisualTheme.GOOD if done >= tgt else VisualTheme.TEXT)
		chip.add_child(txt)
		_objective_row.add_child(chip)
		_objective_chips.append(chip)

func _style_obj_icon(icon: GemIcon, obj: Dictionary) -> void:
	match String(obj.get("type", "")):
		"clear_color":
			icon.kind = &"gem"
			icon.tint = _color_for(String(obj.get("color", "red")))
		"reach_score":
			icon.kind = &"score"
		"create_powers":
			icon.kind = &"power"
		"break_obstacles":
			icon.kind = &"obstacle"
		_:
			icon.kind = &"gem"

func _color_for(id: String) -> Color:
	if GameData.colors != null and GameData.colors.has(StringName(id)):
		return GameData.colors.get_def(StringName(id)).base_color
	return Color(0.9, 0.3, 0.4)

func set_fever(meter: float, meter_max: float, active: bool) -> void:
	_fever_bar.max_value = meter_max
	var t := create_tween()
	t.tween_property(_fever_bar, "value", meter, 0.3).set_trans(Tween.TRANS_CUBIC)
	var fill: StyleBoxFlat = _fever_bar.get_theme_stylebox("fill")
	fill.bg_color = VisualTheme.FEVER_HOT if active else VisualTheme.FEVER
	_fever_label.text = "FEVER!" if active else "FEVER"
	_fever_label.add_theme_color_override("font_color", Color(1, 1, 1) if active else VisualTheme.TEXT_DIM)
	if active != _fever_running:
		_fever_running = active
		if _fever_pulse != null and _fever_pulse.is_valid():
			_fever_pulse.kill()
		if active:
			_fever_bar.value = _fever_bar.max_value
			_fever_wrap.pivot_offset = _fever_wrap.size * 0.5
			_fever_pulse = create_tween().set_loops()
			_fever_pulse.tween_property(_fever_wrap, "scale", Vector2(1.04, 1.12), 0.34).set_trans(Tween.TRANS_SINE)
			_fever_pulse.tween_property(_fever_wrap, "scale", Vector2.ONE, 0.34).set_trans(Tween.TRANS_SINE)
		else:
			_fever_wrap.scale = Vector2.ONE
	elif active:
		_fever_bar.value = _fever_bar.max_value

## A one-off wallop the instant Fever ignites: the meter flares white and
## the whole strip kicks.
func flash_fever() -> void:
	_fever_wrap.pivot_offset = _fever_wrap.size * 0.5
	var fill: StyleBoxFlat = _fever_bar.get_theme_stylebox("fill")
	fill.bg_color = Color(1, 1, 1)
	var t := create_tween()
	t.tween_property(_fever_wrap, "scale", Vector2(1.25, 1.4), 0.12).set_trans(Tween.TRANS_BACK)
	t.tween_property(_fever_wrap, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_ELASTIC)
	t.parallel().tween_method(func(v: float): fill.bg_color = Color(1, 1, 1).lerp(VisualTheme.FEVER_HOT, v), 0.0, 1.0, 0.4)

func set_booster_counts(counts: Dictionary) -> void:
	for id in _booster_badges.keys():
		var n := int(counts.get(id, 0))
		var prev := int(_booster_counts.get(id, 0))
		_booster_counts[id] = n
		_booster_badges[id].text = str(n)
		var slot: Control = _booster_slots[id]
		slot.modulate.a = 1.0 if n > 0 else 0.42
		var chip = slot.get_child(0)
		chip.enabled = n > 0
		chip.queue_redraw()
		if n > prev:
			flash_booster(id)

func show_win_panel(score: int, reward_coins: int, has_next_level: bool, stars: int) -> void:
	_end_title.text = "Level Complete!"
	_end_body.text = "Score  %d\n+%d coins" % [score, reward_coins]
	_end_button.text = "Next Level" if has_next_level else "Back to Map"
	_end_map_button.visible = true
	_rewire(_end_button, func(): next_level_pressed.emit())
	_end_center.visible = true
	_refresh_scrim()
	_pop_in(_end_panel)
	_end_stars.play(stars)
	_end_confetti.restart()
	_end_confetti.emitting = true

func show_lose_panel(score: int) -> void:
	_end_title.text = "So Close!"
	_end_body.text = "Score  %d\nTry again — you've got this!" % score
	_end_button.text = "Try Again"
	_end_map_button.visible = true
	_rewire(_end_button, func(): retry_pressed.emit())
	_end_center.visible = true
	_refresh_scrim()
	_pop_in(_end_panel)
	_end_stars.play(0)

func hide_end_panel() -> void:
	_end_center.visible = false
	_refresh_scrim()

func _rewire(btn: Button, fn: Callable) -> void:
	for c in btn.pressed.get_connections():
		btn.pressed.disconnect(c["callable"])
	btn.pressed.connect(func():
		Audio.play(&"button_tap")
		fn.call()
	)

# ------------------------------------------------------------ anims --

func _pop_in(node: Control) -> void:
	node.pivot_offset = node.size * 0.5
	node.scale = Vector2(0.8, 0.8)
	node.modulate.a = 0.0
	var t := node.create_tween()
	t.set_parallel(true)
	t.tween_property(node, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(node, "modulate:a", 1.0, 0.2)

func _pulse(node: Control, amount: float = 1.08) -> void:
	if node == null:
		return
	node.pivot_offset = node.size * 0.5
	var t := node.create_tween()
	t.tween_property(node, "scale", Vector2(amount, amount), 0.09).set_trans(Tween.TRANS_SINE)
	t.tween_property(node, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_SINE)


## One booster tray chip: glossy rounded face in its tint, a code-drawn
## IconDraw glyph, an armed glow-pulse, and a lock overlay when empty.
class BoosterChip extends Control:
	var tint: Color = Color(0.5, 0.5, 0.5)
	var booster_id: StringName = &"bomb"
	var armed := false
	var enabled := true
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(true)

	func _process(delta: float) -> void:
		_t += delta
		if armed:
			queue_redraw()

	func _draw() -> void:
		var rr := 16.0
		var rect := Rect2(Vector2(3, 3), size - Vector2(6, 6))
		if armed:
			var p := 0.5 + 0.5 * sin(_t * 8.0)
			_round(rect.grow(4.0 + 3.0 * p), rr + 4, Color(tint.r, tint.g, tint.b, 0.35 + 0.35 * p))
		# body: darker base + lighter top band
		_round(rect, rr, tint.darkened(0.32))
		_round(Rect2(rect.position, Vector2(rect.size.x, rect.size.y * 0.5)), rr, tint.lightened(0.05))
		_round(rect.grow(-2.0), rr - 2, tint.darkened(0.12))
		# top gloss
		draw_line(rect.position + Vector2(10, 4), rect.position + Vector2(rect.size.x - 10, 4),
			Color(1, 1, 1, 0.28), 2.0, true)
		var c := size * 0.5
		IconDraw.draw_icon(self, booster_id, c - Vector2(0, size.y * 0.06), minf(size.x, size.y) * 0.62, _t)
		if not enabled:
			_round(rect, rr, Color(0.04, 0.05, 0.09, 0.55))
			draw_arc(c + Vector2(0, -2), size.x * 0.13, PI, TAU, 12, Color(0.8, 0.82, 0.9), 3.0, true)
			draw_rect(Rect2(c + Vector2(-size.x * 0.13, -2), Vector2(size.x * 0.26, size.y * 0.18)), Color(0.8, 0.82, 0.9))

	func _round(r: Rect2, radius: float, col: Color) -> void:
		var pts := ShapeDrawUtils.rounded_rect_points(r.size, radius, 5)
		var moved := PackedVector2Array()
		for p in pts:
			moved.append(p + r.position + r.size * 0.5)
		draw_colored_polygon(moved, col)


## Code-drawn chrome glyph (pause / gear) — avoids missing font glyphs.
class MiniIcon extends Control:
	var kind: StringName = &"pause"

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.26
		match kind:
			&"pause":
				var w := r * 0.5
				draw_rect(Rect2(c + Vector2(-r, -r), Vector2(w, r * 2.0)), VisualTheme.TEXT)
				draw_rect(Rect2(c + Vector2(r - w, -r), Vector2(w, r * 2.0)), VisualTheme.TEXT)
			&"gear":
				draw_arc(c, r, 0, TAU, 24, VisualTheme.TEXT, maxf(r * 0.42, 2.0), true)
				for i in 8:
					var a := TAU * float(i) / 8.0
					draw_line(c + Vector2(cos(a), sin(a)) * r * 0.9,
						c + Vector2(cos(a), sin(a)) * r * 1.5, VisualTheme.TEXT, maxf(r * 0.3, 2.0), true)
				draw_circle(c, r * 0.4, VisualTheme.PANEL_RAISED)
			_:
				draw_circle(c, r, VisualTheme.TEXT)


## Small code-drawn gem / icon used in the coin pill and objective chips.
class GemIcon extends Control:
	var kind: StringName = &"gem" # gem | coin | score | power | obstacle
	var tint: Color = Color(0.9, 0.3, 0.4)

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.46
		match kind:
			&"coin":
				draw_circle(c, r, VisualTheme.COIN)
				draw_circle(c, r * 0.72, VisualTheme.COIN.lightened(0.25))
				draw_arc(c, r, 0, TAU, 20, VisualTheme.COIN.darkened(0.3), 2.0, true)
			&"score":
				draw_colored_polygon(ShapeDrawUtils.star_points(c, r), VisualTheme.STAR)
			&"power":
				var hex := ShapeDrawUtils.regular_polygon(6, r, PI / 6.0, c)
				draw_colored_polygon(hex, Color(1, 0.85, 0.3))
				draw_line(c + Vector2(-r * 0.2, -r * 0.5), c + Vector2(r * 0.1, r * 0.05), Color(0.1, 0.1, 0.12), 3.0)
				draw_line(c + Vector2(r * 0.1, r * 0.05), c + Vector2(-r * 0.1, r * 0.5), Color(0.1, 0.1, 0.12), 3.0)
			&"obstacle":
				draw_colored_polygon(ShapeDrawUtils.regular_polygon(6, r, PI / 6.0, c), Color(0.5, 0.55, 0.62))
				draw_arc(c, r * 0.9, 0, TAU, 18, Color(0.2, 0.22, 0.26), 2.0, true)
			_:
				var g := ShapeDrawUtils.regular_polygon(6, r, PI / 6.0, c)
				draw_polygon(g, ShapeDrawUtils.vertical_shade(g, tint.lightened(0.3), tint.darkened(0.35)))
				draw_circle(c + Vector2(-r * 0.25, -r * 0.3), r * 0.22, Color(1, 1, 1, 0.6))


## Three stars that pop in one-by-one on a win.
class StarRow extends Control:
	var _earned := 0
	var _shown := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(false)

	func play(earned: int) -> void:
		_earned = earned
		_shown = 0.0
		set_process(true)
		var t := create_tween()
		t.tween_method(func(v: float): _shown = v; queue_redraw(), 0.0, 3.0, 0.9)
		t.tween_callback(func(): set_process(false))

	func _draw() -> void:
		var cx := size.x * 0.5
		var cy := size.y * 0.5
		var spacing := 66.0
		for i in 3:
			var center := Vector2(cx + float(i - 1) * spacing, cy)
			var filled := float(i) < _shown and i < _earned
			var grow: float = clampf(_shown - float(i), 0.0, 1.0)
			var r := 24.0 * (0.4 + 0.6 * grow) if float(i) < _shown else 20.0
			if not (float(i) < _shown):
				grow = 1.0
				r = 20.0
			draw_colored_polygon(ShapeDrawUtils.star_points(center, r + 3.0),
				Color(0, 0, 0, 0.35))
			var col := VisualTheme.STAR if filled else Color(0.24, 0.25, 0.32)
			draw_colored_polygon(ShapeDrawUtils.star_points(center, r), col)
			if filled:
				draw_colored_polygon(ShapeDrawUtils.star_points(center, r * 0.5),
					VisualTheme.STAR.lightened(0.4))
