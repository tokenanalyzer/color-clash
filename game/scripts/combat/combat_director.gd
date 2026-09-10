class_name CombatDirector
extends RefCounted
## Bridges the existing connect-clear resolution to character combat for one
## stage. The board and ChainResolver are untouched — app.gd hands each fully
## resolved move here, this turns it into Jamie attack energy + power fires
## and emits signals for the HUD / VFX.
##
## 2026-09-07 gameplay overhaul: the minor-villain HEALTH BAR / boss-HP
## concept is GONE. `is_boss` now only means "chapter-finale stage" (every
## 10th) — it drives the villain-defeat presentation and the boss music mix,
## nothing more. A finale stage is won by completing its objectives, exactly
## like any other stage; there is no HP, no HP victory gate, no boss
## counter-attack. The chapter villain simply stays present for all 10
## stages and is driven off when the 10th is cleared.
##
##   PLAYER CLEARS -> feed_move() -> attack energy -> Jamie attacks / powers
##   fire. Objectives (not HP) decide the win.

## Kept declared for signal-compat with older callers; never emitted now.
signal boss_damaged(amount: int, hp: int, hp_max: int)
signal boss_defeated()
signal boss_attacked()
signal jamie_attack(kind: StringName, damage: int, big: bool)
signal power_fired(power: StringName, combo: StringName)
signal meters_changed(meters: Dictionary)

var level_id: int
## True on every 10th stage — the chapter FINALE. Not a health-bar boss.
var is_boss := false
var boss_id: StringName = &""
var boss_name := ""
var powers := JamiePowers.new()

## `island_index` >= 0 selects the ISLAND-AWARE villain path (the real
## 100-level-per-island progression): a chapter finale / boss presentation
## happens ONLY when `is_finale` is true (the island's last local level).
## `island_index` < 0 keeps the flat 1..50 campaign behaviour (every 10th
## authored stage is a finale) for the direct authored-id callers — the unit
## tests and `_debug_start_authored_level`.
func _init(p_level_id: int, island_index: int = -1, is_finale: bool = false) -> void:
	level_id = p_level_id
	if island_index >= 0:
		var v := EnemyModel.island_villain(island_index, is_finale)
		is_boss = bool(v["is_boss"])
		boss_id = v["id"] if is_boss else &""
	else:
		is_boss = EnemyModel.is_boss_stage(level_id)
		if is_boss:
			boss_id = EnemyModel.boss_for_stage(level_id)
	if is_boss:
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

func _boss_display_name(id: StringName) -> String:
	if id == &"jinn":
		return "JINN"
	return String(EnemyModel.enemy_def(id).get("name", String(id).capitalize())).to_upper()
