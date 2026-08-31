class_name LevelPathCanvas
extends Control
## The winding trail connecting consecutive campaign nodes, drawn behind the
## LevelNodeButtons: a rounded "road" with a dashed centre line. Segments
## whose destination is unlocked read bright and lightly glowing; still-
## locked stretches are dim.

var segments: Array = [] # [{"from": Vector2, "to": Vector2, "lit": bool}]

func set_segments(p_segments: Array) -> void:
	segments = p_segments
	queue_redraw()

func _draw() -> void:
	for seg in segments:
		var a: Vector2 = seg["from"]
		var b: Vector2 = seg["to"]
		var lit: bool = seg["lit"]
		var base := Color(0.24, 0.5, 0.72, 0.9) if lit else Color(0.22, 0.24, 0.30, 0.6)
		if lit:
			draw_line(a, b, Color(0.4, 0.75, 1.0, 0.20), 26.0, true)
		draw_line(a, b, Color(0, 0, 0, 0.25), 20.0, true)
		draw_line(a, b, base, 14.0, true)
		# dashed centre pips
		var dir := (b - a)
		var length := dir.length()
		if length < 1.0:
			continue
		dir /= length
		var step := 26.0
		var d := step * 0.5
		var pip := Color(1, 1, 1, 0.7) if lit else Color(1, 1, 1, 0.18)
		while d < length:
			draw_circle(a + dir * d, 3.0, pip)
			d += step
