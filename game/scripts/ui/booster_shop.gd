class_name BoosterShop
extends Control
## In-level booster shop — a frosted-glass / gold modal the player opens
## from the gameplay HUD WITHOUT leaving the level. Board input is frozen by
## app.gd while this is open (existing `_board.set_input_locked` pause path),
## so no move is consumed and no board / objective / enemy / boss / power
## state changes while shopping.
##
## SINGLE SOURCE OF TRUTH: quantities and purchases go through the existing
## `Boosters` autoload (same one the separate Inventory screen uses) and
## coins through `Economy` / `SaveService`. This screen adds no state.
##
##   signals:
##     use_requested(id)  — player pressed USE; app.gd routes it into the
##                          existing booster pipeline (arm / instant fire).
##     closed()           — the shop was dismissed.

signal use_requested(id: StringName)
signal closed()

const _ORDER: Array[StringName] = [
	&"bomb", &"lightning", &"freeze", &"rainbow", &"shuffle", &"extra_moves",
]

var _scrim: ColorRect
var _frame: UiKit.GoldFramePanel
var _list: VBoxContainer
var _coins_label: Label
var _confirm_layer: Control
var _confirm_id: StringName = &""
var _is_open := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 200
	visible = false
	_track_size()
	get_viewport().size_changed.connect(_track_size)

	_scrim = ColorRect.new()
	_scrim.color = Color(0, 0, 0, 0.58)
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_scrim.gui_input.connect(func(e):
		if (e is InputEventMouseButton or e is InputEventScreenTouch) and e.pressed:
			close())
	add_child(_scrim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_frame = UiKit.GoldFramePanel.new(16)
	_frame.custom_minimum_size = Vector2(600, 720)
	center.add_child(_frame)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	_frame.content().add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	col.add_child(head)
	var title := VisualTheme.label("BOOSTER SHOP", VisualTheme.FS_TITLE, VisualTheme.TEXT_GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var coin_icon := HUD.GemIcon.new()
	coin_icon.kind = &"coin"
	coin_icon.custom_minimum_size = Vector2(30, 30)
	head.add_child(coin_icon)
	_coins_label = VisualTheme.label("0", VisualTheme.FS_LABEL, VisualTheme.TEXT_GOLD)
	_coins_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_coins_label)
	var x := UiKit.icon_button(&"close", 48)
	x.pressed.connect(func(): Audio.play(&"button_tap"); close())
	head.add_child(x)

	col.add_child(VisualTheme.label("Buy or use boosters without leaving the level.",
		VisualTheme.FS_MICRO, VisualTheme.TEXT_DIM, 0))

	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.custom_minimum_size = Vector2(540, 520)
	col.add_child(sc)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_list)

	_build_confirm_layer()

	if Economy.has_signal("coins_changed"):
		Economy.coins_changed.connect(func(_v): _refresh())
	if Boosters.has_signal("inventory_changed"):
		Boosters.inventory_changed.connect(func(_i, _c): _refresh())

func _track_size() -> void:
	var vp := get_viewport_rect().size
	size = vp
	custom_minimum_size = vp

# ------------------------------------------------------------- open/close --

func is_open() -> bool:
	return _is_open

## `focus_id`: when set (e.g. the player tapped a booster in the gameplay
## tray that they own zero of), jumps straight to that booster's buy-confirm
## dialog instead of just showing the list — "I want THIS one" should be a
## single tap, not tap-the-tray-then-scroll-then-tap-BUY.
func open(focus_id: StringName = &"") -> void:
	_is_open = true
	visible = true
	_hide_confirm()
	_refresh()
	_scrim.modulate.a = 0.0
	_scrim.create_tween().tween_property(_scrim, "modulate:a", 1.0, 0.16)
	UiKit.pop_in(_frame)
	if focus_id != &"" and GameData.boosters.has(focus_id):
		request_buy(focus_id)

func close() -> void:
	if not _is_open:
		return
	_is_open = false
	_hide_confirm()
	# The logical "closed" event fires now (app.gd unfreezes the board);
	# the fade-out that follows is purely cosmetic.
	closed.emit()
	var t := UiKit.pop_out(_frame)
	_scrim.create_tween().tween_property(_scrim, "modulate:a", 0.0, 0.16)
	await t.finished
	if not _is_open:
		visible = false

# --------------------------------------------------------------- list --

func _refresh() -> void:
	if not visible:
		return
	_coins_label.text = str(Economy.coins)
	for c in _list.get_children():
		c.queue_free()
	for id in _ORDER:
		if not GameData.boosters.has(id):
			continue
		_list.add_child(_row(id))
	if _confirm_id != &"":
		_populate_confirm(_confirm_id)

func _row(id: StringName) -> PanelContainer:
	var def: Dictionary = GameData.boosters[id]
	var cost := int(def.get("cost", 0))
	var owned := Boosters.get_count(id)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiKit.glass(14, true))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)

	var icon := _booster_icon(id)
	row.add_child(icon)

	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 2)
	row.add_child(v)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	v.add_child(name_row)
	name_row.add_child(VisualTheme.label(String(def.get("label", id)).to_upper(), VisualTheme.FS_HEADING, VisualTheme.TEXT_GOLD))
	var targeted: bool = bool(def.get("targeted", false))
	name_row.add_child(VisualTheme.label("TAP BOARD" if targeted else "INSTANT",
		VisualTheme.FS_MICRO, VisualTheme.ACCENT if targeted else VisualTheme.GOOD, 0))
	var help := VisualTheme.label(String(def.get("help", "")), VisualTheme.FS_MICRO, VisualTheme.TEXT_DIM, 0)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size = Vector2(240, 0)
	v.add_child(help)
	v.add_child(VisualTheme.label("OWNED  x%d" % owned, VisualTheme.FS_CAPTION, VisualTheme.TEXT))

	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	row.add_child(actions)

	var buy := UiKit.button("BUY  %d" % cost, &"primary" if Economy.can_afford(cost) else &"tertiary", VisualTheme.FS_MICRO)
	buy.custom_minimum_size = Vector2(168, 56)
	buy.pressed.connect(func(): Audio.play(&"button_tap"); request_buy(id))
	actions.add_child(buy)

	var use := UiKit.button("USE", &"secondary", VisualTheme.FS_MICRO)
	use.custom_minimum_size = Vector2(168, 52)
	use.disabled = owned <= 0
	use.modulate.a = 1.0 if owned > 0 else 0.4
	use.pressed.connect(func(): Audio.play(&"button_tap"); request_use(id))
	actions.add_child(use)

	return card

func _booster_icon(id: StringName) -> Control:
	var tex := AssetLibrary.power(id)
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2(64, 64)
		return tr
	var g := IconDraw.IconRect.new()
	g.id = id
	g.custom_minimum_size = Vector2(56, 56)
	return g

# ------------------------------------------------------ use / buy flow --

## Player pressed USE — app.gd feeds this into the existing booster pipeline
## (targeted boosters arm, instant boosters fire) so the real
## board -> CombatDirector -> Jamie/boss chain runs. The shop closes first so
## the player is back on the board.
func request_use(id: StringName) -> void:
	if Boosters.get_count(id) <= 0:
		return
	var was_open := _is_open
	_is_open = false
	visible = false
	_hide_confirm()
	if was_open:
		closed.emit()
	use_requested.emit(id)

func request_buy(id: StringName) -> void:
	_confirm_id = id
	_populate_confirm(id)
	_confirm_layer.visible = true
	UiKit.pop_in(_confirm_layer.get_child(0))

## Presses the confirm dialog's BUY. Spends coins through the existing
## Economy (never below zero — Economy.spend refuses) and grants one charge
## through the existing Boosters autoload. Returns true on success.
func confirm_buy() -> bool:
	if _confirm_id == &"":
		return false
	var id := _confirm_id
	var ok := Boosters.purchase(id)   # Economy.spend + Boosters.add(1) + persist
	if ok:
		Audio.play(&"button_tap")
		var label := String(GameData.boosters.get(id, {}).get("label", id)).to_upper()
		UiKit.show_toast(self, "NEW %s ACQUIRED" % label, VisualTheme.GOOD)
	_hide_confirm()
	_refresh()
	return ok

func _build_confirm_layer() -> void:
	_confirm_layer = Control.new()
	_confirm_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_layer.visible = false
	add_child(_confirm_layer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirm_layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_layer.add_child(center)

	# Gold-framed chrome (2026-09-05 UI pass) — same dialog family as every
	# other modal, replacing a hand-rolled stylebox that was the odd one out.
	var panel := UiKit.GoldFramePanel.new(20)
	panel.custom_minimum_size = Vector2(480, 420)
	center.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.content().add_child(v)

	_c_title = VisualTheme.label("", VisualTheme.FS_TITLE, VisualTheme.TEXT_GOLD)
	_c_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_c_title)

	_c_qty = _kv_row(v, "IN INVENTORY")
	_c_price = _kv_row(v, "PRICE")
	_c_coins = _kv_row(v, "YOUR COINS")
	_c_after = _kv_row(v, "COINS AFTER")

	_c_warn = VisualTheme.label("NOT ENOUGH COINS", VisualTheme.FS_BODY, VisualTheme.ACCENT_HOT)
	_c_warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_c_warn.visible = false
	v.add_child(_c_warn)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 12)
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(btns)

	var cancel := UiKit.button("CANCEL", &"tertiary", VisualTheme.FS_MICRO)
	cancel.custom_minimum_size = Vector2(190, 64)
	cancel.pressed.connect(func(): Audio.play(&"button_tap"); _hide_confirm())
	btns.add_child(cancel)

	_c_buy = UiKit.button("BUY", &"primary", VisualTheme.FS_MICRO)
	_c_buy.custom_minimum_size = Vector2(190, 64)
	_c_buy.pressed.connect(func(): confirm_buy())
	btns.add_child(_c_buy)

var _c_title: Label
var _c_qty: Label
var _c_price: Label
var _c_coins: Label
var _c_after: Label
var _c_warn: Label
var _c_buy: Button

func _kv_row(parent: VBoxContainer, key: String) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var k := VisualTheme.label(key, VisualTheme.FS_CAPTION, VisualTheme.TEXT_DIM, 0)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(k)
	var val := VisualTheme.label("", VisualTheme.FS_BODY, VisualTheme.TEXT)
	row.add_child(val)
	return val

func _populate_confirm(id: StringName) -> void:
	var def: Dictionary = GameData.boosters.get(id, {})
	var cost := int(def.get("cost", 0))
	var afford := Economy.can_afford(cost)
	_c_title.text = String(def.get("label", id)).to_upper()
	_c_qty.text = "x%d" % Boosters.get_count(id)
	_c_price.text = "%d" % cost
	_c_coins.text = "%d" % Economy.coins
	_c_after.text = "%d" % maxi(Economy.coins - cost, 0)
	_c_warn.visible = not afford
	_c_buy.disabled = not afford
	_c_buy.modulate.a = 1.0 if afford else 0.45

func _hide_confirm() -> void:
	_confirm_id = &""
	if _confirm_layer != null:
		_confirm_layer.visible = false
