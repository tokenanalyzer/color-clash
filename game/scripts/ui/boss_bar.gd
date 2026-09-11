class_name BossBar
extends Control
## Boss presentation strip for stages 10 / 20 / 30 / 40 / 50 — a framed
## portrait, the boss name, a red HP bar with damage flash, and a defeat
## fade. Stage 50 (Jinn) gets the larger gold-framed "final boss" treatment.
## Pure presentation; CombatDirector owns the numbers.

var _portrait: TextureRect
var _name_label: Label
var _hp := 1.0
var _hp_shown := 1.0
var _flash := 0.0
var _t := 0.0
var _final := false
var _defeated := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, 92)
	set_process(true)

	_portrait = TextureRect.new()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait.clip_contents = true
	add_child(_portrait)

	_name_label = VisualTheme.label("", VisualTheme.FS_HEADING, VisualTheme.TEXT, 5)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name_label)

func configure(boss_name: String, face: Texture2D, is_final: bool) -> void:
	_final = is_final
	_defeated = false
	_hp = 1.0
	_hp_shown = 1.0
	custom_minimum_size = Vector2(0, 118 if is_final else 88)
	_portrait.texture = face
	_name_label.text = boss_name
	_name_label.add_theme_color_override("font_color", VisualTheme.ACCENT_HOT if is_final else VisualTheme.TEXT)
	_name_label.add_theme_font_size_override("font_size", VisualTheme.FS_TITLE if is_final else VisualTheme.FS_HEADING)
	modulate.a = 0.0
	visible = true
	_relayout()
	var t := create_tween()
	t.tween_property(self, "modulate:a", 1.0, 0.3)
	queue_redraw()

func set_hp(hp: int, hp_max: int) -> void:
	_hp = clampf(float(hp) / float(maxi(hp_max, 1)), 0.0, 1.0)
	_flash = 1.0
	var t := create_tween()
	t.tween_property(self, "_hp_shown", _hp, 0.25).set_trans(Tween.TRANS_CUBIC)

func play_defeat() -> void:
	_defeated = true
	_name_label.text += "  —  DEFEATED"
	var t := create_tween()
	t.tween_interval(0.6)
	t.tween_property(self, "modulate:a", 0.0, 0.5)
	t.tween_callback(func(): visible = false)

## Boss reacts to a Jamie hit. `kind`: hit | heavy_hit | knockback | stun.
## Pure presentation — a portrait flinch/knock + a bar flash. HP is set
## separately via set_hp() so this can never desync the numbers.
func play_hit(kind: StringName) -> void:
	if _defeated or _portrait == null:
		return
	_flash = 1.0
	queue_redraw()
	var knock: float = {&"hit": 6.0, &"heavy_hit": 20.0, &"knockback": 26.0, &"stun": 12.0}.get(kind, 6.0)
	var base := Vector2(8, 7)
	_portrait.position = base
	var t := _portrait.create_tween()
	t.tween_property(_portrait, "position", base + Vector2(knock, 0), 0.05).set_trans(Tween.TRANS_SINE)
	t.tween_property(_portrait, "position", base, 0.22).set_trans(Tween.TRANS_ELASTIC)
	if kind == &"stun":
		var s := _portrait.create_tween()
		s.tween_property(_portrait, "rotation", 0.12, 0.06)
		s.tween_property(_portrait, "rotation", -0.12, 0.12)
		s.tween_property(_portrait, "rotation", 0.0, 0.1)

## The final boss watches / taunts (stage 50 flavour) — a quick portrait
## pulse + dark glow flash. No effect on HP or victory logic.
func play_taunt() -> void:
	if _defeated or _portrait == null:
		return
	var pc := _portrait.pivot_offset
	_portrait.pivot_offset = _portrait.size * 0.5
	var t := _portrait.create_tween()
	t.tween_property(_portrait, "scale", Vector2(1.14, 1.14), 0.12).set_trans(Tween.TRANS_BACK)
	t.tween_property(_portrait, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_ELASTIC)
	t.tween_callback(func(): _portrait.pivot_offset = pc)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_relayout()

func _relayout() -> void:
	if _portrait == null or _name_label == null:
		return
	var h := size.y
	var ps := h - 14.0
	_portrait.position = Vector2(8, 7)
	_portrait.size = Vector2(ps, ps)
	_name_label.position = Vector2(ps + 22, 4)

func _process(delta: float) -> void:
	_t += delta
	if _flash > 0.001 or _final:
		_flash = maxf(_flash - delta * 3.0, 0.0)
		queue_redraw()

func _draw() -> void:
	var h := size.y
	var w := size.x
	var ps := h - 14.0
	var gold := UiKit.GOLD if _final else Color(0.8, 0.3, 0.32)

	# panel
	var panel := Rect2(0, 0, w, h)
	_round(panel, 16.0, Color(0.06, 0.05, 0.10, 0.86))
	_round_outline(panel.grow(-1.0), 15.0, Color(gold.r, gold.g, gold.b, 0.8), 2.5 if _final else 2.0)
	if _final:
		VisualTheme.draw_glow(self, Vector2(w * 0.5, h * 0.5), w * 0.5,
			Color(0.7, 0.25, 0.9, 0.10 + 0.06 * sin(_t * 3.0)), 4)

	# portrait ring
	var pc := Vector2(8 + ps * 0.5, 7 + ps * 0.5)
	draw_circle(pc, ps * 0.5 + 3.0, Color(gold.r, gold.g, gold.b, 0.9))
	draw_circle(pc, ps * 0.5 + 1.0, Color(0.04, 0.04, 0.09, 1.0))

	# HP track + fill (under the name) — thicker, gold-framed, with a soft
	# glow and a small gem riding the fill's leading edge (2026-09-05 UI
	# pass: the boss fight is the campaign's climax, this bar should read
	# as premium as the Fever meter elsewhere in the same HUD).
	var bx := ps + 22.0
	var by := h - 34.0
	var bw := w - bx - 18.0
	var bh := 20.0
	_round(Rect2(bx, by, bw, bh), 10.0, Color(0.02, 0.02, 0.05, 0.95))
	if _hp_shown > 0.001:
		var fill := Rect2(bx, by, bw * _hp_shown, bh)
		var fc := Color(0.95, 0.22, 0.26) if not _final else Color(0.85, 0.2, 0.55)
		if _flash > 0.0:
			fc = fc.lerp(Color(1, 1, 1), _flash)
		_round(fill, 10.0, fc)
		_round(Rect2(fill.position + Vector2(0, 2), Vector2(fill.size.x, bh * 0.4)), 10.0, Color(1, 1, 1, 0.28))
		var lead := Vector2(fill.position.x + fill.size.x, fill.position.y + bh * 0.5)
		VisualTheme.draw_glow(self, lead, bh * 1.1, Color(fc.r, fc.g, fc.b, 0.35 + 0.15 * sin(_t * 5.0)), 3)
		draw_circle(lead, bh * 0.34, Color(gold.r, gold.g, gold.b, 0.95))
		draw_arc(lead, bh * 0.34, 0, TAU, 12, Color(1, 1, 1, 0.8), 1.4, true)
	_round_outline(Rect2(bx, by, bw, bh), 10.0, Color(gold.r, gold.g, gold.b, 0.7), 2.0)
	if _flash > 0.0:
		_round(panel, 16.0, Color(1, 0.4, 0.4, 0.12 * _flash))

func _round(r: Rect2, rad: float, col: Color) -> void:
	var pts := ShapeDrawUtils.rounded_rect_points(r.size, minf(rad, r.size.y * 0.5), 5)
	var m := PackedVector2Array()
	for p in pts:
		m.append(p + r.position + r.size * 0.5)
	draw_colored_polygon(m, col)

func _round_outline(r: Rect2, rad: float, col: Color, wd: float) -> void:
	var pts := ShapeDrawUtils.rounded_rect_points(r.size, minf(rad, r.size.y * 0.5), 6)
	var m := PackedVector2Array()
	for p in pts:
		m.append(p + r.position + r.size * 0.5)
	m.append(m[0])
	draw_polyline(m, col, wd, true)
