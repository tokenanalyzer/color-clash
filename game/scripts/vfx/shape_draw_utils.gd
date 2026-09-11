class_name ShapeDrawUtils
extends RefCounted
## Small procedural-drawing helpers shared by piece/board/map rendering.
## Color Clash uses no external art assets — every gem, power icon, board
## socket and map node is layered vector shapes (body + facets + gloss +
## rim + shadow). Cheap to render at 60 FPS on modest Android hardware and
## trivially reskinnable from data.

## Rounded-rect outline centered at local origin, given full size.
static func rounded_rect_points(size: Vector2, radius: float, segments: int = 6) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var w := size.x
	var h := size.y
	var r: float = min(radius, min(w, h) * 0.5)
	var half := size * 0.5
	var corners := [
		{"c": Vector2(half.x - r, -half.y + r), "a0": -PI / 2.0, "a1": 0.0},
		{"c": Vector2(half.x - r, half.y - r), "a0": 0.0, "a1": PI / 2.0},
		{"c": Vector2(-half.x + r, half.y - r), "a0": PI / 2.0, "a1": PI},
		{"c": Vector2(-half.x + r, -half.y + r), "a0": PI, "a1": 3.0 * PI / 2.0},
	]
	for corner in corners:
		var center: Vector2 = corner["c"]
		var a0: float = corner["a0"]
		var a1: float = corner["a1"]
		for i in range(segments + 1):
			var t: float = a0 + (a1 - a0) * float(i) / float(segments)
			pts.append(center + Vector2(cos(t), sin(t)) * r)
	return pts

## Regular n-gon centered at origin, `radius` to each vertex, `rotation` in
## radians (0 = first vertex pointing right).
static func regular_polygon(sides: int, radius: float, rotation: float = 0.0, center: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in sides:
		var a := rotation + TAU * float(i) / float(sides)
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	return pts

## The Color Clash gem silhouette: a flat-top hexagon with lightly rounded
## corners, sized to fit `cell_size`. `squash` < 1 flattens it a touch for a
## more jewel-like read.
static func gem_points(cell_size: float, squash: float = 0.92) -> PackedVector2Array:
	var r := cell_size * 0.46
	var raw := regular_polygon(6, r, PI / 6.0) # flat-top
	return round_polygon(raw, cell_size * 0.10, 3, Vector2(1.0, squash))

## Rounds the corners of an arbitrary convex polygon by chamfering each
## vertex into a short arc. `scale` lets the caller squash the result.
static func round_polygon(poly: PackedVector2Array, radius: float, segs: int = 3, scale: Vector2 = Vector2.ONE) -> PackedVector2Array:
	var n := poly.size()
	if n < 3:
		return poly
	var out := PackedVector2Array()
	for i in n:
		var prev: Vector2 = poly[(i - 1 + n) % n]
		var cur: Vector2 = poly[i]
		var nxt: Vector2 = poly[(i + 1) % n]
		var to_prev := (prev - cur).normalized()
		var to_next := (nxt - cur).normalized()
		var r: float = min(radius, (prev - cur).length() * 0.5, (nxt - cur).length() * 0.5)
		var a := cur + to_prev * r
		var b := cur + to_next * r
		for s in range(segs + 1):
			var t := float(s) / float(segs)
			# quadratic bezier a -> cur -> b
			var p := a.lerp(cur, t).lerp(cur.lerp(b, t), t)
			out.append(p * scale)
	return out

## Per-vertex colour array for `draw_colored_polygon`, lerping `top`→`bottom`
## down the polygon's local Y extent for a lit-from-above body gradient.
static func vertical_shade(poly: PackedVector2Array, top: Color, bottom: Color) -> PackedColorArray:
	var min_y := INF
	var max_y := -INF
	for p in poly:
		min_y = min(min_y, p.y)
		max_y = max(max_y, p.y)
	var span: float = max(max_y - min_y, 0.001)
	var cols := PackedColorArray()
	for p in poly:
		cols.append(top.lerp(bottom, (p.y - min_y) / span))
	return cols

## A 5-pointed star polygon.
static func star_points(center: Vector2, outer: float, inner_ratio: float = 0.45, points: int = 5, rotation: float = -PI / 2.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in points * 2:
		var a := rotation + PI * float(i) / float(points)
		var rad: float = outer if i % 2 == 0 else outer * inner_ratio
		pts.append(center + Vector2(cos(a), sin(a)) * rad)
	return pts
