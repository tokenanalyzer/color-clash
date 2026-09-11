class_name ComboPopup
extends RefCounted
## Floating praise / combo / score text. Punchy scale-bounce in, a short
## hold, then rise-and-fade. Lives on a throwaway Node2D above the board so
## it never blocks touch input on the pieces underneath.

static func spawn(parent: Node, world_pos: Vector2, text: String, color: Color, font_size: int = 44, subtitle: String = "") -> void:
	var root := Node2D.new()
	root.position = world_pos
	root.z_index = 120
	root.scale = Vector2(0.2, 0.2)
	parent.add_child(root)

	var label := _make_label(text, font_size, color)
	label.position = Vector2(-label.size.x * 0.5, -label.size.y * 0.5)
	root.add_child(label)

	if subtitle != "":
		var sub := _make_label(subtitle, int(font_size * 0.5), Color(1, 1, 1, 0.9))
		sub.position = Vector2(-sub.size.x * 0.5, font_size * 0.5)
		root.add_child(sub)

	var tw := root.create_tween()
	tw.tween_property(root, "scale", Vector2(1.15, 1.15), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(root, "scale", Vector2(1.0, 1.0), 0.08)
	tw.tween_interval(0.32)
	tw.parallel().tween_property(root, "position:y", world_pos.y - 84.0, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(0.24)
	tw.tween_property(root, "modulate:a", 0.0, 0.32)
	tw.tween_callback(root.queue_free)

static func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_constant_override("outline_size", maxi(font_size / 6, 4))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.reset_size()
	return label
