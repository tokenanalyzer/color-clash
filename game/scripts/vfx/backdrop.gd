class_name Backdrop
extends Node2D
## Full-screen premium background shared by every screen: a deep vertical
## navy gradient, a soft radial vignette, and a handful of slow-drifting
## light motes for depth. One canvas item, ~30 cheap draw calls, safe on
## the gl_compatibility renderer. `accent` tints the motes/glow so the menu,
## map and gameplay can each feel subtly different without new nodes.

var accent: Color = VisualTheme.ACCENT
var _size: Vector2 = Vector2(1080, 1920)
var _motes: Array = [] # [{pos, r, speed, phase, tint}]
var _time := 0.0
var _accent_tween: Tween

## Smoothly shifts the whole backdrop tint (used to push the scene warm
## during Fever, then back).
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
	_seed_motes()

func _resize() -> void:
	_size = get_viewport().get_visible_rect().size
	queue_redraw()

func _seed_motes() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20240531
	_motes.clear()
	for i in 22:
		_motes.append({
			"x": rng.randf(),
			"y": rng.randf(),
			"r": rng.randf_range(2.0, 7.0),
			"speed": rng.randf_range(0.004, 0.018),
			"phase": rng.randf() * TAU,
			"bright": rng.randf_range(0.15, 0.5),
		})

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, _size)
	VisualTheme.draw_v_gradient(self, rect, VisualTheme.BG_TOP, VisualTheme.BG_BOTTOM, 20)

	# high, soft accent glow near the top — the "stage light"
	VisualTheme.draw_glow(self, Vector2(_size.x * 0.5, _size.y * 0.16), _size.x * 0.7,
		Color(accent.r, accent.g, accent.b, 0.10), 5)

	for m in _motes:
		var y: float = fposmod(m["y"] - _time * m["speed"], 1.0)
		var p := Vector2(m["x"] * _size.x + sin(_time * 0.3 + m["phase"]) * 18.0, y * _size.y)
		var tw: float = 0.55 + 0.45 * sin(_time * 1.3 + m["phase"])
		var c := Color(accent.r, accent.g, accent.b, m["bright"] * tw)
		draw_circle(p, m["r"] * (0.7 + 0.3 * tw), c)
		draw_circle(p, m["r"] * 2.4, Color(accent.r, accent.g, accent.b, m["bright"] * 0.12 * tw))

	# vignette: darkened corners via a big ring stack
	var cx := _size * 0.5
	for i in 6:
		var t := float(i) / 5.0
		draw_arc(cx, _size.length() * 0.5 * (0.55 + t * 0.55), 0, TAU, 48,
			Color(0, 0, 0, 0.10), _size.length() * 0.14, false)
