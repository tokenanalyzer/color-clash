class_name MusicConfig
extends RefCounted
## Adaptive music tuning loaded from data/music.json: tempo/scale, each
## loop layer's pattern, and the per-intensity-state layer gain mix.

var bpm: float = 100.0
var bars: int = 4
var beats_per_bar: int = 4
var root_freq: float = 220.0
var layers: Dictionary = {} # String -> Dictionary
var states: Dictionary = {} # String -> Dictionary(layer_id -> float gain)
var crossfade_seconds: float = 1.0

static func from_dict(data: Dictionary) -> MusicConfig:
	var cfg := MusicConfig.new()
	cfg.bpm = float(data.get("bpm", 100.0))
	cfg.bars = int(data.get("bars", 4))
	cfg.beats_per_bar = int(data.get("beats_per_bar", 4))
	cfg.root_freq = float(data.get("root_freq", 220.0))
	cfg.layers = data.get("layers", {})
	cfg.states = data.get("states", {})
	cfg.crossfade_seconds = float(data.get("crossfade_seconds", 1.0))
	return cfg

func loop_beats() -> float:
	return float(bars * beats_per_bar)

func loop_seconds() -> float:
	return loop_beats() * 60.0 / bpm
