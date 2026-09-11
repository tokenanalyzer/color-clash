class_name IconDraw
extends RefCounted
## Shared original vector icons for powers and boosters, drawn straight onto
## any CanvasItem. Code-only — no font glyphs (Android 16 dropped the legacy
## emoji font, so emoji render as blank) and no art assets. The board's
## power tiles, the booster bar and the reward popup all pull from here so
## a Bomb looks like a Bomb everywhere.
##
## Every icon is drawn centred on `c` and scaled to `s` (roughly the icon's
## full width/height in pixels). `t` is a 0..1 idle phase for the animated
## variants (spark flicker, snowflake spin, prism rotation).

static func draw_icon(ci: CanvasItem, id: StringName, c: Vector2, s: float, t: float = 0.0, tint: Color = Color(1, 1, 1)) -> void:
	match id:
		&"bomb": _bomb(ci, c, s, t)
		&"lightning": _lightning(ci, c, s, t)
		&"freeze": _freeze(ci, c, s, t)
		&"rainbow": _rainbow(ci, c, s, t)
		&"chain": _chain(ci, c, s, t)
		&"shuffle": _shuffle(ci, c, s, t)
		&"extra_moves": _extra_moves(ci, c, s, tint)
		&"fire_sword": _fire_sword(ci, c, s, t)
		_: ci.draw_circle(c, s * 0.3, tint)

## Inventory's POWERS tab icon (2026-09-05 UI pass) — a small flaming blade,
## same visual complexity/style as the other hand-drawn glyphs above.
static func _fire_sword(ci: CanvasItem, c: Vector2, s: float, t: float) -> void:
	var flick := 0.7 + 0.3 * sin(t * 14.0)
	var tip := c + Vector2(0, -s * 0.46)
	var hilt := c + Vector2(0, s * 0.28)
	# blade
	var blade := PackedVector2Array([
		tip, c + Vector2(s * 0.08, -s * 0.05), c + Vector2(s * 0.06, s * 0.14),
		c + Vector2(-s * 0.06, s * 0.14), c + Vector2(-s * 0.08, -s * 0.05),
	])
	ci.draw_colored_polygon(blade, Color(1.0, 0.85, 0.55))
	var edge := blade.duplicate(); edge.append(blade[0])
	ci.draw_polyline(edge, Color(1.0, 0.55, 0.15, 0.9), maxf(s * 0.03, 1.5), true)
	# crossguard + hilt
	ci.draw_line(c + Vector2(-s * 0.18, s * 0.14), c + Vector2(s * 0.18, s * 0.14), Color(0.6, 0.42, 0.2), maxf(s * 0.05, 2.0), true)
	ci.draw_line(c + Vector2(0, s * 0.14), hilt, Color(0.36, 0.24, 0.14), maxf(s * 0.06, 3.0), true)
	# flame licking off the blade
	for i in 5:
		var a := t * 9.0 + TAU * float(i) / 5.0
		var o := tip.lerp(c + Vector2(0, -s * 0.05), float(i) / 5.0) + Vector2(sin(a) * s * 0.1, 0)
		ci.draw_circle(o, s * (0.09 + 0.04 * flick) * (1.0 - float(i) / 6.0), Color(1.0, 0.5, 0.12, 0.55 * flick))
	ci.draw_circle(tip, s * 0.07 * flick, Color(1.0, 0.92, 0.6))

static func _bomb(ci: CanvasItem, c: Vector2, s: float, t: float) -> void:
	# a shaded iron sphere with a lit fuse — a real object, not a flat disc
	var r := s * 0.36
	ci.draw_circle(c + Vector2(r * 0.14, r * 0.2), r * 1.02, Color(0, 0, 0, 0.3))
	for i in range(7, 0, -1):
		var k := float(i) / 7.0
		ci.draw_circle(c + Vector2(-r * 0.32, -r * 0.34) * (1.0 - k), r * k,
			Color(0.24, 0.25, 0.32).lerp(Color(0.05, 0.05, 0.08), 1.0 - k))
	ci.draw_circle(c + Vector2(-r * 0.34, -r * 0.38), r * 0.24, Color(1, 1, 1, 0.5))
	ci.draw_circle(c + Vector2(-r * 0.3, -r * 0.34), r * 0.1, Color(1, 1, 1, 0.9))
	ci.draw_arc(c, r, 0, TAU, 26, Color(0, 0, 0, 0.5), maxf(s * 0.03, 2.0), true)
	# collar + curved fuse
	var neck := c + Vector2(r * 0.14, -r * 0.9)
	ci.draw_circle(neck, r * 0.24, Color(0.16, 0.13, 0.1))
	var mid := c + Vector2(r * 0.5, -r * 1.14)
	var tip := c + Vector2(r * 0.36, -r * 1.5)
	ci.draw_polyline(PackedVector2Array([neck, mid, tip]), Color(0.58, 0.44, 0.3), maxf(s * 0.06, 3.0), true)
	var fl := 0.7 + 0.3 * sin(t * 22.0)
	ci.draw_circle(tip, s * (0.13 + 0.05 * fl), Color(1.0, 0.55, 0.12, 0.9))
	ci.draw_circle(tip, s * 0.08 * fl, Color(1.0, 0.94, 0.65))
	for i in 4:
		var a := t * 12.0 + TAU * float(i) / 4.0
		ci.draw_line(tip, tip + Vector2(cos(a), sin(a)) * s * (0.12 + 0.05 * fl),
			Color(1.0, 0.8, 0.3, 0.8), maxf(s * 0.02, 1.5), true)

static func _lightning(ci: CanvasItem, c: Vector2, s: float, t: float) -> void:
	var glow := 0.7 + 0.3 * sin(t * 9.0)
	# outer electric bloom
	for i in range(4, 0, -1):
		var k := float(i) / 4.0
		ci.draw_circle(c, s * 0.42 * k, Color(0.5, 0.8, 1.0, 0.12 * (1.0 - k) * glow))
	var bolt := PackedVector2Array([
		c + Vector2(s * 0.12, -s * 0.44), c + Vector2(-s * 0.08, -s * 0.02),
		c + Vector2(s * 0.09, -s * 0.02), c + Vector2(-s * 0.14, s * 0.44),
		c + Vector2(s * 0.24, -s * 0.05), c + Vector2(s * 0.04, -s * 0.05),
	])
	ci.draw_colored_polygon(bolt, Color(1.0, 0.95, 0.6).lerp(Color(1, 1, 1), glow))
	var edge := bolt.duplicate(); edge.append(bolt[0])
	ci.draw_polyline(edge, Color(0.55, 0.82, 1.0, 0.95), maxf(s * 0.028, 1.5), true)
	for i in 2:
		var a := t * 6.0 + float(i) * 3.1
		var o := c + Vector2(cos(a), sin(a)) * s * 0.44
		ci.draw_line(o, o + Vector2(cos(a + 1.0), sin(a + 1.0)) * s * 0.14, Color(0.8, 0.95, 1.0, 0.6 * glow), maxf(s * 0.03, 1.5), true)

static func _freeze(ci: CanvasItem, c: Vector2, s: float, t: float) -> void:
	# faceted ice crystal + spinning snowflake
	var spin := t * 0.5
	var crystal := _hexagon(c, s * 0.4)
	var rot := PackedVector2Array()
	for p in crystal:
		var d := p - c
		rot.append(c + d.rotated(spin * 0.3))
	ci.draw_colored_polygon(rot, Color(0.72, 0.9, 1.0, 0.5))
	var re := rot.duplicate(); re.append(rot[0])
	ci.draw_polyline(re, Color(0.95, 1.0, 1.0, 0.95), maxf(s * 0.03, 2.0), true)
	var col := Color(1, 1, 1, 0.95)
	for i in 3:
		var a := spin + PI * float(i) / 3.0
		var tip := Vector2(cos(a), sin(a)) * s * 0.34
		ci.draw_line(c - tip, c + tip, col, maxf(s * 0.045, 2.0), true)
		for side in [-1.0, 1.0]:
			var mid := c + tip * 0.55
			var barb := Vector2(cos(a + side * 0.9), sin(a + side * 0.9)) * s * 0.14
			ci.draw_line(mid, mid + barb, col, maxf(s * 0.035, 1.5), true)
	ci.draw_circle(c, s * 0.08, Color(1, 1, 1))

static func _rainbow(ci: CanvasItem, c: Vector2, s: float, t: float) -> void:
	# pearlescent orb with rotating spectrum wedges
	var spin := t * 0.9
	var r := s * 0.4
	var spectrum := [
		Color(0.96, 0.26, 0.38), Color(1.0, 0.6, 0.2), Color(1.0, 0.87, 0.28),
		Color(0.3, 0.82, 0.5), Color(0.28, 0.6, 0.98), Color(0.66, 0.36, 0.95),
	]
	ci.draw_circle(c, r, Color(0.98, 0.98, 1.0))
	for i in spectrum.size():
		var a0 := spin + TAU * float(i) / 6.0
		var wedge := PackedVector2Array([c])
		for j in 5:
			var aa := a0 + (TAU / 6.0) * float(j) / 4.0
			wedge.append(c + Vector2(cos(aa), sin(aa)) * r)
		var sc: Color = spectrum[i]
		sc.a = 0.62
		ci.draw_colored_polygon(wedge, sc)
	ci.draw_circle(c + Vector2(-r * 0.3, -r * 0.32), r * 0.26, Color(1, 1, 1, 0.7))
	ci.draw_arc(c, r, 0, TAU, 28, Color(1, 1, 1, 0.85), maxf(s * 0.03, 2.0), true)
	ci.draw_circle(c, s * 0.09, Color(1, 1, 1))

static func _chain(ci: CanvasItem, c: Vector2, s: float, t: float) -> void:
	var pulse := 0.8 + 0.2 * sin(t * 5.0)
	var col := Color(0.85, 1.0, 0.9)
	var offs := [Vector2(-s * 0.18, -s * 0.04), Vector2(0, s * 0.16), Vector2(s * 0.18, -s * 0.04)]
	for oi in offs.size():
		var ring := _hexagon(c + offs[oi], s * 0.19)
		ring.append(ring[0])
		ci.draw_polyline(ring, col, maxf(s * 0.05, 2.0) * pulse, true)
		var tt := fmod(t * 1.5 + float(oi) * 0.33, 1.0)
		ci.draw_circle(c + offs[oi] + Vector2(cos(tt * TAU), sin(tt * TAU)) * s * 0.19, s * 0.045, Color(1, 1, 1))
	ci.draw_circle(c, s * 0.06, Color(0.7, 1.0, 0.8))

static func _shuffle(ci: CanvasItem, c: Vector2, s: float, t: float) -> void:
	var col := Color(0.85, 0.95, 1.0)
	var wob: float = sin(t * 3.0) * 0.15
	for di in 2:
		var dir: float = 1.0 if di == 0 else -1.0
		var r: float = s * 0.34
		var a0: float = (0.4 + wob) * dir
		var a1: float = (PI - 0.4 + wob) * dir
		var ctr := c + Vector2(0, dir * s * 0.16)
		ci.draw_arc(ctr, r, a0, a1, 16, col, maxf(s * 0.055, 2.0), true)
		var tip := ctr + Vector2(cos(a1), sin(a1)) * r
		var back := Vector2(cos(a1 - dir * 0.5), sin(a1 - dir * 0.5)) * s * 0.14
		ci.draw_line(tip, tip + back, col, maxf(s * 0.05, 2.0))
		ci.draw_line(tip, tip + Vector2(-back.y, back.x) * dir * 0.9, col, maxf(s * 0.05, 2.0))

static func _extra_moves(ci: CanvasItem, c: Vector2, s: float, tint: Color) -> void:
	var col := Color(0.9, 0.96, 1.0)
	var w := s * 0.42
	var th := maxf(s * 0.13, 3.0)
	ci.draw_line(c - Vector2(w, 0), c + Vector2(w, 0), col, th)
	ci.draw_line(c - Vector2(0, w), c + Vector2(0, w), col, th)

static func _hexagon(center: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var a := PI / 6.0 + TAU * float(i) / 6.0
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	return pts


## A tiny reusable Control that renders one IconDraw glyph (optionally
## animated). Used by the booster bar, reward popup and daily screen.
class IconRect extends Control:
	var id: StringName = &"bomb"
	var animated := false
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(animated)

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var s := minf(size.x, size.y)
		IconDraw.draw_icon(self, id, size * 0.5, s * 0.92, _t)
