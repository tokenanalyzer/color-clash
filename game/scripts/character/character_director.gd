extends Node
## Autoload "CharacterDirector". Turns the raw gameplay event stream
## (GameEvents.event) into debounced, prioritised mascot reactions and emits
## `react(pose, line)` for a CharacterView to play. Pure logic — it holds no
## art and does no rendering, so a missing character art set never blocks a
## build and this can be unit-reasoned about on its own.
##
## Reaction table is data-driven (data/character.json). Triggers are either
## a direct event name ("level_started", "power_created", ...) or a derived
## one the raw stream doesn't name:
##   combo_tier_1/2/3  from CASCADE_FINISHED chain_depth (>=2 / >=4 / >=6)
##   fever_started     from FEVER_CHANGED just_activated
##   near_fail         from MOVES_CHANGED moves_left <= NEAR_FAIL_MOVES

signal react(pose: StringName, line: String)

const NEAR_FAIL_MOVES := 3
const _COMBO_TIER_DEPTHS := [2, 4, 6] # parallels board_view's _COMBO_TIERS

var _table: Dictionary = {}
var _debounce := 1.1
var _last_react_ms := 0
var _last_pose_ms: Dictionary = {} # StringName -> int
var _fired_near_fail := false

func _ready() -> void:
	var data := JsonLoader.load_json("res://data/character.json")
	if data.is_empty():
		data = _fallback_table()
	_table = data.get("reactions", {})
	_debounce = float(data.get("debounce_seconds", 1.1))
	# GameEvents is an autoload registered before this one; guard anyway so a
	# reordering or a headless harness that skips it can't crash boot.
	var bus := get_node_or_null("/root/GameEvents")
	if bus != null:
		bus.event.connect(_on_event)

func _on_event(e: EngineEvent) -> void:
	match e.type:
		EngineEvent.LEVEL_STARTED:
			_fired_near_fail = false
			_try("level_started")
		EngineEvent.POWER_CREATED:
			_try("power_created")
		EngineEvent.POWER_ACTIVATED:
			_try("power_activated")
		EngineEvent.BOOSTER_USED:
			_try("booster_used")
		EngineEvent.FEVER_CHANGED:
			if bool(e.data.get("just_activated", false)):
				_try("fever_started")
		EngineEvent.CASCADE_FINISHED:
			var depth := int(e.data.get("chain_depth", 1))
			var tier := 0
			for d in _COMBO_TIER_DEPTHS:
				if depth >= d:
					tier += 1
			if tier > 0:
				_try("combo_tier_%d" % tier)
		EngineEvent.MOVES_CHANGED:
			var left := int(e.data.get("moves_left", 99))
			if left <= NEAR_FAIL_MOVES and not _fired_near_fail:
				_fired_near_fail = true
				_try("near_fail")
			elif left > NEAR_FAIL_MOVES:
				_fired_near_fail = false
		EngineEvent.LEVEL_COMPLETED:
			_try("level_completed", true)
		EngineEvent.LEVEL_FAILED:
			_try("level_failed", true)
		_:
			pass

## `force` bypasses the debounce (level end is always worth a reaction).
func _try(trigger: String, force: bool = false) -> void:
	if not _table.has(trigger):
		return
	var now := Time.get_ticks_msec()
	var entry: Dictionary = _table[trigger]
	var pose := StringName(String(entry.get("pose", "idle")))
	if not force:
		if now - _last_react_ms < int(_debounce * 1000.0):
			return
		var pose_gap := int(entry.get("cooldown", 0)) * 1000
		if pose_gap > 0 and now - int(_last_pose_ms.get(pose, -999999)) < pose_gap:
			return
	_last_react_ms = now
	_last_pose_ms[pose] = now
	react.emit(pose, String(entry.get("line", "")))

func _fallback_table() -> Dictionary:
	return {
		"debounce_seconds": 1.1,
		"reactions": {
			"level_started": {"pose": "wave", "line": "Let's clash!"},
			"combo_tier_1": {"pose": "cheer", "line": "Nice!"},
			"combo_tier_2": {"pose": "hype", "line": "Colour storm!"},
			"combo_tier_3": {"pose": "hype", "line": "Unreal!"},
			"power_created": {"pose": "point", "line": ""},
			"power_activated": {"pose": "cheer", "line": ""},
			"fever_started": {"pose": "power_up", "line": "FEVER!"},
			"near_fail": {"pose": "worried", "line": "Hang on..."},
			"level_completed": {"pose": "victory", "line": "We did it!"},
			"level_failed": {"pose": "sad", "line": "So close!"},
			"booster_used": {"pose": "point", "line": ""},
		},
	}
