class_name LevelNodeButton
extends Button
## One tappable campaign node. Fully code-drawn to match Color Clash's
## glossy-gem language: a shadowed, gradient-lit disc whose colour, ring and
## icon read locked / unlocked / current / completed at a glance, with a
## star arc above a cleared level and a crowned, rotating-ring treatment on
## the current one. Every Nth node is flagged `is_chest` for a reward beat.

const NODE_RADIUS := 44.0
const _TOP_PADDING := 34.0

var level_id: int = 0
var state: StringName = &"locked" # locked | unlocked | current | completed
var stars: int = 0
var is_chest: bool = false
var _spin := 0.0
var _bob := 0.0

func configure(id: int, p_state: StringName, p_stars: int, p_is_chest: bool = false) -> void:
	level_id = id
	state = p_state
	stars = p_stars
	is_chest = p_is_chest
	disabled = state == &"locked"
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(NODE_RADIUS * 2.0 + 24.0, NODE_RADIUS * 2.0 + _TOP_PADDING + 16.0)
	size = custom_minimum_size
	var empty := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(s, empty)
	set_process(state == &"current")
	if state == &"current":
		_start_pulse()
	queue_redraw()

func _process(delta: float) -> void:
	_spin += delta * 1.4
	_bob += delta
	queue_redraw()

func _start_pulse() -> void:
	var tween := create_tween()
	tween.set_loops()
	tween.tween_property(self, "scale", Vector2(1.07, 1.07), 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _center() -> Vector2:
	var y_off := sin(_bob * 2.2) * 2.5 if state == &"current" else 0.0
	return Vector2(size.x * 0.5, _TOP_PADDING + NODE_RADIUS + y_off)

func _draw() -> void:
	pivot_offset = size * 0.5
	var c := _center()
	var r := NODE_RADIUS

	var base: Color
	var ring: Color
	match state:
		&"locked":
			base = Color(0.24, 0.25, 0.31); ring = Color(0.15, 0.16, 0.2)
		&"current":
			base = Color(1.0, 0.66, 0.16); ring = Color(1.0, 0.88, 0.5)
		&"completed":
			base = Color(0.26, 0.6, 0.96); ring = Color(0.6, 0.82, 1.0)
		_:
			base = Color(0.4, 0.78, 0.55); ring = Color(0.7, 0.96, 0.8)

	# aura for the current node
	if state == &"current":
		VisualTheme.draw_glow(self, c, r * 2.0, Color(1.0, 0.8, 0.3, 0.35), 5)

	# shadow + disc + gloss
	draw_circle(c + Vector2(0, 5), r, Color(0, 0, 0, 0.4))
	var disc := ShapeDrawUtils.regular_polygon(28, r, 0.0, c)
	draw_polygon(disc, ShapeDrawUtils.vertical_shade(disc, base.lightened(0.3), base.darkened(0.35)))
	draw_arc(c, r - 2.0, 0, TAU, 32, ring, 4.0, true)
	draw_circle(c + Vector2(-r * 0.3, -r * 0.34), r * 0.28, Color(1, 1, 1, 0.28))

	# rotating dashed ring on the current node
	if state == &"current":
		for i in 12:
			var a := _spin + TAU * float(i) / 12.0
			var p1 := c + Vector2(cos(a), sin(a)) * (r + 7.0)
			var p2 := c + Vector2(cos(a), sin(a)) * (r + 13.0)
			draw_line(p1, p2, Color(1.0, 0.9, 0.5, 0.9), 3.0, true)
		_draw_crown(c + Vector2(0, -r - 16.0))

	var font := ThemeDB.fallback_font
	if state == &"locked":
		draw_arc(c + Vector2(0, -7), 11.0, PI, TAU, 14, Color(0.8, 0.82, 0.9), 3.5, true)
		draw_rect(Rect2(c + Vector2(-12, -5), Vector2(24, 18)), Color(0.8, 0.82, 0.9))
	elif is_chest:
		_draw_chest(c)
	else:
		var label := str(level_id)
		var fs := 30
		var ts := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		draw_string_outline(font, c - ts * 0.5 + Vector2(0, ts.y * 0.32), label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, 4, Color(0, 0, 0, 0.5))
		draw_string(font, c - ts * 0.5 + Vector2(0, ts.y * 0.32), label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Color.WHITE)

	if state == &"completed":
		var arc_r := r + 16.0
		for i in 3:
			var a := deg_to_rad(-130.0 + float(i) * 40.0)
			var sc := c + Vector2(cos(a), sin(a)) * arc_r
			_draw_star(sc, 9.0, VisualTheme.STAR if i < stars else Color(0.3, 0.31, 0.38))

func _draw_crown(p: Vector2) -> void:
	var w := 20.0
	var pts := PackedVector2Array([
		p + Vector2(-w, 6), p + Vector2(-w, -4), p + Vector2(-w * 0.4, 3),
		p + Vector2(0, -8), p + Vector2(w * 0.4, 3), p + Vector2(w, -4), p + Vector2(w, 6),
	])
	draw_colored_polygon(pts, VisualTheme.STAR)
	draw_polyline(pts, VisualTheme.STAR.darkened(0.3), 1.5, true)

func _draw_chest(c: Vector2) -> void:
	draw_rect(Rect2(c + Vector2(-18, -4), Vector2(36, 22)), Color(0.55, 0.36, 0.18))
	draw_rect(Rect2(c + Vector2(-18, -14), Vector2(36, 12)), Color(0.7, 0.47, 0.22))
	draw_rect(Rect2(c + Vector2(-3, -8), Vector2(6, 10)), VisualTheme.STAR)
	draw_line(c + Vector2(-18, -2), c + Vector2(18, -2), Color(1, 0.85, 0.4), 2.0)

func _draw_star(center: Vector2, rad: float, color: Color) -> void:
	draw_colored_polygon(ShapeDrawUtils.star_points(center, rad + 2.0), Color(0, 0, 0, 0.35))
	draw_colored_polygon(ShapeDrawUtils.star_points(center, rad), color)
