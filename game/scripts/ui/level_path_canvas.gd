class_name LevelPathCanvas
extends Control
## Draws the winding line connecting consecutive campaign nodes, behind the
## LevelNodeButtons. A completed segment (both endpoints unlocked) reads
## brighter than an upcoming, still-locked one.

var segments: Array = [] # [{"from": Vector2, "to": Vector2, "lit": bool}]

func set_segments(p_segments: Array) -> void:
	segments = p_segments
	queue_redraw()

func _draw() -> void:
	for seg in segments:
		var lit: bool = seg["lit"]
		var color := Color(0.55, 0.78, 1.0, 0.85) if lit else Color(0.32, 0.33, 0.4, 0.55)
		draw_line(seg["from"], seg["to"], color, 8.0, true)
