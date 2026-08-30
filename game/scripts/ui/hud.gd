class_name HUD
extends Control
## Mobile-first HUD: top bar (level/objective/moves/coins + Fever meter),
## bottom booster bar, and win/lose overlays. Built entirely in code so the
## layout stays anchor-driven (scales with any portrait resolution) rather
## than relying on fixed pixel positions. The board sits beneath this
## layer; only the top/bottom strips and popups intercept touch input.

signal booster_pressed(booster_id: StringName)
signal next_level_pressed()
signal retry_pressed()

var _level_label: Label
var _objective_labels: Array[Label] = []
var _objective_box: VBoxContainer
var _moves_label: Label
var _coins_label: Label
var _fever_bar: ProgressBar
var _booster_buttons: Dictionary = {} # StringName -> Button
var _booster_count_labels: Dictionary = {} # StringName -> Label
var _end_panel: PanelContainer
var _end_title: Label
var _end_body: Label
var _end_button: Button
var _settings_panel: PanelContainer

const _BOOSTER_ICONS := {
	&"bomb": "💣", &"lightning": "⚡", &"rainbow": "🌈", &"shuffle": "🔀", &"extra_moves": "➕",
}

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_top_bar()
	_build_booster_bar()
	_build_end_panel()
	_build_settings_panel()

func _panel_style(bg: Color, border: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.corner_radius_top_left = 18
	sb.corner_radius_top_right = 18
	sb.corner_radius_bottom_left = 18
	sb.corner_radius_bottom_right = 18
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	if border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(2)
	return sb

func _build_top_bar() -> void:
	var top := PanelContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_top = 24
	top.offset_left = 16
	top.offset_right = -16
	top.add_theme_stylebox_override("panel", _panel_style(Color(0.06, 0.07, 0.12, 0.88)))
	add_child(top)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	top.add_child(vbox)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	vbox.add_child(row)

	_level_label = _make_label("Level 1", 26, Color(1, 1, 1))
	row.add_child(_level_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	_moves_label = _make_label("Moves: 20", 22, Color(0.85, 0.9, 1))
	row.add_child(_moves_label)

	_coins_label = _make_label("🪙 0", 22, Color(1, 0.85, 0.3))
	row.add_child(_coins_label)

	var settings_btn := Button.new()
	settings_btn.text = "⚙"
	settings_btn.custom_minimum_size = Vector2(40, 40)
	settings_btn.add_theme_font_size_override("font_size", 20)
	settings_btn.pressed.connect(func():
		Audio.play(&"button_tap")
		_settings_panel.visible = true
	)
	row.add_child(settings_btn)

	_objective_box = VBoxContainer.new()
	_objective_box.add_theme_constant_override("separation", 2)
	vbox.add_child(_objective_box)

	_fever_bar = ProgressBar.new()
	_fever_bar.min_value = 0
	_fever_bar.max_value = 100
	_fever_bar.value = 0
	_fever_bar.show_percentage = false
	_fever_bar.custom_minimum_size = Vector2(0, 14)
	var fg := StyleBoxFlat.new()
	fg.bg_color = Color(1, 0.55, 0.15)
	fg.corner_radius_top_left = 7
	fg.corner_radius_top_right = 7
	fg.corner_radius_bottom_left = 7
	fg.corner_radius_bottom_right = 7
	_fever_bar.add_theme_stylebox_override("fill", fg)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.15, 0.15, 0.2)
	bg.corner_radius_top_left = 7
	bg.corner_radius_top_right = 7
	bg.corner_radius_bottom_left = 7
	bg.corner_radius_bottom_right = 7
	_fever_bar.add_theme_stylebox_override("background", bg)
	vbox.add_child(_fever_bar)

func _make_label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _build_booster_bar() -> void:
	var bottom := PanelContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_bottom = -24
	bottom.offset_left = 16
	bottom.offset_right = -16
	bottom.add_theme_stylebox_override("panel", _panel_style(Color(0.06, 0.07, 0.12, 0.88)))
	add_child(bottom)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	bottom.add_child(row)

	for id in _BOOSTER_ICONS.keys():
		var cell := VBoxContainer.new()
		cell.alignment = BoxContainer.ALIGNMENT_CENTER
		var btn := Button.new()
		btn.text = _BOOSTER_ICONS[id]
		btn.custom_minimum_size = Vector2(64, 64)
		btn.add_theme_font_size_override("font_size", 28)
		btn.pressed.connect(func():
			Audio.play(&"button_tap")
			booster_pressed.emit(id)
		)
		cell.add_child(btn)
		var count_label := _make_label("0", 16, Color(0.9, 0.9, 0.9))
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(count_label)
		row.add_child(cell)
		_booster_buttons[id] = btn
		_booster_count_labels[id] = count_label

func _build_end_panel() -> void:
	_end_panel = PanelContainer.new()
	_end_panel.set_anchors_preset(Control.PRESET_CENTER)
	_end_panel.custom_minimum_size = Vector2(420, 260)
	_end_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.08, 0.08, 0.16, 0.97), Color(1, 1, 1, 0.15)))
	_end_panel.visible = false
	add_child(_end_panel)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	_end_panel.add_child(vbox)

	_end_title = _make_label("Level Complete!", 32, Color(1, 0.85, 0.3))
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_end_title)

	_end_body = _make_label("", 20, Color(1, 1, 1))
	_end_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_end_body)

	_end_button = Button.new()
	_end_button.text = "Continue"
	_end_button.custom_minimum_size = Vector2(180, 56)
	_end_button.add_theme_font_size_override("font_size", 22)
	vbox.add_child(_end_button)

func _build_settings_panel() -> void:
	_settings_panel = PanelContainer.new()
	_settings_panel.set_anchors_preset(Control.PRESET_CENTER)
	_settings_panel.custom_minimum_size = Vector2(460, 420)
	_settings_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.08, 0.08, 0.16, 0.97), Color(1, 1, 1, 0.15)))
	_settings_panel.visible = false
	_settings_panel.z_index = 200
	add_child(_settings_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	_settings_panel.add_child(vbox)

	var title := _make_label("Settings", 28, Color(1, 1, 1))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	vbox.add_child(_make_toggle_row("Music", AudioSettings.music_enabled, func(v): AudioSettings.set_music_enabled(v)))
	vbox.add_child(_make_toggle_row("Sound Effects", AudioSettings.sfx_enabled, func(v): AudioSettings.set_sfx_enabled(v)))
	vbox.add_child(_make_toggle_row("Haptics", AudioSettings.haptics_enabled, func(v): AudioSettings.set_haptics_enabled(v)))
	vbox.add_child(_make_slider_row("Master Volume", AudioSettings.master_volume, func(v): AudioSettings.set_master_volume(v)))
	vbox.add_child(_make_slider_row("Music Volume", AudioSettings.music_volume, func(v): AudioSettings.set_music_volume(v)))
	vbox.add_child(_make_slider_row("SFX Volume", AudioSettings.sfx_volume, func(v): AudioSettings.set_sfx_volume(v)))

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(160, 48)
	close_btn.pressed.connect(func():
		Audio.play(&"button_tap")
		_settings_panel.visible = false
	)
	vbox.add_child(close_btn)

func _make_toggle_row(label_text: String, initial: bool, on_toggled: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := _make_label(label_text, 18, Color(0.9, 0.92, 1))
	label.custom_minimum_size = Vector2(220, 0)
	row.add_child(label)
	var toggle := CheckButton.new()
	toggle.button_pressed = initial
	toggle.toggled.connect(func(v):
		Audio.play(&"button_tap")
		on_toggled.call(v)
	)
	row.add_child(toggle)
	return row

func _make_slider_row(label_text: String, initial: float, on_changed: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := _make_label(label_text, 18, Color(0.9, 0.92, 1))
	label.custom_minimum_size = Vector2(220, 0)
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = initial
	slider.custom_minimum_size = Vector2(160, 0)
	slider.value_changed.connect(func(v): on_changed.call(v))
	row.add_child(slider)
	return row

# ------------------------------------------------------------- updates --

func set_level_info(level: LevelConfig) -> void:
	_level_label.text = level.level_name

func set_moves(remaining: int) -> void:
	_moves_label.text = "Moves: %d" % max(remaining, 0)

func set_coins(amount: int) -> void:
	_coins_label.text = "🪙 %d" % amount

func set_objectives(tracker: ObjectiveTracker, level: LevelConfig) -> void:
	for l in _objective_labels:
		l.queue_free()
	_objective_labels.clear()
	for i in level.objectives.size():
		var obj: Dictionary = level.objectives[i]
		var desc := _describe_objective(obj)
		var label := _make_label("%s  %d / %d" % [desc, tracker.progress[i], tracker.target_for(i)], 18, Color(0.85, 0.95, 1))
		_objective_box.add_child(label)
		_objective_labels.append(label)

func _describe_objective(obj: Dictionary) -> String:
	match String(obj.get("type", "")):
		"clear_color":
			return "Clear %s" % String(obj.get("color", "")).capitalize()
		"reach_score":
			return "Score"
		"create_powers":
			return "Create Powers"
		"break_obstacles":
			return "Break Obstacles"
		_:
			return "Objective"

func set_fever(meter: float, meter_max: float, active: bool) -> void:
	_fever_bar.max_value = meter_max
	_fever_bar.value = meter
	var fg: StyleBoxFlat = _fever_bar.get_theme_stylebox("fill")
	fg.bg_color = Color(1, 0.25, 0.55) if active else Color(1, 0.55, 0.15)

func set_booster_counts(counts: Dictionary) -> void:
	for id in _booster_count_labels.keys():
		_booster_count_labels[id].text = str(int(counts.get(id, 0)))

func show_win_panel(score: int, reward_coins: int, has_next_level: bool) -> void:
	_end_title.text = "Level Complete!"
	_end_body.text = "Score: %d\n+%d coins" % [score, reward_coins]
	_end_button.text = "Next Level" if has_next_level else "Back to Map"
	for c in _end_button.pressed.get_connections():
		_end_button.pressed.disconnect(c["callable"])
	_end_button.pressed.connect(func():
		Audio.play(&"button_tap")
		next_level_pressed.emit()
	)
	_end_panel.visible = true

func show_lose_panel(score: int) -> void:
	# Keep this encouraging, not punishing — "so close", not "you failed".
	_end_title.text = "So Close!"
	_end_body.text = "Score: %d\nTry again — you've got this!" % score
	_end_button.text = "Try Again"
	for c in _end_button.pressed.get_connections():
		_end_button.pressed.disconnect(c["callable"])
	_end_button.pressed.connect(func():
		Audio.play(&"button_tap")
		retry_pressed.emit()
	)
	_end_panel.visible = true

func hide_end_panel() -> void:
	_end_panel.visible = false
