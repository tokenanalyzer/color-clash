class_name Backdrop
extends Node2D
## Full-screen premium environment shared by every screen: a deep multi-stop
## navy-to-indigo gradient, a breathing "hero" glow behind the play area,
## three slow drifting colour blooms, a soft diagonal light wash, faint
## parallax gem silhouettes, a drifting mote field, a subtle star field and
## a focusing corner vignette. Still one CanvasItem and cheap on the
## gl_compatibility renderer — no textures, no shaders.
##
## `accent` tints the blooms / motes / hero glow so menu, map and gameplay
## each feel subtly different, and it lerps warm during Fever. The whole
## thing is deliberately low-contrast so the board and UI always read on top.

var accent: Color = VisualTheme.ACCENT
var _size: Vector2 = Vector2(1080, 1920)
var _motes: Array = []
var _stars: Array = []
var _gems: Array = []
var _time := 0.0
var _accent_tween: Tween

## Prepared full-screen scene painting (assets 58-67). When set it is drawn
## cover-fit (aspect kept, centred) as the base layer and the procedural field
## below is dialled down to a light animated wash over it. `_scene_a` is the
## live texture, `_scene_b`/`_scene_mix` handle a soft crossfade on change.
var scene_id: StringName = &""
var _scene_a: Texture2D
var _scene_b: Texture2D
var _scene_mix := 1.0
var _scene_tween: Tween

func set_accent_target(color: Color, duration: float = 0.6) -> void:
	if _accent_tween != null and _accent_tween.is_valid():
		_accent_tween.kill()
	_accent_tween = create_tween()
	_accent_tween.tween_property(self, "accent", color, duration).set_trans(Tween.TRANS_SINE)

## Swap the background scene with a crossfade. `id` is an Assets env_* key.
func set_scene(id: StringName, duration: float = 0.5) -> void:
	if id == scene_id and _scene_a != null:
		return
	scene_id = id
	var tex := AssetLibrary.tex(id)
	if tex == null:
		return
	if _scene_a == null:
		_scene_a = tex
		_scene_mix = 1.0
		queue_redraw()
		return
	_scene_b = tex
	_scene_mix = 0.0
	if _scene_tween != null and _scene_tween.is_valid():
		_scene_tween.kill()
	_scene_tween = create_tween()
	_scene_tween.tween_method(func(v: float): _scene_mix = v; queue_redraw(), 0.0, 1.0, duration)
	_scene_tween.tween_callback(func():
		_scene_a = _scene_b
		_scene_b = null
		_scene_mix = 1.0)

## Pick the world scene for a 1-based campaign level id.
func set_scene_for_level(level_id: int) -> void:
	var tex := AssetLibrary.world_for_level(level_id)
	if tex != null:
		var idx := int(max(level_id - 1, 0) / 10) % AssetLibrary.ENV_WORLD_CYCLE.size()
		set_scene(AssetLibrary.ENV_WORLD_CYCLE[idx])

## Cover-fit rect for a texture inside `_size` (aspect kept, centre-cropped).
func _cover_rect(tex: Texture2D) -> Rect2:
	var tw: float = float(tex.get_width())
	var th: float = float(tex.get_height())
	var k: float = maxf(_size.x / tw, _size.y / th)
	var dw := tw * k
	var dh := th * k
	return Rect2((_size - Vector2(dw, dh)) * 0.5, Vector2(dw, dh))

func _ready() -> void:
	z_index = -100
	z_as_relative = false
	_resize()
	get_viewport().size_changed.connect(_resize)
	_seed()
	if scene_id == &"":
		scene_id = &"env_main_background"
	_scene_a = AssetLibrary.tex(scene_id)

func _resize() -> void:
	_size = get_viewport().get_visible_rect().size
	queue_redraw()

func _seed() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20240531
	_motes.clear()
	for i in 22:
		_motes.append({
			"x": rng.randf(), "y": rng.randf(),
			"r": rng.randf_range(2.0, 7.0),
			"speed": rng.randf_range(0.004, 0.018),
			"phase": rng.randf() * TAU,
			"bright": rng.randf_range(0.10, 0.34),
			"depth": rng.randf_range(0.3, 1.0),
		})
	_stars.clear()
	for i in 80:
		_stars.append({
			"x": rng.randf(), "y": rng.randf(),
			"r": rng.randf_range(0.6, 1.9),
			"phase": rng.randf() * TAU,
			"speed": rng.randf_range(0.5, 2.0),
		})
	# faint drifting hex "gem" silhouettes — ties the ambient field to the
	# Color Clash identity without pulling focus.
	_gems.clear()
	for i in 7:
		_gems.append({
			"x": rng.randf(), "y": rng.randf(),
			"r": rng.randf_range(46.0, 120.0),
			"speed": rng.randf_range(0.006, 0.016),
			"spin": rng.randf_range(-0.25, 0.25),
			"phase": rng.randf() * TAU,
			"hue": rng.randi_range(0, 5),
		})

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

const _GEM_HUES := [
	Color(0.95, 0.30, 0.42), Color(1.0, 0.62, 0.24), Color(1.0, 0.85, 0.30),
	Color(0.36, 0.82, 0.52), Color(0.34, 0.62, 1.0), Color(0.64, 0.40, 0.96),
]

func _draw() -> void:
	var w := _size.x
	var h := _size.y
	var rect := Rect2(Vector2.ZERO, _size)

	# a desaturated, tamed version of the accent so a bright screen accent
	# (e.g. gold on the Daily screen) can't blow the whole backdrop out.
	var luma: float = accent.r * 0.3 + accent.g * 0.59 + accent.b * 0.11
	var tint := accent.lerp(Color(luma, luma, luma), 0.45)

	# 1. base layer — a prepared full-screen scene (cover-fit), or the
	#    procedural deep gradient when no scene art is available.
	var has_scene := _scene_a != null
	if has_scene:
		draw_texture_rect(_scene_a, _cover_rect(_scene_a), false)
		if _scene_b != null and _scene_mix < 1.0:
			draw_texture_rect(_scene_b, _cover_rect(_scene_b), false, Color(1, 1, 1, _scene_mix))
		# a slow aurora band drifting across the sky (soft overlay)
		var aur := AssetLibrary.tex(&"env_aurora_energy_bands")
		if aur != null:
			var ar := _cover_rect(aur)
			ar.position.x += sin(_time * 0.06) * w * 0.04
			ar.position.y += sin(_time * 0.05) * h * 0.02
			draw_texture_rect(aur, ar, false, Color(1, 1, 1, 0.12 + 0.03 * sin(_time * 0.4)))
		# a soft accent wash + darkening veil so UI / board always read on top
		draw_rect(rect, Color(tint.r, tint.g, tint.b, 0.05))
		draw_rect(rect, Color(0.03, 0.04, 0.09, 0.30))
	else:
		var luma0: float = accent.r * 0.3 + accent.g * 0.59 + accent.b * 0.11
		var acc0 := accent.lerp(Color(luma0, luma0, luma0), 0.45)
		var crown := VisualTheme.BG_TOP.lerp(Color(acc0.r, acc0.g, acc0.b, 1.0), 0.08)
		var mids := VisualTheme.BG_TOP.lerp(VisualTheme.BG_BOTTOM, 0.55)
		_v_gradient_3(rect, crown, mids, VisualTheme.BG_BOTTOM)

	# density multiplier for the ambient field — quiet over a painted scene.
	var amb := 0.4 if has_scene else 1.0

	# 2. hero glow behind the play area — a big soft radial that gently
	#    breathes; gives the whole screen a light source and depth.
	var breath := 0.5 + 0.5 * sin(_time * 0.5)
	var hero := Vector2(w * 0.5, h * 0.40)
	_soft_disc(hero, w * (0.70 + 0.05 * breath),
		Color(tint.r, tint.g, tint.b, (0.06 + 0.025 * breath) * amb), 8)
	_soft_disc(hero, w * 0.32, Color(tint.r, tint.g, tint.b, 0.04 * amb), 5)

	# 3. star field (very faint, twinkling)
	for s in _stars:
		var tw: float = 0.35 + 0.65 * (0.5 + 0.5 * sin(_time * s["speed"] + s["phase"]))
		draw_circle(Vector2(s["x"] * w, s["y"] * h), s["r"], Color(0.72, 0.82, 1.0, 0.10 * tw * amb))

	# 4. three slow colour blooms drifting on lissajous paths — very low
	#    alpha so UI contrast is never hurt.
	var b1 := Vector2(w * (0.26 + 0.10 * sin(_time * 0.045)), h * (0.20 + 0.05 * cos(_time * 0.037)))
	var b2 := Vector2(w * (0.78 + 0.09 * cos(_time * 0.031)), h * (0.46 + 0.05 * sin(_time * 0.041)))
	var b3 := Vector2(w * (0.44 + 0.12 * sin(_time * 0.027 + 1.5)), h * (0.82 + 0.04 * cos(_time * 0.036)))
	_bloom(b1, w * 0.56, Color(tint.r, tint.g, tint.b, 0.05 * amb))
	_bloom(b2, w * 0.62, Color(tint.b * 0.9, tint.r * 0.85, tint.g, 0.04 * amb))
	_bloom(b3, w * 0.66, Color(tint.g * 0.85, tint.b * 0.95, tint.r * 0.9, 0.035 * amb))

	# 6. faint drifting hex gem silhouettes (identity motif)
	for g in _gems:
		var gy: float = fposmod(g["y"] - _time * g["speed"], 1.15) - 0.075
		var gx: float = g["x"] * w + sin(_time * 0.12 + g["phase"]) * 30.0
		var col: Color = _GEM_HUES[g["hue"]]
		var pts := PackedVector2Array()
		for k in 6:
			var ang: float = PI / 6.0 + TAU * float(k) / 6.0 + _time * float(g["spin"]) + float(g["phase"])
			pts.append(Vector2(gx, gy * h) + Vector2(cos(ang), sin(ang)) * g["r"])
		draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.028 * amb))
		pts.append(pts[0])
		draw_polyline(pts, Color(col.r, col.g, col.b, 0.05 * amb), 2.0, true)

	# 7. parallax motes
	for m in _motes:
		var y: float = fposmod(m["y"] - _time * m["speed"], 1.0)
		var px: float = m["x"] * w + sin(_time * 0.3 + m["phase"]) * 24.0 * m["depth"]
		var tw: float = 0.5 + 0.5 * sin(_time * 1.2 + m["phase"])
		var c := Color(tint.r, tint.g, tint.b, m["bright"] * 0.8 * tw * m["depth"] * amb)
		draw_circle(Vector2(px, y * h), m["r"] * (0.6 + 0.4 * tw) * m["depth"], c)
		draw_circle(Vector2(px, y * h), m["r"] * 3.0 * m["depth"], Color(tint.r, tint.g, tint.b, m["bright"] * 0.06 * tw * amb))

	# 8. focusing corner vignette
	var cx := _size * 0.5
	for i in 6:
		var t := float(i) / 5.0
		draw_arc(cx, _size.length() * 0.5 * (0.52 + t * 0.58), 0, TAU, 48,
			Color(0, 0, 0, 0.12), _size.length() * 0.16, false)

## Three-stop vertical gradient, band-approximated (no Gradient/texture alloc).
func _v_gradient_3(rect: Rect2, top: Color, mid: Color, bottom: Color) -> void:
	var bands := 28
	var bh := rect.size.y / float(bands)
	for i in bands:
		var t := float(i) / float(bands - 1)
		var col := top.lerp(mid, t / 0.5) if t < 0.5 else mid.lerp(bottom, (t - 0.5) / 0.5)
		draw_rect(Rect2(rect.position + Vector2(0, bh * i), Vector2(rect.size.x, bh + 1.0)), col)

## Soft filled disc: concentric fading circles (cheap blur substitute).
func _soft_disc(center: Vector2, radius: float, col: Color, layers: int) -> void:
	for i in range(layers, 0, -1):
		var t := float(i) / float(layers)
		draw_circle(center, radius * t, Color(col.r, col.g, col.b, col.a * pow(1.0 - t, 1.7)))

func _bloom(center: Vector2, radius: float, col: Color) -> void:
	var layers := 12
	for i in range(layers, 0, -1):
		var t := float(i) / float(layers)
		draw_circle(center, radius * t, Color(col.r, col.g, col.b, col.a * pow(1.0 - t, 1.9) * 0.55))
