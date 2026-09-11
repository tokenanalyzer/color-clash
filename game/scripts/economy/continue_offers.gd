class_name ContinueOffers
extends RefCounted
## The in-level "Need More Moves?" continue options, loaded from
## data/economy.json (`extra_moves`). Pure logic — spends the existing coin
## Economy through SaveService, adds NO save state and NO second currency.
## The UI (extra_moves_prompt.gd) and app.gd both go through this so the
## price rules live in exactly one place.
##
##   tiers()        -> [{id, moves, cost, label}, ...] in ascending order
##   tier(id)       -> one tier dict (or {})
##   can_afford(id) -> bool  (against the live Economy balance)
##   purchase(id)   -> int   (moves granted; 0 if unknown id or not affordable)

var _tiers: Array[Dictionary] = []

static func from_dict(d: Dictionary) -> ContinueOffers:
	var co := ContinueOffers.new()
	for entry in d.get("extra_moves", []):
		co._tiers.append({
			"id": StringName(String(entry.get("id", ""))),
			"moves": int(entry.get("moves", 0)),
			"cost": int(entry.get("cost", 0)),
			"label": String(entry.get("label", "+%d Moves" % int(entry.get("moves", 0)))),
		})
	co._tiers.sort_custom(func(a, b): return int(a["moves"]) < int(b["moves"]))
	return co

func tiers() -> Array[Dictionary]:
	return _tiers

func tier(id: StringName) -> Dictionary:
	for t in _tiers:
		if t["id"] == id:
			return t
	return {}

func cost_of(id: StringName) -> int:
	var t := tier(id)
	return int(t.get("cost", -1)) if not t.is_empty() else -1

func moves_of(id: StringName) -> int:
	var t := tier(id)
	return int(t.get("moves", 0))

func can_afford(id: StringName) -> bool:
	var t := tier(id)
	if t.is_empty():
		return false
	return Economy.can_afford(int(t["cost"]))

## Spends coins for tier `id` and returns how many moves to add to the
## running level. Returns 0 (and spends nothing) on an unknown id or when
## the player cannot afford it — the caller then keeps the level unchanged.
func purchase(id: StringName) -> int:
	var t := tier(id)
	if t.is_empty():
		return 0
	if not Economy.spend(int(t["cost"])):
		return 0
	return int(t["moves"])
