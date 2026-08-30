extends Node
## Autoload "Boosters". Pre-level booster inventory (Bomb, Lightning,
## Rainbow, Shuffle, Extra Moves — see data/boosters.json). Purchases spend
## soft currency only through EconomyService; nothing here can grant
## premium currency (see docs/SECURITY.md).

signal inventory_changed(booster_id: StringName, count: int)

var counts: Dictionary = {} # StringName -> int

func _ready() -> void:
	var saved: Dictionary = SaveService.get_value("boosters", {})
	for id in GameData.boosters.keys():
		counts[id] = int(saved.get(String(id), 0))

func get_count(id: StringName) -> int:
	return int(counts.get(id, 0))

func add(id: StringName, amount: int = 1) -> void:
	counts[id] = get_count(id) + amount
	_persist()
	inventory_changed.emit(id, counts[id])

func use(id: StringName) -> bool:
	if get_count(id) <= 0:
		return false
	counts[id] -= 1
	_persist()
	inventory_changed.emit(id, counts[id])
	return true

## Buys one usable charge of `id` with soft currency, per data/boosters.json's
## cost. Note: `value` in that JSON is the *effect magnitude* consumed at
## use time (e.g. Extra Moves grants +5 moves per charge), not the charge
## count — a purchase always grants exactly one charge.
func purchase(id: StringName) -> bool:
	var def: Dictionary = GameData.boosters.get(id, {})
	if def.is_empty():
		return false
	var cost := int(def.get("cost", 0))
	if not Economy.spend(cost):
		return false
	add(id, 1)
	return true

func _persist() -> void:
	var out := {}
	for id in counts.keys():
		out[String(id)] = counts[id]
	SaveService.set_value("boosters", out)
	SaveService.save()
