class_name JamieActionController
extends RefCounted
## Jamie's combat action state machine + queue — the deterministic, testable
## core of the Phase C combat-animation system. PURE LOGIC: it holds no art,
## does no rendering, and NEVER touches damage or combat state. CombatDirector
## stays authoritative; this only decides *which pose phase Jamie is in and
## when*, and JamieRig turns that into visuals.
##
##   request(action_id) ──▶ IDLE?  yes ─▶ begin now
##                                  no  ─▶ enqueue (bounded)
##   tick(dt) advances WINDUP ─▶ STRIKE ─▶ RECOVER ─▶ (next queued | IDLE)
##
## `strike` is the authoritative "hit lands now" beat the rig uses to spawn
## the projectile / impact / enemy reaction — decoupled from any tween so a
## dropped frame can never skip a hit. A `sequence` action (Fever ultimate)
## emits `strike` once per sub-step, spread across its strike phase.
##
## Rapid combos: extra requests queue (max QUEUE_MAX); on overflow the
## OLDEST queued animation is dropped (`dropped` counts it) — never the
## in-flight one, and never a damage event (there are none here).

signal phase_changed(event: StringName, action_id: StringName, meta: Dictionary)

enum { IDLE, WINDUP, STRIKE, RECOVER }
const QUEUE_MAX := 3

var state: int = IDLE
var current_action: StringName = &"idle"
var current_meta: Dictionary = {}
var time_in_phase: float = 0.0
var dropped: int = 0

var _actions: Dictionary = {}
var _queue: Array = []                 # [{id, meta}]
var _seq_fired: int = 0                # sub-steps already struck this action
var _seq_list: Array = []

static func from_dict(d: Dictionary) -> JamieActionController:
	var c := JamieActionController.new()
	c._actions = d.get("actions", {})
	return c

func has_action(id: StringName) -> bool:
	return _actions.has(String(id))

func action_def(id: StringName) -> Dictionary:
	return _actions.get(String(id), {})

func is_busy() -> bool:
	return state != IDLE

func queue() -> Array:
	return _queue.duplicate(true)

func queue_size() -> int:
	return _queue.size()

## Total presentation time of one action (sum of its phases).
func action_duration(id: StringName) -> float:
	var a := action_def(id)
	return float(a.get("windup", 0.0)) + float(a.get("strike", 0.0)) + float(a.get("recover", 0.0))

## Ask Jamie to perform `action_id`. Begins immediately when idle, otherwise
## queues. Unknown ids are ignored (returns false).
func request(action_id: StringName, meta: Dictionary = {}) -> bool:
	if not has_action(action_id):
		return false
	if state == IDLE:
		var out: Array = []
		_begin(action_id, meta, out)
		return true
	_queue.append({"id": action_id, "meta": meta})
	while _queue.size() > QUEUE_MAX:
		_queue.pop_front()
		dropped += 1
	return true

## Advance the state machine. Call once per frame with delta seconds.
## Returns the ordered list of events emitted this tick (also emitted via
## `phase_changed`): windup_start / strike / recover / action_done.
func tick(dt: float) -> Array:
	var out: Array = []
	if state == IDLE:
		return out
	time_in_phase += dt
	# a while-loop so a large dt (lag spike) can cross several phases in one
	# tick without ever skipping a `strike`.
	var guard := 0
	while state != IDLE and guard < 64:
		guard += 1
		var a := action_def(current_action)
		match state:
			WINDUP:
				if time_in_phase >= float(a.get("windup", 0.0)):
					time_in_phase -= float(a.get("windup", 0.0))
					state = STRIKE
					_seq_fired = 0
					_emit(out, &"strike", {"step": 0, "sub_action": _seq_step(0)})
					_seq_fired = 1
				else:
					break
			STRIKE:
				var strike_len := float(a.get("strike", 0.0))
				# sequence actions strike once per sub-step, evenly spread
				if not _seq_list.is_empty():
					var n := _seq_list.size()
					var next_at := strike_len * float(_seq_fired) / float(n)
					if _seq_fired < n and time_in_phase >= next_at:
						_emit(out, &"strike", {"step": _seq_fired, "sub_action": _seq_step(_seq_fired)})
						_seq_fired += 1
						continue
				if time_in_phase >= strike_len:
					time_in_phase -= strike_len
					state = RECOVER
					_emit(out, &"recover", {})
				else:
					break
			RECOVER:
				if time_in_phase >= float(a.get("recover", 0.0)):
					time_in_phase -= float(a.get("recover", 0.0))
					_emit(out, &"action_done", {})
					if _queue.is_empty():
						state = IDLE
						current_action = &"idle"
						current_meta = {}
						_seq_list = []
					else:
						var nxt: Dictionary = _queue.pop_front()
						_begin(nxt["id"], nxt["meta"], out)
				else:
					break
	return out

func reset() -> void:
	state = IDLE
	current_action = &"idle"
	current_meta = {}
	time_in_phase = 0.0
	_queue.clear()
	_seq_list = []
	_seq_fired = 0

# --------------------------------------------------------------- internal --

func _begin(action_id: StringName, meta: Dictionary, out: Array) -> void:
	current_action = action_id
	current_meta = meta
	time_in_phase = 0.0
	state = WINDUP
	_seq_fired = 0
	var a := action_def(action_id)
	_seq_list = []
	for s in a.get("sequence", []):
		_seq_list.append(StringName(String(s)))
	_emit(out, &"windup_start", {})

func _seq_step(i: int) -> StringName:
	if _seq_list.is_empty():
		return current_action
	return _seq_list[clampi(i, 0, _seq_list.size() - 1)]

func _emit(out: Array, event: StringName, extra: Dictionary) -> void:
	var m := current_meta.duplicate()
	for k in extra:
		m[k] = extra[k]
	out.append({"event": event, "action": current_action, "meta": m})
	phase_changed.emit(event, current_action, m)
