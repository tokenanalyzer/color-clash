class_name ExtraMovesPrompt
extends Control
## The "NEED MORE MOVES?" continue modal, shown by app.gd when the player
## runs out of moves with the objective still incomplete. Buying adds moves
## straight to the RUNNING level — the board, objectives, enemy HP, boss HP
## and Jamie's power meters are all left exactly as they were (app.gd never
## re-runs `_start_level`). Declining falls through to the normal loss.
##
## Tiers + prices come from GameData.continue_offers (data/economy.json);
## coins are spent through the existing Economy / SaveService. No new state.
##
##   signals:
##     bought(moves_added: int) — coins already spent; add these moves + resume
##     gave_up()                — no purchase; proceed to the loss screen

signal bought(moves_added: int)
signal gave_up()

var _scrim: ColorRect
var _panel: PanelContainer
var _tier_box: VBoxContainer
var _coins_label: Label
var _is_open := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 205
	visible = false
	_track_size()
	get_viewport().size_changed.connect(_track_size)

	_scrim = ColorRect.new()
	_scrim.color = Color(0, 0, 0, 0.62)
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_scrim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(520, 560)
	var sb := UiKit.glass(28, true)
	sb.bg_color = Color(0.08, 0.09, 0.18, 0.96)
	sb.border_color = Color(UiKit.GOLD.r, UiKit.GOLD.g, UiKit.GOLD.b, 0.45)
	sb.set_border_width_all(2)
	sb.content_margin_left = 26; sb.content_margin_right = 26
	sb.content_margin_top = 24; sb.content_margin_bottom = 24
	_panel.add_theme_stylebox_override("panel", sb)
	center.add_child(_panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	_panel.add_child(v)

	var title := VisualTheme.label("NEED MORE MOVES?", VisualTheme.FS_TITLE, VisualTheme.TEXT_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)

	var sub := VisualTheme.label("Keep this board — top up and play on.", VisualTheme.FS_BODY, VisualTheme.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)

	var coin_row := HBoxContainer.new()
	coin_row.alignment = BoxContainer.ALIGNMENT_CENTER
	coin_row.add_theme_constant_override("separation", 8)
	v.add_child(coin_row)
	var ci := HUD.GemIcon.new()
	ci.kind = &"coin"
	ci.custom_minimum_size = Vector2(30, 30)
	coin_row.add_child(ci)
	_coins_label = VisualTheme.label("0", VisualTheme.FS_LABEL, VisualTheme.TEXT_GOLD)
	coin_row.add_child(_coins_label)

	_tier_box = VBoxContainer.new()
	_tier_box.add_theme_constant_override("separation", 10)
	v.add_child(_tier_box)

	var give_up := UiKit.button("GIVE UP", &"tertiary", VisualTheme.FS_MICRO)
	give_up.custom_minimum_size = Vector2(300, 60)
	give_up.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	give_up.pressed.connect(func(): Audio.play(&"button_tap"); _decline())
	v.add_child(give_up)

func _track_size() -> void:
	var vp := get_viewport_rect().size
	size = vp
	custom_minimum_size = vp

func is_open() -> bool:
	return _is_open

func open() -> void:
	_is_open = true
	visible = true
	_rebuild()
	_scrim.modulate.a = 0.0
	_scrim.create_tween().tween_property(_scrim, "modulate:a", 1.0, 0.16)
	UiKit.pop_in(_panel)

func _rebuild() -> void:
	_coins_label.text = str(Economy.coins)
	for c in _tier_box.get_children():
		c.queue_free()
	for t in GameData.continue_offers.tiers():
		_tier_box.add_child(_tier_button(t))

func _tier_button(t: Dictionary) -> Button:
	var id: StringName = t["id"]
	var cost := int(t["cost"])
	var afford := Economy.can_afford(cost)
	var after := maxi(Economy.coins - cost, 0)
	var b := UiKit.button("%s      %d  (→ %d)" % [String(t["label"]).to_upper(), cost, after],
		&"primary" if afford else &"tertiary", VisualTheme.FS_MICRO)
	b.custom_minimum_size = Vector2(420, 74)
	b.disabled = not afford
	b.modulate.a = 1.0 if afford else 0.45
	b.pressed.connect(func(): _buy(id))
	return b

## Spend + report the moves to add. app.gd adds them to the live level and
## resumes — it does NOT restart the stage.
func _buy(id: StringName) -> void:
	var moves := GameData.continue_offers.purchase(id)   # Economy.spend + persist
	if moves <= 0:
		_rebuild()   # not affordable after all — just refresh
		return
	Audio.play(&"power_up", 0.7)
	_close()
	bought.emit(moves)

func _decline() -> void:
	_close()
	gave_up.emit()

func _close() -> void:
	_is_open = false
	var t := UiKit.pop_out(_panel)
	_scrim.create_tween().tween_property(_scrim, "modulate:a", 0.0, 0.16)
	await t.finished
	visible = false
