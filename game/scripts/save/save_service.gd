extends Node
## Autoload "SaveService". Local-only JSON save for offline continuity —
## coins, boosters, unlocked levels, settings. This is the single local
## persistence boundary; a future Firebase cloud-save integration
## synchronizes against this same data rather than replacing it (see
## docs/ARCHITECTURE.md's offline-first rule).

const SAVE_PATH := "user://save.json"

var _data: Dictionary = {}

func _ready() -> void:
	load_data()

func load_data() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		var text := f.get_as_text()
		f.close()
		var parsed = JSON.parse_string(text)
		_data = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	else:
		_data = {}

func save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_data))
		f.close()

func get_value(key: String, default_value = null):
	return _data.get(key, default_value)

func set_value(key: String, value) -> void:
	_data[key] = value

func get_int(key: String, default_value: int = 0) -> int:
	return int(_data.get(key, default_value))

func set_int(key: String, value: int) -> void:
	_data[key] = value
