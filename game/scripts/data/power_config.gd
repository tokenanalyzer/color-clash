class_name PowerConfig
extends RefCounted
## Data-driven match-size -> power mapping, loaded from data/powers.json.
## Nothing about power thresholds or bonuses is hardcoded in gameplay code;
## change the JSON to rebalance without touching logic.

var thresholds: Array = [] # [{power: StringName, min_size: int}] sorted desc
var definitions: Dictionary = {} # power_id -> Dictionary
var base_points_per_piece: int = 10

static func from_dict(data: Dictionary) -> PowerConfig:
	var cfg := PowerConfig.new()
	for t in data.get("thresholds", []):
		cfg.thresholds.append({"power": StringName(String(t["power"])), "min_size": int(t["min_size"])})
	cfg.thresholds.sort_custom(func(a, b): return a["min_size"] > b["min_size"])
	var defs: Dictionary = data.get("definitions", {})
	for key in defs.keys():
		cfg.definitions[StringName(String(key))] = defs[key]
	cfg.base_points_per_piece = int(data.get("base_points_per_piece", 10))
	return cfg

## Returns the power id created by a connected group of this size, or
## &"none" if the group is too small to earn a power.
func power_for_group_size(size: int) -> StringName:
	for t in thresholds:
		if size >= int(t["min_size"]):
			return t["power"]
	return &"none"

func min_group_size() -> int:
	var m := 999999
	for t in thresholds:
		m = min(m, int(t["min_size"]))
	return m

func get_definition(power_id: StringName) -> Dictionary:
	return definitions.get(power_id, {})
