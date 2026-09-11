class_name JamiePowers
extends RefCounted
## Jamie's three signature powers from the character reference — Fire Sword,
## Blue Lightning Hand, Lightning Boots — as fill-and-fire energy meters.
## Pure logic + signals so the animation / VFX layer can grow later without
## touching this. Fed one resolved move at a time by CombatDirector.
##
##   fire_sword     fills from gems cleared        (raw match power)
##   lightning_hand fills from power activations    (spell power)
##   lightning_boots fills from cascade depth       (momentum / combos)
##
## A meter that reaches MAX auto-fires and resets; two firing together make a
## combo attack, all three an ULTIMATE.

const FIRE_SWORD: StringName = &"fire_sword"
const LIGHTNING_HAND: StringName = &"lightning_hand"
const LIGHTNING_BOOTS: StringName = &"lightning_boots"
const ORDER: Array[StringName] = [FIRE_SWORD, LIGHTNING_HAND, LIGHTNING_BOOTS]
const MAX := 100.0

var meter := {FIRE_SWORD: 0.0, LIGHTNING_HAND: 0.0, LIGHTNING_BOOTS: 0.0}
## Upgrade level 1..5 (from Inventory) scales fill rate + attack damage.
var level := {FIRE_SWORD: 1, LIGHTNING_HAND: 1, LIGHTNING_BOOTS: 1}

func set_levels(lv: Dictionary) -> void:
	for k in ORDER:
		level[k] = clampi(int(lv.get(k, 1)), 1, 5)

func ratio(power: StringName) -> float:
	return clampf(meter.get(power, 0.0) / MAX, 0.0, 1.0)

## Feed one fully-resolved move. Returns:
##   {fired: Array[StringName], combo: StringName, meters: Dictionary}
func feed(result, chain_depth: int, cleared_count: int) -> Dictionary:
	var lvl_mul := func(p): return 0.85 + 0.15 * float(level[p])
	meter[FIRE_SWORD] += float(cleared_count) * 3.4 * lvl_mul.call(FIRE_SWORD)
	meter[LIGHTNING_HAND] += float(result.powers_activated.size()) * 36.0 * lvl_mul.call(LIGHTNING_HAND)
	meter[LIGHTNING_BOOTS] += float(maxi(chain_depth - 1, 0)) * 24.0 * lvl_mul.call(LIGHTNING_BOOTS)

	var fired: Array[StringName] = []
	for p in ORDER:
		if meter[p] >= MAX:
			fired.append(p)
			meter[p] = 0.0
		else:
			meter[p] = minf(meter[p], MAX)

	var combo: StringName = &""
	if fired.size() >= 3:
		combo = &"ultimate"
	elif fired.size() == 2:
		combo = combo_name(fired[0], fired[1])
	return {"fired": fired, "combo": combo, "meters": meter.duplicate()}

static func combo_name(a: StringName, b: StringName) -> StringName:
	var s := {a: true, b: true}
	if s.has(FIRE_SWORD) and s.has(LIGHTNING_HAND):
		return &"lightning_sword"        # Lightning Sword Strike
	if s.has(FIRE_SWORD) and s.has(LIGHTNING_BOOTS):
		return &"dash_slash"             # High-Speed Dash Slash
	if s.has(LIGHTNING_HAND) and s.has(LIGHTNING_BOOTS):
		return &"lightning_dash"         # Lightning Dash Attack
	return &"combo"

## Damage a fired power / combo adds on top of the base match damage.
func attack_damage(kind: StringName) -> int:
	match kind:
		FIRE_SWORD: return 3 + level[FIRE_SWORD]
		LIGHTNING_HAND: return 3 + level[LIGHTNING_HAND]
		LIGHTNING_BOOTS: return 2 + level[LIGHTNING_BOOTS]
		&"lightning_sword", &"dash_slash", &"lightning_dash": return 10
		&"ultimate": return 22
	return 0

## Human label for a fired attack — for the story/combat feed and SFX id.
static func label(kind: StringName) -> String:
	match kind:
		FIRE_SWORD: return "Fire Sword"
		LIGHTNING_HAND: return "Blue Lightning"
		LIGHTNING_BOOTS: return "Lightning Dash"
		&"lightning_sword": return "Lightning Sword Strike"
		&"dash_slash": return "Dash Slash"
		&"lightning_dash": return "Lightning Dash Attack"
		&"ultimate": return "ULTIMATE"
	return "Strike"
