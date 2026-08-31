class_name ScreenShake
extends RefCounted
## Decaying random-offset shake for big chain reactions. Re-entrant safe: a
## new shake while one is running kills the old tween and always restores to
## the node's true rest position (stashed in meta on first use), so
## overlapping power blasts can't make the board drift.

const _REST_META := "_shake_rest_pos"
const _TWEEN_META := "_shake_tween"

static func apply(node: Node2D, strength: float, duration: float) -> void:
	if node == null or strength <= 0.0:
		return

	var rest: Vector2 = node.position
	if node.has_meta(_TWEEN_META):
		var old = node.get_meta(_TWEEN_META)
		if old is Tween and old.is_valid():
			old.kill()
		if node.has_meta(_REST_META):
			rest = node.get_meta(_REST_META)
			node.position = rest
	node.set_meta(_REST_META, rest)

	var tween := node.create_tween()
	node.set_meta(_TWEEN_META, tween)
	var steps := 7
	for i in steps:
		var falloff := 1.0 - float(i + 1) / float(steps)
		var offset := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * strength * falloff
		tween.tween_property(node, "position", rest + offset, duration / float(steps))
	tween.tween_property(node, "position", rest, duration / float(steps))
	tween.tween_callback(func():
		if node.has_meta(_REST_META):
			node.position = node.get_meta(_REST_META)
	)
