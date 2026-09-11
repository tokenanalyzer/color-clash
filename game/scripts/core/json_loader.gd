class_name JsonLoader
extends RefCounted
## Tiny helper for reading a res:// JSON file into a Dictionary. Centralized
## so every data-driven config file is loaded and error-reported the same way.

static func load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("JsonLoader: missing file %s" % path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("JsonLoader: cannot open %s" % path)
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("JsonLoader: %s did not parse to a Dictionary" % path)
		return {}
	return parsed
