class_name Backdrop
extends Node2D
## Full-screen premium environment shared by every screen: a deep layered
## navy gradient, two slow drifting colour "nebula" washes, a soft aurora
## band, drifting parallax light motes, a faint star field and a corner
## vignette. Still one canvas item and cheap on the gl_compatibility
## renderer. `accent` tints the washes/motes so menu, map and gameplay each
## feel subtly different, and it lerps warm during Fever.

var accent: Color = VisualTheme.ACCENT
var _size: Vector2 = Vector2(1080, 1920)
var _motes: Array = []
var _stars: Array = []
var _time := 0.0
var _accent_tween: Tween

func set_accent_target(color: Color, duration: float = 0.6) -> void:
	if _accent_tween != null and _accent_tween.is_valid():
		_accent_tween.kill()
	_accent_tween = create_tween()
	_accent_tween.tween_property(self, "accent", color, duration).set_trans(Tween.TRANS_SINE)

func _ready() -> void:
	z_index = -100
	z_as_relative = false
	_resize()
	get_viewport().size_changed.connect(_resize)
	_seed()

func _resize() -> void:
	_size = get_viewport().get_visible_rect().size
	queue_redraw()

func _seed() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20240531
	_motes.clear()
	for i in 20:
		_motes.append({
			"x": rng.randf(), "y": rng.randf(),
			"r": rng.randf_range(2.0, 8.0),
			"speed": rng.randf_range(0.004, 0.02),
			"phase": rng.randf() * TAU,
			"bright": rng.randf_range(0.12, 0.4),
			"depth": rng.randf_range(0.3, 1.0),
		})
	_stars.clear()
	for i in 70:
		_stars.append({
			"x": rng.randf(), "y": rng.randf(),
			"r": rng.randf_range(0.6, 1.8),
			"phase": rng.randf() * TAU,
			"speed": rng.randf_range(0.6, 2.2),
		})

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func _draw() -> void:
	var w := _size.x
	var h := _size.y
	var rect := Rect2(Vector2.ZERO, _size)

	# base gradient — a touch of accent bled into the top third
	var top := VisualTheme.BG_TOP.lerp(Color(accent.r, accent.g, accent.b, 1.0), 0.06)
	VisualTheme.draw_v_gradient(self, rect, top, VisualTheme.BG_BOTTOM, 24)

	# star field (very faint, twinkling)
	for s in _stars:
		var tw: float = 0.35 + 0.65 * (0.5 + 0.5 * sin(_time * s["speed"] + s["phase"]))
		draw_circle(Vector2(s["x"] * w, s["y"] * h), s["r"], Color(0.7, 0.8, 1.0, 0.12 * tw))

	# two slow nebula washes drifting in a lissajous path
	var n1 := Vector2(w * (0.3 + 0.12 * sin(_time * 0.05)), h * (0.22 + 0.06 * cos(_time * 0.04)))
	var n2 := Vector2(w * (0.72 + 0.10 * cos(_time * 0.037)), h * (0.6 + 0.05 * sin(_time * 0.045)))
	_wash(n1, w * 0.85, Color(accent.r, accent.g, accent.b, 0.11))
	_wash(n2, w * 0.95, Color(accent.b * 0.9, accent.r * 0.7, accent.g, 0.08))

	# aurora band — a soft horizontal ribbon low on the screen
	var ay := h * (0.78 + 0.02 * sin(_time * 0.3))
	for i in 5:
		var t := float(i) / 4.0
		draw_rect(Rect2(0, ay - 60 + t * 80, w, 26),
			Color(accent.r, accent.g * 1.1, accent.b, (0.05 - 0.01 * i) * (0.7 + 0.3 * sin(_time * 0.6 + t * 3.0))))

	# parallax motes
	for m in _motes:
		var y: float = fposmod(m["y"] - _time * m["speed"], 1.0)
		var px: float = m["x"] * w + sin(_time * 0.3 + m["phase"]) * 24.0 * m["depth"]
		var tw: float = 0.5 + 0.5 * sin(_time * 1.2 + m["phase"])
		var c := Color(accent.r, accent.g, accent.b, m["bright"] * tw * m["depth"])
		draw_circle(Vector2(px, y * h), m["r"] * (0.6 + 0.4 * tw) * m["depth"], c)
		draw_circle(Vector2(px, y * h), m["r"] * 3.0 * m["depth"], Color(accent.r, accent.g, accent.b, m["bright"] * 0.08 * tw))

	# corner vignette
	var cx := _size * 0.5
	for i in 6:
		var t := float(i) / 5.0
		draw_arc(cx, _size.length() * 0.5 * (0.5 + t * 0.6), 0, TAU, 48,
			Color(0, 0, 0, 0.11), _size.length() * 0.15, false)

func _wash(center: Vector2, radius: float, col: Color) -> void:
	var layers := 12
	for i in range(layers, 0, -1):
		var t := float(i) / float(layers)
		draw_circle(center, radius * t, Color(col.r, col.g, col.b, col.a * pow(1.0 - t, 1.8) * 0.5))
