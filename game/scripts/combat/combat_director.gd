class_name CombatDirector
extends RefCounted
## Bridges the existing match-3 resolution to character combat for one stage.
## The board and ChainResolver are untouched — app.gd hands each fully
## resolved move here, this turns it into Jamie attack energy + boss damage
## and emits signals for the HUD / VFX. Boss stages (every 10th) carry an
## enemy with HP from EnemyModel; clearing it to 0 wins the stage.
##
##   PLAYER MATCHES -> feed_move() -> attack energy -> Jamie attacks ->
##   boss HP down -> ... -> boss_defeated -> stage won.

signal boss_damaged(amount: int, hp: int, hp_max: int)
signal boss_defeated()
signal boss_attacked()                       # near-fail flavour hit
signal jamie_attack(kind: StringName, damage: int, big: bool)
signal power_fired(power: StringName, combo: StringName)
signal meters_changed(meters: Dictionary)

var level_id: int
var is_boss := false
var boss_id: StringName = &""
var boss_name := ""
var boss_hp := 0
var boss_hp_max := 0
var powers := JamiePowers.new()
var _spent_boss_attack := false

func _init(p_level_id: int) -> void:
	level_id = p_level_id
	is_boss = EnemyModel.is_boss_stage(level_id)
	if is_boss:
		boss_id = EnemyModel.boss_for_stage(level_id)
		boss_hp_max = EnemyModel.boss_hp(level_id)
		boss_hp = boss_hp_max
		boss_name = _boss_display_name(boss_id)
	var inv: Node = Engine.get_main_loop().root.get_node_or_null("Inventory")
	powers.set_levels(inv.power_levels() if inv != null else {})

func is_final_boss() -> bool:
	return boss_id == &"jinn"

func boss_face() -> Texture2D:
	if boss_id == &"jinn":
		return Cast.portrait(Cast.WHO_JINN)
	return EnemyModel.enemy_face(boss_id)

## One fully-resolved player move. `counts_as_move` is false for booster
## detonations (they still build energy, just less).
func feed_move(result, chain_depth: int, cleared_count: int, counts_as_move: bool, moves_left: int) -> void:
	var scale := 1.0 if counts_as_move else 0.6
	var ev: Dictionary = powers.feed(result, chain_depth, int(round(cleared_count * scale)))
	meters_changed.emit(ev["meters"])

	# base attack: match size + cascade depth
	var dmg := 1 + int(round(float(cleared_count) / 4.0)) + maxi(chain_depth - 1, 0)
	var kind: StringName = &"basic"
	var big := false
	for p in ev["fired"]:
		dmg += powers.attack_damage(p)
		kind = p
	if String(ev["combo"]) != "":
		dmg += powers.attack_damage(ev["combo"])
		kind = ev["combo"]
		big = true
		power_fired.emit(kind, ev["combo"])
	elif not (ev["fired"] as Array).is_empty():
		power_fired.emit(kind, &"")

	jamie_attack.emit(kind, dmg, big)

	if is_boss and boss_hp > 0:
		boss_hp = maxi(boss_hp - dmg, 0)
		boss_damaged.emit(dmg, boss_hp, boss_hp_max)
		if boss_hp == 0:
			boss_defeated.emit()
		elif counts_as_move and moves_left <= 3 and not _spent_boss_attack:
			_spent_boss_attack = true
			boss_attacked.emit()

func _boss_display_name(id: StringName) -> String:
	if id == &"jinn":
		return "JINN"
	return String(EnemyModel.enemy_def(id).get("name", String(id).capitalize())).to_upper()
