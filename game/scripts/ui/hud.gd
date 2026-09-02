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

var _level_label: LevelBadge
var _score_label: Label
var _moves_value: Label
var _moves_pill: PanelContainer
var _objective_row: HBoxContainer
var _objective_chips: Array[Node] = []
var _coins_label: Label
var _fever_bar: FeverArt
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
var _fx: SpriteFX
var _end_crown: TextureRect

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
var _top_col: VBoxContainer
var _bottom_col: VBoxContainer

## The booster-tray column is anchored to the screen bottom and END-aligns
## its content, so it needs to be at least as tall as that content. The
## actual space the board must avoid is `playfield_bottom()` (measured from
## the real tray contents), which is smaller.
const TRAY_COL_HEIGHT := 380.0
## Height (viewport units) the tray content occupies inside that column:
## hint line + separator + tray panel (margins + one 214-tall chip row).
const TRAY_CONTENT_HEIGHT := 300.0
## Some Android gesture-nav devices report a full-height safe area (no bottom
## inset) yet still overlay a gesture pill — keep at least this much clear.
const MIN_BOTTOM_CLEARANCE := 56.0

## Y (viewport units) below which the playfield may start — just under the
## top HUD column. app.gd fits the board between this and `playfield_bottom`.
func playfield_top() -> float:
	var top := maxf(_safe_top, VisualTheme.STATUS_BAR_MIN) + 24.0
	var col_h := 264.0
	if _top_col != null:
		var m := _top_col.get_combined_minimum_size().y
		if m > 40.0:
			col_h = m
	return top + col_h + 14.0

## Space (viewport units) to keep clear at the bottom for the booster tray —
## the gap from the screen bottom up to the top of the tray's contents.
func playfield_bottom() -> float:
	return maxf(_safe_bottom, MIN_BOTTOM_CLEARANCE) + 12.0 + TRAY_CONTENT_HEIGHT

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
	_fx = SpriteFX.new()
	_fx.z_index = 300
	add_child(_fx)
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
		_top_margin.add_theme_constant_override("margin_top", int(maxf(_safe_top, VisualTheme.STATUS_BAR_MIN) + 24.0))
	if _bottom_col != null:
		_bottom_col.offset_top = -TRAY_COL_HEIGHT
		_bottom_col.offset_bottom = -int(maxf(_safe_bottom, MIN_BOTTOM_CLEARANCE) + 12.0)

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
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", int(maxf(_safe_top, VisualTheme.STATUS_BAR_MIN) + 24.0))
	_top_margin = margin
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	_top_col = col
	margin.add_child(col)

	# --- row 1: pause | LEVEL + SCORE | gear ------------------------------
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 12)
	col.add_child(row1)

	var pause_btn := _icon_button(&"pause", 68)
	pause_btn.pressed.connect(func():
		Audio.play(&"button_tap")
		pause_pressed.emit()
	)
	row1.add_child(pause_btn)

	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.alignment = BoxContainer.ALIGNMENT_CENTER
	title_box.add_theme_constant_override("separation", 1)
	_level_label = LevelBadge.new()
	_level_label.custom_minimum_size = Vector2(0, 46)
	title_box.add_child(_level_label)
	var score_cap := VisualTheme.label("SCORE", VisualTheme.FS_CAPTION, VisualTheme.TEXT_DIM, 0)
	score_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_box.add_child(score_cap)
	_score_label = VisualTheme.label("0", VisualTheme.FS_DISPLAY, VisualTheme.TEXT, 6)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_box.add_child(_score_label)
	row1.add_child(title_box)

	var gear := _icon_button(&"gear", 68)
	gear.pressed.connect(func():
		Audio.play(&"button_tap")
		_show_settings(true)
	)
	row1.add_child(gear)

	# --- row 2: MOVES pill | objectives pill | COINS pill ----------------
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 12)
	col.add_child(row2)

	var moves_box := VBoxContainer.new()
	moves_box.alignment = BoxContainer.ALIGNMENT_CENTER
	moves_box.add_theme_constant_override("separation", 0)
	var moves_cap := VisualTheme.label("MOVES", VisualTheme.FS_CAPTION, VisualTheme.TEXT_DIM, 0)
	moves_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	moves_box.add_child(moves_cap)
	_moves_value = VisualTheme.label("20", VisualTheme.FS_HERO_NUM, VisualTheme.TEXT)
	_moves_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	moves_box.add_child(_moves_value)
	_moves_pill = _pill(moves_box, 120)
	row2.add_child(_moves_pill)

	var tgt_box := VBoxContainer.new()
	tgt_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tgt_box.add_theme_constant_override("separation", 3)
	var tgt_cap := VisualTheme.label("GOAL", VisualTheme.FS_CAPTION, VisualTheme.TEXT_DIM, 0)
	tgt_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tgt_box.add_child(tgt_cap)
	_objective_row = HBoxContainer.new()
	_objective_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_objective_row.add_theme_constant_override("separation", 12)
	tgt_box.add_child(_objective_row)
	var tgt_pill := _pill(tgt_box)
	tgt_pill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(tgt_pill)

	var coin_box := HBoxContainer.new()
	coin_box.alignment = BoxContainer.ALIGNMENT_CENTER
	coin_box.add_theme_constant_override("separation", 8)
	var coin_icon := GemIcon.new()
	coin_icon.kind = &"coin"
	coin_icon.custom_minimum_size = Vector2(32, 32)
	coin_box.add_child(coin_icon)
	_coins_label = VisualTheme.label("0", VisualTheme.FS_LABEL, VisualTheme.TEXT_GOLD)
	coin_box.add_child(_coins_label)
	row2.add_child(_pill(coin_box, 104))

# ------------------------------------------------------------ fever --

func _build_fever_meter() -> void:
	_fever_wrap = Control.new()
	_fever_wrap.custom_minimum_size = Vector2(0, 64)
	_top_col.add_child(_fever_wrap)

	# The prepared Fever Meter Frame (#53, crowned gold capsule) is the whole
	# meter; FeverArt reveals it left->right by the charge ratio over a dark
	# track, ghosts the empty capsule behind, and pulses the Fever Crystal
	# (#52) at the fill edge. Falls back to a flat bar if the art is absent.
	_fever_bar = FeverArt.new()
	_fever_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fever_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fever_wrap.add_child(_fever_bar)

	# left: FEVER caption; right: the reward it unlocks — so an empty meter
	# still reads as "fill this for a x1.5 bonus", not a disabled field.
	# caption sits in the clear strip ABOVE the fill track (row is 64 tall,
	# track occupies the middle third) so it never fights the gold fill.
	_fever_label = VisualTheme.label("FEVER", VisualTheme.FS_CAPTION, VisualTheme.TEXT_DIM, 4)
	_fever_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_fever_label.offset_left = 208
	_fever_label.offset_top = 2
	_fever_label.offset_bottom = 22
	_fever_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fever_wrap.add_child(_fever_label)

	var mult := VisualTheme.label("x%.1f" % GameData.fever_config.score_multiplier, VisualTheme.FS_CAPTION,
		VisualTheme.FEVER, 4)
	mult.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	mult.offset_right = -18
	mult.offset_left = -104
	mult.offset_top = 2
	mult.offset_bottom = 22
	mult.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mult.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fever_wrap.add_child(mult)

func _bar_style(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(13)
	return sb

# ---------------------------------------------------------- boosters --

func _build_booster_bar() -> void:
	# Anchored directly (not via a MarginContainer) so it has a real rect on
	# a Control that's parented to a CanvasLayer.
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	col.offset_left = 10
	col.offset_right = -10
	col.offset_top = -TRAY_COL_HEIGHT
	col.offset_bottom = -int(maxf(_safe_bottom, MIN_BOTTOM_CLEARANCE) + 12.0)
	col.alignment = BoxContainer.ALIGNMENT_END
	col.add_theme_constant_override("separation", 6)
	_bottom_col = col
	add_child(col)

	_hint_label = VisualTheme.label("", VisualTheme.FS_BODY, VisualTheme.TEXT_GOLD, 5)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.custom_minimum_size = Vector2(0, 38)
	col.add_child(_hint_label)

	var tray := PanelContainer.new()
	var tray_sb := VisualTheme.panel(Color(0.11, 0.13, 0.22, 0.99), 30, VisualTheme.PANEL_BORDER_BRIGHT, 2)
	tray_sb.content_margin_left = 16
	tray_sb.content_margin_right = 16
	tray_sb.content_margin_top = 16
	tray_sb.content_margin_bottom = 18
	tray_sb.shadow_size = 22
	tray.add_theme_stylebox_override("panel", tray_sb)
	col.add_child(tray)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	tray.add_child(row)

	for id in _BOOSTER_ORDER:
		var tint: Color = _BOOSTER_TINT[id]
		var slot := Control.new()
		slot.custom_minimum_size = Vector2(150, 214)
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot.pivot_offset = slot.custom_minimum_size * 0.5

		var chip := BoosterChip.new()
		chip.tint = tint
		chip.booster_id = id
		var bdef: Dictionary = GameData.boosters.get(id, {})
		chip.title = String(bdef.get("label", String(id))).to_upper()
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

		var badge := VisualTheme.label("0", VisualTheme.FS_LABEL, VisualTheme.TEXT, 4)
		badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		badge.offset_left = -46
		badge.offset_right = -2
		badge.offset_top = -8
		badge.custom_minimum_size = Vector2(44, 44)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.add_theme_stylebox_override("normal", VisualTheme.panel(Color(0.04, 0.05, 0.10, 0.98), 22, VisualTheme.PANEL_BORDER_BRIGHT, 2))
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
	_end_panel.custom_minimum_size = Vector2(560, 460)
	_end_panel.add_theme_stylebox_override("panel", VisualTheme.panel(Color(0.09, 0.10, 0.19, 0.98), 30, VisualTheme.PANEL_BORDER_BRIGHT, 2))
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

	_end_crown = TextureRect.new()
	_end_crown.texture = AssetLibrary.tex(&"cel_victory_crown")
	_end_crown.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_end_crown.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_end_crown.custom_minimum_size = Vector2(0, 130)
	_end_crown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_end_crown.visible = _end_crown.texture != null
	vbox.add_child(_end_crown)

	_end_title = VisualTheme.label("LEVEL COMPLETE!", VisualTheme.FS_TITLE, VisualTheme.TEXT_GOLD)
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_end_title)

	_end_stars = StarRow.new()
	_end_stars.custom_minimum_size = Vector2(240, 72)
	vbox.add_child(_end_stars)

	_end_body = VisualTheme.label("", VisualTheme.FS_BODY, VisualTheme.TEXT)
	_end_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_end_body)

	_end_button = _cta_button("CONTINUE", VisualTheme.GOOD)
	_end_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_end_button)

	_end_map_button = _cta_button("LEVEL MAP", VisualTheme.ACCENT)
	_end_map_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_end_map_button.pressed.connect(func():
		Audio.play(&"button_tap")
		map_pressed.emit()
	)
	vbox.add_child(_end_map_button)

func _cta_button(text: String, tint: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(300, 74)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", VisualTheme.FS_BUTTON)
	b.add_theme_color_override("font_color", VisualTheme.TEXT)
	b.add_theme_constant_override("outline_size", 5)
	b.add_theme_color_override("font_outline_color", VisualTheme.OUTLINE)
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
	_settings_panel.custom_minimum_size = Vector2(520, 500)
	_settings_panel.add_theme_stylebox_override("panel", VisualTheme.panel(Color(0.09, 0.10, 0.19, 0.98), 28, VisualTheme.PANEL_BORDER_BRIGHT, 2))
	_settings_center.add_child(_settings_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	_settings_panel.add_child(vbox)

	var title := VisualTheme.label("SETTINGS", VisualTheme.FS_TITLE, VisualTheme.TEXT)
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
	_pause_panel.custom_minimum_size = Vector2(480, 470)
	_pause_panel.add_theme_stylebox_override("panel", VisualTheme.panel(Color(0.09, 0.10, 0.19, 0.98), 28, VisualTheme.PANEL_BORDER_BRIGHT, 2))
	_pause_center.add_child(_pause_panel)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	_pause_panel.add_child(vbox)

	var title := VisualTheme.label("PAUSED", VisualTheme.FS_TITLE, VisualTheme.TEXT_GOLD)
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
	var label := VisualTheme.label(label_text, VisualTheme.FS_BODY, VisualTheme.TEXT_DIM, 0)
	label.custom_minimum_size = Vector2(280, 0)
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
	var label := VisualTheme.label(label_text, VisualTheme.FS_BODY, VisualTheme.TEXT_DIM, 0)
	label.custom_minimum_size = Vector2(280, 0)
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
		var done: int = tracker.progress[i]
		var tgt: int = maxi(tracker.target_for(i), 1)
		var complete := done >= tgt

		# One objective "card": icon + count over a slim progress bar, on a
		# rounded inset so each goal reads as a distinct tracked task.
		var card := PanelContainer.new()
		var csb := VisualTheme.panel(Color(0.05, 0.06, 0.12, 0.85), 14,
			VisualTheme.GOOD if complete else VisualTheme.PANEL_BORDER, 2)
		csb.content_margin_left = 12
		csb.content_margin_right = 12
		csb.content_margin_top = 8
		csb.content_margin_bottom = 8
		csb.shadow_size = 0
		card.add_theme_stylebox_override("panel", csb)

		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		card.add_child(box)

		var top := HBoxContainer.new()
		top.alignment = BoxContainer.ALIGNMENT_CENTER
		top.add_theme_constant_override("separation", 7)
		var icon := GemIcon.new()
		icon.custom_minimum_size = Vector2(38, 38)
		_style_obj_icon(icon, obj)
		top.add_child(icon)
		var txt := VisualTheme.label("%d/%d" % [mini(done, tgt), tgt], VisualTheme.FS_HEADING,
			VisualTheme.GOOD if complete else VisualTheme.TEXT)
		top.add_child(txt)
		box.add_child(top)

		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.min_value = 0.0
		bar.max_value = 1.0
		bar.value = clampf(float(done) / float(tgt), 0.0, 1.0)
		bar.custom_minimum_size = Vector2(120, 10)
		var bg := _bar_style(Color(0.0, 0.0, 0.02, 0.7))
		bg.set_corner_radius_all(5)
		var fg := _bar_style(VisualTheme.GOOD if complete else _obj_bar_color(obj))
		fg.set_corner_radius_all(5)
		bar.add_theme_stylebox_override("background", bg)
		bar.add_theme_stylebox_override("fill", fg)
		box.add_child(bar)

		_objective_row.add_child(card)
		_objective_chips.append(card)

func _obj_bar_color(obj: Dictionary) -> Color:
	match String(obj.get("type", "")):
		"clear_color":
			return _color_for(String(obj.get("color", "red"))).lightened(0.1)
		"reach_score":
			return VisualTheme.STAR
		"create_powers":
			return Color(1.0, 0.7, 0.3)
		"break_obstacles":
			return Color(0.7, 0.75, 0.82)
		_:
			return VisualTheme.ACCENT

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
	var target: float = 1.0 if active else clampf(meter / maxf(meter_max, 1.0), 0.0, 1.0)
	var t := create_tween()
	t.tween_property(_fever_bar, "ratio", target, 0.3).set_trans(Tween.TRANS_CUBIC)
	_fever_bar.active = active
	_fever_label.text = "FEVER!" if active else "FEVER"
	_fever_label.add_theme_color_override("font_color", Color(1, 1, 1) if active else VisualTheme.TEXT_DIM)
	if active != _fever_running:
		_fever_running = active
		if _fever_pulse != null and _fever_pulse.is_valid():
			_fever_pulse.kill()
		if active:
			_fever_bar.ratio = 1.0
			_fever_wrap.pivot_offset = _fever_wrap.size * 0.5
			_fever_pulse = create_tween().set_loops()
			_fever_pulse.tween_property(_fever_wrap, "scale", Vector2(1.04, 1.12), 0.34).set_trans(Tween.TRANS_SINE)
			_fever_pulse.tween_property(_fever_wrap, "scale", Vector2.ONE, 0.34).set_trans(Tween.TRANS_SINE)
		else:
			_fever_wrap.scale = Vector2.ONE
	elif active:
		_fever_bar.ratio = 1.0

## A one-off wallop the instant Fever ignites: the meter flares white and
## the whole strip kicks.
func flash_fever() -> void:
	_fever_wrap.pivot_offset = _fever_wrap.size * 0.5
	_fever_bar.flash = 1.0
	var t := create_tween()
	t.tween_property(_fever_wrap, "scale", Vector2(1.25, 1.4), 0.12).set_trans(Tween.TRANS_BACK)
	t.tween_property(_fever_wrap, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_ELASTIC)
	t.parallel().tween_property(_fever_bar, "flash", 0.0, 0.5)

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
	_end_title.text = "LEVEL COMPLETE!"
	_end_body.text = "Score  %s\n+%d coins" % [_fmt(score), reward_coins]
	_end_button.text = "NEXT LEVEL" if has_next_level else "BACK TO MAP"
	_end_map_button.visible = true
	if _end_crown != null:
		_end_crown.visible = _end_crown.texture != null
	_rewire(_end_button, func(): next_level_pressed.emit())
	_end_center.visible = true
	_refresh_scrim()
	_pop_in(_end_panel)
	_end_stars.play(stars)
	_end_confetti.restart()
	_end_confetti.emitting = true
	# prepared celebration bursts over the panel
	if _fx != null:
		var cc := size * Vector2(0.5, 0.42)
		_fx.play_hold(&"cel_firework_burst", cc, size.x * 0.8, Color(1, 1, 1), 0.8, true, 0.3)
		_fx.play(&"cel_confetti_pieces", cc, size.x * 0.95, Color(1, 1, 1), 1.1, false, 0.4, 2.4)
		if stars >= 3:
			_fx.play(&"cel_star_burst", cc, size.x * 0.7, Color(1, 1, 1), 0.7, true, 0.6)

func show_lose_panel(score: int) -> void:
	_end_title.text = "SO CLOSE!"
	_end_body.text = "Score  %s\nTry again — you've got this!" % _fmt(score)
	_end_button.text = "TRY AGAIN"
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
## IconDraw glyph, a name plate, an armed glow-pulse, and a lock overlay
## when empty.
class BoosterChip extends Control:
	var tint: Color = Color(0.5, 0.5, 0.5)
	var booster_id: StringName = &"bomb"
	var title: String = ""
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

	## Power boosters sit in the sci-fi "power energy" capsule (#51); the
	## utility ones (shuffle / +moves) in the general booster container (#50).
	const _POWER_IDS := [&"bomb", &"lightning", &"freeze", &"rainbow", &"chain"]

	func _draw() -> void:
		var rr := 22.0
		var rect := Rect2(Vector2(4, 4), size - Vector2(8, 8))

		var frame_id := &"ui_power_energy_container" if booster_id in _POWER_IDS else &"ui_booster_container"
		var frame := AssetLibrary.tex(frame_id)

		if armed:
			var p := 0.5 + 0.5 * sin(_t * 8.0)
			for k in 3:
				_round(rect.grow(3.0 + 5.0 * p + k * 5.0), rr + 6,
					Color(tint.r, tint.g, tint.b, (0.34 - k * 0.09) * (0.5 + 0.5 * p)))

		if frame != null:
			# capsule art fills the chip (aspect kept), plus a per-power tinted
			# wash so each slot still reads at a glance. "changing energy level":
			# the capsule brightens when the booster is armed, dims when empty.
			var fw: float = float(frame.get_width())
			var fh: float = float(frame.get_height())
			var scale_k: float = maxf(rect.size.x / fw, rect.size.y / fh)
			var dw := fw * scale_k
			var dh := fh * scale_k
			var fr := Rect2(rect.position + (rect.size - Vector2(dw, dh)) * 0.5, Vector2(dw, dh))
			var lvl := 1.0 if armed else (0.9 if enabled else 0.5)
			draw_texture_rect(frame, fr, false, Color(lvl, lvl, lvl, 1.0))
			if enabled:
				_round(rect.grow(-6.0), rr - 4, Color(tint.r, tint.g, tint.b, 0.16 + (0.18 if armed else 0.0)))
			if armed:
				_round_outline(rect, rr, Color(1, 1, 1, 0.85), 3.0)
		else:
			# drop shadow + tinted body fallback (no container art)
			_round(Rect2(rect.position + Vector2(0, 6), rect.size), rr, Color(0, 0, 0, 0.35))
			_round(rect, rr, tint.darkened(0.34))
			_round(Rect2(rect.position, Vector2(rect.size.x, rect.size.y * 0.52)), rr, tint.lightened(0.10))
			_round(rect.grow(-3.0), rr - 3, tint.darkened(0.10))
			if armed:
				_round_outline(rect, rr, Color(1, 1, 1, 0.85), 3.0)
			draw_line(rect.position + Vector2(14, 6), rect.position + Vector2(rect.size.x - 14, 6),
				Color(1, 1, 1, 0.30), 3.0, true)

		# the booster's own object: prepared power art (#7-11) for the power
		# boosters, vector glyph for shuffle / +moves.
		var icon_c := Vector2(size.x * 0.5, size.y * 0.44)
		var pow_tex := AssetLibrary.power(booster_id)
		if pow_tex != null:
			var s := minf(size.x, size.y) * 0.66
			var m: float = maxf(float(pow_tex.get_width()), float(pow_tex.get_height()))
			var w := s * pow_tex.get_width() / m
			var h := s * pow_tex.get_height() / m
			draw_texture_rect(pow_tex, Rect2(icon_c - Vector2(w, h) * 0.5, Vector2(w, h)), false)
		else:
			IconDraw.draw_icon(self, booster_id, icon_c, minf(size.x, size.y) * 0.6, _t)

		# name plate — a darkened strip along the bottom so the label always
		# reads over the tinted face, clear of the chip's lower edge.
		if title != "":
			var strip_h := clampf(size.y * 0.22, 24.0, 40.0)
			_round(Rect2(rect.position + Vector2(6, rect.size.y - strip_h - 4), Vector2(rect.size.x - 12, strip_h)),
				10.0, Color(0, 0, 0, 0.36))
			var font := ThemeDB.fallback_font
			var fs := int(clampf(size.x * 0.16, 14.0, 20.0))
			var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
			var tp := Vector2(size.x * 0.5 - tw * 0.5, rect.position.y + rect.size.y - strip_h * 0.5 - 4.0 + fs * 0.34)
			draw_string_outline(font, tp, title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.85))
			draw_string(font, tp, title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.96))

		if not enabled:
			_round(rect, rr, Color(0.03, 0.04, 0.08, 0.62))
			var lc := Vector2(size.x * 0.5, size.y * 0.42)
			draw_arc(lc + Vector2(0, -size.x * 0.08), size.x * 0.14, PI, TAU, 14, Color(0.82, 0.85, 0.94), 4.0, true)
			draw_rect(Rect2(lc + Vector2(-size.x * 0.15, -size.x * 0.08), Vector2(size.x * 0.30, size.x * 0.22)), Color(0.82, 0.85, 0.94))

	func _round(r: Rect2, radius: float, col: Color) -> void:
		var pts := ShapeDrawUtils.rounded_rect_points(r.size, radius, 5)
		var moved := PackedVector2Array()
		for p in pts:
			moved.append(p + r.position + r.size * 0.5)
		draw_colored_polygon(moved, col)

	func _round_outline(r: Rect2, radius: float, col: Color, w: float) -> void:
		var pts := ShapeDrawUtils.rounded_rect_points(r.size, radius, 6)
		var moved := PackedVector2Array()
		for p in pts:
			moved.append(p + r.position + r.size * 0.5)
		moved.append(moved[0])
		draw_polyline(moved, col, w, true)


## Code-drawn chrome glyph (pause / gear) — avoids missing font glyphs.
class MiniIcon extends Control:
	var kind: StringName = &"pause"

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.26
		if kind == &"gear":
			var tex := AssetLibrary.tex(&"ui_setting_gear")
			if tex != null:
				var s := minf(size.x, size.y) * 0.92
				var m: float = maxf(float(tex.get_width()), float(tex.get_height()))
				var w := s * tex.get_width() / m
				var h := s * tex.get_height() / m
				draw_texture_rect(tex, Rect2(c - Vector2(w, h) * 0.5, Vector2(w, h)), false)
				return
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

	## Logical icon -> prepared UI/economy sprite. Falls back to the vector draw.
	## `gem` stays the code-drawn TINTED hex (used by colour-clear objective
	## chips, which must show the target colour). `crystal` is the currency icon.
	const _SPRITE := {
		&"coin": &"ui_coin_icon", &"score": &"eco_star", &"crystal": &"eco_reward_crystal",
		&"trophy": &"eco_trophy", &"star": &"eco_star",
	}

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.46
		if _SPRITE.has(kind):
			var tex := AssetLibrary.tex(_SPRITE[kind])
			if tex != null:
				var s := minf(size.x, size.y)
				var m: float = maxf(float(tex.get_width()), float(tex.get_height()))
				var w := s * tex.get_width() / m
				var h := s * tex.get_height() / m
				draw_texture_rect(tex, Rect2(c - Vector2(w, h) * 0.5, Vector2(w, h)), false)
				return
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
		var spacing := 78.0
		var tex := AssetLibrary.tex(&"eco_star")
		for i in 3:
			var center := Vector2(cx + float(i - 1) * spacing, cy)
			var filled := float(i) < _shown and i < _earned
			var grow: float = clampf(_shown - float(i), 0.0, 1.0)
			var r := 26.0 * (0.4 + 0.6 * grow) if float(i) < _shown else 22.0
			if not (float(i) < _shown):
				grow = 1.0
				r = 22.0
			if tex != null:
				var d := r * 2.4
				var col := Color(1, 1, 1) if filled else Color(0.3, 0.32, 0.4, 0.85)
				draw_texture_rect(tex, Rect2(center - Vector2(d, d) * 0.5, Vector2(d, d)), false, col)
				continue
			draw_colored_polygon(ShapeDrawUtils.star_points(center, r + 3.0), Color(0, 0, 0, 0.35))
			var pcol := VisualTheme.STAR if filled else Color(0.24, 0.25, 0.32)
			draw_colored_polygon(ShapeDrawUtils.star_points(center, r), pcol)
			if filled:
				draw_colored_polygon(ShapeDrawUtils.star_points(center, r * 0.5), VisualTheme.STAR.lightened(0.4))


## The Fever charge meter: the crowned Fever Meter Frame (#53) sits undistorted
## as an ornamental "head" on the left, then a dark capsule track fills with
## gold toward the right by `ratio`, with the Fever Crystal (#52) riding the
## fill edge and flaring while Fever is active. Pure code fallback if the art
## is missing.
class FeverArt extends Control:
	var ratio := 0.0: set = _set_ratio
	var active := false: set = _set_active
	var flash := 0.0: set = _set_flash
	var _t := 0.0

	func _set_ratio(v: float) -> void: ratio = clampf(v, 0.0, 1.0); queue_redraw()
	func _set_active(v: bool) -> void: active = v; queue_redraw()
	func _set_flash(v: float) -> void: flash = v; queue_redraw()

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(true)

	func _process(delta: float) -> void:
		_t += delta
		if active or flash > 0.001:
			queue_redraw()

	func _draw() -> void:
		var h := size.y
		var frame := AssetLibrary.tex(&"ui_fever_meter_frame")
		var crystal := AssetLibrary.tex(&"ui_fever_crystal")

		# ornamental crowned head — the prepared frame (#53) drawn at its native
		# 3:1 aspect, fit to the row height, left-aligned (never stretched).
		var head_w := 0.0
		if frame != null:
			head_w = h * float(frame.get_width()) / float(frame.get_height())
			draw_texture_rect(frame, Rect2(0, 0, head_w, h), false)

		# code capsule track occupying the rest of the row (below the caption)
		var x0: float = maxf(head_w * 0.84, h * 0.2)
		var track := Rect2(x0, h * 0.40, size.x - x0, h * 0.34)
		var cr := track.size.y * 0.5
		_capsule(track.grow(3.0), cr + 3.0, Color(0.55, 0.75, 1.0, 0.16))
		_capsule(track, cr, Color(0.04, 0.05, 0.11, 0.96))

		var fill_w := track.size.x * ratio
		if fill_w > cr:
			var fc := VisualTheme.FEVER_HOT if active else VisualTheme.FEVER
			if flash > 0.0:
				fc = fc.lerp(Color(1, 1, 1), flash)
			var pulse := (0.85 + 0.15 * sin(_t * 10.0)) if active else 1.0
			_capsule(Rect2(track.position, Vector2(fill_w, track.size.y)), cr, Color(fc.r, fc.g, fc.b, pulse))
			_capsule(Rect2(track.position + Vector2(0, 2), Vector2(fill_w, track.size.y * 0.42)), cr,
				Color(1, 1, 1, 0.28 * pulse))

		# Fever Crystal (#52) rides the fill edge — flares while Fever is active
		var edge_x := track.position.x + clampf(fill_w, cr, track.size.x - cr * 0.5)
		var cy := track.position.y + track.size.y * 0.5
		if crystal != null:
			var cs := h * (0.95 if active else 0.72)
			if active:
				cs *= 1.0 + 0.08 * sin(_t * 8.0)
			var m: float = maxf(float(crystal.get_width()), float(crystal.get_height()))
			var cw := cs * crystal.get_width() / m
			var ch := cs * crystal.get_height() / m
			if active:
				VisualTheme.draw_glow(self, Vector2(edge_x, cy), cs,
					Color(VisualTheme.FEVER_HOT.r, VisualTheme.FEVER_HOT.g, VisualTheme.FEVER_HOT.b, 0.5), 4)
			draw_texture_rect(crystal, Rect2(Vector2(edge_x - cw * 0.5, cy - ch * 0.5), Vector2(cw, ch)), false)

		if flash > 0.0:
			_capsule(track, cr, Color(1, 1, 1, 0.5 * flash))

	func _capsule(r: Rect2, radius: float, col: Color) -> void:
		var pts := ShapeDrawUtils.rounded_rect_points(r.size, minf(radius, r.size.y * 0.5), 5)
		var moved := PackedVector2Array()
		for p in pts:
			moved.append(p + r.position + r.size * 0.5)
		draw_colored_polygon(moved, col)


## The "LEVEL n" tag: the prepared Level Badge (#56, crowned shield) drawn
## undistorted as an emblem, with the level text set across it. Plain gold
## label if the art is missing.
class LevelBadge extends Control:
	var text := "LEVEL 1": set = _set_text

	func _set_text(v: String) -> void:
		text = v
		queue_redraw()

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var tex := AssetLibrary.tex(&"ui_level_badge")
		if tex == null:
			var fs := VisualTheme.FS_LABEL
			var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
			draw_string_outline(font, Vector2((size.x - ts.x) * 0.5, size.y * 0.5 + fs * 0.34), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, VisualTheme.OUTLINE)
			draw_string(font, Vector2((size.x - ts.x) * 0.5, size.y * 0.5 + fs * 0.34), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, VisualTheme.TEXT_GOLD)
			return
		# badge fit to the row height (aspect kept), centred
		var bh := size.y * 1.34
		var bw := bh * float(tex.get_width()) / float(tex.get_height())
		var bx := (size.x - bw) * 0.5
		draw_texture_rect(tex, Rect2(Vector2(bx, (size.y - bh) * 0.5), Vector2(bw, bh)), false)
		# level number/text on the shield field (lower ~62% of the badge)
		var digits := ""
		for ch in text:
			if ch >= "0" and ch <= "9":
				digits += ch
		var label := digits if digits != "" else text
		var fs := 24
		var ts := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		var pos := Vector2(size.x * 0.5 - ts.x * 0.5, size.y * 0.5 + bh * 0.22 + fs * 0.34)
		draw_string_outline(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.8))
		draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1))
