class_name InventoryScreen
extends Control
## The Inventory — Jamie's powers (upgradeable with coins), boosters,
## equipment and collected items. Reads/writes only the existing autoloads
## (Inventory / Economy / Boosters); no new save logic. Premium glass/gold
## style to match the rest of the UI.

signal closed()

const _TABS := ["POWERS", "BOOSTERS", "EQUIP", "ITEMS"]

var _frame: UiKit.GoldFramePanel
var _scrim: ColorRect
var _body: VBoxContainer
var _tab_row: HBoxContainer
var _coins_label: Label
var _tab := 0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	z_index = 210
	_track_size()
	get_viewport().size_changed.connect(_track_size)

	_scrim = ColorRect.new()
	_scrim.color = Color(0, 0, 0, 0.62)
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

	_frame = UiKit.GoldFramePanel.new(18)
	_frame.custom_minimum_size = Vector2(620, 780)
	center.add_child(_frame)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	_frame.content().add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	col.add_child(head)
	var title := VisualTheme.label("INVENTORY", VisualTheme.FS_TITLE, VisualTheme.TEXT_GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_coins_label = VisualTheme.label("", VisualTheme.FS_LABEL, VisualTheme.TEXT_GOLD)
	head.add_child(_coins_label)
	var x := UiKit.icon_button(&"close", 48)
	var xs := UiKit.button_face(UiKit.RED_FACE, UiKit.RED_DEEP, 24)
	xs.content_margin_left = 0; xs.content_margin_right = 0; xs.content_margin_top = 0; xs.content_margin_bottom = 0
	x.add_theme_stylebox_override("normal", xs); x.add_theme_stylebox_override("hover", xs)
	x.pressed.connect(func(): Audio.play(&"button_tap"); close())
	head.add_child(x)

	_tab_row = HBoxContainer.new()
	_tab_row.add_theme_constant_override("separation", 8)
	col.add_child(_tab_row)
	for i in _TABS.size():
		var b := UiKit.button(_TABS[i], &"tertiary", VisualTheme.FS_MICRO)
		b.custom_minimum_size = Vector2(0, 46)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(idx = i): Audio.play(&"button_tap"); _tab = idx; _rebuild())
		_tab_row.add_child(b)

	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.custom_minimum_size = Vector2(560, 560)
	col.add_child(sc)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 10)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_body)

	if Inventory != null and Inventory.has_signal("changed"):
		Inventory.changed.connect(_rebuild)

func _track_size() -> void:
	var vp := get_viewport_rect().size
	size = vp
	custom_minimum_size = vp

func open() -> void:
	visible = true
	_tab = 0
	_rebuild()
	_scrim.modulate.a = 0.0
	_scrim.create_tween().tween_property(_scrim, "modulate:a", 1.0, 0.16)
	UiKit.pop_in(_frame)

func close() -> void:
	var t := UiKit.pop_out(_frame)
	_scrim.create_tween().tween_property(_scrim, "modulate:a", 0.0, 0.16)
	await t.finished
	visible = false
	closed.emit()

func _clear() -> void:
	for c in _body.get_children():
		c.queue_free()

func _rebuild() -> void:
	if not visible:
		return
	_coins_label.text = "%d  ¢" % Economy.coins
	for i in _tab_row.get_child_count():
		(_tab_row.get_child(i) as Button).modulate.a = 1.0 if i == _tab else 0.55
	_clear()
	match _tab:
		0: _build_powers()
		1: _build_boosters()
		2: _build_equipment()
		3: _build_items()

func _row_card() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiKit.glass(14, true))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return p

const _POWER_META := {
	&"fire_sword": ["Fire Sword", "Raw match power — bigger clears hit harder."],
	&"lightning_hand": ["Blue Lightning", "Spell power — fills from power activations."],
	&"lightning_boots": ["Lightning Boots", "Momentum — fills from deep cascades."],
}

func _build_powers() -> void:
	for id in JamiePowers.ORDER:
		var meta: Array = _POWER_META[id]
		var lvl: int = Inventory.power_level(id)
		var card := _row_card()
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		card.add_child(row)
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(v)
		v.add_child(VisualTheme.label(meta[0], VisualTheme.FS_HEADING, VisualTheme.TEXT_GOLD))
		v.add_child(VisualTheme.label(meta[1], VisualTheme.FS_MICRO, VisualTheme.TEXT_DIM, 0))
		var dots := ""
		for k in Inventory.MAX_POWER_LEVEL:
			dots += "◆ " if k < lvl else "◇ "
		v.add_child(VisualTheme.label("LV %d   %s" % [lvl, dots], VisualTheme.FS_CAPTION, VisualTheme.TEXT))
		var cost: int = Inventory.power_upgrade_cost(id)
		var btn := UiKit.button("MAX" if cost < 0 else "UPGRADE  %d¢" % cost,
			&"primary" if (cost > 0 and Economy.can_afford(cost)) else &"tertiary", VisualTheme.FS_MICRO)
		btn.custom_minimum_size = Vector2(180, 58)
		btn.disabled = cost < 0 or not Economy.can_afford(cost)
		btn.pressed.connect(func():
			if Inventory.upgrade_power(id):
				Audio.play(&"power_up"); _rebuild())
		row.add_child(btn)
		_body.add_child(card)

func _build_boosters() -> void:
	for id in GameData.boosters.keys():
		var def: Dictionary = GameData.boosters[id]
		var card := _row_card()
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		card.add_child(row)
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(v)
		v.add_child(VisualTheme.label(String(def.get("label", id)).to_upper(), VisualTheme.FS_BODY, VisualTheme.TEXT))
		v.add_child(VisualTheme.label(String(def.get("help", "")), VisualTheme.FS_MICRO, VisualTheme.TEXT_DIM, 0))
		row.add_child(VisualTheme.label("x %d" % Boosters.get_count(id), VisualTheme.FS_HEADING, VisualTheme.TEXT_GOLD))
		var buy := UiKit.button("BUY  %d¢" % int(def.get("cost", 0)),
			&"primary" if Economy.can_afford(int(def.get("cost", 0))) else &"tertiary", VisualTheme.FS_MICRO)
		buy.custom_minimum_size = Vector2(150, 54)
		buy.disabled = not Economy.can_afford(int(def.get("cost", 0)))
		buy.pressed.connect(func():
			if Boosters.purchase(id):
				Audio.play(&"button_tap"); _rebuild())
		row.add_child(buy)
		_body.add_child(card)

func _build_equipment() -> void:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_body.add_child(grid)
	for e in Inventory.all_equipment():
		var id := StringName(String(e["id"]))
		var owned: bool = Inventory.is_owned(id)
		var slot := StringName(String(e.get("slot", "")))
		var is_eq: bool = Inventory.equipped_in(slot) == id
		var card := PanelContainer.new()
		var sb := UiKit.glass(14, true)
		sb.border_color = UiKit.GOLD if is_eq else (UiKit.GLASS_BORDER if owned else Color(1, 1, 1, 0.08))
		sb.set_border_width_all(2 if is_eq else 1)
		card.add_theme_stylebox_override("panel", sb)
		card.custom_minimum_size = Vector2(170, 150)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 3)
		card.add_child(v)
		v.add_child(VisualTheme.label(String(e["name"]).to_upper(), VisualTheme.FS_CAPTION,
			VisualTheme.TEXT_GOLD if owned else VisualTheme.TEXT_DIM))
		v.add_child(VisualTheme.label("%s  ·  T%d" % [String(slot).capitalize(), int(e.get("tier", 1))], VisualTheme.FS_MICRO, VisualTheme.TEXT_DIM, 0))
		var desc := VisualTheme.label(String(e.get("bonus", "")), VisualTheme.FS_MICRO, VisualTheme.TEXT, 0)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(150, 46)
		v.add_child(desc)
		if not owned:
			v.add_child(VisualTheme.label("\U0001f512 boss reward", VisualTheme.FS_MICRO, VisualTheme.TEXT_DIM, 0))
		elif is_eq:
			v.add_child(VisualTheme.label("EQUIPPED", VisualTheme.FS_MICRO, VisualTheme.GOOD, 0))
		else:
			var eq := UiKit.button("EQUIP", &"primary", VisualTheme.FS_MICRO)
			eq.custom_minimum_size = Vector2(0, 40)
			eq.pressed.connect(func(): Audio.play(&"button_tap"); Inventory.equip(id))
			v.add_child(eq)
		grid.add_child(card)

func _build_items() -> void:
	var items: Dictionary = Inventory.collectibles()
	if items.is_empty():
		_body.add_child(VisualTheme.label("No relics yet. Clear boss stages to gather Kingdom Shards.",
			VisualTheme.FS_BODY, VisualTheme.TEXT_DIM, 0))
		return
	for id in items:
		var card := _row_card()
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		card.add_child(row)
		row.add_child(VisualTheme.label(String(id).replace("_", " ").capitalize(), VisualTheme.FS_BODY, VisualTheme.TEXT))
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(sp)
		row.add_child(VisualTheme.label("x %d" % int(items[id]), VisualTheme.FS_HEADING, VisualTheme.TEXT_GOLD))
		_body.add_child(card)
