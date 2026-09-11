class_name SfxConfig
extends RefCounted
## Registry of SFX definitions loaded from data/sfx.json. Each definition
## is a plain Dictionary consumed by SfxBuilder — this class just owns
## lookup, so sound design changes never touch gameplay or audio-engine code.

var _defs: Dictionary = {} # StringName -> Dictionary

static func from_dict(data: Dictionary) -> SfxConfig:
	var cfg := SfxConfig.new()
	var sfx: Dictionary = data.get("sfx", {})
	for key in sfx.keys():
		cfg._defs[StringName(String(key))] = sfx[key]
	return cfg

func has(id: StringName) -> bool:
	return _defs.has(id)

func get_def(id: StringName) -> Dictionary:
	return _defs.get(id, {})
