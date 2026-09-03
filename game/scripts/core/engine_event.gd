class_name EngineEvent
extends RefCounted
## One typed gameplay event produced by the game-logic layer and consumed by
## the presentation layers (board view, animation, audio/VFX, character).
##
##     Board / Game Logic
##            v
##     Typed Gameplay Events   <- this class
##            v
##     Game View | Animation | Audio/VFX | Character
##
## Deliberately minimal: a `type` (one of the constants below) and a plain
## `data` Dictionary payload. No behaviour, no engine dependency — it is a
## value object so it stays trivially serialisable, loggable and testable.
## New mechanics add a new constant + payload shape here and one handler in
## each consumer that cares; nothing else changes.

## --- move / input ---------------------------------------------------------
const MOVE_STARTED: StringName = &"move_started"      # {path:Array[Vector2i], kind:String}
const GEM_SELECTED: StringName = &"gem_selected"      # {pos:Vector2i, path_len:int}
const MATCH_FOUND: StringName = &"match_found"        # {size:int, cell_count:int, color:StringName}
const GEM_REMOVED: StringName = &"gem_removed"        # {count:int, wave:int}

## --- powers -------------------------------------------------------------
const POWER_CREATED: StringName = &"power_created"    # {power_id:StringName, pos:Vector2i, formed:bool}
const POWER_ACTIVATED: StringName = &"power_activated" # {power_id:StringName, pos:Vector2i, wave:int, bonus:int}

## --- cascade ----------------------------------------------------------
const CASCADE_STARTED: StringName = &"cascade_started"   # {}
const CASCADE_STEP: StringName = &"cascade_step"         # {wave:int, cell_count:int, power_bonus:int}
const CASCADE_FINISHED: StringName = &"cascade_finished" # {chain_depth:int, powers_formed:bool, secondary_triggers:int, total_cleared:int}

## --- obstacles ------------------------------------------------------
const OBSTACLE_DAMAGED: StringName = &"obstacle_damaged"  # {obstacle_id:StringName, pos:Vector2i, hp:int}  (reserved — see MoveEventTranslator)
const OBSTACLE_CLEARED: StringName = &"obstacle_cleared"  # {obstacle_id:StringName, pos:Vector2i}
const GEM_FROZEN: StringName = &"gem_frozen"              # {pos:Vector2i}
const TIMEBOMB_EXPLODED: StringName = &"timebomb_exploded" # {pos:Vector2i, move_penalty:int}

## --- board mutation ------------------------------------------------
const GRAVITY_APPLIED: StringName = &"gravity_applied"   # {count:int}
const BOARD_REFILLED: StringName = &"board_refilled"     # {count:int}
const BOARD_SHUFFLED: StringName = &"board_shuffled"     # {}

## --- session / meta ---------------------------------------------------
const OBJECTIVE_PROGRESS: StringName = &"objective_progress" # {index:int, value:int, target:int, type:String, complete:bool}
const SCORE_CHANGED: StringName = &"score_changed"       # {score:int, gained:int}
const COMBO_CHANGED: StringName = &"combo_changed"       # {combo:int, best:int}
const FEVER_CHANGED: StringName = &"fever_changed"       # {meter:float, meter_max:float, active:bool, just_activated:bool}
const MOVES_CHANGED: StringName = &"moves_changed"       # {moves_left:int, move_limit:int}
const BOOSTER_USED: StringName = &"booster_used"         # {booster_id:StringName, targeted:bool}
const LEVEL_STARTED: StringName = &"level_started"       # {level_id:int, name:String}
const LEVEL_COMPLETED: StringName = &"level_completed"   # {level_id:int, score:int, stars:int}
const LEVEL_FAILED: StringName = &"level_failed"         # {level_id:int, score:int}

var type: StringName
var data: Dictionary

func _init(p_type: StringName, p_data: Dictionary = {}) -> void:
	type = p_type
	data = p_data

## Deterministic factory — identical inputs always give an equivalent event.
static func make(p_type: StringName, p_data: Dictionary = {}) -> EngineEvent:
	return EngineEvent.new(p_type, p_data)

func get_value(key: String, default_value = null) -> Variant:
	return data.get(key, default_value)

func _to_string() -> String:
	return "EngineEvent(%s, %s)" % [type, data]
