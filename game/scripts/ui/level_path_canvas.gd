class_name LevelPathCanvas
extends Control
## The winding trail connecting consecutive campaign nodes, drawn behind the
## LevelNodeButtons: a glowing rounded "ribbon" road with travelling light
## pips. Segments whose destination is unlocked read bright and glowing;
## still-locked stretches are dim and flat.

var segments: Array = [] # [{"from": Vector2, "to": Vector2, "lit": bool}]
var _t := 0.0

func set_segments(p_segments: Array) -> void:
	segments = p_segments
	_update_anim()
	queue_redraw()

func _update_anim() -> void:
	var any_lit := false
	for s in segments:
		if s.get("lit", false):
			any_lit = true
			break
	set_process(any_lit)

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	for seg in segments:
		var a: Vector2 = seg["from"]
		var b: Vector2 = seg["to"]
		var lit: bool = seg["lit"]
		if lit:
			# outer glow, dark casing, bright core
			draw_line(a, b, Color(0.45, 0.72, 1.0, 0.16), 34.0, true)
			draw_line(a, b, Color(0, 0, 0, 0.30), 24.0, true)
			draw_line(a, b, Color(0.30, 0.56, 0.86, 0.95), 16.0, true)
			draw_line(a, b, Color(0.6, 0.82, 1.0, 0.5), 6.0, true)
		else:
			draw_line(a, b, Color(0, 0, 0, 0.22), 20.0, true)
			draw_line(a, b, Color(0.20, 0.22, 0.30, 0.7), 13.0, true)

		var dir := (b - a)
		var length := dir.length()
		if length < 1.0:
			continue
		dir /= length
		if lit:
			# a couple of light pips travelling toward the next node
			var step := 46.0
			var flow := fposmod(_t * 60.0, step)
			var d := flow
			while d < length:
				var p := a + dir * d
				draw_circle(p, 5.0, Color(1, 1, 1, 0.9))
				draw_circle(p, 9.0, Color(0.7, 0.88, 1.0, 0.3))
				d += step
		else:
			var step := 30.0
			var d := step * 0.5
			while d < length:
				draw_circle(a + dir * d, 3.0, Color(1, 1, 1, 0.16))
				d += step
