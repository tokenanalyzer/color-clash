class_name GemTextures
extends RefCounted
## Jewel textures for the board. When the prepared gem art (assets 1-6) is
## present it is served directly; otherwise the premium look is BAKED ONCE into
## a cached ImageTexture (a rounded flat-top hexagon with a lit body gradient,
## faint facets, specular, rim light and a crisp AA edge). Either way the board
## just blits one textured quad per cell — the Android "draw heavy once, blit
## cheap forever" technique — and it scales crisply with linear+mipmap
## filtering across every phone resolution.
##
## The multicolour Rainbow jewel stays procedural (`_bake_rainbow`) — there is
## no dedicated art asset for it and the baked one already matches the set.
## Shared soft-shadow / additive-glow sprites are procedural falloffs tinted per
## draw and are also kept.

const RES := 176          # baked gem resolution (downscaled on screen)
const PAD := 16           # room for the AA edge / rim
const _SIZE := RES + PAD * 2

static var _gems: Dictionary = {}      # StringName -> ImageTexture (body)
static var _shadow: ImageTexture
static var _glow: ImageTexture
static var _rainbow: ImageTexture

## Prepares the jewel textures up front (call from BoardView.setup so any
## one-time bake cost is hidden by the level-in fade). Colours that have a
## prepared art asset skip the bake entirely. Idempotent.
static func prime(palette: PieceColorPalette) -> void:
	_ensure_shared()
	for id in palette.ordered_ids:
		if _gems.has(id):
			continue
		if AssetLibrary.gem(id) != null:
			_gems[id] = AssetLibrary.gem(id)
		else:
			_gems[id] = _bake_gem(palette.get_def(id))
	if _rainbow == null:
		_rainbow = _bake_rainbow()

## A baked jewel in an arbitrary solid colour (power tiles / obstacles),
## cached under `key`. `base` is the mid tone; the rest are derived.
static func solid_gem(key: StringName, base: Color) -> Texture2D:
	if not _gems.has(key):
		var d := ColorDef.new()
		d.base_color = base
		d.deep_color = base.darkened(0.5)
		d.accent_color = base.lightened(0.42)
		d.rim_color = base.lightened(0.7)
		d.glow_color = base.lightened(0.25)
		_gems[key] = _bake_gem(d)
	return _gems[key]

static func gem(color_id: StringName, palette: PieceColorPalette) -> Texture2D:
	if color_id == BoardModel.RAINBOW_COLOR_ID:
		if _rainbow == null:
			_rainbow = _bake_rainbow()
		return _rainbow
	if not _gems.has(color_id):
		var art := AssetLibrary.gem(color_id)
		if art != null:
			_gems[color_id] = art
		elif palette != null and palette.has(color_id):
			_gems[color_id] = _bake_gem(palette.get_def(color_id))
		else:
			return null
	return _gems[color_id]

static func shadow() -> ImageTexture:
	_ensure_shared()
	return _shadow

static func glow() -> ImageTexture:
	_ensure_shared()
	return _glow

static func _ensure_shared() -> void:
	if _shadow == null:
		_shadow = _bake_shadow()
	if _glow == null:
		_glow = _bake_glow()

# ------------------------------------------------------------- geometry --

## Signed distance to a rounded flat-top hexagon centred at the origin.
## Negative inside. `r` is the (pre-rounding) circumradius, `round_r` the
## corner rounding — both in pixels. (iq's hexagon SDF, axes swapped for a
## flat top, with the standard `- round_r` rounding applied last.)
static func _hex_sdf(p: Vector2, r: float, round_r: float) -> float:
	var q := Vector2(absf(p.y), absf(p.x))
	var k := Vector2(-0.8660254, 0.5)
	var d: float = minf(k.x * q.x + k.y * q.y, 0.0)
	q -= Vector2(2.0 * d * k.x, 2.0 * d * k.y)
	q -= Vector2(clampf(q.x, -0.5773503 * r, 0.5773503 * r), r)
	return q.length() * signf(q.y) - round_r

# ---------------------------------------------------------------- bakes --

static func _bake_gem(def: ColorDef) -> ImageTexture:
	var img := Image.create(_SIZE, _SIZE, false, Image.FORMAT_RGBA8)
	var buf := PackedByteArray()
	buf.resize(_SIZE * _SIZE * 4)

	# Brighter lit cap, deeper shaded base — a wider tonal range reads as a
	# thicker, glossier jewel rather than a flat chip.
	var top := def.accent_color.lightened(0.14)
	var mid := def.base_color
	var deep := def.base_color.lerp(def.deep_color, 0.95).darkened(0.1)
	var rim := def.rim_color
	var glow_c := def.glow_color

	var cx := float(_SIZE) * 0.5
	var cy := float(_SIZE) * 0.5
	var r := float(RES) * 0.5 - 1.0
	var round_r := float(RES) * 0.16
	var spec_c := Vector2(cx - RES * 0.16, cy - RES * 0.25)
	var spec_r := RES * 0.36

	var i := 0
	for y in _SIZE:
		for x in _SIZE:
			var p := Vector2(float(x) - cx, float(y) - cy)
			var sd := _hex_sdf(p, r, round_r)
			var a: float = clampf(0.5 - sd, 0.0, 1.0)   # ~1px AA edge
			var col := Color(0, 0, 0, 0)
			if a > 0.001:
				# vertical lit gradient
				var vy: float = clampf((p.y / r) * 0.5 + 0.5, 0.0, 1.0)
				var body: Color
				if vy < 0.45:
					body = top.lerp(mid, vy / 0.45)
				else:
					body = mid.lerp(deep, (vy - 0.45) / 0.55)
				# faint faceting: two soft diagonal planes
				var f1: float = clampf((p.x - p.y) / r, -1.0, 1.0)
				var f2: float = clampf((p.x + p.y) / r, -1.0, 1.0)
				body = body.lightened(clampf(f1 * 0.06, 0.0, 0.09))
				body = body.darkened(clampf(-f2 * 0.05, 0.0, 0.08))
				# inner colour bloom toward the centre
				var cd: float = 1.0 - clampf(p.length() / (r * 0.9), 0.0, 1.0)
				body = body.lerp(glow_c, cd * 0.12)
				# broad soft specular + a tight hot glint = glossy bead
				var s: float = clampf(1.0 - (Vector2(float(x), float(y)) - spec_c).length() / spec_r, 0.0, 1.0)
				s = s * s * 0.9
				body = body.lerp(Color(1, 1, 1), s)
				var hot: float = clampf(1.0 - (Vector2(float(x), float(y)) - spec_c).length() / (spec_r * 0.26), 0.0, 1.0)
				body = body.lerp(Color(1, 1, 1), hot * hot * 0.95)
				# small counter-highlight on the lower-right (bounce light)
				var bl := Vector2(cx + RES * 0.19, cy + RES * 0.2)
				var b2: float = clampf(1.0 - (Vector2(float(x), float(y)) - bl).length() / (RES * 0.24), 0.0, 1.0)
				body = body.lerp(rim, b2 * b2 * 0.22)
				# top rim light (bright band just inside the upper edge)
				var edge: float = clampf(1.0 + sd / 6.0, 0.0, 1.0)  # 1 at edge -> 0 at 6px in
				if p.y < 0.0:
					body = body.lerp(rim, edge * clampf(-p.y / r, 0.0, 1.0) * 1.0)
				# bottom inner shade — deeper, for a domed bead look
				if p.y > r * 0.15:
					body = body.darkened(edge * 0.34)
				# ambient-occlusion ring hugging the lower boundary all round
				var ao: float = clampf(1.0 + sd / 10.0, 0.0, 1.0)
				body = body.darkened((1.0 - ao) * 0.18)
				# crisp dark contour just inside the boundary — a defined edge
				# so touching jewels never bleed into one another
				var outline: float = clampf(1.0 - absf(sd + 1.5) / 3.0, 0.0, 1.0)
				body = body.darkened(outline * 0.55)
				col = Color(body.r, body.g, body.b, a)
			buf[i] = int(round(clampf(col.r, 0.0, 1.0) * 255.0))
			buf[i + 1] = int(round(clampf(col.g, 0.0, 1.0) * 255.0))
			buf[i + 2] = int(round(clampf(col.b, 0.0, 1.0) * 255.0))
			buf[i + 3] = int(round(clampf(col.a, 0.0, 1.0) * 255.0))
			i += 4

	img.set_data(_SIZE, _SIZE, false, Image.FORMAT_RGBA8, buf)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

static func _bake_rainbow() -> ImageTexture:
	var spectrum := [
		Color(0.96, 0.26, 0.38), Color(1.0, 0.6, 0.2), Color(1.0, 0.87, 0.28),
		Color(0.3, 0.82, 0.5), Color(0.28, 0.6, 0.98), Color(0.66, 0.36, 0.95),
	]
	var img := Image.create(_SIZE, _SIZE, false, Image.FORMAT_RGBA8)
	var buf := PackedByteArray()
	buf.resize(_SIZE * _SIZE * 4)
	var cx := float(_SIZE) * 0.5
	var cy := float(_SIZE) * 0.5
	var r := float(RES) * 0.5 - 1.0
	var round_r := float(RES) * 0.115
	var i := 0
	for y in _SIZE:
		for x in _SIZE:
			var p := Vector2(float(x) - cx, float(y) - cy)
			var sd := _hex_sdf(p, r, round_r)
			var a: float = clampf(0.5 - sd, 0.0, 1.0)
			var col := Color(0, 0, 0, 0)
			if a > 0.001:
				var ang: float = fposmod(atan2(p.y, p.x) + PI, TAU) / TAU
				var seg: float = ang * 6.0
				var s0 := int(seg) % 6
				var s1 := (s0 + 1) % 6
				var body: Color = (spectrum[s0] as Color).lerp(spectrum[s1], seg - floor(seg))
				body = body.lerp(Color(1, 1, 1), 0.22)
				var s: float = clampf(1.0 - (p - Vector2(-RES * 0.16, -RES * 0.22)).length() / (RES * 0.3), 0.0, 1.0)
				body = body.lerp(Color(1, 1, 1), s * s * 0.85)
				var outline: float = clampf(1.0 - absf(sd) / 1.6, 0.0, 1.0)
				body = body.darkened(outline * 0.3)
				col = Color(body.r, body.g, body.b, a)
			buf[i] = int(clampf(col.r, 0, 1) * 255.0)
			buf[i + 1] = int(clampf(col.g, 0, 1) * 255.0)
			buf[i + 2] = int(clampf(col.b, 0, 1) * 255.0)
			buf[i + 3] = int(clampf(col.a, 0, 1) * 255.0)
			i += 4
	img.set_data(_SIZE, _SIZE, false, Image.FORMAT_RGBA8, buf)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

static func _bake_shadow() -> ImageTexture:
	var n := 96
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var buf := PackedByteArray()
	buf.resize(n * n * 4)
	var c := float(n) * 0.5
	var i := 0
	for y in n:
		for x in n:
			var d: float = Vector2(float(x) - c, float(y) - c).length() / c
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			a = pow(a, 1.7) * 0.55
			buf[i] = 0
			buf[i + 1] = 0
			buf[i + 2] = 0
			buf[i + 3] = int(a * 255.0)
			i += 4
	img.set_data(n, n, false, Image.FORMAT_RGBA8, buf)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

static func _bake_glow() -> ImageTexture:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var buf := PackedByteArray()
	buf.resize(n * n * 4)
	var c := float(n) * 0.5
	var i := 0
	for y in n:
		for x in n:
			var d: float = Vector2(float(x) - c, float(y) - c).length() / c
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			a = pow(a, 2.2)
			buf[i] = 255
			buf[i + 1] = 255
			buf[i + 2] = 255
			buf[i + 3] = int(a * 255.0)
			i += 4
	img.set_data(n, n, false, Image.FORMAT_RGBA8, buf)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
