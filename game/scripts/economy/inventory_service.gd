extends Node
## Autoload "Inventory". Jamie's power upgrade levels + owned/equipped
## equipment + collectibles for War of Love. Persists through the existing
## SaveService and spends the existing soft currency (Economy). NO second
## save or currency system — boosters still live in the Boosters autoload,
## coins in Economy, campaign progress in Progress.

signal changed()

const KEY_POWERS := "inv_power_levels"       # {fire_sword:int, ...}
const KEY_OWNED := "inv_owned_equipment"     # [id, ...]
const KEY_EQUIPPED := "inv_equipped"         # {slot: id}
const KEY_ITEMS := "inv_collectibles"        # {id: count}

const POWER_IDS: Array[StringName] = [&"fire_sword", &"lightning_hand", &"lightning_boots"]
const MAX_POWER_LEVEL := 5

var _cfg: Dictionary = {}
var _levels: Dictionary = {}
var _owned: Dictionary = {}      # id -> true
var _equipped: Dictionary = {}   # slot -> id
var _items: Dictionary = {}

func _ready() -> void:
	_cfg = JsonLoader.load_json("res://data/inventory.json")
	var saved_lv: Dictionary = SaveService.get_value(KEY_POWERS, {})
	for p in POWER_IDS:
		_levels[p] = clampi(int(saved_lv.get(String(p), 1)), 1, MAX_POWER_LEVEL)
	for id in SaveService.get_value(KEY_OWNED, []):
		_owned[String(id)] = true
	_equipped = SaveService.get_value(KEY_EQUIPPED, {})
	_items = SaveService.get_value(KEY_ITEMS, {})
	# grant + auto-equip starter gear the first time
	for e in _cfg.get("equipment", []):
		if bool(e.get("starter", false)) and not _owned.has(String(e["id"])):
			_owned[String(e["id"])] = true
			if not _equipped.has(String(e["slot"])):
				_equipped[String(e["slot"])] = String(e["id"])
	_persist()

# --------------------------------------------------------------- powers --

func power_levels() -> Dictionary:
	var out := {}
	for p in POWER_IDS:
		out[p] = int(_levels.get(p, 1))
	return out

func power_level(id: StringName) -> int:
	return int(_levels.get(id, 1))

func power_upgrade_cost(id: StringName) -> int:
	var lv := power_level(id)
	if lv >= MAX_POWER_LEVEL:
		return -1
	var costs: Array = _cfg.get("power_upgrade_cost", [150, 350, 700, 1400])
	return int(costs[mini(lv - 1, costs.size() - 1)])

func can_upgrade_power(id: StringName) -> bool:
	var c := power_upgrade_cost(id)
	return c > 0 and Economy.can_afford(c)

func upgrade_power(id: StringName) -> bool:
	var c := power_upgrade_cost(id)
	if c <= 0 or not Economy.spend(c):
		return false
	_levels[id] = mini(power_level(id) + 1, MAX_POWER_LEVEL)
	_persist()
	changed.emit()
	return true

# ------------------------------------------------------------ equipment --

func all_equipment() -> Array:
	return _cfg.get("equipment", [])

func equipment_def(id: StringName) -> Dictionary:
	for e in all_equipment():
		if String(e["id"]) == String(id):
			return e
	return {}

func is_owned(id: StringName) -> bool:
	return _owned.has(String(id))

func grant_equipment(id: StringName) -> void:
	if String(id) == "" or _owned.has(String(id)):
		return
	_owned[String(id)] = true
	var slot := String(equipment_def(id).get("slot", ""))
	if slot != "" and not _equipped.has(slot):
		_equipped[slot] = String(id)
	_persist()
	changed.emit()

func equipped_in(slot: StringName) -> StringName:
	return StringName(String(_equipped.get(String(slot), "")))

func equip(id: StringName) -> void:
	if not is_owned(id):
		return
	var slot := String(equipment_def(id).get("slot", ""))
	if slot == "":
		return
	_equipped[slot] = String(id)
	_persist()
	changed.emit()

# ---------------------------------------------------------- collectibles --

func collectibles() -> Dictionary:
	return _items.duplicate()

func add_collectible(id: StringName, n: int = 1) -> void:
	_items[String(id)] = int(_items.get(String(id), 0)) + n
	_persist()
	changed.emit()

# --------------------------------------------------- boss reward hook --

## Called by app.gd after a boss stage is cleared. Grants that boss's
## equipment drop (if any) + a collectible shard. Coins/boosters are still
## handled by the existing milestone-chest / level-reward path. Returns the
## display name of newly-granted equipment (empty if none/already owned) so
## the caller can show a "NEW EQUIPMENT" toast.
func grant_boss_reward(level_id: int) -> String:
	var granted_name := ""
	for e in all_equipment():
		if int(e.get("reward_stage", -1)) == level_id:
			var id := StringName(String(e["id"]))
			if not is_owned(id):
				granted_name = String(e.get("name", String(id)))
			grant_equipment(id)
	add_collectible(&"kingdom_shard", 1)
	return granted_name

func _persist() -> void:
	var lv := {}
	for p in POWER_IDS:
		lv[String(p)] = int(_levels.get(p, 1))
	SaveService.set_value(KEY_POWERS, lv)
	SaveService.set_value(KEY_OWNED, _owned.keys())
	SaveService.set_value(KEY_EQUIPPED, _equipped)
	SaveService.set_value(KEY_ITEMS, _items)
	SaveService.save()
