class_name Haptics
extends RefCounted
## Thin wrapper over Input.vibrate_handheld() with a global settings toggle,
## so gameplay code never has to check the setting itself.

static var enabled: bool = true

static func light() -> void:
	if enabled:
		Input.vibrate_handheld(20)

static func medium() -> void:
	if enabled:
		Input.vibrate_handheld(40)

static func strong(duration_ms: int = 70) -> void:
	if enabled:
		Input.vibrate_handheld(duration_ms)
