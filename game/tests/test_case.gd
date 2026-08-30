class_name TestCase
extends RefCounted
## Minimal reflection-based test base class. A subclass defines any number
## of test_*() methods; run() discovers and executes them, collecting
## pass/fail results. No external test framework dependency required.

var results: Array[Dictionary] = []

func run() -> Array[Dictionary]:
	results = []
	for m in get_method_list():
		var method_name: String = m["name"]
		if method_name.begins_with("test_"):
			call(method_name)
	return results

func check(name: String, condition: bool, message: String = "") -> void:
	results.append({"name": name, "pass": condition, "message": message})

func check_eq(name: String, actual, expected) -> void:
	var ok: bool = actual == expected
	check(name, ok, "expected %s got %s" % [str(expected), str(actual)])
