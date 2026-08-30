class_name ShapeDrawUtils
extends RefCounted
## Small procedural-drawing helpers shared by piece/board rendering. Color
## Clash has no external art assets yet, so pieces are drawn as layered
## vector shapes (rounded gem + gloss + shadow) — cheap to render at 60 FPS
## on modest Android hardware and easy to reskin later without code changes.

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
