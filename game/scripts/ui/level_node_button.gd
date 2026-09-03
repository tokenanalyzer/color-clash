class_name LevelNodeButton
extends Button
## One tappable node on the campaign map. Entirely custom-drawn (no art
## assets) to match Color Clash's layered-gem visual language: a shadowed,
## gradient-lit circle whose color/ring/icon read locked/current/completed/
## unlocked at a glance, with up to 3 stars shown above a completed node.

const NODE_RADIUS := 58.0
const _TOP_PADDING := 36.0 # room for the star row above the circle

var level_id: int = 0
var state: StringName = &"locked" # locked | unlocked | current | completed
var stars: int = 0

func configure(id: int, p_state: StringName, p_stars: int) -> void:
	level_id = id
	state = p_state
	stars = p_stars
	disabled = state == &"locked"
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(NODE_RADIUS * 2.0 + 20.0, NODE_RADIUS * 2.0 + _TOP_PADDING + 14.0)
	size = custom_minimum_size
	var empty := StyleBoxEmpty.new()
	for state_name in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state_name, empty)
	if state == &"current":
		_start_pulse()
	queue_redraw()

func _start_pulse() -> void:
	var tween := create_tween()
	tween.set_loops()
	tween.tween_property(self, "scale", Vector2(1.08, 1.08), 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _center() -> Vector2:
	return Vector2(size.x * 0.5, _TOP_PADDING + NODE_RADIUS)

func _draw() -> void:
	pivot_offset = size * 0.5
	var center := _center()

	draw_circle(center + Vector2(0, 5), NODE_RADIUS, Color(0, 0, 0, 0.38))

	var base_color: Color
	var ring_color: Color
	match state:
		&"locked":
			base_color = Color(0.27, 0.28, 0.33)
			ring_color = Color(0.16, 0.17, 0.21)
		&"current":
			base_color = Color(1.0, 0.62, 0.14)
			ring_color = Color(1.0, 0.87, 0.45)
		&"completed":
			base_color = Color(0.24, 0.72, 0.46)
			ring_color = Color(0.55, 0.95, 0.68)
		_:
			base_color = Color(0.28, 0.53, 0.94)
			ring_color = Color(0.55, 0.76, 1.0)

	# The current level gets an extra soft outer glow ring, on top of the
	# pulsing scale animation, so it's unmistakable even mid-scroll.
	if state == &"current":
		draw_arc(center, NODE_RADIUS + 10.0, 0.0, TAU, 40, Color(1.0, 0.75, 0.3, 0.45), 6.0, true)

	draw_circle(center, NODE_RADIUS, base_color)
	draw_arc(center, NODE_RADIUS - 2.5, 0.0, TAU, 40, ring_color, 5.0, true)
	draw_circle(center + Vector2(-NODE_RADIUS * 0.28, -NODE_RADIUS * 0.32), NODE_RADIUS * 0.3, Color(1, 1, 1, 0.22))

	var font := ThemeDB.fallback_font
	if state == &"locked":
		draw_arc(center + Vector2(0, -9), 14.0, PI, TAU, 16, Color(0.85, 0.85, 0.92), 4.5, true)
		draw_rect(Rect2(center + Vector2(-15, -6), Vector2(30, 22)), Color(0.85, 0.85, 0.92))
	else:
		var label := str(level_id)
		var font_size := 36
		var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		draw_string(font, center - text_size * 0.5 + Vector2(0, text_size.y * 0.32), label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color.WHITE)

	if state == &"completed":
		for i in 3:
			var star_center := center + Vector2(float(i - 1) * 24.0, -NODE_RADIUS - 17.0)
			_draw_star(star_center, 9.5, Color(1, 0.85, 0.2) if i < stars else Color(0.32, 0.33, 0.4))

func _draw_star(center: Vector2, r: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 10:
		var angle: float = -PI / 2.0 + float(i) * PI / 5.0
		var rad: float = r if i % 2 == 0 else r * 0.45
		points.append(center + Vector2(cos(angle), sin(angle)) * rad)
	draw_colored_polygon(points, color)
