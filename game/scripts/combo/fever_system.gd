class_name FeverSystem
extends RefCounted
## Builds a Fever meter purely from consecutive strong moves (chain depth).
## When it fills, Fever activates for a configurable number of moves with a
## score multiplier. There is no monetization hook here by design — see
## docs/GAME_DESIGN.md's "Do NOT make monetization required to activate Fever".

var config: FeverConfig
var meter: float = 0.0
var moves_remaining: int = 0

func _init(p_config: FeverConfig) -> void:
	config = p_config

func is_active() -> bool:
	return moves_remaining > 0

func score_multiplier() -> float:
	return config.score_multiplier if is_active() else 1.0

## Call once per resolved move with that move's chain depth. Returns true
## if this call activated Fever.
func register_move(chain_depth: int) -> bool:
	if is_active():
		moves_remaining -= 1
		return false
	if chain_depth >= config.weak_move_chain_threshold:
		var gain: float = float(chain_depth) * config.gain_per_chain_step
		meter += min(gain, config.max_gain_per_move)
	else:
		meter = max(0.0, meter - config.decay_per_weak_move)
	meter = clamp(meter, 0.0, config.meter_max)
	if meter >= config.activation_meter:
		moves_remaining = config.duration_moves
		if config.meter_reset_on_activate:
			meter = 0.0
		return true
	return false

func reset() -> void:
	meter = 0.0
	moves_remaining = 0
