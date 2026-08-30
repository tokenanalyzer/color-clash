class_name ComboPopup
extends RefCounted
## Floating combo/score text — spawns a Label that rises and fades, then
## frees itself. Kept off the board's own visual hierarchy so it never
## blocks touch input on the pieces underneath.

static func spawn(parent: Node, world_pos: Vector2, text: String, color: Color, font_size: int = 40) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	label.position = world_pos
	label.z_index = 100
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)

	var tween := label.create_tween()
	tween.tween_property(label, "position:y", label.position.y - 70.0, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.7).set_delay(0.15)
	tween.tween_callback(label.queue_free)
