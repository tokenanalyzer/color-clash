class_name RewardPopup
extends Control
## A celebratory "you got stuff" moment: a chest drops in, rattles, bursts
## open with particles, and the rewards fly out one by one and count up.
## Presentation only — it never touches Economy/Boosters itself; the caller
## grants on `claimed` so all economy mutation stays in one place.
##
## rewards: Array of { "type": "coins", "amount": int }
##                 or { "type": "booster", "id": StringName, "amount": int }
##                 or { "type": "stars", "amount": int }

signal claimed()

const _RARITY_TINT := {
	&"common": Color(0.36, 0.72, 0.42),
	&"rare": Color(0.30, 0.58, 0.95),
	&"epic": Color(0.62, 0.36, 0.92),
	&"legendary": Color(1.0, 0.78, 0.24),
}
## Rarity -> which prepared chest sprite opens (33 reward / 34 premium /
## 35 booster). `opts.chest` overrides it explicitly (milestone -> booster).
const _RARITY_CHEST := {
	&"common": &"eco_reward_chest", &"rare": &"eco_reward_chest",
	&"epic": &"eco_premium_chest", &"legendary": &"eco_premium_chest",
}
const _CHEST_KEY := {
	&"reward": &"eco_reward_chest", &"premium": &"eco_premium_chest", &"booster": &"eco_booster_chest",
}

var _rewards: Array = []
var _rarity: StringName = &"common"
var _chest_tex: StringName = &"eco_reward_chest"
var _rows: VBoxContainer
var _burst: CPUParticles2D
var _chest: ChestArt
var _fx: SpriteFX

static func present(parent: Node, rewards: Array, opts: Dictionary = {}) -> RewardPopup:
	var p := RewardPopup.new()
	p._rewards = rewards
	p._rarity = StringName(String(opts.get("rarity", _auto_rarity(rewards))))
	p._title_text = String(opts.get("title", "Reward!"))
	if opts.has("chest"):
		p._chest_tex = _CHEST_KEY.get(StringName(String(opts["chest"])), &"eco_reward_chest")
	else:
		p._chest_tex = _RARITY_CHEST.get(p._rarity, &"eco_reward_chest")
	parent.add_child(p)
	return p

static func _auto_rarity(rewards: Array) -> StringName:
	var coins := 0
	var boosters := 0
	for r in rewards:
		match String(r.get("type", "")):
			"coins": coins += int(r.get("amount", 0))
			"booster": boosters += int(r.get("amount", 1))
	if coins >= 600 or boosters >= 3:
		return &"legendary"
	if coins >= 350 or boosters >= 2:
		return &"epic"
	if coins >= 150 or boosters >= 1:
		return &"rare"
	return &"common"

var _title_text := "Reward!"

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_track_size()
	get_viewport().size_changed.connect(_track_size)

	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.0)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)
	scrim.create_tween().tween_property(scrim, "color", Color(0, 0, 0, 0.62), 0.25)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 560)
	panel.add_theme_stylebox_override("panel", VisualTheme.panel(Color(0.09, 0.10, 0.19, 0.98), 30, _tint(), 3))
	center.add_child(panel)

	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 14)
	panel.add_child(vb)

	var title := VisualTheme.label(_title_text, VisualTheme.FS_HEADING, VisualTheme.TEXT_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)

	_chest = ChestArt.new()
	_chest.tint = _tint()
	_chest.sprite_key = _chest_tex
	_chest.custom_minimum_size = Vector2(240, 200)
	vb.add_child(_chest)

	_fx = SpriteFX.new()
	add_child(_fx)

	_burst = CPUParticles2D.new()
	_burst.emitting = false
	_burst.one_shot = true
	_burst.amount = 60
	_burst.lifetime = 1.2
	_burst.explosiveness = 0.9
	_burst.spread = 180.0
	_burst.direction = Vector2.UP
	_burst.gravity = Vector2(0, 480)
	_burst.initial_velocity_min = 180.0
	_burst.initial_velocity_max = 420.0
	_burst.scale_amount_min = 3.0
	_burst.scale_amount_max = 6.0
	_burst.color = _tint().lightened(0.3)
	_chest.add_child(_burst)
	_burst.position = Vector2(110, 70)

	_rows = VBoxContainer.new()
	_rows.alignment = BoxContainer.ALIGNMENT_CENTER
	_rows.add_theme_constant_override("separation", 10)
	vb.add_child(_rows)

	var collect := Button.new()
	collect.text = "COLLECT"
	collect.custom_minimum_size = Vector2(280, 70)
	collect.add_theme_font_size_override("font_size", VisualTheme.FS_BUTTON)
	collect.add_theme_color_override("font_color", VisualTheme.TEXT)
	collect.add_theme_constant_override("outline_size", 5)
	collect.add_theme_color_override("font_outline_color", VisualTheme.OUTLINE)
	collect.add_theme_stylebox_override("normal", VisualTheme.button_face(VisualTheme.GOOD.darkened(0.1)))
	collect.add_theme_stylebox_override("hover", VisualTheme.button_face(VisualTheme.GOOD))
	collect.add_theme_stylebox_override("pressed", VisualTheme.button_face(VisualTheme.GOOD.darkened(0.3)))
	collect.focus_mode = Control.FOCUS_NONE
	collect.modulate.a = 0.0
	collect.pressed.connect(_on_collect)
	vb.add_child(collect)
	_collect_btn = collect

	panel.pivot_offset = panel.custom_minimum_size * 0.5
	panel.scale = Vector2(0.8, 0.8)
	panel.modulate.a = 0.0
	var pin := panel.create_tween()
	pin.set_parallel(true)
	pin.tween_property(panel, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pin.tween_property(panel, "modulate:a", 1.0, 0.2)

	_run_sequence()

var _collect_btn: Button

func _track_size() -> void:
	var vp := get_viewport_rect().size
	size = vp
	custom_minimum_size = vp

func _tint() -> Color:
	return _RARITY_TINT.get(_rarity, Color(0.4, 0.7, 0.5))

func _run_sequence() -> void:
	await get_tree().create_timer(0.35).timeout
	await _chest.drop_in()
	await _chest.rattle()
	Audio.play(&"level_complete")
	_chest.open()
	var cc := _chest.global_position + _chest.size * 0.5
	_fx.play_hold(&"cel_treasure_explosion", cc, 320.0, Color(1, 1, 1), 0.7, true, 0.5)
	_burst.restart()
	_burst.emitting = true
	await get_tree().create_timer(0.25).timeout

	for r in _rewards:
		_add_reward_row(r)
		if String(r.get("type", "")) == "coins":
			_fx.play(&"eco_coin_burst", cc + Vector2(0, 40.0), 180.0, Color(1, 1, 1), 0.5, true)
		Audio.play(&"combo_ding", 0.4)
		await get_tree().create_timer(0.16).timeout

	await get_tree().create_timer(0.15).timeout
	var t := _collect_btn.create_tween()
	t.tween_property(_collect_btn, "modulate:a", 1.0, 0.2)

func _add_reward_row(r: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)

	var kind := String(r.get("type", ""))
	var amount := int(r.get("amount", 1))
	var label := VisualTheme.label("", VisualTheme.FS_BODY, VisualTheme.TEXT)

	if kind == "coins":
		var icon := HUD.GemIcon.new()
		icon.kind = &"coin"
		icon.custom_minimum_size = Vector2(30, 30)
		row.add_child(icon)
		row.add_child(label)
		label.create_tween().tween_method(
			func(v: float): label.text = "+%d" % int(round(v)), 0.0, float(amount), 0.5)
	elif kind == "booster":
		var bid := StringName(String(r.get("id", "bomb")))
		var ptex := AssetLibrary.power(bid)
		if ptex != null:
			var tr := TextureRect.new()
			tr.texture = ptex
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.custom_minimum_size = Vector2(44, 44)
			row.add_child(tr)
		else:
			var g := IconDraw.IconRect.new()
			g.id = bid
			g.custom_minimum_size = Vector2(32, 32)
			row.add_child(g)
		label.text = "%s  x%d" % [String(r.get("id", "booster")).capitalize().replace("_", " "), amount]
		row.add_child(label)
	elif kind == "stars":
		var sr := HUD.GemIcon.new()
		sr.kind = &"score"
		sr.custom_minimum_size = Vector2(30, 30)
		row.add_child(sr)
		label.text = "x%d" % amount
		label.add_theme_color_override("font_color", VisualTheme.STAR)
		row.add_child(label)
	else:
		label.text = str(r)
		row.add_child(label)

	row.modulate.a = 0.0
	row.pivot_offset = Vector2(120, 16)
	row.scale = Vector2(0.6, 0.6)
	_rows.add_child(row)
	var t := row.create_tween()
	t.set_parallel(true)
	t.tween_property(row, "modulate:a", 1.0, 0.2)
	t.tween_property(row, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_collect() -> void:
	Audio.play(&"button_tap")
	claimed.emit()
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.2)
	t.tween_callback(queue_free)


## Code-drawn treasure chest with a hinged lid. All motion is internal
## offsets (not `position`) so a parent container can't fight it.
class ChestArt extends Control:
	var tint: Color = Color(0.4, 0.7, 0.5)
	var sprite_key: StringName = &"eco_reward_chest"
	var lid_angle := 0.0          # radians, 0 = closed, negative = open (tilt cue)
	var _shake := 0.0
	var _drop := 0.0             # extra Y offset for the drop-in

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func drop_in() -> void:
		_drop = -180.0
		var t := create_tween()
		t.tween_method(func(v): _drop = v; queue_redraw(), -180.0, 0.0, 0.4).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		await t.finished

	func rattle() -> void:
		var t := create_tween()
		for i in 3:
			t.tween_method(func(v): _shake = v; queue_redraw(), -0.12, 0.12, 0.06)
			t.tween_method(func(v): _shake = v; queue_redraw(), 0.12, -0.12, 0.06)
		t.tween_method(func(v): _shake = v; queue_redraw(), -0.12, 0.0, 0.05)
		await t.finished

	func open() -> void:
		var t := create_tween()
		t.tween_method(func(v): lid_angle = v; queue_redraw(), 0.0, -1.9, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var cx := w * 0.5 + _shake * 40.0

		# prepared chest sprite (33/34/35) — shake via x-offset + a slight tilt
		# as it "opens", glow spilling once open. No vector chest when present.
		var tex := AssetLibrary.tex(sprite_key)
		if tex != null:
			var s := minf(w, h * 1.05) * 0.92
			var m: float = maxf(float(tex.get_width()), float(tex.get_height()))
			var iw := s * tex.get_width() / m
			var ih := s * tex.get_height() / m
			var cy := h * 0.52 + _drop
			VisualTheme.draw_glow(self, Vector2(cx, cy + ih * 0.2), iw * 0.62,
				Color(tint.r, tint.g, tint.b, 0.4 + 0.3 * clampf(-lid_angle, 0.0, 1.0)), 5)
			draw_set_transform(Vector2(cx, cy), _shake * 0.35 + lid_angle * 0.06, Vector2.ONE)
			draw_texture_rect(tex, Rect2(-iw * 0.5, -ih * 0.5, iw, ih), false)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			if lid_angle < -0.4:
				VisualTheme.draw_glow(self, Vector2(cx, cy - ih * 0.15), iw * 0.5,
					Color(1, 0.95, 0.7, 0.55 * clampf(-lid_angle, 0.0, 1.0)), 4)
			return

		var base_y := h * 0.60 + _drop
		var bw := w * 0.62
		var bh := h * 0.34

		VisualTheme.draw_glow(self, Vector2(cx, base_y + bh * 0.4), bw * 0.95, Color(tint.r, tint.g, tint.b, 0.4), 5)
		# body
		var body := Rect2(cx - bw * 0.5, base_y, bw, bh)
		draw_rect(body, Color(0.40, 0.26, 0.15))
		draw_rect(Rect2(body.position, Vector2(body.size.x, body.size.y * 0.30)), Color(0.5, 0.34, 0.2))
		var bring := body.grow(-1.0)
		draw_rect(Rect2(bring.position, Vector2(bring.size.x, 3)), Color(1, 1, 1, 0.12))
		# gold bands + lock plate
		draw_rect(Rect2(cx - bw * 0.5, base_y + bh * 0.55, bw, 6), tint)
		draw_rect(Rect2(cx - 9, base_y - bh * 0.28, 18, bh * 0.9), tint)
		draw_circle(Vector2(cx, base_y + bh * 0.18), 7, Color(0.14, 0.11, 0.09))
		# hinged lid — pivots at the back-top edge of the body
		var pivot := Vector2(cx - bw * 0.5, base_y)
		var lid_pts := PackedVector2Array([
			Vector2(0, 0), Vector2(bw, 0), Vector2(bw, -bh * 0.42), Vector2(bw * 0.5, -bh * 0.58), Vector2(0, -bh * 0.42),
		])
		var rot := PackedVector2Array()
		for p in lid_pts:
			rot.append(pivot + p.rotated(lid_angle))
		draw_colored_polygon(rot, Color(0.46, 0.30, 0.18))
		var edge := rot.duplicate()
		edge.append(rot[0])
		draw_polyline(edge, tint, 3.0, true)
		# inner glow spilling out once open
		if lid_angle < -0.4:
			VisualTheme.draw_glow(self, Vector2(cx, base_y - 2), bw * 0.4,
				Color(1, 0.95, 0.7, 0.5 * clampf(-lid_angle, 0.0, 1.0)), 4)
