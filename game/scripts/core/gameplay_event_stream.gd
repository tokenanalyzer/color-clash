class_name GameplayEventStream
extends RefCounted
## An ordered, replayable list of EngineEvents for one unit of gameplay
## (typically one resolved move, or one level session). Pure data — build it
## from the game logic, then hand it to any number of consumers.
##
## `event_pushed` lets a live consumer react as events land; `events` /
## `of_type` / `types` let a test (or a debug overlay) inspect the whole
## sequence after the fact. No engine dependency, fully deterministic.

signal event_pushed(event: EngineEvent)

var events: Array[EngineEvent] = []

## Append a new event and return it (so callers can tweak the payload).
func push(type: StringName, data: Dictionary = {}) -> EngineEvent:
	var e := EngineEvent.new(type, data)
	events.append(e)
	event_pushed.emit(e)
	return e

## Append an already-built event.
func add(event: EngineEvent) -> void:
	events.append(event)
	event_pushed.emit(event)

## Append a batch (e.g. the output of MoveEventTranslator).
func extend(list: Array) -> void:
	for e in list:
		add(e)

func of_type(type: StringName) -> Array[EngineEvent]:
	var out: Array[EngineEvent] = []
	for e in events:
		if e.type == type:
			out.append(e)
	return out

func has_type(type: StringName) -> bool:
	for e in events:
		if e.type == type:
			return true
	return false

func count_of(type: StringName) -> int:
	var n := 0
	for e in events:
		if e.type == type:
			n += 1
	return n

## The ordered list of type names — handy for asserting a whole sequence.
func types() -> Array[StringName]:
	var out: Array[StringName] = []
	for e in events:
		out.append(e.type)
	return out

func size() -> int:
	return events.size()

func clear() -> void:
	events.clear()
