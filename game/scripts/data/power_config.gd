class_name PowerConfig
extends RefCounted
## Data-driven match-size -> power mapping, loaded from data/powers.json.
## Nothing about power thresholds or bonuses is hardcoded in gameplay code;
## change the JSON to rebalance without touching logic.
##
## A threshold's `count` (default 1) is how many power tiles a group of
## that size creates — a big enough connection legitimately earns more
## than one power (see docs/GAME_DESIGN.md's "Deeper chain reactions").

var thresholds: Array = [] # [{power: StringName, min_size: int, count: int}] sorted desc
var definitions: Dictionary = {} # power_id -> Dictionary
var base_points_per_piece: int = 10

static func from_dict(data: Dictionary) -> PowerConfig:
	var cfg := PowerConfig.new()
	for t in data.get("thresholds", []):
		cfg.thresholds.append({
			"power": StringName(String(t["power"])),
			"min_size": int(t["min_size"]),
			"count": int(t.get("count", 1)),
		})
	cfg.thresholds.sort_custom(func(a, b): return a["min_size"] > b["min_size"])
	var defs: Dictionary = data.get("definitions", {})
	for key in defs.keys():
		cfg.definitions[StringName(String(key))] = defs[key]
	cfg.base_points_per_piece = int(data.get("base_points_per_piece", 10))
	return cfg

## Returns the list of power ids a connected group of this size creates
## (possibly more than one for a very large group, possibly empty for a
## too-small group). Order is stable so callers can place them in order
## along a path/group.
func powers_for_group_size(size: int) -> Array[StringName]:
	for t in thresholds:
		if size >= int(t["min_size"]):
			var power: StringName = t["power"]
			var out: Array[StringName] = []
			if power == &"none":
				return out
			var count: int = max(int(t["count"]), 0)
			for i in count:
				out.append(power)
			return out
	return []

## Convenience for callers that only care about a single power (or none).
func power_for_group_size(size: int) -> StringName:
	var powers := powers_for_group_size(size)
	return powers[0] if not powers.is_empty() else &"none"

func min_group_size() -> int:
	var m := 999999
	for t in thresholds:
		m = min(m, int(t["min_size"]))
	return m

func get_definition(power_id: StringName) -> Dictionary:
	return definitions.get(power_id, {})
