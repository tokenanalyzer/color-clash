class_name FeverConfig
extends RefCounted
## Data-driven Fever tuning, loaded from data/fever.json. Fever is earned
## purely from skilled play (consecutive strong chains); nothing here can
## be purchased.

var meter_max: float = 100.0
var gain_per_chain_step: float = 16.0
var decay_per_weak_move: float = 6.0
var weak_move_chain_threshold: int = 2
var activation_meter: float = 100.0
var duration_moves: int = 6
var score_multiplier: float = 1.5
var meter_reset_on_activate: bool = true

static func from_dict(d: Dictionary) -> FeverConfig:
	var c := FeverConfig.new()
	c.meter_max = float(d.get("meter_max", 100.0))
	c.gain_per_chain_step = float(d.get("gain_per_chain_step", 16.0))
	c.decay_per_weak_move = float(d.get("decay_per_weak_move", 6.0))
	c.weak_move_chain_threshold = int(d.get("weak_move_chain_threshold", 2))
	c.activation_meter = float(d.get("activation_meter", 100.0))
	c.duration_moves = int(d.get("duration_moves", 6))
	c.score_multiplier = float(d.get("score_multiplier", 1.5))
	c.meter_reset_on_activate = bool(d.get("meter_reset_on_activate", true))
	return c
