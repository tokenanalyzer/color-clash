extends Node
## Autoload "GameEvents". The single fan-out point for typed gameplay events.
##
##     app.gd / board logic  --publish-->  GameEvents.event  -->  consumers
##                                                                (view, audio,
##                                                                 VFX, character)
##
## app.gd builds the event list for each move (MoveEventTranslator) plus the
## session-level events (score/moves/fever/objective/level) and publishes
## them here in order. Anything that wants to react just connects to
## `event`. This is additive: the existing direct signal wiring
## (board_view.move_resolved -> app._on_move_resolved, etc.) is untouched;
## the bus runs alongside it and is what new systems build on.

signal event(e: EngineEvent)

## Small ring buffer of the most recent events, debug builds only, for an
## on-screen event log later. Never read by gameplay.
const _RECENT_MAX := 64
var _recent: Array[EngineEvent] = []
var _debug := false

func _ready() -> void:
	_debug = OS.is_debug_build()

func publish(e: EngineEvent) -> void:
	if e == null:
		return
	if _debug:
		_recent.append(e)
		if _recent.size() > _RECENT_MAX:
			_recent.pop_front()
	event.emit(e)

func publish_type(type: StringName, data: Dictionary = {}) -> EngineEvent:
	var e := EngineEvent.new(type, data)
	publish(e)
	return e

func publish_all(list: Array) -> void:
	for e in list:
		publish(e)

func recent() -> Array[EngineEvent]:
	return _recent.duplicate()
