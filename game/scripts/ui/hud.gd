class_name HUD
extends Control
## Mobile-first HUD: top bar (nav/score, moves/level/coins, goal chips,
## Fever meter), bottom booster tray, and win/lose overlays. Built entirely
## in code so the layout stays anchor-driven (scales with any portrait
## resolution) rather than relying on fixed pixel positions. The board sits
## beneath this layer; only the top/bottom strips and popups intercept
## touch input.
##
## Sizing follows a deliberate hierarchy: a big bold VALUE (score, moves,
## coins, level number) always outranks its small caption label, so a
## player can read what matters at a glance without zooming in.

signal booster_pressed(booster_id: StringName)
signal next_level_pressed()
signal retry_pressed()
signal map_pressed()

var _level_value: Label
var _score_value: Label
var _objective_labels: Array[Control] = []
var _objective_box: VBoxContainer
var _moves_value: Label
var _coins_value: Label
var _fever_bar: ProgressBar
var _fever_label: Label
var _booster_buttons: Dictionary = {} # StringName -> Button
var _booster_count_labels: Dictionary = {} # StringName -> Label
var _end_panel: PanelContainer
var _end_title: Label
var _end_stars: Label
var _end_body: Label
var _end_button: Button
var _end_map_button: Button
var _settings_panel: PanelContainer

const _BOOSTER_ICONS := {
	&"bomb": "💣", &"lightning": "⚡", &"rainbow": "🌈", &"shuffle": "🔀", &"extra_moves": "➕",
}
const _BOOSTER_ACCENTS := {
	&"bomb": Color(1.0, 0.5, 0.28), &"lightning": Color(1.0, 0.86, 0.25),
	&"rainbow": Color(0.78, 0.45, 0.95), &"shuffle": Color(0.35, 0.68, 1.0),
	&"extra_moves": Color(0.38, 0.86, 0.56),
}
## Minimum comfortable Android touch target (Material Design guidance ~48dp;
## our design canvas maps close to 1:1 with dp at typical densities).
const _MIN_TOUCH := Vector2(64, 64)

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_top_bar()
	_build_booster_bar()
	_build_end_panel()
	_build_settings_panel()

func _panel_style(bg: Color, border: Color = Color(0, 0, 0, 0), radius: int = 26) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 10
	if border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(2)
	return sb

func _icon_button(icon: String, font_size: int) -> Button:
	var btn := Button.new()
	btn.text = icon
	btn.custom_minimum_size = _MIN_TOUCH
	btn.add_theme_font_size_override("font_size", font_size)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.08)
	sb.set_corner_radius_all(18)
	sb.set_border_width_all(2)
	sb.border_color = Color(1, 1, 1, 0.18)
	btn.add_theme_stylebox_override("normal", sb)
	var sb_hover := sb.duplicate()
	sb_hover.bg_color = Color(1, 1, 1, 0.16)
	btn.add_theme_stylebox_override("hover", sb_hover)
	btn.add_theme_stylebox_override("pressed", sb_hover)
	return btn

## A caption+value "stat block": a small muted label above a large bold
## number, so the value always reads first. Returns the value Label to update.
func _make_stat_block(caption: String, value_text: String, value_size: int, value_color: Color, align: int = HORIZONTAL_ALIGNMENT_CENTER) -> Dictionary:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var cap := _make_label(caption, 13, Color(0.72, 0.78, 0.9))
	cap.horizontal_alignment = align
	box.add_child(cap)
	var value := _make_label(value_text, value_size, value_color)
	value.horizontal_alignment = align
	box.add_child(value)
	return {"box": box, "value": value}

func _build_top_bar() -> void:
	var top := PanelContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_top = 20
	top.offset_left = 14
	top.offset_right = -14
	top.add_theme_stylebox_override("panel", _panel_style(Color(0.06, 0.07, 0.12, 0.94)))
	add_child(top)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	top.add_child(vbox)

	# Row 1: nav + big centered score.
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 12)
	vbox.add_child(row1)

	var map_btn := _icon_button("🗺", 28)
	map_btn.pressed.connect(func():
		Audio.play(&"button_tap")
		map_pressed.emit()
	)
	row1.add_child(map_btn)

	var spacer1 := Control.new()
	spacer1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row1.add_child(spacer1)

	var score_block := _make_stat_block("SCORE", "0", 36, Color(1, 0.86, 0.3))
	_score_value = score_block["value"]
	row1.add_child(score_block["box"])

	var spacer2 := Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row1.add_child(spacer2)

	var settings_btn := _icon_button("⚙", 28)
	settings_btn.pressed.connect(func():
		Audio.play(&"button_tap")
		_settings_panel.visible = true
	)
	row1.add_child(settings_btn)

	# Row 2: moves | level | coins.
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 12)
	vbox.add_child(row2)

	var moves_block := _make_stat_block("MOVES", "20", 30, Color(0.85, 0.92, 1), HORIZONTAL_ALIGNMENT_LEFT)
	_moves_value = moves_block["value"]
	row2.add_child(moves_block["box"])

	var row2_spacer1 := Control.new()
	row2_spacer1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(row2_spacer1)

	var level_block := _make_stat_block("LEVEL", "1", 26, Color(1, 1, 1))
	_level_value = level_block["value"]
	row2.add_child(level_block["box"])

	var row2_spacer2 := Control.new()
	row2_spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(row2_spacer2)

	var coins_block := _make_stat_block("COINS", "🪙 0", 26, Color(1, 0.85, 0.3), HORIZONTAL_ALIGNMENT_RIGHT)
	_coins_value = coins_block["value"]
	row2.add_child(coins_block["box"])

	# Row 3: goal chips.
	_objective_box = VBoxContainer.new()
	_objective_box.add_theme_constant_override("separation", 6)
	vbox.add_child(_objective_box)

	# Row 4: Fever meter.
	var fever_wrap := Control.new()
	fever_wrap.custom_minimum_size = Vector2(0, 26)
	vbox.add_child(fever_wrap)

	_fever_bar = ProgressBar.new()
	_fever_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fever_bar.min_value = 0
	_fever_bar.max_value = 100
	_fever_bar.value = 0
	_fever_bar.show_percentage = false
	var fg := StyleBoxFlat.new()
	fg.bg_color = Color(1, 0.55, 0.15)
	fg.set_corner_radius_all(13)
	_fever_bar.add_theme_stylebox_override("fill", fg)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.15, 0.15, 0.2)
	bg.set_corner_radius_all(13)
	_fever_bar.add_theme_stylebox_override("background", bg)
	fever_wrap.add_child(_fever_bar)

	_fever_label = _make_label("FEVER", 13, Color(1, 1, 1))
	_fever_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fever_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fever_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_fever_label.add_theme_constant_override("outline_size", 3)
	_fever_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	fever_wrap.add_child(_fever_label)

func _make_label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _build_booster_bar() -> void:
	var bottom := PanelContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_bottom = -20
	bottom.offset_left = 14
	bottom.offset_right = -14
	bottom.add_theme_stylebox_override("panel", _panel_style(Color(0.06, 0.07, 0.12, 0.94)))
	add_child(bottom)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	bottom.add_child(row)

	for id in _BOOSTER_ICONS.keys():
		var cell := VBoxContainer.new()
		cell.alignment = BoxContainer.ALIGNMENT_CENTER
		cell.add_theme_constant_override("separation", 4)

		var btn := Button.new()
		btn.text = _BOOSTER_ICONS[id]
		btn.custom_minimum_size = Vector2(92, 92)
		btn.add_theme_font_size_override("font_size", 40)
		btn.pressed.connect(func():
			Audio.play(&"button_tap")
			booster_pressed.emit(id)
		)
		cell.add_child(btn)

		var count_pill := PanelContainer.new()
		var pill_sb := StyleBoxFlat.new()
		pill_sb.bg_color = Color(0, 0, 0, 0.4)
		pill_sb.set_corner_radius_all(10)
		pill_sb.content_margin_left = 10
		pill_sb.content_margin_right = 10
		pill_sb.content_margin_top = 2
		pill_sb.content_margin_bottom = 2
		count_pill.add_theme_stylebox_override("panel", pill_sb)
		var count_label := _make_label("0", 20, Color(1, 1, 1))
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count_pill.add_child(count_label)
		cell.add_child(count_pill)

		row.add_child(cell)
		_booster_buttons[id] = btn
		_booster_count_labels[id] = count_label
		_style_booster_card(id, false)

## Available (count > 0, ready to use) reads as a bright, colorful card;
## unavailable (tap-to-buy) reads as a dimmed, muted card so the two states
## are unmistakable at a glance.
func _style_booster_card(id: StringName, available: bool) -> void:
	var btn: Button = _booster_buttons[id]
	var accent: Color = _BOOSTER_ACCENTS.get(id, Color(0.6, 0.6, 0.7))
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(20)
	sb.set_border_width_all(3)
	if available:
		sb.bg_color = Color(accent.r, accent.g, accent.b, 0.28)
		sb.border_color = accent
		btn.modulate = Color(1, 1, 1, 1)
	else:
		sb.bg_color = Color(0.14, 0.14, 0.18, 0.85)
		sb.border_color = Color(1, 1, 1, 0.12)
		btn.modulate = Color(1, 1, 1, 0.55)
	for state_name in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(state_name, sb)

func _build_end_panel() -> void:
	_end_panel = PanelContainer.new()
	_end_panel.set_anchors_preset(Control.PRESET_CENTER)
	_end_panel.custom_minimum_size = Vector2(560, 420)
	_end_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.08, 0.08, 0.16, 0.98), Color(1, 1, 1, 0.18), 30))
	_end_panel.visible = false
	_end_panel.z_index = 200
	add_child(_end_panel)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	_end_panel.add_child(vbox)

	_end_title = _make_label("Level Complete!", 40, Color(1, 0.85, 0.3))
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_end_title)

	_end_stars = _make_label("", 46, Color(1, 0.85, 0.2))
	_end_stars.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_end_stars)

	_end_body = _make_label("", 24, Color(1, 1, 1))
	_end_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_end_body)

	_end_button = Button.new()
	_end_button.text = "Continue"
	_end_button.custom_minimum_size = Vector2(280, 72)
	_end_button.add_theme_font_size_override("font_size", 26)
	vbox.add_child(_end_button)

	_end_map_button = Button.new()
	_end_map_button.text = "Level Map"
	_end_map_button.custom_minimum_size = Vector2(280, 60)
	_end_map_button.add_theme_font_size_override("font_size", 20)
	_end_map_button.pressed.connect(func():
		Audio.play(&"button_tap")
		map_pressed.emit()
	)
	vbox.add_child(_end_map_button)

func _build_settings_panel() -> void:
	_settings_panel = PanelContainer.new()
	_settings_panel.set_anchors_preset(Control.PRESET_CENTER)
	_settings_panel.custom_minimum_size = Vector2(640, 560)
	_settings_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.08, 0.08, 0.16, 0.98), Color(1, 1, 1, 0.18), 30))
	_settings_panel.visible = false
	_settings_panel.z_index = 200
	add_child(_settings_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	_settings_panel.add_child(vbox)

	var title := _make_label("Settings", 36, Color(1, 1, 1))
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
	close_btn.custom_minimum_size = Vector2(240, 68)
	close_btn.add_theme_font_size_override("font_size", 24)
	close_btn.pressed.connect(func():
		Audio.play(&"button_tap")
		_settings_panel.visible = false
	)
	vbox.add_child(close_btn)

func _make_toggle_row(label_text: String, initial: bool, on_toggled: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 56)
	row.add_theme_constant_override("separation", 16)
	var label := _make_label(label_text, 24, Color(0.92, 0.94, 1))
	label.custom_minimum_size = Vector2(300, 0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	var toggle := CheckButton.new()
	toggle.button_pressed = initial
	toggle.scale = Vector2(1.5, 1.5)
	toggle.toggled.connect(func(v):
		Audio.play(&"button_tap")
		on_toggled.call(v)
	)
	row.add_child(toggle)
	return row

func _make_slider_row(label_text: String, initial: float, on_changed: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 48)
	row.add_theme_constant_override("separation", 16)
	var label := _make_label(label_text, 20, Color(0.92, 0.94, 1))
	label.custom_minimum_size = Vector2(260, 0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = initial
	slider.custom_minimum_size = Vector2(0, 44)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(v): on_changed.call(v))
	row.add_child(slider)
	return row

# ------------------------------------------------------------- updates --

func set_level_info(level: LevelConfig) -> void:
	_level_value.text = str(level.id)

func set_moves(remaining: int) -> void:
	_moves_value.text = str(max(remaining, 0))

func set_score(score: int) -> void:
	_score_value.text = str(score)

func set_coins(amount: int) -> void:
	_coins_value.text = "🪙 %d" % amount

func set_objectives(tracker: ObjectiveTracker, level: LevelConfig) -> void:
	for c in _objective_labels:
		c.queue_free()
	_objective_labels.clear()
	for i in level.objectives.size():
		var obj: Dictionary = level.objectives[i]
		var desc := _describe_objective(obj)
		var chip := _make_objective_chip(desc, tracker.progress[i], tracker.target_for(i))
		_objective_box.add_child(chip)
		_objective_labels.append(chip)

## A rounded "goal" chip whose progress numbers are bold and noticeably
## larger than the label, so the important part (how close am I) reads
## first — matches the stat-block hierarchy used elsewhere in the HUD.
func _make_objective_chip(desc: String, progress: int, target: int) -> PanelContainer:
	var chip := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.06)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	chip.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	chip.add_child(row)

	var label := _make_label(desc, 18, Color(0.85, 0.9, 1))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var complete := progress >= target
	var progress_label := _make_label("%d / %d" % [progress, target], 24, Color(0.55, 0.95, 0.65) if complete else Color(1, 0.85, 0.3))
	row.add_child(progress_label)
	return chip

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
	_fever_label.text = "FEVER x1.5!" if active else "FEVER"

func set_booster_counts(counts: Dictionary) -> void:
	for id in _booster_count_labels.keys():
		var count := int(counts.get(id, 0))
		_booster_count_labels[id].text = str(count)
		_style_booster_card(id, count > 0)

func show_win_panel(score: int, reward_coins: int, has_next_level: bool, stars: int) -> void:
	_end_title.text = "Level Complete!"
	_end_stars.text = _star_text(stars)
	_end_body.text = "Score: %d\n+%d coins" % [score, reward_coins]
	_end_button.text = "Next Level" if has_next_level else "Back to Map"
	_end_map_button.visible = true
	for c in _end_button.pressed.get_connections():
		_end_button.pressed.disconnect(c["callable"])
	_end_button.pressed.connect(func():
		Audio.play(&"button_tap")
		next_level_pressed.emit()
	)
	_end_panel.visible = true

func _star_text(stars: int) -> String:
	var out := ""
	for i in 3:
		out += "★" if i < stars else "☆"
	return out

func show_lose_panel(score: int) -> void:
	# Keep this encouraging, not punishing — "so close", not "you failed".
	_end_title.text = "So Close!"
	_end_stars.text = ""
	_end_body.text = "Score: %d\nTry again — you've got this!" % score
	_end_button.text = "Try Again"
	_end_map_button.visible = true
	for c in _end_button.pressed.get_connections():
		_end_button.pressed.disconnect(c["callable"])
	_end_button.pressed.connect(func():
		Audio.play(&"button_tap")
		retry_pressed.emit()
	)
	_end_panel.visible = true

func hide_end_panel() -> void:
	_end_panel.visible = false
