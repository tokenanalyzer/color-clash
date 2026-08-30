class_name PieceColorPalette
extends RefCounted
## The full registry of playable piece colors, loaded from data/colors.json.
## Levels reference a subset of these ids; the system is designed so new
## colors can be added to the JSON without touching gameplay code.
## (Named PieceColorPalette, not ColorPalette, to avoid colliding with
## Godot's built-in editor ColorPalette resource type.)

var _by_id: Dictionary = {} # StringName -> ColorDef
var ordered_ids: Array[StringName] = []

static func from_dict(data: Dictionary) -> PieceColorPalette:
	var pal := PieceColorPalette.new()
	for entry in data.get("colors", []):
		var def := ColorDef.from_dict(entry)
		pal._by_id[def.id] = def
		pal.ordered_ids.append(def.id)
	return pal

func get_def(id: StringName) -> ColorDef:
	return _by_id.get(id, null)

func has(id: StringName) -> bool:
	return _by_id.has(id)

func subset(ids: Array) -> Array[StringName]:
	var result: Array[StringName] = []
	for id in ids:
		var sid := StringName(String(id))
		if _by_id.has(sid):
			result.append(sid)
	return result
