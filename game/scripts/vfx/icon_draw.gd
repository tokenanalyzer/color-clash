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
		_: ci.draw_circle(c, s * 0.3, tint)

static func _bomb(ci: CanvasItem, c: Vector2, s: float, t: float) -> void:
	var r := s * 0.34
	ci.draw_circle(c + Vector2(0, r * 0.12), r, Color(0.10, 0.10, 0.13))
	ci.draw_circle(c + Vector2(0, r * 0.12), r, Color(1, 1, 1, 0.0))
	ci.draw_circle(c + Vector2(-r * 0.34, -r * 0.36), r * 0.30, Color(1, 1, 1, 0.35))
	# fuse
	var neck := c + Vector2(r * 0.28, -r * 0.78)
	var tip := c + Vector2(r * 0.62, -r * 1.28)
	ci.draw_line(c + Vector2(r * 0.2, -r * 0.55), neck, Color(0.55, 0.4, 0.28), maxf(s * 0.06, 2.0))
	ci.draw_line(neck, tip, Color(0.55, 0.4, 0.28), maxf(s * 0.055, 2.0))
	var spark := s * (0.11 + 0.05 * sin(t * 20.0))
	ci.draw_circle(tip, spark, Color(1, 0.62, 0.15))
	ci.draw_circle(tip, spark * 0.55, Color(1, 0.95, 0.7))

static func _lightning(ci: CanvasItem, c: Vector2, s: float, t: float) -> void:
	var glow := 0.7 + 0.3 * sin(t * 9.0)
	var col := Color(1.0, 0.93, 0.45).lerp(Color(1, 1, 1), glow)
	var top := PackedVector2Array([
		c + Vector2(s * 0.10, -s * 0.42), c + Vector2(s * 0.24, -s * 0.02),
		c + Vector2(-s * 0.02, -s * 0.02),
	])
	var bottom := PackedVector2Array([
		c + Vector2(-s * 0.10, s * 0.42), c + Vector2(-s * 0.24, s * 0.02),
		c + Vector2(s * 0.02, s * 0.02),
	])
	ci.draw_colored_polygon(top, col)
	ci.draw_colored_polygon(bottom, col)
	# a couple of stray arcs
	for i in 2:
		var a := t * 6.0 + float(i) * 3.1
		var o := c + Vector2(cos(a), sin(a)) * s * 0.42
		ci.draw_line(o, o + Vector2(cos(a + 1.0), sin(a + 1.0)) * s * 0.14, Color(1, 1, 0.8, 0.5 * glow), maxf(s * 0.03, 1.5))

static func _freeze(ci: CanvasItem, c: Vector2, s: float, t: float) -> void:
	var spin := t * 0.9
	var col := Color(0.9, 0.98, 1.0)
	for i in 3:
		var a := spin + PI * float(i) / 3.0
		var tip := Vector2(cos(a), sin(a)) * s * 0.44
		ci.draw_line(c - tip, c + tip, col, maxf(s * 0.06, 2.0))
		for side in [-1.0, 1.0]:
			var mid := c + tip * 0.5
			var barb := Vector2(cos(a + side * 0.9), sin(a + side * 0.9)) * s * 0.18
			ci.draw_line(mid, mid + barb, col, maxf(s * 0.045, 1.5))
			var mid2 := c + tip * 0.82
			ci.draw_line(mid2, mid2 + barb * 0.6, col, maxf(s * 0.04, 1.2))
	ci.draw_circle(c, s * 0.09, Color(1, 1, 1))

static func _rainbow(ci: CanvasItem, c: Vector2, s: float, t: float) -> void:
	var spin := t * 1.3
	var spectrum := [
		Color(0.96, 0.26, 0.38), Color(1.0, 0.6, 0.2), Color(1.0, 0.87, 0.28),
		Color(0.3, 0.82, 0.5), Color(0.28, 0.6, 0.98), Color(0.66, 0.36, 0.95),
	]
	for i in spectrum.size():
		var a0 := spin + TAU * float(i) / 6.0
		ci.draw_arc(c, s * 0.36, a0, a0 + 1.35, 12, spectrum[i], maxf(s * 0.11, 3.0), true)
	ci.draw_circle(c, s * 0.11, Color(1, 1, 1))

static func _chain(ci: CanvasItem, c: Vector2, s: float, t: float) -> void:
	var pulse := 0.8 + 0.2 * sin(t * 5.0)
	var col := Color(0.85, 1.0, 0.9)
	for off in [Vector2(-s * 0.16, -s * 0.05), Vector2(s * 0.16, s * 0.05)]:
		var ring := _hexagon(c + off, s * 0.22)
		ring.append(ring[0])
		ci.draw_polyline(ring, col, maxf(s * 0.06, 2.0) * pulse, true)
	ci.draw_circle(c, s * 0.07, Color(0.7, 1.0, 0.8))

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
