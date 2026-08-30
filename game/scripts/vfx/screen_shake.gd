class_name ScreenShake
extends RefCounted
## Subtle screen shake for big chain reactions. Applies a decaying random
## offset to any Node2D (board root or camera) via a short tween so it
## never needs its own _process hook.

static func apply(node: Node2D, strength: float, duration: float) -> void:
	if node == null or strength <= 0.0:
		return
	var base_pos := node.position
	var tween := node.create_tween()
	var steps := 6
	for i in steps:
		var t := float(i + 1) / float(steps)
		var falloff := 1.0 - t
		var offset := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * strength * falloff
		tween.tween_property(node, "position", base_pos + offset, duration / float(steps))
	tween.tween_property(node, "position", base_pos, duration / float(steps))
